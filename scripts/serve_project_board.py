"""Serve the read-only local MxAgile project board on loopback."""

from __future__ import annotations

import argparse
import hashlib
import json
import mimetypes
import os
import re
import subprocess
import sys
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path, PurePosixPath
from urllib.parse import parse_qs, unquote, urlsplit

import yaml

from build_project_status import ProjectUiConfigError, build_status, build_status_summary, resolve_project_ui_settings
from project_compatibility import is_standalone_interaction_artifact, safe_file
from reconcile_external_changes import build_report

MAX_SOURCE_BYTES = 32 * 1024 * 1024
UI_FILES = {"/": "index.html", "/index.html": "index.html", "/styles.css": "styles.css", "/board.js": "board.js"}
STATUS_FILES = (
    "mxagile-project.yaml", ".mxagile/config.yaml", ".mxagile/version.yaml",
    "planning/lifecycle/process-state.yaml", "planning/lifecycle/context-epoch.yaml",
    "planning/mission/mission-state.yaml",
)
STATUS_ROOTS = (
    "requirements", "specs", "scripts", "planning", "input-resources/ui-ux", "mprcontents",
    ".mxagile/schemas", ".mxagile/tools", ".mxagile/state",
)
SKIP_STATUS_DIRS = {".git", ".concord", ".mxcli", "__pycache__", "node_modules", "deployment"}
PREVIEW_EXTENSIONS = {".html", ".htm", ".css", ".js", ".mjs", ".json", ".svg", ".png", ".jpg", ".jpeg", ".webp", ".gif", ".ico", ".woff", ".woff2", ".ttf"}


def _metadata_record(root: Path, path: Path) -> tuple | None:
    relative = path.relative_to(root).as_posix()
    try:
        stat_result = path.lstat()
    except FileNotFoundError:
        return (relative, "MISSING")
    required = ("st_dev", "st_ino", "st_size", "st_mtime_ns", "st_ctime_ns", "st_mode")
    if any(not hasattr(stat_result, name) for name in required) or not stat_result.st_ino:
        return None
    entry = (
        relative, stat_result.st_dev, stat_result.st_ino, stat_result.st_mode,
        stat_result.st_size, stat_result.st_mtime_ns, stat_result.st_ctime_ns,
        getattr(stat_result, "st_birthtime_ns", None), getattr(stat_result, "st_file_attributes", None),
    )
    if os.name == "nt":
        change_time = _windows_change_time(path)
        if change_time is None:
            return None
        entry += (change_time,)
    if path.is_symlink():
        try:
            return entry + ("SYMLINK", os.readlink(path))
        except OSError:
            return None
    return entry


def _windows_change_time(path: Path) -> int | None:
    if os.name != "nt":
        return None
    import ctypes
    from ctypes import wintypes

    class FileBasicInfo(ctypes.Structure):
        _fields_ = [
            ("CreationTime", ctypes.c_longlong),
            ("LastAccessTime", ctypes.c_longlong),
            ("LastWriteTime", ctypes.c_longlong),
            ("ChangeTime", ctypes.c_longlong),
            ("FileAttributes", wintypes.DWORD),
        ]

    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    create_file = kernel.CreateFileW
    create_file.argtypes = [wintypes.LPCWSTR, wintypes.DWORD, wintypes.DWORD, wintypes.LPVOID, wintypes.DWORD, wintypes.DWORD, wintypes.HANDLE]
    create_file.restype = wintypes.HANDLE
    get_info = kernel.GetFileInformationByHandleEx
    get_info.argtypes = [wintypes.HANDLE, ctypes.c_int, wintypes.LPVOID, wintypes.DWORD]
    get_info.restype = wintypes.BOOL
    close_handle = kernel.CloseHandle
    close_handle.argtypes = [wintypes.HANDLE]
    flags = 0x02000000 | (0x00200000 if path.is_symlink() else 0)
    handle = create_file(str(path), 0x80, 0x1 | 0x2 | 0x4, None, 3, flags, None)
    if handle == wintypes.HANDLE(-1).value:
        return None
    try:
        info = FileBasicInfo()
        if not get_info(handle, 0, ctypes.byref(info), ctypes.sizeof(info)):
            return None
        return int(info.ChangeTime)
    finally:
        close_handle(handle)


def git_head_and_branch(project_root: Path) -> tuple[str | None, str | None]:
    """Cheap observed HEAD and branch (one git process); never a reconciliation claim."""
    try:
        result = subprocess.run(
            ["git", "--no-optional-locks", "-C", str(project_root), "rev-parse", "HEAD",
             "--symbolic-full-name", "HEAD"],
            capture_output=True,
            check=False,
            timeout=10,
        )
    except (OSError, subprocess.SubprocessError):
        return None, None
    if result.returncode:
        return None, None
    lines = result.stdout.decode("utf-8", errors="replace").split()
    head = lines[0] if lines and re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", lines[0]) else None
    branch = lines[1] if len(lines) > 1 and lines[1].startswith("refs/heads/") else None
    return head, branch


def select_latest_run(runs: list[dict]) -> dict | None:
    """Single latest-run rule: current runs win over historical ones; newest capture wins."""
    current = [run for run in runs if not run.get("historical")]
    candidates = current or runs
    if not candidates:
        return None
    return max(
        candidates,
        key=lambda run: (
            max((capture.get("captured_at") or "" for capture in run.get("captures", [])), default=""),
            str(run.get("entry_id") or ""),
            str(run.get("run_id") or ""),
        ),
    )


def run_key(run: dict) -> dict:
    return {"entry_id": run.get("entry_id"), "run_id": run.get("run_id"), "manifest_path": run.get("manifest_path")}


def _emit_board_timing(event: str, **fields: object) -> None:
    if os.environ.get("MXAGILE_BOARD_PROFILE") != "1":
        return
    payload = {"event": event, **fields}
    sys.stderr.write("BOARD_TIMING " + json.dumps(payload, ensure_ascii=True, sort_keys=True) + "\n")


VALIDATION_WINDOW_SECONDS = 5.0
BACKGROUND_REFRESH_SECONDS = 2.0
SOURCE_CHURN_BACKOFF_SECONDS = (0.5, 1.0, 2.0)
LAST_GOOD_FORMAT = 1
MODEL_ROOT = "mprcontents"


def legacy_cache_mode() -> bool:
    """One-release rollback switch to the pre-CS-2 per-request full signature behaviour."""
    return os.environ.get("MXAGILE_BOARD_LEGACY_CACHE") == "1"


