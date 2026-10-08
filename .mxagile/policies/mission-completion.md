# Policy: Mission Completion & Lifecycle Continuation

Defines what "done" means at each level of the MxAgile execution hierarchy,
prevents premature mission termination, and ensures deterministic lifecycle
continuation after phase transitions.

This policy addresses the autonomy failure class in which implementation-checklist
completion is incorrectly treated as USER_MISSION_COMPLETE.

Maschinenlesbare Lifecycle-Definition: `.mxagile/lifecycle.yaml`
State tracking: `planning/lifecycle/process-state.yaml`
Phase re-sync: `policies/lifecycle-resync.md`

---

## Completion Levels

These levels are ordered and are NOT synonyms.
A lower level NEVER implies the next level unless explicitly verified.

### IMPLEMENTATION_CHANGE_COMPLETE

A coherent technical mutation has passed the required implementation gates for
that change cluster:

- `mxcli check --references` passes
- `mxcli lint` passes (no critical findings)
- `mxcli exec` applied without error
- Checklist item marked `done`

**Does NOT imply:** checklist empty, wave complete, or anything above.

### WAVE_IMPLEMENTATION_COMPLETE

All implementation checklist items for the active Wave are in terminal state:
`done | blocked | deferred`

Per `lifecycle.yaml`: this is the **exit condition for the Implementing phase only**.

**Does NOT imply:** Verifying entered, wave verified, or anything above.

### REVISION_IMPLEMENTATION_COMPLETE

All authorized implementation scope for the active revision (across all Waves in scope)
has reached WAVE_IMPLEMENTATION_COMPLETE.

**Does NOT imply:** Verifying started, acceptance gate passed, or anything above.

### VERIFICATION_COMPLETE

All required verification campaigns and evidence obligations for the Wave are
complete or legitimately classified (DEFERRED with documented rationale):

- Verification Plans created (VPL-NNN.yaml) for all in-scope Test Contracts
- Quality-Gate passed (`mxcli check`, `mxcli lint`, `mxcli docker check`, APPLICATION_REACHABLE)
- UI-Agent Verify complete (parity report in `planning/ui-inventory/`)
- Acceptance-Agent campaigns complete (REQUIREMENT + ROLE + RISK_CHANGE_IMPACT where applicable)

**Does NOT imply:** Acceptance gate passed or USER_MISSION_COMPLETE.

### ACCEPTANCE_COMPLETE

The applicable acceptance gate has reached its valid terminal state:

- All REQUIREMENT campaigns: `status: PASS`
- All triggered ROLE campaigns: `status: PASS`
- All RISK_CHANGE_IMPACT campaigns: `status: PASS` (when applicable)
- No open `DECISION_REQUIRED` items
- All CRITICAL and MATERIAL GAPs: `VERIFIED` or `DEFERRED`
- Wave report written to `planning/wave-reports/`

Only after ACCEPTANCE_COMPLETE can a Wave transition to `done` in process-state.

**Does NOT imply:** USER_MISSION_COMPLETE unless the wave is the only criterion.

### FEATURE_SCOPE_COMPLETE

All currently authorized Feature Waves have reached `done` AND the Feature-Scope
Completeness Check has passed:

- Every Wave in `planning/execution-waves.md` is in terminal state `done`
  (or classified as `VERIFIED_LEGACY_STATE` — see legacy reconciliation below)
- No active revision still requires implementation or verification
- No accepted Requirement is unassigned to a Wave
- No accepted Acceptance Criterion is known to be unfulfilled without explicit DEFERRED classification
- No open required change effect remains unresolved
- Every user-visible Acceptance Criterion is satisfied by a reachable UI surface
  (not only by backend evidence)

**Historical Waves:** A Wave whose stored `phase` is not `done` is not automatically
`CURRENT_REQUIRED_SCOPE`. Apply legacy reconciliation before concluding incompleteness.
Full algorithm: `policies/legacy-completion-reconciliation.md`.

**Does NOT imply:** UI/UX parity review done, functional integration verified,
PROJECT_RELEASE_REVIEW_COMPLETE, or USER_MISSION_COMPLETE.

Full contract: `policies/project-release-checkpoint.md`

### PROJECT_RELEASE_CHECKPOINT_PENDING

Feature delivery has reached a coherent boundary. Before selecting new product scope
or assessing Go-Live readiness, the Project/Release Completion Checkpoint must be
offered or applied.

