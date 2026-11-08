---
description: "Task list for MxAgile Dev Board Redesign (CS-1 → CS-2 → CS-7 → CS-0 → CS-3 → CS-4 → CS-5 → CS-6)"
---

# Tasks: MxAgile Dev Board Redesign

**Input**: `specs/001-board-redesign/` — spec.md, plan.md, research.md, data-model.md, contracts/, quickstart.md
**Authority**: `docs/board-redesign-implementation-contract.md` (binding), `docs/board-redesign-plan.md`, `docs/board-redesign-findings.md`

**Tests**: Required — the gate contract (`contracts/changeset-gates.md`) demands specific tests per changeset. Tests are written first in each phase and must fail before implementation where they cover new behavior.

**Organization**: One phase per changeset in the binding sequence. Story labels: US1=CS-1, US2=CS-2, US3=CS-7, US4=CS-0, US5=CS-3, US6=CS-4, US7=CS-5, US8=CS-6. Every changeset phase ends with **Gate → Commit → STOP**. No task of a later phase starts before the explicit approval recorded in the previous STOP task.

**Global rules (apply to every task)**: read-only Board; no writes into analyzed projects; CapTrack (`D:\MTC\Mendix\Projekte\CapTrack\CapTrack-devrick`) read-only only (`python -B`, `PYTHONDONTWRITEBYTECODE=1`, `git --no-optional-locks`); never `git add -A`/`.`; commit identity must be `Zwergomaniac <Keeperdeluxe@web.de>`; do not touch files carrying pre-existing foreign uncommitted changes; Full Regression only where stated.

## Format: `[ID] [P?] [Story] Description`

---

## Phase 1: Setup — Pre-Flight & Ownership (no code, no commit)

**Purpose**: Protect pre-existing foreign work; establish the gate baseline.

- [x] T001 Record `git status --porcelain` of the framework repo into `specs/001-board-redesign/preflight.md` (section "Foreign uncommitted changes"), listing at least `.mxagile/policies/{agent-delegation,implementation-control,lifecycle-resync,test-workflow}.md`, `.mxagile/skills/gate-to-ready.md`, `CLAUDE.md`, `docs/context-architecture-baseline.md`, `scripts/apply-project-agent-instructions.ps1`, `tests/test-{agent-delegation,architecture-drift-prevention,lifecycle-resync,runtime-orchestration,startup-priority}.ps1`, `.vscode/tasks.json` as owned by others
- [x] T002 For every changeset, cross-check its planned file list (plan.md "Changeset-Architektur") against T001 and record in `specs/001-board-redesign/preflight.md` which changesets are blocked by foreign changes (expected: CS-0 blocked until `lifecycle-resync.md` and `implementation-control.md` are committed by their owner; CS-7/CS-5 must not touch the foreign-modified `CLAUDE.md`)
- [x] T003 Verify commit identity via `git var GIT_AUTHOR_IDENT` and `git var GIT_COMMITTER_IDENT`; record result in `specs/001-board-redesign/preflight.md`; STOP and ask the maintainer if it differs from `Zwergomaniac <Keeperdeluxe@web.de>`

---

## Phase 2: Foundational — Baseline & Shared Fixture (blocks all changesets)

**Purpose**: Measurable before/after reference and a reusable fixture; committed together with CS-1 (first commit boundary).

- [x] T004 Capture CapTrack read-only baseline with `MXAGILE_BOARD_PROFILE=1` (framework `scripts/serve_project_board.py --project-root <CapTrack> --port 8797`, curl timings per quickstart.md, record HEAD) into `specs/001-board-redesign/baseline.md`; stop the server afterwards and confirm CapTrack `git status` unchanged (background invalidation cost target ≤ 1 s is measured again in T040)
- [x] T005 [P] **(adapted, see note)** Create fixture project `tests/fixtures/board-redesign/project/` containing: `mxagile-project.yaml`, `.mxagile/version.yaml`, `planning/lifecycle/process-state.yaml` (one `done` wave with an open task, one `implementing` wave), 3 requirements, 4 tasks (one `type: repair`), 2 decisions (one PROPOSED with `affected_screens`), 1 finding (terminal), 1 standalone `interaction-states-*.yaml` in `planning/ui-inventory/`, 2 pages (one with `html_source` under `themesource/x/public/y/`), 1 parity report without `comparison_identity`, `planning/revisions/REV-002.yaml` with `active_target: true`
- [x] T006 [P] **(done in CS-2 inside `tests/test_external_change_reconciliation.py`, see note)** Create fixture helper `tests/fixtures/board-redesign/make_fixture_repo.py` that copies the fixture project to a temp dir and builds a deterministic synthetic Git history (fixed author/date env vars): linear commits, one merge, one commit with `MxAgile-Mission`/`MxAgile-Change-Set` trailers plus a schema-valid change-set, one schema-invalid change-set, one commit touching only `mprcontents/`, one commit only mentioning `REQ-001` in its message

**Checkpoint**: Baseline recorded; fixture available. Neither is committed alone — both land with CS-1.

**CS-1 execution notes (2026-11-05):**
- T005 adapted: the fixture is embedded as `BOARD_FIXTURE_FILES` / `write_board_fixture()` in `tests/test_board_http.py` instead of `tests/fixtures/board-redesign/`. Reason: new paths under `tests/fixtures/board-redesign/` and new test modules are **unmapped** in `tests/run-impact-tests.py`; per CLAUDE.md unmapped paths force the Full Release Gate, and adding a mapping is a test-runner change (also Full Gate). Embedding keeps CS-1 within its contracted gate. Revisions-ledger/decision/repair-task content of the original T005 list is not needed by CS-1 and moves with the CS-4 tests.
- T006 deferred to CS-2 (first consumer: reconciliation equivalence test T028). The same mapping constraint applies there: implement the helper inside `tests/test_external_change_reconciliation.py` or accept the Full Release Gate for CS-2.
- T011 placed in `tests/test_board_http.py` (`test_latest_run_rule_is_single_and_server_side`) instead of `tests/test_parity_gallery.py`; same coverage, both modules are mapped.


