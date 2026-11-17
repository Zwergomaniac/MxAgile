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

## Named Child Availability

For a specific Claude child, query `subagent_spawn` with `-AgentType <name>`. The
`integration.agent_availability` distinguishes generated_definition_present,
definition_name_valid, host_inventory_observed, host_registered, spawn_ready and execution_status.
Only pass `-AgentTypesObserved -AgentTypes <observed-name>` from actual current host inventory,
never by scanning files. With no observed inventory, registration/execution remain NOT_OBSERVABLE
and that named capability is not available for spawn. Generic adapter support is not registration.
Observed absence is AGENT_NOT_REGISTERED; invalid required frontmatter is AGENT_DEFINITION_INVALID.
Even observed registration is not proof of execution or actual_model.

Read-only diagnostic work must not silently fall back to unconstrained Explore/Plan or Main
execution when the User explicitly requested a child. Follow `agent-delegation.md` for bounded
registration diagnosis. Do not infer HOST_RELOAD_REQUIRED or prescribe repeated reloads from
file existence/absence alone. The standalone CLI and VS Code extension have separate runtime
versions; only live extension evidence describes the extension's inventory.

## Capability State Model

| State | Meaning |
|-------|---------|
| `supported` | Framework version supports this capability |
| `available` | Environment/dependencies detected |
| `enabled` | Project config allows use |
| `active` | Legacy config/dependency eligibility; not current operation execution |
| `degraded` | Partial operation or fallback |
| `unavailable` | Dependencies absent or incompatible |

## Mendix Operation Routing

The `studio_pro_mcp` and `concord_mcp` registry entries establish toolchain availability,
not support for a particular model operation. Before a Mendix tool call, classify the requested
operation and check the current session's registered tool descriptions and read/write semantics.
Do not probe with guessed document types or paths.

Classify at least: `page.read`, `page.write`, `microflow.read`, `microflow.write`,
`nanoflow.read`, `nanoflow.write`, `navigation.mutate`, `security.mutate`,
`domain_model.mutate`, `javascript_action.mutate`, `html_first_asset.write`,
`runtime.validate`, `model.validate`, and `model.sync`.

Choose a path only when its operation, target project, and required semantics are supported by
current-session evidence. Unknown support stays `UNKNOWN`; it is not inferred from tool presence
or another tool's support. If a tool structurally reports `unsupported`, `unknown document type`,
or `operation not supported`, record that tool/operation/document-type outcome in the current
run's routing notes and mark that operation path `UNSUPPORTED` for this run. Do not retry an
equivalent operation with guessed names. Select a verified alternative path or stop with
`NEEDS_ALTERNATIVE_TOOL` / `NEEDS_HUMAN`.

## Operation Evidence and Small Provider Selection Contract

MCP `enabled` reads the registry's **MCP config location**, not the Framework config YAML.
An enabled MCP entry is DECLARED only. It cannot establish `active`, project identity,
or current execution. Tools offered by another host can be DISCOVERED even when the
local VS Code declaration is absent: record that host's operation evidence separately;
do not rewrite project config to make a declaration match an observation.

For each needed capability/operation record independently:

| Dimension | Evidence |
|---|---|
| DECLARED | Package/config/status advertises the provider |
| DISCOVERED | Current tool inventory or explicitly loaded handler exposes this operation |
| CURRENTLY_AVAILABLE | Fresh same-run/same-generation discovery with correct target binding |
| EXECUTABLE | Bounded successful same-operation probe with source evidence |
| LAST_VERIFIED | Historical probe timestamp; never a freshness guarantee |
| PROVIDER / OPERATION | Exact provider, tool/handler and operation, not guessed naming families |

Browser operations include `browser.navigate`, `browser.snapshot`, `browser.click`,
`browser.screenshot` and runtime assertions; a successful navigation does not verify all others.
Use current handler descriptions, including Studio-Pro-MCP Playwright handlers, instead of
assuming names start with `browser_`. Concord availability alone is not browser support.

Evidence adds `current_run_id`, `session_generation`, `current_session_generation`,
`view_state: FRESH`, `bound_target` and `required_target` to the observation below.
Targets identify the **exact project/Studio Pro endpoint/runtime instance**, including the
resolved runtime URL and backend when relevant, not merely a localhost port. The caller
must obtain current fields from host/runtime evidence; the resolver validates supplied
facts and does not discover or attest a host. Missing context fails closed.
Freshness means no intervening relevant change since inspection; the timestamp alone is
insufficient. A reconnect, tool-inventory reload or host notice “available again” invalidates
prior Availability/Executability evidence: advance generation, explicitly rediscover/load
operations, recheck binding and make one bounded non-mutating probe. A host notice is not
itself a probe; never copy old generation fields into new current evidence.

