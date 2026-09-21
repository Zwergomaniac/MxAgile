# MXAGILE IMPLEMENTATION BACKLOG
## Stabilization, Integration, Pilot Validation and Framework Completion

This backlog defines the intended remaining MxAgile work program.

IMPORTANT:

This document is NOT evidence that a task is incomplete.

Before applying it, reconcile every item against the CURRENT LOCAL WORKSPACE,
because the agent may already have implemented or changed parts of this work.

For each item, use one of these statuses:

    NOT STARTED
    IN PROGRESS
    IMPLEMENTED, VALIDATION PENDING
    PARTIAL
    BLOCKED
    DECISION REQUIRED
    DONE
    NOT APPLICABLE
    SUPERSEDED

A task may only be marked DONE when its Acceptance Criteria are satisfied or
explicitly documented as not applicable.

Do not downgrade already completed and validated work merely because it appears
in this backlog.

Do not create duplicate implementations.

Do not create duplicate TODO systems.

Reconcile this backlog into the existing canonical development plan.

======================================================================
AUTHORITATIVE DECISIONS
======================================================================

DECISION D-001: CURRENT OVERALL PHASE

Status:
    APPROVED

Decision:

The overall framework phase is:

    Stabilization, Integration and Pilot Validation

Do not classify the entire project as being in pure maintenance mode until the
major lifecycle capabilities have been validated together.

Individual mature capabilities may already be maintained incrementally.

Acceptance Criteria:

- Current documentation uses honest phase terminology.
- The phase is not changed to Maintenance solely because one pilot passes.
- Entry criteria for Maintenance are documented.


DECISION D-002: HYBRID LIFECYCLE

Status:
    APPROVED

Decision:

MxAgile supports a controlled Hybrid lifecycle during migration.

Legacy artifact paths may include:

    planning/stories/
    planning/checklists/
    existing execution waves

Preferred target artifact paths include:

    requirements/
    specs/
    planning/tasks/

Existing projects must not require a destructive big-bang migration.

Acceptance Criteria:

- Legacy artifacts remain readable where required.
- New projects use the intended current structure.
- Migration is explicit.
- Migration does not silently discard unsupported content.
- Canonical ownership is documented.
- Hybrid does not mean permanent uncontrolled duplication.



DECISION D-004: BROWNFIELD ADOPTION

Status:
    APPROVED

Decision:

Brownfield adoption uses a non-destructive skeleton-injection approach.

Existing implementation reality is reconstructed as CURRENT STATE.

Historical requirements must not be fabricated.

Acceptance Criteria:

- Existing project logic is preserved.
- Partial prior adoption is detected.
- Repeated adoption is safe.
- Observed behavior is distinguished from inferred intent.
- An adoption report is produced.
- Legacy, Hybrid or Native state is identified where possible.


DECISION D-005: SECRET MANAGEMENT

Status:
    APPROVED

Decision:

Secrets remain manually managed in local environment configuration such as:

    .env.mendix

The previous password finding was false.

Acceptance Criteria:

- No secret values are committed.
- Example values remain safe.
- Local secrets are not printed in reports or logs.
- The false password finding is not retained as active work.


DECISION D-006: SCRIPT FINDINGS

Status:
    APPROVED

Decision:

The prior claim that several scripts were syntactically broken or truncated
was false.

Acceptance Criteria:

- Valid scripts are not modified merely to satisfy the old assessment.
- Parser validity remains testable.
- Behavioral incompleteness is assessed separately from syntax validity.
- The false finding is recorded as resolved by falsification, not by repair.


DECISION D-007: ARTIFACT TRACE INDEX

Status:
    APPROVED

Decision:

MxAgile uses ONE canonical deterministic Artifact Trace Index.

The index is derived state.

Canonical lifecycle information remains in canonical lifecycle artifacts.

Acceptance Criteria:

- The index can be deleted and rebuilt without lifecycle information loss.
- Agents do not manually maintain graph nodes or edges.
- Full rebuild remains authoritative.
- Incremental indexing, if ever added, is optimization only.
- Trace, Refine, Analyze and Converge use the canonical mechanism where relevant.
- MxAgile does not become a generic Graphify replacement.


DECISION D-008: WORKFLOW-OWNED CONSISTENCY

Status:
    APPROVED

Decision:

Consistency is enforced through commands, scripts, skills and validation
workflows rather than relying primarily on an agent remembering to update
derived state.

Acceptance Criteria:

- Generated trace state is not manually edited.
- Lifecycle-changing workflows rebuild or validate traceability.
- AGENT.md contains principles and routing rules, not excessive procedural detail.
- Operational details live in focused skills or deterministic scripts.


DECISION D-009: PAGE YAML

Status:
    APPROVED

Decision:

Page YAML remains a first-class semantic lifecycle artifact between executable
HTML mockups and downstream requirements/implementation work.

Acceptance Criteria:

- Page YAML has a defined schema.
- Page YAML has stable identity.
- Page YAML participates in traceability.
- At least one consumer uses it meaningfully.
- It is not generated and then ignored.
- HTML changes do not automatically authorize semantic requirement changes.


DECISION D-010: INFERENCE

Status:
    APPROVED

Decision:

    INFERENCE IS NOT CONFIRMATION

Acceptance Criteria:

- Inferred relationships are distinguishable from declared relationships.
- Inferred Brownfield intent is labeled.
- Name similarity does not create authoritative lifecycle relationships.
- Convergence does not treat unconfirmed inference as accepted evidence.



======================================================================
WORK PACKAGE 0: WORKSPACE RECONCILIATION
======================================================================

Status:
    DONE

Note:
    Validated by session checkpoint and repository state.

Objective:

Reconcile this backlog with all work already completed since the previous
handover and avoid overwriting valid ongoing work.

TODO:

- [x] Capture current Git status without modifying it.
- [x] Inventory modified tracked files.
- [x] Inventory untracked files relevant to MxAgile.
- [x] Identify ignored files relevant to testing and integration.
- [x] Identify files modified since the last development-plan update.
- [x] Read the current TODO/development plan.
- [x] Read current decision records.
- [x] Inspect all currently active Claude Code TODOs.
- [x] Identify any work in progress.
- [x] Identify partially completed edits.
- [x] Identify generated files that may currently be stale.
- [x] Identify tests added or changed during the ongoing session.
- [x] Reconcile existing TODOs with this backlog.
- [x] Preserve valid completed work.
- [x] Merge overlapping work packages.
- [x] Remove or mark obsolete TODOs.
- [x] Record newly discovered architecture decisions.
- [x] Do not revert current work merely because it differs from the earlier plan.

Suggested approach:

Create a short reconciliation section in the persistent plan:

    Work discovered since handover
    Completed and retained
    In progress and retained
    Conflicts requiring resolution
    New work introduced
    Superseded recommendations

Acceptance Criteria:

- No ongoing valid edit is accidentally reverted.
- Existing completed work is not recreated.
- Existing TODOs and this backlog result in one canonical plan.
- Repository status is understood before new structural edits.
- Any conflicting implementation is surfaced explicitly.


======================================================================
WORK PACKAGE 1: DEVELOPMENT PLAN CORRECTION
======================================================================

Status:
    DONE

Note:
    Validated by session checkpoint and repository state.

Objective:

Turn the current optimistic progress list into an evidence-based implementation
and validation plan.

TODO:

- [x] Rename the active phase to Stabilization, Integration and Pilot Validation.
- [x] Record the false password finding.
- [x] Record the false malformed-script finding.
- [x] Record Company Layer separation as intentional.
- [x] Replace unsupported broad DONE statuses with evidence-based statuses.
- [x] Add validation evidence references to completed capabilities.
- [x] Separate implementation status from validation status.
- [x] Add missing work packages for Page YAML.
- [x] Add missing work packages for Feature Specs.
- [x] Add missing work packages for Mendix-native plans.
- [x] Add missing work packages for Tasks and Hybrid migration.
- [x] Add missing work packages for Artifact Trace Index consolidation.
- [x] Add missing work packages for Analyze.
- [x] Add missing work packages for Reconciliation.
- [x] Add missing work packages for Brownfield pilot validation.
- [x] Add explicit Maintenance entry criteria.