---

## Phase 3: CS-1 — Board shows nothing false (US1, Priority P1) 🎯 MVP

**Goal**: Remove the misleading displays BRD-F-01…08. **Independent Test**: fixture + CapTrack RC-01…03.
**Excluded**: new views, state vocabulary, performance changes, layout changes, canonical/schema changes.

### Tests (write first, must fail)

- [x] T007 [P] [US1] Add test in `tests/test_board_http.py`: `/api/status` reconciliation placeholder renders as loading — assert `board.js` `renderProjectDrift` path no longer emits "BASELINE REQUIRED"/"UNKNOWN" for `availability: not_loaded` (DOM-free check via served JS + status JSON contract: placeholder carries `head`/`branch`)
- [x] T008 [P] [US1] Add test in `tests/test_external_change_reconciliation.py`: `build_report` without watermark returns `commit_range.to_commit == head` (BRD-F-02)
- [x] T009 [P] [US1] Add test in `tests/test_board_http.py`: page-previews item count equals status page count for fixture with standalone interaction artifact (BRD-F-05)
- [x] T010 [P] [US1] Add test in `tests/test_board_http.py`: `GET /source/planning/parity/<report>.yaml` returns 200 for fixture parity report (BRD-F-07)
- [x] T011 [P] [US1] Add test in `tests/test_parity_gallery.py`: one server-side "latest run" rule (max `captured_at`, current before historical) is exposed in page-previews and used unchanged by the client contract (BRD-F-08)

### Implementation

- [x] T012 [US1] In `scripts/serve_project_board.py::_status`, add cheap `head` and `branch` (single `git rev-parse HEAD` / `symbolic-ref`, `--no-optional-locks`) to the reconciliation placeholder; keep `availability: not_loaded`
- [x] T013 [US1] In `.mxagile/board/board.js::renderProjectDrift`, render `not_loaded`/loading as "LÄDT" with HEAD/branch; never map missing `from_commit` to "BASELINE REQUIRED" while not loaded (BRD-F-01)
- [x] T014 [US1] In `scripts/reconcile_external_changes.py::build_report`, set `commit_range = {"status": report["status"], "to_commit": report["head"], "commits": [], "spans": []}` when no watermark exists (BRD-F-02)
- [x] T015 [P] [US1] In `.mxagile/board/board.js::renderDetail` (kind `finding`), resolve from `status.findings.items` and `status.findings.history` (BRD-F-03)
- [x] T016 [P] [US1] In `.mxagile/board/board.js::renderDetail` (kind `wave`), remove the fabricated "MISSION BLOCKERS 0"; show `countText(null)`-style "nicht erfasst" when `status.mission.availability` is not available (BRD-F-04)
- [x] T017 [US1] In `scripts/serve_project_board.py::build_page_previews`, skip paths where `project_compatibility.is_standalone_interaction_artifact(relative)` is true (BRD-F-05)
- [x] T018 [US1] In `scripts/build_project_status.py::build_source_references`, include `planning/parity/*.yaml` as `source_type: parity_report` (already allowed by schema) (BRD-F-07)
- [x] T019 [US1] Move the latest-run selection into a single function in `scripts/serve_project_board.py` used by `build_page_previews` and returned as `latest_run_id` in gallery items; replace `updatePageEvidence` selection in `.mxagile/board/board.js` with that server value; UI & Pages shows "nicht geladen" (no value) until gallery data exists (BRD-F-06, BRD-F-08)

### Gate → Commit → STOP

- [x] T020 [US1] Run `python tests/run-impact-tests.py --list --paths scripts/serve_project_board.py scripts/reconcile_external_changes.py scripts/build_project_status.py .mxagile/board/board.js tests/...`; then Fast Gate; then Impact Regression incl. Tier 3 suites `test_external_change_reconciliation.py`, `test-core-provenance.ps1`, `test-injection-contract.ps1` (plan.md A1); record Fast/Impact separately in `specs/001-board-redesign/reports/cs-1.md`
- [x] T021 [US1] CapTrack read-only RC-01…03 check (Overview drift, page count 10, parity source 200) with before/after screenshots stored under OS temp and referenced in `specs/001-board-redesign/reports/cs-1.md`; profile timings within ±10 % of `baseline.md`
- [x] T022 [US1] Commit only CS-1 files + Phase 2 fixture/baseline (explicit `git add -- <paths>`), identity verified, message `fix(board): CS-1 correctness fixes (BRD-F-01..08)` with required attribution trailer — **done: `f38b0c8`**
- [x] T023 [US1] **STOP CS-1** — report diff summary, gates, RC results; wait for explicit approval of CS-2 (record approval status in `specs/001-board-redesign/reports/cs-1.md`)

---

## Phase 4: CS-2 — Board behaves like a local dashboard (US2, Priority P1)

**Goal**: No interactive full scans; no startup 503; reconciliation ≤ 10 s. **Independent Test**: SC-001…004 on CapTrack + equivalence test.
**Excluded**: new partial endpoints (CS-6), timeline (CS-5), UI changes except projection age; no change to `install-core.ps1` (research R-02).

### Tests (write first)