Full contract: `policies/project-release-checkpoint.md`

### PROJECT_RELEASE_REVIEW_COMPLETE

The selected project-wide review scope has reached its legitimate terminal state.
Remaining findings are classified. Release-readiness result is available in
`planning/project-release/`.

Full contract: `policies/project-release-checkpoint.md`

### USER_MISSION_COMPLETE

Every completion criterion explicitly or implicitly required by the current user
mission has reached its terminal state.

**Verification required:**

1. Current lifecycle phase = `done` (or all explicitly scoped phases complete)
2. All lifecycle-derived criteria satisfied (per lifecycle.yaml phases)
3. All user-additional criteria satisfied (from mission-state.yaml `criteria.additional`)
4. No unresolved deterministic work items remain
5. No genuine blockers that prevent further progress
6. If acceptance explicitly required human authority: human gate reached

**Only USER_MISSION_COMPLETE permits an unqualified "finished" response.**

---

## False Completion Equivalences (Forbidden)

The following MUST NOT be treated as USER_MISSION_COMPLETE:

| What happened | What it actually means |
|---|---|
| `mxcli check` passes | IMPLEMENTATION_CHANGE_COMPLETE (partial) |
| `mxcli docker check` passes | Build gate pass — no lifecycle meaning beyond |
| `git commit` created | Checkpoint recorded — NOT a stop condition |
| Implementation checklist empty | WAVE_IMPLEMENTATION_COMPLETE |
| Implementation report written | Reporting artifact created — NOT lifecycle completion |
| `delivery-report` file created | Report artifact — does NOT establish mission completion |
| Wave report written | Acceptance evidence recorded — NOT USER_MISSION_COMPLETE by itself |
| TODO list empty | Current working plan exhausted — evaluate wave and mission next |
| Build succeeds | Technical gate — NOT verification, NOT acceptance |
| All waves done | FEATURE_SCOPE_COMPLETE (pending completeness check) — NOT USER_MISSION_COMPLETE; project/release checkpoint must be evaluated |
| Implementation checklist wired + backend exists | NOT FEATURE_SCOPE_COMPLETE if UI ACs require reachable surfaces and none exist |
| Board contains new/unworked stories | NOT authorized scope — Board existence is not scope authorization |
| Board story changed or added | NOT a Wave reopen/create trigger — Board does not drive lifecycle |
| Board-Sync discovers unimplemented items | NOT a mission extension — Board context is read-only |
| Feature Scope complete + Board has more stories | NOT a continuation trigger — next scope requires explicit developer selection |
| Wave phase=verifying in session cache, canonical process-state shows done | NOT incomplete — canonical state wins; session cache is reconstructed from canonical |
| Historical report says "Review required", current canonical evidence shows complete | NOT a current work item — stale historical marker does not override canonical evidence |
| Requirement numbering gap in legacy migration | NOT missing authorized scope — authority must be established before treating as current scope |
| Old checklist has open item; wave report shows acceptance_gate: passed | NOT currently open — acceptance evidence outranks checklist entry |

---

## Phase-Boundary Continuation (Mandatory)

When the exit condition of the current lifecycle phase becomes true, the agent
MUST continue deterministically. This must not depend on the agent remembering
the original long prompt.

### Implementing → Verifying

When WAVE_IMPLEMENTATION_COMPLETE is reached (all checklist items terminal):

```
1. Persist checklist final state to planning/checklists/W*-implementation-checklist.yaml
2. Update planning/lifecycle/process-state.yaml — phase remains implementing until re-sync
3. Create checkpoint commit (if autonomous commit authority is delegated)
4. Run lifecycle re-sync (policies/lifecycle-resync.md)
5. lifecycle.yaml confirms: implementing.next = [verifying]
6. Enter Verifying — begin Step 1: Verification Plan Creation
7. Do NOT stop, do NOT ask user confirmation for this deterministic transition
```

**The transition implementing → verifying is deterministic and requires no user confirmation.**

If the agent has reached WAVE_IMPLEMENTATION_COMPLETE and has NOT entered Verifying,
this is a framework execution failure. The correct next action is always to enter Verifying.

### Verifying → Done

When ACCEPTANCE_COMPLETE is reached:

```
1. Write wave report to planning/wave-reports/
2. Update process-state.yaml — phase: done for this Wave
3. Create checkpoint commit (if authorized)
4. Run lifecycle re-sync
5. Are all authorized Feature Waves now done?
   YES →
     a. Run Feature-Scope Completeness Check (policies/project-release-checkpoint.md)
        - incomplete: reopen affected scope, continue deterministically
        - complete: FEATURE_SCOPE_COMPLETE
     b. Evaluate Project/Release Checkpoint (Terminal-State Guard check 8)
        - PROJECT_RELEASE_CHECKPOINT_REQUIRED → offer checkpoint, await decision
        - already offered/decided → respect stored decision
     c. If review selected: execute per review profile, reach PROJECT_RELEASE_REVIEW_COMPLETE
   NO →
     determine next Wave/action, continue
6. Evaluate Mission Completion (see Terminal-State Guard below)
7. If USER_MISSION_COMPLETE: produce MISSION_REPORT, stop
8. If mission criteria remain: determine next action, continue
```

---

## TODO → Mission Hierarchy

```
MISSION
  ↓ defines completion boundary
Lifecycle (lifecycle.yaml phases)
  ↓ structures progress
Wave (planning/execution-waves.md)
  ↓ organizes work
Working TODOs (implementation-checklist.yaml items)
```

**Rule: A lower level completing NEVER implies a higher level completing.**

When the working TODO list becomes empty:

```
TODO empty
→ evaluate Wave (all items terminal? any blocked/deferred?)
→ run lifecycle re-sync
→ lifecycle.yaml determines next phase
→ evaluate Mission (all criteria satisfied?)
→ if mission criteria remain: create next appropriate working plan, continue
→ if USER_MISSION_COMPLETE: terminal-state guard → MISSION_REPORT → stop
```

**A TODO list or implementation checklist becoming empty is never a reason to stop.
It is a reason to re-sync and evaluate the mission at the next level.**

---

## Terminal-State Guard

Before the agent produces any of the following:
- "done", "finished", "complete", "mission complete"
- A final delivery report
- An unqualified acceptance statement
- A response to "Are you finished?"

The agent MUST run the Terminal-State Guard:

### Guard Checklist

1. **Lifecycle phase:** What is the current phase in process-state.yaml?
2. **Phase exit gate:** Has the current phase's exit condition been met?
3. **Next phase:** What does lifecycle.yaml say is next?
4. **Mission criteria:** Are all USER_MISSION_COMPLETE criteria satisfied?
5. **Unresolved deterministic work:** Are there checklist items, campaigns, or
   evidence requirements that can be completed without genuine human input?
6. **Genuine blockers:** Is there a genuine blocker that prevents all remaining work?
7. **Human acceptance boundary:** Does the mission require human approval at this point?
8. **Feature scope:** If all authorized Feature Waves are `done`, has the
   Project/Release Completion Checkpoint been evaluated?
   See `policies/project-release-checkpoint.md`.

### Guard Results

| Result | Condition | Required Action |
|---|---|---|
| `CONTINUE_DETERMINISTICALLY` | Lifecycle phase incomplete OR next phase not entered OR unresolved deterministic work | Enter next phase, create next working plan, continue without stopping |
| `WAITING_FOR_GENUINE_DECISION` | A genuine business decision or DECISION_REQUIRED blocks all remaining work | Report blocking decision to user, stop until resolved |
| `WAITING_FOR_HUMAN_ACCEPTANCE` | All deterministic steps complete; acceptance explicitly requires human authority | Report acceptance-ready state, present evidence, stop at human gate |
| `PROJECT_RELEASE_CHECKPOINT_REQUIRED` | All Feature Waves done; checkpoint not yet offered; mission does not exclude it | Offer checkpoint per `policies/project-release-checkpoint.md`; do NOT return MISSION_COMPLETE |
| `MISSION_COMPLETE` | All USER_MISSION_COMPLETE criteria verified by guard; project/release checkpoint evaluated (offered, run, or legitimately skipped) | Produce MISSION_REPORT, stop |
| `MISSION_BLOCKED` | A blocker prevents ALL valid remaining actions | Report specific blocker, classify blast radius, stop |

**Only `MISSION_COMPLETE` permits an unqualified "finished" or terminal report.**

If guard result is `CONTINUE_DETERMINISTICALLY`:
- Do NOT tell the user you are done
- Do NOT produce a final report
- Enter the next lifecycle phase automatically
- Report: "IMPLEMENTATION_COMPLETE — MISSION_CONTINUES"

---

