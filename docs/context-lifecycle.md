# MxAgile Context Lifecycle Architecture

**Normative framework behavior.**
Configuration reference and examples are included in this document.

Related files:
- Schema: `.mxagile/schemas/context-epoch.schema.json`
- Policy: `.mxagile/policies/context-lifecycle.md`
- Config: `.mxagile/config.yaml` → `context_lifecycle:`

---

## 1. Architecture Overview

MxAgile Context Lifecycle separates *mission state* from *agent session state*.

```
MISSION
  ├── Context Epoch 1  ─── HOT context injected
  │     (discovery + analysis)
  │     ↓ checkpoint written
  ├── Context Epoch 2  ─── only HOT context + references to WARM/COLD
  │     (implementation)
  │     ↓ checkpoint written
  └── Context Epoch 3  ─── only HOT context + references
        (verification + acceptance)
```

Each epoch loads only what the current task needs.
Prior raw tool output, full logs, and large diffs are COLD evidence —
referenced but not re-injected automatically.

---

## 2. Problem Statement and Gateway Observation

Gateway telemetry indicates approximately 90% of token consumption originates
from requests whose context length exceeds 150k tokens in a 250k context window.
Repeated injection of large raw tool outputs, full logs, and prior epoch
conversation history is the primary driver.

This architecture addresses the structural cause:
**missions accumulate long contexts because durable state has no explicit alternative.**

**Important limitations:**
- The 150k figure is a measurement boundary for evaluation, not a production threshold.
- Exact token counting is not available locally.
- Improvement in the >150k concentration cannot be claimed until post-change
  gateway measurements confirm it.

---

## 3. Mission vs. Session vs. Context Epoch

| Concept | Scope | Lifecycle |
|---------|-------|-----------|
| **Mission** | The entire delivery objective (e.g. implement W01) | Begins at mission start; ends at USER_MISSION_COMPLETE |
| **Session** | One agent invocation (conversation) | Begins when agent starts; ends when agent stops or is reset |
| **Context Epoch** | One continuous agent-session segment with bounded context | Begins at epoch start; ends at epoch rollover (manual or auto) |

A mission spans multiple sessions and epochs.
A session spans at most a few epochs.
An epoch is the unit of context management.

---

## 4. HOT / WARM / COLD Context Model

### HOT Context

Small, continuously required information. Must be present in every epoch.

- Current user goal and mission ID
- Active lifecycle phase and active Context Epoch
- Framework / Company Layer / project scope
- Current task and open gates
- Current blockers
- Short repository state summary
- Next intended action
- Applicable user overrides

**HOT context must NOT contain complete COLD evidence.**
HOT context MAY contain references to COLD evidence files.

### WARM Context

Durable, retrievable information — not always injected.

- Prior decisions and rationale
- Architecture findings
- Prior checkpoint summaries
- Module analyses
- Earlier known issues
- Graphify findings (when available and READY)
- Historical but still relevant task state
- References to prior implementation reports

Retrieve WARM context when it is needed for the current task.
Do not inject all WARM context into every epoch by default.

### COLD Evidence

Canonical evidence. **Never replaced by a summary.** Available on demand.

- Raw command output
- Complete logs
- Complete diffs (where required)
- Screenshots
- Test result files
- Runtime traces
- mxcli dumps
- Structured inspection output
- Large JSON fixtures
- Acceptance reports
- Generated diagnostic artifacts

COLD evidence is referenced via `artifacts[]` in the Context Epoch contract.
It is retrieved when a specific claim requires verification, not by default.

---

## 5. Durable Resume Contract

The resume contract is a structured YAML document at:

```
planning/lifecycle/context-epoch.yaml    ← canonical, Git-tracked
.concord/scratch/context-epoch.yaml     ← local session cache, gitignored
```

Schema: `.mxagile/schemas/context-epoch.schema.json`
Current version: `1.0`