Suggested plan format:

    Capability
    Status
    Validation Status
    Implementation
    Evidence
    Known Gaps
    Next Action

Acceptance Criteria:

- The plan distinguishes created, implemented, integrated and validated.
- False findings are not active backlog items.
- All major lifecycle capabilities are represented.
- Completed status is backed by evidence.
- The plan is concise enough to remain maintainable.


======================================================================
WORK PACKAGE 2: TEST HARNESS FOUNDATION
======================================================================

Status:
    DONE

Note:
    Validated by session checkpoint and repository state.

Objective:

Create a repeatable framework-level validation foundation before additional
large architectural migrations.

TODO:

- [x] Verify PowerShell parser checking.
- [x] Verify Python compilation/import checking.
- [x] Verify JSON Schema validation.
- [x] Verify YAML parsing.
- [x] Add a single documented framework test entry point.
- [x] Ensure tests return reliable exit codes.
- [x] Ensure test failures identify the failing capability.
- [x] Separate fast tests from environment-dependent tests.
- [x] Add a test-result summary.
- [x] Add deterministic temporary workspace creation.
- [x] Ensure temporary test workspaces are cleaned safely.
- [x] Preserve failed fixtures/output when useful for diagnosis.
- [x] Ensure tests do not operate destructively on the source repository.
- [x] Ensure tests do not require production/customer projects.
- [x] Add synthetic sanitized fixtures.
- [x] Document which tests require mxcli.
- [x] Document which tests require Docker.
- [x] Document which tests require Studio Pro.
- [x] Document which tests require Playwright.
- [x] Classify skipped tests clearly.

Suggested test levels:

    Level 1: parser/schema
    Level 2: deterministic unit tests
    Level 3: filesystem workflow tests
    Level 4: mxcli/Mendix/tool integration
    Level 5: non-production pilot

Acceptance Criteria:

- One documented command runs the normal framework test suite.
- Fast tests do not require Studio Pro.
- Tests do not expose secrets.
- Failed tests produce actionable output.
- Environment-dependent tests are reported as skipped, not falsely passed.
- Test execution does not mutate the real project unexpectedly.


======================================================================
WORK PACKAGE 3: INITIALIZATION
======================================================================

Status:
    DONE

Note:
    Validated by session checkpoint and repository state.

Objective:

Make project initialization reproducible, safe and idempotent.

TODO:

- [x] Test initialization into an empty fixture.
- [x] Test repeated initialization.
- [x] Test initialization into a partially initialized fixture.
- [x] Test initialization when legacy paths exist.
- [x] Test initialization when target paths already exist.
- [x] Test behavior when required tools are unavailable.
- [x] Test behavior when an installed layer exists.
- [x] Test behavior when local config exists.
- [x] Verify generated versus maintained file ownership.
- [x] Ensure initialization does not overwrite human-maintained content.
- [x] Ensure initialization reports preserved/skipped/conflicting files.
- [x] Validate initialized schemas and configuration.
- [x] Document initialization order relative to mxcli init.
- [x] Document initialization order relative to agent setup.
- [x] Add dry-run/preview if justified by actual risk.
- [x] Verify Windows Local operation.

Possible solution:

Create an initialization manifest that describes:

    source template
    destination
    ownership
    overwrite policy
    merge policy
    generated status

Do not introduce a manifest unless it simplifies existing behavior.

Acceptance Criteria:

- Clean init succeeds.
- Repeated init is safe.
- Partial init produces understandable recovery behavior.
- Existing human content is preserved.
- Active layers remain valid.
- Local secrets/configuration are not overwritten.
- Output clearly identifies resulting project mode.



======================================================================
WORK PACKAGE 5: ARTIFACT TRACE INDEX CONSOLIDATION
======================================================================

Status:
    DONE

Note:
    Validated by session checkpoint and repository state.

Objective:

Consolidate build_trace_index and build_artifact_graph into one canonical,
deterministic Artifact Trace Index.

TODO:

- [x] Inventory existing trace builder.
- [x] Inventory existing artifact graph builder.
- [x] Inventory both schemas.
- [x] Inventory both generated outputs.
- [x] Inventory all producers.
- [x] Inventory all consumers.
- [x] Inventory tests.
- [x] Inventory documentation references.
- [x] Compare node types.
- [x] Compare edge types.
- [x] Compare hashes.
- [x] Compare stale-state handling.
- [x] Compare provenance.
- [x] Identify unique information in each mechanism.
- [x] Identify graph-only information.
- [x] Move graph-only canonical information into source artifacts where needed.
- [x] Decide canonical script/module names.
- [x] Decide canonical output file.
- [x] Define canonical schema.
- [x] Define deterministic ordering.
- [x] Define generated metadata policy.
- [x] Implement or adapt the canonical full builder.
- [x] Add compatibility adapter for old consumers if needed.
- [x] Migrate trace consumer.
- [x] Migrate refine consumer.
- [x] Migrate analyze consumer.
- [x] Migrate converge consumer.
- [x] Deprecate redundant builder.
- [x] Remove redundant implementation only when consumers are migrated.
- [x] Update generated-file ownership documentation.
- [x] Update migration documentation.

Recommended design:

    canonical artifacts
            |
            v
    deterministic parsers
            |
            v
    canonical Artifact Trace Index
            |
      trace/refine/analyze/converge

Recommended generated file properties:

    schema version
    framework version if useful
    nodes
    edges
    diagnostics
    source hashes if needed
    deterministic ordering

Do not place unique business decisions in the generated index.

Acceptance Criteria:

- Generated index can be deleted and rebuilt.
- Rebuilding twice is semantically identical.
- No required lifecycle information exists only in the index.
- All active consumers use the canonical mechanism.
- Old mechanisms are migrated or explicitly deprecated.
- Broken references are visible.
- Duplicate IDs are visible.
- Generated state is not manually edited.
- Full rebuild is the correctness reference.
- No generic graph/database platform is introduced.


======================================================================
WORK PACKAGE 6: TRACE NODE AND EDGE SEMANTICS
======================================================================

Status:
    DONE

Note:
    Validated by session checkpoint and repository state.

Objective:

Define trace semantics precisely enough for Refine, Analyze and Converge.

Candidate node types:

    MOCKUP
    PAGE
    REQUIREMENT
    SPEC
    PLAN
    TASK
    MENDIX_ARTIFACT
    VALIDATION_EVIDENCE
    DECISION
    LAYER

Use only types justified by actual consumers.

Candidate edge types:

    DERIVED_FROM
    DESCRIBES
    REFERENCES
    INCLUDED_IN
    PLANNED_BY
    IMPLEMENTED_BY
    IMPLEMENTS
    VERIFIED_BY
    DEPENDS_ON
    SUPERSEDES
    AFFECTS

Do not introduce every candidate automatically.

TODO:

- [x] Define minimum required node types.
- [x] Define minimum required edge types.
- [x] Define stable ID rules.
- [x] Define duplicate ID behavior.
- [x] Define missing reference behavior.
- [x] Define edge source/provenance.
- [x] Define declared relationship behavior.
- [x] Define derived relationship behavior.
- [x] Define inferred relationship behavior if needed.
- [x] Define stale state representation.
- [x] Define diagnostic severity.
- [x] Define legacy artifact representation.
- [x] Define migrated artifact representation.
- [x] Define Mendix reference format.
- [x] Avoid copying full mxcli reference graphs.
- [x] Add schema tests.
- [x] Add extraction tests.
- [x] Add negative tests.

Recommended provenance model:

    DECLARED
    DERIVED
    INFERRED

Recommended rule:

    An inferred edge must never satisfy an acceptance requirement that demands
    explicit traceability unless a confirmation workflow promotes it into a
    canonical declared relationship.

Acceptance Criteria:

- Every edge can be explained.
- Source location is available where feasible.
- Inference remains distinguishable.
- Name similarity alone is not authoritative.
- Stable IDs survive safe migration.
- Broken links do not disappear silently.


======================================================================
WORK PACKAGE 7: PAGE YAML LIFECYCLE
======================================================================

