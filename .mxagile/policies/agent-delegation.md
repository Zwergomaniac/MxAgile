# Bounded Agent Delegation

## Routing Decision

Before substantive semantic analysis of a work package, the main agent MUST make
and persist a routing decision. A capability declaration or an available Context
Mode operation is not a routing decision and is never evidence that a subagent was
spawned.

Classify each bounded work package independently:

```powershell
& ./.mxagile/tools/Get-MxAgileCapabilities.ps1 -Capability subagent_spawn -Format json -ModelProfile MID
```

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

The input carries `mission_id`, unique `decision_id`, `session_identity` when known,
`work_package`, `requested_agent_type`, `work_class`, bounded `scope`, `artifact_count`,
`semantic`, `deterministic`, `capability_state`, `requested_profile`, `route`, `reason`,
`fallback_reason`, `delegation_attempted`, `spawn_outcome`, `delegation_id`,
`result_reference`, `main_consumed`, `compaction_occurred`, `result_reused`,
`stale_result_rejected`, `batch_restarted`, and `references` (`path` and optional
`identity`). The writer timestamps the record, fingerprints referenced sources, and
links it from the active Context Epoch. Never put source contents or transcripts in
the input.

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

If the profile cannot be resolved, continue with the harness's available/default
agent model and report `fallback_used: true` with a reason. Do not claim a resolved
model unless the adapter mapping or harness runtime proves it. Escalate from MID to
HIGH for genuine ambiguity or conflicting active references; size alone is not an
escalation reason. Deterministic work has no model profile.

Each actual delegation handoff and persisted result records model-selection status,
profile-resolution status, resolution method, resolved model when known, requested
reasoning effort when applicable, and fallback use/reason. Result schema 1.1 adds
this evidence while the reader continues to accept compact 1.0 results. Dynamic or
undisclosed runtime choices remain unresolved rather than being inferred from the
adapter.

Session completion should report spawned mission IDs, requested profiles, resolved
model identifiers only when the harness proves them, result references, reused results,
and delegation fallbacks. Never include full subagent transcripts. The board may later
project active/completed mission state and result references; no monitoring UI is part
of this contract.