The contract captures:
- Mission identity and status
- Scope boundaries
- Lifecycle phase and epoch history
- Repository state snapshot (branch, commit, working-tree)
- Verified, failed, and unverified evidence claims
- Key decisions and their rationale
- Open gates and their required evidence
- User overrides in effect
- Artifact references
- The safe next action
- Context pressure metadata

**Security rule:** No passwords, tokens, API keys, credentials, or
sensitive environment values may be stored in this file.
Use `process-state.yaml → prerequisite_state` for non-sensitive
readiness status (e.g., `runtime_config: configured`).

---

## 6. Evidence State Model

Every claim in the resume contract carries an explicit `evidence_state`:

| State | Meaning |
|-------|---------|
| `VERIFIED` | Positively confirmed with durable evidence at the named `validity_scope` |
| `FAILED` | Evaluated and failed; `failure_summary` must be present |
| `UNVERIFIED` | Not verified — evidence unavailable, tool unavailable, or precondition missing |
| `STALE` | Previously VERIFIED; a subsequent repository or runtime change may have invalidated it |
| `SUPERSEDED` | Replaced by newer evidence; preserved for audit traceability |

**Critical invariant:** `UNVERIFIED` is **never** equivalent to `VERIFIED`.
A context epoch rollover must not promote, demote, or discard evidence states.

### Staleness Triggers

A claim with `stale_if_commit_changes: true` becomes `STALE` when:
- The repository commit hash changes between checkpoint and resume

Additional staleness triggers (regardless of `stale_if_commit_changes`):
- A story spec referenced by the claim is modified
- An input resource that the claim depends on is changed
- An acceptance campaign result file is deleted or overwritten

---

## 7. Interruption Semantics

Four interruption classes (aligned with `lifecycle-resync.md`):

| Class | Example | Behavior |
|-------|---------|----------|
| `OBSERVATION` | "Show me the security roles" | Answer; phase unchanged; resume at exact position |
| `CLARIFICATION` | "D02 applies per facility" | Record decision; re-evaluate only affected gate; continue |
| `CHANGE` | "Mockup replaced" | Determine earliest affected phase; mark IMPACT_REVIEW_REQUIRED; preserve unaffected |
| `PAUSE` | "Stop here" | Write checkpoint; set `interrupted: true`; preserve done checklist items |

An `OBSERVATION` does not:
- Change the lifecycle phase
- Trigger a gate evaluation
- Create a user_override in the resume contract
- Roll over to a new Context Epoch

---

## 8. Re-Synchronization Algorithm

On resume after an interruption or Context Epoch rollover:

1. Load `planning/lifecycle/context-epoch.yaml`
2. Validate schema version — if unknown, produce conflict state (do not continue)
3. Verify repository identity (origin URL or project root marker)
4. Inspect actual branch, commit, and working-tree state
5. Compare actual state with checkpoint state
6. Validate referenced artifact paths exist locally
7. Identify files changed since the checkpoint commit
8. Mark claims with `stale_if_commit_changes: true` as `STALE` if commit changed
9. Preserve `FAILED` and `UNVERIFIED` states unchanged
10. Reconstruct only the required HOT context
11. Retrieve WARM or COLD material only when needed for the current task
12. Determine a safe next action (from `next_action` + current repository reality)
13. Continue without repeating already-VERIFIED work
14. Record the re-synchronization result in an updated checkpoint

### Delegated Result Reuse

Completed bounded semantic work is stored as a compact result under
`.concord/delegated-results/` and referenced from the Context Epoch `artifacts` list.
The pre-compaction checkpoint preserves these references. After resume, reuse is
allowed only when the active mission matches and every recorded source fingerprint
is current; changed or missing sources make the result `STALE`. Running or interrupted
delegations are not completed work. Result transcripts are never checkpointed, and
Context Mode does not automatically index every result.

Full handoff and result contract: `.mxagile/policies/agent-delegation.md`.

### Repository Incompatibility

If actual state is incompatible with the checkpoint:

