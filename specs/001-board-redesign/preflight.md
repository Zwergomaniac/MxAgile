# Pre-Flight — 001-board-redesign

## T001 · Foreign uncommitted changes (Stand 2026-11-05, vor CS-1, HEAD `e6a1481`)

Diese Pfade tragen fremde, vor dieser Mission entstandene Änderungen. Sie werden von keinem Changeset gestaged,
überschrieben oder zurückgesetzt.

| Pfad | Status |
|---|---|
| `.mxagile/policies/agent-delegation.md` | M |
| `.mxagile/policies/implementation-control.md` | M |
| `.mxagile/policies/lifecycle-resync.md` | M |
| `.mxagile/policies/test-workflow.md` | M |
| `.mxagile/skills/gate-to-ready.md` | M |
| `CLAUDE.md` | M |
| `docs/context-architecture-baseline.md` | M |
| `scripts/apply-project-agent-instructions.ps1` | M |
| `tests/test-agent-delegation.ps1` | M |
| `tests/test-architecture-drift-prevention.ps1` | M |
| `tests/test-lifecycle-resync.ps1` | M |
| `tests/test-runtime-orchestration.ps1` | M |
| `tests/test-startup-priority.ps1` | M |
| `.vscode/tasks.json` | ?? |
| `tests/temp-project/` | ?? (neu, Herkunft nicht von dieser Mission) |

Eigene, noch untrackte Planungsartefakte dieser Mission: `docs/board-redesign-{plan,findings,implementation-contract}.md`, `specs/001-board-redesign/`.

## T002 · Changeset-Dateien vs. fremde Änderungen

| CS | Geplante Dateien (plan.md) | Konflikt mit T001 | Status |
|---|---|---|---|
| CS-1 | `scripts/serve_project_board.py`, `scripts/reconcile_external_changes.py`, `scripts/build_project_status.py`, `.mxagile/board/board.js`, `tests/test_board_http.py`, `tests/test_external_change_reconciliation.py`, `tests/test_parity_gallery.py`, `tests/fixtures/board-redesign/` | keiner | frei |
| CS-2 | `serve_project_board.py`, `reconciliation_git.py`, `reconcile_external_changes.py`, `project_compatibility.py`, `project-status.schema.json`, `board.js`, Tests | keiner | frei |
| CS-7 | `board_smoke.py`, `serve_project_board.py`, `project_compatibility.py`, `install-core.ps1`, `run-impact-tests.py`, Tests | keiner (darf `CLAUDE.md` nicht berühren) | frei |
| CS-0 | Policies inkl. `lifecycle-resync.md`, `implementation-control.md`, `gap-verification-repair.md`, `lifecycle.yaml`, `GLOSSARY.yaml`, `process-state.schema.json`, `project_compatibility.py` | **ja**: `lifecycle-resync.md`, `implementation-control.md` | **blockiert** bis zum Eigentümer-Commit |
| CS-3…CS-6 | Board-/Status-/Schema-Dateien | keiner | frei |

## T003 · Commit-Identität

`git var GIT_AUTHOR_IDENT` = `git var GIT_COMMITTER_IDENT` = `Zwergomaniac <Keeperdeluxe@web.de>` → **OK**.

## Update nach CS-1 (2026-11-05)

Der Eigentümer hat die vorbestehenden Änderungen in `c74382e` („Clarify MxAgile execution and Wave policies") committet. Die CS-0-Blockade aus T002 ist damit aufgehoben; T058 bleibt als Prüfschritt vor CS-0 bestehen.
