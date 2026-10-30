# Changelog

## [1.8.0] - 2026-10-30

### Added: Deterministic Project Mission Control

- Read-only local board for portfolio, project overview, waves/workpackages,
	requirements, verification/evidence, findings, and decisions.
- Project Status Contract v2 and deterministic canonical-artifact builder without
	LLM calls or a second lifecycle authority.
- Per-bundle ACTIVE_TARGET references, explicit single-file authority, revision
	drift detection, and source deep links.
- Core installation and update distribution of board assets and tools.

### Security and Evidence Boundaries

- Loopback-only HTTP serving with allowlisted references and sources; no general
	filesystem access, traversal, symlink serving, or directory browsing.
- Target freshness is separate from model freshness; model freshness remains
	`UNKNOWN` until verification evidence has a reliable model fingerprint.

### Added: Compatibility Doctor and Controlled Repair

- Read-only post-install/update Doctor separates framework installation from
	current parser, schema, identity, reference and assignment compatibility.
- Structured, sanitized diagnostics expose positions, repairability and coverage;
	the board retains partial results and displays unassigned recognized tasks.
- Fingerprint-bound repair plans support conservative text-scalar quoting,
	exact checklist-provenance wave assignments, bounded reviewed candidates,
	per-file atomic writes and scoped rollback without lifecycle promotion.

## [1.7.1] — 2026-10-15

### Added: Autonomy-First Compaction Hardening

**Invariant:** `AUTONOMY HAS PRIORITY OVER OPTIONAL CONTEXT OPTIMIZATION.`

A useful or recommended compaction is never by itself a reason to interrupt
mission execution or request user action.

**Behavior for unsupported harnesses (generic, copilot):**
- Returns `COMPACTION_SKIPPED_UNSUPPORTED` (not `TRANSITION_BLOCKED`)
- `Success=true`, `MissionContinues=true`, `IsHumanGate=false`, `RequiredAction=""`
- No `/compact` user request. No new-session demand. Mission continues.
- Native harness auto-compaction applies if available.

**New diagnostic vocabulary (none of the first four are Human Gates):**
- `COMPACTION_USEFUL` — beneficial but not blocking
- `COMPACTION_AUTOMATABLE` — autonomous path available (OpenCode, Claude Code)
- `COMPACTION_SKIPPED_UNSUPPORTED` — skipped; not a gate; mission continues
- `HARNESS_NATIVE_COMPACTION` — harness handled compaction natively
- `CONTEXT_EXHAUSTION_BLOCKING` — only valid Human Gate (actual execution failure)

**Schema additions (additive):** `diagnostic_state`, `mission_continues`, `is_human_gate`
in `context_meta`; 5 new `transition_state` enum values.

**Tests:** `test-context-transition-autonomy-hardening.ps1` (tests 41-50, Tier 1 FastGate).

## [1.7] — 2026-10-14

### Added: Autonomous Context Transition (Compaction & Fresh Epoch)

MxAgile can now autonomously coordinate context compaction and fresh-epoch transitions
across supported harnesses, preserving Mission Truth through the transition.

**Architecture:**
- Generic coordinator: `Invoke-MxAgileContextTransition.ps1`
- Pre-compaction protocol (17 steps): `Invoke-MxAgilePreCompactionCheckpoint.ps1`
- Post-compaction Re-Sync: `Invoke-MxAgilePostCompactionResync.ps1`
- Capability resolver: `Get-MxAgileTransitionCapabilities.ps1`

**Harness adapters:**
- OpenCode: programmatic compact API (LIVE_HARNESS_UNVERIFIED)
- Claude Code: PreCompact hook + SessionStart Re-Sync (LOCALLY_VERIFIED)
- Copilot CLI: UNSUPPORTED (no verified compact API)
- Generic: EXTERNAL_ACTION_REQUIRED fallback

**Primary invariant:** Compaction summary cannot promote evidence, satisfy gates,
close a mission, or suppress Re-Sync. MxAgile checkpoint always wins on conflict.

**Tests:** 3 new test files, 40+ test scenarios (Tier 1 FastGate).

## Unreleased
- Initial productization.