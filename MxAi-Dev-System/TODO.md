# MxAgile - TODO

## Epic: Core Workflow Testing

- [x] **Test Company Layer Workflow (`mxagile-add-layer.ps1`):**
  - [x] Create a separate Git repository for a test layer.
  - [x] Use `mxagile-add-layer.ps1` to clone it into the test project.
  - [x] Verify agent's OVERRIDE logic (Project > Layer).
  - [x] Verify agent's MERGE logic and MULTI-LAYER precedence (e.g., for `platform-modules.md`).
- [x] **Test Layer Manifest Generation**
- [ ] **Test Wave Planning (`mxagile-plan-wave.ps1`):**
  - [ ] Create a `.wave` file with multiple specs.
  - [ ] Run `mxagile-plan-wave.ps1`.
  - [ ] Verify the output is a single, valid MDL file containing all entities/associations.
- [ ] **Test Greenfield Initialization (`mxagile-init.ps1`):**
  - [ ] Run the script in a clean directory.
  - [ ] Verify the directory structure is created correctly.
  - [ ] Verify the prompt for company layers works.
- [ ] **Test Framework Installation (`install-mxagile.ps1`):**
  - [ ] Create a new dummy project.
  - [ ] Run the install script pointing to the `MxAgile` GitHub repo.
  - [ ] Verify the framework files are correctly installed.

## Epic: Lifecycle Feature Implementation (from `majorchange.md`)

- [ ] **Implement Refinement Engine (`mxagile-refine.ps1`):**
  - [ ] Define logic for change detection (e.g., file hash comparison).
  - [ ] Implement semantic diffing for mockups/Page YAML.
  - [ ] Implement impact analysis and report generation.
- [ ] **Implement Living Spec Scripts:**
  - [ ] `mxagile-clarify.ps1`: Implement the structured Q&A workflow.
  - [ ] `mxagile-tasks.ps1`: Implement the decomposition of a plan into tasks.
  - [ ] `mxagile-reconcile.ps1` (New Script): Implement the process of updating a stale spec.
- [ ] **Implement Brownfield Adoption (`mxagile-adopt.ps1`):**
  - [ ] Add logic to inventory a Mendix model via `mxcli`.
  - [ ] Implement the generation of baseline `spec` and `req` files from the model.
  - [ ] Add the `INFERRED_FROM_EXISTING_MODEL` status flag.
- [ ] **Implement Analysis & Verification Scripts:**
  - [ ] `mxagile-analyze.ps1`: Implement checks for broken traceability links, orphan artifacts, etc.
  - [ ] `mxagile-converge.ps1` (New Script): Implement the check that all requirements have validation evidence.
- [ ] **Implement Traceability Query (`mxagile-trace.ps1`):**
  - [ ] Create a script that takes an ID (`REQ-001`, `SP-002`, etc.).
  - [ ] Implement logic to search the `trace-index.json` and report the full chain of related artifacts.

## Epic: Quality Gates

- [ ] **Implement Specification Quality Gate:**
  - [ ] Create a script or agent skill to check a `.spec` file against a quality checklist (e.g., is it testable, unambiguous?).
