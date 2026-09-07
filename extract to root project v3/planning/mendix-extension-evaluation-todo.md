# Mendix Extension Evaluation TODO

Last update: 2026-08-21
Owner: AI + Developer

## Mission
Assess how much the Mendix VS Code extension can improve day-to-day development speed, quality, and safety in this project.

## Scope
- Read-only model exploration and diagnostics
- Safe validation workflows
- Controlled write workflows (only where approved)
- Practical fit with current Concord and Studio Pro MCP setup

## Success criteria
- We have a clear list of high-value tasks where the extension is faster or safer.
- We have a clear list of tasks where the extension is not sufficient.
- We define a recommended default route per task type.

## Test matrix
1. Discovery and navigation
- List modules, entities, pages, microflows.
- Read one entity and one microflow end-to-end.
- Check if output is complete and reliable.

2. Diagnostics and checks
- Run model checks (normal + strict).
- Capture diagnostics in a repeatable evidence format.
- Verify if CE0066-relevant indicators can be detected early.

3. Security-related analysis
- Inspect how far security dependencies can be analyzed:
- entity access rules
- role mappings
- association/generalization impact
- Document missing visibility areas.

4. Write support (only in disposable or explicitly approved flow)
- Try a minimal model write and read-back.
- Verify rollback/recovery path.
- Confirm no accidental impact on canonical Original MPR-v2.

5. Productivity comparison
- Compare 3 representative tasks against current baseline:
- Concord-only path
- Studio-Pro-MCP path
- Hybrid path
- Record duration, friction, and failure modes.

## Output artifacts
- One short result summary under planning/
- One recommended workflow table (task -> preferred tool path)
- One risk list with mitigations

## Constraints
- Never run docker check on canonical Original.
- Keep destructive experiments on disposable copies only.
- No git write operations in this project workflow.

## Initial hypotheses
- H1: The extension significantly improves read-only exploration and diagnostics.
- H2: Security metadata repair is still partially dependent on Studio Pro UI steps.
- H3: A hybrid route (extension + Concord + strict checks) yields best reliability.

## Decision checkpoints
- Checkpoint A: After read-only matrix (go/no-go for deeper write tests).
- Checkpoint B: After first controlled write test.
- Checkpoint C: Final recommendation for team default workflow.
