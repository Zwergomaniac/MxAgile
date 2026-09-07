# CE0066 Automation TODO

Last update: 2026-08-21
Owner: AI + Developer

## Mission
Automate handling of Mendix error CE0066 as far as technically possible, while protecting the canonical Original MPR-v2 state.

## Non-negotiable safety rules
- Never run `docker check` on the canonical Original project.
- Run destructive or materializing checks only on disposable copies.
- No git write operations in this project workflow.
- Keep all temporary artifacts under `.concord/`.

## Desired end state
- CE0066 can be reproduced in a controlled way.
- Verification is automated and repeatable.
- If full auto-fix is not possible, a minimal manual gate is clearly documented.
- Evidence output is generated after every attempt.

## What has already been falsified
1. Running `mxcli docker check` on Original is safe.
- Result: falsified.
- Observed: MPR-v2 materialization risk (Original can jump from small MPR-v2 state to large monolithic MPR state).

2. `mxcli --mcp ... -c "SHOW MODULES"` is a reliable generic read path on this backend.
- Result: falsified for this setup.
- Observed: backend capability limitation (`ListUnits not supported by the MCP backend`).

3. Concord tools with dotted names (`concord.discover`, `concord.invoke`) always work in VS Code as-is.
- Result: falsified in one session/client combination.
- Observed: tool-name validation may reject dots depending on MCP client handling.

4. Full automatic `Update security` capability is currently exposed by Concord in this environment.
- Result: not confirmed / effectively falsified for now.
- Observed: discover results expose checks and model operations, but no explicit `update security` action.

## What is currently working
- Concord MCP is reachable and callable via `concord_discover` / `concord_invoke`.
- `mx.check-model` and `mx.check-model-strict` return results.
- Project diagnostics and done-evidence flows run successfully.
- Read-only CE0066 verification flow is operational.

## Current conclusion on Update security
- A fully automated Update security step is not available in current exposed capabilities.
- Practical path today:
  1. Developer runs `Update security` in Studio Pro for affected domain model(s).
  2. Save changes.
  3. AI runs read-only verification (`mx.check-model`, `mx.check-model-strict`, evidence capture).

## Next experiments (safe order)
1. Capability re-check after extension/runtime updates.
2. Try direct mendix-studio-pro MCP document-level operations that may affect security metadata, if exposed.
3. Keep CE0066 reproduction strictly split:
- Original: minimal write only when explicitly approved.
- Disposable copy: materializing checks and heavy validation.
4. Add an automated evidence bundle per run under `.concord/scratch/`.

## Dependency-first remediation hypothesis
Idea: CE0066 may disappear if we resolve all security dependencies explicitly instead of relying on a broad Studio Pro refresh.

### Working hypothesis
- CE0066 can be triggered by stale or incomplete links between:
  - Entities and their access rules
  - Module roles and user roles
  - Associations/generalizations and effective rights
- If these links are made explicit and consistent, CE0066 may no longer appear.

### Experiment path
1. Snapshot baseline evidence (check + strict check + logs).
2. Build a dependency map for one affected entity:
- access rules (read/write/create/delete scope)
- related associations and generalization chain
- module-role and user-role bindings
3. Apply only minimal targeted fixes (one dependency class at a time).
4. Re-run checks after each small fix.
5. Mark each dependency class as:
- confirmed contributor
- no-effect (falsified)

### Falsification criteria
- If CE0066 still appears after all mapped dependencies are explicitly consistent, this hypothesis is falsified.
- If CE0066 disappears only after Studio Pro `Update security`, then a hidden metadata refresh step is still required in current tooling.

### Current tooling note
- Current Concord capabilities in this environment expose strong check/read flows, but no explicit `update security` capability yet.

## Open questions
- Will a newer Concord runtime expose explicit `update security` or equivalent remediation API?
- Can Studio Pro MCP expose a safe security metadata refresh operation for domain models?

## Decision log
- 2026-08-21: Keep the CE0066 automation topic active; do not drop it.
- 2026-08-21: Treat manual Studio Pro `Update security` as the current required gate.