Status:
    DONE

Note:
    Validated by session checkpoint and repository state.

Objective:

Make Page YAML a meaningful first-class artifact.

TODO:

- [x] Inventory existing Page YAML schema.
- [x] Inventory existing generated Page YAML examples.
- [x] Identify the current generator.
- [x] Identify the current validator.
- [x] Identify all current consumers.
- [x] Define stable Page ID.
- [x] Define mockup source reference.
- [x] Define Page YAML ownership.
- [x] Define generated versus manually enriched fields.
- [x] Define regeneration behavior.
- [x] Protect human-maintained semantic content.
- [x] Represent sections/components/fields/actions/states as needed.
- [x] Represent navigation references.
- [x] Represent role/security hints where appropriate.
- [x] Represent relevant requirement references.
- [x] Represent relevant Mendix mapping hints without overcommitting.
- [x] Add trace-index extraction.
- [x] Add schema validation.
- [x] Add mockup change tests.
- [x] Add UI verification linkage.
- [x] Add at least one complete fixture.

Possible solution:

Separate fields conceptually into:

    observed from mockup
    semantically interpreted
    explicitly confirmed
    implementation mapping

Do not claim that all of these must be separate files.

Acceptance Criteria:

- Page YAML validates.
- Page YAML has stable identity.
- Mockup provenance is recorded.
- Regeneration does not silently destroy confirmed semantic content.
- Requirements can reference Page IDs.
- Trace Index includes Page relationships.
- Refine can identify affected Pages.
- At least one downstream workflow consumes Page YAML.


======================================================================
WORK PACKAGE 8: REFINEMENT ENGINE
======================================================================

Status:
    DONE

Note:
    Validated by session checkpoint and repository state.

Objective:

Detect upstream changes, classify their significance and identify affected
lifecycle artifacts without silently rewriting accepted intent.

TODO:

- [x] Verify baseline creation.
- [x] Verify baseline update policy.
- [x] Verify hierarchical hashing.
- [x] Verify meaningful normalization.
- [x] Avoid treating irrelevant formatting as semantic change where possible.
- [x] Detect added artifacts.
- [x] Detect modified artifacts.
- [x] Detect deleted artifacts.
- [x] Classify visual changes.
- [x] Classify content changes.
- [x] Classify interaction changes.
- [x] Classify navigation changes.
- [x] Classify data changes.
- [x] Classify business behavior changes.
- [x] Classify validation changes.
- [x] Classify security changes.
- [x] Classify integration changes.
- [x] Support UNKNOWN classification.
- [x] Determine directly affected artifacts.
- [x] Determine transitively affected artifacts.
- [x] Use Artifact Trace Index.
- [x] Create explainable impact report.
- [x] Mark review state without auto-rewriting accepted semantics.
- [x] Add positive test cases.
- [x] Add ambiguous test cases.
- [x] Add deletion test cases.
- [x] Add tests protecting accepted requirements.

Suggested impact levels:

    DEFINITELY_AFFECTED
    PROBABLY_AFFECTED
    POTENTIALLY_AFFECTED

Use different terms if the current model already has suitable semantics.

Acceptance Criteria:

- Change detection is reproducible.
- Impact is explainable.
- Direct and transitive impact are distinguishable.
- A visual-only change does not automatically invalidate business intent.
- A security or validation change is not treated as cosmetic.
- Accepted Requirements are not silently overwritten.
- UNKNOWN changes are surfaced for review.


======================================================================
WORK PACKAGE 9: RECONCILIATION
======================================================================

Objective:

Provide a controlled human/agent workflow to resolve refinement impacts.

TODO:

- [x] Inspect current reconcile implementation.
- [x] Identify whether it only generates a report.
- [x] Define proposal format.
- [x] Show old and new evidence.
- [x] Show affected artifact chain.
- [x] Show accepted decisions.
- [x] Generate candidate changes without silently applying semantic changes.
- [x] Preserve manual sections.
- [x] Require approval for requirement/spec meaning changes.
- [x] Apply approved changes.
- [x] Update baselines only after appropriate confirmation.
- [x] Rebuild Trace Index.
- [x] Re-run Analyze.
- [x] Re-run Converge where appropriate.
- [x] Record remaining unresolved items.
- [x] Add rejection scenario.
- [x] Add partial-approval scenario.
- [x] Add rerun/idempotency scenario.

Acceptance Criteria:

- Reconciliation cannot silently replace accepted business intent.
- Proposed changes are reviewable.
- Rejected proposals preserve current accepted artifacts.
- Approved changes propagate predictably.
- Manual content is preserved.
- Traceability remains consistent afterward.


======================================================================
WORK PACKAGE 10: REQUIREMENTS
======================================================================

Objective:

Ensure atomic requirements are stable, traceable and migration-friendly.

TODO:

- [ ] Define/verify Requirement schema.
- [ ] Verify stable ID rules.
- [ ] Verify provenance/reference fields.
- [ ] Verify role representation.
- [ ] Verify business-rule representation.
- [ ] Verify validation intent.
- [ ] Verify acceptance conditions.
- [ ] Verify assumptions.
- [ ] Verify status/state.
- [ ] Verify stale/review state.
- [ ] Verify external source references.
- [ ] Add schema tests.
- [ ] Add migration from legacy story format.
- [ ] Preserve unsupported legacy content.
- [ ] Ensure migration is idempotent.
- [ ] Avoid fictional splitting when semantics are ambiguous.
- [ ] Report decisions required.

Acceptance Criteria:

- Requirement IDs are stable.
- Requirements are not derived solely from filenames.
- Provenance is available.
- Migration preserves meaningful content.
- Unsupported content is reported.
- Requirements can be traced to specs and evidence.
- Manual changes survive rebuilds.


======================================================================
WORK PACKAGE 11: LIVING FEATURE SPECIFICATIONS
======================================================================

Objective:

Make Feature Specs coherent accepted behavior descriptions connected to atomic
Requirements.

TODO:

- [x] Define/verify Spec schema.
- [x] Verify stable Spec ID.
- [x] Reference included Requirements explicitly.
- [x] Represent coherent feature behavior.
- [x] Represent roles where appropriate.
- [x] Represent flows/scenarios where appropriate.
- [x] Represent constraints.
- [x] Represent assumptions.
- [x] Represent decisions.
- [x] Represent acceptance behavior.
- [x] Represent known deviations.
- [x] Represent stale/review state.
- [x] Link to Page YAML where relevant.
- [x] Link to plan.
- [x] Link to validation expectations.
- [x] Add broken requirement reference tests.
- [x] Add stale propagation tests.
- [x] Avoid copying every Requirement field without purpose.

Acceptance Criteria:

- Specs are not isolated documents.
- Every accepted Spec can explain its Requirement coverage.
- Missing Requirements are reported.
- Changed Requirements can mark dependent Specs for review.
- Specs can be traced to plans/tasks/evidence.
- Specs remain readable to humans.


======================================================================
WORK PACKAGE 12: MENDIX-NATIVE PLANNING
======================================================================

Objective:

Produce implementation plans that describe Mendix architecture without
duplicating mxcli skill internals.

TODO:

- [x] Inspect current plan generator.
- [x] Inspect current wave plan generator.
- [x] Identify domain-model-only assumptions.
- [x] Define minimum plan schema/structure.
- [x] Reference source Spec.
- [x] Reference Requirements.
- [x] Reference Pages.
- [x] Identify affected modules.
- [x] Identify domain model work.
- [x] Identify page/UI work.
- [x] Identify microflow/nanoflow work.
- [x] Identify security work.
- [x] Identify navigation work.
- [x] Identify integration work.
- [x] Identify platform/module reuse.
- [x] Identify migration impact.
- [x] Identify test/verification strategy.
- [x] Avoid low-level MDL duplication.
- [x] Add representative planning fixtures.
- [x] Add validation tests.
- [x] Add unsupported/ambiguous planning scenario.

Acceptance Criteria:

- A UI-heavy feature is not reduced to an entity script.
- A security change appears in the plan.
- Relevant Pages and Requirements are referenced.
- Plan is detailed enough to create Tasks.
- Plan delegates low-level Mendix operations to mxcli skills.


