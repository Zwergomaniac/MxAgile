# MxAgile Major Evolution

## 1. Executive Summary

This document outlines the major architectural evolution of the `dfc-ai` framework into `MxAgile`. This evolution transforms the framework into a more universal, Mendix-native, spec-driven development system that integrates the powerful lifecycle concepts of Spec Kit while preserving and strengthening the core principles of the original framework.

*   **What changed:** The framework is renamed to `MxAgile`. A formal, traceable, and verifiable lifecycle from mockup to Mendix implementation has been established. This includes the introduction of Living Feature Specs, a structured Refinement Engine for managing change, a global consistency analysis command, and formal processes for brownfield adoption and project initialization. Company-specific content (like Mercedes-Benz modules) is now optional and managed via a pluggable layer system.
*   **Why it changed:** To increase reproducibility, improve traceability, formalize the artifact lifecycle, and make the framework more universal and adaptable for different projects and companies, reducing the risk of artifact drift and providing a clearer path for both greenfield and brownfield projects.
*   **What remains unchanged:** The core philosophy of being mockup-driven and Mendix-native remains central. `mxcli` remains the primary Mendix engineering layer. The phased workflow (`Discovery`, `Refinement`, etc.) and the agent-agnostic skill architecture are preserved and strengthened.
*   **Why MxAgile is not Spec Kit:** MxAgile adopts architectural *concepts* from Spec Kit (e.g., living specs, clarification, planning) but adapts them to a Mendix-native context. It does not adopt high-code assumptions. The mockup-to-Page-YAML analysis via Playwright and the multi-layered, Mendix-native validation process remain unique and core to MxAgile.

## 2. Design Principles

*   **Mendix-native:** The framework is for Mendix development, not a high-code framework adapted for Mendix.
*   **Mockup-driven discovery:** HTML mockups remain a first-class citizen for discovering and defining UI/UX.
*   **Page YAML as a semantic artifact:** Page YAML is a structured, machine-readable contract for a page, not just a list of fields.
*   **Stable Requirement Identity:** Requirements have stable identifiers and are not automatically overridden by upstream changes.
*   **Traceable Derived Artifacts:** All derived artifacts (specs, plans, tasks) must be traceable back to their source requirements and mockups.
*   **Controlled Reconciliation:** Changes propagate through a controlled reconciliation process, not silent, destructive updates.
*   **Human Review Gates:** Important semantic changes require human review and approval.
*   **Script-driven Automation:** Deterministic operations (e.g., initialization, validation) are handled by scripts for reliability.
*   **Agent-driven Reasoning:** Semantic interpretation (e.g., mockup analysis, planning) is delegated to AI agents.
*   **Pluggable Company Layers:** Company-specific conventions, modules, and rules are optional and can be plugged in during initialization.
*   **Brownfield Compatibility:** Existing projects have a clear, incremental path to adopt the new lifecycle.

## 3. Old Architecture (pre-MxAgile)

The previous `dfc-ai` architecture was based on a solid, phase-driven model defined in `orchestrator.md`.

*   **Workflow:** A sequence of phases (`Intake` -> `Discovery` -> `Refinement` -> `Ready` -> `Implementing` -> `Verifying`) with specific agent responsibilities.
*   **Source of Truth:** A clear hierarchy prioritized customer mockups and requirements documents over the Mendix model or board stories.
*   **Artifacts:**
    *   **Inputs:** HTML Mockups and Requirement documents in `input-resources/`.
    *   **Discovery:** A `dfc-ui-agent` analyzed mockups with Playwright to create a "field inventory" (the precursor to Page YAML) in `planning/ui-inventory/`. A `dfc-discovery-agent` analyzed requirements to create `planning/stories/*.md` files.
    *   **Planning:** The `Ready` gate generated an `implementation-checklist.yaml`, a highly structured file that served as the task list for the `Implementation-Agent`.
    *   **Validation:** A multi-step `Verifying` phase used `mxcli`, Docker, and Playwright for technical, UI, and functional validation.
*   **Gaps:** The architecture lacked a "living spec" to group requirements, a formal process for refining artifacts when mockups change, a global analysis command, and a clear brownfield adoption path. Company-specific logic was tightly integrated.

## 4. New Architecture (MxAgile)

