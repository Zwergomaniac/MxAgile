# Bounded Agent Delegation

## Routing Decision

Before substantive semantic analysis of a work package, the main agent MUST make
and persist a routing decision. A capability declaration or an available Context
Mode operation is not a routing decision and is never evidence that a subagent was
spawned.

Classify each bounded work package independently:

```powershell
& ./.mxagile/tools/Get-MxAgileCapabilities.ps1 -Capability subagent_spawn -Format json -ModelProfile MID -MainProfile <observed-main-profile>```

Use the adapter's `integration.status` and `state` fields and inspect the current
session's actual tool namespace. `supported` is necessary, but does not prove that a
spawn tool is visible or call it. Never infer one harness's support or tool signature
from another harness or another session. Record the decision with
`.mxagile/tools/Save-MxAgileRoutingDecision.ps1` before beginning the semantic
analysis; this applies to `DELEGATE`, `MAIN_AGENT`, `CONTEXT_MODE`, `HELPER`, and
`FALLBACK` routes. Every non-delegation decision requires a concrete reason.

Write only decision metadata and project-relative references to a temporary JSON file
under `.concord/scratch/`, then persist it with:

```powershell
& ./.mxagile/tools/Save-MxAgileRoutingDecision.ps1 -ProjectRoot . -InputFile <decision-json>
```

The input carries `schema_version: "1.0"`, `mission_id`, unique `decision_id`,
`session_identity` (required key, `null` when unknown),
`work_package`, `requested_agent_type`, `work_class`, bounded `scope`, `artifact_count`,
`semantic`, `deterministic`, `capability_state`, `requested_profile`, `route`, `reason`,
`fallback_reason`, `delegation_attempted`, `spawn_outcome`, `delegation_id`,
`result_reference`, `main_consumed`, `compaction_occurred`, `result_reused`,
`stale_result_rejected`, `batch_restarted`, and `references` (each with required
`path` and string `identity`; empty identity only when the source has none).
All listed keys are required, including nullable metadata. `scope.paths` and
`references` are arrays; counts are integers and observation flags are real JSON
booleans, never strings. `recorded_at`, `updated_at` and `source_fingerprints` belong
only to the persisted output, not writer input. The writer timestamps the record, fingerprints referenced sources, and
links it from the active Context Epoch. Never put source contents or transcripts in
the input.

### Complete minimal writer input

Replace `mission_id` with the active checkpoint identity. The referenced file must exist;
this example declares a helper route, not a spawn or an acceptance PASS.

```json
{
  "schema_version": "1.0",
  "mission_id": "MISSION-example",
  "decision_id": "ROUTE-example",
  "session_identity": null,
  "work_package": "Validate one requirement candidate",
  "requested_agent_type": null,
  "work_class": "deterministic",
  "scope": {"summary": "One requirement", "paths": ["requirements/REQ-001.yml"]},
  "artifact_count": 1,
  "semantic": false,
  "deterministic": true,
  "capability_state": "not_applicable",
  "requested_profile": null,
  "route": "HELPER",
  "reason": "Deterministic validation is sufficient",
  "fallback_reason": null,
  "delegation_attempted": false,
  "spawn_outcome": "not_attempted",
  "delegation_id": null,
  "result_reference": null,
  "main_consumed": false,
  "compaction_occurred": false,
  "result_reused": false,
  "stale_result_rejected": false,
  "batch_restarted": false,
  "references": [{"path": "requirements/REQ-001.yml", "identity": "REQ-001"}]
}
```

A pre-spawn DELEGATE input retains every key above and changes `work_class` to
`bounded_semantic`, `semantic` to true, `deterministic` to false, `route` to DELEGATE,
and `spawn_outcome` to pending. Set the actually observed agent/profile and supported
capability; never infer them from registry declarations. Canonical `delegation_id`, when
known, uses `DELEGATION-...` (case-sensitive), not a host UUID or agent name. Unknown
identity remains null. The writer computes `source_fingerprints`; input references require
`identity` but do not contain a caller-invented hash. Reconcile actual dispatch afterward.

Routing order:

