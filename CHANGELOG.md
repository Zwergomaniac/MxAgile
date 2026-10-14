# Changelog

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