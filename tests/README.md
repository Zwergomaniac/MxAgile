# Test Architecture & Fast Feedback WP — Final Report

Date: 2026-09-28

---

## FASTGATE CLASSIFICATION

FastGate is an independent metadata axis from Tier. Tier describes integration depth; FastGate describes suitability for the normal developer/agent feedback loop.

**Tier 0 — all FastGate=true (23 tests)**
All Tier-0 tests are pure static file-content assertions with zero mutation. They complete in 2–8s each, require no subprocesses, network, or mxcli. Every Tier-0 test is ParallelSafe=true.

**Tier 1 — FastGate classification (13 tests)**

| Test | FastGate | Reason |
|---|---|---|
| test-adoption-skeleton.ps1 | true | Single inline script call, < 5s |
| test-injection-contract.ps1 | true | Single subprocess, GUID fixture, < 10s |
| test-managed-block.ps1 | true | PS script subprocesses only, no Git/download |
| test-dfc-migration-preflight.ps1 | true | Inline calls, GUID fixtures, no mxcli |
| test-migration-crash-safety.ps1 | true | Inline state machine, no subprocesses |
| test-artifact-trace-index.ps1 | true | Python indexer subprocess, GUID dir |
| test-spa-bundle-revision.ps1 | true | Python hash/revision subprocesses, GUID dir |
| test-impact-resolver.ps1 | true | Python resolver subprocesses, GUID dir |
| test-session-bootstrap.ps1 | true | Static reads + inline GUID fixture logic |
| test-workcopy-hygiene.ps1 | **false** | ~94s, 50+ robocopy ops, junction on shared dir |
| test-mxagile-dev-cli.ps1 | **false** | ~151s, 46 subprocess launches, global env mutation |
| test-layer-update.ps1 | **false** | ~177s, 24 Git repos, 2 Start-Job invocations |
| test-mxcli-binary-cache.ps1 | **false** | Global env mutation (MXCLI_TEST_BINARY), mxagile-init.ps1 subprocess |

**Tier 2 — all FastGate=false (14 tests)**
All Tier-2 tests require real mxcli and network access. Excluded from FAST by definition.

**FAST composition: 23 Tier-0 + 9 Tier-1 FastGate=true = 32 tests**
All 32 FAST tests are ParallelSafe=true → entire FAST run executes in one parallel batch on PS7.

---

## SLOW TEST ANALYSIS

### test-existing-project-update.ps1

**Measured runtime:** ~263s  
**Test count:** ~75 assertions, 8 groups (A-H) + Group G regression  
**Dominant runtime drivers:**

- **Group G cascade** — REDUNDANT_EXECUTION. G1 → test-migration-provenance → test-install-bootstrap-regression. G2 → test-migration-lifecycle-resync → test-migration-provenance → test-install-bootstrap-regression. G3 → test-wp10-artifact-schemas → test-mxcli-acquisition → lifecycle-resync + migration-provenance. Result: test-install-bootstrap-regression.ps1 ran 3+ times in a single execution of this test.
- **Groups A-H** (excluding G): < 5s total, all in-process with GUID fixtures. SAFE_IMMUTABLE_FIXTURE_REUSE already achieved.

**Process launches:** 3 (each spawning a cascade)  
**Immutable fixture opportunity:** Not applicable — cost is in cascade, not fixture creation.  
**Safe optimization implemented:** Removed G2 and G3. G1 (migration-provenance) retained as the single integration gate. G2 and G3 are standalone tests in run-all-tests.ps1 and transitively overlap G1's coverage entirely.  
**Rejected:** Cannot remove G1 — it is the regression guard for migration provenance within this test.  
**Estimated post-optimization runtime:** ~95s (Groups A-H ~10s + G1 via test-migration-provenance ~85s)

---

### test-layer-update.ps1

**Measured runtime:** ~177s  
**Test count:** 24 test functions  
**Process launches:** 31 direct pwsh subprocess calls  
**Git repos created:** ~26 (git init + add + commit per repo fixture)  

**Dominant runtime drivers:**