1. Deterministic work uses its helper, script, doctor, or parser.
2. Large raw-source retrieval may use Context Mode only when usable for the required operation; persist the compact decision-relevant finding.
3. Then classify semantic work derived from those sources independently. For separable bounded semantic work, when delegation is `supported`, an actual spawn tool is visible, authority permits it, no deterministic helper is sufficient, anti-amplification limits are respected, and a compact result is useful, delegation is the default and MUST be attempted.
4. If any delegation condition is not met, persist `MAIN_AGENT` or `FALLBACK` with the exact reason and continue fail-soft. Context Mode must never suppress this second semantic routing decision.
5. The main agent performs final integration, conflict resolution, lifecycle/gate decisions, and user decisions.

Use the authorized Wave plan as one input to semantic work-package boundaries: scope,
dependencies, and verification/exit obligations can make work independently reviewable
or unsafe to parallelize. Do not equate one Wave with one subagent. A Wave may remain
with the main agent or contain multiple bounded packages; work in separate Waves may
run in parallel only when their dependencies and shared-state risks permit it. The main
agent retains integration and all lifecycle/gate authority.

For `DELEGATE`, the pre-spawn record uses `delegation_attempted: false`,
`spawn_outcome: pending`, a concrete requested agent/profile and the bounded scope.
After dispatch, record `delegation_attempted: true` and observed `started` or `failed`;
only completed results may become `completed` and `main_consumed: true`.
For `DELEGATE`, persist the decision first, then invoke the harness-native named-agent,
subagent, or fork operation actually exposed by the current session. Use only its
observed tool name and supported parameters. Pass the bounded handoff, requested
profile, and no conversation transcript. Update the routing record with attempted
dispatch evidence. On spawn failure, update the route to `FALLBACK`, record the failed
attempt and concrete fallback reason, then continue with the main agent. On success,
save a compact completed result, retrieve it through the result reader, and explicitly
consume it before reconciliation. A declaration, handoff file, or simulated invocation
is not a successful spawn.

Before a child that may write is spawned, the parent MUST have a valid Delivery Context under
`policies/lifecycle-resync.md`. A child cannot create authorization the parent does not have:
without a current mission, canonically planned and registered Wave, assigned work package,
required gates, and mutation-boundary operating-mode evidence, use `MAIN_AGENT` or a read-only
handoff. Never dispatch a write-capable child to recover from an invalid or unknown parent context.

Do not delegate YAML quoting, schema checks, regex/provenance mapping, Git index
checks, framework updates, lifecycle re-sync, or final planning decisions.

## Autonomous Read-only Diagnostic Delegation

An explicit request for a subagent to perform bounded analysis without file/model changes
is `READ_ONLY_DIAGNOSTIC`, not a write-capable Delivery child. Resolve the concrete input
paths within this project. Clear read-only intent needs no Human authorization and no
"create a handoff or analyze yourself?" question. Ambiguous mutation/authority scope is
`DIAGNOSTIC_SCOPE_NEEDS_HUMAN`; never silently assume read-only or replace an explicitly
requested safe subagent with main-agent analysis.

Use the installed canonical producer, supplying the observed main profile and explicit
read-only/input scope. MID is the ordinary bounded-analysis demand; genuine conflicts may
require a different profile under the existing model-ceiling policy.

```powershell
python -B <absolute-project-root>/.mxagile/tools/control-plane/child_contract.py diagnostic-handoff --project-root <absolute-project-root> --task "Compare the two bound revisions; no files changed" --source-paths <revision-037-path> <revision-038-path> --read-only --main-profile MID
```

The producer resolves the profile through the existing capability helper, persists and
schema-validates only `.concord/delegation-handoffs/DELEGATION-....json`, and returns the
native `subagent_type`, explicit `model`, and `MXAGILE_HANDOFF` marker. The integrity-bound
producer grammar is permitted by the hook without Mission/Wave/write authorization;
extra shell commands, arbitrary targets and missing read-only scope are not permitted.
Invoke the actual discovered native Agent tool with those returned fields. A prepared
handoff or hook ALLOW is not execution evidence; reconcile real dispatch separately.

