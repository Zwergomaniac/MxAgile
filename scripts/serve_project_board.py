"""Serve the read-only local MxAgile project board on loopback."""

from __future__ import annotations

import argparse
import json
import mimetypes
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path, PurePosixPath
from urllib.parse import unquote, urlsplit

from build_project_status import build_status
from project_compatibility import safe_file

MAX_SOURCE_BYTES = 32 * 1024 * 1024
UI_FILES = {"/": "index.html", "/index.html": "index.html", "/styles.css": "styles.css", "/board.js": "board.js"}


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
        return build_status(self.project_root)

    def do_GET(self) -> None:
        parsed = urlsplit(self.path)
        if parsed.query and not parsed.path.startswith(("/reference/", "/source/")):
            self.send_error(400)
            return
        if parsed.path == "/api/status":
            try:
                payload = json.dumps(self._status(), ensure_ascii=False, sort_keys=True).encode("utf-8")
            except Exception:
                payload = json.dumps({"error": "status_unavailable"}).encode("utf-8")
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
            diagnostics = [item for item in self._status().get("compatibility", {}).get("diagnostics", []) if item["source_path"] == requested]
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
            path = resolve_capture_file(self.project_root, self._status(), requested)
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
            file_path = resolve_reference_file(self.project_root, self._status(), requested)
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
            file_path = resolve_source_file(self.project_root, self._status(), requested)
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