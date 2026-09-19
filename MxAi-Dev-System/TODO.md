# MxAgile - TODO

## Epic: Core Workflow Testing

- [x] **Test Company Layer Workflow (`mxagile-add-layer.ps1`)**
- [x] **Test Wave Planning (`mxagile-plan-wave.ps1`)**
- [x] **Test Greenfield Initialization (`mxagile-init.ps1`)**
- [x] **Test Framework Installation (`install-mxagile.ps1`)**

## Epic: Lifecycle Feature Implementation (from `majorchange.md`)

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

## Epic: Quality Gates

- [x] **Implement Specification Quality Gate**
  - [x] Create a script or agent skill to check a `.spec` file against a quality checklist.

## Epic: Unify Artifacts with YAML

- [ ] **Convert All Artifacts to YAML:**
  - [ ] Convert `.spec`, `.req`, `.wave` to `.yml` format.
  - [ ] Convert `glossary.md` and `platform-modules.md` to `.yml`.
- [x] **Rewrite Indexer in Python:**
  - [x] Replace `mxagile-build-trace-index.ps1` with a Python script that reads all artifact types.
- [ ] **Update All Scripts and Skills:**
  - [ ] Update all scripts and agent skills that create or read artifacts to use the new `.yml` format.
