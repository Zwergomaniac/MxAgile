# MASTER PROMPT: mxagile-AI Major Evolution
## Mendix-native Spec-Driven Development, Mockup-Driven Discovery and Brownfield Migration

You are working on an existing agentic Mendix development framework named `mxagile-ai`.

Your task is NOT to replace the existing framework with GitHub Spec Kit.

Your task is to evolve the existing `mxagile-ai` framework into a Mendix-native, mockup-driven, spec-driven development framework that adopts the strongest architectural concepts of Spec Kit while preserving and strengthening the valuable mxagile-AI concepts that already exist.

The working directory contains the editable copy of the framework.

IMPORTANT:
- Work only inside the editable `mxagile-ai COPILOT-Edit` copy.
- Do not modify the IST/reference copy.
- Treat the existing implementation as valuable production work.
- Do not perform a blind rewrite.
- Do not delete or replace working mechanisms simply because an equivalent Spec Kit mechanism exists.
- Preserve backward compatibility wherever reasonably possible.
- Existing mxagile-AI projects must have a realistic incremental migration path.
- Perform the work iteratively and validate continuously.
- Before making structural changes, analyze the actual repository thoroughly.
- Where this prompt makes an assumption that conflicts with the actual repository, prefer the repository reality, document the deviation, and preserve the architectural intention described here.

======================================================================
1. PRIMARY OBJECTIVE
======================================================================

Evolve mxagile-AI into a framework with the following conceptual pipeline:

    PROJECT INITIALIZATION
              |
              v
       PROJECT PRINCIPLES
        / CONSTITUTION
              |
              v
          DISCOVERY
              |
              v
         HTML MOCKUP
              |
              v
         PAGE YAML
              |
              v
        REQUIREMENTS
              |
              v
       DISCOVERY GATE
              |
              v
        FEATURE SPEC
              |
              v
          CLARIFY
              |
              v
           PLAN
              |
              v
           TASKS
              |
              v
     CONSISTENCY ANALYSIS
              |
              v
    MENDIX IMPLEMENTATION
              |
              v
       MXCLI / MDL
              |
              v
    MENDIX VALIDATION
              |
              v
         CONVERGE


This must NOT become a conventional high-code Spec Kit implementation.

mxagile-AI continues to own:
- Mendix methodology
- Discovery methodology
- Mockup methodology
- Page YAML semantics
- Requirement semantics
- Mendix implementation strategy
- mxcli integration
- Mendix validation strategy

Spec Kit concepts are used to improve:
- initialization
- reproducibility
- process structure
- artifact lifecycle
- specification lifecycle
- clarification
- planning
- task decomposition
- quality gates
- analysis
- convergence
- brownfield adoption
- script-driven automation
- agent independence

======================================================================
2. FIRST ACTION: REPOSITORY ANALYSIS
======================================================================

Before implementing anything, recursively inspect the complete repository.

Pay particular attention to:

- `.mxagile-ai`
- `skillssource`
- `scripts`
- `adapters`
- `planning`
- `ui-inventory`
- `checklists`
- `sprints`
- `tests`
- mockup directories
- HTML files
- YAML/YML files
- requirement files
- specifications
- planning artifacts
- agent instructions
- skills
- prompts
- initialization scripts
- bootstrap mechanisms
- validation scripts
- backlog mechanisms
- sprint mechanisms
- test mechanisms
- documentation
- README files

Identify both explicit and implicit workflows.

Do NOT immediately start restructuring files.

First reconstruct the existing architecture.

Determine:

1. How discovery currently starts.
2. How HTML mockups are created and maintained.
3. How individual pages are represented as YAML.
4. How YAML descriptions are generated from HTML.
5. How requirements are derived.
6. How requirements are classified.
7. How assumptions are represented.
8. How open questions are represented.
9. How confirmed information is represented.
10. How Mendix candidates are identified.
11. How specifications are currently maintained.
12. How planning works.
13. How tasks/backlog/sprints work.
14. How implementation agents consume those artifacts.
15. How validation and testing work.
16. Which operations are script-driven.
17. Which operations rely mainly on prompts or agent judgment.
18. Which artifacts are currently treated as sources of truth.
19. Which artifacts are generated or derived.
20. Where artifact drift can currently occur.
21. What mechanisms already exist that overlap with Spec Kit.
22. What mechanisms are more Mendix-specific or more useful than the Spec Kit equivalent.

Create an internal architecture map before making changes.

Do not assume the directory names above are exact architectural boundaries.
Follow actual dependencies in the repository.

======================================================================
3. CREATE `majorchange.md` BEFORE THE MAJOR IMPLEMENTATION
======================================================================

After analyzing the repository, create:

    majorchange.md

at an appropriate high-level documentation location, preferably repository root unless the current documentation architecture strongly indicates another canonical location.

This document is critical.

It must serve simultaneously as:

1. architecture decision document,
2. major-version migration guide,
3. brownfield adoption guide,
4. compatibility guide,
5. conceptual explanation for future coding agents,
6. human-readable explanation of why this evolution was made.

It must be sufficiently detailed to allow older mxagile-AI projects to be migrated later.

Include at least:

# mxagile-AI Major Evolution

## 1. Executive Summary