- [x] T024 [P] [US2] Extend `tests/test_board_performance.py`: asset request (`/source`, `/reference`, `/capture`) performs no signature computation (patch counter on signature function == 0 after warm-up)
- [x] T025 [P] [US2] Extend `tests/test_board_performance.py`: same-mtime content edit still invalidates (keep P3b green) and size-change detection without full walk
- [x] T026 [P] [US2] Extend `tests/test_board_performance.py`: source change during build → no 503; response carries `projection.state` `STALE` or `FRESH`; 503 only when no last-good exists and build fails (`PROJECTION_ERROR`)
- [x] T027 [P] [US2] Add test in `tests/test_board_performance.py`: project tree unchanged after server lifecycle (stat + `git status --porcelain` before/after, `MXAGILE_BOARD_CACHE_DIR` pointing to temp)
- [x] T028 [P] [US2] Add reconciliation equivalence test in `tests/test_external_change_reconciliation.py` using `tests/fixtures/board-redesign/make_fixture_repo.py`: old path vs batched path produce JSON-identical `commit_range` (commits, paths, classifications, spans)

### Implementation

- [x] T029 [US2] In `scripts/serve_project_board.py`, add cache-dir resolution (`%LOCALAPPDATA%\mxagile\board-cache\<repository_identity>\<branch_key>` / `${XDG_CACHE_HOME:-~/.cache}/...`, override `MXAGILE_BOARD_CACHE_DIR`, atomic temp+replace writes, in-memory fallback with `projection.reason = CACHE_UNAVAILABLE`) (research R-03)
- [x] T030 [US2] In `scripts/serve_project_board.py`, replace per-request `source_metadata_signature` with a background invalidation thread (≤ every 2 s): Git HEAD, index stat, branch ref, per-collection directory listing (name, `mtime_ns`, size), `*.mpr` stat, `git rev-parse HEAD:mprcontents` + `git status --porcelain=v1 -z --untracked-files=no -- mprcontents *.mpr`; no walk of `mprcontents/` (research R-01; BRD-F-10)
- [x] T031 [US2] In `scripts/serve_project_board.py`, serve all asset routes against the current snapshot allowlist without recomputation (FR-020)
- [x] T032 [US2] In `scripts/serve_project_board.py::ProjectStatusCache`, implement stale-while-revalidate with `last-good.json`, 3 retries with 0.5/1/2 s backoff on `*_SOURCES_CHANGED_DURING_*`, `projection{state, age_seconds, reason, built_at_head}` (data-model §1: `state ∈ FRESH | STALE | BUILDING | PROJECTION_ERROR`) (research R-04; BRD-F-11)
- [x] T033 [US2] Add `projection` object to `.mxagile/schemas/project-status.schema.json` (root `additionalProperties: false` → required in same commit, plan.md A2)
- [x] T034 [US2] In `scripts/reconciliation_git.py`, replace per-commit subprocesses with one `git log --raw -z --no-renames` and one `git cat-file --batch` process; keep `classify_path` semantics (research R-05; BRD-F-24)
- [x] T035 [US2] In `scripts/reconcile_external_changes.py::build_report`, accept the existing status snapshot (no second `build_status`), cache result per (HEAD, watermark commit, worktree status hash), cache mxcli capability probe per binary stat
- [x] T036 [US2] In `scripts/project_compatibility.py::compatibility_report`, cache per-document results keyed by (path, sha256, schema fingerprint, rule version); cross-file checks recomputed on cached results (research R-06)
- [x] T037 [US2] Add `MXAGILE_BOARD_LEGACY_CACHE=1` fallback to previous per-request behavior in `scripts/serve_project_board.py` (one release)
- [x] T038 [US2] Show projection age/state in `.mxagile/board/board.js` footer (`#updated-label`) and the global header

### Gate → Commit → STOP

- [x] T039 [US2] `run-impact-tests.py --list` for changed paths; Fast Gate; Impact Regression Tier 3 (board, reconciliation, schema suites); confirm `install-core.ps1` unchanged (else escalate to Full Release Gate); record in `specs/001-board-redesign/reports/cs-2.md`
- [x] T040 [US2] CapTrack read-only measurement per quickstart.md: warm view ≤ 300 ms, link ≤ 200 ms, first paint ≤ 3 s with last-good / ≤ 6 s cold, reconciliation (current range, note commit count) ≤ 10 s, background invalidation cycle ≤ 1 s, 20 restarts under parallel file change on fixture with 0 startup errors; record in `reports/cs-2.md`
- [x] T041 [US2] Commit CS-2 files only (identity verified), message `perf(board): CS-2 snapshot serving, background invalidation, batched reconciliation`
- [x] T042 [US2] **STOP CS-2 (reached; CS-7 NOT authorized)** — report measurements before/after and equivalence proof; wait for approval of CS-7 (record approval status in `specs/001-board-redesign/reports/cs-2.md`)

---

## Phase 5: CS-7 — Bounded Doctor board smoke (US3, Priority P1)

**Goal**: Optional smoke, PASS/FAIL/UNAVAILABLE/TIMEOUT, ≤ 15 s, hard 60 s (OD-4). **Independent Test**: fixture runs incl. negative cases.
**Excluded**: default Doctor stays browser-free; no Mendix runtime, no visual parity, no crawling, no regression suites, no browser installation; reconciliation only with `--include-reconciliation`.

### Tests (write first)

- [x] T043 [P] [US3] Create `tests/test_board_smoke.py`: PASS on fixture (browser available) or UNAVAILABLE (no browser) — never PASS without browser; `project_unchanged: true`
- [x] T044 [P] [US3] In `tests/test_board_smoke.py`: injected JS error in a fixture copy of `board.js` → `FAIL`, screenshot only under OS temp, exit code 1
- [x] T045 [P] [US3] In `tests/test_board_smoke.py`: artificially delayed server → `TIMEOUT` within 60 s, no leftover process, port free, exit code 3
- [x] T046 [P] [US3] Add PowerShell test (extend `tests/test-local-updater.ps1` or new `tests/test-board-smoke-offer.ps1`): non-interactive `install-core.ps1` run never starts the smoke and reports `Board Smoke: NOT RUN (non-interactive)`

### Implementation