======================================================================
WORK PACKAGE 13: TASKS, CHECKLISTS AND WAVES
======================================================================

Objective:

Create an actionable target Task model while preserving controlled Legacy and
Hybrid compatibility.

TODO:

- [x] Inventory current checklist format.
- [x] Inventory current task format.
- [x] Inventory wave format.
- [x] Identify orchestrator consumers.
- [x] Define canonical format for new projects.
- [x] Define legacy-read behavior.
- [x] Define migration behavior.
- [x] Preserve stable IDs.
- [x] Preserve requirement references.
- [x] Preserve spec references.
- [x] Preserve validation intent.
- [x] Preserve dependencies.
- [x] Detect unmappable fields.
- [x] Add migration dry run.
- [x] Add collision detection.
- [x] Add repeat migration test.
- [x] Add partial migration test.
- [x] Add unsupported legacy content test.
- [x] Define Task completion evidence.
- [x] Define Task verification fields.
- [x] Keep Tasks reasonably sized.
- [x] Avoid embedding giant agent prompts.

Suggested target Task content:

    task ID
    objective
    source Spec
    Requirements
    Pages
    dependencies
    expected Mendix artifact categories
    implementation notes
    validation expectations
    status
    evidence references

Acceptance Criteria:

- Existing projects can remain Hybrid.
- New Tasks are traceable.
- Migration does not silently lose semantics.
- Repeated migration is safe.
- Task completion requires meaningful evidence.
- Existing orchestrator behavior is either supported or migrated.


======================================================================
WORK PACKAGE 14: BROWNFIELD ADOPTION
======================================================================

Objective:

Validate the adoption mechanism beyond skeleton creation.

TODO:

- [x] Test clean legacy fixture.
- [x] Test fixture with existing docs.
- [x] Test fixture with legacy planning artifacts.
- [x] Test fixture with partial MxAgile structure.
- [x] Test repeated adoption.

- [x] Test local environment preservation.
- [x] Test collision behavior.
- [x] Test unsupported state.
- [x] Add dry-run/preview if appropriate.
- [x] Classify project as Legacy/Hybrid/Native where possible.
- [x] Generate adoption report.
- [x] Record observed current state.
- [x] Label inferred intent.
- [x] Avoid invented historical requirements.
- [x] Recommend next migration actions.
- [x] Rebuild Artifact Trace Index after adoption.
- [x] Run Analyze after adoption.
- [x] Keep original project logic unchanged.
- [x] Document rollback/manual recovery.

Acceptance Criteria:

- No existing project logic is overwritten.
- Repeated adoption is safe.
- Partial adoption is recognized.
- Local secrets/config remain local.
- Adoption report is understandable.
- Current state and inference are distinguished.
- The resulting project can proceed in Hybrid mode.


======================================================================
WORK PACKAGE 15: GLOBAL ANALYZE
======================================================================

Objective:

Provide actionable lifecycle diagnostics across the repository.

TODO:

- [x] Detect duplicate stable IDs.
- [x] Detect broken references.
- [x] Detect orphan Requirements.
- [x] Detect Requirements absent from Specs.
- [x] Detect Specs with missing Requirements.
- [x] Detect Plans without accepted Specs.
- [x] Detect Tasks without traceability.
- [x] Detect stale Page YAML.
- [x] Detect stale Specs.
- [x] Detect incomplete migration.
- [x] Detect legacy artifact still consumed unexpectedly.
- [x] Detect invalid active Layer state.
- [x] Detect missing validation evidence.
- [x] Detect unresolved decisions.
- [x] Detect conflicting lifecycle states.
- [x] Add severity.
- [x] Add evidence/source location.
- [x] Add remediation guidance.
- [x] Suppress low-value noise.
- [x] Add positive fixture.
- [x] Add negative fixture.
- [x] Add mixed Hybrid fixture.

Acceptance Criteria:

- Analyze finds intentionally seeded defects.
- Clean fixture does not produce misleading critical findings.
- Every diagnostic explains source and remediation.
- Output differentiates error, warning and information.
- Analyze consumes the canonical Trace Index where appropriate.


======================================================================
WORK PACKAGE 16: CONVERGENCE
======================================================================

Objective:

Determine whether accepted feature intent is actually complete and evidenced.

TODO:

- [x] Define convergence scope.
- [x] Define feature identity.
- [x] Verify Requirement coverage.
- [x] Verify Spec coverage.
- [x] Verify Page relevance where applicable.
- [x] Verify Plan existence/coverage.
- [x] Verify Task completion.
- [x] Verify Task evidence.
- [x] Verify implementation references.
- [x] Verify technical validation evidence.
- [x] Verify UI verification evidence when required.
- [x] Verify acceptance evidence.
- [x] Reject stale artifacts.
- [x] Surface unresolved decisions.
- [x] Surface known deviations.
- [x] Surface broken references.
- [x] Distinguish missing evidence from failed validation.
- [x] Add false-completion test.
- [x] Add placeholder-evidence test.
- [x] Add stale-feature test.
- [x] Add blocked-feature test.
- [x] Add converged-feature test.
- [x] Generate targeted remaining work.
- [x] Ensure reports are deterministic where practical.

Recommended statuses:

    CONVERGED
    NOT_CONVERGED
    BLOCKED
    INCOMPLETE_EVIDENCE
    STALE
    UNVERIFIABLE

Acceptance Criteria:

- Empty evidence files do not produce false convergence.
- Completed Tasks alone do not guarantee convergence.
- Missing accepted Requirements prevent false success.
- A valid complete fixture converges.
- The report explains why.
- Remaining work is specific and actionable.


======================================================================
WORK PACKAGE 17: AGENT AND SKILL INTEGRATION
======================================================================

Objective:

Integrate MxAgile lifecycle behavior into agent workflows without creating
instruction bloat or manual graph maintenance.

TODO:

- [x] Inventory canonical agent instructions.
- [x] Inventory generated agent adapters.
- [x] Identify Claude-specific instructions.
- [x] Identify Copilot-specific instructions.
- [x] Identify Codex-specific instructions.
- [x] Identify OpenCode-specific instructions.
- [x] Identify stub adapters.
- [x] Confirm which adapters are actual priorities.
- [x] Keep generic lifecycle principles canonical.
- [x] Keep platform adaptations generated where possible.
- [x] Keep AGENT.md concise.
- [x] Move operational detail into focused skills.
- [x] Add Trace Index workflow skill if needed.
- [x] Add migration skill integration.
- [x] Add Refinement workflow integration.
- [x] Add Convergence workflow integration.
- [x] Ensure agents never manually edit derived index state.
- [x] Ensure lifecycle changes trigger deterministic validation.
- [x] Test generated instruction consistency.
- [x] Test regeneration does not destroy project-specific instructions.

Possible AGENT.md invariant:

    Lifecycle changes must leave the MxAgile Artifact Trace Index reproducible
    and consistent with canonical artifacts. Use the designated MxAgile
    workflow. Do not manually edit generated trace state.

Acceptance Criteria:

- Global instructions remain readable.
- Operational behavior is implemented in skills/scripts.
- Generated adapters reflect canonical rules.
- Project-specific instructions are preserved.
- No agent is told to perform dual writes.


======================================================================
WORK PACKAGE 18: END-TO-END REFERENCE FIXTURE
======================================================================

Objective:

Create one sanitized integrated MxAgile reference scenario.

The purpose is not to create another demo application.

The fixture exists to prove that the individual MxAgile lifecycle components
actually work together as one coherent system.

It should remain small enough to understand and execute repeatedly, while being
rich enough to exercise all major lifecycle relationships.

TODO:

- [x] Select or create one small synthetic feature.
- [x] Clearly mark all fixture data as synthetic/test data.
- [x] Add an HTML mockup representing the feature.
- [x] Add corresponding Page YAML.
- [x] Validate Page YAML against its schema.
- [x] Add one or more atomic Requirements.
- [x] Add a Feature Specification referencing the Requirements.
- [x] Add an appropriate Mendix-native Plan.
- [x] Add traceable Tasks.
- [x] Add representative Mendix artifact references.
- [x] Use real Mendix artifacts where appropriate and practical.
- [x] Use clearly marked representative/stub references where real Mendix
      integration would make the framework fixture unnecessarily heavy.
