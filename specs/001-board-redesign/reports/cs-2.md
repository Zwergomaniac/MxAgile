# CS-2 Report — Board behaves like a local dashboard

**Baseline:** CS-1 `f38b0c8` · **Status:** implementation + gate complete · **STOP after CS-2** (CS-7 not authorized)
Raw benchmark data: `cs-2-bench.json`.

## 1. Architecture actually implemented

```
canonical project (read-only)
   │  validated by: Git HEAD/index/branch, `git status -uall` (covers mprcontents), *.mpr stat,
   │  metadata walk of requirements/specs/scripts/planning/ui-ux/.mxagile roots (lstat + ChangeTime)
   ▼
ProjectStatusCache (in memory)  ──persist──►  %LOCALAPPDATA%\mxagile\board-cache\<sha256(path)>\<sha256(branch)>\last-good-summary.json
   │  request path: snapshot validated ≤ 5 s ago → served without any scan
   │  background thread: revalidate every ≥ 2 s (adaptive: ≥ 3× last duration) → rebuild only on change
   │  rebuild running → serve previous snapshot (state STALE/rebuilding), never block
   │  sources change during build → retry 0.5/1/2 s → else STALE "SOURCES_CHURNING" (503 only without any projection)
   │  startup → last-good served immediately as STALE "STARTUP_LAST_GOOD", rebuilt in background
   ▼
/api/status.projection_state {state FRESH|STALE|BUILDING|PROJECTION_ERROR, age_seconds, validated_age_seconds, reason, built_at_head, rebuilding}
board.js: footer "PROJEKTION AKTUELL · geprüft vor N s" / "VERALTET · Grund · Stand vor N s"; header suffix when not FRESH
```

Further changes: per-document Compatibility result cache (key: path, content hash, schema signatures, rule version; thread-safe, bounded 8192, unavailable-validator results never cached); batched Git for reconciliation (`rev-list`/`log` once, `diff-tree` per commit and parent, no per-path `ls-tree`/`rev-parse`, `interpret-trailers` only when `mxagile-` occurs in the message); mxcli capability probe cached per binary identity; `MXAGILE_BOARD_LEGACY_CACHE=1` restores per-request full validation (no window, no thread, no persistence, model walk kept).

Safety properties (each covered by a test): cache lives outside the project (inside → refused); the project tree is byte/mtime-identical after server lifecycle; deleting the cache rebuilds a byte-identical projection; stale/startup state is explicit; failed cache writes never degrade the in-memory projection; last-good is never trusted as current (`signature=None` → first validation rebuilds).

## 2. Findings resolved

BRD-F-10 (per-request full scan: model walk removed in Git trees, asset routes served from validated snapshot), BRD-F-11 (no startup/refresh failure while a projection exists; bounded otherwise), BRD-F-24 (reconciliation 239 s → 6.9 s on real history). New findings: see §8.

## 3. Primary comparable benchmark — frozen reference project snapshot (`365beaa`, `<benchmark-dir>`, unbuffered, alternating old/new, 2 rounds)

| Metric | Old (`f38b0c8`) | New (CS-2) |
|---|---|---|
| Signature computation (median of 5) | 4.87 / 4.99 s | 1.94 / 1.01 s |
| `/api/status` cold | 22.46 / 12.84 s | 4.28 / 6.83 s |
| `/api/status` warm (median of 5) | 3.21 / 7.86 s | **0.108 / 0.135 s** |
| `/api/page-previews` | 3.58 / 7.57 s | 0.110 / 0.120 s |
| `/api/gallery` first / repeat | 10.76 / 4.04 s · 17.22 / 7.39 s | 1.77 / 0.008 s · 2.94 / 0.017 s |
| source link `/source/…DEC-053.yml` (median of 3) | 3.22 / 7.72 s | **0.011 / 0.016 s** |
| reference link `/reference/…` (median of 3) | 7.37 / 7.35 s | **0.010 / 0.036 s** |
| status / navigation after 3 s idle | 5.27–7.42 / 4.19–7.50 s | 0.135 / 0.132 · 0.018 / 0.048 s |
| change written → reflected in `/api/status` | 9.2 / 11.5 s | 6.6 / 10.2 s |
| restart with last-good: first response | — | 0.47 s (STALE `STARTUP_LAST_GOOD`), FRESH after 10.8 s |

Cache-hit behavior: warm requests and all link/asset requests inside the window perform no signature computation (test `test_asset_and_status_requests_reuse_validated_snapshot_without_signature`).

Against spec targets: warm ≤ 0.3 s ✔; link ≤ 0.2 s ✔; first paint with last-good ≤ 3 s ✔ (0.47 s); **cold ≤ 6 s: 4.28 s ✔ / 6.83 s ✘ (one of two rounds misses by 0.8 s)**; background invalidation cycle ≤ 1 s: not met as such — validation takes ~1–2 s on the snapshot (BRD-F-42), but runs off the request path.

