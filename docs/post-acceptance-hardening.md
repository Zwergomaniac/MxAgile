# MxAgile Post-Acceptance Hardening (1.6)

**Version:** MxAgile 1.6
**Basis:** A/B/C/D Acceptance Campaign Reconciliation (`planning/mxa-abcd-reconciliation.md`)
**Datum:** 2026-10-14

This document summarizes the hardening changes applied after the A/B/C/D acceptance campaign.

---

## Campaign Limitations (Important)

Before citing campaign results, note:

- Mode A/D ran on **MxAgile 1.1**; Mode B/C on **MxAgile 1.5** → not directly comparable.
- **0 application defects** across all four campaigns.
- RTK and Context Mode usage was **observed** but token benefit was **not measured**.
- Mode D (combined) does not prove the 1.5-managed combination is defect-free.
- Full reconciliation: `planning/mxa-abcd-reconciliation.md`.

---

## RF-001: Resume Mission Priority

**Problem:** Resume could fall back to general product lifecycle (e.g. FEATURE_SCOPE_COMPLETE)
when a valid active mission checkpoint existed.

**Fix:**
- Added `mission_scope` discriminator section to `policies/context-lifecycle.md`.
- Extended `schemas/context-epoch.schema.json` with `mission.campaign` field.
- Defined explicit Resume logic: active mission checkpoint always wins over general lifecycle.
- Backward compatible: checkpoints without `mission_scope` behave as before.

**Files:** `.mxagile/policies/context-lifecycle.md`, `.mxagile/schemas/context-epoch.schema.json`

---

## RF-002: Context Mode Setup / Discovery States

**Problem:** Framework did not clearly distinguish INSTALLED / REGISTERED / LOADED / ACTIVE.

**Fix:**
- Added `setup_states` section to `.mxagile/integrations/context-mode.yaml`.
- Defined all four states with detection evidence and resolution algorithm.
- `authoring_tool` section clarifies that `ctx_index` (not `ctx_store`) is the correct tool.
- Executable in PATH alone does NOT imply LOADED or ACTIVE.

**Files:** `.mxagile/integrations/context-mode.yaml`

---

## RF-003: ctx_index Is the Authoring Tool

**Status:** Repository was already clean — no `ctx_store` references found.

**Fix:**
- Affirmed in `setup_states.authoring_tool` section of `context-mode.yaml`.
- Added regression test `tests/test-hardening-rf003.ps1` to verify no `ctx_store` references.

**Files:** `.mxagile/integrations/context-mode.yaml`, `tests/test-hardening-rf003.ps1`

---

## RF-004: Studio Pro Detection Must Fail Safe

**Problem:** SP process detector could hang indefinitely; timeout produced CLOSED-AUTONOM
instead of AMBIGUOUS-SP-STATE (UNKNOWN).

**Fix:**
- Added `-TimeoutSeconds` parameter (default: 10s) to `scripts/check-studio-pro-status.ps1`.
- Detection runs in background job with bounded wait.
- Timeout → exit code 2 with `detection_state: UNKNOWN` in JSON output.
- Updated `policies/operating-mode.md`:
  - Explicit rule: timeout → AMBIGUOUS-SP-STATE, NOT CLOSED-AUTONOM.
  - MPR lock is project-affinity evidence only; MUST NOT imply execution intent.
  - New `detection_source: script_timeout` added to vocabulary.
  - New `detection_confidence: unknown` added for timeout cases.

**Files:** `scripts/check-studio-pro-status.ps1`, `.mxagile/policies/operating-mode.md`

---

## RF-005: PowerShell Runtime Requirement

**Problem:** PS 5.x caused cryptic mid-install failures with no clear error message.

**Fix:**
- Added PowerShell 7 preflight to `mxagile-setup.ps1` (before any state mutation).
- Added same preflight to `scripts/install-core.ps1` (canonical installer entry point).
- Fail immediately with clear message: detected version, required version, install instructions.

**Files:** `mxagile-setup.ps1`, `scripts/install-core.ps1`

---

## RF-006: Runtime Start Reality Check