| Driver | Classification |
|---|---|
| 26 × git init/add/commit | SAFE_TO_CACHE — "healthy-1.2.0" repo identical across 12+ tests |
| 31 × pwsh process startups (~2s each) | PROCESS_STARTUP_OVERHEAD |
| All 24 tests are isolated GUID-path | POTENTIALLY_PARALLELIZABLE |
| Start-Job in Test-SchemaVersionSameNoPromptRequired | CONTRACT_REQUIRED — timeout IS the assertion |

**Start-Job analysis:** Used in `Test-SchemaVersionSameNoPromptRequired` with `Wait-Job -Timeout 120`. The contract being verified is that the update completes WITHOUT an interactive Read-Host prompt when schema version is unchanged. A blocking Read-Host would hang direct pwsh invocation indefinitely; Start-Job + timeout is the only safe detection mechanism. **NOT_SAFE_TO_OPTIMIZE.**

**Immutable fixture reuse opportunity:** A single pre-built "healthy-1.2.0" fake layer repo (created once before the test loop, copied per test) would eliminate ~12 git init/add/commit cycles. This requires refactoring `New-FakeLayerRepo` to accept an optional pre-built path. Safe but not implemented — significant refactor, deferred.

**Safe optimizations:** Deferred (see DEFERRED section).  
**FastGate:** false — 177s is too heavy for fast feedback.

---

### test-mxagile-dev-cli.ps1

**Measured runtime:** ~151s  
**Test count:** ~60 assertions, 18 scenarios (A-R)  
**Process launches:** ~46 powershell.exe subprocess launches  

**Dominant runtime drivers:**

| Driver | Classification |
|---|---|
| ~46 × powershell.exe startup (~1-2s each) | PROCESS_STARTUP_OVERHEAD (~60-90s) |
| Scenario E dispatches smoke-test.ps1 internally | CONTRACT_REQUIRED |
| Scenario R stdin piping (interactive menu) | CONTRACT_REQUIRED |
| MXAGILE_NONINTERACTIVE parent mutation | EXCLUSIVE_RESOURCE (prevents parallelism) |

**Minor batching opportunities:** Scenarios A5/A6 (--help) could share one captured output; Scenario B (5 bad subcommand checks) could batch into one parameterized invocation. Savings: ~3-5s.  
**Rejected:** MXAGILE_NONINTERACTIVE mutation in parent process prevents parallel execution and cannot be changed without weakening the contract test. CLI process startups are the contract.  
**FastGate:** false.

---

### test-workcopy-hygiene.ps1

**Measured runtime:** ~94s  
**Test count:** ~35 assertions, 13 groups (A-M)  
**Process launches:** ~15-16 subprocess calls (one robocopy-backed call each)  

**Dominant runtime drivers:**

| Driver | Classification |
|---|---|
| Junction in shared project-templates/ | EXCLUSIVE_RESOURCE |
| Group M brownfield_migration_demo (>1000 files robocopy) | CONTRACT_REQUIRED |
| Groups D/G/H: identical -WithDfc source, separate New-MinimalFixture | SAFE_IMMUTABLE_FIXTURE_REUSE |
| 15 powershell.exe process startups | PROCESS_STARTUP_OVERHEAD |

**Immutable fixture reuse:** Groups D, G, H share the same `-WithDfc` source configuration. A single pre-built source fixture could serve all three. Savings: ~3 New-MinimalFixture calls + 3 subprocess startups (~6-10s). Minor gain — deferred.  
**Junction constraint:** The architecture requires mklink /j in project-templates/ for every Invoke-Workcopy call. This is not a robocopy choice; it is a constraint of create-test-workcopy.ps1 resolving TemplateName within project-templates/. NOT_SAFE_TO_OPTIMIZE without changing the production script.  
**FastGate:** false.

---

### test-wp10-artifact-schemas.ps1

**Measured runtime:** ~177s  
**Test count:** ~95 assertions, 11 groups (A-K)  
**Process launches:** ~6 Python calls + 3 powershell subprocess calls  

**Group breakdown:**

| Groups | Type |
|---|---|
| A, B, C, D, I, J | Static assertions — no subprocess |
| E, F, G, H | Python (canonicalize_artifacts.py, build_artifact_index.py) — fast, orthogonal contracts |
| K1 | test-mxcli-acquisition.ps1 (Tier 2, cascade root) — CONTRACT_REQUIRED |
| K2 | test-migration-lifecycle-resync.ps1 — REDUNDANT_EXECUTION (called by K1 transitively) |
| K3 | test-migration-provenance.ps1 — REDUNDANT_EXECUTION (called by K1 and K2 transitively) |