| Conflict Type | Detection | Recovery |
|---------------|-----------|---------|
| Branch diverged | `checkpoint.branch` ≠ actual branch | Inform user; preserve checkpoint; do not continue implementing |
| Commit diverged | `checkpoint.commit` not in history | Inform user; mark commit-sensitive claims STALE |
| Artifact missing | Referenced path does not exist | Create UNVERIFIED entry for affected claims |
| Schema incompatible | `schema_version` unknown | Stop; explain; request manual migration |

Do not continue blindly. Do not discard the checkpoint. Preserve user work.

---

## 9. Context Pressure Policy

### Pressure States

| State | Meaning | Action |
|-------|---------|--------|
| `NORMAL` | No action needed | Continue normally |
| `PRESSURE` | Approaching threshold | Checkpoint recommended at next safe boundary |
| `ROLLOVER_RECOMMENDED` | Checkpoint available; rollover advisable | Recommend rollover to user |
| `ROLLOVER_REQUIRED` | Must roll over at next safe boundary | Warn; defer to next safe boundary |

### Threshold Configuration

Thresholds are in `.mxagile/config.yaml → context_lifecycle.pressure_thresholds`.
Default values are `null` (not measured locally).

**Do not manufacture token counts.**
Accept token measurements only from:
- Harness-reported counts (`context_token_source: harness_reported`)
- Gateway measurements (`context_token_source: gateway_measurement`)
- Explicit user-supplied counts (`context_token_source: user_supplied`)

Without a measurement, report `NORMAL` and note that pressure cannot be computed.

---

## 10. Manual and Automatic Rollover

### Implementation Order (required)

1. Durable checkpoint generation ✓
2. Schema validation ✓
3. Manual resume ✓
4. Repository and lifecycle re-synchronization ✓
5. Manual Context Epoch rollover ✓
6. Context pressure reporting/recommendation ✓
7. Guarded automatic rollover — only after manual mode is proven

### Manual Rollover

Trigger: User requests rollover explicitly, or `pressure_state = ROLLOVER_RECOMMENDED`.

Process:
1. Write a complete, validated checkpoint
2. Record `rollover_reason: manual_rollover`
3. Increment epoch ID
4. Start the new epoch with HOT context only
5. Retrieve WARM/COLD on demand

### Automatic Rollover

Enabled only when `context_lifecycle.auto_rollover: true` AND all conditions are met:

- Valid, schema-validated checkpoint written
- Required evidence persisted
- No critical tool call, file write, migration, or commit in flight
- Current repository state captured in checkpoint
- Next action representable
- Rollback/resume available
- Active harness can safely start a fresh context

If any condition is not met: issue recommendation; defer to next safe boundary.

### Safe Rollover Boundaries (preferred order)

1. After completing a full lifecycle phase
2. After a gate result is recorded
3. After completing a checklist item
4. After an explicit user PAUSE
5. Between independent analysis tasks

### Unsafe Rollover Points (forbidden)

- During an active tool call
- During a file write
- Between starting and confirming a git commit
- Mid-verification campaign (after first confirmed proof point)

---

## 11. Feature Controls and Defaults

All features default to disabled for backward compatibility.

| Feature | Config key | Default |
|---------|-----------|---------|
| Master switch | `context_lifecycle.enabled` | `false` |
| Checkpoint/resume | `context_lifecycle.checkpoint_resume` | `false` |
| Manual rollover | `context_lifecycle.manual_rollover` | `false` |
| Pressure recommendations | `context_lifecycle.pressure_recommendations` | `false` |
| Automatic rollover | `context_lifecycle.auto_rollover` | `false` |

Enable sequentially:
`checkpoint_resume` → `manual_rollover` → `pressure_recommendations` → `auto_rollover`

---

## 12. Storage and Artifact Lifecycle

| Location | Purpose | Git-tracked | Cleanup |
|----------|---------|------------|---------|
| `planning/lifecycle/context-epoch.yaml` | Canonical resume contract | Yes | Retain; superseded when wave is done |
| `.concord/scratch/context-epoch.yaml` | Local session cache | No (gitignored) | Safe to delete; canonical file is authoritative |
| `tests/fixtures/context-lifecycle/` | Test fixtures | Yes | Retain with test suite |