- [x] T047 [US3] Add `--port 0` support to `scripts/serve_project_board.py::main` (free port; ready line unchanged) (research R-08)
- [x] T048 [US3] Create `scripts/board_smoke.py` with stages S0–S6 and budgets per `contracts/board-smoke-result.md`; process group start/terminate/kill; monotonic 60 s deadline; `route_list_version: 1` with routes `portfolio, overview, waves, requirements, verification, gallery, ui-pages, findings, decisions` (plan.md A5)
- [x] T049 [US3] In `scripts/board_smoke.py`, browser detection order Python-playwright → `playwright-cli` subprocess → none (`MXAGILE_BOARD_SMOKE_BROWSER=none` forces none); no installation (research R-07)
- [x] T050 [US3] In `scripts/board_smoke.py`, S6 consistency values per research R-08 (health chip reported `NOT_APPLICABLE` until CS-3), result JSON per contract, exit codes 0/1/2/3
- [x] T051 [US3] Add `--board-smoke` flag to `scripts/project_compatibility.py doctor` (runs smoke after Doctor; Doctor exit-code contract 0/1/2 unchanged; smoke reported separately)
- [x] T052 [US3] In `scripts/install-core.ps1`, distribute `board_smoke.py` to `.mxagile/tools/` and add it to the provenance list; after successful Doctor, offer the smoke only when interactive (default No); non-interactive/CI → `NOT RUN (non-interactive)`
- [x] T053 [US3] Map `scripts/board_smoke.py` and `tests/test_board_smoke.py` in `tests/run-impact-tests.py` impact rules (test-runner change → Full Release Gate)

### Gate → Commit → STOP

- [x] T054 [US3] Fast Gate; Tier 2 smoke tests; **Full Release Gate** (installer + test-runner change, plan.md A3); record Fast/Impact/Full separately in `specs/001-board-redesign/reports/cs-7.md`
- [x] T055 [US3] CapTrack read-only smoke run (`python -B scripts/board_smoke.py --project-root <CapTrack> --format json`): ≤ 15 s, PASS or UNAVAILABLE, `project_unchanged: true`; record
- [x] T056 [US3] Commit CS-7 files only (must not include foreign-modified `CLAUDE.md`), message `feat(doctor): CS-7 bounded board smoke (--board-smoke)`
- [x] T057 [US3] **STOP CS-7 (reached; CS-0 NOT authorized)** — report run logs and Full-Gate result; wait for approval of CS-0 (record approval status in `specs/001-board-redesign/reports/cs-7.md`)

---

## Phase 6: CS-0 — Lifecycle clarification OD-3 (US4, Priority P2)

**Goal**: R1–R6 from plan K.4 / `contracts/lifecycle-rules-cs0.md`. **Independent Test**: schema/Doctor fixtures; CapTrack Doctor read-only 0 new blockers.
**Excluded**: new entity, Markdown parsing of `execution-waves.md`, automatic project migration, Board changes, repair.

- [x] T058 [US4] **Pre-flight gate**: confirm via `git status` / `git log -1 -- <file>` that `.mxagile/policies/lifecycle-resync.md` and `.mxagile/policies/implementation-control.md` carry no foreign uncommitted changes (owner has committed them); otherwise STOP and ask the owner — do not stage, revert or rewrite them

### Tests (write first)

- [x] T059 [P] [US4] Extend `tests/test-negative-schema.ps1` (or `tests/test_project_status.py`): process-state without new gates valid; with `testability_gate` valid; `acceptance_gate.result: pending` valid; `gate_to_ready.result: pending` invalid
- [x] T060 [P] [US4] Add Doctor fixtures in `tests/test_project_status.py` (or new `tests/test_doctor_lifecycle.py`): `CHANGE_SET_SCHEMA_INVALID` (WARNING, `blocking: false`), `DONE_BASIS_NOT_RECORDED` (INFO), `ACTIVE_REVISION_UNBOUND` (WARNING); compatibility state never changes to BLOCKED because of them

### Implementation

- [x] T061 [US4] In `.mxagile/schemas/process-state.schema.json`, add optional `gates.testability_gate` (`gate_result`) and `gates.acceptance_gate` (`acceptance_gate_result`: `result ∈ {not_recorded, passed, failed, pending}`, `evaluated`, `evidence`, optional `pending_decisions: [{id, text}]`); keep `gates.required = [gate_to_refinement, gate_to_ready]` (R4, BRD-F-30)
- [x] T062 [P] [US4] In `.mxagile/lifecycle.yaml`, correct header comment and `state_tracking.file` to `planning/lifecycle/process-state.yaml` (local cache remains supplementary) and align `required_gate_keys` wording with the schema (R5, BRD-F-31)
- [x] T063 [P] [US4] In `.mxagile/GLOSSARY.yaml`, add terms Mission, Workpackage (optional label, no lifecycle), Acceptance Campaign (verification run inside `verifying`), GAP (= Finding), Repair Task (`type: repair`), Change-Set (commit provenance, not a work container) (R5, BRD-F-35)
- [x] T064 [US4] In `.mxagile/policies/gap-verification-repair.md` § Relation to Acceptance Gate, clarify: rule applies while the affected wave is not `done`; after `done`, remediation is a repair task in a new wave; link via `Finding.wave_id` (affected) → `repair_task_id` → `Task.wave_id` (executing) (R2, BRD-F-32)
- [x] T065 [US4] In `.mxagile/policies/implementation-control.md` § Mission Decomposition (on top of the owner-committed text), add R2 (work after DONE → new wave, LOCAL allowed) and R3 (register wave in `process-state.yaml` at authorization: `phase: discovery`, gates `not_recorded`) (BRD-F-33)
- [x] T066 [US4] In `.mxagile/policies/lifecycle-resync.md`, add R1 (DONE wave never reopened; scoped `completion_override`) and reference R3 under `NOT_STARTED`
- [x] T067 [US4] In `scripts/project_compatibility.py`, add change-set contract validation and the three diagnostics from `contracts/lifecycle-rules-cs0.md` (non-blocking, no repair, no Markdown parsing) (R6, BRD-F-34)
- [x] T068 [US4] If any canonical skill/agent under `.mxagile/skills/` or `.mxagile/agents/` needs the R1–R3 wording, edit only the canonical source and regenerate projections via `scripts/generate-mxagile-platform-skills.ps1`; never edit generated projections manually