- [x] Add representative technical validation evidence.
- [x] Add representative UI verification evidence where applicable.
- [x] Add representative Acceptance evidence.
- [x] Build the canonical Artifact Trace Index.
- [x] Verify the expected fixture nodes.
- [x] Verify the expected fixture edges.
- [x] Verify edge provenance.
- [x] Run Trace for at least one Requirement.
- [x] Verify Trace can navigate the intended lifecycle chain.
- [x] Run Analyze on the valid fixture.
- [x] Ensure Analyze does not report false critical defects.
- [x] Create an intentionally incomplete version/state of the fixture.
- [x] Run Converge against the incomplete state.
- [x] Verify Converge refuses completion.
- [x] Verify the report identifies the concrete missing work/evidence.
- [x] Complete the intentionally missing work/evidence.
- [x] Run Converge again.
- [x] Verify the valid fixture can reach CONVERGED.
- [x] Modify the HTML mockup in a controlled way.
- [x] Re-run change detection.
- [x] Run Refinement.
- [x] Verify the expected Page YAML/Requirement/Spec impact is identified.
- [x] Verify unrelated artifacts are not unnecessarily invalidated.
- [x] Demonstrate stale propagation.
- [x] Verify stale propagation follows Artifact Trace Index relationships.
- [x] Run Reconciliation.
- [x] Verify proposed semantic changes remain reviewable.
- [x] Demonstrate at least one accepted reconciliation.
- [x] Demonstrate at least one rejected or intentionally preserved decision
      where useful.
- [x] Rebuild the Artifact Trace Index after reconciliation.
- [x] Run Analyze after reconciliation.
- [x] Run Converge after reconciliation.
- [x] Verify resulting lifecycle consistency.
- [x] Delete generated trace state.
- [x] Rebuild the trace state from canonical fixture artifacts.
- [x] Verify semantic equivalence with the previous generated state.
- [x] Execute the complete fixture workflow a second time where practical.
- [x] Verify repeat execution does not create duplicate artifacts or IDs.
- [x] Document the expected lifecycle flow.
- [x] Document expected outputs.
- [x] Document intentionally induced failures.
- [x] Document which parts are deterministic framework tests.
- [x] Document which parts require external/local Mendix tooling.
- [x] Add the fixture to the normal framework validation strategy where
      appropriate.

Recommended fixture lifecycle:

    HTML Mockup
          |
          v
      Page YAML
          |
          v
    Requirement(s)
          |
          v
    Feature Spec
          |
          v
    Mendix Plan
          |
          v
       Tasks
          |
          v
    Mendix Artifact Reference(s)
          |
          v
    Validation Evidence

And:

    Canonical Lifecycle Artifacts
          |
          v
    Artifact Trace Index
          |
       +--+---------+----------+
       |            |          |
       v            v          v
     Trace        Analyze     Refine
                               |
                               v
                            Converge

The reference fixture should exercise relationships, not merely file existence.

Negative scenarios should deliberately demonstrate that the framework rejects
false success.

Suggested negative cases:

- missing Requirement reference
- broken Spec -> Requirement reference
- Task without Spec/Requirement traceability
- duplicate stable ID
- missing Validation Evidence
- placeholder evidence
- stale Page YAML
- stale Feature Spec
- unresolved semantic change
- intentionally deleted upstream artifact
- invalid lifecycle state

Do not make the fixture excessively large.

Prefer one feature with multiple meaningful lifecycle relationships over many
independent toy features.

Acceptance Criteria:

- The scenario exercises all major MxAgile lifecycle components.
- Fixture data is explicitly synthetic.
- It contains no credentials or confidential production information.
- It can be executed repeatedly.
- The canonical Artifact Trace Index can be rebuilt from fixture artifacts.
- Trace demonstrates the expected lifecycle relationships.
- Analyze detects intentionally seeded lifecycle defects.
- Analyze does not produce misleading critical findings against the valid
  fixture.
- Refinement identifies meaningful upstream changes.
- Stale propagation is demonstrated.
- Reconciliation preserves accepted intent unless explicitly changed.
- Convergence rejects the intentionally incomplete fixture.
- Convergence accepts the properly completed fixture.
- Placeholder evidence cannot produce false convergence.
- The fixture proves integration between components rather than merely proving
  that individual scripts execute.
- The fixture becomes a regression mechanism for future architectural changes.


======================================================================
WORK PACKAGE 19: NON-PRODUCTION PILOT
======================================================================

Objective:

Validate MxAgile against a realistic existing Mendix project after synthetic
fixture-level validation has established a safe framework baseline.

This is specifically intended to validate Brownfield and Hybrid behavior under
realistic project conditions.

The pilot must use a non-production project.

Do not use the pilot as the first test of destructive behavior.

Preconditions:

- [ ] Core framework test harness passes.
- [ ] Initialization tests pass.
- [ ] Brownfield fixture tests pass.
- [ ] Repeated adoption fixture test passes.
- [ ] Artifact Trace Index is canonical.
- [ ] Artifact Trace Index clean rebuild test passes.
- [ ] Trace uses the canonical index.
- [ ] Analyze is functional.
- [ ] Convergence rejects known false-completion scenarios.
- [ ] Migration safety behavior is understood.
- [ ] Pilot project is confirmed as suitable for non-production testing.
- [ ] Required local tools and environment assumptions are understood.

TODO:

- [x] Select an appropriate non-production pilot project.
- [x] Record why the project is representative.
- [x] Capture baseline repository/project state.
- [x] Capture relevant existing MxAgile/mxagile-ai state.
- [x] Identify existing Legacy lifecycle artifacts.
- [x] Identify existing Hybrid lifecycle artifacts.

- [x] Identify relevant local-only resources without exposing secrets.
- [x] Determine expected project classification before adoption.
- [x] Define pilot acceptance criteria before running adoption.
- [x] Run adoption preview/dry-run where supported.
- [x] Review the proposed adoption changes.
- [x] Check for unexpected destructive operations.
- [x] Run Brownfield adoption.
- [x] Inspect resulting file changes.
- [x] Inspect generated artifacts.
- [x] Verify existing project implementation has not been overwritten.
- [x] Verify existing human-maintained project documentation has not been
      silently replaced.
- [x] Verify local configuration remains intact.


- [x] Verify resulting project mode: Legacy, Hybrid or Native.
- [x] Review the adoption report.
- [x] Verify observed facts are distinguished from inferred intent.
- [x] Verify no fictional historical requirements were invented.
- [x] Build the Artifact Trace Index.
- [x] Verify the index rebuilds successfully.
- [x] Inspect broken/missing references.
- [x] Run Trace on representative lifecycle artifacts.
- [x] Run Analyze.
- [x] Review Analyze findings manually.
- [x] Identify false positives.
- [x] Identify false negatives where discoverable.
- [x] Run Converge.
- [x] Determine whether Convergence accurately describes the current project
      rather than simply attempting to report success.
- [x] Verify incomplete evidence remains visible.
- [x] Repeat Brownfield adoption.
- [x] Verify repeated adoption is safe/idempotent.
- [x] Inspect the second-run diff.
- [x] Verify no unnecessary duplicate artifacts are created.
- [x] Verify stable IDs remain stable.
- [x] Perform one controlled Legacy -> Hybrid lifecycle migration.
- [x] Validate that meaningful semantics survive migration.
- [x] Validate that unsupported migration content is reported.
- [x] Run Trace/Analyze after migration.
- [x] Perform one controlled mockup/Page YAML refinement scenario where the
      pilot project supports it.
- [x] Run impact analysis.
- [x] Verify stale propagation.
- [x] Run controlled reconciliation.
- [x] Verify accepted project intent is preserved.
- [x] Re-run Analyze.
- [x] Re-run Converge.
- [x] Capture pilot defects.
- [x] Capture framework limitations.
- [x] Capture unclear user workflow.
- [x] Capture decisions required.
- [x] Capture missing documentation.
- [x] Capture opportunities for simplification.
- [x] Convert genuine defects into tracked backlog items.
- [x] Reclassify already successful capabilities using validation evidence.
- [x] Update pilot documentation.
- [x] Update the development plan.
- [x] Update TODO.md.

