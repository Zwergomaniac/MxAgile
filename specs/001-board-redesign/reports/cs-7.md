# CS-7 Report — Bounded Board smoke (opt-in)

**Baseline:** CS-2 `cb60ce7` · **Commit:** `6cb79ca` · **Status:** ACCEPTED by the PO with a documented Full Release Gate exception (see 5) · **STOP after CS-7** (CS-0 not authorized)

## 1. Architecture

`scripts/board_smoke.py` (also distributed to `.mxagile/tools/`): S0 preflight (payload, PyYAML, server script, project snapshot) → S1 Board start (`--port 0`, ready line parsed, isolated temp cache via `MXAGILE_BOARD_CACHE_DIR`, `MXAGILE_BOARD_LEGACY_CACHE`/`PROFILE` removed) → S2 API (`/api/status` with 503 retry, schema check, `projection_state` evaluation, `/api/page-previews`, `/api/gallery?screen_id=`, optional `/api/reconciliation`) → S5 links (≤5) → browser (Python Playwright only): S3 nine v1 routes, S6 UI-vs-API consistency + visible projection state, S4 wave/requirement/page drilldowns by click. Waiting is selector/`inner_text` based only (CSP untouched).

## 2. Status and exit semantics

| Result | Exit | When |
|---|---|---|
| PASS | 0 | all stages pass; warnings possible (STALE/BUILDING, SLOW_RUN, schema deviation, project changed in live mode) |
| FAIL | 1 | Board cannot start/payload missing, uncaught JS error, route not rendered, HTTP error, link unresolved, PROJECTION_ERROR, 503 without projection (`status_503_no_projection`), consistency mismatch, cleanup failure, project modified (strict mode) |
| UNAVAILABLE | 2 | no Python Playwright/Chromium (S3/S4/S6 UNAVAILABLE, never PASS) |
| TIMEOUT / ERROR | 3 | hard limit (default and maximum 60 s, watchdog at +8 s) / defect in the smoke itself |

Doctor: exit codes 0/1/2 unchanged; `--board-smoke` adds exit 4 for FAIL/TIMEOUT/ERROR; `--require-board-smoke` also for UNAVAILABLE. The Doctor JSON gets `board_smoke` only with the flag. Installer: separate `Invoke-BoardSmokeOffer`, offered only after an update, interactively, never in CI (`NOT RUN (non-interactive)`), `-BoardSmoke` explicit opt-in; the installer exit code never depends on the smoke.

## 3. Deterministic fixture (embedded CS-1 fixture, Git project in temp)

`tests/test_board_smoke.py`: 20 tests, all OK (PASS, forced UNAVAILABLE, injected JS error → FAIL + OS-temp screenshot, broken route → FAIL, missing payload, crashing Board, 503 without projection, hanging Board → TIMEOUT within limit, STALE → warning, PROJECTION_ERROR → FAIL, schema deviation → warning, older payload → warning, older project schema, strict vs live project modification, `--port 0` distinct ports + flushed ready line, Doctor exits incl. mapping table and repair rejection). Fixture runs: PASS in 18.6–38.1 s (SLOW_RUN visible each time; hard limit never reached). Typical stage times: startup 1.6–2.7 s, first status 2.1–4.3 s, browser launch 0.6–1.7 s, first usable page 0.6–1.3 s, Playwright driver stop 3–9 s (dominant overhead), cleanup 0.6–1.0 s.

## 4. CapTrack read-only reality (framework `board_smoke.py` against CapTrack `dev/gb` @ `248a8998`)

Two runs: PASS, exit 0, 39.3–40.4 s (`SLOW_RUN`), 9/9 routes, source/reference/design_preview/parity_source links 200 (no capture in project), consistency OK (90 requirements, 16 waves done, 17 listed), `project_unchanged: true`, CapTrack `git status` unchanged by anyone during the runs, cleanup complete. Warnings: `STATUS_SCHEMA_DEVIATION` (38 violations, first `TASK_INSPECT_TYPED_TARGET_V1` not in enum; BRD-F-45), `PROJECTION_NOT_DISPLAYED` (CapTrack carries an older Board payload; BRD-F-47), `SLOW_RUN`. First runs revealed (and led to) three robustness decisions: validate against the Core schema, treat an older payload as warning, treat schema deviation as warning.