### Gate → Commit → STOP

- [x] T069 [US4] `run-impact-tests.py --list`; Fast Gate; Impact Regression Tier 2 (`test-injection-contract.ps1`, `test-negative-schema.ps1`, `test_project_status.py`, `test-documentation-consistency.ps1`, `test-ui-parity.ps1`, `test-verification-lifecycle.ps1`, `test-lifecycle-resync.ps1`, `test-architecture-drift-prevention.ps1`, projection tests if T068 ran); Full Release Gate only if `unmapped` is reported; record in `reports/cs-0.md`
- [x] T070 [US4] CapTrack read-only `doctor --format json` (framework script against CapTrack root): new INFO/WARNING diagnostics as expected (RC-06), 0 new blocking, runtime +≤ 10 %; record
- [x] T071 [US4] Commit CS-0 files only, message `feat(lifecycle): CS-0 clarify post-DONE work, wave registration, acceptance gates (OD-3)`
- [x] T072 [US4] **STOP CS-0** — present policy diff + CapTrack Doctor JSON; **explicit approval required (agent behavior changes)** before distribution and before CS-3 (record approval status in `specs/001-board-redesign/reports/cs-0.md`)

---

## Phase 7: CS-3 — Observation states & separation (US5, Priority P2)

**Goal**: Closed vocabulary; attention vs. health vs. diagnostics. **Independent Test**: fixture with all states; CapTrack mapping old → new.
**Excluded**: new data sources, timeline, navigation rework except the Health view; no state is hidden.

### Tests (write first)

- [x] T073 [P] [US5] Create `tests/test_board_states.py`: every projected area has exactly one `observation_state` from `{AVAILABLE, EMPTY, NOT_RECORDED, NOT_LOADED, LOADING, STALE, INVALID, UNSUPPORTED, NOT_OBSERVABLE, NOT_APPLICABLE, AMBIGUOUS, PROJECTION_ERROR}`; missing `planning/findings/` → NOT_RECORDED; empty dir → EMPTY; all-invalid dir → INVALID
- [x] T074 [P] [US5] In `tests/test_board_states.py`: unconditional gaps map to NOT_OBSERVABLE and never appear in `project_attention`; `UNASSIGNED` workpackage diagnostics in `optional_metadata`
- [x] T075 [P] [US5] Schema snapshot test in `tests/test_project_status.py` for `schema_version: 3` additive fields; v2 `availability` fields still present

### Implementation

- [x] T076 [US5] In `scripts/build_project_status.py::read_collection`, distinguish missing directory (NOT_RECORDED), empty (EMPTY) and all-invalid (INVALID) while keeping legacy `availability` values (research R-09; BRD-F-23)
- [x] T077 [US5] In `scripts/build_project_status.py::_build_status`, attach `observation_state` per area and classify unconditional gaps (`MODEL_FRESHNESS_`, `PROJECT_ID_`, `OPERATING_MODE_`, `CAPABILITY_SESSION_`, `CONTEXT_SESSION_`, `MULTI_SOURCE_UNAVAILABLE`) as NOT_OBSERVABLE (BRD-F-21, BRD-F-20 stays NOT_OBSERVABLE until CX-A)
- [x] T078 [US5] In `scripts/project_compatibility.py`, add `diagnostic_group` per diagnostic per data-model §2 mapping (BRD-F-22)
- [x] T079 [US5] Update `.mxagile/schemas/project-status.schema.json`: `schema_version` 3, `observation_state`, `diagnostic_group`, root `health`
- [x] T080 [US5] Add `/api/health` in `scripts/serve_project_board.py` per `contracts/board-http-api.md`
- [x] T081 [US5] In `.mxagile/board/board.js`/`index.html`/`styles.css`: global health chip; Health & Diagnostics view; project context block and compatibility panel only on Overview/Health; render each observation state with its explanation; v2/v3 feature detection
- [x] T082 [US5] Update smoke route list to version 2 (add `health`) in `scripts/board_smoke.py`; S6 health-chip value now checked

### Gate → Commit → STOP

- [x] T083 [US5] Fast Gate; Impact Regression Tier 2; smoke on fixture; status build time +≤ 10 % vs. `reports/cs-2.md`; record in `reports/cs-3.md`
- [x] T084 [US5] CapTrack read-only: produce mapping table old → new (RC-07, RC-08) in `reports/cs-3.md`
- [x] T085 [US5] Commit CS-3 files only, message `feat(board): CS-3 observation states and attention/health/diagnostics separation`
- [x] T086 [US5] **STOP CS-3** — present mapping table for PO review; wait for approval of CS-4 (record approval status in `specs/001-board-redesign/reports/cs-3.md`)

---

## Phase 8: CS-4 — Current Work, delivery assessment, DONE trust, projections (US6, Priority P2)

**Goal**: FR-060…069. **Independent Test**: rule fixtures + CapTrack RC-09…13.
**Excluded**: timeline view, navigation rework, Page Hub, heuristic assignment, writing back any assessment.

### Tests (write first)