Explain:
- what changed,
- why it changed,
- what remains unchanged,
- why mxagile-AI is not simply becoming Spec Kit,
- why mockup-driven development remains central.

## 2. Design Principles

Include principles such as:

- Mendix-native, not high-code adapted
- Mockup-driven discovery remains first-class
- Page YAML is a first-class semantic artifact
- Requirements retain stable identity
- Derived artifacts must be traceable
- Changes propagate through controlled reconciliation
- Agents must not silently change business intent
- Brownfield compatibility is mandatory
- Human review gates exist for important semantic changes
- Automation should be script-driven where determinism matters
- Agent reasoning should be used where semantic interpretation matters
- mxcli is the Mendix engineering/execution layer
- mxagile-AI remains agent-harness independent where possible

## 3. Old Architecture

Document the detected current architecture based on actual repository evidence.

Do not invent missing mechanisms.

## 4. New Architecture

Describe:

    Discovery
        |
    HTML Mockup
        |
    Page YAML
        |
    Requirements
        |
    Living Feature Spec
        |
    Plan
        |
    Tasks
        |
    Mendix Implementation
        |
    Validation
        |
    Convergence


## 5. Artifact Responsibility Model

For every important artifact document:

- purpose
- owner
- source-of-truth status
- derived-from relationship
- downstream consumers
- whether manually editable
- whether generated
- whether regeneration may overwrite it
- stable identifiers
- validation rules

## 6. Source-of-Truth Rules

Explicitly define that there is NOT necessarily one universal source of truth.

Examples:

- HTML owns approved visual/interaction representation.
- Page YAML owns structured semantic page description.
- Requirements own accepted business intent.
- Feature Spec owns accepted feature behavior.
- Plan owns implementation strategy.
- Tasks own executable work decomposition.
- Mendix model owns implemented system state.

Clarify conflicts and precedence.

Mockup changes must NOT automatically override accepted business requirements.

## 7. Traceability Model

Document intended traceability:

    HTML element
        <->
    Page YAML artifact
        <->
    Requirement
        <->
    Feature Spec
        <->
    Plan
        <->
    Task
        <->
    Mendix artifact
        <->
    Validation evidence

Define stable IDs.

Example categories may include:

    PAGE-*
    FIELD-*
    ACT-*
    REQ-*
    SPEC-*
    TASK-*

Do not force these exact patterns if the repository already has a sensible ID convention.
Prefer migration-compatible extensions of existing conventions.

## 8. Discovery Lifecycle

Describe existing discovery plus improved workflow.

Discovery must remain iterative.

## 9. Mockup Lifecycle

Explain:
- creation,
- interpretation,
- YAML derivation,
- user review,
- approval,
- refinement,
- version changes,
- impact analysis.

## 10. Refinement Lifecycle

This is especially important.

Document:

    Mockup vN
        |
        v
    Mockup vN+1
        |
        v
    Change Detection
        |
        v
    Change Classification
        |
        +-- visual
        +-- interaction
        +-- behavior
        +-- data
        +-- navigation
        +-- validation
        +-- authorization/security
        +-- unknown
        |
        v
    Page YAML Impact
        |
        v
    Requirement Impact
        |
        v
    Spec Impact
        |
        v
    Plan Impact
        |
        v
    Task Impact
        |
        v
    Mendix Artifact Impact
        |
        v
    Reconciliation Gate

No destructive downstream update should occur purely because the HTML changed.

## 11. Living Specification Model

Explain that specifications evolve.

A changed accepted requirement can trigger:

    requirements
        ->
    feature spec
        ->
    plan
        ->
    tasks
        ->
    implementation

But implementation discoveries may also reveal missing information.

Support controlled flow-back:

    implementation discovery
        ->
    proposed requirement/spec adjustment
        ->
    review
        ->
    reconciliation

## 12. Quality Gates

Document:
- discovery gate
- mockup understanding gate
- requirement quality gate
- specification quality gate
- plan completeness gate
- task readiness gate
- implementation gate
- Mendix validation gate
- convergence gate

## 13. Mendix Boundary

Explicitly explain:

Spec-driven orchestration decides WHAT and WHY and manages the delivery lifecycle.

mxcli and Mendix-specific skills determine HOW implementation is performed in the Mendix model.

Do not introduce assumptions such as:
- npm test
- conventional source-code unit tests
- source tree linting
- code coverage

unless the actual project specifically uses those technologies.

## 14. Validation Strategy

Explain Mendix-native verification layers.

Potential layers, when supported by the project/tooling:

- artifact consistency
- model/MDL validation
- mxcli checks
- Mendix build validation
- runtime startup
- functional tests
- microflow tests
- integration validation
- browser/UI verification
- requirement acceptance
- traceability completeness

Only document mechanisms actually supported after repository/tool analysis.

## 15. Greenfield Initialization

Document the new init flow.

## 16. Brownfield Adoption

Document how an existing project adopts the framework without recreating its entire history.

## 17. Legacy Compatibility

Explain which old workflows continue to work.

## 18. Migration Matrix

Create a detailed mapping:

    OLD ARTIFACT / MECHANISM
            ->
    NEW ARTIFACT / MECHANISM
            ->
    MIGRATION REQUIRED?
            ->
    AUTOMATIC / MANUAL
            ->
    BREAKING?

