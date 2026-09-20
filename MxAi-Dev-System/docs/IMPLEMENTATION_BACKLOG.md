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


DECISION D-003: COMPANY LAYER RESPONSIBILITIES

Status:
    APPROVED

Decision:

    company-layers/
        = catalog, registry and collection of known reusable company definitions

    .mxagile/layers/
        = installed and active project layer state

This separation is intentional.

Acceptance Criteria:

- The two concepts are not merged merely because content overlaps.
- Active project behavior is driven by installed project layers.
- Catalog content remains reusable and independent of one project.
- Installation and update behavior preserves this distinction.
- Documentation reflects catalog versus installed state.


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

Objective:

Reconcile this backlog with all work already completed since the previous
handover and avoid overwriting valid ongoing work.

TODO:

- [ ] Capture current Git status without modifying it.
- [ ] Inventory modified tracked files.
- [ ] Inventory untracked files relevant to MxAgile.
- [ ] Identify ignored files relevant to testing and integration.
- [ ] Identify files modified since the last development-plan update.
- [ ] Read the current TODO/development plan.
- [ ] Read current decision records.
- [ ] Inspect all currently active Claude Code TODOs.
- [ ] Identify any work in progress.
- [ ] Identify partially completed edits.
- [ ] Identify generated files that may currently be stale.
- [ ] Identify tests added or changed during the ongoing session.
- [ ] Reconcile existing TODOs with this backlog.
- [ ] Preserve valid completed work.
- [ ] Merge overlapping work packages.
- [ ] Remove or mark obsolete TODOs.
- [ ] Record newly discovered architecture decisions.
- [ ] Do not revert current work merely because it differs from the earlier plan.

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

Objective:

Turn the current optimistic progress list into an evidence-based implementation
and validation plan.

TODO:

- [ ] Rename the active phase to Stabilization, Integration and Pilot Validation.
- [ ] Record the false password finding.
- [ ] Record the false malformed-script finding.
- [ ] Record Company Layer separation as intentional.
- [ ] Replace unsupported broad DONE statuses with evidence-based statuses.
- [ ] Add validation evidence references to completed capabilities.
- [ ] Separate implementation status from validation status.
- [ ] Add missing work packages for Page YAML.
- [ ] Add missing work packages for Feature Specs.
- [ ] Add missing work packages for Mendix-native plans.
- [ ] Add missing work packages for Tasks and Hybrid migration.
- [ ] Add missing work packages for Artifact Trace Index consolidation.
- [ ] Add missing work packages for Analyze.
- [ ] Add missing work packages for Reconciliation.
- [ ] Add missing work packages for Brownfield pilot validation.
- [ ] Add explicit Maintenance entry criteria.

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

Objective:

Create a repeatable framework-level validation foundation before additional
large architectural migrations.

TODO:

- [ ] Verify PowerShell parser checking.
- [ ] Verify Python compilation/import checking.
- [ ] Verify JSON Schema validation.
- [ ] Verify YAML parsing.
- [ ] Add a single documented framework test entry point.
- [ ] Ensure tests return reliable exit codes.
- [ ] Ensure test failures identify the failing capability.
- [ ] Separate fast tests from environment-dependent tests.
- [ ] Add a test-result summary.
- [ ] Add deterministic temporary workspace creation.
- [ ] Ensure temporary test workspaces are cleaned safely.
- [ ] Preserve failed fixtures/output when useful for diagnosis.
- [ ] Ensure tests do not operate destructively on the source repository.
- [ ] Ensure tests do not require production/customer projects.
- [ ] Add synthetic sanitized fixtures.
- [ ] Document which tests require mxcli.
- [ ] Document which tests require Docker.
- [ ] Document which tests require Studio Pro.
- [ ] Document which tests require Playwright.
- [ ] Classify skipped tests clearly.

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

Objective:

Make project initialization reproducible, safe and idempotent.

TODO:

- [ ] Test initialization into an empty fixture.
- [ ] Test repeated initialization.
- [ ] Test initialization into a partially initialized fixture.
- [ ] Test initialization when legacy paths exist.
- [ ] Test initialization when target paths already exist.
- [ ] Test behavior when required tools are unavailable.
- [ ] Test behavior when an installed layer exists.
- [ ] Test behavior when local config exists.
- [ ] Verify generated versus maintained file ownership.
- [ ] Ensure initialization does not overwrite human-maintained content.
- [ ] Ensure initialization reports preserved/skipped/conflicting files.
- [ ] Validate initialized schemas and configuration.
- [ ] Document initialization order relative to mxcli init.
- [ ] Document initialization order relative to agent setup.
- [ ] Add dry-run/preview if justified by actual risk.
- [ ] Verify Windows Local operation.

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
WORK PACKAGE 4: COMPANY LAYER WORKFLOW
======================================================================

Objective:

Preserve and operationalize the approved catalog versus installed-layer model.

TODO:

- [ ] Inventory current company-layers catalog format.
- [ ] Inventory current active layer format.
- [ ] Identify current installation mechanism.
- [ ] Verify selected layer copying/install behavior.
- [ ] Verify installed layer identity.
- [ ] Determine whether installed layer version is recorded.
- [ ] Verify repeated installation behavior.
- [ ] Detect catalog update versus installed state.
- [ ] Preserve project-specific overrides.
- [ ] Avoid modifying catalog content during normal project work.
- [ ] Validate layer schema/manifest.
- [ ] Validate compatibility constraints if present.
- [ ] Document layer provenance.
- [ ] Add layer workflow tests.
- [ ] Avoid creating a second competing layer registry.

