# CS-1 Report — Board shows nothing false

**Status:** Implementation + gate complete · Commit `f38b0c8` · **STOP after CS-1** (CS-2 not authorized)

## 1. Scope delivered

| Finding | Change | Files |
|---|---|---|
| BRD-F-01 | Reconciliation placeholder carries observed `to_commit`/`branch_ref` (one `git rev-parse HEAD --symbolic-full-name HEAD`, only on `/api/status`); client renders `NICHT GELADEN`/`LÄDT …` with HEAD/branch, never `BASELINE REQUIRED`/`HEAD UNKNOWN` while not loaded; failed load keeps observed HEAD/branch (`RECONCILIATION NICHT VERFÜGBAR`) | `scripts/serve_project_board.py`, `.mxagile/board/board.js` |
| BRD-F-02 | `build_report` without watermark exposes `commit_range.to_commit` (HEAD) and `branch_ref`; `from_commit: null` | `scripts/reconcile_external_changes.py` |
| BRD-F-03 | Finding detail resolves terminal findings from `findings.history` (title fallback for history items) | `.mxagile/board/board.js` |
| BRD-F-04 | Wave detail shows `NICHT ERFASST` instead of a fabricated `0` when no mission state exists | `.mxagile/board/board.js` |
| BRD-F-05 | Page previews skip standalone interaction artifacts (same rule as status projection) | `scripts/serve_project_board.py` |
| BRD-F-06 | UI & Pages loads parity evidence lazily; until loaded shows `NICHT GELADEN`/`LÄDT …`/`NICHT VERFÜGBAR` (no value implied) | `.mxagile/board/board.js` |
| BRD-F-07 | Parity reports in `planning/parity/` are `source_type: parity_report` source references (artifact id = `scenario_id`) → linkable without manifest binding | `scripts/build_project_status.py` |
| BRD-F-08 | Single server-side latest-run rule `select_latest_run` (current over historical, newest capture, deterministic tie-break); `/api/gallery` returns `latest_runs`; client only looks up | `scripts/serve_project_board.py`, `.mxagile/board/board.js` |

No schema change (HEAD/branch live in `commit_range`, which allows additional properties; `parity_report` already existed). No canonical data change. `source_fingerprint` unchanged for identical sources (verified on CapTrack snapshot).

## 2. Tests (written; red proof on unmodified HEAD, green on CS-1)

| Test | Red on HEAD (`git archive`) | Green |
|---|---|---|
| `test_board_http.BoardCorrectnessCs1Tests.test_reconciliation_placeholder_carries_observed_head_and_branch` | KeyError `to_commit` | ✓ |
| `…test_placeholder_without_git_reports_no_head_instead_of_failing` (also: HEAD probe only on `/api/status`, not on asset routes) | missing `git_head_and_branch` | ✓ |
| `…test_page_previews_exclude_standalone_interaction_artifacts` | 3 pages ≠ 2 | ✓ |
| `…test_parity_report_without_manifest_binding_is_a_linkable_source` | HTTP 404 | ✓ |
| `…test_latest_run_rule_is_single_and_server_side` | missing `select_latest_run` | ✓ |
| `…test_board_client_contract_for_cs1_corrections` (static client contract F-01/03/04/08) | substring not found | ✓ |
| `test_external_change_reconciliation…test_report_without_baseline_still_exposes_observed_head` | KeyError `from_commit` | ✓ |

## 3. Validation gate

| Gate | Result |
|---|---|
| Impact selection (`--list --paths`, 6 changed paths) | tier 3, unmapped: none; suites: `test-board-authority.ps1`, `test-core-provenance.ps1`, `test-injection-contract.ps1`, `test_board_http.py`, `test_board_performance.py`, `test_external_change_reconciliation.py`, `test_parity_gallery.py`, `test_project_status.py` |
| **Fast Gate** | **PASS** (0.33 s) |
| **Impact Regression (Tier 3)** | **PASS** (608.65 s; 184 Python tests OK; PowerShell suites FAIL: 0) |
| Full Release Gate | **NOT RUN** — not required (no unmapped path, no installer/test-runner change) |

`test-reconciliation-board.ps1` (named in the contract) was not selected by the impact runner; it only re-runs three suites that were all part of this gate.

## 4. CapTrack reality check (read-only)

Live CapTrack `dev/gb` @ `d10a168b` (heavy parallel foreign activity: HEAD moved from `6d8923dc`, model files saved during the run):

