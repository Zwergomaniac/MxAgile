# Policy: MxAgile Capability Discovery

**MxAgile 1.5**

Do not rely on model memory to determine which Framework capabilities are available.
Use the authoritative resolver instead.

## Resolver

```powershell
scripts/Get-MxAgileCapabilities.ps1 -Format json
```

Run this command to get the current capability inventory as structured JSON.
It answers questions such as:

- "Can MxAgile optimize command output?" → check `rtk_optimization.state.active`
- "Can I use Context Mode here?" → check `context_mode_integration.state.available`
- "Which context features are currently active?" → filter `state.active == true`
- "Why is automatic rollover unavailable?" → read `auto_rollover.state.reason`
- "What optional features would help this mission?" → filter `agent_may_recommend == true AND state.active == false`
- "What changed since the last Framework version?" → run with `-CheckUpgrades`

Human-readable output:
```powershell
scripts/Get-MxAgileCapabilities.ps1
```

## Capability State Model

| State | Meaning |
|-------|---------|
| `supported` | Framework version supports this capability |
| `available` | Environment/dependencies detected |
| `enabled` | Project config allows use |
| `active` | Actually in use right now |
| `degraded` | Partial operation or fallback |
| `unavailable` | Dependencies absent or incompatible |

## Recommendation Policy

An agent MAY proactively surface an optional capability when:
- It is relevant to the current task
- `supported` and `available` are both true
- `active` is false
- Expected benefit is meaningful
- The recommendation was not just dismissed

An agent MUST NOT:
- Recommend every capability on every startup
- Block work because an optional optimization is disabled
- Activate external-install capabilities (`user_approval_required: true`) without explicit user authorization
- Treat an `ENABLED` capability as `ACTIVE` when its dependencies are absent

## Safe Activation Rules

For project-config-only changes (`user_approval_required: false`):
An agent may edit `.mxagile/config.yaml` when clearly authorized by the user's request.

For external installation (`user_approval_required: true`):
Do not silently install. Report what is needed and wait for user confirmation.

Never set `enabled: true` when dependencies are absent — this creates a misleading config state.

## Documentation

- Capability catalog: `docs/capabilities.md`
- Context optimization (RTK, Context Mode): `docs/context-optimization.md`
- Registry source: `.mxagile/capabilities.yaml`
- Context lifecycle: `docs/context-lifecycle.md`
