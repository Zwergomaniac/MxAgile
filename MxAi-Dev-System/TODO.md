# MxAgile Development Plan

# Architectural Decisions
- **Lifecycle:** Hybrid approach (maintaining old + new paths), prioritizing migration to new structure (`requirements/`, `specs/`, `planning/tasks/`). Migration guidance via `mxagile-migration.md`.
- **Layers:** Clear separation: `company-layers/` (Local Registry/Database) vs `.mxagile/layers/` (Framework Active).
- **Brownfield Adoption:** Skeleton-injection method (injecting MxAgile into existing projects without destroying logic).
- **Security:** Manual management of secrets via `.env.mendix`.

## Phase 1: Safety, Executability & Foundational Härtung (COMPLETED)
- [x] Workspace forensic analysis and file system inventory.
- [x] Naming drift validation (.MxAgile vs .mxagile).
- [x] Parser-check of critical PowerShell scripts.
- [x] Grilling session and architectural decision formalization.
- [x] Fix path error in `scripts/mxagile-reconcile.ps1`.
- [x] Secure `env.mendix.example` (remove hardcoded passwords).
- [x] Establish `tests/smoke-test.ps1` for core script validation.

## Phase 2: Framework Test Harness (CURRENT FOCUS)
- [ ] Implement `init` idempotency tests (verify repeated runs don't corrupt workspace).
- [ ] Implement skeleton adoption test (verify `scripts/mxagile-adopt.ps1` safely injects structure).
- [ ] Create basic fixture library for testing migration logic.

## Phase 3: Lifecycle Convergence & Migration
- [ ] Refine `mxagile-migration.md` skill to handle specific edge cases in story conversion.
- [ ] Implement automatic conversion script for `planning/stories` -> `requirements/`.
- [ ] Implement automatic conversion script for `planning/checklists` -> `planning/tasks/`.
- [ ] Finalize documentation of layer separation and management workflows.

## Phase 4: Refinement Engine & Semantic Traceability
- [ ] Develop baseline detection for HTML mockups.
- [ ] Implement hash/change detection for Page YAML vs. Mockup state.
- [ ] Build artifact graph linking: Mockup -> Page YAML -> Requirement -> Feature Spec -> Plan -> Task -> Mendix Artifact.
- [ ] Implement "impacted artifact" resolution (stale propagation).

## Phase 5: Agentic Convergence & Validation
- [ ] Implement robust convergence check (`converge.py` improvement: validation of implementation status).
- [ ] Implement automated Mendix quality/security gates for CI.
- [ ] Finalize agent adapters for remaining experimental platforms (OpenCode/Hermes).
- [ ] Run full project quality assessment using best practices report.

---
### Guidelines for Contributors
- Always check the latest `TODO.md` before starting a task.
- Follow the architectural decisions formalized in the grilling session.
- Keep the `mxagile-migration.md` skill up-to-date with new migration patterns.
- If you encounter ambiguities or undocumented behaviors, do not silently resolve them. Grill the technical owner/developer for clarification.