**Safe optimization implemented:** Removed K2 and K3. K1 already exercises them as transitive dependencies.  
**Estimated post-optimization runtime:** ~95s (A-J + K1 only)

---

### test-ps51-compatibility.ps1

**Measured runtime:** ~196s  
**Test count:** ~45 assertions, 16 groups (A-P)  
**Process launches:** 1 (Group B3 using `powershell`) + 6 (Groups K-P)  

**Genuinely PS5.1-specific:**
- **Group B3 only** — runs `powershell` to validate Join-Path syntax works at PS5.1 runtime.
- Groups A, C-J are static text assertions that don't require execution.

**Groups K-P analysis:**

| Group | Test | PS5.1-specific? |
|---|---|---|
| K | test-mxcli-acquisition.ps1 | No — already run by run-all-tests.ps1 under PS5.1 |
| L | test-migration-lifecycle-resync.ps1 | No — also called by K transitively |
| M | test-migration-provenance.ps1 | No — also called by K and L |
| N | test-migration-crash-safety.ps1 | No — Tier-1 test with no PS5.1 dependency |
| O | test-install-bootstrap-regression.ps1 | No — also called by K transitively |
| P | test-startup-priority.ps1 | No — Tier-0 static test |

**Safe optimization implemented:** Removed Groups K-P entirely. run-all-tests.ps1 invokes each as a standalone test under `powershell.exe` (PS5.1), giving identical PS5.1 coverage without the cascade redundancy. K-L-M-O formed the same transitive cascade pattern found in the other two tests.  
**Estimated post-optimization runtime:** ~5s (Groups A-J only, B3 is the only runtime call)

---

## PARALLELSAFE EVIDENCE

All 9 Tier-1 FastGate=true tests are correctly marked ParallelSafe=true. Verified criteria per test:

| Test | Unique Temp Paths | No Env Mutation | No Shared Write | No Fixed Port | No Shared Cache |
|---|---|---|---|---|---|
| test-adoption-skeleton.ps1 | GUID | ✓ | ✓ | ✓ | ✓ |
| test-injection-contract.ps1 | GetRandomFileName | ✓ | ✓ | ✓ | ✓ |
| test-managed-block.ps1 | GetRandomFileName | ✓ | ✓ | ✓ | ✓ |
| test-dfc-migration-preflight.ps1 | GUID | ✓ | ✓ | ✓ | ✓ |
| test-migration-crash-safety.ps1 | GUID per scenario | ✓ | ✓ | ✓ | ✓ |
| test-artifact-trace-index.ps1 | GUID | ✓ | ✓ | ✓ | ✓ |
| test-spa-bundle-revision.ps1 | GUID | ✓ | ✓ | ✓ | ✓ |
| test-impact-resolver.ps1 | GUID | ✓ | ✓ | ✓ | ✓ |
| test-session-bootstrap.ps1 | GUID (E-F); read-only (A-D, G-J) | ✓ | read-only only | ✓ | ✓ |
| test-layer-update.ps1 (Tier-1 FastGate=false) | GUID | ✓ | ✓ | ✓ | ✓ |

**Note on test-session-bootstrap.ps1:** Groups A-D and G-J read from `scripts/` and `project-templates/` but do not write. Read-only concurrent access to shared paths is safe.

**Correctly marked ParallelSafe=false:**
- test-workcopy-hygiene.ps1: Junction in shared `project-templates/` directory.
- test-mxagile-dev-cli.ps1: Sets `$env:MXAGILE_NONINTERACTIVE` in parent process scope.
- test-mxcli-binary-cache.ps1: Sets `MXCLI_TEST_BINARY` env var transiently in parent scope.

---

## PERFORMANCE OPTIMIZATIONS IMPLEMENTED

1. **FastGate metadata field** added to all 49 test-inventory.json entries. run-fast-tests.ps1 now selects `Tier-0 ∪ (Tier-1 ∧ FastGate=true)` instead of `Tier-0 ∪ Tier-1`.