For the single task capability, use `-OperationEvidenceFile` with `operation`, `providers`
(array of scoped observations plus `limitations`), an ordered `preferred_providers`,
`preference_reason`, and envelope `current_run_id`, `current_session_generation`,
`required_target`. Every eligible provider must match that same task context.
Record the task's preference rationale in the input evidence. The resolver returns
per-provider eligibility/rejection reasons, `selected_provider` and eligible
`fallback_providers`; no delivery plan or automatic installation is introduced.
Only a currently executable, correctly bound provider is eligible. If none is eligible,
return NEEDS_ALTERNATIVE_TOOL; fallback requires its own current evidence.

Browser/runtime default preference: a correctly bound Studio-Pro-MCP-Playwright route,
then configured project-local Playwright. Record why the first preserves the current IDE/
runtime binding or why the project's runner is necessary (fixtures, origins, assertions).
Concord is eligible only if this exact browser operation is actually exposed and executable;
it is otherwise rejected, not guessed. Explicit user preference may reorder **eligible**
providers, never bypass binding/freshness. Known limitations that prevent the task invalidate
that provider's operation evidence; report others without inventing global capability absence.

## Browser Declaration, Discovery and Execution

Registry/toolchain availability is not executable browser capability. For the
specific provider, operation and run, use an opt-in bounded observation:

```powershell
pwsh .mxagile/tools/Get-MxAgileCapabilities.ps1 -ProjectRoot . -Format json -BrowserEvidenceFile .concord/scratch/browser-observation.json
```

Input keys: `provider`, `host` (`UNKNOWN` when unobserved), `run_id`, `observed_at`,
`operation`, `declared_available`, `tools_observed`, `operation_discovered` and
`execution_status` (`NOT_OBSERVED`, `PASSED`, `FAILED`, `TIMEOUT`). Observed execution
also requires a non-empty `execution_reference` to its source evidence. Boolean keys are
real JSON booleans. Execution means a bounded successful same-provider/same-operation
probe in this run, not package presence, an availability status, or a historical
report. Bind the observation to its current source evidence and generation/target fields
from the operation contract above before routing. An old PASSED execution remains historical
LAST_VERIFIED only; missing current binding or invalidated generation never allows routing.

`DECLARED_AVAILABLE` means a declaration only; `DISCOVERED_AVAILABLE` means the
required operation is exposed; `EXECUTABLE_AVAILABLE` requires successful execution.
A positive declaration with observed missing operations, or failed/timed-out execution,
is `PARTIAL`; an inspected absent path without a positive declaration is
`UNAVAILABLE`. Missing observation remains `UNKNOWN`. Only
`browser.route_allowed: true` authorizes this operation's Runtime/Visual route.
A declared or discovered path may get one bounded execution probe, not a retry loop.

Do not infer global browser unavailability from Studio-Pro-MCP exposing no
`browser_*` handlers despite `playwright_status` declaring availability. An independently
verified local Node Playwright/Chromium path is a separate provider. Historical
local `@playwright/cli` Chromium build 1243 evidence belongs to that run; its agent
host remains UNKNOWN unless attested. Neither provider identity nor report date
proves the host, exact execution time or current availability. Evidence-only resolver
modes are read-only, bounded to 256 KiB, and never alter discovery state.

## Lightweight Dependency Health at SessionStart

This is a narrow exception to optional-capability discovery on demand: SessionStart and Doctor
read Context Mode installation metadata and cached release information, not the full environment
or network. Framework recovery still has priority. The canonical producer is installed
`dependency_health.py`; `Get-MxAgileCapabilities.ps1` exposes it as
`context_mode_integration.integration.dependency_health`. It uses the existing canonical
`capabilities.yaml` external-dependency record, not a second dependency catalog.