The MxAgile workflow strengthens the existing pipeline by introducing new concepts and formalizing the relationships between artifacts.

    PROJECT INITIALIZATION (with Company Layer selection)
              |
              v
       PROJECT PRINCIPLES / CONSTITUTION
              |
              v
          DISCOVERY (HTML Mockup -> Page YAML -> Requirements)
              |
              v
       DISCOVERY GATE (Quality check on discovery artifacts)
              |
              v
        LIVING FEATURE SPEC (Groups and contextualizes requirements)
              |
              v
          CLARIFY (Structured Q&A to resolve ambiguities)
              |
              v
           PLAN (Mendix-native implementation strategy)
              |
              v
           TASKS (Decomposition of the plan into executable steps)
              |
              v
     CONSISTENCY ANALYSIS (`mxagile analyze`)
              |
              v
    MENDIX IMPLEMENTATION (`mxcli` via MxAgile skills)
              |
              v
    MENDIX VALIDATION (Technical, UI, and Acceptance Testing)
              |
              v
         CONVERGE (Checks for completeness against intent)

A key addition is the **Refinement Engine**, which is triggered when an upstream artifact (like a mockup) changes. It performs impact analysis and guides the user through a controlled reconciliation process instead of forcing a full regeneration.

## 5. Artifact Responsibility Model

| Artifact | Purpose | Owner | Source/Derived | Editable | Overwritten? | ID Pattern |
|---|---|---|---|---|---|---|
| `input-resources/` | Raw stakeholder inputs | Human | Source | Yes | No | - |
| `Page YAML` | Structured semantic page description | Generated | Derived from HTML | Reviewable | On reconcile | `PAGE-*`, `FIELD-*` |
| `Requirements` | Accepted business intent | Human/Agent | Derived/Source | Yes | No | `REQ-*` |
| `Feature Spec` | Accepted feature behavior contract | Human/Agent | Derived from Reqs | Yes | On reconcile | `SPEC-*` |
| `Plan` | Mendix-native implementation strategy | Agent | Derived from Spec | No | Yes | - |
| `Tasks` | Executable work decomposition | Agent | Derived from Plan | No | Yes | `TASK-*` |
| `Mendix Model` | Implemented system state | mxcli/Studio Pro | Implementation | Yes | No | - |
| `majorchange.md`| This document | Human/Agent | Source | Yes | No | - |

## 6. Source-of-Truth Rules

MxAgile operates with a multi-polar source-of-truth model:
-   **HTML Mockup:** Owns the *approved visual and interaction representation*.
-   **Page YAML:** Owns the *structured semantic interpretation* of a page.
-   **Requirements:** Own the *atomic, accepted business intent* and acceptance criteria.
-   **Feature Spec:** Owns the *holistic, accepted feature behavior* and acts as a stable contract for implementation.
-   **Mendix Model:** Owns the *as-implemented state* of the system.

**Conflict Precedence:** A change in one artifact does not automatically grant permission to destructively change another. For example, a change in the HTML Mockup triggers the **Refinement Engine**, which analyzes the impact on Page YAML and Requirements. Semantic changes require review and reconciliation before being propagated downstream to the Feature Spec and Plan.

## 7. Traceability Model

Traceability is enforced through stable identifiers used across all artifacts.

    HTML element (via selector)
        <->
    Page YAML artifact (e.g., FIELD-PLANNING-FTE)
        <->
    Requirement (e.g., REQ-PLN-042)
        <->
    Feature Spec (e.g., SPEC-WORKFORCE-SUBMISSION)
        <->
    Plan section
        <->
    Task (e.g., TASK-123)
        <->
    Mendix artifact (documented mapping)
        <->
    Validation evidence (e.g., test case)

A new command, `mxagile trace <ID>`, will allow querying these relationships.

## 8. Discovery Lifecycle

The Discovery phase is enhanced to produce three distinct, linked artifacts:
1.  **HTML Mockup:** The visual and interactive source, analyzed by the UI-Agent via Playwright.
2.  **Page YAML:** A structured representation of the mockup's contents, semantics, and actions, generated by the UI-Agent from the mockup. Stored in `ui-inventory/`.
3.  **Requirements:** Atomic statements of business intent, extracted from requirements documents and the semantic understanding of the mockup. Stored in `requirements/`.

The **Discovery Gate** ensures these three artifacts are consistent and complete before they can be used to build a Feature Spec.

## 9. Mockup Lifecycle

-   **Creation:** Mockups are created manually or by the UI-Agent in `generate` mode. They reside in `input-resources/ui-ux/`.
-   **Interpretation:** The UI-Agent analyzes the mockup using Playwright to generate Page YAML and screenshots.
-   **Approval:** A human must approve the mockup and the initial Page YAML interpretation.
-   **Refinement:** When an HTML mockup file is changed, the `mxagile refine` command is triggered. This starts the Refinement Engine.
-   **Impact Analysis:** The engine semantically diffs the mockup changes and reports the potential impact on Page YAML, Requirements, and downstream artifacts, classifying changes (e.g., Visual, Data, Behavior).
-   **Reconciliation:** A human reviews the impact report and approves the propagation of changes. Purely visual changes can be fast-tracked. Semantic changes create new versions of requirements or specs, preserving the old ones for history.