def board_cache_dir(project_root: Path) -> Path | None:
    """Disposable projection cache location; never inside the project tree."""
    override = os.environ.get("MXAGILE_BOARD_CACHE_DIR")
    if override:
        base = Path(override)
    elif os.name == "nt":
        base = Path(os.environ.get("LOCALAPPDATA") or (Path.home() / "AppData/Local")) / "mxagile" / "board-cache"
    else:
        base = Path(os.environ.get("XDG_CACHE_HOME") or (Path.home() / ".cache")) / "mxagile" / "board-cache"
    root = project_root.resolve()
    try:
        base.resolve().relative_to(root)
        return None  # a cache inside the project would violate the read-only contract
    except (OSError, ValueError):
        pass
    identity = str(root).casefold() if os.name == "nt" else str(root)
    _, branch = git_head_and_branch(root)
    project_key = hashlib.sha256(identity.encode("utf-8")).hexdigest()[:32]
    branch_key = hashlib.sha256((branch or "NO_BRANCH").encode("utf-8")).hexdigest()[:16]
    return base / project_key / branch_key


def source_metadata_signature(project_root: Path) -> str | None:
    started = time.perf_counter()
    result = _source_metadata_signature(project_root, include_model_walk=legacy_cache_mode())
    _emit_board_timing("source_signature", seconds=round(time.perf_counter() - started, 4), available=result is not None)
    return result