## 19. Incremental Migration

Migration must NOT require a big bang.

Support mixed-mode projects where appropriate:

Old features:
    previous workflow

New/refined features:
    new living-spec workflow

## 20. Breaking Changes

List only actual breaking changes introduced by this implementation.

## 21. Rollback Considerations

Explain how teams can fall back or stop adoption without destroying existing project artifacts.

## 22. Agent Migration Notes

Explain how older prompts/agents/skills map into the new framework.

## 23. Directory Changes

Document:
- old directories,
- new directories,
- moved files,
- compatibility aliases/shims if any.

## 24. Command Changes

Document all new or changed commands.

## 25. Migration Checklist

Provide a practical checklist for upgrading an existing mxagile-AI project.

======================================================================
4. DO NOT FORK OR COPY SPEC KIT BLINDLY
======================================================================

Do not vendor large portions of GitHub Spec Kit unless technically necessary and justified.

Prefer adopting architectural concepts.

mxagile-AI must remain understandable without requiring developers to understand Spec Kit internals.

Where useful, borrow concepts similar to:

- init
- constitution
- specify
- clarify
- checklist
- plan
- tasks
- analyze
- implement
- converge
- living specs
- brownfield adoption

But adapt semantics to Mendix and the actual mxagile-AI architecture.

Avoid naming every command `speckit.*` unless there is a compelling compatibility reason.

mxagile-AI should remain mxagile-AI.

======================================================================
5. INITIALIZATION / BOOTSTRAP
======================================================================

Implement or evolve a deterministic initialization mechanism.

The repository may already have initialization scripts. Reuse and improve them rather than duplicating them.

Conceptual command:

    dfc init

The actual implementation may be:
- PowerShell,
- Python,
- shell,
- another existing framework mechanism,
- an agent skill invoking deterministic scripts.

Prefer technology already used by the repository.

Initialization should be idempotent.

Running initialization repeatedly must not destroy user data.

It should detect:

A. Empty/new project
B. Existing mxagile-AI project
C. Existing Mendix project without the new lifecycle
D. Partially migrated project

Generate only missing framework-owned structures.

Do not overwrite user-owned project artifacts without explicit migration logic.

Potential managed framework structure:

    .mxagile-ai/
        config.*
        constitution.*
        state/
        schemas/
        templates/

But use the repository's actual conventions where possible.

Init should establish:
- framework configuration
- framework version/state
- required directories
- templates
- schemas
- scripts/hooks
- agent integrations where applicable
- baseline project principles
- artifact index if introduced

======================================================================
6. BROWNFIELD ADOPTION
======================================================================

Implement a brownfield adoption mechanism.

Conceptual command:

    dfc adopt

Do NOT require old projects to manufacture historical specs.

Adoption should reconstruct CURRENT STATE, not fictional history.

Conceptual process:

    Existing project
          |
          v
    Inventory
          |
          v
    Existing mockups
          |
          v
    Existing Page YAML
          |
          v
    Existing requirements/specs
          |
          v
    Existing Mendix artifacts
          |
          v
    Traceability baseline
          |
          v
    Gaps marked UNKNOWN
          |
          v
    New lifecycle active for future changes

Rules:

- Do not fabricate requirements.
- Do not fabricate confirmation history.
- Do not claim inferred behavior is confirmed.
- Mark uncertain relationships explicitly.
- Preserve legacy artifacts.
- Produce a migration/adoption report.

======================================================================
7. PROJECT CONSTITUTION / PRINCIPLES
======================================================================

Add a project-level principles mechanism inspired by Spec Kit Constitution.

It must contain project-wide constraints rather than feature requirements.

Potential topics:

- Mendix version constraints
- module architecture
- naming conventions
- security rules
- Atlas/design system rules
- Marketplace module modification policy
- Java/JavaScript escape rules
- reusable components
- integration rules
- logging
- error handling
- testing strategy
- mockup authority rules
- requirement authority rules
- AI usage/compliance rules
- Definition of Done
- architecture constraints
- documentation expectations

Agents must consume these principles during:
- planning
- task generation
- implementation
- analysis
- convergence

Avoid turning this into a giant always-loaded prompt.

If the repository has a skill/context loading mechanism, make detailed rules loadable on demand to reduce context bloat.

======================================================================
8. MOCKUP PROCESS MUST BE STRENGTHENED, NOT REPLACED
======================================================================

The existing HTML mockup process is a central feature.

Treat HTML mockups as executable/inspectable discovery artifacts.

The desired relationship is:

    HTML Mockup
        <->
    Page YAML
        <->
    Requirements

These are related but not interchangeable.

HTML:
- visual structure
- interaction representation
- navigation representation
- stakeholder review surface

Page YAML:
- structured semantic interpretation
- machine-readable page contract
- structured fields/actions/states/navigation references
- link to requirements

Requirements:
- accepted business intent
- acceptance conditions
- constraints
- roles
- rules

Do not infer that changing one automatically authorizes destructive changes to the others.

======================================================================
9. PAGE YAML AS FIRST-CLASS ARTIFACT
======================================================================

Analyze the existing per-page YAML schema before changing it.

Preserve all useful properties.

Extend only where necessary.