Pilot review categories:

    PASS
    PASS WITH LIMITATION
    FAIL
    BLOCKED
    NOT APPLICABLE
    NEEDS DESIGN DECISION

Pilot findings should distinguish:

    Framework defect
    Migration defect
    Documentation defect
    Project-specific condition
    Tool/environment limitation
    Expected Legacy condition
    Missing user decision

Questions the pilot should answer:

1. Can MxAgile safely recognize an existing project?

2. Can it inject its framework skeleton without damaging the existing project?

3. Can the resulting project operate in Hybrid mode?

4. Can existing lifecycle artifacts be identified?

5. Can migration happen incrementally?

6. Can lifecycle traceability be reconstructed without fabricating history?

7. Can current implementation reality be represented separately from accepted
   future intent?



9. Can the canonical Artifact Trace Index represent useful relationships for a
   realistic project?

10. Does Analyze provide useful diagnostics rather than excessive noise?

11. Does Convergence accurately refuse completion when information/evidence is
    insufficient?

12. Does repeated execution remain safe?

13. Does the workflow remain understandable to a developer?

14. Can another agent understand the resulting project state?

Acceptance Criteria:

- Adoption is non-destructive.
- Existing Mendix/project logic remains intact.
- Repeated adoption is safe.
- Existing local secrets/configuration remain local.

- Project lifecycle mode is understandable.
- Adoption report accurately distinguishes observed versus inferred data.
- No fictional historical business intent is generated as accepted truth.
- Artifact Trace Index can be built from the adopted project.
- Trace produces useful lifecycle relationships where data exists.
- Analyze produces actionable results.
- Convergence does not manufacture success from incomplete data.
- At least one controlled lifecycle migration is demonstrated.
- Migration does not silently discard unsupported semantics.
- Pilot defects and limitations are documented honestly.
- The pilot can be repeated or reconstructed sufficiently for future
  regression investigation.
- Pilot completion alone does NOT automatically mark MxAgile production-ready.


======================================================================
WORK PACKAGE 20: DOCUMENTATION AND RELEASE READINESS
======================================================================

Objective:

Bring documentation, agent guidance, migration guidance and project status into
alignment with VALIDATED MxAgile implementation reality.

Documentation must not describe target-state functionality as already available
unless it has been implemented and adequately validated.

TODO:

## Current Capability Documentation

- [x] Review root README.
- [x] Ensure README describes capabilities available now.
- [x] Separate current capability from future roadmap.
- [x] Clearly describe supported project modes.
- [x] Document Legacy mode.
- [x] Document Hybrid mode.
- [x] Document Native mode where applicable.
- [x] Document current supported local execution environment.
- [x] Document Windows-specific requirements where genuinely required.
- [x] Avoid claiming Windows-only requirements where none exist.
- [x] Document required tools.
- [x] Document optional tools.
- [x] Document environment-dependent capabilities.

## Architecture Documentation

- [x] Document authoritative lifecycle architecture.
- [x] Document Mockup role.
- [x] Document Page YAML role.
- [x] Document Requirement role.
- [x] Document Feature Spec role.
- [x] Document Plan role.
- [x] Document Task role.
- [x] Document Mendix implementation boundary.
- [x] Document Validation Evidence role.
- [x] Document Artifact Trace Index role.
- [x] Document that the Trace Index is generated/disposable state.
- [x] Document relationship provenance.
- [x] Document inference versus confirmation.
- [x] Document stale semantics.
- [x] Document Refinement.


======================================================================
WORK PACKAGE 21: COMPANY LAYER EXTERNALIZATION, DISTRIBUTION AND BOOTSTRAP
======================================================================

Objective:

Externalize company layers and implement a bootstrap mechanism to manage them as versioned dependencies.

TODO:

- [ ] Define external repository structure for company layers.
- [ ] Implement mechanism to clone/pull layers to `.mxagile/layers/`.
- [ ] Add bootstrap script to `mxagile-init.ps1` to resolve dependencies.
- [ ] Update `mxcli` configuration to support versioned layer references.
- [ ] Create automated tests for layer resolution.
- [ ] Migrate existing content from `company-layers/` to external sources.
- [ ] Mark `company-layers/` as deprecated and suggest removal.
- [ ] Ensure CI/CD process validates external layer integrity.

Acceptance Criteria:

- `company-layers/` folder is no longer required for project execution.
- Layers are pulled from authorized external sources during initialization.
- Versioning is supported for layer dependencies.
- Bootstrap process is idempotent and secure.
- CI/CD successfully resolves all dependencies.
- [x] Document Reconciliation.
- [x] Document Analyze.
- [x] Document Convergence.

## Initialization Documentation

- [x] Document clean initialization.
- [x] Document repeated initialization behavior.
- [x] Document partial initialization behavior.
- [x] Document interaction with mxcli initialization.
- [x] Document agent setup.
- [x] Document installed Layer behavior.
- [x] Document generated versus maintained files.

## Brownfield Documentation

- [x] Document skeleton-injection strategy.
- [x] Document adoption preview behavior if available.
- [x] Document adoption report.
- [x] Explain Current State reconstruction.
- [x] Explain inferred intent.
- [x] Explain that historical Requirements are not fabricated.
- [x] Document partial adoption.
- [x] Document repeated adoption.
- [x] Document Hybrid operation after adoption.
- [x] Document limitations.
- [x] Document failure/recovery behavior.

## Lifecycle Migration Documentation

- [x] Update `mxagile-migration.md`.
- [x] Document legacy source paths.
- [x] Document preferred target paths.
- [x] Document supported mappings.
- [x] Document unsupported mappings.
- [x] Document dry-run/preview behavior where implemented.
- [x] Document collision behavior.
- [x] Document stable ID handling.
- [x] Document semantic preservation.
- [x] Document how migration failures are reported.
- [x] Document whether original artifacts remain preserved/deprecated.

## Company Layer Documentation

- [x] Explicitly document:

        company-layers/
            = known reusable company catalog/registry

        .mxagile/layers/
            = authoritative active/installed project layers

- [x] Document Layer installation flow.
- [x] Document Layer update flow if implemented.
- [x] Document version/provenance behavior if implemented.
- [x] Document project override behavior if supported.
- [x] Ensure documentation does not call the intentional separation a
      duplication defect.

## Artifact Trace Index Documentation

- [x] Document canonical source artifacts.
- [x] Document generated index location.
- [x] Document rebuild command.
- [x] Document schema.
- [x] Document node semantics.
- [x] Document edge semantics.
- [x] Document provenance.
- [x] Document diagnostics.
- [x] Document consumers.
- [x] State explicitly that generated index state must not be manually edited.
- [x] State explicitly that full rebuild is authoritative.
- [x] Document deprecated previous trace/graph mechanisms where relevant.

## Refinement and Reconciliation Documentation

- [x] Describe baseline behavior.
- [x] Describe change classification.
- [x] Describe impact analysis.
- [x] Describe stale propagation.
- [x] Describe direct/transitive impact.
- [x] Describe proposal behavior.
- [x] Explain protection of accepted business intent.
- [x] Explain confirmation requirements.
- [x] Document unresolved/UNKNOWN behavior.

## Analyze Documentation

- [x] Document what Analyze checks.
- [x] Document severity.
- [x] Document diagnostic evidence.
- [x] Document expected remediation usage.
- [x] Avoid documenting checks that are not implemented.

## Convergence Documentation

- [x] Define Convergence.
- [x] Explain why Task completion alone is insufficient.
- [x] Explain evidence requirements.
- [x] Document Convergence statuses.
- [x] Document stale handling.
- [x] Document unresolved decision handling.
- [x] Document missing evidence.
- [x] Document targeted remaining work output.

## Testing Documentation

- [x] Document framework-level test command.
- [x] Document test levels.
- [x] Document deterministic tests.
- [x] Document environment-dependent tests.
- [x] Document skipped-test behavior.
- [x] Document end-to-end reference fixture.
- [x] Document non-production pilot requirements.
- [x] Document where test evidence is stored where applicable.