Possible solution:

A minimal installed-layer record may contain:

    layer id
    version
    source catalog path
    installed timestamp if useful
    content hash
    project overrides reference

Avoid timestamps in deterministic comparisons unless necessary.

Acceptance Criteria:

- Catalog and installed state remain separate.
- A layer can be installed reproducibly.
- Active project behavior does not read arbitrary catalog content implicitly.
- Layer update state can be explained.
- Reinstallation does not silently remove overrides.
- Tests demonstrate expected behavior.


======================================================================
WORK PACKAGE 5: ARTIFACT TRACE INDEX CONSOLIDATION
======================================================================

Objective:

Consolidate build_trace_index and build_artifact_graph into one canonical,
deterministic Artifact Trace Index.

TODO:

- [ ] Inventory existing trace builder.
- [ ] Inventory existing artifact graph builder.
- [ ] Inventory both schemas.
- [ ] Inventory both generated outputs.
- [ ] Inventory all producers.
- [ ] Inventory all consumers.
- [ ] Inventory tests.
- [ ] Inventory documentation references.
- [ ] Compare node types.
- [ ] Compare edge types.
- [ ] Compare hashes.
- [ ] Compare stale-state handling.
- [ ] Compare provenance.
- [ ] Identify unique information in each mechanism.
- [ ] Identify graph-only information.
- [ ] Move graph-only canonical information into source artifacts where needed.
- [ ] Decide canonical script/module names.
- [ ] Decide canonical output file.
- [ ] Define canonical schema.
- [ ] Define deterministic ordering.
- [ ] Define generated metadata policy.
- [ ] Implement or adapt the canonical full builder.
- [ ] Add compatibility adapter for old consumers if needed.
- [ ] Migrate trace consumer.
- [ ] Migrate refine consumer.
- [ ] Migrate analyze consumer.
- [ ] Migrate converge consumer.
- [ ] Deprecate redundant builder.
- [ ] Remove redundant implementation only when consumers are migrated.
- [ ] Update generated-file ownership documentation.
- [ ] Update migration documentation.

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

- [ ] Define minimum required node types.
- [ ] Define minimum required edge types.
- [ ] Define stable ID rules.
- [ ] Define duplicate ID behavior.
- [ ] Define missing reference behavior.
- [ ] Define edge source/provenance.
- [ ] Define declared relationship behavior.
- [ ] Define derived relationship behavior.
- [ ] Define inferred relationship behavior if needed.
- [ ] Define stale state representation.
- [ ] Define diagnostic severity.
- [ ] Define legacy artifact representation.
- [ ] Define migrated artifact representation.
- [ ] Define Mendix reference format.
- [ ] Avoid copying full mxcli reference graphs.
- [ ] Add schema tests.
- [ ] Add extraction tests.
- [ ] Add negative tests.

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

Objective:

Make Page YAML a meaningful first-class artifact.

TODO:

- [ ] Inventory existing Page YAML schema.
- [ ] Inventory existing generated Page YAML examples.
- [ ] Identify the current generator.
- [ ] Identify the current validator.
- [ ] Identify all current consumers.
- [ ] Define stable Page ID.
- [ ] Define mockup source reference.
- [ ] Define Page YAML ownership.
- [ ] Define generated versus manually enriched fields.
- [ ] Define regeneration behavior.
- [ ] Protect human-maintained semantic content.
- [ ] Represent sections/components/fields/actions/states as needed.
- [ ] Represent navigation references.
- [ ] Represent role/security hints where appropriate.
- [ ] Represent relevant requirement references.
- [ ] Represent relevant Mendix mapping hints without overcommitting.
- [ ] Add trace-index extraction.
- [ ] Add schema validation.
- [ ] Add mockup change tests.
- [ ] Add UI verification linkage.
- [ ] Add at least one complete fixture.

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

Objective:

Detect upstream changes, classify their significance and identify affected
lifecycle artifacts without silently rewriting accepted intent.

TODO:

- [ ] Verify baseline creation.
- [ ] Verify baseline update policy.
- [ ] Verify hierarchical hashing.
- [ ] Verify meaningful normalization.
- [ ] Avoid treating irrelevant formatting as semantic change where possible.
- [ ] Detect added artifacts.
- [ ] Detect modified artifacts.
- [ ] Detect deleted artifacts.
- [ ] Classify visual changes.
- [ ] Classify content changes.
- [ ] Classify interaction changes.
- [ ] Classify navigation changes.
- [ ] Classify data changes.
- [ ] Classify business behavior changes.
- [ ] Classify validation changes.
- [ ] Classify security changes.
- [ ] Classify integration changes.
- [ ] Support UNKNOWN classification.
- [ ] Determine directly affected artifacts.
- [ ] Determine transitively affected artifacts.
- [ ] Use Artifact Trace Index.
- [ ] Create explainable impact report.
- [ ] Mark review state without auto-rewriting accepted semantics.
- [ ] Add positive test cases.
- [ ] Add ambiguous test cases.
- [ ] Add deletion test cases.
- [ ] Add tests protecting accepted requirements.

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

