# MxAgile Development Plan

## Architectural Decisions
- **Lifecycle:** Hybrid approach (maintaining old + new paths), prioritizing migration to new structure (`requirements/`, `specs/`, `planning/tasks/`). Migration guidance via `mxagile-migration.md`.
- **Layers:** Clear separation: `company-layers/` (Local Registry/Database) vs `.mxagile/layers/` (Framework Active).
- **Brownfield Adoption:** Skeleton-injection method (injecting MxAgile into existing projects without destroying logic).
- **Security:** Manual management of secrets via `.env.mendix`.

## Completed Phases
### Phase 1: Safety, Executability & Foundational Härtung
- [x] Workspace forensic analysis, file system inventory, naming drift validation.
- [x] Parser-check of PowerShell scripts and security hardening (env.mendix.example).
- [x] Grilling session and architectural decision formalization.
- [x] Fix path error in `scripts/mxagile-reconcile.ps1`.
- [x] Establish `tests/smoke-test.ps1` for core script validation.

### Phase 2: Framework Test Harness
- [x] Implement `init` idempotency tests.
- [x] Implement skeleton adoption test (`scripts/mxagile-adopt.ps1` with logic fix).
- [x] Create basic fixture library for testing migration logic.

### Phase 3: Lifecycle Convergence & Migration
- [x] Create `mxagile-migration.md` skill.
- [x] Implement automatic conversion script (`planning/stories` -> `requirements/`).
- [x] Implement automatic conversion script (`planning/checklists` -> `planning/tasks/`).
- [x] Document layer separation and management workflows.

### Phase 4: Refinement Engine & Semantic Traceability
- [x] Develop baseline detection for HTML mockups.
- [x] Implement hierarchical hashing (artifact hashing utility).
- [x] Build artifact graph and schema (`artifact-graph.json`).
- [x] Implement stale propagation logic (`propagate_stale.py`).

### Phase 5: Agentic Convergence & Validation
- [x] Implement robust convergence check (`converge.py` and `convergence-report.md`).

---

## Active & Future Phase
### Phase 6: Convergence Pilot & Maintenance
- [ ] Pilot Adoption: Apply `mxagile-adopt.ps1` to a non-production project.
- [ ] Pilot Validation: Run `converge.py` on the pilot project and review reports.
- [ ] Framework Optimization: Refine hashing/graph performance.
- [ ] Continuous Improvement: Refine `AGENT.md` instructions based on pilot feedback.

---
### Guidelines for Contributors
- Always check the latest `TODO.md` before starting a task.
- Follow the architectural decisions formalized in the grilling session.
- If you encounter ambiguities or undocumented behaviors, do not silently resolve them. Grill the technical owner/developer for clarification.
- Keep the `mxagile-migration.md` skill up-to-date with new migration patterns.