- [ ] T087 [P] [US6] Create `tests/test_board_projections.py`: Current Work cascade cases ACTIVE (mission), ACTIVE/BLOCKED (registered wave), NOT_STARTED, NONE + `unattributed_activity.observed` true/false, CONFLICT (`active_wave` points to `done` wave); never assigns observed commits to a wave
- [ ] T088 [P] [US6] In `tests/test_board_projections.py`: Delivery Assessment `delivery-assessment/v1` — each level has ≥ 1 `evidence_ref` or ≥ 1 `reason`; `REPORTED_UNBOUND` never satisfies verification; `derived: true`
- [ ] T089 [P] [US6] In `tests/test_board_projections.py`: wave trust — open tasks `superseded` only with `done_basis` RECORDED/LEGACY, else `open_tasks_unexplained`; parity reports without identity → `REPORTED_UNBOUND`; revision ledger `active_target` visible; implementation intent vs. fact mismatch flagged

### Implementation

- [ ] T090 [US6] In `scripts/build_project_status.py`, project mission/context fields (`objective`, `progress.*`, blocker details, `checkpoint_commits`, `terminal_guard_result`, `next_action`) (FR-069)
- [ ] T091 [US6] In `scripts/build_project_status.py`, add `current_work` per data-model §3 (`state ∈ ACTIVE | BLOCKED | NOT_STARTED | NONE | CONFLICT`, `derived: true`) and the "last DONE transition" Git query per research R-10 (single `git log -p` on process-state, ≤ 200 commits, cached per HEAD; NOT_OBSERVABLE without Git)
- [ ] T092 [US6] In `scripts/build_project_status.py`, add `delivery_assessment` per requirement per research R-11 / data-model §4
- [ ] T093 [US6] In `scripts/build_project_status.py`, add `waves_trust[]` per data-model §5 using `gates.acceptance_gate` (CS-0) (BRD-F-14)
- [ ] T094 [P] [US6] In `scripts/build_project_status.py`, extend decision items (`created_at`, `confirmed_at`, `rationale_excerpt`, `affected_screens`, `affected_mockup_revisions`) (BRD-F-19)
- [ ] T095 [P] [US6] In `scripts/build_project_status.py::build_active_targets`, read `planning/revisions/REV-*.yaml` ledger (`active_target`, `screens`, `acceptance_decisions`) as `authority_source: revision_ledger` (BRD-F-16)
- [ ] T096 [P] [US6] In `scripts/build_project_status.py`, add `verification.parity_reports[]` with `state ∈ COMPUTED | REPORTED_UNBOUND | STALE | NOT_VERIFIED` and reasons (BRD-F-15)
- [ ] T097 [P] [US6] In `scripts/serve_project_board.py::build_page_previews`, expose implementation `intent` (settings/override) and `fact` (resolvable `html_source`) with `mismatch` (BRD-F-17); expose non-canonicalized checklists (BRD-F-13)
- [ ] T098 [US6] Update `.mxagile/schemas/project-status.schema.json` for all CS-4 additive fields (`contracts/status-projection.md`)
- [ ] T099 [US6] In `.mxagile/board/board.js`, render Current Work card (incl. "Arbeit außerhalb des kanonischen Lifecycles beobachtet"), "Vertrauen in DONE", requirement assessment with "abgeleitet" badge + evidence links, decision details, revision ledger, parity "berichtet, nicht belegt", intent ≠ fact hint

### Gate → Commit → STOP

- [x] T100 [US6] Fast Gate; Impact Regression Tier 2; `/api/status` warm ≤ 300 ms, Git query ≤ 500 ms; record in `reports/cs-4.md`
- [x] T101 [US6] CapTrack read-only RC-09…13 (expect "Keine aktive kanonische Arbeit" + unattributed activity; REV-037 visible; 6 PASS/5 PARTIAL as REPORTED_UNBOUND; PAGE-ABTEILUNGSVERWALTUNG intent ≠ fact); record with HEAD
- [x] T102 [US6] Write rule text `delivery-assessment/v1` with CapTrack examples into `reports/cs-4.md`
- [x] T103 [US6] Commit CS-4 files only, message `feat(board): CS-4 current work, delivery assessment, DONE trust, canonical projections`
- [x] T104 [US6] **STOP CS-4** — PO acceptance of rule text (OD-1 condition); wait for approval of CS-5 (record approval status in `specs/001-board-redesign/reports/cs-4.md`)

---

## Phase 9: CS-5 — Evidence-based timeline (US7, Priority P3)

**Goal**: FR-070…076. **Independent Test**: synthetic Git fixture; determinism; no proximity assignment.
**Excluded**: live/harness telemetry (OD-2), persisted events in the project, proximity/branch/free-text assignment, semantic model diffs.

### Tests (write first)

- [x] T105 [P] [US7] Create `tests/test_project_timeline.py` using `tests/fixtures/board-redesign/make_fixture_repo.py`: authority classes per event; trailer + valid change-set → `COMMIT_TRAILER`; invalid change-set → event with `health: [CHANGE_SET_SCHEMA_INVALID]` and no attribution; message-only mention → `GIT_MENTION`, `lane: unattributed`
- [x] T106 [P] [US7] In `tests/test_project_timeline.py`: determinism (two builds → identical `event_id` sets); incremental build equals full build; rebase/force-push invalidates index; merge uses first parent; shallow history handled
- [x] T107 [P] [US7] In `tests/test_project_timeline.py`: negative test — commit adjacent in time to a wave transition but without evidence stays `unattributed`

### Implementation