The handoff has no Mission/Wave (null, never fabricated), empty write scope, false
`mutation_allowed`, and `delivery_authority`, `lifecycle_authority`, `publication_authority`
all `none`. It binds input fingerprints and permits only Read/Grep/Glob, returning findings
in the conversation. It cannot write results, promote evidence, accept a gate or spawn
another child. Input changes invalidate the handoff.

For Claude, the generated `mxagile-diagnostic-agent` definition has only Read/Grep/Glob.
The hook verifies that exact named-agent tool restriction, no-authority envelope, input
fingerprints, model ceiling and explicit model request instead of requiring the unavailable
stdin `attest_diagnostic_child` callback. This is deterministic native-contract validation,
not an attestation that Claude loaded the file or executed the requested model. When a
host has no persistent Main Run ID, the diagnostic Run ID is correlation only, never
Delivery authority. Other hosts/custom agents still need actual tool-constraint evidence;
no unconstrained generic child is authorized by a prompt saying "read-only".

A diagnostic child with the native host agent identity is denied all non-read operations
by the hook; Claude's native tools list independently withholds mutation tools. Delivery
children retain the existing Mission/Wave/Delivery Context and authority gates. No automatic
HIGH escalation or MID-to-Sonnet live PASS follows from this path.

## Harness Contract

The generic adapter contract is `.mxagile/schemas/harness-adapter.schema.json`;
the current host declarations live under `.mxagile/adapters/*/agent-delegation*.yaml`.
Capability states are `supported`, `unsupported`, and `unknown`. A missing field is
`unknown`; no broad provider or harness family inherits another adapter's result.

The assessed declarations are intentionally conservative:

| Harness | Delegation | Model selection | Evidence |
| --- | --- | --- | --- |
| Claude Code | supported | supported | Current reality audit and named-agent adapter |
| VS Code Copilot | supported | supported | Official subagent/custom-agent documentation; profile mapping is session-dependent |
| Copilot CLI | supported | supported | Official task/fork, custom-agent model, and plan-dependent concurrency documentation |
| OpenCode | supported | supported | Official named-subagent and per-agent model documentation; generic fork remains unknown |
| Codex | supported | supported | Official named-agent, parallel-workflow, model, and configurable concurrency documentation |
| Hermes, Grok, Concord, generic | unknown | unknown | No verified delegation contract in this assessment |

No harness in the current inventory is declared unsupported without evidence.
An explicit `unsupported` adapter is still a valid state and must route to fallback.
Concurrency is `null` when the effective value depends on plan/session configuration
or the limit is undocumented; see each adapter's `concurrency_notes`. Do not invent
a numeric limit or treat an adjustable default as a hard cap. For example, Claude
Code documents a default maximum of 20 and Copilot CLI documents plan-dependent
defaults, but neither establishes the effective limit of an arbitrary session.

## Handoff

The handoff conforms to `.mxagile/schemas/delegation-handoff.schema.json` and contains
only mission/delegation IDs, the concrete task, bounded scope and paths, authority
references, necessary artifact paths and fingerprints, allowed tools, forbidden
mutations, expected result schema, the mandatory `delivery_context` envelope, and an
optional supported context budget/profile. The envelope binds canonical Wave/work-package IDs,
project root, branch/worktree, base HEAD, operating mode, `read_only` or `authorized_write`,
write/forbidden scope, required artifacts, verification and commit expectations, re-sync
conditions, required and loaded Skills, required/available capabilities, required evidence sources,
evidence destinations, and output artifacts. Record requested profile, resolved model, and effective
model separately. `effective_model_status: not_observable` is valid; a task title, parent model, or
requested profile is never host confirmation. Do not attach the repository, conversation history,
secrets, full historical reports, or unrelated authority material. A null/unknown branch, HEAD, mode,
authorization, required skill, or required capability cannot grant a write/verification scope.
State a read-only scope unless a specific mutation is explicitly authorized; lifecycle authority is
never delegated.

For delegated runtime/browser/parity work, the coordinating agent resolves the runtime once
and places the non-secret `resolved_runtime_recipe` in the active mission/verification
preflight record. Every dependent handoff references that same record through `artifact_paths`.
Consumers must not generate a second recipe or reconstruct arguments. Secret values are never
stored in the record; secret arguments are represented only by their authoritative references
and are resolved at the actual credential-consuming operation.