**Naming convention for archived epochs:**
When rolling over, rename old file to `context-epoch-EPOCH-NNN.yaml` before writing the new one.
This creates a browsable epoch history for debugging.

**Retention:** Retain context-epoch files until the wave or mission is in terminal state `done`.
After `done`, files may be archived to `planning/archive/` or deleted if not needed for audit.

**Corruption handling:**
If `context-epoch.yaml` is corrupt (not valid YAML or not valid schema),
fall back to `process-state.yaml` and `implementation-checklist.yaml` for re-sync.
Do not invent missing state.

**Schema migration:**
When `schema_version` changes, write a migration note in this document.
Agents detecting an unknown version must not read the file; they must inform the user
and request manual migration.

---

## 13. Security and Privacy

- No secrets, credentials, tokens, API keys, or personally identifiable information
  in `context-epoch.yaml` or any fixture file
- Non-sensitive readiness status only in `prerequisite_state` (e.g. `runtime_config: configured`)
- Gateway measurements do not flow into the checkpoint unless the user explicitly supplies them
- Fixtures in `tests/fixtures/context-lifecycle/` must be free of real employee data,
  real credentials, and real API endpoints

---

## 14. Harness Adapter Responsibilities

The harness (Claude Code, Copilot, Codex, etc.) is responsible for:
1. Measuring or reporting actual context size (token count)
2. Providing `estimated_context_tokens` to the checkpoint when available
3. Starting a fresh context when rollover is requested
4. Passing the resume contract path at new session start

The harness does NOT control:
- MxAgile lifecycle state
- Gate evaluations
- Evidence validity
- Checkpoint content decisions

---

## 15. Backward Compatibility and Rollout

When `context_lifecycle.enabled: false` (the default):
- No checkpoint is created or read
- No resume contract is written
- No pressure state is computed
- All existing MxAgile processes operate unchanged
- Existing `planning/lifecycle/context-epoch.yaml` files are ignored

Consumer projects (CapTrack, MB_SSO, HierarchyTree, etc.) do not need to migrate
to benefit from existing functionality. Context Lifecycle is opt-in.

---

## 16. Rollback

To return to pre-Context-Lifecycle behavior:

1. Set `context_lifecycle.enabled: false` in `.mxagile/config.yaml`
2. Do NOT delete `planning/lifecycle/context-epoch.yaml` (audit record)
3. `.concord/scratch/context-epoch.yaml` may be deleted safely
4. All MxAgile processes continue with `process-state.yaml` as before

**Purely additive changes (safe to ignore when disabled):**
- `context-epoch.schema.json`
- `policies/context-lifecycle.md`
- `context_lifecycle:` section in `config.yaml`
- `planning/lifecycle/context-epoch.yaml` (only written when enabled)

**Behavior-changing changes:**
- Only when `context_lifecycle.enabled: true`

---

## 17. Testing and Acceptance Strategy

See test files in `tests/`:

| Layer | File | Coverage |
|-------|------|---------|
| 1 (schema/unit) | `test-context-epoch-schema.ps1` | Schema structure, required fields, evidence states, feature control defaults, fixture structural checks |
| 3 (golden scenarios) | `test-context-lifecycle-golden-scenarios.ps1` | GOLD-CTX-01 through GOLD-CTX-05 |
| 5 (regression) | `run-fast-tests.ps1` | All existing Tier 0 + Tier 1 FastGate tests |

Layer 2 integration tests and Layer 4 harness smoke test are the primary
remaining items — documented in section 21 (Known Limitations).

---

## 18. Operational Troubleshooting

**Problem:** Resume fails with schema version error.
**Action:** Check `schema_version` in `planning/lifecycle/context-epoch.yaml`.
If it differs from `"1.0"`, the file was written by a newer schema version.
Manually migrate following the instructions in this document, section 12.