The small generic assessment contract records:
`installed`, `installed_version`, `executable`, `required_capabilities`,
`capabilities_discoverable`, `compatible`, `latest_known_version`, `update_available`,
`last_update_check`, `health_status`, plus `update_check_status`, `route_allowed`, `blocking`,
`severity`, `recovery_hint` and `automatic_action`. The producer also records `check_execution`,
`requirement_sources`, `version_source`, `versions_by_source`, `update_check_source`,
`update_check_decision`, a compact `summary` and structured `next_actions`.
After recovery/freshness and before offering project work, MUST show this summary, including
UNKNOWN/STALE and NOT_OBSERVABLE discovery/execution. An UPDATE_AVAILABLE signal stays visible
in the summary even when the primary health is CAPABILITY_DEGRADED; age alone never blocks Delivery.
`recover-session` exposes fresh cache-only health separately from historical Doctor evidence;
its READY, reconciliation and idempotent READY outputs must not drop the health report.
Null means not observed; never infer
executability from a PATH shim, package, enabled plugin or cached health. Live tool/probe
observations are passed for this invocation only and never persisted as cross-session truth.
A same-session successful `ctx_doctor` probe supplies adapter runtime evidence, NOT proof that
`ctx_execute` or another operation executes. Inspect each required tool's actual schema and use
one bounded non-mutating same-operation probe; pass successful operations via
`-ContextModeExecutableTools` / `--executed-tool`. These observations follow the existing
current-session/generation/target evidence contract; reconnect invalidates them. A missing
operation probe remains `executable: null`, `CAPABILITY_DEGRADED`, and cannot authorize routing.
A failed/timeout runtime probe is not executable. Installed version comes from package/plugin metadata, never a running-server attestation.
For a resolved Claude host with an enabled Context Mode plugin declaration, bind it to that
project's applicable registered plugin metadata; retain the global CLI's version as a separate
source, not a conflicting version of the same installation. Conflicts within the selected
source, or unresolved harness/source ambiguity, remain unknown. Claude declarations honor
home, project and local settings overrides; they do NOT prove hooks/tools are loaded.
At cold Claude startup an enabled plugin declaration can require checking `ctx_execute` even
when Core context optimization is off. Record this as `claude_plugin_declaration`, not as live
execution or permission to enable Core routing. A declaration-only route is conditional:
`required_contract_active: false` cannot globally block unrelated Delivery, even with incompatible
metadata; that route remains disallowed. Core-enabled or explicitly needed operations activate
the version contract and known incompatibility blocks. Explicit task-required operations remain
the operation-specific contract; a hook demanding `ctx_execute` requires that exact operation's proof. A verified operation can remain usable with unknown version, but compatibility is
not called PASS; a known incompatible required version contract always blocks that route.

Release metadata is cached per project/dependency in
`.mxagile/state/runs/dependency-update-cache.json`. Standard TTL: 24 hours, including failed
attempts. An exclusive lock and persisted attempt lease prevent duplicate concurrent checks.
SessionStart/Doctor never query the network or write this cache. After recovery/freshness,
a due installed/required dependency MUST receive one permitted bounded release check using
`python -B <absolute-root>/.mxagile/tools/dependency_health.py --project-root <absolute-root>
--check-updates`, then show the refreshed summary. If unavailable, network-forbidden, or denied
by an actual hook requiring an unloaded tool, report UNKNOWN/STALE/CAPABILITY_DEGRADED; do not
retry, bypass hooks or pretend up to date. No extra upgrade approval is needed for public metadata.
The Context Mode server's in-memory latest value is not a timestamped MxAgile cache; no latest
value or freshness may be invented from an old warning. An empty cache is explicitly DUE/NONE,
not TTL suppression. A fresh cache remains visible even when the check is TTL_SUPPRESSED.
The Core-bound hook authorizes only this
metadata/cache scope, not Delivery. HTTP release metadata has a 1.5-second socket timeout;
it is deferred out of the startup hook. No code, project inputs or credentials are sent.
`-ContextModeCheckUpdates` is the resolver's explicit equivalent. Unreachable release metadata
retains latest-known information as STALE, or UNKNOWN without prior data; `update_available`
is null, never a false "up to date". No package-manager/install/update command is executed.

| Observation | Health / consequence |
| --- | --- |
| Not installed and not required | INFO, no blocker |
| Current, executable, compatible and fresh release evidence | HEALTHY |
| Update available but executable and compatible | WARNING / UPDATE_AVAILABLE; no Delivery block |
| Required tool missing, not discoverable, failed or execution unknown | CAPABILITY_DEGRADED; `route_allowed: false`, unrelated permitted work continues |
| Known incompatible version of a required contract | INCOMPATIBLE with explicit approval/re-probe recovery; no automatic update |

For the observed 1.0.169 → 2.2.0 case, age alone is not incompatibility (the declared Context
Mode baseline is >=1.0.33). Update availability is transparent but never authorizes or forces
an upgrade. If a hook demands `ctx_execute`, establish exact current-host loading and bounded
executable health FIRST. A recommended but unavailable alternative is not a valid recovery.
Do not retry denied commands, change executors to evade a hook, or claim historical cache as
current tool inventory. Later true dependencies such as mxcli may reuse the assessment/cache
contract with their own bounded detectors; this is not a dependency manager.

## Context Mode Integration Evidence

`context_mode_integration` carries an `integration` object (harness, mode, configured, loaded,
loaded_tools, health, required_tools, usable, status, guidance, fallback). For a relevant large-data
task, use this order once:

- Determine the active host from the current agent runtime, not from its MCP/tool providers. Set
  `MXAGILE_HARNESS` only for this resolver process when the host is Copilot CLI or VS Code Copilot;
  Claude Code and OpenCode runtime markers are also detected directly. Do not persist this variable
  globally. `-Harness` must match current-session evidence; without it the result is
  `harness_ambiguous`. If no host identity is available, use `auto` and accept `harness_unknown`.