**Problem:** Ambiguous start result treated as APPLICATION_NOT_STARTED → blind retry → BindException.

**Fix:**
- Added "Ambiguous Start Result ≠ Application Not Started" section to
  `policies/runtime-startup-recovery.md`.
- Before retry: check reachability, inspect port/process, confirm ownership.
- Only restart if evidence shows runtime is stale or wrong.

**Files:** `.mxagile/policies/runtime-startup-recovery.md`

---

## RF-007: MxTest / Test-Harness Cleanup Discipline

**Problem:** Test harness injection (*.mxunit, javasource/mxtest) polluted working tree.
No cleanup discipline documented.

**Fix:**
- Created `.mxagile/policies/test-harness-cleanup.md` with:
  - Artifact classification: REQUIRED_APPLICATION_CHANGE / REQUIRED_ACCEPTANCE_EVIDENCE /
    TEMPORARY_TEST_HARNESS_ARTIFACT / UNEXPECTED_OR_UNKNOWN.
  - Required lifecycle: snapshot → test → cleanup → verification.
  - .gitignore usage rules: only for genuinely always-transient files.

**Files:** `.mxagile/policies/test-harness-cleanup.md`

---

## RF-008: mxcli Known Limitations

**Problem:** Campaign findings about mxcli limitations were treated as application defects.

**Fix:**
- Created `docs/mxcli-known-limitations.md` with three evidence-backed items:
  - KL-001: CALL MICROFLOW not available in tested versions.
  - KL-002: Windows attach/PID issue.
  - KL-003: OQL invocation expectations and selection guidance.

**Files:** `docs/mxcli-known-limitations.md`

---

## RF-009: Test-Script Findings Stay Project-Specific

**Problem:** Risk of CapTrack-specific Playwright findings entering Core behavior.

**Fix:**
- Added `TEST_SCRIPT_FAILURE` / `APPLICATION_DEFECT` / `TEST_INFRASTRUCTURE_GAP` classification
  table to `policies/mission-completion.md`.
- Documented rule: no campaign-specific navigation, routes, or selectors in Core.

**Files:** `.mxagile/policies/mission-completion.md`

---

## RF-010: Verification-Before-Completion Hardening

**Problem:** Agent claimed clean completion using a git-status check that ran BEFORE
the final test-harness action.

**Fix:**
- Added "Final Completion Cleanliness Gate" section to `policies/mission-completion.md`.
- Rule: git status MUST be checked AFTER the last harness/runtime action.
- If TEMPORARY_TEST_HARNESS_ARTIFACT: clean → re-verify.
- If UNEXPECTED_OR_UNKNOWN: do NOT claim clean completion.
- Regression test: `tests/test-hardening-rf010.ps1`.

**Files:** `.mxagile/policies/mission-completion.md`

---

## Section 12: Checkpoint Durability Model

**Fix:**
- Added "Checkpoint-Durability" section to `policies/context-lifecycle.md`.
- Defined validity per intended resume scope (same machine vs. fresh clone).
- Documented when portability requires committed Handoff-Store.

**Files:** `.mxagile/policies/context-lifecycle.md`

---

## Section 13: Default Policy After Acceptance

**Target policy (new installations):**
- Context Lifecycle: enabled, checkpoint/resume, manual rollover, pressure_recommendations
- auto_rollover: remains false (requires proven manual flow)
- RTK: disabled (no measured benefit)
- Context Mode: disabled (no measured benefit)
- Graphify: opt-in

**Implementation:** Config.yaml comments updated to document intended new-installation defaults.
Existing installations must opt-in explicitly per upgrade contract.

---

## Sections 14–17: Capability UX, AI-First Discovery, Measurement Readiness

- Capability summary UX documented in `docs/capabilities.md` (Section 14).
- AI-first feature discovery pattern documented in `docs/capabilities.md` (Section 15).
- Measurement readiness (RTK/Context Mode telemetry guidance) in `docs/context-optimization.md` (Section 16).
- No token-savings claims made anywhere in Framework based on A/B/C/D campaign.

---

## Version

MxAgile 1.5 → **1.6** (hardening/consolidation pass)

See `version.yaml` for full change log.