- [x] T108 [US7] Create `.mxagile/schemas/project-timeline.schema.json` per `contracts/timeline-event.md` (derived, non-canonical)
- [x] T109 [US7] Create `scripts/build_project_timeline.py` (CLI + library) per research R-12: one `git log --raw -z --first-parent`, one `git cat-file --batch`, trailers, change-set validation, field diffs for status/phase/authority fields, artifact timestamps, all event types of plan D.2 incl. `delegation.completed` (delegation results), `changeset.recorded`, `mission.checkpoint`, `epoch.rollover`, `wave.gate_evaluated`, `reconciliation.performed`, `framework.updated` (`.mxagile/state/last-update-result.json`, `core-provenance.json`), `event_id` rule, index + cursor in OS cache (BRD-F-27; BRD-F-28 limits documented as NOT_RECORDED, not inferred)
- [x] T110 [US7] Add `/api/timeline` with filters/pagination in `scripts/serve_project_board.py` per `contracts/board-http-api.md`
- [x] T111 [US7] In `.mxagile/board/board.js`, add Timeline view (filters as URL params), Recent Activity (5) on Overview, entity timelines in detail views; no live telemetry
- [x] T112 [US7] In `scripts/install-core.ps1`, distribute `build_project_timeline.py` and the new schema; add to provenance list
- [x] T113 [US7] Map `scripts/build_project_timeline.py`, `.mxagile/schemas/project-timeline.schema.json`, `tests/test_project_timeline.py` in `tests/run-impact-tests.py`

### Gate → Commit → STOP

- [x] T114 [US7] Fast Gate; timeline tests; Impact; **Full Release Gate** (installer + test-runner, plan.md A3); record in `reports/cs-5.md`
- [x] T115 [US7] CapTrack read-only: initial build ≤ 10 s, incremental ≤ 1 s, `/api/timeline` ≤ 300 ms; RC-14 excerpt (events of 2026-11-05 with authority classes; CAP2 commits without trailer in `unattributed`)
- [x] T116 [US7] Commit CS-5 files only, message `feat(board): CS-5 evidence-based project timeline`
- [x] T117 [US7] **STOP CS-5** — present timeline excerpt; wait for approval of CS-6 (record approval status in `specs/001-board-redesign/reports/cs-5.md`)

---

## Phase 10: CS-6 — Information architecture & Page Hub (US8, Priority P3)

**Goal**: FR-080…084. **Independent Test**: PO walkthrough of 12 questions (plan J); smoke with route list v3.
**Excluded**: write functions, live telemetry, board-side image diffs, new canonical data.

### Tests (write first)

- [x] T118 [P] [US8] Extend `tests/test_board_http.py`: `/api/page/<PAGE-ID>` returns only that page's data per data-model §8; `/api/requirement/<REQ-ID>` includes traceability + assessment; unknown IDs → 404
- [x] T119 [P] [US8] Extend `tests/test_board_http.py`: old hash routes (`#gallery`, `#ui-pages`, `#page/<id>`) map to new routes; `#legacy/...` still served

### Implementation

- [x] T120 [US8] Add `/api/page/<PAGE-ID>` and `/api/requirement/<REQ-ID>` in `scripts/serve_project_board.py` (snapshot slices; captures for the selected page only, incl. previous run) (research R-13; page/builder-kit data moved under the status contract — BRD-F-09)
- [x] T121 [US8] Restructure navigation NOW / DELIVERY / QUALITY / SYSTEM in `.mxagile/board/index.html` and router in `.mxagile/board/board.js`; add Tasks list; merge Gallery + UI & Pages into "Pages & Parity"
- [x] T122 [US8] Implement Page Hub in `.mxagile/board/board.js`/`styles.css` (links: reference, design preview, HTML source, inventory source, parity source, runtime "aus Evidenz vom …"; parity reasons; captures current/previous; evidence state; page history; authority & builder kit) — screenshots never imply parity
- [x] T123 [US8] Overview layout per plan C.3 (Current Work, Braucht dich, Vertrauen in DONE, Recent Activity, compact Design Authority without fingerprints/authority-source lists on Overview — BRD-F-29, Delivery)
- [x] T124 [US8] Legacy router `#legacy/...` for one release in `.mxagile/board/board.js`
- [x] T125 [US8] Update smoke route list to version 3 in `scripts/board_smoke.py` (new IA routes + one Page Hub drilldown)

### Gate → Commit → STOP

- [x] T126 [US8] Fast Gate; Impact Tier 1–2; smoke on fixture with route list v3; route switch ≤ 500 ms, Page Hub ≤ 1 s; record in `reports/cs-6.md`
- [x] T127 [US8] CapTrack read-only PO walkthrough material: screenshots answering the 12 questions (plan J) incl. RC-15 Page Hub for `PAGE-ABTEILUNGSVERWALTUNG`; SC-008 assessment
- [x] T128 [US8] Commit CS-6 files only, message `feat(board): CS-6 information architecture and Page Hub`
- [x] T129 [US8] **STOP CS-6** — PO acceptance walkthrough; removal of legacy router requires a separate approval (record approval status in `specs/001-board-redesign/reports/cs-6.md`)

---

## Phase 11: Polish & Cross-Cutting (only after CS-6 approval)

- [ ] T130 [P] Update `docs/board-redesign-plan.md` / `docs/board-redesign-findings.md` status columns (BRD-F → fixed in CS-n) without changing architecture text
- [ ] T131 [P] Update `docs/architecture.md` Board section and `.mxagile/README.md` Board description to the new IA (canonical docs only)
- [ ] T132 Final cross-check spec SC-001…013 against `reports/cs-*.md`; list any unmet criterion explicitly (no implied PASS)

---

## Dependencies & Execution Order

```
Phase 1 (T001–T003) → Phase 2 (T004–T006)
  → CS-1 (T007–T023) ─STOP→ CS-2 (T024–T042) ─STOP→ CS-7 (T043–T057) ─STOP→
  CS-0 (T058–T072, requires owner commit of lifecycle-resync.md / implementation-control.md) ─STOP→
  CS-3 (T073–T086) ─STOP→ CS-4 (T087–T104) ─STOP→ CS-5 (T105–T117) ─STOP→ CS-6 (T118–T129) ─STOP→ Polish
```