- [ ] Inspect current reconcile implementation.
- [ ] Identify whether it only generates a report.
- [ ] Define proposal format.
- [ ] Show old and new evidence.
- [ ] Show affected artifact chain.
- [ ] Show accepted decisions.
- [ ] Generate candidate changes without silently applying semantic changes.
- [ ] Preserve manual sections.
- [ ] Require approval for requirement/spec meaning changes.
- [ ] Apply approved changes.
- [ ] Update baselines only after appropriate confirmation.
- [ ] Rebuild Trace Index.
- [ ] Re-run Analyze.
- [ ] Re-run Converge where appropriate.
- [ ] Record remaining unresolved items.
- [ ] Add rejection scenario.
- [ ] Add partial-approval scenario.
- [ ] Add rerun/idempotency scenario.

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

- [ ] Define/verify Spec schema.
- [ ] Verify stable Spec ID.
- [ ] Reference included Requirements explicitly.
- [ ] Represent coherent feature behavior.
- [ ] Represent roles where appropriate.
- [ ] Represent flows/scenarios where appropriate.
- [ ] Represent constraints.
- [ ] Represent assumptions.
- [ ] Represent decisions.
- [ ] Represent acceptance behavior.
- [ ] Represent known deviations.
- [ ] Represent stale/review state.
- [ ] Link to Page YAML where relevant.
- [ ] Link to plan.
- [ ] Link to validation expectations.
- [ ] Add broken requirement reference tests.
- [ ] Add stale propagation tests.
- [ ] Avoid copying every Requirement field without purpose.

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

- [ ] Inspect current plan generator.
- [ ] Inspect current wave plan generator.
- [ ] Identify domain-model-only assumptions.
- [ ] Define minimum plan schema/structure.
- [ ] Reference source Spec.
- [ ] Reference Requirements.
- [ ] Reference Pages.
- [ ] Identify affected modules.
- [ ] Identify domain model work.
- [ ] Identify page/UI work.
- [ ] Identify microflow/nanoflow work.
- [ ] Identify security work.
- [ ] Identify navigation work.
- [ ] Identify integration work.
- [ ] Identify platform/module reuse.
- [ ] Identify migration impact.
- [ ] Identify test/verification strategy.
- [ ] Avoid low-level MDL duplication.
- [ ] Add representative planning fixtures.
- [ ] Add validation tests.
- [ ] Add unsupported/ambiguous planning scenario.

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

- [ ] Inventory current checklist format.
- [ ] Inventory current task format.
- [ ] Inventory wave format.
- [ ] Identify orchestrator consumers.
- [ ] Define canonical format for new projects.
- [ ] Define legacy-read behavior.
- [ ] Define migration behavior.
- [ ] Preserve stable IDs.
- [ ] Preserve requirement references.
- [ ] Preserve spec references.
- [ ] Preserve validation intent.
- [ ] Preserve dependencies.
- [ ] Detect unmappable fields.
- [ ] Add migration dry run.
- [ ] Add collision detection.
- [ ] Add repeat migration test.
- [ ] Add partial migration test.
- [ ] Add unsupported legacy content test.
- [ ] Define Task completion evidence.
- [ ] Define Task verification fields.
- [ ] Keep Tasks reasonably sized.
- [ ] Avoid embedding giant agent prompts.

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

- [ ] Test clean legacy fixture.
- [ ] Test fixture with existing docs.
- [ ] Test fixture with legacy planning artifacts.
- [ ] Test fixture with partial MxAgile structure.
- [ ] Test repeated adoption.
- [ ] Test active Company Layer state.
- [ ] Test local environment preservation.
- [ ] Test collision behavior.
- [ ] Test unsupported state.
- [ ] Add dry-run/preview if appropriate.
- [ ] Classify project as Legacy/Hybrid/Native where possible.
- [ ] Generate adoption report.
- [ ] Record observed current state.
- [ ] Label inferred intent.
- [ ] Avoid invented historical requirements.
- [ ] Recommend next migration actions.
- [ ] Rebuild Artifact Trace Index after adoption.
- [ ] Run Analyze after adoption.
- [ ] Keep original project logic unchanged.
- [ ] Document rollback/manual recovery.

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

- [ ] Detect duplicate stable IDs.
- [ ] Detect broken references.
- [ ] Detect orphan Requirements.
- [ ] Detect Requirements absent from Specs.
- [ ] Detect Specs with missing Requirements.
- [ ] Detect Plans without accepted Specs.
- [ ] Detect Tasks without traceability.
- [ ] Detect stale Page YAML.
- [ ] Detect stale Specs.
- [ ] Detect incomplete migration.
- [ ] Detect legacy artifact still consumed unexpectedly.
- [ ] Detect invalid active Layer state.
- [ ] Detect missing validation evidence.
- [ ] Detect unresolved decisions.
- [ ] Detect conflicting lifecycle states.
- [ ] Add severity.
- [ ] Add evidence/source location.
- [ ] Add remediation guidance.
- [ ] Suppress low-value noise.
- [ ] Add positive fixture.
- [ ] Add negative fixture.
- [ ] Add mixed Hybrid fixture.

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