**Problem:** All verified claims marked STALE after resume.
**Action:** Check if the commit changed since the checkpoint.
If `stale_if_commit_changes: true` claims are expected to be stable, verify that
the commit hash is correct and that the relevant files were not changed.

**Problem:** Context pressure stays at NORMAL but token counts are large.
**Action:** Token counting is not available locally.
Supply gateway measurements via `estimated_context_tokens` and
`context_token_source: gateway_measurement` for pressure to be computed.

---

## 19. Known Limitations

1. **Exact token counting not available locally.**
   Pressure state cannot be automatically computed without external measurement.
   Manual rollover is the primary mechanism.

2. **Layer 2 integration tests (checkpoint write/read cycle) not yet automated.**
   Covered by Layer 1 static checks and Layer 3 golden scenarios.
   A full write-read cycle test requires a project fixture with a real
   `planning/lifecycle/` directory. Documented as follow-up item.

3. **Layer 4 harness smoke test not yet automated.**
   A true fresh-context resume test requires harness integration.
   Manual procedure: write checkpoint → start new session → verify resume.

4. **auto_rollover is not yet safe to enable.**
   Harness-reported token counts and fresh-context start capability are
   not verified for any current harness. Remains `false` by default.

5. **Graphify findings as WARM context are not yet automatically loaded.**
   The agent must manually query Graphify and add findings to WARM context.

6. **No RTK or Context Mode integration.**
   Extension points exist in `config.yaml` but no implementation is active.

---

## 20. Extension Points for RTK and Context Mode

Extension points exist in `.mxagile/config.yaml` as commented-out keys:

```yaml
# warm_retrieval_provider: none     # future: rtk
# compression_provider: none        # future: context_mode
# token_counter: none               # future: api
```

These are placeholders only. No implementation is included in this version.

To evaluate RTK: set `warm_retrieval_provider: rtk` and implement the
WARM retrieval adapter in the relevant harness skill.

To evaluate Context Mode: set `compression_provider: context_mode` and
implement the adapter in the harness integration layer.

---

## 21. Why Graphify Is Not Expanded Here

Graphify was assessed as providing medium observed benefit for orientation
during lifecycle re-sync. The primary driver of long-context accumulation
is not graph absence but repeated raw evidence injection across sessions.

Graphify is:
- Already integrated as an optional information source
- Usable as WARM context by reference
- Not causing the 150k+ context concentration observed in telemetry

Expanding Graphify would address a different problem (artifact relationship
navigation) and would not reduce context accumulation on its own.
A direct measurement gap that requires a Graphify change has not been found.

---

## 22. Examples

### Example 1: Valid Checkpoint (implementing phase)

See `tests/fixtures/context-lifecycle/checkpoint-valid.yaml`.

Key fields at a glance:
```yaml
schema_version: "1.0"
mission:
  id: MISSION-2026-W01-CTX
  status: active
lifecycle:
  current_phase: implementing
  active_context_epoch: EPOCH-002
  interrupted: false
context:
  epoch_id: EPOCH-002
  pressure_state: NORMAL
  hot_context_summary: >
    Mission: implement Context Lifecycle. Phase: implementing W01.
    Next: schema tests. No blockers.
```

### Example 2: Resume / Re-Sync After Epoch Rollover

Scenario: Epoch 1 ended at gate-to-ready. Agent resumes in Epoch 2.

1. Load `planning/lifecycle/context-epoch.yaml`
2. Validate: `schema_version: "1.0"` ✓
3. Verify repo: branch=main, commit=2ed7bf6
4. Inspect actual: branch=main, commit=2ed7bf6 ✓ — no divergence
5. Artifacts: `planning/lifecycle/process-state.yaml` exists ✓
6. Changes since checkpoint: none for relevant paths ✓
7. Stale claims: none (commit unchanged)
8. Reconstruct HOT: phase=implementing, epoch=EPOCH-002, next=schema tests
9. WARM/COLD: not needed for next action
10. Safe next action: continue checklist item W01-03
11. Write updated checkpoint with re-sync confirmation

### Example 3: Interruption Example

Scenario: During implementing W01-03, user asks "What security roles exist?"