Logical dependencies (for reordering requests only; binding sequence above stays):
- CS-1, CS-2, CS-7, CS-0: independently committable/reviewable (CS-2 merges after CS-1 due to shared `serve_project_board.py`; CS-0 after its prerequisite).
- CS-3 needs CS-1. CS-4 needs CS-3 + CS-0. CS-5 needs CS-2 + CS-3 (independent of CS-4). CS-6 needs CS-3 + CS-4 + CS-5.

## Parallel Opportunities

- Phase 2: T005 ‖ T006.
- Within each phase, all test tasks marked [P] (different test files/cases) can be written in parallel.
- CS-1: T015 ‖ T016 (separate functions in board.js — same file, sequence edits but independent logic).
- CS-0: T062 ‖ T063 (different files).
- CS-4: T094 ‖ T095 ‖ T096 ‖ T097 (independent projectors).
- No parallelism across changesets (STOP gates); no subagents without explicit mission permission (CLAUDE.md).

### Parallel Example: CS-4 (US6)

```text
Task: "T087 Current Work cascade tests in tests/test_board_projections.py"
Task: "T088 Delivery Assessment tests in tests/test_board_projections.py"
Task: "T094 Decision projection in scripts/build_project_status.py"
Task: "T095 Revision ledger projection in scripts/build_project_status.py::build_active_targets"
```

## Implementation Strategy

### MVP First (CS-1 only)

1. Phase 1 + Phase 2 (pre-flight, baseline, fixture).
2. CS-1 → Gate → Commit → **STOP and validate** (RC-01…03). This alone removes the misleading displays.

### Incremental Delivery

Each subsequent changeset adds value without breaking the previous one; every phase ends with its own gate, commit and STOP. CS-2 + CS-7 form the safety foundation (speed + regression net) before semantic changes (CS-0, CS-3, CS-4) and new views (CS-5, CS-6).

## Notes

- Tests marked [P] are written before the implementation of the same phase; they must fail first where they cover new behavior.
- Reports under `specs/001-board-redesign/reports/` document Fast/Impact/Full separately; NOT RUN ≠ PASS.
- Never touch CapTrack; never commit foreign changes; never run Full Regression outside T054/T114 (or when `unmapped` forces it).

## CS-2 execution notes (2026-11-06)

Evidence: `reports/cs-2.md`, raw benchmark `reports/cs-2-bench.json`. Deviations from this task list:
- T006/T028: Git fixture helper `build_reconciliation_history_fixture` lives in the mapped `tests/test_external_change_reconciliation.py` (no new test path).
- T029: cache key = sha256(project path) + sha256(branch ref) instead of Git repository identity (simpler, no extra Git queries); override `MXAGILE_BOARD_CACHE_DIR`; a cache path inside the project is refused.
- T030/T031: request path trusts a snapshot validated within a 5 s window and never blocks on a rebuild; a background thread revalidates (adaptive pacing, >= 2 s). `mprcontents/` is no longer walked inside a Git work tree (Git status covers it); the other roots keep the metadata walk, so same-mtime edits are still detected.
- T032: the Status-Schema field is `projection_state` (the root already has `projection: true`); last-good persistence covers the summary projection only.
- T035: mxcli capability probe is cached; a separate result cache for the reconciliation report was NOT added (wall time target met without it).
- T033: schema change is additive; `projection_state` is optional.
- T034 grew during validation: merge commits initially kept the per-path lookup (71 s on real history); fixed in the same changeset (6.9 s), result byte-identical to the old implementation.

## CS-7 execution notes (2026-11-06)

Evidence: `reports/cs-7.md`. Deviations from this task list (PO decisions of 2026-11-06 in parentheses):
- T049: Python Playwright only; no `playwright-cli`/Node assertion path (PO decision 2). No browser -> `UNAVAILABLE`.
- T043-T046: tests live in `tests/test_board_smoke.py` (+ wrapper `tests/test-board-smoke.ps1`, inventory entry, impact rules). T046 is covered by extending `tests/test-capability-discovery-routing.ps1` (U9 block) with the real installer in a non-interactive run and the offer function in isolation (CI, first install, explicit opt-in).
- T047: `--port 0` already worked; only the ready line was not flushed. Fixed with `flush=True`.
- T048/T050: result semantics PASS/FAIL/UNAVAILABLE/TIMEOUT/ERROR plus warnings; `--strict-project-unchanged` makes project modification a FAIL (fixtures), default is a WARNING with paths (live projects) (PO decision 3). Added `notes`, `timings`, `consistency`, `links_checked`.
- T051: Doctor exit codes 0/1/2 unchanged; exit 4 only for an explicitly requested smoke (FAIL/TIMEOUT/ERROR, or UNAVAILABLE with `--require-board-smoke`) (PO decision 4). The Doctor JSON gets a `board_smoke` object only when the flag is used; the installer never passes the flag.
- T052: the offer is a separate function (`Invoke-BoardSmokeOffer`) instead of a change inside `Invoke-PostUpdateCompatibility` (its output stream is parsed as one JSON object). Offered only after a Core update, only interactively and never in CI; `-BoardSmoke` is the explicit opt-in. The installer exit code never depends on the smoke.
- Schema validation: the projection is validated against the schema of the SAME Core as the smoke/server (not an older project copy), without the server overlays `ui_settings` and `reconciliation`. A deviation is reported as warning `STATUS_SCHEMA_DEVIATION` (not FAIL) - decision taken during CS-7, see report. The complete `/api/status` response is NOT claimed to be schema-valid (BRD-F-44, deferred).
- Older installed Board payloads that do not display the projection state yield warning `PROJECTION_NOT_DISPLAYED`, not a mismatch FAIL.
- T053: `tests/run-impact-tests.py` mapping added (board_smoke -> tier 2; server/Doctor/board payload -> `test_board_smoke.py` at tier 1).
