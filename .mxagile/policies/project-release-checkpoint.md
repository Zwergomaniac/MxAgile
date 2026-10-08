# Policy: Project/Release Completion Checkpoint

Defines what happens after all currently authorized Feature Waves reach `done`.
Prevents MxAgile from returning MISSION_COMPLETE or proposing new product scope without
first evaluating whether the integrated product should receive a holistic review.

Maschinenlesbare Lifecycle-Definition: `.mxagile/lifecycle.yaml` § `feature_scope_completion`
Mission state tracking: `planning/mission/mission-state.yaml`
Terminal-State Guard: `policies/mission-completion.md`

---

## Completion Levels

These three levels are additions to the ordered completion hierarchy in
`policies/mission-completion.md`. They sit between ACCEPTANCE_COMPLETE and USER_MISSION_COMPLETE.

### FEATURE_SCOPE_COMPLETE

All currently authorized Feature Waves have reached `done`:

- Every Wave in `planning/execution-waves.md` is in terminal state `done`
- No active revision still requires implementation or verification
- No accepted Requirement is unassigned to a Wave
- No accepted Acceptance Criterion is known to be unfulfilled
- No open required change effect remains unresolved
- Feature-Scope Completeness Check has passed (see § Feature-Scope Completeness Check below)

**Does NOT imply:** UI/UX parity review done, functional integration verified,
PROJECT_RELEASE_REVIEW_COMPLETE, or USER_MISSION_COMPLETE.

### PROJECT_RELEASE_CHECKPOINT_PENDING

Feature delivery has reached a coherent boundary. The Project/Release Completion Checkpoint
must be offered or applied before:

- selecting new product scope
- syncing external Board scope for new features
- starting deferred NFR/Go-Live scope autonomously
- returning an unqualified MISSION_COMPLETE

### PROJECT_RELEASE_REVIEW_COMPLETE

The selected project-wide review scope has reached its legitimate terminal state:

- selected review profile executed
- remaining findings classified (VERIFIED, DEFERRED with rationale, or DECISION_REQUIRED)
- release-readiness result produced
- review record written to `planning/project-release/`

---

## Trigger Conditions

Evaluate the checkpoint when ALL of the following are true:

1. All Waves in `planning/execution-waves.md` are in terminal state `done`
2. No further authorized Feature Wave remains in the current mission scope
3. No active revision still requires implementation or verification
4. No accepted Requirement is unassigned to a Wave
5. The current mission reaches a coherent feature-delivery boundary

**Also trigger when the developer asks:**
- "Is the project / application / release ready?"
- "What should happen after all development Waves?"
- "Continue with the project." AND Feature Scope is complete

## Non-Trigger Conditions

Do NOT trigger the checkpoint when:

- One individual Wave is done while more authorized Waves remain
- One Requirement is implemented while others in the mission scope are not
- One revision completed while more authorized Waves remain
- The developer gave an explicitly implementation-only scoped mission
- The current mission intentionally excludes project-wide verification
- The developer already declined the review in the current mission (skip decision persisted)

---

## Feature-Scope Completeness Check

Before declaring FEATURE_SCOPE_COMPLETE or offering the project/release review,
verify that the supposedly complete Feature Scope is actually complete.

**This check exists because of a confirmed real failure mode:**

```
backend logic exists
+ implementation checklist says done
+ UI behavior required by Acceptance Criteria is not wired to any UI entry point
→ Wave falsely appears complete
→ PROJECT_RELEASE_CHECKPOINT would give a false "all waves done" signal
```

### Legacy Scope Reconciliation (Step 0)

Before running the completeness checks below, apply legacy reconciliation to any Wave
or requirement whose canonical `phase` is not yet `done`.

**A Wave with `phase != done` is not automatically `CURRENT_REQUIRED_SCOPE`.**

Full algorithm: `policies/legacy-completion-reconciliation.md`.