Desired conceptual information:

    page
    purpose
    roles
    sections
    components
    fields
    actions
    navigation
    states
    visibility
    validation
    data needs
    business rules
    requirement references
    source references
    confidence/status
    open questions

Do not introduce redundant duplication.

Where information belongs in requirements rather than Page YAML, reference the requirement rather than copy the full content.

======================================================================
10. STABLE ARTIFACT IDENTITIES
======================================================================

Introduce or strengthen stable identifiers.

Identifiers must survive:
- wording changes
- file movement
- mockup refinements
- planning regeneration

Do not use line numbers as identity.

Possible conceptual IDs:

    PAGE-PLANNING-DETAIL
    FIELD-PLANNING-FTE
    ACT-PLANNING-SUBMIT
    REQ-PLN-042

Use existing naming conventions where available.

Traceability is more important than exact syntax.

======================================================================
11. REQUIREMENT PROVENANCE
======================================================================

Every important requirement should be traceable to its origin where possible.

Possible sources:

- stakeholder confirmation
- mockup
- Page YAML
- uploaded document
- existing system behavior
- implementation discovery
- assumption

Preserve existing useful statuses.

The repository has used concepts such as:

    CONFIRMED_BY_SOURCE
    OPEN
    ASSUMPTION

Do not replace such semantics blindly.

Consider extending them only if required.

Critical rule:

INFERENCE IS NOT CONFIRMATION.

======================================================================
12. DISCOVERY GATE
======================================================================

Preserve the existing philosophy that implementation artifacts are not finalized before mockup understanding has been reviewed.

Formalize this.

The gate should check relevant aspects such as:

- project goal understood
- actors identified
- screens identified
- primary navigation understood
- important data concepts identified
- user actions identified
- major business rules captured
- assumptions visible
- open questions visible
- page YAML generated/updated
- requirement extraction completed
- traceability has no unexplained critical gaps

Do not auto-approve the gate merely because an agent generated the artifacts.

======================================================================
13. REFINEMENT ENGINE
======================================================================

Implement refinement as a first-class workflow.

Conceptual command:

    dfc refine

Refinement can start when any upstream artifact changes, particularly an HTML mockup.

The workflow should:

1. identify previous accepted baseline,
2. inspect current artifact,
3. calculate meaningful changes,
4. classify those changes,
5. identify potentially impacted Page YAML,
6. identify impacted requirements,
7. identify impacted specs,
8. identify impacted plans,
9. identify impacted tasks,
10. identify potentially impacted Mendix artifacts,
11. produce an impact report,
12. distinguish safe derived updates from semantic changes requiring review,
13. reconcile accepted changes,
14. mark outdated downstream artifacts appropriately.

Do NOT simply regenerate everything.

Avoid losing manually captured design reasoning.

======================================================================
14. CHANGE CLASSIFICATION
======================================================================

Support semantic change classification.

At minimum distinguish conceptually:

- VISUAL
- CONTENT
- INTERACTION
- NAVIGATION
- DATA
- BUSINESS_BEHAVIOR
- VALIDATION
- SECURITY
- INTEGRATION
- UNKNOWN

The exact enum may differ based on current repository conventions.

Example:

CSS color changed:
    likely VISUAL

New Cost Center field:
    potentially DATA + BUSINESS_BEHAVIOR

New Submit button:
    potentially INTERACTION + BUSINESS_BEHAVIOR + SECURITY + VALIDATION

Removing a button:
    must NOT automatically delete downstream requirements or Mendix behavior.

======================================================================
15. IMPACT ANALYSIS
======================================================================

Implement:

    dfc impact

or integrate equivalent behavior into existing commands.

Impact should answer:

"What may be affected if this artifact changes?"

Example conceptual result:

    ACT-PLN-SUBMIT changed

    Affected:
    - PAGE-PLANNING-DETAIL
    - REQ-PLN-067
    - SPEC-WORKFORCE-SUBMISSION
    - TASK-123
    - Mendix page candidate
    - Mendix microflow candidate
    - authorization rules
    - tests

Distinguish:
- definitely affected,
- probably affected,
- potentially affected,
- unknown.

Do not fabricate exact Mendix dependencies if they cannot be established.

======================================================================
16. LIVING FEATURE SPECS
======================================================================

Introduce or formalize feature specifications.

Feature specs describe:

WHAT the system must do
and
WHY.

They should not become implementation documentation.

Implementation details belong in Plan.

Requirements may be more atomic than feature specs.

Feature Specs group and contextualize accepted requirements.

A feature spec should reference requirement IDs rather than duplicating all requirements unnecessarily.

When accepted intended behavior changes:

    Requirement update
        ->
    Feature Spec reconciliation
        ->
    Plan reconciliation
        ->
    Task reconciliation
        ->
    implementation reconciliation

======================================================================
17. CLARIFICATION
======================================================================

Implement a structured clarification workflow inspired by Spec Kit.

Conceptual command:

    dfc clarify

It should inspect:
- requirements,
- Page YAML,
- feature spec,
- assumptions,
- open questions,
- conflicting artifacts.

It should identify meaningful ambiguity.

Do not ask dozens of generic questions.

Prioritize questions that:
- block implementation,
- affect architecture,
- affect security,
- affect data model,
- affect user workflow,
- could cause significant rework.

Answers must update the appropriate canonical artifact.

