"""Harness-neutral, opt-in context architecture inventory and record scaffold."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from context_telemetry_model import DECLARED, OBSERVED, new_session_record, not_observable, observation


def _file_entry(path: Path, project_root: Path) -> dict[str, Any]:
    relative_path = path.relative_to(project_root).as_posix()
    try:
        raw = path.read_bytes()
    except FileNotFoundError:
        return {
            "path": relative_path,
            "file_presence": observation(OBSERVED, "ABSENT", "local filesystem lookup"),
            "runtime_load": not_observable("Harness file loading was not attested in this collector run."),
        }
    except OSError:
        return {
            "path": relative_path,
            "file_presence": not_observable("File metadata could not be read in this collector run."),
            "runtime_load": not_observable("Harness file loading was not attested in this collector run."),
        }
    return {
        "path": relative_path,
        "file_presence": observation(OBSERVED, "PRESENT", "local filesystem lookup"),
        "runtime_load": not_observable("File presence is not evidence that the harness loaded this file."),
        "utf8_bytes": len(raw),
        "sha256": hashlib.sha256(raw).hexdigest(),
    }


def source_inventory(project_root: Path) -> dict[str, Any]:
    instruction_paths = (
        "AGENT.md",
        "AGENTS.md",
        "CLAUDE.md",
        ".github/copilot-instructions.md",
    )
    instructions = [_file_entry(project_root / relative, project_root) for relative in instruction_paths]
    projection_roots = {
        "claude_agents": ".claude/agents",
        "claude_skills": ".claude/skills",
        "copilot_skills": ".github/skills",
        "codex_skills": ".agents/skills",
        "grok_skills": ".grok/skills",
        "opencode_skills": ".opencode/skills",
        "hermes_skills": ".hermes/skills",
    }
    projections: dict[str, Any] = {}
    for name, relative_root in projection_roots.items():
        root = project_root / relative_root
        files = [path for path in root.rglob("*") if path.is_file()] if root.is_dir() else []
        projections[name] = {
            "source_class": "GENERATED_PROJECTION",
            "file_presence": observation(OBSERVED, len(files), "local filesystem inventory"),
            "runtime_load": not_observable("Harness loading was not attested in this collector run."),
            "files": len(files),
            "utf8_bytes": sum(path.stat().st_size for path in files),
        }
    return {
        "instruction_files": instructions,
        "generated_projections": projections,
        "note": "On-disk presence and bytes do not prove harness loading.",
    }


def build_report(project_root: Path, harness: str, session_id: str, run_id: str) -> dict[str, Any]:
    record = new_session_record(harness, session_id, run_id)
    record["collector_id"] = observation(DECLARED, "context_architecture_telemetry", "executed shared CLI")
    record["harness"] = observation(DECLARED, harness, "caller-selected collector scope")
    record["session_identity"] = observation(DECLARED, session_id, "caller-supplied identifier")
    record["run_identity"] = observation(DECLARED, run_id, "caller-supplied identifier")
    record["collection_scope"] = observation(DECLARED, "this_collector_run", "shared CLI report scope")
    return {
        "telemetry_version": 1,
        "collector_scope": "NOT_OBSERVABLE applies to this collector run and is not a harness capability claim.",
        "measured_at": datetime.now(timezone.utc).isoformat(),
        "project_root_label": project_root.name,
        "session": record,
        "source_inventory": source_inventory(project_root),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", type=Path, default=Path.cwd())
    parser.add_argument("--harness", required=True, help="Caller-declared collector scope; not a runtime harness attestation.")
    parser.add_argument("--session-id", required=True, help="Caller-supplied session identity.")
    parser.add_argument("--run-id", required=True, help="Caller-supplied collection run identity.")
    parser.add_argument("--output", type=Path, help="Optional report JSON path. Default is stdout; no automatic store is written.")
    args = parser.parse_args()

    try:
        report = build_report(args.project_root.resolve(), args.harness, args.session_id, args.run_id)
        serialized = json.dumps(report, ensure_ascii=False, indent=2) + "\n"
        if args.output:
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(serialized, encoding="utf-8")
        else:
            sys.stdout.write(serialized)
        return 0
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"context telemetry unavailable: {type(exc).__name__}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