def _source_metadata_signature(project_root: Path, *, include_model_walk: bool = False) -> str | None:
    """Cheap invalidation hint; metadata is never emitted as project authority.

    In a Git work tree the Mendix model folder is covered by `git status --untracked-files=all`
    plus HEAD, so it is not walked file by file (2k+ files in real projects). Without Git, or in
    legacy mode, the full walk is kept.
    """
    root = project_root.resolve()
    records: dict[str, tuple] = {}
    try:
        root_record = _metadata_record(root, root)
        if root_record is None:
            return None
        records["."] = root_record

        in_git = False
        revision = subprocess.run(
            ["git", "--no-optional-locks", "-C", str(root), "rev-parse", "HEAD", "--symbolic-full-name", "HEAD",
             "--git-path", "index"],
            capture_output=True,
            check=False,
        )
        if revision.returncode == 0:
            lines = revision.stdout.decode("utf-8", errors="replace").splitlines()
            if len(lines) < 3:
                return None
            head = lines[0].strip()
            branch_ref = lines[1].strip() if lines[1].strip() != "HEAD" else "DETACHED"
            index_path = Path(lines[2].strip())
            if not index_path.is_absolute():
                index_path = root / index_path
            index_record = _metadata_record(root, index_path) if index_path.exists() else (index_path.as_posix(), "MISSING")
            if index_record is None:
                return None
            git_status = subprocess.run(
                ["git", "--no-optional-locks", "-C", str(root), "status", "--porcelain=v1", "-z", "--untracked-files=all"],
                capture_output=True,
                check=False,
            )
            if git_status.returncode:
                return None
            records["!git"] = (head, branch_ref, index_record, hashlib.sha256(git_status.stdout).hexdigest())
            in_git = True
        elif (root / ".git").exists():
            return None
        else:
            records["!git"] = ("NO_GIT",)

        for mpr_path in sorted(root.glob("*.mpr")):
            record = _metadata_record(root, mpr_path)
            if record is None:
                return None
            records[mpr_path.relative_to(root).as_posix()] = record
        for relative in STATUS_FILES:
            path = root / relative
            record = _metadata_record(root, path)
            if record is None:
                return None
            records[relative] = record

        for relative in STATUS_ROOTS:
            base = root / relative
            base_record = _metadata_record(root, base)
            if base_record is None:
                return None
            records[relative] = base_record
            if not base.is_dir() or base.is_symlink():
                continue
            if relative == MODEL_ROOT and in_git and not include_model_walk:
                continue

            def onerror(error: OSError) -> None:
                raise error

            for directory, dirnames, filenames in os.walk(base, topdown=True, followlinks=False, onerror=onerror):
                current = Path(directory)
                current_record = _metadata_record(root, current)
                if current_record is None:
                    return None
                records[current.relative_to(root).as_posix()] = current_record
                retained = []
                for name in sorted(dirnames):
                    child = current / name
                    if name in SKIP_STATUS_DIRS:
                        continue
                    child_record = _metadata_record(root, child)
                    if child_record is None:
                        return None
                    records[child.relative_to(root).as_posix()] = child_record
                    if not child.is_symlink():
                        retained.append(name)
                dirnames[:] = retained
                for name in sorted(filenames):
                    child = current / name
                    child_record = _metadata_record(root, child)
                    if child_record is None:
                        return None
                    records[child.relative_to(root).as_posix()] = child_record
    except (OSError, UnicodeError, ValueError, subprocess.SubprocessError):
        return None
    payload = json.dumps([records[key] for key in sorted(records)], ensure_ascii=False, separators=(",", ":"))
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def _atomic_write_json(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    handle = tempfile.NamedTemporaryFile(
        mode="w", encoding="utf-8", newline="\n", dir=path.parent, prefix=f".{path.name}.", suffix=".tmp", delete=False,
    )
    temporary = Path(handle.name)
    try:
        with handle:
            json.dump(value, handle, ensure_ascii=False, sort_keys=True)
        os.replace(temporary, path)
    finally:
        if temporary.exists():
            temporary.unlink()


class ProjectStatusCache:
    """Disposable, reconstructable projection cache.

    Direct callers get strictly validated results (signature check per call). Server requests use
    a bounded validation window (`request_window`): a snapshot validated within the window is
    served without re-scanning, and while a rebuild is running the last projection is served
    with an explicit STALE/BUILDING projection state instead of blocking or failing.
    """

    def __init__(self, project_root: Path, *, persist: bool = False, cache_dir: Path | None = None):
        self.project_root = project_root.resolve()
        self._condition = threading.Condition()
        self._building = False
        self._reconciliation_building = False
        self._signature: str | None = None
        self._status: dict | None = None
        self._full_status: dict | None = None
        self._gallery_cache: dict[str, dict] = {}
        self._gallery_building: set[str] = set()
        self._failure_generation = 0
        self._last_failure: Exception | None = None
        self.build_count = 0
        self.request_window = 0.0
        self._validated_at: float | None = None
        self._built_at: float | None = None
        self._built_wall: float | None = None
        self._built_head: str | None = None
        self._stale_reason: str | None = None
        self.persist = persist and not legacy_cache_mode()
        self.cache_dir = cache_dir if cache_dir is not None else None
        self._cache_dir_resolved = cache_dir is not None
        self._last_good_checked = False
        self._background_build: threading.Thread | None = None

    # -- projection state -------------------------------------------------
    def _last_good_path(self) -> Path | None:
        if not self.persist:
            return None
        if not self._cache_dir_resolved:
            self.cache_dir = board_cache_dir(self.project_root)
            self._cache_dir_resolved = True
        return self.cache_dir / "last-good-summary.json" if self.cache_dir is not None else None

    def projection_info(self) -> dict:
        with self._condition:
            now = time.monotonic()
            if self._status is None:
                state = "PROJECTION_ERROR" if self._last_failure is not None and not self._building else "BUILDING"
            elif self._stale_reason is not None:
                state = "STALE"
            else:
                state = "FRESH"
            if self._built_at is not None:
                age = round(now - self._built_at, 3)
            elif self._built_wall is not None:
                age = round(max(0.0, time.time() - self._built_wall), 3)
            else:
                age = None
            return {
                "state": state,
                "age_seconds": age,
                "validated_age_seconds": round(now - self._validated_at, 3) if self._validated_at is not None else None,
                "reason": self._stale_reason,
                "built_at_head": self._built_head,
                "rebuilding": self._building,
            }

    def _load_last_good_locked(self) -> dict | None:
        if self._last_good_checked:
            return None
        self._last_good_checked = True
        path = self._last_good_path()
        if path is None or not path.is_file():
            return None
        try:
            stored = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return None
        status = stored.get("status") if isinstance(stored, dict) else None
        if (
            stored.get("format") != LAST_GOOD_FORMAT
            or stored.get("project_root") != str(self.project_root)
            or not isinstance(status, dict)
            or status.get("schema_version") != 2
        ):
            return None
        self._status = status
        self._signature = None  # never trusted as current: the next validation rebuilds
        self._stale_reason = "STARTUP_LAST_GOOD"
        self._built_wall = stored.get("built_wall") if isinstance(stored.get("built_wall"), (int, float)) else None
        self._built_head = stored.get("head") if isinstance(stored.get("head"), str) else None
        self._built_at = None
        self._validated_at = None
        return status

    def _persist_last_good(self, status: dict, signature: str) -> None:
        path = self._last_good_path()
        if path is None:
            return
        try:
            _atomic_write_json(path, {
                "format": LAST_GOOD_FORMAT, "project_root": str(self.project_root), "signature": signature,
                "built_wall": self._built_wall, "head": self._built_head, "status": status,
            })
        except OSError:
            # A failed cache write never degrades the fresh in-memory projection.
            _emit_board_timing("last_good_write_failed")

    def _start_background_build_locked(self) -> None:
        if self._building or (self._background_build is not None and self._background_build.is_alive()):
            return

        def rebuild() -> None:
            try:
                self._get_summary_validated()
            except Exception as exc:  # visible through projection_info / next request
                _emit_board_timing("background_build_failed", reason=type(exc).__name__)

        self._background_build = threading.Thread(target=rebuild, name="mxagile-board-rebuild", daemon=True)
        self._background_build.start()

    # -- summary ------------------------------------------------------------
    def get_summary(self, *, max_validation_age: float | None = None) -> dict:
        window = self.request_window if max_validation_age is None else max_validation_age
        if window > 0:
            with self._condition:
                now = time.monotonic()
                if self._status is not None and (
                    self._building
                    or (self._validated_at is not None and now - self._validated_at <= window)
                ):
                    _emit_board_timing("status_window_hit", rebuilding=self._building)
                    return self._status
                if self._status is None and self.persist:
                    last_good = self._load_last_good_locked()
                    if last_good is not None:
                        self._start_background_build_locked()
                        _emit_board_timing("status_last_good_served")
                        return last_good
        return self._get_summary_validated()

    def revalidate(self) -> None:
        """Background check: refresh the validation timestamp or rebuild after a source change."""
        with self._condition:
            if self._status is None or self._building:
                return
            current = self._signature
        signature = source_metadata_signature(self.project_root)
        with self._condition:
            if signature is not None and signature == current and self._signature == current and self._stale_reason is None:
                self._validated_at = time.monotonic()
                return
        self._get_summary_validated()

    def _get_summary_validated(self) -> dict:
        request_started = time.perf_counter()
        signature_started = time.perf_counter()
        signature = source_metadata_signature(self.project_root)
        signature_seconds = time.perf_counter() - signature_started
        observed_failure_generation = self._failure_generation
        with self._condition:
            while self._building:
                self._condition.wait()
                if self._failure_generation > observed_failure_generation and self._last_failure is not None:
                    raise RuntimeError(f"PROJECT_STATUS_BUILD_FAILED:{type(self._last_failure).__name__}") from self._last_failure
                signature_started = time.perf_counter()
                signature = source_metadata_signature(self.project_root)
                signature_seconds += time.perf_counter() - signature_started
                if signature is not None and signature == self._signature and self._status is not None:
                    self._validated_at = time.monotonic()
                    _emit_board_timing("status_cache_hit", seconds=round(time.perf_counter() - request_started, 4),
                                       signature_seconds=round(signature_seconds, 4))
                    return self._status
            if signature is not None and signature == self._signature and self._status is not None:
                self._validated_at = time.monotonic()
                _emit_board_timing("status_cache_hit", seconds=round(time.perf_counter() - request_started, 4),
                                   signature_seconds=round(signature_seconds, 4))
                return self._status
            self._building = True
            self.build_count += 1
        try:
            attempt = 0
            while True:
                build_started = time.perf_counter()
                status = build_status_summary(self.project_root)
                build_seconds = time.perf_counter() - build_started
                after_started = time.perf_counter()
                after = source_metadata_signature(self.project_root)
                after_seconds = time.perf_counter() - after_started
                if signature is None or after == signature:
                    break
                # Sources changed while building (e.g. a parallel agent session): retry with
                # bounded backoff instead of failing the request (BRD-F-11).
                if attempt >= len(SOURCE_CHURN_BACKOFF_SECONDS):
                    with self._condition:
                        if self._status is not None:
                            self._stale_reason = "SOURCES_CHURNING"
                            self._validated_at = time.monotonic()
                            _emit_board_timing("status_churn_served_stale", attempts=attempt + 1)
                            return self._status
                    raise RuntimeError("PROJECT_STATUS_SOURCES_CHANGED_DURING_BUILD")
                time.sleep(SOURCE_CHURN_BACKOFF_SECONDS[attempt])
                attempt += 1
                signature = source_metadata_signature(self.project_root)
                with self._condition:
                    self.build_count += 1
            head = git_head_and_branch(self.project_root)[0] if self.persist else None
            with self._condition:
                if signature is not None and after == signature:
                    self._signature = signature
                    self._status = status
                    self._full_status = None
                    self._gallery_cache.clear()
                    self._validated_at = time.monotonic()
                    self._built_at = self._validated_at
                    self._built_wall = time.time()
                    self._built_head = head
                    self._stale_reason = None
                else:
                    self._signature = None
                    self._status = None
                    self._full_status = None
                    self._gallery_cache.clear()
            if signature is not None and after == signature:
                self._persist_last_good(status, signature)
            _emit_board_timing(
                "status_cache_miss", seconds=round(time.perf_counter() - request_started, 4),
                signature_before_seconds=round(signature_seconds, 4), build_project_status_seconds=round(build_seconds, 4),
                signature_after_seconds=round(after_seconds, 4), retries=attempt,
            )
            return status
        except Exception as exc:
            with self._condition:
                self._failure_generation += 1
                self._last_failure = exc
            raise
        finally:
            with self._condition:
                self._building = False
                self._condition.notify_all()

    def get(self) -> dict:
        status = self.get_summary()
        with self._condition:
            while self._reconciliation_building:
                self._condition.wait()
            if self._full_status is not None and self._full_status.get("source_fingerprint") == status.get("source_fingerprint"):
                return self._full_status
            self._reconciliation_building = True
            expected_signature = self._signature
        started = time.perf_counter()
        try:
            reconciliation = build_report(self.project_root, project_status=status)
            result = dict(status)
            result["reconciliation"] = {
                "status": reconciliation.get("status", "UNKNOWN"),
                "read_only": True,
                "commit_range": reconciliation.get("commit_range", {"status": "UNKNOWN", "commits": [], "spans": []}),
                "watermark_gate": reconciliation.get("watermark_gate", {"can_advance": False, "blockers": ["REPORT_UNAVAILABLE"]}),
                "finding_impacts": reconciliation.get("finding_impacts", []),
                "model_semantic_review": reconciliation.get("model_semantic_review", {"status": "NOT_APPLICABLE", "model_paths": [], "capabilities": []}),
                "external_reference_candidates": reconciliation.get("external_reference_candidates", []),
                "impact_resolution": reconciliation.get("impact_resolution", {"status": "UNKNOWN", "candidates": []}),
            }
            after_started = time.perf_counter()
            after = source_metadata_signature(self.project_root)
            after_seconds = time.perf_counter() - after_started
            if expected_signature is not None and after != expected_signature:
                with self._condition:
                    self._validated_at = None  # force revalidation; keep serving the summary meanwhile
                raise RuntimeError("PROJECT_STATUS_SOURCES_CHANGED_DURING_RECONCILIATION")
            with self._condition:
                if expected_signature is not None and after == expected_signature:
                    self._full_status = result
            _emit_board_timing("full_projection_complete", reconciliation_seconds=round(time.perf_counter() - started, 4),
                               validation_signature_seconds=round(after_seconds, 4))
            return result
        except Exception as exc:
            with self._condition:
                self._failure_generation += 1
                self._last_failure = exc
            raise
        finally:
            with self._condition:
                self._reconciliation_building = False
                self._condition.notify_all()

    def get_gallery(self, screen_id: str | None = None) -> dict:
        self.get_summary()
        cache_key = screen_id or "*"
        with self._condition:
            while cache_key in self._gallery_building:
                self._condition.wait()
                cached = self._gallery_cache.get(cache_key)
                if cached is not None:
                    return cached
            cached = self._gallery_cache.get(cache_key)
            if cached is not None:
                return cached
            self._gallery_building.add(cache_key)
            expected_signature = self._signature
        started = time.perf_counter()
        try:
            status = build_status(self.project_root, include_gallery=True, gallery_screen_id=screen_id)
            after_started = time.perf_counter()
            after = source_metadata_signature(self.project_root)
            after_seconds = time.perf_counter() - after_started
            if expected_signature is not None and after != expected_signature:
                with self._condition:
                    self._validated_at = None
                    self._gallery_cache.clear()
                raise RuntimeError("PROJECT_STATUS_SOURCES_CHANGED_DURING_GALLERY_BUILD")
            items = status.get("verification", {}).get("gallery", [])
            latest_runs = {}
            for page_id in sorted({run.get("screen_id") for run in items if isinstance(run.get("screen_id"), str)}):
                page_runs = [run for run in items if run.get("screen_id") == page_id]
                latest = select_latest_run(page_runs)
                if latest is not None:
                    latest_runs[page_id] = {
                        **run_key(latest),
                        "stale": not any(not run.get("historical") for run in page_runs),
                    }
            result = {
                "source_fingerprint": status.get("source_fingerprint"),
                "gallery_state": status.get("verification", {}).get("gallery_state", "available"),
                "screen_id": screen_id,
                "items": items,
                # Server-side latest-run decision; the client must not re-derive it (BRD-F-08).
                "latest_runs": latest_runs,
            }
            with self._condition:
                if expected_signature is not None and after == expected_signature:
                    self._gallery_cache[cache_key] = result
            _emit_board_timing("gallery_projection_complete", seconds=round(time.perf_counter() - started, 4),
                               validation_signature_seconds=round(after_seconds, 4),
                               screen_id=screen_id, runs=len(result["items"]))
            return result
        except Exception as exc:
            with self._condition:
                self._failure_generation += 1
                self._last_failure = exc
            raise
        finally:
            with self._condition:
                self._gallery_building.discard(cache_key)
                self._condition.notify_all()


def canonical_url_path(value: str) -> str | None:
    if not value or value.startswith("/") or "\\" in value or "%" in value:
        return None
    path = PurePosixPath(value)
    if (
        not path.parts
        or path.is_absolute()
        or path.as_posix() != value
        or any(part in ("", ".", "..") for part in value.split("/"))
        or ":" in path.parts[0]
    ):
        return None
    return value


def _no_symlink_components(root: Path, relative_path: str) -> Path | None:
    candidate = root.joinpath(*PurePosixPath(relative_path).parts)
    current = root
    for part in PurePosixPath(relative_path).parts:
        current = current / part
        if current.is_symlink():
            return None
    try:
        candidate.resolve().relative_to(root.resolve())
    except (OSError, ValueError):
        return None
    return candidate


def resolve_reference_file(project_root: Path, status: dict, requested_path: str) -> Path | None:
    """Resolve active or manifest-bound historical references without filesystem browsing."""
    canonical = canonical_url_path(requested_path)
    if canonical is None or any(part.startswith('.') for part in PurePosixPath(canonical).parts):
        return None
    targets = list(status.get("project", {}).get("active_targets", {}).get("items", []))
    for run in status.get('verification', {}).get('gallery', []):
        reference = run['reference_path']
        revision_root = reference.split('/_history/', 1)[0] + '/_history/' + run['revision'] if '/_history/' in reference else None
        if revision_root and PurePosixPath(canonical).suffix.lower() in ('.html', '.css', '.js', '.mjs', '.png', '.jpg', '.jpeg', '.webp', '.svg', '.woff', '.woff2', '.ttf', '.ico'):
            targets.append({'availability': 'available', 'canonical_path': reference, 'reference_root': revision_root, 'reference_type': 'spa_bundle_entrypoint'})
        elif not revision_root and canonical == reference and PurePosixPath(canonical).suffix.lower() in ('.html', '.htm'):
            targets.append({'availability': 'available', 'canonical_path': reference, 'reference_root': str(PurePosixPath(reference).parent), 'reference_type': 'single_file_mockup'})
    for target in targets:
        if target.get("availability") != "available":
            continue
        target_path = target.get("canonical_path")
        reference_root = target.get("reference_root")
        if not isinstance(target_path, str) or not isinstance(reference_root, str):
            continue
        if target.get("reference_type") == "single_file_mockup":
            if canonical != target_path:
                continue
        elif target.get("reference_type") == "spa_bundle_entrypoint":
            if canonical != reference_root and not canonical.startswith(reference_root + "/"):
                continue
            if PurePosixPath(canonical).name.lower() == "revision.yaml":
                continue
        else:
            continue
        candidate = _no_symlink_components(project_root, canonical)
        if candidate is not None and candidate.is_file():
            return candidate
    return None


def resolve_source_file(project_root: Path, status: dict, requested_path: str) -> Path | None:
    canonical = canonical_url_path(requested_path)
    if canonical is None:
        return None
    references = status.get("source_references", {}).get("items", [])
    if not any(item.get("availability") == "available" and item.get("canonical_path") == canonical for item in references):
        return None
    candidate = _no_symlink_components(project_root, canonical)
    if candidate is not None and candidate.is_file():
        return candidate
    return None


def load_page_inventory(project_root: Path, page_id: str) -> dict | None:
    if not isinstance(page_id, str) or not re.fullmatch(r"PAGE-[A-Z0-9][A-Z0-9_-]*", page_id):
        return None
    inventory_root = _no_symlink_components(project_root, "planning/ui-inventory")
    if inventory_root is None or not inventory_root.is_dir():
        return None
    matches = []
    for path in sorted(inventory_root.glob("*.yaml"), key=lambda item: item.name.casefold()):
        if path.is_symlink():
            continue
        try:
            page = yaml.safe_load(path.read_text(encoding="utf-8"))
        except (OSError, yaml.YAMLError):
            continue
        if isinstance(page, dict) and page.get("page_id") == page_id:
            matches.append(page)
    return matches[0] if len(matches) == 1 else None


def _html_source_location(project_root: Path, page: dict) -> tuple[str, str] | None:
    source = page.get("html_source")
    canonical = canonical_url_path(source) if isinstance(source, str) else None
    if canonical is None:
        return None
    parts = PurePosixPath(canonical).parts
    if len(parts) < 5 or parts[0] != "themesource" or parts[2] != "public":
        return None
    if PurePosixPath(canonical).suffix.lower() not in (".html", ".htm"):
        return None
    if any(part.startswith(".") for part in parts):
        return None
    return canonical, PurePosixPath(*parts[:4]).as_posix()


def resolve_design_preview_file(project_root: Path, page_id: str, resource_path: str = "") -> Path | None:
    page = load_page_inventory(project_root, page_id)
    if page is None:
        return None
    location = _html_source_location(project_root, page)
    if location is None:
        return None
    source, feature_root = location
    relative = source
    if resource_path:
        canonical_resource = canonical_url_path(resource_path)
        if canonical_resource is None or any(part.startswith(".") for part in PurePosixPath(canonical_resource).parts):
            return None
        relative = f"{feature_root}/{canonical_resource}"
    if PurePosixPath(relative).suffix.lower() not in PREVIEW_EXTENSIONS:
        return None
    candidate = _no_symlink_components(project_root, relative)
    if candidate is None or not candidate.is_file():
        return None
    try:
        if candidate.stat().st_size > MAX_SOURCE_BYTES:
            return None
    except OSError:
        return None
    return candidate


def build_page_previews(project_root: Path, status: dict) -> dict:
    inventory_root = _no_symlink_components(project_root, "planning/ui-inventory")
    if inventory_root is None or not inventory_root.is_dir():
        return {"availability": "unavailable", "items": []}

    gallery = status.get("verification", {}).get("gallery", [])
    gallery_loaded = status.get("verification", {}).get("gallery_state") != "not_loaded"
    finding_projection = status.get("findings", {})
    finding_state = finding_projection.get("availability")
    findings = finding_projection.get("items", [])
    targets = status.get("project", {}).get("active_targets", {}).get("items", [])
    readiness = status.get("runtime", {}).get("recorded_readiness")
    runtime_state = "NOT_RECORDED"
    if isinstance(readiness, dict):
        runtime_state = readiness.get("state") or readiness.get("status") or "RECORDED"
    pages = []

    for path in sorted(inventory_root.glob("*.yaml")):
        if path.is_symlink():
            continue
        # Standalone interaction records are not Pages; the status projection excludes them too (BRD-F-05).
        if is_standalone_interaction_artifact(path.relative_to(project_root).as_posix()):
            continue
        try:
            page = yaml.safe_load(path.read_text(encoding="utf-8"))
        except (OSError, yaml.YAMLError):
            continue
        if not isinstance(page, dict) or not isinstance(page.get("page_id"), str):
            continue
        page_id = page["page_id"]
        if not re.fullmatch(r"PAGE-[A-Z0-9][A-Z0-9_-]*", page_id):
            continue

        try:
            settings = resolve_project_ui_settings(project_root, page_id)["settings"]
            settings_available = True
        except ProjectUiConfigError:
            settings = {}
            settings_available = False
        html_setting = settings.get("html_first", {})
        mockup_setting = settings.get("mockup_driven", {})

        target = next((item for item in targets if page_id in item.get("screen_ids", [])), None)
        reference_path = (target or {}).get("canonical_path") or page.get("target_mockup") or page.get("source_mockup")
        reference_available = bool(
            isinstance(reference_path, str) and resolve_reference_file(project_root, status, reference_path)
        )

        page_runs = [run for run in gallery if run.get("screen_id") == page_id]
        current_runs = [run for run in page_runs if not run.get("historical")]
        latest_run = select_latest_run(page_runs)
        parity_status = latest_run.get("parity_result", "NOT_VERIFIED") if latest_run else ("NOT_VERIFIED" if gallery_loaded else "NOT_LOADED")
        if page_runs and not current_runs:
            parity_status = "STALE"
        captures = latest_run.get("captures", []) if latest_run else []
        last_evidence = None
        if latest_run:
            last_evidence = {
                "entry_id": latest_run.get("entry_id"),
                "run_id": latest_run.get("run_id"),
                "parity_status": latest_run.get("parity_result", "NOT_VERIFIED"),
                "captured_at": max((item.get("captured_at", "") for item in captures), default=None),
                "capture_count": len(captures),
                "historical": bool(latest_run.get("historical")),
                "runtime_url": next((item.get("runtime_url") for item in captures if item.get("runtime_url")), None),
            }
        elif not gallery_loaded:
            last_evidence = {"status": "NOT_LOADED"}

        inventory_path = f"planning/ui-inventory/{page_id}.yaml"
        conflicts = []
        page_bound_findings = []
        for finding in findings:
            disposition = finding.get("authority_disposition") or {}
            if inventory_path in finding.get("source_artifact_paths", []):
                page_bound_findings.append(finding)
            if inventory_path in finding.get("source_artifact_paths", []) and disposition.get("classification") == "AUTHORITY_CONFLICT":
                conflicts.append({"id": finding.get("id"), "title": finding.get("title"), "status": disposition.get("status")})

        source_location = _html_source_location(project_root, page)
        html_source = page.get("html_source") if source_location else None
        source_exists = bool(source_location and resolve_design_preview_file(project_root, page_id))
        pages.append({
            "page_id": page_id,
            "page_name": page.get("page_name") or page.get("title") or page_id,
            "implementation_mode": (
                "HTML_FIRST" if html_setting.get("effective") is True else
                "MENDIX_NATIVE" if html_setting.get("effective") is False else "UNKNOWN"
            ),
            "html_first": html_setting,
            "mockup_driven": mockup_setting,
            "reference": {
                "path": reference_path,
                "availability": "available" if reference_available else "unknown",
                "url": f"/reference/{reference_path}" if reference_available else None,
            },
            "parity_status": parity_status,
            "authority_conflicts": {
                "availability": (
                    "unavailable" if finding_state not in ("available", "partial") else
                    "available" if page_bound_findings else "not_observable"
                ),
                "items": conflicts,
            },
            "html_source": {
                "path": html_source,
                "availability": "available" if source_exists else ("missing" if html_source else "not_configured"),
                "preview_url": f"/design-preview/{page_id}/" if source_exists else None,
                "source_url": f"/design-preview-source/{page_id}/?view=source" if source_exists else None,
                "preview_class": "DESIGN PREVIEW",
            },
            "runtime_status": {"state": runtime_state, "source": "recorded_readiness"},
            "last_verification_evidence": last_evidence,
        })
    return {"availability": "available", "items": pages}


def _design_preview_shell(page_id: str) -> bytes:
    safe_id = page_id.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace('"', "&quot;")
    document = (
        "<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">"
        "<title>Design Preview</title><style>html,body{margin:0;min-height:100%;font:13px 'Segoe UI',sans-serif;background:#f1f3f1;color:#18211d}"
        "header{padding:9px 14px;background:#1d2925;color:#fff;font:11px Consolas,monospace;letter-spacing:.04em}"
        "iframe{display:block;width:100%;height:calc(100vh - 35px);border:0;background:#fff}</style></head><body>"
        f"<header>DESIGN PREVIEW · {safe_id} · NOT MENDIX RUNTIME EVIDENCE</header>"
        f"<iframe title=\"Design Preview {safe_id}\" sandbox=\"allow-scripts\" src=\"/design-preview-source/{safe_id}/\"></iframe>"
        "</body></html>"
    )
    return document.encode("utf-8")


def resolve_builder_kit_status(project_root: Path) -> dict:
    started = time.perf_counter()
    home = Path.home()
    manifest_paths = (
        (project_root / ".mendix-page-designer-html-mode" / "manifest.json", "project"),
        (home / ".mendix-page-designer-html-mode" / "manifest.json", "global"),
    )
    manifest_state = "missing"
    manifest_version = None
    manifest_source = None
    for path, source in manifest_paths:
        if not path.is_file() or path.is_symlink():
            continue
        try:
            manifest = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            manifest_state = "invalid"
            continue
        if manifest.get("kit") != "mendix-ui-builder-kit" or manifest.get("agent") != "mendix-page-designer-html-mode":
            continue
        manifest_state = "valid"
        manifest_version = manifest.get("version") if isinstance(manifest.get("version"), str) else None
        manifest_source = source
        break

    agent_files = {
        "vscode_copilot": (
            project_root / ".github/agents/mendix-page-designer-html-mode.agent.md",
            home / ".copilot/agents/mendix-page-designer-html-mode.agent.md",
        ),
        "claude_code": (
            project_root / ".claude/agents/mendix-page-designer-html-mode.md",
            home / ".claude/agents/mendix-page-designer-html-mode.md",
        ),
        "opencode": (
            project_root / ".opencode/agents/mendix-page-designer-html-mode.md",
            home / ".config/opencode/agents/mendix-page-designer-html-mode.md",
        ),
    }
    available_agents = {
        harness: any(path.is_file() and not path.is_symlink() for path in paths)
        for harness, paths in agent_files.items()
    }
    result = {
        "availability": "available",
        "kit": "mendix-ui-builder-kit",
        "installed": manifest_state == "valid",
        "installation_state": manifest_state,
        "version": manifest_version,
        "manifest_source": manifest_source,
        "current_harness": "unknown",
        "agent": "mendix-page-designer-html-mode",
        "agent_files_available": available_agents,
        "agent_available_for_harness": None,
        "agent_delegable": None,
        "agent_observed": False,
        "delegation_reason": "The Board has no current-session harness or named-agent observation.",
        "note": "Builder Kit installation is independent from ui.implementation.html_first.",
    }
    _emit_board_timing("builder_kit_capability", seconds=round(time.perf_counter() - started, 4))
    return result


def resolve_capture_file(project_root: Path, status: dict, requested_path: str) -> Path | None:
    canonical = canonical_url_path(requested_path)
    if canonical is None:
        return None
    allowed = {capture['screenshot_path'] for run in status.get('verification', {}).get('gallery', []) for capture in run['captures']}
    return safe_file(project_root, canonical) if canonical in allowed else None


class ProjectBoardHandler(BaseHTTPRequestHandler):
    server_version = "MxAgileBoard/1"
    sys_version = ""

    @property
    def project_root(self) -> Path:
        return self.server.project_root  # type: ignore[attr-defined]

    @property
    def ui_root(self) -> Path:
        return self.server.ui_root  # type: ignore[attr-defined]

    def _send(self, status_code: int, body: bytes, content_type: str, *, is_reference: bool = False, is_preview: bool = False) -> None:
        if len(body) > MAX_SOURCE_BYTES:
            self.send_error(413)
            return
        self.send_response(status_code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Referrer-Policy", "no-referrer")
        if is_preview:
            self.send_header("X-MxAgile-Evidence-Class", "DESIGN_PREVIEW")
            self.send_header(
                "Content-Security-Policy",
                "default-src 'self' data: blob:; script-src 'self' 'unsafe-inline'; "
                "style-src 'self' 'unsafe-inline'; connect-src 'self'; img-src 'self' data: blob:; "
                "font-src 'self' data:; frame-src 'self'; object-src 'none'; base-uri 'none'; frame-ancestors 'self'",
            )
        elif is_reference:
            self.send_header(
                "Content-Security-Policy",
                "default-src 'self' data: blob:; script-src 'self' 'unsafe-inline'; "
                "style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; "
                "font-src 'self' data:; object-src 'none'; base-uri 'none'; frame-ancestors 'none'",
            )
        else:
            self.send_header(
                "Content-Security-Policy",
                "default-src 'self'; script-src 'self'; style-src 'self'; connect-src 'self'; "
                "img-src 'self' data:; object-src 'none'; base-uri 'none'; frame-ancestors 'none'",
            )
        self.end_headers()
        try:
            self.wfile.write(body)
        except (ConnectionAbortedError, ConnectionResetError, BrokenPipeError):
            self.log_message("CLIENT_DISCONNECT")
        finally:
            request_started = getattr(self, "_request_started_at", None)
            if request_started is not None:
                _emit_board_timing(
                    "http_response", path=urlsplit(self.path).path, status=status_code,
                    seconds=round(time.perf_counter() - request_started, 4),
                    server_age_seconds=round(time.perf_counter() - self.server.created_at, 4),
                    response_bytes=len(body),
                )

    def _read_file(self, path: Path) -> bytes | None:
        try:
            if path.stat().st_size > MAX_SOURCE_BYTES:
                return None
            return path.read_bytes()
        except OSError:
            return None

    def _status(self, *, include_git_head: bool = False) -> dict:
        status = dict(self.server.status_cache.get_summary())  # type: ignore[attr-defined]
        try:
            status["ui_settings"] = {
                "availability": "available",
                **resolve_project_ui_settings(self.project_root),
            }
        except ProjectUiConfigError:
            status["ui_settings"] = {"availability": "invalid", "page_id": None, "settings": {}}
        status["reconciliation"] = {
            "availability": "not_loaded",
            "status": "NOT_LOADED",
            "read_only": True,
            "commit_range": {"status": "NOT_LOADED", "commits": [], "spans": []},
            "watermark_gate": {"can_advance": False, "blockers": ["RECONCILIATION_NOT_LOADED"]},
            "finding_impacts": [],
            "model_semantic_review": {"status": "NOT_LOADED", "model_paths": [], "capabilities": []},
            "external_reference_candidates": [],
            "impact_resolution": {"status": "NOT_LOADED", "candidates": []},
        }
        if include_git_head:
            # Observed repository facts are cheap and known before reconciliation loads (BRD-F-01).
            head, branch = git_head_and_branch(self.project_root)
            status["reconciliation"]["commit_range"].update({"to_commit": head, "branch_ref": branch})
        return status

    def do_GET(self) -> None:
        self._request_started_at = time.perf_counter()
        parsed = urlsplit(self.path)
        if parsed.query and parsed.path != "/api/gallery" and not parsed.path.startswith(("/reference/", "/source/", "/design-preview-source/")):
            self.send_error(400)
            return
        if parsed.path == "/api/status":
            try:
                status = self._status(include_git_head=True)
                # Projection state is explicit: a stale or rebuilding projection never looks current.
                status["projection_state"] = self.server.status_cache.projection_info()  # type: ignore[attr-defined]
                payload = json.dumps(status, ensure_ascii=False, sort_keys=True).encode("utf-8")
            except Exception as exc:
                self.log_error("STATUS_BUILD_FAILED: %s", type(exc).__name__)
                payload = json.dumps({"error": "status_unavailable", "reason": type(exc).__name__}).encode("utf-8")
                self._send(503, payload, "application/json; charset=utf-8")
                return
            self._send(200, payload, "application/json; charset=utf-8")
            return

        if parsed.path == "/api/gallery":
            query = parse_qs(parsed.query, keep_blank_values=True)
            if set(query) - {"screen_id"} or any(len(values) != 1 for values in query.values()):
                self.send_error(400)
                return
            screen_id = query.get("screen_id", [None])[0]
            if screen_id is not None and not re.fullmatch(r"PAGE-[A-Z0-9][A-Z0-9_-]*", screen_id):
                self.send_error(400)
                return
            try:
                payload = json.dumps(
                    self.server.status_cache.get_gallery(screen_id),  # type: ignore[attr-defined]
                    ensure_ascii=False,
                    sort_keys=True,
                ).encode("utf-8")
            except Exception as exc:
                self.log_error("GALLERY_BUILD_FAILED: %s", type(exc).__name__)
                self._send(503, json.dumps({"error": "gallery_unavailable", "reason": type(exc).__name__}).encode("utf-8"), "application/json; charset=utf-8")
                return
            self._send(200, payload, "application/json; charset=utf-8")
            return

        if parsed.path == "/api/reconciliation":
            try:
                started = time.perf_counter()
                full_status = self.server.status_cache.get()  # type: ignore[attr-defined]
                payload = json.dumps({
                    "source_fingerprint": full_status.get("source_fingerprint"),
                    "reconciliation": full_status.get("reconciliation"),
                }, ensure_ascii=False, sort_keys=True).encode("utf-8")
                _emit_board_timing("reconciliation_json", seconds=round(time.perf_counter() - started, 4), bytes=len(payload))
            except Exception as exc:
                self.log_error("RECONCILIATION_BUILD_FAILED: %s", type(exc).__name__)
                self._send(503, json.dumps({"error": "reconciliation_unavailable", "reason": type(exc).__name__}).encode("utf-8"), "application/json; charset=utf-8")
                return
            self._send(200, payload, "application/json; charset=utf-8")
            return

        if parsed.path == "/api/page-previews":
            try:
                started = time.perf_counter()
                status = self._status()
                projection = build_page_previews(self.project_root, status)
                payload = json.dumps({
                    "availability": projection["availability"],
                    "project_settings": status["ui_settings"],
                    "builder_kit": resolve_builder_kit_status(self.project_root),
                    "items": projection["items"],
                }, ensure_ascii=False, sort_keys=True).encode("utf-8")
                _emit_board_timing("page_preview_metadata", seconds=round(time.perf_counter() - started, 4),
                                   page_count=len(projection["items"]), bytes=len(payload))
            except Exception as exc:
                self.log_error("PAGE_PREVIEW_METADATA_FAILED: %s", type(exc).__name__)
                self._send(503, json.dumps({"error": "page_preview_metadata_unavailable", "reason": type(exc).__name__}).encode("utf-8"), "application/json; charset=utf-8")
                return
            self._send(200, payload, "application/json; charset=utf-8")
            return

        if parsed.path.startswith("/design-preview/"):
            encoded_id = parsed.path[len("/design-preview/"):].strip("/")
            try:
                page_id = unquote(encoded_id, errors="strict")
            except UnicodeError:
                self.send_error(404)
                return
            if "/" in page_id or resolve_design_preview_file(self.project_root, page_id) is None:
                self.send_error(404)
                return
            self._send(200, _design_preview_shell(page_id), "text/html; charset=utf-8", is_preview=True)
            return

        if parsed.path.startswith("/design-preview-source/"):
            raw = parsed.path[len("/design-preview-source/"):]
            encoded_id, separator, encoded_resource = raw.partition("/")
            try:
                page_id = unquote(encoded_id, errors="strict")
                resource = unquote(encoded_resource, errors="strict") if separator else ""
            except UnicodeError:
                self.send_error(404)
                return
            query = parse_qs(parsed.query, keep_blank_values=True)
            if query not in ({}, {"view": ["source"]}) or "/" in page_id:
                self.send_error(400)
                return
            file_path = resolve_design_preview_file(self.project_root, page_id, resource)
            body = self._read_file(file_path) if file_path else None
            if body is None:
                self.send_error(404)
                return
            if query.get("view") == ["source"]:
                self._send(200, body, "text/plain; charset=utf-8")
                return
            content_type = mimetypes.guess_type(file_path.name)[0] or "application/octet-stream"
            self._send(200, body, content_type, is_preview=True)
            return

        if parsed.path.startswith("/diagnostic-source/"):
            try:
                requested = unquote(parsed.path[len("/diagnostic-source/"):], errors="strict")
            except UnicodeError:
                self.send_error(404)
                return
            if canonical_url_path(requested) is None or safe_file(self.project_root, requested) is None:
                self.send_error(404)
                return
            try:
                status = self._status()
            except Exception as exc:
                self.log_error("STATUS_BUILD_FAILED: %s", type(exc).__name__)
                self._send(503, json.dumps({"error": "status_unavailable", "reason": type(exc).__name__}).encode("utf-8"), "application/json; charset=utf-8")
                return
            diagnostics = [item for item in status.get("compatibility", {}).get("diagnostics", []) if item["source_path"] == requested]
            if not diagnostics:
                self.send_error(404)
                return
            body = json.dumps({"source_path": requested, "source_content": "REDACTED", "diagnostics": diagnostics}, sort_keys=True, indent=2).encode("utf-8")
            self._send(200, body, "text/plain; charset=utf-8")
            return

        ui_name = UI_FILES.get(parsed.path)
        if ui_name:
            path = self.ui_root / ui_name
            if not path.is_file() or path.is_symlink():
                self.send_error(404)
                return
            body = self._read_file(path)
            if body is None:
                self.send_error(404)
                return
            content_type = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
            self._send(200, body, f"{content_type}; charset=utf-8")
            return

        if parsed.path.startswith("/capture/"):
            try:
                requested = unquote(parsed.path[len('/capture/'):], errors='strict')
            except UnicodeError:
                self.send_error(404)
                return
            try:
                status = self._status()
            except Exception as exc:
                self.log_error("STATUS_BUILD_FAILED: %s", type(exc).__name__)
                self._send(503, json.dumps({"error": "status_unavailable", "reason": type(exc).__name__}).encode("utf-8"), "application/json; charset=utf-8")
                return
            if status.get("verification", {}).get("gallery_state") == "not_loaded":
                try:
                    gallery = self.server.status_cache.get_gallery()  # type: ignore[attr-defined]
                    status["verification"]["gallery"] = gallery["items"]
                    status["verification"]["gallery_state"] = gallery["gallery_state"]
                except Exception as exc:
                    self.log_error("GALLERY_BUILD_FAILED: %s", type(exc).__name__)
                    self._send(503, json.dumps({"error": "gallery_unavailable", "reason": type(exc).__name__}).encode("utf-8"), "application/json; charset=utf-8")
                    return
            path = resolve_capture_file(self.project_root, status, requested)
            body = self._read_file(path) if path else None
            if body is None:
                self.send_error(404)
                return
            self._send(200, body, mimetypes.guess_type(path.name)[0] or 'application/octet-stream')
            return

        if parsed.path.startswith("/reference/"):
            raw_path = parsed.path[len("/reference/"):]
            try:
                requested = unquote(raw_path, errors="strict")
            except UnicodeError:
                self.send_error(404)
                return
            try:
                status = self._status()
            except Exception as exc:
                self.log_error("STATUS_BUILD_FAILED: %s", type(exc).__name__)
                self._send(503, json.dumps({"error": "status_unavailable", "reason": type(exc).__name__}).encode("utf-8"), "application/json; charset=utf-8")
                return
            file_path = resolve_reference_file(self.project_root, status, requested)
            if file_path is None:
                self.send_error(404)
                return
            body = self._read_file(file_path)
            if body is None:
                self.send_error(404)
                return
            content_type = mimetypes.guess_type(file_path.name)[0] or "application/octet-stream"
            self._send(200, body, content_type, is_reference=True)
            return

        if parsed.path.startswith("/source/"):
            raw_path = parsed.path[len("/source/"):]
            try:
                requested = unquote(raw_path, errors="strict")
            except UnicodeError:
                self.send_error(404)
                return
            try:
                status = self._status()
            except Exception as exc:
                self.log_error("STATUS_BUILD_FAILED: %s", type(exc).__name__)
                self._send(503, json.dumps({"error": "status_unavailable", "reason": type(exc).__name__}).encode("utf-8"), "application/json; charset=utf-8")
                return
            file_path = resolve_source_file(self.project_root, status, requested)
            if file_path is None:
                self.send_error(404)
                return
            body = self._read_file(file_path)
            if body is None:
                self.send_error(404)
                return
            self._send(200, body, "text/plain; charset=utf-8")
            return

        self.send_error(404)

    def log_message(self, format_string: str, *args: object) -> None:
        sys.stderr.write("%s - %s\n" % (self.address_string(), format_string % args))


class ProjectBoardServer(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = False

    def __init__(
        self,
        project_root: Path,
        ui_root: Path,
        port: int,
        *,
        background_refresh: bool = False,
        persist_cache: bool = False,
    ):
        started = time.perf_counter()
        self.project_root = project_root.resolve()
        self.ui_root = ui_root.resolve()
        self.status_cache = ProjectStatusCache(self.project_root, persist=persist_cache)
        # Requests trust a snapshot validated within this window; legacy mode keeps per-request validation.
        self.status_cache.request_window = 0.0 if legacy_cache_mode() else VALIDATION_WINDOW_SECONDS
        self._refresh_stop = threading.Event()
        self._refresh_thread: threading.Thread | None = None
        super().__init__(("127.0.0.1", port), ProjectBoardHandler)
        self.created_at = time.perf_counter()
        self.startup_seconds = self.created_at - started
        if background_refresh and not legacy_cache_mode():
            self._refresh_thread = threading.Thread(target=self._refresh_loop, name="mxagile-board-revalidate", daemon=True)
            self._refresh_thread.start()
        _emit_board_timing("server_bound", seconds=round(self.startup_seconds, 4), port=self.server_port)

    def _refresh_loop(self) -> None:
        interval = BACKGROUND_REFRESH_SECONDS
        while not self._refresh_stop.wait(interval):
            started = time.perf_counter()
            try:
                self.status_cache.revalidate()
            except Exception as exc:  # surfaced via projection_info on the next request
                _emit_board_timing("background_revalidate_failed", reason=type(exc).__name__)
            # Adaptive pacing bounds idle CPU: at most ~1/3 of wall time is spent on validation.
            interval = max(BACKGROUND_REFRESH_SECONDS, 3 * (time.perf_counter() - started))

    def server_close(self) -> None:
        self._refresh_stop.set()
        super().server_close()


def default_project_root() -> Path:
    script_path = Path(__file__).resolve()
    for parent in script_path.parents:
        if parent.name != ".mxagile" and (parent / ".mxagile").is_dir():
            return parent
    return Path.cwd().resolve()


def main() -> int:
    parser = argparse.ArgumentParser(description="Serve the read-only MxAgile project board on loopback.")
    parser.add_argument("--project-root", type=Path, default=default_project_root())
    parser.add_argument("--port", type=int, default=8765)
    args = parser.parse_args()
    root = args.project_root.resolve()
    ui_root = root / ".mxagile" / "board"
    if not (root / ".mxagile").is_dir() or not (ui_root / "index.html").is_file():
        print("Project board payload unavailable", file=sys.stderr)
        return 2
    try:
        server = ProjectBoardServer(root, ui_root, args.port, background_refresh=True, persist_cache=True)
    except OSError as exc:
        print(f"Project board could not bind to loopback ({type(exc).__name__})", file=sys.stderr)
        return 2
    print(f"MxAgile Board: http://127.0.0.1:{server.server_port}/")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())