Do NOT hide decisions only inside chat history.

======================================================================
18. REQUIREMENT QUALITY CHECKLISTS
======================================================================

Strengthen the existing checklist architecture.

Introduce the concept of "tests for requirements".

Potential questions:

- Is the actor known?
- Is the trigger known?
- Is expected behavior clear?
- Are invalid states defined?
- Are permissions defined?
- Are important edge cases specified?
- Is navigation behavior defined?
- Are acceptance conditions testable?
- Are dependencies explicit?

Reviewer-owned gates must not be silently self-approved by the same implementation agent.

======================================================================
19. PLANNING
======================================================================

Implement/evolve:

    dfc plan

Plan is derived from:
- accepted requirements,
- feature spec,
- project principles,
- Page YAML,
- existing architecture,
- Mendix project reality.

The plan must be Mendix-native.

Do NOT produce generic architecture such as:

    Repository
    Service Layer
    Controller
    React component

unless actually applicable.

A Mendix plan may discuss:

- modules
- domain model
- entities
- associations
- enumerations
- pages
- snippets
- layouts
- microflows
- nanoflows
- workflows
- security
- navigation
- integrations
- constants
- scheduled events
- reusable components
- marketplace modules
- test strategy

Only include artifact types relevant to the feature.

======================================================================
20. TASK GENERATION
======================================================================

Implement/evolve:

    dfc tasks

Tasks must be derived from Plan.

Tasks should reference:
- requirements,
- spec,
- Page YAML/screens,
- expected Mendix artifacts,
- validation criteria.

Avoid enormous tasks.

Avoid generating trivial tiny tasks that create unnecessary agent overhead.

Respect dependency order.

Example:

Domain model changes may need to precede pages that consume those entities.

Security-related work must not be postponed as an afterthought when it affects implementation design.

======================================================================
21. GLOBAL ANALYZE COMMAND
======================================================================

Implement or strengthen:

    dfc analyze

This is one of the most important features.

It should analyze consistency across the full artifact chain:

    HTML
      <->
    Page YAML
      <->
    Requirements
      <->
    Feature Specs
      <->
    Plan
      <->
    Tasks
      <->
    Mendix implementation metadata/artifacts where inspectable
      <->
    Validation evidence

Detect:

- orphan requirements
- unmatched mockup elements
- obsolete Page YAML
- spec drift
- undocumented plan decisions
- tasks without requirement/spec traceability
- requirements with no implementation path
- implemented behavior without known requirement
- unresolved blocking questions
- stale generated artifacts
- violated project principles

Produce a useful report.

Avoid noisy warnings that cannot be acted upon.

======================================================================
22. TRACEABILITY REPORT
======================================================================

Produce human- and machine-readable traceability.

Conceptual output:

    REQ-042
      Mockup: PASS
      Page YAML: PASS
      Spec: PASS
      Plan: PASS
      Task: PASS
      Mendix: PASS
      Validation: PASS

    REQ-067
      Mockup: PASS
      Page YAML: PASS
      Spec: PASS
      Plan: PASS
      Task: MISSING
      Mendix: UNKNOWN
      Validation: MISSING

Prefer structured data internally plus readable report output.

======================================================================
23. IMPLEMENTATION BOUNDARY
======================================================================

mxagile-AI must explicitly separate orchestration from Mendix engineering.

Conceptual model:

    DFC Lifecycle
        |
        v
    Prepared Mendix Task
        |
        v
    Mendix implementation agent
        |
        v
    mxcli skills
        |
        v
    mxcli / MDL
        |
        v
    Mendix project

Do not duplicate mxcli knowledge unnecessarily inside Spec templates.

Load Mendix expertise from the appropriate skills.

Avoid enormous master prompts containing all MDL syntax.

======================================================================
24. MENDIX-NATIVE VALIDATION
======================================================================

Do not import conventional high-code testing assumptions.

Inspect actual mxcli capabilities available in the environment.

Use supported mechanisms.

Potential pipeline:

    Artifact validation
        |
    MDL/model validation
        |
    lint/check
        |
    build
        |
    runtime startup
        |
    microflow/functional tests
        |
    integration tests
        |
    browser/UI validation
        |
    acceptance validation

Build success alone must NOT imply requirement completeness.

Test success alone must NOT imply spec alignment.

======================================================================
25. CONVERGENCE
======================================================================

Implement:

    dfc converge

The purpose is to answer:

"Is the feature actually complete against accepted intent?"

Check:

- requirements coverage
- Page YAML alignment
- feature spec alignment
- plan completion
- task completion
- Mendix implementation
- validation evidence
- remaining open questions
- principle violations
- known deviations

If gaps remain:

Do NOT simply declare failure.

Generate or propose targeted remaining tasks.

Support iterative loop:

    implement
        ->
    validate
        ->
    converge
        ->
    remaining tasks
        ->
    implement
        ->
    converge

until accepted completion.

======================================================================
26. SCRIPT-DRIVEN VS AGENT-DRIVEN RESPONSIBILITIES
======================================================================

Be deliberate.

Prefer scripts for deterministic operations:

- init
- directory creation
- schema validation
- ID validation
- file indexing
- artifact reference checking
- dependency graph construction where deterministic
- migration transforms
- report generation
- state management
- command wrappers