## Read-Only Diagnostic and Dispatcher Boundaries

`read_only_diagnostic` is a capability plus a schema-valid bounded handoff, not
an agent-name permission. It binds parent run/project, safe paths and fingerprints,
actual read tools, `authorization: read_only`, no write/evidence destinations or
commit, and `output_contract: diagnostic-findings/1`. Host-attested tool/path
restrictions and run correlation are required. A diagnostic conclusion cannot
grant Delivery or Acceptance authority. Without host attestation report
`NOT_OBSERVABLE` and retain the existing safe fallback; do not expand Explore names.

`concord_invoke` and `execute_handler` dispatchers are classified by the discovered
inner operation's complete argument contract, never just the outer tool or an
agent-supplied `read_only` flag. The current stdin hook has no live provider for
that attestation and fails closed; synthetic boundary tests are not live evidence.

## Anti-Amplification

Never dispatch one subagent per file or requirement. The regression fixtures include
87 requirements and 52 decisions: group items into a small number of coherent
missions, with boundaries chosen from semantic cohesion, artifact count, estimated
context size, handoff size, and verified harness concurrency. Do not impose a fixed
batch count or size when source and context sizes vary. Parallelize only independent
batches whose results remain independently reviewable.

## Result and Resume

Only completed bounded work produces a result. Write a compact result through
`.mxagile/tools/Save-MxAgileDelegationResult.ps1`; the tool verifies the active
mission, confines source paths to the project, computes source fingerprints, rejects
common secret patterns, persists the result under `.concord/delegated-results/`, and
links it from the operational Context Epoch. Retrieve with
`.mxagile/tools/Get-MxAgileDelegationResult.ps1 -DelegationId <id>`. Reuse only when
the active mission matches and all source fingerprints remain current. A stale,
missing, interrupted, or incomplete result is not completed work.

The result conforms to `delegation-result.schema.json` and carries conclusion,
findings, provenance, affected IDs, unknowns, conflicts, decision candidates, evidence
references, and source fingerprints. Do not store transcripts, raw reads, or secrets.
Context Mode may be used for targeted retrieval only when usable; do not automatically
index every result or historical report. After interruption or resume, re-sync the
canonical lifecycle state before reusing completed results.

## Main-Agent Authority

The main agent retains `ACTIVE_TARGET` authority, lifecycle state, gate decisions,
final findings reconciliation, planning decisions, user escalation, and merging of
conflicting subagent findings. Subagents analyze and return evidence; the main agent
integrates and owns the decision. Running delegations are never treated as completed
after interruption.

## Profiles and Observability

Core mission semantics use `LIGHT`, `MID`, and `HIGH` from `.mxagile/delegation.yaml`.
They describe reasoning demand, not model price, identity, or context capacity. The
physical context window is modeled independently by `.mxagile/model-profiles.yaml`
and the context-lifecycle contract. A large window or a model ID such as
`claude-fable-5-1` does not imply a higher reasoning profile; there is no `ULTRA`
Core profile.

Harness adapters declare model-selection support separately from profile resolution:

- `static_mapping` requires a verified harness-specific mapping in that adapter.
- `dynamic_capability` may request a harness effort supported by the selected model;
	the request is not proof of the actual model or accepted effort.
- `unknown` means model selection may exist but MxAgile has no verified profile
	mapping or capability result. An empty mapping must state this reason.
- `unsupported` means the harness cannot select a model/profile; an empty mapping is
	expected.

Current adapter coverage:

| Harness | Model selection | Profile resolution | Empty mapping / discovery evidence |
| --- | --- | --- | --- |
| Claude Code | supported | static mapping | Verified harness aliases live only in its adapter. |
| Codex | supported | dynamic capability request | `model_reasoning_effort` is model-dependent; no concrete model is claimed without runtime evidence. |
| VS Code Copilot | supported | unknown | Model availability is session-dependent; no reliable profile-capability ranking is exposed to MxAgile. |
| Copilot CLI | supported | unknown | Selection exists, but verified capability discovery and profile ranking are not wired into MxAgile. |
| OpenCode | supported | unknown | Available model IDs can be listed, but the catalog does not rank MxAgile reasoning capability. |
| Hermes, Grok, Concord, generic | unknown | unknown | No verified selection/discovery contract; no mapping is inferred. |