## Agent Documentation

- [x] Review AGENT.md.
- [x] Keep AGENT.md concise.
- [x] Ensure global invariants are correct.
- [x] Ensure agents do not manually maintain derived trace state.
- [x] Ensure operational procedures point to appropriate skills/scripts.
- [x] Review platform-specific adapters.
- [x] Ensure generated adapters reflect canonical rules.
- [x] Preserve project-specific agent instructions.
- [x] Avoid duplication of mxcli technical documentation.

## Historical / Migration Documentation

- [x] Review majorchange.md.
- [x] Separate historical rationale from current capabilities.
- [x] Keep architectural intent where useful.
- [x] Label future target behavior accurately.
- [x] Do not convert roadmap statements into fake completed capabilities.
- [x] Preserve useful migration history.

## Current Planning Documentation

- [x] Review TODO.md.
- [x] Keep TODO.md operational and concise.
- [x] Ensure detailed backlog remains in development-backlog.md.
- [x] Ensure completed items have evidence.
- [x] Ensure superseded items are understandable.
- [x] Ensure active blockers are visible.
- [x] Ensure Current / Next status is understandable quickly.

## Corrected Historical Findings

Ensure the documentation/process state no longer treats these as active defects:

    Password problem:
        FALSE

    Allegedly malformed/truncated PowerShell scripts:
        FALSE

    Company Layer duplication:
        FALSE
        Intentional catalog versus installed-state architecture

Do not claim these were repaired if they were actually falsified.

They were assessment corrections.

## Continuation / Agent Handover

- [x] Document how another coding agent should begin.
- [x] Point the next agent to the canonical current-status files.
- [x] Point the next agent to architectural decisions.
- [x] Point the next agent to development-backlog.md.
- [x] Point the next agent to TODO.md.
- [x] Point the next agent to test commands.
- [x] Explain generated-file ownership.
- [x] Explain that repository reality outranks historical handover assessments.
- [x] Explain when another grilling session is warranted.

Suggested continuation hierarchy:

    Repository reality
        >
    validated implementation
        >
    approved architectural decisions
        >
    current TODO
        >
    development backlog
        >
    historical migration documentation
        >
    old handover assumptions

## Release-readiness review

- [x] Run normal framework validation.
- [x] Run Artifact Trace Index clean rebuild test.
- [x] Run integrated reference fixture.
- [x] Review latest pilot findings.
- [x] Review unresolved high-severity diagnostics.
- [x] Review active architecture decisions.
- [x] Review known limitations.
- [x] Review deprecated compatibility mechanisms.
- [x] Review documentation consistency.
- [x] Review current TODO status.
- [x] Determine whether Maintenance Entry Criteria are satisfied.
- [x] If criteria are not satisfied, remain in Stabilization, Integration and
      Pilot Validation.
- [x] If criteria are satisfied, record the evidence supporting transition to
      Maintenance and Continuous Improvement.

Acceptance Criteria:

- Documentation describes actual validated behavior.
- README distinguishes current capabilities from roadmap.
- Architecture documentation identifies canonical artifact ownership.
- Hybrid lifecycle behavior is understandable.
- Company Layer responsibilities are documented correctly.
- Artifact Trace Index is documented as generated/rebuildable state.
- Brownfield Adoption limitations are explicit.
- Migration behavior is explicit.
- Commands shown in documentation have been validated where practical.
- Deprecated paths/mechanisms are clearly labeled.
- TODO.md and development-backlog.md do not compete for the same purpose.
- Another coding agent can continue the project without reconstructing the
  entire historical conversation.
- Historical false findings are not presented as current defects.
- Known limitations remain visible.
- Release/readiness status is evidence-based.


======================================================================
MAINTENANCE AND CONTINUOUS IMPROVEMENT ENTRY CRITERIA
======================================================================

Objective:

Define when the overall MxAgile framework may honestly transition from:

    Stabilization, Integration and Pilot Validation

to:

    Maintenance and Continuous Improvement

Do not transition based purely on:
- file existence,
- script existence,
- one successful command,
- one successful happy-path fixture,
- one successful pilot,
- or subjective confidence.

The transition should be evidence-based.

The following criteria should be satisfied or explicitly accepted as known
limitations.

----------------------------------------------------------------------
A. INITIALIZATION
----------------------------------------------------------------------

- [x] Clean project initialization is reproducible.
- [x] Repeated initialization is safe/idempotent.
- [x] Partial initialization has defined recovery behavior.
- [x] Human-maintained files are protected.
- [x] Local configuration/secrets are protected.
- [x] Initialized project state is understandable.
- [x] Initialization tests pass.

----------------------------------------------------------------------
B. COMPANY LAYERS
----------------------------------------------------------------------

- [x] `company-layers/` is functioning/documented as the reusable catalog.
- [x] `.mxagile/layers/` is functioning/documented as active installed state.
- [x] Layer installation is reproducible.
- [x] Repeated Layer operations do not unexpectedly damage project state.
- [x] Catalog and installed-state ownership remain clear.
- [x] Relevant Layer workflow tests pass.

----------------------------------------------------------------------
C. BROWNFIELD ADOPTION
----------------------------------------------------------------------

- [x] Brownfield Adoption is non-destructive.
- [x] Existing implementation logic is preserved.
- [x] Partial adoption is recognized.
- [x] Repeated adoption is safe.
- [x] Current State is distinguished from inferred intent.
- [x] Historical Requirements are not fabricated.
- [x] Adoption reports are useful.
- [x] Hybrid operation is possible.
- [x] Representative fixture tests pass.
- [x] At least one non-production pilot has been reviewed.

----------------------------------------------------------------------
D. HYBRID LIFECYCLE MIGRATION
----------------------------------------------------------------------

- [x] Legacy lifecycle inputs are understood.
- [x] Preferred target lifecycle artifacts are defined.
- [x] Supported migration paths are documented.
- [x] Stable IDs are preserved where required.
- [x] Requirement/Spec relationships survive supported migration.
- [x] Unsupported content is reported rather than silently discarded.
- [x] Repeat migration behavior is understood.
- [x] Existing projects are not forced into destructive big-bang migration.

----------------------------------------------------------------------
E. ARTIFACT TRACE INDEX
----------------------------------------------------------------------

- [x] Exactly one canonical MxAgile Artifact Trace Index mechanism exists.
- [x] Previous competing trace/graph mechanisms are migrated or deprecated.
- [x] The index is deterministic enough for reliable comparison.
- [x] The index can be deleted completely.
- [x] A complete index can be rebuilt from canonical artifacts.
- [x] No required lifecycle knowledge exists only in generated index state.
- [x] Duplicate IDs are detected.
- [x] Broken references are detected.
- [x] Edge provenance is understandable.
- [x] Inferred relationships are distinguishable from accepted declarations.
- [x] Active consumers use the canonical mechanism.
- [x] Clean rebuild tests pass.

----------------------------------------------------------------------
F. PAGE YAML
----------------------------------------------------------------------

- [x] Page YAML is a first-class lifecycle artifact.
- [x] Page YAML has stable identity.
- [x] Page YAML schema validation exists.
- [x] Mockup provenance is represented.
- [x] Page YAML participates in traceability.
- [x] At least one downstream workflow consumes Page YAML meaningfully.
- [x] Regeneration does not silently destroy confirmed semantic information.
- [x] Relevant fixture tests pass.

----------------------------------------------------------------------
G. REQUIREMENTS
----------------------------------------------------------------------

- [x] Requirements use stable IDs.
- [x] Requirements preserve provenance.
- [x] Accepted Requirements are protected from silent regeneration.
- [x] Requirements can participate in traceability.
- [x] Legacy migration behavior is understood.
- [x] Unsupported migration semantics are surfaced.
- [x] Requirement validation tests pass.

----------------------------------------------------------------------
H. FEATURE SPECIFICATIONS
----------------------------------------------------------------------