Prefer agents for semantic operations:

- interpreting mockups
- identifying business meaning
- classifying ambiguous UI changes
- requirement extraction
- clarification
- architectural reasoning
- impact interpretation
- plan generation
- task decomposition

Never use an LLM where a deterministic script would be more reliable.

Never force deterministic scripts to decide ambiguous business semantics.

======================================================================
27. CONFIGURATION
======================================================================

Introduce or improve framework configuration.

Potential conceptual configuration:

    framework_version
    project_mode
    mendix_version
    mockup_root
    ui_inventory_root
    requirements_root
    specs_root
    planning_root
    task_root
    tests_root
    traceability
    validation
    agent integrations

Do not build configuration fields that have no consumer.

Keep defaults sensible.

======================================================================
28. FRAMEWORK STATE
======================================================================

For reliable refinement, the framework needs to know accepted baselines.

Design a lightweight state mechanism.

Potential tracked information:

- framework version
- artifact versions/hashes
- accepted mockup baseline
- last reconciliation
- generated artifact ownership
- migration state

Do NOT turn this into a database unless there is a strong reason.

Prefer repository-friendly text/structured files.

Generated state should be deterministic and reviewable where practical.

======================================================================
29. GENERATED VS HUMAN-OWNED ARTIFACTS
======================================================================

Clearly mark artifact ownership.

Example categories:

HUMAN/AGENT MAINTAINED:
- requirements
- decisions
- project principles
- accepted specs

DERIVED:
- indexes
- traceability reports
- dependency reports
- some planning projections

GENERATED BUT REVIEWABLE:
- Page YAML extraction
- draft requirements
- impact reports

Never overwrite manually owned artifacts merely because regeneration is convenient.

======================================================================
30. SCHEMAS
======================================================================

Where appropriate, introduce machine-readable schemas for structured artifacts.

Priority candidates:
- Page YAML
- requirement metadata
- traceability
- framework configuration
- state

Do not over-engineer Markdown schemas.

Validate YAML deterministically where possible.

======================================================================
31. AGENT-HARNESS INDEPENDENCE
======================================================================

mxagile-AI should work with different coding agents where feasible.

Target conceptual compatibility with:
- Claude Code
- GitHub Copilot
- OpenCode
- Codex
- other skill-aware agents

Do not duplicate whole workflow implementations for every harness.

Prefer:

    canonical skill source
            |
            v
    adapter / generation
            |
       +----+----+----+
       v    v    v    v
    Claude OpenCode Copilot Codex

Reuse the existing `skillssource` and `adapters` architecture if that is what it already implements.

======================================================================
32. CONTEXT MANAGEMENT
======================================================================

Avoid instruction bloat.

Do not place:
- all Mendix knowledge,
- all mockup rules,
- all planning rules,
- all testing rules

into a single global agent instruction.

Use skills and progressive/on-demand context loading.

Top-level instructions should explain:
- workflow,
- boundaries,
- which skills to load.

Detailed expertise belongs in focused skills.

======================================================================
33. DIRECTORY STRUCTURE
======================================================================

Do NOT force a completely new directory structure before analyzing current conventions.

Prefer minimal evolution.

If new directories are necessary, consider concepts such as:

    .mxagile-ai/
        config
        constitution
        state
        schemas
        templates

    specs/
    requirements/
    planning/
    ui-inventory/
    checklists/
    tests/

But preserve current directories when they already fulfill the same responsibility.

Document every structural change in `majorchange.md`.

======================================================================
34. MIGRATION COMPATIBILITY
======================================================================

Existing projects are a first-class concern.

Three modes should conceptually be supported:

MODE 1: LEGACY

    old mxagile-AI workflow continues

MODE 2: HYBRID

    existing features remain legacy
    new/refined features use living specs

MODE 3: NATIVE

    complete new DFC lifecycle

Do not unnecessarily force all projects into MODE 3.

======================================================================
35. MIGRATION TOOLING
======================================================================

Where realistic, create deterministic migration tooling.

Conceptual:

    dfc migrate --analyze
    dfc migrate --apply

or repository-equivalent scripts.

Analyze should:
- never mutate,
- inventory current files,
- show intended changes,
- flag conflicts,
- show unsupported legacy patterns.

Apply should:
- create backups or otherwise operate safely according to repository practices,
- migrate framework-owned structures,
- preserve project artifacts,
- produce migration report.

Never pretend inferred requirements are historical facts.

======================================================================
36. COMPATIBILITY SHIMS
======================================================================

If existing agents expect old paths or artifact names, consider temporary compatibility shims.

Do not keep duplicate sources of truth indefinitely.

Document:
- deprecated path
- replacement
- transition policy

======================================================================
37. TESTING THE FRAMEWORK ITSELF
======================================================================

Add tests for the mxagile-AI framework, not only generated Mendix applications.

Important cases:

INIT:
- clean project
- repeated init
- partially initialized project
- existing project

ADOPT:
- old DFC project
- existing Mendix project
- incomplete metadata

REFINE:
- visual-only mockup change
- new field
- removed field
- new action
- changed action
- navigation change
- ambiguous change

TRACEABILITY:
- orphan requirement
- missing YAML reference
- missing task
- stale artifact

MIGRATION:
- legacy project
- hybrid project
- already migrated project

