# MxAgile - TODO

## Epic: Core Workflow & Artifact Migration (Completed)

- [x] **Test Company Layer Workflow (`mxagile-add-layer.ps1`)**
- [x] **Test Wave Planning (`mxagile-plan-wave.ps1`)**
- [x] **Test Greenfield Initialization (`mxagile-init.ps1`)**
- [x] **Test Framework Installation (`install-mxagile.ps1`)**
- [x] **Implement Refinement Engine (`mxagile-refine.ps1`)**
  - [x] Implement hash-based change detection.
  - [x] Implement Python-based semantic diffing (initial version).
  - [x] Implement impact analysis and report generation.
- [x] **Implement Living Spec Scripts**
- [x] **Implement Brownfield Adoption (`mxagile-adopt.ps1`)**
- [x] **Implement Analysis & Verification Scripts**
  - [x] `mxagile-analyze.ps1`: Implement orphan/unused check in Python.
  - [x] `mxagile-converge.ps1` (New Script): Implement the check that all requirements have validation evidence.
- [x] **Implement Traceability Query (`mxagile-trace.ps1`)**
  - [x] Create Python script and wrapper to trace parent/child relationships.
- [x] **Implement Specification Quality Gate**
  - [x] Create a script or agent skill to check a `.spec` file against a quality checklist.
- [x] **Unify Artifacts with YAML:**
  - [x] Convert `.spec`, `.req`, `.wave` to `.yml` format.
  - [x] Convert `glossary.md` and `platform-modules.md` to `.yml`.
- [x] **Rewrite Indexer in Python:**
  - [x] Replace `mxagile-build-trace-index.ps1` with a Python script that reads all artifact types.
- [x] **Update All Scripts and Skills:**
  - [x] Update all scripts and agent skills that create or read artifacts to use the new `.yml` format.

## Epic: Formalize Core Workflows (NEW)

*This epic ensures that the existing scripts fully implement the vision from `majorchange.md`.* 

- [x] **Formalize Refinement Engine (`mxagile-refine.ps1`):**
  - [x] Implement semantic diffing to distinguish visual vs. behavioral changes (see Section 10 & 14 of `majorchange.md`).
- [x] **Implement Traceability Query (`mxagile-trace.ps1`):**
  - [x] Implement the query logic to trace an ID through the `trace-index.json` (see Section 7).
- [ ] **Implement Convergence Loop (`mxagile-converge.ps1`):**
  - [ ] Enhance the script to perform the full convergence check and generate remaining tasks if gaps are found (see Section 25).
- [ ] **Expand Global Analysis (`mxagile-analyze.ps1`):**
  - [ ] Expand the script to check for consistency across the full artifact chain as described in `majorchange.md`.

## Epic: Framework Hardening & Testing (NEW)

*This epic covers the need for robust testing of the framework itself.* 

- [ ] **Create Framework Test Suite:**
  - [ ] Add tests for `mxagile init` (clean project, repeated init).
  - [ ] Add tests for `mxagile adopt` (legacy brownfield project).
  - [ ] Add tests for `mxagile refine` (visual vs. semantic mockup changes).

## Epic: Documentation & Finalization (NEW)

*This epic covers the final steps to make the project complete and usable.* 

- [ ] **Update `majorchange.md` to Reflect Final State:**
  - [ ] Mark the YAML migration as complete.
  - [ ] Align the document with the implemented reality.
- [ ] **Create Project Constitution (`constitution.md`):**
  - [ ] Create the file with key project principles as a starting point for new projects.
- [ ] **Create User Documentation:**
  - [ ] Update READMEs and create simple guides for the main workflows (Greenfield, Brownfield, Refinement).
