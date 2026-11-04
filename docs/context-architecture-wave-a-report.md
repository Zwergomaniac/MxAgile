# Context Architecture Wave A Report

**Date:** 2026-11-02
**Scope result:** `WAVE_A_COMPLETE = JA`
**Stop boundary:** `STOP_AFTER_WAVE_A = JA`

Wave A implements only the approved C0 instrumentation and C2 minimal Operating Mode authority. C1, C3, C4, C5, and C6 remain pending. No Example Project project artifacts were changed, no commit was created, and no parity behavior was implemented or restarted.

## C0: Opt-In Telemetry

Before Wave A there was no shared telemetry record vocabulary, and the prototype coupled Claude JSONL details to the common report path. C0 now provides:

- `scripts/context_telemetry_model.py`: harness-neutral record factory with `OBSERVED`, `DECLARED`, and `NOT_OBSERVABLE`; every observation is scoped to `this_collector_run`.
- `scripts/context_architecture_telemetry.py`: harness-neutral opt-in CLI for caller-declared identifiers and local source/projection inventory. Disk presence never implies runtime loading.
- `scripts/claude_jsonl_collector.py`: separate Claude JSONL adapter. Claude-specific event IDs and tool details remain in `collector_extensions.claude_jsonl`.
- Copilot-style records with absent token, request, or delegation data remain valid; missing fields do not claim a harness capability limitation.
- Prompt bodies, command contents, tool inputs/results, and full transcript text are not emitted. Default output is stdout; file output requires explicit `--output`.

C0 is not called from startup, instruction injection, or hooks. It creates no automatic telemetry store or durable state.

## C2: Operating-Mode Authority

Before C2 the detector returned process/project facts while agents reconstructed tool routing from policy prose. The existing `scripts/Get-MxAgileCapabilities.ps1` now has opt-in `-ResolveOperatingMode` output that combines the existing read-only detector, the existing `studio_pro_mcp` / `concord_mcp` capability IDs, and explicit current-session MCP attestations.

- Configuration read from the registry's project MCP config path/key is separate from runtime probe status and project binding.
- `LIVE-SP-CURRENT` prefers Studio Pro MCP. Concord is selected only after a healthy current-session read-only probe and matching project identity.
- Missing/unhealthy MCP evidence yields `BLOCKED`; a mismatched project identity yields `CONFLICT` and effective mode `AMBIGUOUS-SP-STATE`.
- Failed `.mpr` enumeration is `AMBIGUOUS-SP-STATE`; only an observed successful lookup with no `.mpr` yields `CLOSED-AUTONOM`.
- `mxcli_permitted` and `mxcli_fallback_after_mcp_failure` are separate. mxcli is never permitted as a LIVE-SP fallback.
- `CLOSED-AUTONOM` / `LIVE-SP-OTHER` mark the existing mxcli route permitted, but C2 reports its availability as `NOT_RESOLVED_BY_C2`; the project-local mxcli resolver remains authoritative for that separate decision.
- The resolver calls the canonical Studio Pro detector once per requested resolution, does not call MCP tools, and does not persist mode state. The policy says this replaces a direct detector call for the same check.

No new capability registry, persistent schema, or competing resolver was added. The route aggregator lives inside the existing capability resolver.

## Phase-1 Reality Fund Addition

The user-supplied Regions failure is recorded in `docs/context-architecture-baseline.md` as a Verification/Parity Reality Fund. It captures the four smoke checks that were incorrectly promoted to parity `PASS`, the missing Behavioral/Role/Whole-Screen Visual evidence, and the earlier Reference-vs-Model analysis that lacked live-runtime evidence.

The planned C4 target now requires a deterministic aggregate over required dimensions, evidence sufficiency, freshness, and comparison identity. The Regions smoke-only and no-live-runtime cases are named as future C4 regressions. No verification schema, parity policy, or parity resolver was changed in Wave A.

## Wave-A Closure