```
historical Waves found with phase != done
     OR legacy requirement artifacts with unclear status
     ↓
Apply Legacy Completion Classification for each item:
  VERIFIED_LEGACY_STATE            → count as done for this check; record basis
  CURRENT_REQUIRED_SCOPE           → genuine remaining work; see Completeness Check steps
  DEFERRED_OUTSIDE_FEATURE_SCOPE   → exclude from completeness check
  SUPERSEDED                       → exclude; trace to successor artifact
  GENUINE_DECISION_BLOCKER         → surface to developer; blocks FEATURE_SCOPE_COMPLETE
  UNKNOWN_REQUIRES_RECONCILIATION  → surface to developer; blocks until classified
     ↓
Continue completeness checks below using only CURRENT_REQUIRED_SCOPE items
```

Do NOT reopen implementation for `VERIFIED_LEGACY_STATE` items.
Do NOT start `DEFERRED_OUTSIDE_FEATURE_SCOPE` scope.
Do NOT fabricate authorization for `UNKNOWN_REQUIRES_RECONCILIATION` items.

### Completeness Checks

Execute all checks that are applicable to the current project:

#### 1. Requirement Coverage
- Every accepted Requirement is assigned to a Wave
- Every accepted Requirement's Wave has reached `done`
- No accepted Requirement has a status of STALE or REOPENED without explanation

#### 2. Acceptance Criteria Traceability
- Every Acceptance Criterion in every accepted Requirement is addressed by a
  Test Contract (TC-NNN) or has an explicit DEFERRED classification with rationale
- No AC that describes user-visible behavior is satisfied only by backend evidence

#### 3. UI Surface Reachability
For accepted Requirements with user-visible ACs:
- The UI surface(s) that satisfy the AC are present in the Mendix model
- The UI surfaces are reachable through navigation from the default landing page
  for at least one authorized Role
- `mxcli DESCRIBE pages` confirms the pages exist and are published

If UI surfaces are unreachable, the Wave is **not complete** regardless of checklist status.

#### 4. Implementation Wiring
- Required Microflows, Nanoflows, and DataSources referenced by accepted ACs are
  actually consumed by at least one published Page or Snippet
- Required change effects (D-effects from decisions) are resolved
- Entities required by UI screens are populated by reachable data sources

#### 5. Per-Wave Acceptance Evidence
- Each Wave in scope has a wave report at `planning/wave-reports/`
- Each wave report records `acceptance_gate: passed`
- No wave report has open `DECISION_REQUIRED` items without resolution

#### 6. Deferred vs Accepted Scope
- Identify all `deferred` checklist items and all `DEFERRED` acceptance criteria
- Confirm each has an explicit scope classification: either within accepted scope
  (and planned for a future authorized Wave) or out of scope for this mission
- Unclassified deferrals block FEATURE_SCOPE_COMPLETE

### If Completeness Check Fails

Do NOT open the Project/Release review.

Instead:
1. Report the specific completeness gap found
2. Determine the earliest necessary lifecycle phase for affected scope only
3. Preserve unaffected Wave results (do NOT restart entire Waves)
4. Reopen only the affected scope: STALE story spec, failed checklist items, missing wiring
5. Continue deterministically where authorized
6. Re-evaluate completeness after the repair

**Scoped return routing (from lifecycle.yaml § return_routing):**

| Gap found | Return to | Scope |
|---|---|---|
| AC describes UI behavior, UI not wired | implementing | Affected items only |
| Implementation artifact not called from UI | implementing | Affected checklist items |
| DECISION REQUIRED items unresolved | refinement | Affected story specs |
| Input resource changed | discovery | Affected stories only |

---

## User Interaction

When FEATURE_SCOPE_COMPLETE is confirmed, present a concise, non-technical checkpoint to the developer.

**Standard offer (use natural language, not internal terms):**

```
The planned Feature Scope is complete.

Would you like me to run a project-wide completion review?

This can include:
- overall UI/UX parity across all delivered screens
- functional parity across integrated user journeys
- cross-wave regression and integration validation
- role and authorization coverage
- detection and execution of existing automated tests
- remaining-gap classification
- release-readiness assessment

Choose: Quick Health Check / Integrated Product Review / Release Readiness Review / Skip
```