- [ ] Define convergence scope.
- [ ] Define feature identity.
- [ ] Verify Requirement coverage.
- [ ] Verify Spec coverage.
- [ ] Verify Page relevance where applicable.
- [ ] Verify Plan existence/coverage.
- [ ] Verify Task completion.
- [ ] Verify Task evidence.
- [ ] Verify implementation references.
- [ ] Verify technical validation evidence.
- [ ] Verify UI verification evidence when required.
- [ ] Verify acceptance evidence.
- [ ] Reject stale artifacts.
- [ ] Surface unresolved decisions.
- [ ] Surface known deviations.
- [ ] Surface broken references.
- [ ] Distinguish missing evidence from failed validation.
- [ ] Add false-completion test.
- [ ] Add placeholder-evidence test.
- [ ] Add stale-feature test.
- [ ] Add blocked-feature test.
- [ ] Add converged-feature test.
- [ ] Generate targeted remaining work.
- [ ] Ensure reports are deterministic where practical.

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

- [ ] Inventory canonical agent instructions.
- [ ] Inventory generated agent adapters.
- [ ] Identify Claude-specific instructions.
- [ ] Identify Copilot-specific instructions.
- [ ] Identify Codex-specific instructions.
- [ ] Identify OpenCode-specific instructions.
- [ ] Identify stub adapters.
- [ ] Confirm which adapters are actual priorities.
- [ ] Keep generic lifecycle principles canonical.
- [ ] Keep platform adaptations generated where possible.
- [ ] Keep AGENT.md concise.
- [ ] Move operational detail into focused skills.
- [ ] Add Trace Index workflow skill if needed.
- [ ] Add migration skill integration.
- [ ] Add Refinement workflow integration.
- [ ] Add Convergence workflow integration.
- [ ] Ensure agents never manually edit derived index state.
- [ ] Ensure lifecycle changes trigger deterministic validation.
- [ ] Test generated instruction consistency.
- [ ] Test regeneration does not destroy project-specific instructions.

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

- [ ] Select or create one small synthetic feature.
- [ ] Clearly mark all fixture data as synthetic/test data.
- [ ] Add an HTML mockup representing the feature.
- [ ] Add corresponding Page YAML.
- [ ] Validate Page YAML against its schema.
- [ ] Add one or more atomic Requirements.
- [ ] Add a Feature Specification referencing the Requirements.
- [ ] Add an appropriate Mendix-native Plan.
- [ ] Add traceable Tasks.
- [ ] Add representative Mendix artifact references.
- [ ] Use real Mendix artifacts where appropriate and practical.
- [ ] Use clearly marked representative/stub references where real Mendix
      integration would make the framework fixture unnecessarily heavy.
- [ ] Add representative technical validation evidence.
- [ ] Add representative UI verification evidence where applicable.
- [ ] Add representative Acceptance evidence.
- [ ] Build the canonical Artifact Trace Index.
- [ ] Verify the expected fixture nodes.
- [ ] Verify the expected fixture edges.
- [ ] Verify edge provenance.
- [ ] Run Trace for at least one Requirement.
- [ ] Verify Trace can navigate the intended lifecycle chain.
- [ ] Run Analyze on the valid fixture.
- [ ] Ensure Analyze does not report false critical defects.
- [ ] Create an intentionally incomplete version/state of the fixture.
- [ ] Run Converge against the incomplete state.
- [ ] Verify Converge refuses completion.
- [ ] Verify the report identifies the concrete missing work/evidence.
- [ ] Complete the intentionally missing work/evidence.
- [ ] Run Converge again.
- [ ] Verify the valid fixture can reach CONVERGED.
- [ ] Modify the HTML mockup in a controlled way.
- [ ] Re-run change detection.
- [ ] Run Refinement.
- [ ] Verify the expected Page YAML/Requirement/Spec impact is identified.
- [ ] Verify unrelated artifacts are not unnecessarily invalidated.
- [ ] Demonstrate stale propagation.
- [ ] Verify stale propagation follows Artifact Trace Index relationships.
- [ ] Run Reconciliation.
- [ ] Verify proposed semantic changes remain reviewable.
- [ ] Demonstrate at least one accepted reconciliation.
- [ ] Demonstrate at least one rejected or intentionally preserved decision
      where useful.
- [ ] Rebuild the Artifact Trace Index after reconciliation.
- [ ] Run Analyze after reconciliation.
- [ ] Run Converge after reconciliation.
- [ ] Verify resulting lifecycle consistency.
- [ ] Delete generated trace state.
- [ ] Rebuild the trace state from canonical fixture artifacts.
- [ ] Verify semantic equivalence with the previous generated state.
- [ ] Execute the complete fixture workflow a second time where practical.
- [ ] Verify repeat execution does not create duplicate artifacts or IDs.
- [ ] Document the expected lifecycle flow.
- [ ] Document expected outputs.
- [ ] Document intentionally induced failures.
- [ ] Document which parts are deterministic framework tests.
- [ ] Document which parts require external/local Mendix tooling.
- [ ] Add the fixture to the normal framework validation strategy where
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