- Concord-MCP is a capability source, never the harness: Concord under Claude remains
  `claude_code`; Concord under Copilot remains the actual Copilot harness. Windows Terminal,
  Studio-Pro-integrated terminal, `COPILOT_HOME`, and VS Code terminal variables do not change it.
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
  operation present and successfully probed via `-ContextModeExecutableTools`. A healthy
  `ctx_doctor` without same-operation execution evidence is not usable for that task.
- Pass `-ContextModeHooksRequired` only when this task needs automatic routing interception. A task
  that explicitly uses loaded `ctx_*` operations may use MCP-only mode without hooks; if routing
  hooks are required, MCP-only is not sufficient and the adapter's plugin path is user-global.
- A configured-but-not-loaded result gets the adapter's single restart/reload hint. A health failure
  gets one diagnostic path only; no retry loop.
- Not installed / not configured / misconfigured / unhealthy / unknown or unsupported harness:
  continue with the normal MxAgile fallback (deterministic helpers, bounded semantic delegation,
  targeted direct read; never a full-repository read) and, if useful, state the harness-specific
  `integration.guidance` compactly.
- Never silently install global packages/plugins, change user-global harness configuration, or touch
  credentials. A reversible project-local setup edit is allowed only when the user's request
  authorizes that project setup and existing MxAgile autonomy rules permit the file mutation.
- Follow `integration.action_classification`: `SAFE_AUTOMATIC` for permitted local/read-only work,
  `REQUIRES_USER_APPROVAL` for user/machine mutations, `REQUIRES_RESTART` for one reported reload
  (no retry), and `UNSUPPORTED` with normal fallback.
- For a large source such as HTML, do not use a direct full read as fallback; if the required Context Mode
  operation is unavailable, report `NOT_VERIFIABLE_FOR_CM_TEST` and leave the large source unread.
- Context Mode never owns lifecycle state, gates, evidence validity or mission completion.

Compact answer from the resolver output alone (no adapter files need to be read):

> Context Mode is optional and currently not usable (`integration.status`, `integration.reason`).
> The normal MxAgile fallback stays available.
> Setup path for your harness: `integration.guidance` (project/global/verify lines).

`integration.harness` is attested by the current runtime. Never pass a guessed `-Harness`; caller
assertions without matching session evidence resolve to `harness_ambiguous`. `unknown` is not a
reason to ask the user to route manually; continue with fallback unless this is an explicit CM test.

When a user action is required, report compactly: what is missing, why MxAgile cannot do it
autonomously, the exact action, whether reload/restart follows, and that normal fallback continues.

Details: `.mxagile/integrations/context-mode.yaml#harness_integration`.

## Hook-Requested Tool Discovery and Loopback Checks

An upstream Context Mode hook is external tooling, not a MxAgile hook to silently patch.
Distinguish a bounded TCP/HTTP readiness probe to the configured literal loopback target
(`localhost`, `127.0.0.1`, `[::1]`) from external HTTP retrieval. A local Node invocation,
redirect to an external origin, proxy or dynamically computed host is not automatically a
loopback probe. No general HTTP exemption or hook bypass follows from this classification.

If a hook requests `ctx_execute` or another alternative absent from general discovery:
use the host's explicit ToolSearch/ToolDiscovery for the exact canonical name and
Context Mode provider; in Studio Pro, search handlers and retrieve their full schema
before execution. Record DISCOVERED/LOADED only after that inventory actually exposes the
tool. General discovery's omission is NOT an absence claim. The adapter's load/reload hint
is a single recovery path, not an automatic global installation.

If exact-name discovery/loading fails, report `HOOK_ALTERNATIVE_NOT_DISCOVERABLE`, the
required capability and attempted loader, with normal permitted fallback or BLOCKED.
Do not repeat a denied command, switch executors to evade interception, or send external
HTTP through a loopback exemption. Keep upstream routing behavior NOT_OBSERVABLE/PARTIAL
unless the exact hook version and response were observed. Framework guidance does not
claim to change an external hook's matcher.

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

For project-local Context Mode configuration:
Only create or change reversible, non-secret project files when the user's request authorizes that
setup and repository autonomy rules permit it. Preserve unrelated configuration. Do not use this
permission for global package/plugin installation.

For external installation (`user_approval_required: true`):
Do not silently install. Report what is needed and wait for user confirmation.

Never set `enabled: true` when dependencies are absent — this creates a misleading config state.

## Documentation

- Capability catalog: `docs/capabilities.md`
- Context optimization (RTK, Context Mode): `docs/context-optimization.md`
- Registry source: `.mxagile/capabilities.yaml`
- Context lifecycle: `docs/context-lifecycle.md`