Do NOT present framework-internal vocabulary to the developer. Do NOT ask about:
- VPL materialization
- Verification Economics
- campaign taxonomy
- evidence layers
- lifecycle internals

The developer chooses the intended outcome; MxAgile selects the appropriate mechanisms.

---

## Behavior by Mission Intent

### A. Developer requested release-readiness explicitly

Trigger phrases: "bring to release readiness", "fully verify", "test everything",
"run overall parity", "is the project ready for go-live", or equivalent.

→ Project/Release review is already authorized in the mission scope.
→ Proceed autonomously with RELEASE_READINESS_REVIEW.
→ No additional review question required.

### B. Normal feature/revision mission without explicit release-wide request

Trigger: "Implement REV-017", "Implement REQ-084", "Continue with the project."
when Feature Scope reaches completion.

→ Run Feature-Scope Completeness Check.
→ If complete: present concise offer (§ User Interaction above).
→ Wait for one simple YES/NO or profile selection.
→ Do not ask repeatedly; store the decision in mission-state.yaml.

### C. Implementation-only mission

Trigger: "Only implement the model changes", "Just implement, don't verify."

→ Respect the narrower completion_boundary.
→ Do NOT run the project/release review automatically.
→ Report: "Project/Release review is available when you are ready."
→ Record in mission-state.yaml: `project_release_checkpoint.skipped: true` with reason.

### D. Developer says "Continue with the project." and Feature Scope is complete

→ Reconstruct state from `planning/mission/mission-state.yaml`.
→ If checkpoint was previously declined: respect the stored decision.
→ If checkpoint was never offered: present the offer now.
→ Do NOT invent or start new product scope.
→ Do NOT select a Board story as next work solely because it exists on the Board.
→ If no authorized scope remains: request product prioritization from the developer.

---

## Review Profiles

### QUICK_HEALTH_CHECK

Focus: Is the application functioning correctly for the core paths?

Scope:
- Application reachability (`APPLICATION_REACHABLE` per quality-gate policy)
- Core smoke paths: primary user journeys for each authorized Role
- Existing fast automated tests (if AVAILABLE_CURRENT)
- Major unresolved GAPs from per-Wave parity reports
- Compact readiness result

Excludes: deep cross-wave integration, full role/security regression, NFRs.

### INTEGRATED_PRODUCT_REVIEW

Focus: Does the integrated product meet all accepted Requirements end-to-end?

Scope:
- Overall UI/UX parity: all accepted screens against active target mockups
  (reuse valid per-Wave evidence; re-execute only for staleness or integration gaps)
- Functional parity: accepted Requirements, Decisions, Design Contracts, business flows
- Reachability: all required UI surfaces accessible for all authorized Roles
- Cross-Wave integration: user journeys that span multiple Waves
- Cross-Wave regression: shared entities, microflows, navigation, security roles
- Role and authorization coverage: full role capability contract
- Available automated tests (AVAILABLE_CURRENT and AVAILABLE_STALE after refresh)
- GAP classification: remaining gaps classified and bounded
- Release-readiness statement (excluding NFRs unless explicitly in accepted scope)

Includes: repair loop for authorized-scope gaps found during review (§ Gap Repair).

### RELEASE_READINESS_REVIEW

Focus: Is the application ready for the intended release target?

Scope: Everything in INTEGRATED_PRODUCT_REVIEW, plus:
- Non-functional readiness where requirements exist (performance, security, privacy)
- Environment and deployment prerequisites (if in authorized scope)
- Evidence that goes beyond functional acceptance
- Release-readiness classification with explicit human-approval gate if required

**RELEASE_READINESS_REVIEW does not claim Go-Live readiness when required external
or human approvals are absent.** External governance gates remain explicit.

---

## UI/UX Parity (Integrated Review)

For an authorized integrated UI/UX review:

1. Determine current accepted UI targets (`input-resources/ui-ux/` active revisions)
2. Identify all relevant screens and states (all accepted Requirements with UI surfaces)
3. Assess navigation and reachability across Roles
4. Assess cross-screen consistency (layout, widget patterns, Atlas theme)
5. Assess role variants (different UI states per role)
6. Assess integrated flows spanning multiple Waves (not verifiable per-Wave)
7. Compare against accepted Design Contract / active target mockup

**Evidence reuse:** Apply the seven-dimensional UI parity contract (`policies/ui-parity.md`).
Mark per-Wave evidence as REUSABLE where still valid. Re-execute only where:
- Integration across Waves creates new UI state not verifiable per-Wave
- Per-Wave evidence is STALE (upstream mockup or requirement changed)
- New screen appears unreachable in the integrated flow

Do NOT rerun every screenshot or browser path blindly.

---

## Functional Parity

Assess the integrated product against accepted scope:

**Assess:**
- Accepted Requirements: each AC satisfied with traceable evidence
- Accepted Decisions: implemented effects present
- Accepted Design Contracts: mockup → implementation fidelity
- Business flows: end-to-end flow reachable and functionally correct
- Role contracts: each authorized Role can complete their expected journeys
- Cross-Wave dependencies: functionality depending on multiple Wave outputs

**Specifically detect:**
- Unreachable backend functionality (microflow exists but no UI entry point)
- Unused implementation artifacts required by accepted ACs
- Functions with no UI/API entry point where ACs require one
- Cross-Wave integration gaps (Wave A output not consumed by Wave B)
- Contradictions between individually accepted Waves
- User journeys that cannot complete end-to-end

Do not infer completeness from isolated model object existence.

---

## Automated Test Discovery

Before presenting testing options, inspect what the project actually has.

### Detection

Check:
- `planning/test-contracts/TC-NNN.yaml` — existing Test Contracts
- `planning/verification-plans/VPL-NNN.yaml` — existing Verification Plans
- `planning/acceptance-campaigns/` — evidence from executed campaigns
- `tests/` — project-level test harnesses (PowerShell, Python, shell)
- CI workflows (`.github/workflows/`, if present)
- Playwright test files (`.spec.ts`, `.spec.js`, `.test.ts`)
- Smoke suites referenced by wave reports
- Test-data prerequisites and fixtures

### Classification

| Class | Meaning |
|---|---|
| `AVAILABLE_CURRENT` | Tests exist, still valid, infrastructure reachable |
| `AVAILABLE_STALE` | Tests exist, upstream source changed — refresh before run |
| `PARTIAL_COVERAGE` | Tests cover some scenarios; others need generation |
| `NO_AUTOMATION` | No test automation artifacts found |
| `INFRASTRUCTURE_BLOCKED` | Test infrastructure not available (no Playwright, no DB) |
| `UNKNOWN` | Tests referenced but not inspectable in current context |

Do not fabricate test automation.
Do not install heavy infrastructure merely because automation is absent.

### User Presentation

Present testing in normal developer language:

```
Automated tests are available for [N] of [M] relevant scenarios.
[K] scenarios need manual or new test coverage.

Options:
1. Run existing automated tests only
2. Run automated tests + generate missing coverage
3. Full integrated review
4. Skip for now
```

Use only measured project data. Do not invent counts.

If existing automated tests are safe, AVAILABLE_CURRENT, and included by the selected
review profile: execute them autonomously without additional confirmation.

If generating new automation creates significant project artifacts: follow current
mission/commit-authority contract.

---

## Cross-Wave Regression

Derive regression scope from existing artifacts — do not guess:

**Sources:**
- Artifact graph (`scripts/build_artifact_index.py` output)
- Change propagation vocabulary (CURRENT/CHANGED/IMPACT_REVIEW_REQUIRED in process-state)
- Affected Requirements, Specs, Decisions across Waves
- Shared entities and microflows referenced by multiple Waves
- Shared UI layouts, snippets, navigation structures
- Security roles spanning multiple Waves
- Platform/Company Layer boundaries