Thus, dynamic model-ID discovery alone is insufficient for profile resolution:
MxAgile needs reliable capability metadata or a harness-owned mapping. Codex can
accept a capability-dependent effort request, but the selected model and accepted
effort remain runtime facts. No current adapter reports model selection as explicitly
unsupported; if one does, its empty mapping is correct and fallback is mandatory.

If the profile cannot be resolved safely within the main-model ceiling, continue
with the main agent and report `fallback_used: true` with a reason. An arbitrary
host/default child may be more expensive and is not a safe implicit fallback. Do not
claim a resolved model unless the adapter mapping or harness runtime proves it.
Genuine ambiguity or conflicting active references may justify a HIGH demand, but
never bypass the child-escalation authority below; size alone is not justification.
Deterministic work has no model profile.

### Child-Model Escalation Authority

The user's deliberately selected main profile is the ceiling for automatic children.
Apply this check **before** host model resolution and dispatch, including named-agent
HIGH defaults and mission overrides. Profile order is LIGHT < MID < HIGH; this is not
an ordering of universal model names or context windows. For the currently verified
Claude adapter, HIGH resolves to Opus and MID to Sonnet. Other hosts require their
own verified mapping/capability resolution; never infer rank from an ID or catalog.

Core default: `model_escalation: never` in `.mxagile/delegation.yaml`. Project/user
preference: `agent_delegation.model_escalation` in `.mxagile/config.yaml`; a missing
key also means never. A per-mission `-ModelEscalation` override must reflect an actual
active user instruction, not an agent's self-selected permission. Invalid values fail
closed. Lifecycle, delegation scope and host capability constraints remain independent.

| Policy | Child above main | Required action / authority |
| --- | --- | --- |
| never (default) | Not automatic | Limit the request to the main profile before mapping, or remain with the main agent. |
| ask | Only after approval | Ask the user for this work package; persist the concrete approval reference before dispatch. Pending/unanswered approval is not permission. |
| autonomous | Permitted when justified | Record the enabled policy source and substantive task-specific justification before dispatch; source size/price alone is insufficient. |

Thus HIGH main permits MID/HIGH children; MID main permits MID, but a HIGH demand
is limited to MID under never, awaits approval under ask, or needs an auditable
justification under autonomous. LIGHT follows the same ceiling rule. A current
explicit user instruction such as "Start an Opus subagent for this task" overrides
never/ask, **only** for the specified task/model and only when the host supports it.
A model parameter, child claim, profile default, or catalog entry alone is not user
permission. Do not generalize one approval into future work-package authority.

Resolve with the existing capability helper, passing the known main profile/model:

```powershell
& ./.mxagile/tools/Get-MxAgileCapabilities.ps1 -Capability subagent_spawn -Format json -ModelProfile HIGH -MainProfile MID -MainModel <user-selected-main-model>
```

`integration.route_allowed` must be true before dispatch; capability `available`
alone is insufficient. `integration.escalation.decision` is allowed, limited,
needs_user_approval or blocked. `requested_profile` retains the original demand;
use the permitted `resolved_child_profile` and resolved host model/effort in the
actual spawn, not the old HIGH agent default. Reassess if the host substitutes a
different model. The helper assesses supplied declarations/current host observations;
it does not discover a live model catalog, execute a spawn, or attest actual identity.

For ask, supply `-UserModelAuthority <task-scoped-approval-reference>`. For autonomous,
provide `-EscalationReason <substantive-reason>` and retain the policy source. For an
explicit model instruction, also supply `-ExplicitUserModelRequest`,
`-RequestedChildModel <exact-host-model-id>` and `-AvailableChildModels <current-host-ids>`.
The catalog input is current discovered evidence, not a list invented by the agent;
its absence is MODEL_AVAILABILITY_UNKNOWN, an absent requested ID is MODEL_UNAVAILABLE.
An unsupported model-selection host cannot fulfill an explicit request. Do not silently
replace the requested model; remain with the main agent or seek approval for a specific
supported alternative. Dynamic effort resolution must bind to the known main model
supported for child selection; unknown mapping/inheritance defaults cannot authorize
an automatic child. A static adapter mapping is declared eligibility, not a live probe.

