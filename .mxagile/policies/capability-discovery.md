# Policy: MxAgile Capability Discovery

**MxAgile 1.5**

Do not rely on model memory to determine which Framework capabilities are available.
Use the authoritative resolver instead.

## Resolver

In an installed project the resolver is `.mxagile/tools/Get-MxAgileCapabilities.ps1` (framework-owned,
re-distributed on every install/update; in the framework repository itself: `scripts/`).

**Lazy use only.** Never run it at startup or per turn. Query only the capability that is relevant to the
current task (`-Capability <id>`), not the whole registry:

```powershell
pwsh .mxagile/tools/Get-MxAgileCapabilities.ps1 -Capability <id> -Format json
```

| Task shape | Capability id |
|------------|---------------|
| Large raw data / context-intensive analysis worth externalizing | `context_mode_integration` |
| CLI-output-heavy work | `rtk_optimization` |
| Survive a new session / long mission | `checkpoint_resume` |

Small or normal tasks: no check. Unavailable, unhealthy, timed-out or unknown: use the normal MxAgile path.
The resolver never starts `context-mode` and never waits on a server.

Without `-Capability` the command returns the full inventory as structured JSON.
It answers questions such as:

- "Can MxAgile optimize command output?" → check `rtk_optimization.state.active`
- "Can I use Context Mode here?" → check `context_mode_integration.state.active` AND `integration.usable`
  (`available` only means a runtime exists; it does not mean the integration works in this session)
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

## Context Mode Integration Evidence

`context_mode_integration` carries an `integration` object (harness, mode, configured, loaded,
loaded_tools, health, required_tools, usable, status, guidance, fallback). For a relevant large-data
task, use this order once:

- Query the resolver first. In Copilot/Concord contexts, `concord_discover` is not the MxAgile
  resolver and must not replace or precede the relevant capability query.
- Inspect the current harness's actual registered tool inventory. Do not infer LOADED from packages,
  config files, plugin cache, generic ToolSearch alone, Concord discovery, or another session.
- Pass `-ContextModeToolsObserved` and the canonical `ctx_*` names from this session. If the inventory
  was inspected and contains none, pass the switch with no tool names; if it was not inspectable, omit it.
- If tools are loaded, run at most one bounded `ctx_doctor` probe in this same session; it must
  report the configured runtime/hooks healthy. Rerun the resolver with the observed tool list, task-required operation(s), and
  `-ContextModeHealth healthy|failed|timeout`. Never reuse health from an earlier session.
- Pass the operation(s) required by this task via `-ContextModeRequiredTools`; `integration.usable`
  requires supported + installed + configured + loaded + healthy + MxAgile enabled + every required
  operation present. A healthy adapter without task-operation evidence is not usable for that task.
- A configured-but-not-loaded result gets the adapter's single restart/reload hint. A health failure
  gets one diagnostic path only; no retry loop.
- Not installed / not configured / misconfigured / unhealthy / unknown or unsupported harness:
  continue with the normal MxAgile fallback (deterministic helpers, bounded semantic delegation,
  targeted direct read; never a full-repository read) and, if useful, state the harness-specific
  `integration.guidance` compactly.
- Never install, enable or edit harness configuration (e.g. `opencode.json`) on the agent's own authority.
- For a large source such as HTML, do not use a direct full read as fallback; if the required Context Mode
  operation is unavailable, report `NOT_VERIFIABLE_FOR_CM_TEST` and leave the large source unread.
- Context Mode never owns lifecycle state, gates, evidence validity or mission completion.

Compact answer from the resolver output alone (no adapter files need to be read):

> Context Mode is optional and currently not usable (`integration.status`, `integration.reason`).
> The normal MxAgile fallback stays available.
> Setup path for your harness: `integration.guidance` (project/global/verify lines).

`integration.harness` comes from `-Harness` (`claude_code`, `copilot_cli`, `vscode_copilot`, `opencode`)
or is detected from the environment; if it is `unknown`, say so instead of guessing.

Details: `.mxagile/integrations/context-mode.yaml#harness_integration`.

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