Ensure operations are safe to rerun.

======================================================================
38. DOCUMENTATION
======================================================================

Update normal project documentation in addition to `majorchange.md`.

Users must understand:

NEW PROJECT:

    init
      ->
    discovery
      ->
    mockup
      ->
    requirements
      ->
    spec
      ->
    plan
      ->
    tasks
      ->
    implement
      ->
    validate
      ->
    converge

EXISTING PROJECT:

    adopt/migrate analysis
      ->
    baseline
      ->
    hybrid or native mode

REFINEMENT:

    change mockup
      ->
    refine
      ->
    impact review
      ->
    reconcile
      ->
    analyze
      ->
    continue implementation

======================================================================
39. DO NOT LOSE EXISTING mxagile-AI ADVANTAGES
======================================================================

During implementation continuously ask:

"Does the new solution make an existing mxagile-AI capability worse?"

Especially protect:
- HTML mockup workflow
- Page YAML
- structured discovery
- requirement extraction
- understanding review
- open-question handling
- Mendix candidate identification
- backlog/sprint concepts
- reusable skills
- agent adapters
- current deterministic scripts
- Mendix-specific knowledge

If a Spec Kit concept conflicts with a stronger mxagile-AI concept:

Prefer mxagile-AI and document the reason.

======================================================================
40. IMPLEMENTATION STRATEGY
======================================================================

Implement incrementally.

Recommended dependency order:

PHASE A: ANALYSIS
- inventory repository
- map architecture
- map artifact lifecycle
- identify compatibility constraints

PHASE B: DOCUMENTATION BASELINE
- create majorchange.md
- capture old/new architecture
- migration model

PHASE C: FOUNDATION
- framework config/version
- constitution/principles
- state/baseline model
- schemas where justified

PHASE D: INIT AND ADOPT
- idempotent init
- brownfield adoption
- migration analysis

PHASE E: TRACEABILITY
- stable IDs
- artifact references
- traceability index/report

PHASE F: DISCOVERY 2.0
- formal HTML <-> Page YAML <-> Requirements chain
- retain understanding review gate

PHASE G: REFINEMENT
- baseline comparison
- semantic change classification
- impact analysis
- reconciliation

PHASE H: SPEC LIFECYCLE
- feature spec
- clarify
- requirement checklist
- living spec behavior

PHASE I: PLAN/TASKS
- Mendix-native plan
- traceable task decomposition

PHASE J: ANALYSIS
- cross-artifact consistency checks

PHASE K: IMPLEMENTATION INTEGRATION
- connect prepared tasks to existing mxcli/Mendix skills
- do not duplicate mxcli

PHASE L: VALIDATION/CONVERGENCE
- Mendix-native verification
- convergence loop

PHASE M: AGENT ADAPTERS
- update supported harness integrations from canonical sources

PHASE N: FRAMEWORK TESTS
- migration tests
- refinement tests
- idempotency tests
- backward compatibility tests

PHASE O: DOCUMENTATION FINALIZATION
- update majorchange.md with actual implemented paths/commands
- update migration checklist
- update README/user documentation

======================================================================
41. QUALITY GATES DURING IMPLEMENTATION
======================================================================

After every major implementation phase:

1. run existing tests,
2. run new tests,
3. inspect changes,
4. ensure existing workflows still function unless intentionally deprecated,
5. update majorchange.md if reality differs from the initial plan,
6. check for duplicate sources of truth,
7. check for unnecessary generated boilerplate,
8. check context size/instruction bloat,
9. check migration compatibility.

Do not postpone compatibility verification until the very end.

======================================================================
42. GIT / CHANGE SAFETY
======================================================================

Use the repository's existing Git conventions.

Before broad transformations:
- understand current status,
- avoid overwriting unrelated user changes,
- keep changes logically separable.

Do not silently delete files.

When replacing an old mechanism:
- document replacement,
- migrate consumers where possible,
- preserve compatibility if practical,
- mark deprecation clearly.

Do not perform destructive history rewriting.

======================================================================
43. DECISION LOG
======================================================================

For significant architecture decisions, record:

- decision,
- alternatives,
- reason,
- migration impact,
- compatibility impact.

Use an existing decision mechanism if present.

Otherwise keep a concise decision section in `majorchange.md` or introduce a lightweight ADR mechanism only if justified.

Do not create bureaucracy for trivial decisions.

======================================================================
44. EXPECTED END STATE
======================================================================

A new project should eventually be able to follow a predictable workflow conceptually similar to:

    init
      |
    constitution/project principles
      |
    discovery
      |
    mockup
      |
    page YAML
      |
    requirements
      |
    discovery review
      |
    feature spec
      |
    clarify
      |
    plan
      |
    tasks
      |
    analyze
      |
    Mendix implementation via mxcli
      |
    validate
      |
    converge

A changed mockup should follow:

    changed HTML
      |
    refine
      |
    semantic diff
      |
    Page YAML impact
      |
    requirement impact
      |
    spec impact
      |
    planning/task impact
      |
    Mendix impact
      |
    review/reconciliation
      |
    implementation
      |
    converge

An old project should follow:

    existing project
      |
    adopt/migration analysis
      |
    current-state baseline
      |
    legacy / hybrid / native choice
      |
    incremental migration

