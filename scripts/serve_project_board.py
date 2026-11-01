"""Serve the read-only local MxAgile project board on loopback."""

from __future__ import annotations

import argparse
import hashlib
import json
import mimetypes
import os
import subprocess
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path, PurePosixPath
from urllib.parse import unquote, urlsplit

from build_project_status import build_status
from project_compatibility import safe_file
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
SKIP_STATUS_DIRS = {".git", ".concord", ".mxcli", "node_modules", "deployment"}


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


def source_metadata_signature(project_root: Path) -> str | None:
    """Cheap invalidation hint; metadata is never emitted as project authority."""
    root = project_root.resolve()
    records: dict[str, tuple] = {}
    try:
        root_record = _metadata_record(root, root)
        if root_record is None:
            return None
        records["."] = root_record
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
                    child_record = _metadata_record(root, child)
                    if child_record is None:
                        return None
                    records[child.relative_to(root).as_posix()] = child_record
                    if name not in SKIP_STATUS_DIRS and not child.is_symlink():
                        retained.append(name)
                dirnames[:] = retained
                for name in sorted(filenames):
                    child = current / name
                    child_record = _metadata_record(root, child)
                    if child_record is None:
                        return None
                    records[child.relative_to(root).as_posix()] = child_record

        git = subprocess.run(
            ["git", "--no-optional-locks", "-C", str(root), "rev-parse", "--verify", "HEAD"],
            capture_output=True,
            check=False,
        )
        if git.returncode == 0:
            head = git.stdout.decode("ascii", errors="strict").strip()
            branch = subprocess.run(
                ["git", "--no-optional-locks", "-C", str(root), "symbolic-ref", "--quiet", "HEAD"],
                capture_output=True,
                check=False,
            )
            branch_ref = branch.stdout.decode("utf-8", errors="replace").strip() if branch.returncode == 0 else "DETACHED"
            index_value = subprocess.run(
                ["git", "--no-optional-locks", "-C", str(root), "rev-parse", "--git-path", "index"],
                capture_output=True,
                check=False,
            )
            if index_value.returncode:
                return None
            index_path = Path(index_value.stdout.decode("utf-8", errors="replace").strip())
            if not index_path.is_absolute():
                index_path = root / index_path
            index_record = _metadata_record(root, index_path)
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
        elif (root / ".git").exists():
            return None
        else:
            records["!git"] = ("NO_GIT",)
    except (OSError, UnicodeError, ValueError, subprocess.SubprocessError):
        return None
    payload = json.dumps([records[key] for key in sorted(records)], ensure_ascii=False, separators=(",", ":"))
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


class ProjectStatusCache:
    def __init__(self, project_root: Path):
        self.project_root = project_root.resolve()
        self._condition = threading.Condition()
        self._building = False
        self._signature: str | None = None
        self._status: dict | None = None
        self._failure_generation = 0
        self._last_failure: Exception | None = None
        self.build_count = 0

    def get(self) -> dict:
        signature = source_metadata_signature(self.project_root)
        observed_failure_generation = self._failure_generation
        with self._condition:
            while self._building:
                self._condition.wait()
                if self._failure_generation > observed_failure_generation and self._last_failure is not None:
                    raise RuntimeError(f"PROJECT_STATUS_BUILD_FAILED:{type(self._last_failure).__name__}") from self._last_failure
                signature = source_metadata_signature(self.project_root)
                if signature is not None and signature == self._signature and self._status is not None:
                    return self._status
            if signature is not None and signature == self._signature and self._status is not None:
                return self._status
            self._building = True
            self.build_count += 1
        try:
            status = build_status(self.project_root)
            reconciliation = build_report(self.project_root, project_status=status)
            status["reconciliation"] = {
                "status": reconciliation.get("status", "UNKNOWN"),
                "read_only": True,
                "commit_range": reconciliation.get("commit_range", {"status": "UNKNOWN", "commits": [], "spans": []}),
                "watermark_gate": reconciliation.get("watermark_gate", {"can_advance": False, "blockers": ["REPORT_UNAVAILABLE"]}),
                "finding_impacts": reconciliation.get("finding_impacts", []),
                "model_semantic_review": reconciliation.get("model_semantic_review", {"status": "NOT_APPLICABLE", "model_paths": [], "capabilities": []}),
                "external_reference_candidates": reconciliation.get("external_reference_candidates", []),
                "impact_resolution": reconciliation.get("impact_resolution", {"status": "UNKNOWN", "candidates": []}),
            }
            after = source_metadata_signature(self.project_root)
            if signature is not None and after != signature:
                raise RuntimeError("PROJECT_STATUS_SOURCES_CHANGED_DURING_BUILD")
            with self._condition:
                if signature is not None and after == signature:
                    self._signature = signature
                    self._status = status
                else:
                    self._signature = None
                    self._status = None
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

    def _send(self, status_code: int, body: bytes, content_type: str, *, is_reference: bool = False) -> None:
        if len(body) > MAX_SOURCE_BYTES:
            self.send_error(413)
            return
        self.send_response(status_code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Referrer-Policy", "no-referrer")
        if is_reference:
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
        self.wfile.write(body)

    def _read_file(self, path: Path) -> bytes | None:
        try:
            if path.stat().st_size > MAX_SOURCE_BYTES:
                return None
            return path.read_bytes()
        except OSError:
            return None

    def _status(self) -> dict:
        return self.server.status_cache.get()  # type: ignore[attr-defined]

    def do_GET(self) -> None:
        parsed = urlsplit(self.path)
        if parsed.query and not parsed.path.startswith(("/reference/", "/source/")):
            self.send_error(400)
            return
        if parsed.path == "/api/status":
            try:
                payload = json.dumps(self._status(), ensure_ascii=False, sort_keys=True).encode("utf-8")
            except Exception as exc:
                self.log_error("STATUS_BUILD_FAILED: %s", type(exc).__name__)
                payload = json.dumps({"error": "status_unavailable", "reason": type(exc).__name__}).encode("utf-8")
                self._send(503, payload, "application/json; charset=utf-8")
                return
            self._send(200, payload, "application/json; charset=utf-8")
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

    def __init__(self, project_root: Path, ui_root: Path, port: int):
        self.project_root = project_root.resolve()
        self.ui_root = ui_root.resolve()
        self.status_cache = ProjectStatusCache(self.project_root)
        super().__init__(("127.0.0.1", port), ProjectBoardHandler)


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
        server = ProjectBoardServer(root, ui_root, args.port)
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