## 4. Reconciliation on real history (read-only Git; reference project `dev/gb`, range `62463e88..6c9a4115` pinned, 42 commits, 593 paths)

| Variant | Time | Result |
|---|---|---|
| old (`f38b0c8`) | 239.4 s | `AMBIGUOUS_HISTORY` |
| new, first version (merges still per-path) | 70.7 s | identical |
| **new, final** | **6.94 s** | **byte-identical JSON to old (sha256 3467…)** |

SC-003 (≤ 10 s) met. Equivalence is additionally covered by `ReconciliationBatchingEquivalenceTests` (fixture with root, edit, mode-only, delete, merge with resolution delta, clean merge, trailer + valid Change-Set, invalid Change-Set, model-only, message-only mention; also asserts < ½ of the old Git process count).

## 5. Live reference project reality observation (NOT a benchmark; uncontrolled parallel activity; HEAD `6c9a4115`)

cold `/api/status` 4.10 s → warm 0.111 / 0.134 / 0.103 s; page-previews 0.095 s; `/source/…DEC-053.yml` 0.018 s; **parity report source 200 in 0.034 s**; reference 0.199 s; no 503; `projection_state` FRESH, validated 0.17 s ago. Reference project status lines changed by others during the run: 0; the Board wrote nothing. (Earlier CS-1 live observation: 3.8–13.3 s per request, two 503.)

## 6. Concurrency and the 503 class (snapshot, controlled writer every 0.3 s, 10 sequential requests)

| Scenario | Old | New |
|---|---|---|
| writer on `requirements/REQ-001.yml`, no previous projection | 10× 503 (median 13.6 s) | 10× 503 (median 21.6 s) — **bounded, explicit, not eliminated** |
| same, restart with persisted last-good | — | **10× 200, state STALE, median 0.21 s** |
| writer on a model file (`mprcontents/…mxunit`) | 10× 503 (median 17.1 s) | **10× 200 FRESH, median 0.18 s** (model files are not projection input; Git status covers path-set changes) |

Unit tests: single source change during a build is absorbed by retry (FRESH); permanent churn with a previous projection → STALE `SOURCES_CHURNING` after exactly 3 retries; permanent churn without any projection → visible error (`PROJECTION_ERROR`), never a fake value.
Result: the 503 class is **eliminated whenever a projection (in memory or persisted) exists** and for model-file activity; with neither it remains a bounded, explicit failure that is slower than before (BRD-F-41).

## 7. Validation

| Gate | Result |
|---|---|
| Impact selection (8 paths) | tier 3, unmapped: none, `install-core.ps1` unchanged → no Full Release Gate |
| Fast Gate | PASS (2.30 s) |
| Impact Regression Tier 3 (`test-board-authority.ps1`, `test-core-provenance.ps1`, `test-injection-contract.ps1`, `test-negative-schema.ps1`, `test_board_http.py`, `test_board_performance.py`, `test_external_change_reconciliation.py`, `test_parity_gallery.py`, `test_project_status.py`) | PASS (524.95 s; 194 Python tests OK; PowerShell FAIL: 0) |
| Targeted rerun after the late merge-path change in `reconciliation_git.py` (mapped suites for that file + its test: `test-core-provenance.ps1`, `test-injection-contract.ps1`, `test_external_change_reconciliation.py`) | PASS (286.66 s; 48 tests OK) — the full Tier-3 set was **not** repeated; it ran against the version without the merge-path change |
| Full Release Gate | NOT RUN (not required) |
| New tests red on `f38b0c8` | 10/10 ERROR (baseline lacks the features), green on CS-2 |

## 8. New findings

BRD-F-40 (`projection` name collision → `projection_state`), BRD-F-41 (503 bounded, slower without projection), BRD-F-42 (residual signature cost; cold-target miss in 1 of 2 rounds), BRD-F-43 (5 s validation window labelled FRESH with "geprüft vor N s") — all in `docs/board-redesign-findings.md`.
Not measured: idle CPU of the background thread (design bound: ≤ ~1/3 of one core during validation, adaptive); separate effect of the Compatibility result cache.

## 9. Deviations from the Spec Kit plan

See `tasks.md` "CS-2 execution notes": field name, cache key, window + background revalidation instead of purely background, no reconciliation-report result cache, last-good for the summary only, merge path added during validation.

## 10. CS-7 assumptions

Hold: `--port 0` (T047) is not implemented yet and still needed; the Board now starts quickly and survives churn, which keeps the Smoke inside its 15 s budget on reference project (cold 4–7 s). New constraints for CS-7: use `MXAGILE_BOARD_CACHE_DIR` (temp) for isolated smoke runs and `MXAGILE_BOARD_LEGACY_CACHE` must not be set; the smoke must treat `projection_state.state != FRESH` as a reportable state, not a failure; the Board's CSP blocks `wait_for_function` (selector waits only).

## 11. Approval status

STOP. Waiting for explicit approval of CS-7.