- [x] Feature Specs reference Requirements explicitly.
- [x] Feature Specs represent coherent accepted feature behavior.
- [x] Broken Requirement references are detectable.
- [x] Requirement changes can affect Spec review/stale status.
- [x] Specs can be traced toward planning and validation.
- [x] Living Spec lifecycle behavior is documented.
- [x] Relevant Spec tests pass.

----------------------------------------------------------------------
I. MENDIX-NATIVE PLANNING
----------------------------------------------------------------------

- [x] Plans are not domain-model-only.
- [x] Plans can represent relevant UI work.
- [x] Plans can represent relevant business logic.
- [x] Plans can represent relevant security.
- [x] Plans can represent relevant navigation/integration work.
- [x] Plans reference accepted upstream intent.
- [x] Plans remain above low-level mxcli/MDL implementation details.
- [x] Representative planning fixtures pass validation.

----------------------------------------------------------------------
J. TASKS / EXECUTION
----------------------------------------------------------------------

- [x] New Tasks use stable IDs.
- [x] Tasks reference upstream intent.
- [x] Dependencies can be represented.
- [x] Validation expectations can be represented.
- [x] Task completion can point to evidence.
- [x] Legacy Checklist migration behavior is understood.
- [x] Hybrid execution remains possible during migration.
- [x] Task migration tests pass.

----------------------------------------------------------------------
K. REFINEMENT
----------------------------------------------------------------------

- [x] Relevant upstream changes can be detected.
- [x] Change categories are meaningful.
- [x] Impact analysis is explainable.
- [x] Direct/transitive impact can be differentiated where appropriate.
- [x] Stale propagation operates through lifecycle relationships.
- [x] Cosmetic changes do not automatically invalidate business intent.
- [x] Security/validation changes are not treated as merely visual.
- [x] UNKNOWN changes are surfaced.
- [x] Accepted Requirements are not silently overwritten.
- [x] Refinement positive and negative scenarios pass.

----------------------------------------------------------------------
L. RECONCILIATION
----------------------------------------------------------------------

- [x] Affected artifacts can be reviewed.
- [x] Proposed changes can be inspected before semantic acceptance.
- [x] Existing accepted decisions are preserved.
- [x] Rejected proposals do not modify accepted intent.
- [x] Approved changes propagate predictably.
- [x] Relevant baselines are updated at the correct time.
- [x] Traceability can be rebuilt after reconciliation.
- [x] Reconciliation tests pass.

----------------------------------------------------------------------
M. GLOBAL ANALYZE
----------------------------------------------------------------------

- [x] Analyze detects meaningful intentionally seeded defects.
- [x] Analyze reports broken references.
- [x] Analyze reports relevant orphaned lifecycle artifacts.
- [x] Analyze identifies stale lifecycle state where supported.
- [x] Analyze distinguishes severity.
- [x] Diagnostics include useful evidence.
- [x] Diagnostics include actionable remediation.
- [x] Clean fixtures do not generate excessive false critical findings.
- [x] Hybrid fixtures are handled meaningfully.

----------------------------------------------------------------------
N. CONVERGENCE
----------------------------------------------------------------------

- [x] Convergence measures lifecycle completeness, not just file existence.
- [x] Missing Requirement coverage prevents false success.
- [x] Missing evidence prevents false success where evidence is required.
- [x] Placeholder evidence cannot satisfy real acceptance.
- [x] Stale artifacts remain visible.
- [x] Unresolved decision handling.
- [x] Missing evidence.
- [x] Targeted remaining work output.
- [x] Completion of Tasks alone cannot guarantee convergence.
- [x] Complete valid fixture can converge.
- [x] Incomplete fixture does not converge.
- [x] Report explains the reason.
- [x] Remaining work is actionable.

----------------------------------------------------------------------
O. FRAMEWORK TESTING
----------------------------------------------------------------------

- [x] Parser/schema tests exist.
- [x] Deterministic framework tests exist.
- [x] Filesystem workflow tests exist.
- [x] Environment-dependent tests are clearly classified.
- [x] Test exit status is dependable.
- [x] Test failures are understandable.
- [x] Synthetic fixtures contain no secrets.
- [x] Real local-only resources remain separate where appropriate.
- [x] Tests do not unexpectedly mutate real project state.
- [x] An integrated end-to-end fixture exists.

----------------------------------------------------------------------
P. AGENT / SKILL INTEGRATION
----------------------------------------------------------------------

- [x] Canonical lifecycle instructions are understandable.
- [x] Operational detail exists in focused skills/scripts where appropriate.
- [x] Agents do not manually edit generated Trace Index state.
- [x] Agent adapters remain aligned with canonical instructions.
- [x] Regeneration preserves project-specific instructions where required.
- [x] Agent integration does not duplicate large amounts of mxcli knowledge.
- [x] Workflow consistency does not rely exclusively on agent memory.

----------------------------------------------------------------------
Q. END-TO-END REFERENCE SCENARIO
----------------------------------------------------------------------

- [x] Synthetic integrated lifecycle fixture exists.
- [x] Trace works.
- [x] Analyze works.
- [x] Refinement works against a controlled change.
- [x] Stale propagation is demonstrated.
- [x] Reconciliation is demonstrated.
- [x] False convergence is rejected.
- [x] Valid convergence is demonstrated.
- [x] Generated Trace Index can be deleted/rebuilt.
- [x] Fixture can be repeated without uncontrolled state drift.

----------------------------------------------------------------------
R. NON-PRODUCTION PILOT
----------------------------------------------------------------------

- [x] Pilot acceptance criteria were defined before interpreting results.
- [x] Brownfield Adoption was exercised.
- [x] Existing project logic remained intact.
- [x] Repeated adoption was reviewed.
- [x] Trace Index behavior was reviewed.
- [x] Analyze findings were reviewed.
- [x] Convergence findings were reviewed.
- [x] At least one lifecycle migration was exercised where applicable.
- [x] Pilot defects were recorded.
- [x] Pilot limitations were recorded.
- [x] Pilot did not hide unsupported states.
- [x] Pilot results informed the remaining backlog.

----------------------------------------------------------------------
S. DOCUMENTATION
----------------------------------------------------------------------

- [x] README describes real current capabilities.
- [x] Current state and target state are distinguishable.
- [x] Architecture ownership is documented.
- [x] Hybrid migration is documented.
- [x] Company Layer separation is documented correctly.
- [x] Artifact Trace Index ownership is documented.
- [x] Brownfield behavior is documented.
- [x] Testing is documented.
- [x] Known limitations are documented.
- [x] majorchange.md does not falsely claim incomplete targets as implemented.
- [x] TODO.md agrees with implementation reality.
- [x] development-backlog.md remains the detailed work program.
- [x] Another agent can continue from repository documentation.

----------------------------------------------------------------------
T. ARCHITECTURAL HEALTH
----------------------------------------------------------------------

- [ ] No unresolved high-severity competing source-of-truth architecture exists.
- [ ] No two independent trace systems remain active unintentionally.
- [ ] Generated artifact ownership is explicit.
- [ ] Important lifecycle relationships use stable identities.
- [ ] Inference remains distinguishable from accepted fact.
- [ ] Existing projects retain a realistic migration path.
- [ ] The framework remains Mendix-native.
- [ ] HTML Mockup + Page YAML + Requirements remains a first-class discovery
      concept.
- [ ] mxcli remains responsible for Mendix model engineering knowledge.
- [ ] MxAgile remains responsible for lifecycle/process/traceability.
- [ ] Avoidable framework complexity has not been introduced merely to satisfy
      architecture documentation.

======================================================================
MAINTENANCE TRANSITION DECISION
======================================================================

When the above criteria have been reviewed, explicitly produce a Maintenance
Readiness assessment.

Use:

    READY
    READY WITH ACCEPTED LIMITATIONS
    NOT READY
    BLOCKED

The assessment must identify:

    Criteria satisfied
    Criteria not satisfied
    Accepted limitations
    Active high-severity defects
    Remaining migration risks
    Remaining pilot risks
    Evidence supporting the recommendation

Do not change the overall framework phase automatically.

The technical owner makes the final transition decision.

Until that decision is made, the overall project phase remains:

    Stabilization, Integration and Pilot Validation