Persist `model_resolution.escalation` in each new handoff/result. It carries
`main_profile`, `main_model`, `requested_child_profile`, `resolved_child_profile`,
`requested_child_model`, `spawn_request_model`, `actual_model`, `escalation_policy`,
`escalation_authority`, plus `authority_reference`, `decision`, `reason`,
`actual_model_status` and `actual_model_source`. Known request/mapping fields are
DECLARED until independently observed. The pre-spawn resolver leaves spawn_request_model
and actual_model null: update the former only from the actual host call, the latter
only from child execution attestation with its source. Missing actual identity is
null/NOT_OBSERVABLE, never guessed from the parent, requested profile or mapping.
The parent's authority is immutable in the child handoff/result; a child cannot grant
itself escalation. Legacy envelopes without this optional schema extension remain
readable but are NOT_OBSERVABLE for escalation and do not authorize a new dispatch.
The result writer rejects pending/blocked authority, unaudited escalation and guessed
actual identity. No model-routing engine, universal price matrix or live host guarantee
is introduced.

Each actual delegation handoff and persisted result records model-selection status,
profile-resolution status, resolution method, resolved model when known, requested
reasoning effort when applicable, and fallback use/reason. Result schema 1.1 adds
this evidence while the reader continues to accept compact 1.0 results. Dynamic or
undisclosed runtime choices remain unresolved rather than being inferred from the
adapter.

For empirical routing, keep the selected Core profile, model/effort actually
present in the spawn request, and host-observed child model as separate evidence.
FAST/MID/DEEP labels in a host are not new Core profiles: translate only through
an explicit adapter mapping to LIGHT/MID/HIGH. Classify observed failures as
`FRAMEWORK_PROFILE_RESOLUTION_FAILED` (requested profile not resolved),
`HOST_IGNORED_PROFILE` (verified request and different observed child),
`HOST_DOES_NOT_SUPPORT_CHILD_MODEL_SELECTION` (verified host limitation), or
`MAIN_MODEL_INHERITED` (host-confirmed inheritance). Missing spawn/child evidence
is `NOT_OBSERVABLE`, never inferred from the parent model, task title, plugin name
or model catalog. A supported model-selection declaration does not prove request
acceptance or actual child identity.

### Bounded Model Evidence / Telemetry

The opt-in harness-neutral telemetry record also carries `main_profile`, `main_model`,
`requested_child_profile`, `resolved_child_profile`, `requested_child_model`,
`escalation_policy`, `escalation_authority`, `escalation_reason` and
`escalation_authority_reference`; explicit metadata remains DECLARED. Observed parent
message.model proves the main model at spawn, not user-selected profile or child identity.
The original fields remain compatible. The record separates `requested_profile`,
`resolved_profile`, `requested_model`, `provider`, `spawn_request_model`,
`resolved_model` and `actual_model`. Each field carries state/source/reason;
unavailable values remain null/NOT_OBSERVABLE, never inferred from parent model,
profile name or adapter default. Explicit child metadata is DECLARED, not host
execution attestation. Actual message.model evidence is OBSERVED only for that
child's recorded requests. A mapping resolution may be DECLARED while its
execution remains NOT_OBSERVABLE; keep those facts distinct.

The Claude collector records parent Agent input.model independently of child
metadata and message.model. An observed omission is `spawn_request_model.value: null`
with an omission reason, not a claim of Opus/Sonnet or inheritance. If an Opus
parent launches a Plan child for MID without model input and no child model
attestation exists, actual_model/resolved_model remain NOT_OBSERVABLE. No collector
is automatically injected into startup and no harness/model-selection matrix is
claimed by these additional fields.

Session completion should report spawned mission IDs, requested profiles, resolved
model identifiers only when the harness proves them, result references, reused results,
and delegation fallbacks. Never include full subagent transcripts. The board may later
project active/completed mission state and result references; no monitoring UI is part
of this contract.