**Prefer targeted risk-based regression.** Do not default to rerunning every historical
browser campaign.

**However:** INTEGRATED_PRODUCT_REVIEW must include critical integrated user journeys
even when they cross several Waves, because per-Wave verification cannot validate
cross-Wave integration paths.

---

## Gap Repair

For confirmed project/release review findings:

**Classify the gap:**
- Source: which accepted Requirement, Decision, or Design Contract does it trace to?
- Authority: is this in accepted scope, deferred scope, or out of scope?
- Blast radius: LOCAL (one page/microflow) / REQUIREMENT / WAVE / CROSS_WAVE

**Route to the earliest necessary lifecycle phase** (from lifecycle.yaml § return_routing):
| Finding | Route to |
|---|---|
| Implementation defect (UI not wired, wrong behavior) | implementing |
| Specification gap (AC ambiguous or missing) | refinement |
| Fundamental missing context | discovery |

**Repair deterministic gaps** within accepted scope:
- Checkpoint commit after repair
- Lifecycle re-sync
- Re-run affected review scope (targeted, not full restart)

**Do NOT repair:**
- Deferred product scope
- Unaccepted backlog ideas
- Missing product-owner decisions
- Legal/privacy requirements requiring human authority
- External deployment configuration without explicit authority

The project/release review does not grant new product scope.

---

## Release-Readiness Result

After the selected review completes, produce one of these results:

| Result | Meaning |
|---|---|
| `PROJECT_HEALTHY_FOR_CURRENT_ACCEPTED_SCOPE` | All accepted Requirements verified; no open authorized gaps |
| `PROJECT_HEALTHY_WITH_LIMITATIONS` | Core accepted scope verified; limitations documented and classified |
| `PROJECT_GAPS_REQUIRE_REPAIR` | Authorized gaps found; repair work identified; not yet release-candidate |
| `PROJECT_DECISIONS_REQUIRED` | Open DECISION_REQUIRED items block acceptance; human input needed |
| `RELEASE_READINESS_NOT_ASSESSED` | Only QUICK_HEALTH_CHECK or INTEGRATED_PRODUCT_REVIEW run; NFR/deployment not assessed |
| `RELEASE_READINESS_BLOCKED` | Critical gap prevents release assessment |
| `RELEASE_READY_PENDING_HUMAN_APPROVAL` | All deterministic checks pass; release requires human governance gate |
| `RELEASE_READY` | All required evidence present and approved |

**A project may be PROJECT_HEALTHY_FOR_CURRENT_ACCEPTED_SCOPE while not being RELEASE_READY**
due to: deferred NFRs, privacy/legal approvals, performance evidence, deployment configuration,
infrastructure prerequisites, or human governance gates.

Do NOT collapse product correctness into production readiness.

---

## State and Artifacts

Use the smallest durable state model. Extend `planning/mission/mission-state.yaml`
with a `project_release_checkpoint` block (schema: `mission-state.schema.json`).

```yaml
project_release_checkpoint:
  status: not_evaluated | offered | accepted | declined | complete
  review_profile: QUICK_HEALTH_CHECK | INTEGRATED_PRODUCT_REVIEW | RELEASE_READINESS_REVIEW | null
  feature_scope_complete: true | false | null
  completeness_check_result: passed | failed | not_run
  completeness_gaps: []           # list of gap descriptions if failed
  review_result: null             # one of the readiness result vocabulary values above
  review_report: null             # path to planning/project-release/<report-file>.yaml
  skip_reason: null               # reason if status: declined
  decided_at: null                # YYYY-MM-DD
```

**Artifact path:** `planning/project-release/<mission-id>-release-review.yaml`

**Creation trigger:** When PROJECT_RELEASE_REVIEW_COMPLETE is reached.

**Archive:** On mission archive, move to `planning/project-release/archive/`.

**Do not create the artifact** merely because the checkpoint was offered.
Create it when a review actually runs and produces findings.

---

## Terminal-State Guard Integration