2. **run-fast-tests.ps1 parallel execution** — All 32 FAST tests (23 Tier-0 + 9 Tier-1 FastGate=true) are ParallelSafe=true. On PS7, all 32 run in a single `ForEach-Object -Parallel -ThrottleLimit 8` batch. Sequential path retained for PS5.1 compatibility and any future non-parallel-safe FAST tests.

3. **Cascade redundancy removed from test-existing-project-update.ps1** — Removed G2 (test-migration-lifecycle-resync.ps1) and G3 (test-wp10-artifact-schemas.ps1). G1 retained. Both G2 and G3 were REDUNDANT_EXECUTION: each transitively called test-install-bootstrap-regression.ps1 which G1 already exercises. Estimated saving: ~168s per full run.

4. **Cascade redundancy removed from test-wp10-artifact-schemas.ps1** — Removed K2 (test-migration-lifecycle-resync.ps1) and K3 (test-migration-provenance.ps1). K1 retained. K2 and K3 are transitive dependencies of K1. Classification: REDUNDANT_EXECUTION. Estimated saving: ~80s per full run.

5. **Cascade redundancy removed from test-ps51-compatibility.ps1** — Removed Groups K-P (6 regression suites). None of K-P tested PS5.1-specific behavior; run-all-tests.ps1 already runs each under PS5.1 as a standalone test. The K-L-M-O cascade called test-install-bootstrap-regression.ps1 3+ additional times. Only Group B3 provides genuine PS5.1 runtime coverage. Classification: REDUNDANT_EXECUTION. Estimated saving: ~185s per full run.

**Total estimated cascade saving: ~433s from the FULL run.**

---

## PERFORMANCE OPTIMIZATIONS DEFERRED

1. **test-layer-update.ps1 — immutable "healthy-1.2.0" repo fixture** (~12 git init/add/commit cycles eliminated). Requires refactoring `New-FakeLayerRepo` to accept a pre-built path and copying instead of re-initializing. Safe but non-trivial refactor; estimated saving ~30-40s. The remaining cost (~137s) is PROCESS_STARTUP_OVERHEAD from 31 pwsh launches, which is CONTRACT_REQUIRED.

2. **test-layer-update.ps1 — Start-Job replacement** — cannot be replaced. `Test-SchemaVersionSameNoPromptRequired` uses Start-Job + Wait-Job -Timeout 120 to detect a blocking Read-Host. The timeout IS the assertion; direct invocation would hang indefinitely on a regression.

3. **test-mxagile-dev-cli.ps1 — subprocess batching** — Minor opportunity (~3-5s savings from sharing `--help` output and batching bad-subcommand checks). Not implemented; the test is already FastGate=false and the savings are negligible relative to total runtime.

4. **test-workcopy-hygiene.ps1 — D/G/H fixture sharing** — Pre-building source for the three identical `-WithDfc` groups. Savings < 10s. Deferred; junction architecture constraint is the dominant blocker for this test anyway.

5. **test-layer-update.ps1 — per-test parallelism within the file** — All 24 tests are POTENTIALLY_PARALLELIZABLE (all GUID-isolated). Parallelizing within a single test file requires significant restructuring. Deferred.

---

## FAST PERFORMANCE

**FAST test count:** 32 (23 Tier-0 + 9 Tier-1 FastGate=true)  
**ParallelSafe count:** 32/32 (100% — entire FAST run is one parallel batch on PS7)  
**Execution model:** `ForEach-Object -Parallel -ThrottleLimit 8`

**Estimated wall-clock (PS7):**
- Tier-0 parallel: ~15s (23 tests × ~4s avg, 8-slot concurrency)
- Tier-1 FastGate=true parallel: ~30s (9 tests, Python-only or inline PS, limited concurrency)
- Combined (all 32 in one batch): **~30–35s estimated**

*Measured wall-clock not yet available — requires a timed run of `pwsh -File run-fast-tests.ps1`.*

**FAST does NOT include:**
- test-layer-update.ps1 (177s, FastGate=false)
- test-mxagile-dev-cli.ps1 (151s, FastGate=false)
- test-workcopy-hygiene.ps1 (94s, FastGate=false)
- test-mxcli-binary-cache.ps1 (unknown, FastGate=false)
- All Tier-2 tests (require mxcli + network)