## Durable Mission Contract

### Purpose

The mission contract preserves user intent and completion criteria across:
- Long implementation runs
- TODO-list replacement
- Context compression
- Commits and phase transitions
- Interruptions and fresh-session resume

### Location

`planning/mission/mission-state.yaml` — Git-tracked, durable

### Schema Reference

`.mxagile/schemas/mission-state.schema.json`

### Lifecycle-Derived vs User-Additional Criteria

A **lifecycle-derived** criterion is one that MxAgile lifecycle.yaml prescribes
for any implementation mission (implementation, verification, acceptance).

A **user-additional** criterion is one explicitly stated in the user's mission
beyond normal lifecycle scope (parity audit, framework finding report, migration check, etc.).

Example:

User: "Implement REV-014"
→ lifecycle-derived criteria: implementing, verifying, acceptance (all from lifecycle.yaml)
→ user-additional criteria: none

User: "Implement REV-014 and report framework findings"
→ lifecycle-derived criteria: implementing, verifying, acceptance
→ user-additional criteria: framework_findings_report

User: "Only implement the model changes; don't run browser verification"
→ lifecycle-derived criteria: implementing only (explicit scope boundary honored)
→ user-additional criteria: none
→ completion_boundary: REVISION_IMPLEMENTATION_COMPLETE (not USER_MISSION_COMPLETE via full lifecycle)

### Creation

Create `planning/mission/mission-state.yaml` when:
- User gives a mission that spans more than one implementation checklist cycle
- User's prompt implies criteria beyond a single session's work

**Simple developer prompts map to full lifecycle by default:**

```
"Implement REQ-084"     → completion_boundary: ACCEPTANCE_COMPLETE (full wave lifecycle)
"Implement REV-014"     → completion_boundary: ACCEPTANCE_COMPLETE (all waves in revision)
"Continue with project" → completion_boundary: read from existing mission-state.yaml or derive from process-state
```

The developer does NOT need to enumerate lifecycle phases. The framework derives them.

### Update

Update `planning/mission/mission-state.yaml` as phases complete:
- Mark lifecycle-derived criteria as satisfied when verified
- Record completion evidence (process-state phase, wave report path, acceptance gate)

### Resume

On fresh session or context loss, reconstruct from repository evidence: mission and lifecycle
state are reproduced from `process-state.yaml` and `mission-state.yaml` — no stale session
cache required.

```
repository evidence
+ planning/lifecycle/process-state.yaml
+ planning/mission/mission-state.yaml
→ reconstruct active mission
→ reconstruct current lifecycle phase
→ reconstruct next deterministic action
→ continue
```

Do not persist ephemeral reasoning. Persist only the compact durable state
required for correct continuation. The mission record is NOT a transcript.

If `mission-state.yaml` does not exist, derive mission criteria from:
1. `process-state.yaml` (current phase tells you what work remains)
2. `planning/execution-waves.md` (planned waves)
3. The lifecycle.yaml default completion boundary

### Archive / Deletion

When USER_MISSION_COMPLETE:
- Move to `planning/mission/archive/YYYY-MM-DD-mission-state.yaml` (do not delete)
- Final mission-state.yaml must not be deleted before MISSION_REPORT is written

---

## Reporting Semantics

These report types are distinct. Creating one does NOT terminate the mission.

| Report | When created | Terminates mission? |
|---|---|---|
| `IMPLEMENTATION_REPORT` | After WAVE_IMPLEMENTATION_COMPLETE | NO — verifying remains |
| `WAVE_REPORT` | After ACCEPTANCE_COMPLETE for a wave | NO — subsequent waves or mission criteria may remain |
| `VERIFICATION_REPORT` | After VERIFICATION_COMPLETE | NO — acceptance gate may remain |
| `ACCEPTANCE_REPORT` | After ACCEPTANCE_COMPLETE | NO — other waves/criteria may remain |
| `MISSION_REPORT` | Only when USER_MISSION_COMPLETE | YES — legitimate terminal report |

A file named `delivery-report`, `wave-report`, or `implementation-report` does NOT
imply lifecycle completion. `planning/lifecycle/process-state.yaml` and
`planning/mission/mission-state.yaml` are the authoritative completion registers.

---

## Partial Blockers

A localized blocker must NOT automatically terminate the mission.

### Blast Radius Classification

When a blocker is encountered:

1. Classify the blocker type:
   - `INFRASTRUCTURE_GAP` — runtime not available, Playwright cannot start
   - `LOCATOR_UNSTABLE` — specific browser selector fails
   - `ROLE_SWITCH_BLOCKED` — specific role-switch path unavailable
   - `DECISION_REQUIRED` — business decision needed before this item
   - `SCOPE_EXCEEDED` — item outside authorized mission scope

2. Determine blast radius:
   - Does this blocker prevent only this specific item?
   - Does it block this role/page/requirement only?
   - Does it block ALL remaining verification?
   - Does it block ALL remaining mission work?

3. Continue everything not blocked:
   - Model proof (mxcli DESCRIBE)
   - Build proof (docker check)
   - Unaffected browser paths and roles
   - Other Requirements
   - Other Waves
   - Report preparation

4. Stop the WHOLE mission only if the blocker prevents ALL valid next actions.

### Classification Table

| Blocker | Continue | Stop |
|---|---|---|
| One Playwright locator unstable | All other paths | Only that locator assertion |
| One role-switch blocked | Other roles, model proof | Only that role-switch path |
| Runtime startup fails | Model+build evidence, report preparation | Browser-dependent assertions |
| One requirement's acceptance blocked | Other requirements' campaigns | Only that requirement's acceptance |
| Infrastructure proof unavailable | Model+build proof | Infrastructure-dependent evidence |

Report partial blockers clearly. Do not present "blocked path" as "whole mission blocked."

---

## Human Acceptance Boundary

Do NOT stop before the actual human gate.

Before stopping for genuine human approval:

1. Complete ALL deterministic preparation steps
2. Gather all required evidence (model, build, runtime, browser where available)
3. Complete all campaigns that can run autonomously
4. Produce the acceptance assessment document
5. Stop ONLY at the genuine human decision point

Stopping earlier before the human gate is a framework execution failure.

---

## Simple Developer UX

### Scenario A: "Implement REQ-084"

Expected framework behavior:
1. Lifecycle re-sync → determine current phase
2. If not Ready: complete discovery + refinement → get to Ready
3. Developer approval → enter Implementing
4. Implementation checklist → execute all items
5. WAVE_IMPLEMENTATION_COMPLETE → mandatory lifecycle re-sync → enter Verifying
6. Verification campaigns → ACCEPTANCE_COMPLETE
7. Wave report written
8. Mission evaluation → USER_MISSION_COMPLETE
9. MISSION_REPORT → stop

Developer does NOT need to say: lifecycle re-sync, gate-to-ready, verifying, campaigns.

### Scenario B: "Implement REV-014"

Same as A but across all Waves in the revision scope.
Between Waves: lifecycle re-sync → next Wave → continue.
Developer does NOT need to supervise wave transitions.

### Scenario C: "Continue with the project"

1. Read `planning/mission/mission-state.yaml` → active mission criteria
2. Read `planning/lifecycle/process-state.yaml` → current phase
3. Determine next deterministic action
4. Continue without mega-prompt

**Board Guard:** "Continue with the project" MUST NEVER select a Board item solely
because it exists. If no authorized MxAgile scope remains and no active mission
criteria are outstanding, the correct action is to request product prioritization
from the developer — not to autonomously import Board stories as next work.
See `policies/backlog-sync.md` § Board Authority Contract.

### Scenario D: "Only implement the model changes; don't run browser verification"

Explicit scope boundary honored:
- completion_boundary: REVISION_IMPLEMENTATION_COMPLETE (not full lifecycle)
- Framework does NOT proceed to Verifying
- Framework does NOT exceed user-authorized scope
- Mission record: `scope_boundary: implementation_only`

---

## Integration with Autonomy Policies

### Operating Mode Detection

`policies/operating-mode.md` governs when model mutations are safe.

Autonomous lifecycle continuation (implementing → verifying) requires:
- CLOSED_AUTONOM: full autonomous continuation permitted
- LIVE_SP_CURRENT: no model mutations; safe steps (planning, documentation) continue
- Detection MUST occur before first model mutation (not after)

### Checkpoint Commits

`policies/commit-authority.md` governs commit authority.

After a phase-boundary checkpoint commit:
- Record commit hash in mission-state.yaml
- Run lifecycle re-sync
- Enter next phase
- Continue WITHOUT waiting for user confirmation
- Do NOT produce a final report because a commit was created

See commit-authority.md § Continue After Commit.