```
Interrupt class: OBSERVATION
Action: Answer the question about security roles
Phase after answer: implementing (unchanged)
Next checklist item: W01-03 (unchanged)
Epoch: EPOCH-002 (unchanged)
user_overrides: not added (OBSERVATION does not create override)
```

On resume: re-sync confirms phase=implementing, W01-03=pending, continue.

### Example 4: Context Pressure / Rollover Example

Scenario: User supplies gateway measurement — context is at 160k tokens.

```yaml
context:
  epoch_id: EPOCH-003
  estimated_context_tokens: 160000
  context_token_source: user_supplied
  pressure_state: ROLLOVER_RECOMMENDED
```

Agent recommendation:
> "Context pressure is ROLLOVER_RECOMMENDED (160k tokens supplied).
> A checkpoint is available. Recommend starting Epoch 4 at the next
> safe lifecycle boundary (end of checklist item W01-04).
> Type 'roll over context' to confirm."

### Example 5: Conflict — Branch Diverged

Scenario: Checkpoint branch=feature/ctx, actual branch=main.

```
conflict_type: branch_diverged
checkpoint_branch: feature/context-lifecycle
actual_branch: main
action: STOP — inform user; preserve checkpoint; do not continue
recovery: Confirm which branch is correct; if main, archive feature branch checkpoint
```

### Example 6: UNVERIFIED Claim Preserved Across Rollover

Checkpoint in Epoch 1:
```yaml
unverified:
  - claim: "Productive API integration tested end-to-end"
    reason: evidence_unavailable
    blocking_or_non_blocking: blocking
    evidence_state: UNVERIFIED
```

After rollover to Epoch 2:
```yaml
unverified:
  - claim: "Productive API integration tested end-to-end"
    reason: evidence_unavailable
    blocking_or_non_blocking: blocking
    evidence_state: UNVERIFIED    # unchanged — NOT promoted to VERIFIED
```

The acceptance gate remains `blocked` until this claim is resolved.

---

## 23. Model-Aware Context Management

Strictly separates three concerns:

### A. Model Capability (physical, factual)

- Physical context-window size
- Model identifier
- Harness/provider capability flags

Source: `.mxagile/model-profiles.yaml` (profiles section)

### B. MxAgile Working-Context Policy (configurable)

- Effective working budget
- Pressure thresholds (ratio-based or absolute)
- Rollover recommendation threshold
- Rollover requirement threshold
- Safety reserve

Source: `.mxagile/model-profiles.yaml` (policy_overrides) or
`.mxagile/config.yaml` (pressure_thresholds for absolute overrides)

### C. Observed Context State (runtime, external)

- Current context tokens
- Measurement source (harness/gateway/user)
- Measurement reliability
- Measurement timestamp

Source: External harness/gateway adapter (never fabricated locally)

### Resolution Hierarchy

Deterministic, highest priority first:

1. Reliable value supplied by active harness/provider/gateway adapter
2. Explicitly configured model profile (matched by `model_id`)
3. Explicitly configured generic fallback (where safe)
4. **UNKNOWN**

Never fabricate: model identity, context-window size, current token
consumption, or pressure state. UNKNOWN remains UNKNOWN when reliable
data is unavailable.

### Operational Scripts

| Script | Purpose |
|--------|---------|
| `scripts/Get-MxAgileModelPolicy.ps1` | Resolves model capability and working-context policy |
| `scripts/Get-MxAgileContextPressure.ps1` | Evaluates context pressure from external measurements |
| `scripts/Test-MxAgileRolloverSafety.ps1` | Checks all rollover safety conditions |
| `scripts/Invoke-MxAgileEpochRollover.ps1` | Performs complete manual epoch rollover |

---

## 24. Harness / Provider Adapter Contract

Schema: `.mxagile/schemas/harness-adapter.schema.json`

The adapter contract is the smallest generic interface required for an external
harness, gateway, or provider to integrate with MxAgile Context Lifecycle.

### Adapter Capabilities