| RC | Before (baseline.md) | After CS-1 |
|---|---|---|
| RC-01 | placeholder without HEAD → "BASELINE REQUIRED / HEAD UNKNOWN" | placeholder `to_commit d10a168b…`, `branch_ref refs/heads/dev/gb` |
| RC-02 | 11 page previews | 10 page previews, standalone excluded |
| RC-03 | 0 `parity_report` references; parity source 404 | 11 `parity_report` references; parity source **200** |

CapTrack `git status` before/after: only `.mxunit`/`.mpr` changes from the parallel Studio Pro session; no file touched by the Board (read-only server, `python -B`, `git --no-optional-locks`).

**UI evidence (Playwright, OS temp only):**
- CapTrack snapshot `d10a168` with CS-1 `board.js`: drift section shows `LÄDT … · CURRENT HEAD d10a168b5116 · BRANCH dev/gb · LAST RECONCILED lädt …` (before: "BASELINE REQUIRED / HEAD UNKNOWN", see first-inspection screenshot `overview.png`).
- Embedded fixture, CS-1 `board.js`: 0 page errors, 0 console errors; drift `LÄDT …` → after load `BASELINE REQUIRED` with HEAD (fixture truly has no watermark); UI & Pages 2 cards (standalone excluded), parity `NICHT GELADEN` → `NOT_VERIFIED` after lazy gallery load; `#finding/FIND-001` (terminal) opens; `#wave/W1` shows `MISSION BLOCKERS (MISSIONSWEIT) NICHT ERFASST`.
- The full UI & Pages screenshot on the CapTrack snapshot was not captured: the measurement script used Playwright `wait_for_function`, which the Board's strict CSP (`script-src 'self'`, no `unsafe-eval`) correctly blocks; RC-02 is evidenced by API (10 previews) and the unit test instead.

## 5. Performance (contract: ±10 %)

Live CapTrack timings are dominated by the unchanged signature walk (3.8–13.3 s per request under churn) and two 503s from pre-existing BRD-F-11 (sources changed during build) — not comparable with the baseline. Controlled comparison on a frozen shallow snapshot (`d10a168`, OS temp), old (`git archive HEAD`) vs. CS-1, alternating:

| Path | Old | CS-1 |
|---|---|---|
| `build_status_summary` stage profile (same round) | Σ 1.39 s / 2.27 s | Σ 1.34 s / 2.68 s |
| `build_page_previews` median | 0.103 s | 0.102 s |
| HEAD probe (`/api/status` only) | — | 0.12 s |
| `source_fingerprint` | identical | identical |

Per-stage medians match within run-to-run noise caused by the parallel machine load; the only added work is 11 source references from already-hashed files plus the 0.12 s probe on `/api/status`. Assessment: **no CS-1-attributable regression beyond measurement noise; the strict ±10 % proof is not achievable on this machine under the current concurrent load** (reported as such, not as PASS).

## 6. New findings / observations

- **BRD-F-37 (gate/process):** New test fixtures, new test modules and `specs/` are unmapped in `tests/run-impact-tests.py` → Full Release Gate per CLAUDE.md. CS-1 embedded its fixture in a mapped test module (T005 adapted, T006 deferred). Affects CS-2 (T006/T028) and the commit of Spec Kit artifacts.
- **BRD-F-38 (projection, minor):** `findings.history` items omit `title` (the board falls back to "Historical finding"). Candidate for CS-3/CS-4.
- **BRD-F-39 (environment):** Board server on a fresh clone in OS temp is ~3× slower than on the live project (likely real-time scanning of new files) — relevant for CS-2/CS-7 measurement design (measure on stable, non-temp locations or warm the snapshot first).
- **Observation:** Foreign activity in the framework repo during CS-1: `tests/temp-project/` and `.vscode/tasks.json` disappeared (not caused by the CS-1 gate; `test-init-idempotency.ps1` was not selected).

## 7. Commit

- `f38b0c8 fix(board): CS-1 correctness fixes (BRD-F-01..08)` — exactly the 6 CS-1 paths (`.mxagile/board/board.js`, `scripts/{build_project_status,reconcile_external_changes,serve_project_board}.py`, `tests/test_board_http.py`, `tests/test_external_change_reconciliation.py`); identity `Zwergomaniac <Keeperdeluxe@web.de>` verified; explicit staging.
- Not committed (unmapped → would require Full Release Gate, BRD-F-37): `specs/001-board-redesign/` (incl. this report), `docs/board-redesign-*.md` (mapped Tier 1, but outside the CS-1 boundary).
- Foreign commit `c74382e` (owner, 20:21) landed during the CS-1 gate run and committed the pre-existing policy changes → **CS-0 prerequisite (T058) is now satisfied**.

## 8. Approval status

STOP. Waiting for explicit approval of CS-2. Successful CS-1 completion is not an authorization for CS-2.