## 10. Refinement Lifecycle

This new engine is central to managing change:

    Mockup vN+1
        |
        v
    `mxagile refine` -> Change Detection (semantic diff)
        |
        v
    Change Classification (visual, data, behavior, etc.)
        |
        v
    Impact Report (shows affected Page YAML, Reqs, Specs, Tasks)
        |
        v
    Reconciliation Gate (Human review and approval)
        |
        v
    Downstream artifacts are versioned or updated safely.

This process prevents mockup changes from silently overwriting accepted business requirements.

## 11. Living Specification Model

Feature Specs are the central, "living" contract for a feature. They are stored in `specs/`.

-   A Feature Spec groups multiple requirements (`REQ-*`) into a coherent whole.
-   It describes WHAT the system must do and WHY, but not HOW (which is the Plan's job).
-   When an underlying requirement is updated (via the Refinement Engine or manual edit), the Feature Spec is marked as `stale`.
-   The `mxagile reconcile` command guides a user through updating the Feature Spec to incorporate the requirement changes.
-   This, in turn, marks the `Plan` and `Tasks` as stale, which can then be regenerated from the updated spec.
-   Implementation discoveries can also flow back up. An agent can propose a spec adjustment, which is reviewed and reconciled, ensuring the spec always reflects the current, agreed-upon understanding.

## 12. Quality Gates

-   **Discovery Gate:** Checks consistency and completeness of Mockup, Page YAML, and Requirements.
-   **Specification Quality Gate:** Uses a checklist to ensure a Feature Spec is unambiguous, testable, and complete.
-   **Plan Completeness Gate:** Verifies that the Mendix-native plan covers all aspects of the spec.
-   **Task Readiness Gate:** Ensures tasks are actionable, traceable, and have clear dependencies.
-   **Mendix Validation Gate:** The existing robust process: `mxcli check`, `lint`, Docker build, UI tests, and acceptance tests.
-   **Convergence Gate:** The final check that all accepted requirements in a spec have been implemented, tested, and validated.

## 13. Mendix Boundary

The framework maintains a strict boundary:
-   **MxAgile Lifecycle (WHAT/WHY):** Manages the specification, planning, and validation lifecycle. It produces prepared, Mendix-native tasks.
-   **mxcli & Mendix Skills (HOW):** The implementation agent uses `mxcli` and specialized Mendix skills to execute the prepared tasks. The "how" of creating a microflow or page is delegated to the Mendix engineering layer, not defined within the spec.

## 14. Validation Strategy

The existing multi-layer validation strategy is formalized:
1.  **Artifact Consistency:** `mxagile analyze` checks for drift and broken links.
2.  **MDL Validation:** `mxcli check` and `mxcli lint` run before execution.
3.  **Build Validation:** `mxcli docker check` and the Docker build process verify model integrity.
4.  **Runtime Validation:** The container must start successfully.
5.  **UI Verification:** The UI-Agent compares the running app against mockup screenshots and Page YAML definitions.
6.  **Acceptance Validation:** The Acceptance-Agent runs Playwright tests derived from `test:` blocks in the task list.
7.  **Traceability Completeness:** `mxagile converge` ensures all requirements have corresponding validation evidence.

## 15. Greenfield Initialization (`mxagile init`)

The `init` script will:
1.  Be idempotent (safe to run multiple times).
2.  Ask the user if they want to use a company-specific layer.
3.  If yes, prompt for the layer name (e.g., `mercedes-benz`).
4.  Create the `.mxagile/` directory structure.
5.  Copy the generic framework files.
6.  If a layer was selected, copy and overlay the company-specific files (e.g., from `.mxagile/layers/mercedes-benz/`).
7.  Create the `constitution.md` file and other baseline project principles.

## 16. Brownfield Adoption (`mxagile adopt`)

For existing Mendix projects, the `adopt` command will:
1.  Run `mxagile init` to set up the framework files.
2.  Inventory the existing Mendix model using `mxcli`.
3.  Inventory existing `input-resources` (mockups, docs).
4.  Create baseline Page YAML, Requirement, and Spec artifacts.
5.  **Crucially, it will not fabricate history.** It will mark all inferred relationships and requirements with a status of `INFERRED_FROM_EXISTING_MODEL` and flag them for human review.
6.  Produce an adoption report showing the generated baseline and areas needing review.
7.  This allows the new lifecycle to be used for all *future* changes and new features.

## 17. Legacy Compatibility

Existing `dfc-ai` projects can be migrated using `mxagile adopt`. The process is designed to be incremental. A project can operate in a mixed "Hybrid" mode.

## 18. Migration Matrix

| OLD ARTIFACT / MECHANISM (`dfc-ai`) | NEW ARTIFACT / MECHANISM (`MxAgile`) | MIGRATION REQUIRED? | AUTOMATIC / MANUAL | BREAKING? |
|---|---|---|---|---|
| `.dfc-ai/` directory | `.mxagile/` directory | Yes | Automatic (`mv`) | Yes (Path) |
| File/content `dfc-ai` references | `MxAgile` references | Yes | Automatic (sed/replace) | Yes (String) |
| `.dfc-ai/modules/MB_*` | `.mxagile/layers/mercedes-benz/modules/` | Yes | Automatic (`mv`) | Yes (Path) |
| `planning/stories/*.md` | `requirements/*.md` + `specs/*.md` | Yes | Manual Logic | Yes (Concept) |
| `planning/checklists/*.yaml` | `planning/tasks/TASK-*.yaml` | Yes | Automatic (Script) | Yes (Structure) |
| `planning/ui-inventory/*.yaml` | `planning/ui-inventory/*.yml` (as Page YAML) | Yes | Automatic (Script) | No |
| `orchestrator.md` | `orchestrator.md` (updated) | Yes | Manual | No |

## 19. Incremental Migration

Projects can operate in three modes:
-   **Legacy:** No changes; the old workflow continues (not recommended).
-   **Hybrid:** Use `mxagile adopt` to baseline the project. Existing features are untouched. All *new* features must follow the full new MxAgile lifecycle.
-   **Native:** The entire project is managed under the new MxAgile lifecycle.

## 20. Breaking Changes

-   **Project Name:** All `dfc-ai` file paths, directory paths, and content strings are replaced with `MxAgile`. Scripts relying on the old name will fail.
-   **Company-Specific Content:** Previously integrated Mercedes-Benz content is moved to an optional layer. Projects using it must be configured to include the `mercedes-benz` layer during `init` or `adopt`.
-   **Planning Artifacts:** `planning/stories` and `planning/checklists` are replaced by `requirements`, `specs`, and `planning/tasks`, which have a new structure and relationship.

## 21. Rollback Considerations

Rollback is possible by reverting the initial refactoring commit that renames `dfc-ai` to `MxAgile` and creates the new directory structure. Since `mxagile adopt` does not destroy existing artifacts, a project can safely revert to the pre-adoption state.

## 22. Agent Migration Notes

Old agent prompts that directly reference `dfc-ai` paths or artifacts will need to be updated. The core `orchestrator.md` will guide them to the new artifact locations (`specs/`, `requirements/`, etc.). The agent-adapter architecture is preserved, so the core logic change is minimal.

## 23. Directory Changes

-   `.dfc-ai/` -> `.mxagile/`
-   `.dfc-ai/modules/` -> `.mxagile/layers/<company>/modules/`
-   `planning/stories/` -> `requirements/`
-   (new) `specs/`
-   `planning/checklists/` -> `planning/tasks/`

## 24. Command Changes

-   (new) `mxagile init`
-   (new) `mxagile adopt`
-   (new) `mxagile refine`
-   (new) `mxagile clarify`
-   (new) `mxagile plan`
-   (new) `mxagile tasks`
-   (new) `mxagile analyze`
-   (new) `mxagile converge`
-   (new) `mxagile trace`

These commands will be implemented as scripts (e.g., PowerShell) that orchestrate agent skills.

## 25. Migration Checklist

1.  [ ] Ensure the project is under version control and has no uncommitted changes.
2.  [ ] Run the global refactoring script to rename `dfc-ai` to `MxAgile`.
3.  [ ] Run `mxagile adopt`. This will:
    *   Initialize the `.mxagile` directory.
    *   Prompt you to select the `mercedes-benz` layer to preserve the old modules.
    *   Inventory the existing project and create baseline specs/requirements.
4.  [ ] Review the adoption report and the newly generated artifacts in `requirements/` and `specs/`. Manually verify and accept the inferred requirements.
5.  [ ] Move old `planning/stories` and `planning/checklists` to an `_archive` directory.
6.  [ ] Update any custom scripts or agent prompts that had hardcoded `dfc-ai` paths.
7.  [ ] For the next new feature, use the full `mxagile` lifecycle, starting with Discovery.