| Field | Type | Purpose |
|-------|------|---------|
| `model_capability.model_id` | string | Model identifier for profile lookup |
| `model_capability.context_window_tokens` | integer | Physical context-window size |
| `context_measurement.estimated_context_tokens` | integer | Current context usage |
| `context_measurement.source` | enum | How the measurement was obtained |
| `context_measurement.reliability` | enum | Measurement reliability: exact, estimate, stale, unknown |
| `harness_capability.can_report_tokens` | boolean | Can supply token measurements |
| `harness_capability.can_start_fresh_context` | boolean | Can programmatically start new session |
| `harness_capability.supports_epoch_transition` | boolean | Supports full epoch transition protocol |
| `transition_result` | object | Result of most recent transition attempt |

### Design Constraints

- Generic: not tied to Claude, Copilot, Codex, or any specific provider
- No hosted service required
- No external network services required
- Absent fields are treated as UNKNOWN
- If the current harness cannot expose a required value, keep it UNKNOWN

---

## 25. Manual Context Epoch Rollover

### 10-Step Rollover Process

1. Determine current mission/lifecycle state (read checkpoint)
2. Ensure no unsafe operation is in flight (safety check)
3. Persist required evidence (verify checkpoint has evidence)
4. Write durable operational checkpoint
5. Validate the checkpoint
6. Record rollover reason
7. Close the current Context Epoch (archive prior checkpoint)
8. Create/increment the next Epoch identity (EPOCH-NNN → EPOCH-NNN+1)
9. Expose the state required for a fresh agent context
10. Require resume/re-sync before work continues

**Invariant:** Manual rollover never silently declares mission completion.

### Rollover State Machine

| State | Meaning |
|-------|---------|
| `not_applicable` | No rollover in progress or considered |
| `rollover_recommended` | Pressure or boundary suggests rollover |
| `rollover_pending_safe_boundary` | Approved but waiting for safe point |
| `rollover_ready` | All preconditions met, can proceed |
| `rollover_performed` | Completed; this is the post-rollover epoch |
| `rollover_blocked` | Preconditions not met; `rollover_blocked_reasons` lists details |
| `rollover_unsupported_by_harness` | Harness cannot execute context transition |

### Rollover Safety Conditions

Checked by `Test-MxAgileRolloverSafety.ps1`:

| Condition | Script-checked | Caller-supplied |
|-----------|---------------|-----------------|
| Valid checkpoint exists | ✓ | |
| Feature controls allow rollover | ✓ | |
| Working tree clean | ✓ | |
| Mission not in terminal state | ✓ | |
| No tool call in flight | | ✓ |
| No file write in flight | | ✓ |
| No checkpoint write active | | ✓ |
| No pending commit | | ✓ |
| Harness supports transition | | ✓ (informational) |

If the harness cannot start a fresh context:
- Produces a deterministic rollover-ready state
- Does not pretend a context transition occurred
- Preserves the checkpoint
- Exposes the required human/harness action

---

## 26. Natural-Boundary / Opportunistic Rollover

Rollover below a numeric pressure threshold is permitted when a particularly
clean lifecycle boundary exists and substantial historical context can safely
be discarded.

### Boundary Classes

Configured in `.mxagile/config.yaml → context_lifecycle.natural_rollover_boundaries`:

| Boundary | Lifecycle Transition |
|----------|---------------------|
| `discovery_to_implementation` | discovery → implementing |
| `implementation_to_verification` | implementing → verifying |
| `debugging_resolution_to_acceptance` | debugging resolution → acceptance |
| `completed_work_package_to_next` | completed bounded work package → next |

### Policy

- Do NOT automatically roll over at every phase boundary
- The policy must consider whether rollover provides value
- A valid durable checkpoint must exist
- Set `natural_rollover_boundaries: []` to disable entirely

---

## 27. Guarded Automatic Rollover

### Status: Implemented but DISABLED BY DEFAULT

`context_lifecycle.auto_rollover: false`

Automatic rollover may proceed only when **all** required preconditions are true:

1. Reliable pressure information available
2. Policy says rollover is required or appropriate
3. Valid durable checkpoint can be produced
4. Checkpoint validation succeeds
5. Evidence is persisted
6. Repository state has been captured
7. No unsafe operation is active
8. Next action is representable
9. Harness supports the required context transition

If any condition is not met: issue recommendation, defer to next safe boundary.

### Feature Control

```yaml
context_lifecycle:
  enabled: true
  checkpoint_resume: true
  manual_rollover: true
  pressure_recommendations: true
  auto_rollover: true     # ← only when ALL prior stages are proven
```

### Pilot Configuration (recommended starting point)

```yaml
context_lifecycle:
  enabled: true
  checkpoint_resume: true
  manual_rollover: true
  pressure_recommendations: true
  auto_rollover: false    # ← manual only until confidence is established
```

---

## 28. Upgrade / Migration Notes

**v1.0 → v1.0 (no change):** No migration needed.

**v1.0 additive (current):** `rollover_state` and `rollover_blocked_reasons`
added as optional fields. Existing checkpoints remain valid — new fields
have defaults. No migration script needed.

**Future v1.0 → v1.1 (hypothetical additive):**
- Add new optional fields to the schema
- Existing files remain valid (new fields have defaults)
- No migration script needed

**Future v1.0 → v2.0 (hypothetical breaking):**
- Increment `schema_version` to `"2.0"`
- Write a migration script at `scripts/migrate-context-epoch-v1-to-v2.ps1`
- Document required field changes in this section
- Agents encountering v1.0 files after v2.0 is released must:
  1. Detect version mismatch
  2. Inform user
  3. Run migration script if available
  4. Validate migrated file before use

---

## 29. Risk Register

| Risk | Likelihood | Impact | Prevention | Detection | Recovery |
|------|-----------|--------|-----------|-----------|---------|
| State loss on checkpoint write failure | Low | High | Atomic write (temp file + rename) | Schema validation at read | Re-sync from process-state.yaml |
| Stale evidence used as valid | Medium | High | `stale_if_commit_changes` flag; re-sync on resume | Commit comparison at resume | Mark STALE; re-evaluate |
| Incorrect gate restoration | Low | High | Gates only pass via gate skill; re-sync required | Gate state audit at resume | Re-run affected gate |
| Secret leakage into checkpoint | Low | Critical | Schema description warns; review before commit | Static grep for credential patterns | Remove and rotate credentials |
| Checkpoint corruption | Low | High | YAML syntax validation; additionalProperties check | Schema validation | Fall back to process-state.yaml |
| Schema incompatibility | Low | Medium | Version field required; agents check version | Version mismatch detection | Manual migration |
| Repository mismatch | Medium | Medium | Branch/commit comparison at resume | Conflict detection in re-sync | Conflict state; user decision |
| Duplicate memory authorities | Prevents if not addressed | High | Policy explicitly designates MxAgile as sole authority | Compliance check in review | Remove competing authority |
| Excessive HOT context | Medium | Medium | HOT context definition limits scope | Token count (when available) | Trim HOT; move to WARM |
| Rollover during unsafe operation | Low | High | Rollover safety conditions; safe boundary rules | Condition check before rollover | Defer rollover; note limitation |
| Repeated resumption loops | Low | Medium | Re-sync records result; loop detection | Epoch history length check | Manual reset of epoch |
| User instruction loss | Low | High | user_overrides preserved in checkpoint | user_overrides audit at resume | Reload from prior epoch |
| False completion | Low | Critical | Evidence state invariants; gate-only pass | Terminal state guard | Re-evaluate incomplete gates |
| Regression in non-context-managed flows | Low | High | enabled: false by default | FAST regression suite | Rollback to disabled |
| Generated artifact accumulation | Medium | Low | Gitignore for scratch; epoch archiving policy | File count monitoring | Archive or delete old epochs |
| Documentation drift | Medium | Medium | Docs reference schema and policy directly | Review at schema change | Update doc section 22 examples |