**Closure status:** `MAPPING_CLOSED = JA`; `RELEASE_READY = NEIN`.

### Impact Mapping

The planner uses explicit path rules; the new C0 Python module/test paths and `.mxagile/policies/operating-mode.md` had no matching rule. Exact-path mappings were added in `tests/run-impact-tests.py`:

- The three shared/Claude collector modules and the C0 Python fixture map to `test-context-architecture-telemetry.ps1` at Tier 1.
- The operating-mode policy maps to the direct operating-mode test plus the existing resolver/discovery consumer suites at Tier 1.
- `tests/test_test_impact.py` now asserts those narrow mappings and preserves the unknown-path Tier-3 fail-closed behavior.

No catch-all was added. The final `python tests/run-impact-tests.py --list` reports **Tier 3**, the seven suites below, and `unmapped: []`. Tier 3 remains because the central impact runner and test inventory changed; the mapping does not downgrade that classification.

### Executed Checks

| Check | Result |
|---|---:|
| Mapping unit tests, `test_test_impact.py` after mapping change | PASS, 16/16 |
| Fast Gate, `python tests/run-impact-tests.py --tier fast` | PASS |
| Mapped Impact Regression, `python tests/run-impact-tests.py --tier impact` | PASS, 149.27 s |
| `test-agent-delegation.ps1` | PASS, 34/34 |
| `test-capabilities-resolver.ps1` | PASS, 29/29 |
| `test-capability-discovery-routing.ps1` | PASS, 133/133 |
| `test-context-architecture-telemetry.ps1` | PASS, 4/4 |
| `test-documentation-consistency.ps1` | PASS, 58/58 |
| `test-operating-mode-detection.ps1` | PASS, 66/66 |
| C0 Python `py_compile` and test-inventory JSON parse | PASS |
| `git diff --check` (Fast Gate component) | PASS |

Impact Regression selected:

- `test-agent-delegation.ps1`
- `test-capabilities-resolver.ps1`
- `test-capability-discovery-routing.ps1`
- `test-context-architecture-telemetry.ps1`
- `test-documentation-consistency.ps1`
- `test-operating-mode-detection.ps1`
- `test_test_impact.py`

### Full-Gate Status and Findings

The Full Release Gate was started before the scope correction, but **did not complete**: the first attempt was interrupted, and the later attempt was terminated when the user explicitly narrowed the task to mapping closure. There is no final full-run summary, so Full Regression is `INCOMPLETE`, not PASS.

One full-gate suite, `test-runtime-orchestration.ps1`, completed with 74/81 and seven failures; it reproduced the same seven failures when run alone. These files are unchanged from HEAD and outside Wave A. Classification: **test/mapping issue, not a Wave-A regression**:

- `B.6` / `L.3`: the source phrase `autonomen` / `Modus` is wrapped across a newline, but the assertion requires a literal space.
- `B.7` / `L.4`: lexical assertions require a phrase absent from the Quality Gate skill, although that skill directs consumers to determine Operating Mode/Tool Authority and execute the complete resolved recipe.
- `C.2` / `C.3` / `O.1`: assertions require `--db-name` inside `development-runtime.md`; that policy delegates exact arguments to `local-runtime-profile.md`, which documents help-verified `--dbname default` and explicitly forbids substituting `--db-name` from memory.

No runtime policy, test assertion, parity artifact, or C1/C4 behavior was changed to mask these findings. The Regionen Reality Fund remains audit/design evidence only.

### Remaining Release Obligation

The final impact plan is mapped but Tier 3. Fast Gate and Impact Regression have already passed and need not be repeated. The **Full Release Gate remains outstanding** because the central impact runner was changed and the full runner never completed. Do not begin C1 or C4 until that obligation is closed and the pre-existing Runtime Orchestration test/mapping findings are adjudicated.

**Recommended commit boundary:** one Wave-A commit containing C0, C2, the narrow impact mappings/tests, and both architecture reports, after the full release obligation is satisfied or explicitly waived. No commit or push was made.