- [ ] Select an appropriate non-production pilot project.
- [ ] Record why the project is representative.
- [ ] Capture baseline repository/project state.
- [ ] Capture relevant existing MxAgile/dfc-ai state.
- [ ] Identify existing Legacy lifecycle artifacts.
- [ ] Identify existing Hybrid lifecycle artifacts.
- [ ] Identify existing Company Layer installation state.
- [ ] Identify relevant local-only resources without exposing secrets.
- [ ] Determine expected project classification before adoption.
- [ ] Define pilot acceptance criteria before running adoption.
- [ ] Run adoption preview/dry-run where supported.
- [ ] Review the proposed adoption changes.
- [ ] Check for unexpected destructive operations.
- [ ] Run Brownfield adoption.
- [ ] Inspect resulting file changes.
- [ ] Inspect generated artifacts.
- [ ] Verify existing project implementation has not been overwritten.
- [ ] Verify existing human-maintained project documentation has not been
      silently replaced.
- [ ] Verify local configuration remains intact.
- [ ] Verify active Company Layer state.
- [ ] Verify company catalog content remains separate from active layers.
- [ ] Verify resulting project mode: Legacy, Hybrid or Native.
- [ ] Review the adoption report.
- [ ] Verify observed facts are distinguished from inferred intent.
- [ ] Verify no fictional historical requirements were invented.
- [ ] Build the Artifact Trace Index.
- [ ] Verify the index rebuilds successfully.
- [ ] Inspect broken/missing references.
- [ ] Run Trace on representative lifecycle artifacts.
- [ ] Run Analyze.
- [ ] Review Analyze findings manually.
- [ ] Identify false positives.
- [ ] Identify false negatives where discoverable.
- [ ] Run Converge.
- [ ] Determine whether Convergence accurately describes the current project
      rather than simply attempting to report success.
- [ ] Verify incomplete evidence remains visible.
- [ ] Repeat Brownfield adoption.
- [ ] Verify repeated adoption is safe/idempotent.
- [ ] Inspect the second-run diff.
- [ ] Verify no unnecessary duplicate artifacts are created.
- [ ] Verify stable IDs remain stable.
- [ ] Perform one controlled Legacy -> Hybrid lifecycle migration.
- [ ] Validate that meaningful semantics survive migration.
- [ ] Validate that unsupported migration content is reported.
- [ ] Run Trace/Analyze after migration.
- [ ] Perform one controlled mockup/Page YAML refinement scenario where the
      pilot project supports it.
- [ ] Run impact analysis.
- [ ] Verify stale propagation.
- [ ] Run controlled reconciliation.
- [ ] Verify accepted project intent is preserved.
- [ ] Re-run Analyze.
- [ ] Re-run Converge.
- [ ] Capture pilot defects.
- [ ] Capture framework limitations.
- [ ] Capture unclear user workflow.
- [ ] Capture decisions required.
- [ ] Capture missing documentation.
- [ ] Capture opportunities for simplification.
- [ ] Convert genuine defects into tracked backlog items.
- [ ] Reclassify already successful capabilities using validation evidence.
- [ ] Update pilot documentation.
- [ ] Update the development plan.
- [ ] Update TODO.md.

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

8. Can Layer state be understood correctly?

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
- Installed Company Layers remain distinguishable from catalog content.
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

- [ ] Review root README.
- [ ] Ensure README describes capabilities available now.
- [ ] Separate current capability from future roadmap.
- [ ] Clearly describe supported project modes.
- [ ] Document Legacy mode.
- [ ] Document Hybrid mode.
- [ ] Document Native mode where applicable.
- [ ] Document current supported local execution environment.
- [ ] Document Windows-specific requirements where genuinely required.
- [ ] Avoid claiming Windows-only requirements where none exist.
- [ ] Document required tools.
- [ ] Document optional tools.
- [ ] Document environment-dependent capabilities.

## Architecture Documentation

- [ ] Document authoritative lifecycle architecture.
- [ ] Document Mockup role.
- [ ] Document Page YAML role.
- [ ] Document Requirement role.
- [ ] Document Feature Spec role.
- [ ] Document Plan role.
- [ ] Document Task role.
- [ ] Document Mendix implementation boundary.
- [ ] Document Validation Evidence role.
- [ ] Document Artifact Trace Index role.
- [ ] Document that the Trace Index is generated/disposable state.
- [ ] Document relationship provenance.
- [ ] Document inference versus confirmation.
- [ ] Document stale semantics.
- [ ] Document Refinement.
- [ ] Document Reconciliation.
- [ ] Document Analyze.
- [ ] Document Convergence.

## Initialization Documentation

- [ ] Document clean initialization.
- [ ] Document repeated initialization behavior.
- [ ] Document partial initialization behavior.
- [ ] Document interaction with mxcli initialization.
- [ ] Document agent setup.
- [ ] Document installed Layer behavior.
- [ ] Document generated versus maintained files.

## Brownfield Documentation

- [ ] Document skeleton-injection strategy.
- [ ] Document adoption preview behavior if available.
- [ ] Document adoption report.
- [ ] Explain Current State reconstruction.
- [ ] Explain inferred intent.
- [ ] Explain that historical Requirements are not fabricated.
- [ ] Document partial adoption.
- [ ] Document repeated adoption.
- [ ] Document Hybrid operation after adoption.
- [ ] Document limitations.
- [ ] Document failure/recovery behavior.

## Lifecycle Migration Documentation

