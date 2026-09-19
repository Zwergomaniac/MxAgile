# MxAgile - TODO

## Epic: Core Workflow Testing

- [x] **Test Company Layer Workflow (`mxagile-add-layer.ps1`)**
  - [x] Create a separate Git repository for a test layer.
  - [x] Use `mxagile-add-layer.ps1` to clone it into the test project.
  - [x] Verify agent's OVERRIDE logic (Project > Layer).
  - [x] Verify agent's MERGE logic and MULTI-LAYER precedence.
  - [x] Test Layer Manifest Generation.
- [x] **Test Wave Planning (`mxagile-plan-wave.ps1`)**
  - [x] Implement as an agentic orchestrator, not an MDL generator.
- [x] **Test Greenfield Initialization (`mxagile-init.ps1`)**
  - [x] Run the script in a clean directory and verify structure.
- [x] **Test Framework Installation (`install-mxagile.ps1`)**
  - [x] Run the install script and verify files are copied.

## Epic: Lifecycle Feature Implementation (from `majorchange.md`)

- [x] **Implement Refinement Engine (`mxagile-refine.ps1`)**
  - [x] Implement hash-based change detection.
  - [ ] Implement semantic diffing for mockups/Page YAML.
  - [ ] Implement impact analysis and report generation.
- [x] **Implement Living Spec Scripts**
  - [x] `mxagile-clarify.ps1`: Implement the structured Q&A workflow.
  - [x] `mxagile-tasks.ps1`: Implement the decomposition of a plan into tasks.
  - [x] `mxagile-reconcile.ps1`: Implement the agent-based process of updating a stale spec.
- [x] **Implement Brownfield Adoption (`mxagile-adopt.ps1`)**
  - [x] Replace scripted approach with an agent-based skill.
- [ ] **Implement Analysis & Verification Scripts**
  - [ ] `mxagile-analyze.ps1`: Implement checks for broken traceability links, orphan artifacts, etc.
  - [ ] `mxagile-converge.ps1` (New Script): Implement the check that all requirements have validation evidence.
- [ ] **Implement Traceability Query (`mxagile-trace.ps1`)**
  - [ ] Create a script that takes an ID and reports the full chain of related artifacts.

## Epic: Quality Gates

- [ ] **Implement Specification Quality Gate**
  - [ ] Create a script or agent skill to check a `.spec` file against a quality checklist.

## Epic: Unify Artifacts with YAML

- [ ] **Convert All Artifacts to YAML:**
  - [ ] Convert `.spec`, `.req`, `.wave` to `.yml` format.
  - [ ] Convert `glossary.md` and `platform-modules.md` to `.yml`.
- [ ] **Rewrite Indexer in Python:**
  - [ ] Replace `mxagile-build-trace-index.ps1` with a Python script that reads all `.yml` artifacts.
- [ ] **Update All Scripts and Skills:**
  - [ ] Update all scripts and agent skills that create or read artifacts to use the new `.yml` format.
