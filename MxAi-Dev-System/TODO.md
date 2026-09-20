# MxAgile Operational Plan

## Current Phase
Stabilization, Integration, and Pilot Validation

## Current Work Package
WP-6: Trace Node and Edge Semantics

---

## In Progress
- [x] **WP-6**: Review and document the canonical schema for core artifact types.
- [ ] **WP-6**: Enhance `build_artifact_index.py` to extract more relationship types from other artifact fields (e.g., `dependencies`, Mendix artifact references).
- [ ] **WP-2**: Investigate and fix spurious test warnings/failures.

## Next
- [ ] **WP-15**: Implement initial version of the Global `Analyze` script.
  - [ ] Detect duplicate IDs.
  - [ ] Detect broken references (edges pointing to non-existent nodes).

## Recently Completed
- [x] **WP-6**: Defined and validated schemas for Page, Requirement, Spec, and Task.
- [x] **WP-2**: Established a single, reliable test entry point (`run-all-tests.ps1`).
- [x] **WP-5**: Artifact Trace Index Consolidation.
- [x] **WP-0**: Workspace Reconciliation and Planning.

## Blocked / Decisions Required
- None

## Validation Status
- **Artifact Trace Index:** Validated (Happy Path & Schema Definition).
- **Test Harness:** In Progress. The main test runner is now reliable. Two scripts (`generate-mxagile-platform-skills.ps1`, `run-docker-isolated.ps1`) are failing the smoke test and require investigation.