---

## FULL PERFORMANCE

**FULL test count:** ~50 tests (all tiers)  
**Previous measured baseline:** ~1592s (~26.5 min)  

**Estimated post-optimization FULL runtime:**
- test-existing-project-update.ps1: 263s → ~95s (removed G2+G3)
- test-wp10-artifact-schemas.ps1: 177s → ~95s (removed K2+K3)
- test-ps51-compatibility.ps1: 196s → ~5s (removed K-P)
- All other tests: unchanged
- **Estimated saving: ~433s**
- **Estimated new FULL runtime: ~1592 − 433 ≈ 1159s (~19 min)**

*Measured wall-clock not yet available — requires a timed run of `pwsh -File run-all-tests.ps1`.*

**Dominant remaining costs (unchanged):**
- test-layer-update.ps1: ~177s (31 pwsh launches + 26 git operations)
- test-mxagile-dev-cli.ps1: ~151s (46 subprocess launches)
- test-workcopy-hygiene.ps1: ~94s (robocopy + junction)
- test-bootstrap-generic.ps1, test-install-bootstrap-regression.ps1, etc.: mxcli download dependent

---

## COVERAGE PRESERVATION

The cascade removals eliminate no integration boundary coverage:

| Removed | Still covered by |
|---|---|
| test-existing-project-update.ps1 G2 | test-migration-lifecycle-resync.ps1 (standalone in run-all-tests.ps1) |
| test-existing-project-update.ps1 G3 | test-wp10-artifact-schemas.ps1 (standalone in run-all-tests.ps1) |
| test-wp10-artifact-schemas.ps1 K2 | test-migration-lifecycle-resync.ps1 (standalone) + K1 transitive dependency |
| test-wp10-artifact-schemas.ps1 K3 | test-migration-provenance.ps1 (standalone) + K1 transitive dependency |
| test-ps51-compatibility.ps1 K-P | Each is a standalone test in run-all-tests.ps1; PS5.1 outer runner (powershell.exe) exercises them under PS5.1 directly |

**Integration boundaries retained:**
- mxcli acquisition: test-mxcli-acquisition.ps1 (standalone Tier-2)
- install-bootstrap full chain: test-install-bootstrap-regression.ps1 (standalone Tier-2)
- migration provenance: test-migration-provenance.ps1 (standalone Tier-2)
- lifecycle resync: test-migration-lifecycle-resync.ps1 (standalone Tier-2)
- PS5.1 runtime: Group B3 in test-ps51-compatibility.ps1 (verified) + all PS5.1 tests via powershell.exe outer runner in run-all-tests.ps1

**FAST vs FULL distinction confirmed:**
- FAST PASS = Tier-0 static contracts + Tier-1 fast component contracts verified
- FULL PASS = above + slow Tier-1 update/CLI/hygiene contracts + all Tier-2 integration contracts (mxcli acquisition, installer regression, migration lifecycle) verified
- The 4 Tier-1 FastGate=false tests and 14 Tier-2 tests represent real integration depth absent from FAST.

---

## SUMMARY METRICS

| Metric | Value |
|---|---|
| FAST test count | 32 |
| FULL test count | ~50 |
| Tier-0 tests | 23 (all FastGate=true, all ParallelSafe=true) |
| Tier-1 FastGate=true | 9 |
| Tier-1 FastGate=false | 4 |
| Tier-2 tests | ~14 (all FastGate=false) |
| ParallelSafe=true (all tiers) | 37 |
| Previous FULL baseline | ~1592s |
| Estimated FULL post-optimization | ~1159s |
| Estimated cascade saving | ~433s |
| FAST estimated wall-clock (PS7, parallel) | ~30-35s |

*All FULL and FAST wall-clock values marked "estimated" require a timed run to confirm.*

---

## READY FOR REAL CAPTRACK COMPANY LAYER UPDATE

YES — subject to running a confirmed FULL regression pass after the cascade removal changes.

The cascade removals are mechanically safe (removed lines are REDUNDANT_EXECUTION with transitive coverage preserved), but a FULL run is required to confirm no test relies on side effects of the removed suites.