- [ ] Update `mxagile-migration.md`.
- [ ] Document legacy source paths.
- [ ] Document preferred target paths.
- [ ] Document supported mappings.
- [ ] Document unsupported mappings.
- [ ] Document dry-run/preview behavior where implemented.
- [ ] Document collision behavior.
- [ ] Document stable ID handling.
- [ ] Document semantic preservation.
- [ ] Document how migration failures are reported.
- [ ] Document whether original artifacts remain preserved/deprecated.

## Company Layer Documentation

- [ ] Explicitly document:

        company-layers/
            = known reusable company catalog/registry

        .mxagile/layers/
            = authoritative active/installed project layers

- [ ] Document Layer installation flow.
- [ ] Document Layer update flow if implemented.
- [ ] Document version/provenance behavior if implemented.
- [ ] Document project override behavior if supported.
- [ ] Ensure documentation does not call the intentional separation a
      duplication defect.

## Artifact Trace Index Documentation

- [ ] Document canonical source artifacts.
- [ ] Document generated index location.
- [ ] Document rebuild command.
- [ ] Document schema.
- [ ] Document node semantics.
- [ ] Document edge semantics.
- [ ] Document provenance.
- [ ] Document diagnostics.
- [ ] Document consumers.
- [ ] State explicitly that generated index state must not be manually edited.
- [ ] State explicitly that full rebuild is authoritative.
- [ ] Document deprecated previous trace/graph mechanisms where relevant.

## Refinement and Reconciliation Documentation

- [ ] Describe baseline behavior.
- [ ] Describe change classification.
- [ ] Describe impact analysis.
- [ ] Describe stale propagation.
- [ ] Describe direct/transitive impact.
- [ ] Describe proposal behavior.
- [ ] Explain protection of accepted business intent.
- [ ] Explain confirmation requirements.
- [ ] Document unresolved/UNKNOWN behavior.

## Analyze Documentation

- [ ] Document what Analyze checks.
- [ ] Document severity.
- [ ] Document diagnostic evidence.
- [ ] Document expected remediation usage.
- [ ] Avoid documenting checks that are not implemented.

## Convergence Documentation

- [ ] Define Convergence.
- [ ] Explain why Task completion alone is insufficient.
- [ ] Explain evidence requirements.
- [ ] Document Convergence statuses.
- [ ] Document stale handling.
- [ ] Document unresolved decision handling.
- [ ] Document missing evidence.
- [ ] Document targeted remaining work output.

## Testing Documentation

- [ ] Document framework-level test command.
- [ ] Document test levels.
- [ ] Document deterministic tests.
- [ ] Document environment-dependent tests.
- [ ] Document skipped-test behavior.
- [ ] Document end-to-end reference fixture.
- [ ] Document non-production pilot requirements.
- [ ] Document where test evidence is stored where applicable.

## Agent Documentation

- [ ] Review AGENT.md.
- [ ] Keep AGENT.md concise.
- [ ] Ensure global invariants are correct.
- [ ] Ensure agents do not manually maintain derived trace state.
- [ ] Ensure operational procedures point to appropriate skills/scripts.
- [ ] Review platform-specific adapters.
- [ ] Ensure generated adapters reflect canonical rules.
- [ ] Preserve project-specific agent instructions.
- [ ] Avoid duplication of mxcli technical documentation.

## Historical / Migration Documentation

- [ ] Review majorchange.md.
- [ ] Separate historical rationale from current capabilities.
- [ ] Keep architectural intent where useful.
- [ ] Label future target behavior accurately.
- [ ] Do not convert roadmap statements into fake completed capabilities.
- [ ] Preserve useful migration history.

## Current Planning Documentation

- [ ] Review TODO.md.
- [ ] Keep TODO.md operational and concise.
- [ ] Ensure detailed backlog remains in development-backlog.md.
- [ ] Ensure completed items have evidence.
- [ ] Ensure superseded items are understandable.
- [ ] Ensure active blockers are visible.
- [ ] Ensure Current / Next status is understandable quickly.

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

- [ ] Document how another coding agent should begin.
- [ ] Point the next agent to the canonical current-status files.
- [ ] Point the next agent to architectural decisions.
- [ ] Point the next agent to development-backlog.md.
- [ ] Point the next agent to TODO.md.
- [ ] Point the next agent to test commands.
- [ ] Explain generated-file ownership.
- [ ] Explain that repository reality outranks historical handover assessments.
- [ ] Explain when another grilling session is warranted.

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

- [ ] Run normal framework validation.
- [ ] Run Artifact Trace Index clean rebuild test.
- [ ] Run integrated reference fixture.
- [ ] Review latest pilot findings.
- [ ] Review unresolved high-severity diagnostics.
- [ ] Review active architecture decisions.
- [ ] Review known limitations.
- [ ] Review deprecated compatibility mechanisms.
- [ ] Review documentation consistency.
- [ ] Review current TODO status.
- [ ] Determine whether Maintenance Entry Criteria are satisfied.
- [ ] If criteria are not satisfied, remain in Stabilization, Integration and
      Pilot Validation.
- [ ] If criteria are satisfied, record the evidence supporting transition to
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

- [ ] Clean project initialization is reproducible.
- [ ] Repeated initialization is safe/idempotent.
- [ ] Partial initialization has defined recovery behavior.
- [ ] Human-maintained files are protected.
- [ ] Local configuration/secrets are protected.
- [ ] Initialized project state is understandable.
- [ ] Initialization tests pass.