The Terminal-State Guard in `policies/mission-completion.md` is extended with:

**Additional guard check (step 8):**
> **Feature scope:** If all authorized Feature Waves are `done`, has the
> Project/Release Completion Checkpoint been evaluated?
> See `policies/project-release-checkpoint.md`.

**Additional guard result:**

| Result | Condition | Required Action |
|---|---|---|
| `PROJECT_RELEASE_CHECKPOINT_REQUIRED` | All Feature Waves done; checkpoint not yet offered; mission does not exclude it | Offer checkpoint per this policy; do not return MISSION_COMPLETE |

**Skip semantics:**
A developer decision to skip the optional review is legitimate and must be stored in
`planning/mission/mission-state.yaml` (`project_release_checkpoint.status: declined`).

Once stored:
- Do not offer again within the same mission
- `PROJECT_RELEASE_CHECKPOINT_REQUIRED` does NOT fire again
- `MISSION_COMPLETE` is permitted if all other mission criteria are satisfied

---

## Next-Scope Safety

After Feature Scope completion, MxAgile must NOT autonomously:

- start deferred NFR/go-live scope
- sync external Board scope for new features
- choose a Board backlog feature
- select any Board story as next work solely because it exists
- import or authorize scope from the Board
- implement technically attractive opportunities
- resolve unrelated historical Decisions

**Required order:**
1. Complete existing authorized scope
2. Run Feature-Scope Completeness Check
3. Offer/execute Project/Release Completion Checkpoint
4. Report integrated readiness result
5. Offer organizational Board completion reflection (if Board configured — status only)
6. Only then: identify whether a next authorized scope exists
7. If none: request product prioritization from the developer — NOT autonomous Board story selection

**Board Authority Guard (post-checkpoint):**
Absence of new authorized scope after PROJECT_RELEASE_REVIEW_COMPLETE results in
product prioritization / user authority, NOT autonomous Board story selection.
The Board may be mentioned as one surface where the developer can find candidate
work, but the agent MUST NOT select a Board item without explicit developer direction.
See `policies/backlog-sync.md` § Board Authority Contract.

---

## Simple Developer UX

### Scenario A: "Implement REV-017."

Expected behavior:
1. Lifecycle re-sync → current phase
2. If not Ready: discovery/refinement → get to Ready
3. Developer approval → Implementing
4. WAVE_IMPLEMENTATION_COMPLETE → Verifying (automatic)
5. Acceptance → Wave done
6. Repeat for all Waves in REV-017 scope
7. All Waves done → Feature-Scope Completeness Check
8. If complete: offer project/release review (one question)
9. Developer chooses profile → integrated review → readiness result
10. MISSION_COMPLETE → MISSION_REPORT → stop

Developer does NOT need to know: feature-scope levels, review profiles, evidence layers.

### Scenario B: "Bring the current project to release readiness."

Expected behavior:
1. Mission scope includes RELEASE_READINESS_REVIEW (derived from prompt)
2. Complete all remaining Feature Waves through Verifying
3. Feature-Scope Completeness Check
4. RELEASE_READINESS_REVIEW proceeds autonomously
5. Stops at genuine external/human gates
6. MISSION_COMPLETE → MISSION_REPORT

No additional review question required (already authorized in mission).

### Scenario C: "Continue with the project." when Feature Scope is complete

Expected behavior:
1. Reconstruct from `planning/mission/mission-state.yaml`
2. `project_release_checkpoint.status` = `not_evaluated` → offer the review
3. `project_release_checkpoint.status` = `declined` → respect stored decision, evaluate
   whether other mission criteria remain, then MISSION_COMPLETE if satisfied
4. Do NOT invent new product scope

### Scenario D: "Only implement the current Wave."

Expected behavior:
1. `completion_boundary: WAVE_IMPLEMENTATION_COMPLETE` honored
2. project/release review NOT run
3. Report: "Project/Release review available when you are ready."
4. `project_release_checkpoint.status: declined` with reason `implementation_only_scope`