======================================================================
45. REQUIRED DELIVERABLES
======================================================================

Do not consider the task complete merely because documentation was written.

At the end there should be, where supported by the actual repository:

1. `majorchange.md`
2. documented current architecture
3. documented target architecture
4. migration guide
5. migration matrix
6. init/bootstrap capability
7. brownfield adopt capability
8. project principles/constitution mechanism
9. improved artifact schemas
10. stable traceability model
11. strengthened HTML -> Page YAML -> Requirements chain
12. refinement workflow
13. impact analysis
14. living feature specs
15. clarification workflow
16. requirement-quality gates
17. Mendix-native planning
18. traceable task generation
19. global consistency analysis
20. mxcli implementation handoff
21. Mendix-native validation integration
22. convergence workflow
23. compatibility strategy
24. tests
25. updated user/agent documentation

If the repository architecture makes one of these deliverables inappropriate, do not fake it.
Document the reason and implement the equivalent architectural capability.

======================================================================
46. FINAL REVIEW
======================================================================

Before declaring completion perform a final architecture review.

Answer internally and document meaningful deviations:

A. Can a new project initialize reproducibly?

B. Can an existing mxagile-AI project adopt the new architecture without reconstructing fictional history?

C. Can old and new workflows coexist during migration?

D. Can a mockup be refined without silently desynchronizing Page YAML, Requirements, Specs, Plan and Tasks?

E. Can the system show what a mockup change impacts?

F. Are business-semantic changes distinguished from visual changes?

G. Are stable IDs preserved across refinement?

H. Can requirements be traced toward implementation?

I. Can implementation discoveries trigger controlled flow-back?

J. Are Mendix-specific implementation rules delegated to mxcli/skills rather than generic high-code assumptions?

K. Does validation test more than "build succeeded"?

L. Can convergence find remaining gaps?

M. Are deterministic operations implemented as scripts where practical?

N. Is semantic reasoning left to agents where appropriate?

O. Is the framework still agent-harness independent?

P. Did instruction/context bloat become worse?

Q. Is `majorchange.md` sufficient to migrate an older project later?

R. Did any existing useful mxagile-AI capability regress?

If any answer is unsatisfactory, address it before declaring the migration complete.

======================================================================
47. MOST IMPORTANT NON-NEGOTIABLE RULES
======================================================================

1. DO NOT TURN mxagile-AI INTO A GENERIC HIGH-CODE FRAMEWORK.

2. DO NOT REPLACE THE MOCKUP PROCESS.

3. STRENGTHEN:
       HTML <-> Page YAML <-> Requirements

4. DO NOT MAKE HTML THE UNCONDITIONAL SOURCE OF TRUTH.

5. DO NOT SILENTLY PROPAGATE SEMANTIC MOCKUP CHANGES.

6. REQUIRE IMPACT ANALYSIS AND RECONCILIATION.

7. DO NOT FABRICATE REQUIREMENTS DURING BROWNFIELD ADOPTION.

8. DO NOT FORCE OLD PROJECTS INTO A BIG-BANG MIGRATION.

9. PRESERVE LEGACY/HYBRID OPERATION WHERE REASONABLE.

10. KEEP MENDIX IMPLEMENTATION IN THE MENDIX ENGINEERING LAYER.

11. USE MXCLI/SKILLS FOR MENDIX-SPECIFIC IMPLEMENTATION AND VERIFICATION.

12. DO NOT ASSUME CONVENTIONAL SOURCE-CODE TESTING.

13. USE SCRIPTS FOR DETERMINISTIC OPERATIONS.

14. USE AGENTS FOR SEMANTIC REASONING.

15. KEEP ARTIFACT OWNERSHIP EXPLICIT.

16. PRESERVE HUMAN DECISIONS DURING REGENERATION.

17. KEEP TRACEABILITY MACHINE-READABLE.

18. KEEP THE PROCESS REVIEWABLE BY HUMANS.

19. UPDATE `majorchange.md` AS THE IMPLEMENTATION EVOLVES.

20. THE ACTUAL REPOSITORY IS THE AUTHORITY WHEN THIS PROMPT'S ASSUMPTIONS ARE WRONG.


======================================================================
48. START NOW
======================================================================

Begin by recursively analyzing the repository.

Do not ask the user to redesign the framework for you.

Use the existing implementation to resolve details wherever possible.

Then:

1. reconstruct and document the current workflow,
2. create `majorchange.md`,
3. define the migration-compatible target architecture,
4. implement the foundation,
5. implement the phases above in dependency order,
6. continuously test backward compatibility,
7. update documentation as implementation decisions become concrete,
8. complete the final architecture review.

When encountering ambiguity:

- preserve existing behavior if safe,
- prefer reversible changes,
- explicitly document assumptions,
- avoid destructive migration,
- create clear TODOs only where a genuine external decision is required.

The goal is not maximum change.

The goal is a coherent next major version of mxagile-AI that combines:

    mxagile-AI's mockup-driven Mendix discovery
                    +
    structured Page YAML
                    +
    traceable requirements
                    +
    the strongest Spec Kit lifecycle concepts
                    +
    deterministic script-driven framework operations
                    +
    mxcli as Mendix engineering layer

into one consistent, migration-friendly development system.