----------------------------------------------------------------------
B. COMPANY LAYERS
----------------------------------------------------------------------

- [ ] `company-layers/` is functioning/documented as the reusable catalog.
- [ ] `.mxagile/layers/` is functioning/documented as active installed state.
- [ ] Layer installation is reproducible.
- [ ] Repeated Layer operations do not unexpectedly damage project state.
- [ ] Catalog and installed-state ownership remain clear.
- [ ] Relevant Layer workflow tests pass.

----------------------------------------------------------------------
C. BROWNFIELD ADOPTION
----------------------------------------------------------------------

- [ ] Brownfield Adoption is non-destructive.
- [ ] Existing implementation logic is preserved.
- [ ] Partial adoption is recognized.
- [ ] Repeated adoption is safe.
- [ ] Current State is distinguished from inferred intent.
- [ ] Historical Requirements are not fabricated.
- [ ] Adoption reports are useful.
- [ ] Hybrid operation is possible.
- [ ] Representative fixture tests pass.
- [ ] At least one non-production pilot has been reviewed.

----------------------------------------------------------------------
D. HYBRID LIFECYCLE MIGRATION
----------------------------------------------------------------------

- [ ] Legacy lifecycle inputs are understood.
- [ ] Preferred target lifecycle artifacts are defined.
- [ ] Supported migration paths are documented.
- [ ] Stable IDs are preserved where required.
- [ ] Requirement/Spec relationships survive supported migration.
- [ ] Unsupported content is reported rather than silently discarded.
- [ ] Repeat migration behavior is understood.
- [ ] Existing projects are not forced into destructive big-bang migration.

----------------------------------------------------------------------
E. ARTIFACT TRACE INDEX
----------------------------------------------------------------------

- [ ] Exactly one canonical MxAgile Artifact Trace Index mechanism exists.
- [ ] Previous competing trace/graph mechanisms are migrated or deprecated.
- [ ] The index is deterministic enough for reliable comparison.
- [ ] The index can be deleted completely.
- [ ] A complete index can be rebuilt from canonical artifacts.
- [ ] No required lifecycle knowledge exists only in generated index state.
- [ ] Duplicate IDs are detected.
- [ ] Broken references are detected.
- [ ] Edge provenance is understandable.
- [ ] Inferred relationships are distinguishable from accepted declarations.
- [ ] Active consumers use the canonical mechanism.
- [ ] Clean rebuild tests pass.

----------------------------------------------------------------------
F. PAGE YAML
----------------------------------------------------------------------

- [ ] Page YAML is a first-class lifecycle artifact.
- [ ] Page YAML has stable identity.
- [ ] Page YAML schema validation exists.
- [ ] Mockup provenance is represented.
- [ ] Page YAML participates in traceability.
- [ ] At least one downstream workflow consumes Page YAML meaningfully.
- [ ] Regeneration does not silently destroy confirmed semantic information.
- [ ] Relevant fixture tests pass.

----------------------------------------------------------------------
G. REQUIREMENTS
----------------------------------------------------------------------

- [ ] Requirements use stable IDs.
- [ ] Requirements preserve provenance.
- [ ] Accepted Requirements are protected from silent regeneration.
- [ ] Requirements can participate in traceability.
- [ ] Legacy migration behavior is understood.
- [ ] Unsupported migration semantics are surfaced.
- [ ] Requirement validation tests pass.

----------------------------------------------------------------------
H. FEATURE SPECIFICATIONS
----------------------------------------------------------------------

- [ ] Feature Specs reference Requirements explicitly.
- [ ] Feature Specs represent coherent accepted feature behavior.
- [ ] Broken Requirement references are detectable.
- [ ] Requirement changes can affect Spec review/stale status.
- [ ] Specs can be traced toward planning and validation.
- [ ] Living Spec lifecycle behavior is documented.
- [ ] Relevant Spec tests pass.

----------------------------------------------------------------------
I. MENDIX-NATIVE PLANNING
----------------------------------------------------------------------

- [ ] Plans are not domain-model-only.
- [ ] Plans can represent relevant UI work.
- [ ] Plans can represent relevant business logic.
- [ ] Plans can represent relevant security.
- [ ] Plans can represent relevant navigation/integration work.
- [ ] Plans reference accepted upstream intent.
- [ ] Plans remain above low-level mxcli/MDL implementation details.
- [ ] Representative planning fixtures pass validation.

----------------------------------------------------------------------
J. TASKS / EXECUTION
----------------------------------------------------------------------

- [ ] New Tasks use stable IDs.
- [ ] Tasks reference upstream intent.
- [ ] Dependencies can be represented.
- [ ] Validation expectations can be represented.
- [ ] Task completion can point to evidence.
- [ ] Legacy Checklist migration behavior is understood.
- [ ] Hybrid execution remains possible during migration.
- [ ] Task migration tests pass.

----------------------------------------------------------------------
K. REFINEMENT
----------------------------------------------------------------------

- [ ] Relevant upstream changes can be detected.
- [ ] Change categories are meaningful.
- [ ] Impact analysis is explainable.
- [ ] Direct/transitive impact can be differentiated where appropriate.
- [ ] Stale propagation operates through lifecycle relationships.
- [ ] Cosmetic changes do not automatically invalidate business intent.
- [ ] Security/validation changes are not treated as merely visual.
- [ ] UNKNOWN changes are surfaced.
- [ ] Accepted Requirements are not silently overwritten.
- [ ] Refinement positive and negative scenarios pass.