Idle-CPU observation of the CS-2 background thread on CapTrack: 2.4 % of one core — not abnormal, no finding.

## 5. Validation

| Gate | Result |
|---|---|
| Fast Gate | PASS (1.5–5.7 s) |
| Tier 2 / deterministic smoke | `test_board_smoke.py` OK (first full pass 277 s; later additions run individually), `test-capability-discovery-routing.ps1` PASS (110.6 s in the gate) incl. provenance, distribution, tamper-restore, offer checks |
| Full Release Gate (`run-all-tests.ps1`, supported cached `MXCLI_TEST_BINARY`, no download) | **initial run: FAIL (3 of 119 suites; 116 PASS), 4493 s** — (1) `test-impact-tiers.ps1`: **CS-7 regression** (my second impact rule broke `test_doctor_is_narrow`) → rule removed in the commit; (2) `test-installer-ux.ps1` "fast-fail" timing check (11.97 s) under machine load → PASS in 6.7 s/19 s on rerun; (3) `test-context-mode-harness.ps1` (harness auto-detection) → fails identically on **unmodified HEAD** in this Claude Code session environment, passes with `CLAUDE*` variables unset (pre-existing, environment-dependent). |
| Targeted rerun of exactly these 3 via the official runner (`-SelectedTests`, `CLAUDE*` unset) | PASS (190 s) |

**Recorded accurately (PO 2026-11-06): the Full Release Gate is an accepted gate with analyzed deviations, NOT a clean PASS.** The three deviations are analyzed above; the exit code of the original complete run was lost when the Python processes disappeared; no second ~75-minute run is required solely to obtain a cosmetically clean aggregate. The simultaneous disappearance of the Python processes stays a separate, unresolved environment/reality finding (no evidence links it to MxAgile; not investigated in CS-0). BRD-F-44 deferred; BRD-F-45 needs explicit later triage (CS-3 vs. separate bounded compatibility fix; no silent normalization); BRD-F-46/47 remain reality/performance/compatibility findings.

A single clean Full Release Gate run was **not** obtained; the evidence is the initial run (116 suites PASS) plus the targeted official-runner rerun of the 3 failures. The gate wrapper process (Python) was terminated externally at 10:15:13 while `run-all-tests.ps1` kept running; the summary was read from the runner itself (its exit code was lost).

## 6. Incident (outside CS-7 scope)

At 10:15:12–13 all `python.exe` processes disappeared simultaneously, including the user's own Boards (8765/8767) and `http.server` processes (8888/7777/8101) and the demo Board. No repository code terminates processes by name (searched `Stop-Process`, `taskkill`, `Kill`, `Terminate`, `os.kill`, `psutil`); cause not established (external).

## 7. Findings / deviations

New: BRD-F-44 (overlay schema mismatch, deferred), BRD-F-45 (enum lag), BRD-F-46 (smoke 39–40 s on CapTrack), BRD-F-47 (mixed Core versions in installs). Deviations: Python Playwright only (PO), `--port 0` already existed (only flush added), offer as separate function, schema deviation = warning (decision taken in CS-7, can be flipped), no `playwright-cli` path, second impact rule removed.

## 8. CS-0 assumptions

Hold. CS-0 will change canonical schemas/policies: the smoke validates against the Core schema, so schema additions in CS-0 (`process-state`) do not affect it; Doctor additions must keep exit codes 0/1/2; add the enum value for BRD-F-45 only if CS-0 touches `project-status.schema.json` (otherwise separate follow-up). The foreign policy changes are committed (`c74382e`), so the CS-0 prerequisite is satisfied.

## 9. Approval status

STOP. Waiting for explicit approval of CS-0.