----------------------------------------------------------------------
L. RECONCILIATION
----------------------------------------------------------------------

- [ ] Affected artifacts can be reviewed.
- [ ] Proposed changes can be inspected before semantic acceptance.
- [ ] Existing accepted decisions are preserved.
- [ ] Rejected proposals do not modify accepted intent.
- [ ] Approved changes propagate predictably.
- [ ] Relevant baselines are updated at the correct time.
- [ ] Traceability can be rebuilt after reconciliation.
- [ ] Reconciliation tests pass.

----------------------------------------------------------------------
M. GLOBAL ANALYZE
----------------------------------------------------------------------

- [ ] Analyze detects meaningful intentionally seeded defects.
- [ ] Analyze reports broken references.
- [ ] Analyze reports relevant orphaned lifecycle artifacts.
- [ ] Analyze identifies stale lifecycle state where supported.
- [ ] Analyze distinguishes severity.
- [ ] Diagnostics include useful evidence.
- [ ] Diagnostics include actionable remediation.
- [ ] Clean fixtures do not generate excessive false critical findings.
- [ ] Hybrid fixtures are handled meaningfully.

----------------------------------------------------------------------
N. CONVERGENCE
----------------------------------------------------------------------

- [ ] Convergence measures lifecycle completeness, not just file existence.
- [ ] Missing Requirement coverage prevents false success.
- [ ] Missing evidence prevents false success where evidence is required.
- [ ] Placeholder evidence cannot satisfy real acceptance.
- [ ] Stale artifacts remain visible.
- [ ] Unresolved decisions remain visible.
- [ ] Completion of Tasks alone cannot guarantee convergence.
- [ ] Complete valid fixture can converge.
- [ ] Incomplete fixture does not converge.
- [ ] Report explains the reason.
- [ ] Remaining work is actionable.

----------------------------------------------------------------------
O. FRAMEWORK TESTING
----------------------------------------------------------------------

- [ ] Parser/schema tests exist.
- [ ] Deterministic framework tests exist.
- [ ] Filesystem workflow tests exist.
- [ ] Environment-dependent tests are clearly classified.
- [ ] Test exit status is dependable.
- [ ] Test failures are understandable.
- [ ] Synthetic fixtures contain no secrets.
- [ ] Real local-only resources remain separate where appropriate.
- [ ] Tests do not unexpectedly mutate real project state.
- [ ] An integrated end-to-end fixture exists.

----------------------------------------------------------------------
P. AGENT / SKILL INTEGRATION
----------------------------------------------------------------------

- [ ] Canonical lifecycle instructions are understandable.
- [ ] Operational detail exists in focused skills/scripts where appropriate.
- [ ] Agents do not manually edit generated Trace Index state.
- [ ] Agent adapters remain aligned with canonical instructions.
- [ ] Regeneration preserves project-specific instructions where required.
- [ ] Agent integration does not duplicate large amounts of mxcli knowledge.
- [ ] Workflow consistency does not rely exclusively on agent memory.

----------------------------------------------------------------------
Q. END-TO-END REFERENCE SCENARIO
----------------------------------------------------------------------

- [ ] Synthetic integrated lifecycle fixture exists.
- [ ] Trace works.
- [ ] Analyze works.
- [ ] Refinement works against a controlled change.
- [ ] Stale propagation is demonstrated.
- [ ] Reconciliation is demonstrated.
- [ ] False convergence is rejected.
- [ ] Valid convergence is demonstrated.
- [ ] Generated Trace Index can be deleted/rebuilt.
- [ ] Fixture can be repeated without uncontrolled state drift.

----------------------------------------------------------------------
R. NON-PRODUCTION PILOT
----------------------------------------------------------------------

- [ ] Pilot acceptance criteria were defined before interpreting results.
- [ ] Brownfield Adoption was exercised.
- [ ] Existing project logic remained intact.
- [ ] Repeated adoption was reviewed.
- [ ] Trace Index behavior was reviewed.
- [ ] Analyze findings were reviewed.
- [ ] Convergence findings were reviewed.
- [ ] At least one lifecycle migration was exercised where applicable.
- [ ] Pilot defects were recorded.
- [ ] Pilot limitations were recorded.
- [ ] Pilot did not hide unsupported states.
- [ ] Pilot results informed the remaining backlog.

----------------------------------------------------------------------
S. DOCUMENTATION
----------------------------------------------------------------------

- [ ] README describes real current capabilities.
- [ ] Current state and target state are distinguishable.
- [ ] Architecture ownership is documented.
- [ ] Hybrid migration is documented.
- [ ] Company Layer separation is documented correctly.
- [ ] Artifact Trace Index ownership is documented.
- [ ] Brownfield behavior is documented.
- [ ] Testing is documented.
- [ ] Known limitations are documented.
- [ ] majorchange.md does not falsely claim incomplete targets as implemented.
- [ ] TODO.md agrees with implementation reality.
- [ ] development-backlog.md remains the detailed work program.
- [ ] Another agent can continue from repository documentation.

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