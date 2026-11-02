# Context Architecture Baseline

**Status:** `CONTEXT_ARCHITECTURE_BASELINE_COMPLETE = JA`
**Implementation approval required:** `JA`
**Phase:** analysis only. No framework policy semantics were changed for this baseline. No test suite or release gate was run.

## Scope and Evidence

This baseline separates:

1. Canonical MxAgile sources under `.mxagile/`.
2. Generated harness projections.
3. Content the selected harness actually includes automatically.
4. Content loaded only when a router, agent, skill, resolver, or hook selects it.

Generated copies are not counted as additional normative authorities. Their bytes are counted only where the harness can inject their descriptions or bodies. The analysis used repository sources at `91e8cec`, the CapTrack campaign commit `c34c4c285d4c91764b899286afd1767bb959c6aa`, Claude Code transcript metadata, the local Copilot session index, and current Claude/Copilot load documentation. The CapTrack repository was inspected read-only; its pre-existing dirty files were left untouched.

Evidence labels used below:

- `OBSERVED`: recorded in a transcript, provider report, commit, file-access event, or measured byte count.
- `HARNESS CONTRACT`: documented harness behavior; not proof that a particular file appeared in an individual request.
- `DECLARED`: adapter/configuration says a capability is supported or requested.
- `NOT_OBSERVABLE`: the available logs do not establish the fact.

The local Copilot SQLite index has no per-event token/usage table and did not contain the CapTrack campaign commit or recipe turns. Claude JSONL logs did contain the campaign. Provider usage remains authoritative for billed totals; transcript-derived token sums do not fully reconcile and are reported separately.

## 1. Load Graph

### Canonical source and projection

`.mxagile/` is the agent-agnostic Core source. `generate-mxagile-platform-skills.ps1` produces Claude/Copilot/Codex/Grok/OpenCode/Hermes skill projections and Claude agent projections. `apply-project-agent-instructions.ps1` injects the startup router as a managed block. `install-core.ps1` distributes Core files and runs the setup/generator path. Neither a generated file's presence nor the setup script itself proves that its full body is in a particular request.

The framework repository's root `CLAUDE.md` is **FRAMEWORK_DEVELOPMENT_ONLY**. It describes Core development and is not the consumer project's runtime instruction contract. `skillssource/AGENTS.md` is a project-knowledge router/template source, distinct from `.mxagile/` and from generated harness agents.

### Claude Code consumer session

| Classification | CapTrack evidence and load behavior |
|---|---|
| `ALWAYS_LOADED` | Claude Code loads root `CLAUDE.md` and expands its `@AGENT.md` import. At campaign commit, `CLAUDE.md` was 13,296 bytes and `AGENT.md` 13,672 bytes. Replacing the 9-byte import directive yields about 26,959 bytes of project instruction content, including a 6,715-byte managed MxAgile startup block. User-level instructions are also in scope; current profile files measured 239 bytes (`~/.claude/CLAUDE.md`) and 460 bytes (`RTK.md`), but their exact campaign-time snapshot is `NOT_OBSERVABLE`. |
| `ALWAYS_LOADED` metadata | Claude's available skill descriptions and custom-agent descriptions contribute a listing/selection context. CapTrack commit contains 87 project `SKILL.md` files: 1,399,522 body bytes and 20,645 description characters. Nine custom agents contain 142,799 body bytes and 1,037 description characters. Claude's description budget can truncate listings; exact descriptions delivered in each request are `NOT_OBSERVABLE`. |
| `ON_DEMAND` | Full skill bodies load on invocation/relevance. The campaign invoked `mxagile-visual-verification` once; its projected body is 13,690 bytes. The other 86 skill bodies were available but are not evidence of being loaded. |
| `ON_DEMAND` | Custom-agent bodies load when selected/spawned. The campaign's 13 children are Claude `fork` transcripts, not the generated MxAgile custom agents; their custom-agent bodies are not shown as invoked. |
| `GENERATED_PROJECTION` | The 12 generated MxAgile skills total 109,145 bytes in `.claude/skills/`; their descriptions total 935 characters. The nine custom-agent descriptions are 1,037 characters. These are projections of canonical `.mxagile/` bodies, not separate authorities. |
| `REFERENCE_ONLY` | Policy links in the startup block, agent bodies, and skills are routing instructions. A link is not evidence that the target policy was read. |

Claude's documented fork behavior is decisive here: a fork inherits the entire parent conversation/system/tools, while a non-fork subagent gets a fresh context and task handoff. Child cache reads therefore include inherited context; this is a measured context mechanism, not MxAgile model-profile routing. Project skill bodies and their reattachment after compaction have their own lifecycle; direct session evidence for exactly which skill text was reattached is `NOT_OBSERVABLE`.

### Copilot consumer session

VS Code Copilot automatically includes `.github/copilot-instructions.md` when the Copilot harness is selected. Custom instructions are additive and may include `AGENTS.md` or applicable `*.instructions.md`. Skills are progressive: discovery/description first, full `SKILL.md` body when relevant or explicitly invoked, then supporting resources only when referenced. Custom agent files become context when selected or spawned. At the CapTrack commit, `.github/copilot-instructions.md` was 22,660 bytes; this was not the harness used for the Claude/Bedrock benchmark.

### Startup and Re-Sync

The generated startup block imposes this route:

```text
workspace boundary / Git integrity
  -> lifecycle Re-Sync
  -> tool-instruction conflict and selected tool authority
  -> external-change reconciliation when installed
  -> project knowledge / Brain after state is known
  -> delegation route before substantive semantic work
  -> optional capabilities only on demand
  -> update compatibility contract after update
```

This is instruction text, not an executable lifecycle resolver. The neutral `AGENT.md` is inlined into `AGENTS.md` and Copilot instructions; Claude receives the startup block plus `@AGENT.md`. The separate `skillssource/AGENTS.md` is a project knowledge index, not the same injected file.

A normal session reads `.mxagile/lifecycle.yaml`, canonical process state, checklist, decisions, stories, and input inventory per `lifecycle-resync.md`. This is a **conditional mandatory read at startup/resume**, not automatic loading of every policy. A phase router in `lifecycle.yaml` selects agents and skills. Agents then read their listed policies. After a Core update, `update-contract.md` requires an explicit same-session contract/projection re-read; regenerated projections on disk are not evidence the running context reloaded them.

### Compaction, Resume, and Child Context

Compaction hooks/scripts are available but hook installation is user-authorized and configuration-dependent. `Invoke-MxAgilePreCompactionCheckpoint.ps1`, `Invoke-MxAgilePostCompactionResync.ps1`, `Read/Write-MxAgileEpochCheckpoint.ps1`, and the transition resolver are executable components. Their presence does not prove that a particular hook ran. Claude logs directly record six compaction markers in this campaign: two Main and four across two Sonnet forks, with pre-compaction sizes around 167k–176k tokens. Whether MxAgile pre/post hooks ran for each event is `NOT_OBSERVABLE` from the saved transcript.

All 13 observed children are depth-1 `fork`s with `model: inherit`; their transcript `message.model` values match the Main model at each spawn. The fork gets the whole then-current parent context. It does not get a bounded fresh policy-only context, even when the task itself is narrowly worded. This is the benchmark's main demonstrated context-amplification mechanism.

## 2. Context Baseline Measurements

All byte counts are UTF-8 bytes unless noted. They are source/result sizes, not estimated tokens.

| Measurement | Observed value | Scope/limit |
|---|---:|---|
| CapTrack `CLAUDE.md` at `c34c4c28` | 13,296 B | Contains startup block and `@AGENT.md` include. |
| CapTrack `AGENT.md` at `c34c4c28` | 13,672 B | Expanded project instructions. |
| Effective project instruction source | about 26,959 B | `CLAUDE.md` with the 9-byte import directive replaced by `AGENT.md`; exact harness serialization not captured. |
| MxAgile managed startup block | 6,715 B | Exact managed block in CapTrack `CLAUDE.md`; current Core script block is 6,702 B. |
| Generated Copilot instructions | 22,660 B | Separate harness projection; not loaded in the Claude benchmark. |
| CapTrack project skills | 87 files / 1,399,522 B | All bodies on disk; not all bodies enter context. |
| CapTrack project skill descriptions | 20,645 chars | Listing source size; exact post-budget descriptions delivered are `NOT_OBSERVABLE`. |
| Generated MxAgile skill projections | 12 / 109,145 B | Generated copies, not new authorities. |
| Invoked visual-verification skill | 13,690 B | One explicit skill invocation. |
| Custom agents | 9 / 142,799 B | Bodies are not loaded just because they exist. |
| Custom-agent descriptions | 1,037 chars | Metadata/listing source; exact serialized token cost is `NOT_OBSERVABLE`. |
| Local Claude auto-memory index | 149 B | Current snapshot only; exact campaign-time state is `NOT_OBSERVABLE`. |
| Claude `api-request-blob.message` payload | 328 objects / 1,000,536 B | Serialized message-object proxy only. It excludes complete system prompt, tool schemas, cache framing, and other provider context; not a total-context measurement. |
| Direct Read tool calls through campaign cutoff | 43 calls / 29 distinct files / 182,013 B returned | Includes project artifacts, not just policies. Fourteen calls repeat a previously read path. |
| Context Mode results through cutoff | 80 calls / 550,728 B returned | `ctx_batch_execute`: 418,522 B; `ctx_execute`: 66,257 B; `ctx_search`: 44,520 B; `ctx_execute_file`: 20,151 B; `ctx_doctor`: 1,278 B. Returned bytes can overlap other reads; not unique material. |
| Bash results through cutoff | 411 calls / 385,392 B returned | Output size, not unique context; may include command summaries. |
| Main-to-child handoffs | 13 / 18,277 B | Serialized Agent-call inputs; mean about 1.4 KB. |
| Child results returned to Main | 13 / 14,846 B | Result payload bytes; about 1.1 KB each. |
| Total Main + Child direct file Read calls | 43 / 29 distinct paths | The same page inventory and `FINDINGS.md` were read four times each across three transcripts; other test/scenario artifacts were repeated twice or three times. |
| Child context cache read through commit cutoff | about 35.25m tokens | 58% of transcript-recorded cache reads; this is not a dollar allocation. |
| Main context cache read through commit cutoff | about 25.55m tokens | Transcript usage; provider total is supplied separately. |

The local transcript's commit-bounded usage sum does not reconcile with the provider's session report (especially uncached input and output). The report therefore preserves the provider totals as the billing source and treats transcript usage as per-request evidence only. No per-agent dollar split is available.

## 3. Reality Benchmark

```text
REALITY_BENCHMARK_ID: CAPTRACK_REGIONS_2026-11-02
Commit: c34c4c285d4c91764b899286afd1767bb959c6aa
Campaign result: PARTIAL
```

### Provider report (user-supplied)

| Model | Input | Output | Cache Read | Cache Write | Cost |
|---|---:|---:|---:|---:|---:|
| Opus 4.6 | 4.1k | 36.4k | 5.5m | 212.5k | $4.99 |
| Sonnet 4.6 | 20.1k | 356.1k | 55.1m | 1.9m | $28.96 |
| Total | — | — | — | — | $33.95 |

API duration: 2h 50m 44s. Wall duration: 21h 30m 54s. Usage report delta: +1,213 / -1,474 lines. The commit itself contains 7 files, +5,984 / -5 lines, including a 5,526-line reference mockup. These are different measurement scopes; do not reconcile them as productivity or cost-per-line.

**Model provenance:** Main model switching was manually initiated by the user. Therefore the Sonnet/Opus cost distribution is provider accounting only, not evidence that MxAgile routed Main work between profiles. The Claude Main transcript has both model IDs; its tool-call inputs contain no `model`, `profile`, or `model_profile` argument for the 13 direct forks. All 13 fork metadata records request `inherit`. At each spawn the parent's current model matches the child's first recorded `message.model`: 8 children ran Opus 4.6 and 5 ran Sonnet 4.6. This is actual fork inheritance, not an automatic MxAgile model-profile decision.

### Verified workpackage result

- REV-020 became `ACTIVE_TARGET`; REV-014 was deactivated.
- Regionen screen was reachable for AppAdmin; Name / Code / Status columns and AppAdmin read-only state were verified.
- CAP_Ceko and E2 role parity remained blocked by missing fixtures.
- Screenshot was bound to REV-020 / Regionen / AppAdmin.
- `SCN-CAP-REGIONS.yaml` records `overall_result: PARTIAL`; Findings and Change-Set were updated.
- Commit description records 7 files, +5,984 / -5 lines. Work was real and produced a committed artifact, but not a fully verified role campaign.

### Agent and fork anatomy

| Agent | Requested | Actual model from transcript | Requests through commit | Output tokens | Cache Read tokens |
|---|---|---|---:|---:|---:|
| Main | `USER_CONTROLLED` | Opus 4.6 and Sonnet 4.6 | 262 | 137,874 | 25,545,420 |
| `repair-parity-schema` | `inherit` | Sonnet 4.6 | 197 | 133,971 | 19,470,915 |
| `rev14-parity-analysis` | `inherit` | Sonnet 4.6 | 72 | 44,229 | 7,707,870 |
| Other 11 forks | `inherit` | 8 Opus, 3 Sonnet | 208 | 48,123 | 8,073,109 |

There were 13 direct child transcripts. A further 13 `Agent` tool results inside child logs say “Fork started — that fork is you”; no separate grandchild transcripts exist, so they are not counted as additional child agents. Twelve child metadata records mark `finished: true`; `repair-parity-schema` has a non-error parent result but no persisted `finished` flag, so its completion metadata is `NOT_OBSERVABLE`.

### Runtime recipe loss point

The installed Core at the campaign commit already had project-local mxcli resolution and a local-runtime profile. The profile specified `db_name: default` as Core autonomous identity and included local HSQLDB as project metadata. However:

- `Resolve-MxAgileMxcli.ps1` selected a binary path/source; it did not return a versioned runtime capability manifest or a resolved argv array.
- `development-runtime.md` documented `default` but used the `--db-name` spelling and said not to emit `--db-type` absent help evidence.
- Credential discovery ran as a pre-start requirement, and the consumers each reconstructed the effective command from examples and profile fragments.
- The user-reported project-local `./mxcli help run` documented `--dbname default` for the actual CapTrack binary, a different spelling from the policy example.

Observed active sequence: PostgreSQL was discussed at 08:20Z; `mxcli help run` was read at 08:29Z; an HSQLDB local invocation at 08:31Z omitted the DB identifier; another HSQLDB invocation at 09:11Z also omitted it; `AfterStartup` troubleshooting occurred around 09:10Z; the user supplied the missing `--dbname default` hint at 09:12Z. A later logged invocation included `--db-name default`, while the supplied Reality Evidence says the working binary option was `--dbname default`. This syntax discrepancy is unresolved in the saved transcript. The user reports that the HSQLDB runtime itself starts; the missing fixtures/identities are separate blockers.

**AVOIDABLE_WORKFLOW_BRANCH = JA.** Evidence: an external-DB-oriented diagnostic branch preceded capability resolution; logged local HSQLDB starts omitted the identifier; recipe completion followed a user correction. The logs do not support an attributable dollar amount or a claim that every PostgreSQL/SSO/AfterStartup investigation was unnecessary.

## 4. Load and Read Anatomy
### Verification/Parity Reality Fund (user-supplied, 2026-11-02)

**Evidence class:** `USER-SUPPLIED REALITY`; the underlying CapTrack artifacts were not re-inspected as part of this audit update.

The Regions run first passed four minimum smoke checks: expected text fragments, Regions title, successful navigation, and presence of any edit control/action. That evidence was later promoted to `overall_result: PASS` for Regions parity even though complete Behavioral, Role, and Whole-Screen Visual parity had not been established. A separate Mockup-vs-Mendix-Model analysis was also initially described as complete SOLL/IST parity while live-runtime evidence was still absent.

This is a resolver/authority failure, not a request for an ad-hoc parity patch. It sharpens the existing C4 design target:

- Keep `SMOKE` as its own evidence class. Navigation, text, and edit-control smoke may pass while full parity remains `NOT_VERIFIED` or `PARTIAL`; smoke alone can never produce parity `PASS`.
- Preserve structured dimension results separately, at minimum: `Contract`, `Model`, `Structural/Runtime`, `Behavioral`, `Role`, and `Whole-Screen Visual`.
- Derive the aggregate deterministically from the required dimensions, evidence sufficiency, freshness, and reference/comparison identity. Missing required evidence must resolve to `NOT_VERIFIED` / `PARTIAL`, never an agent-authored `PASS`.
- Label reference-vs-model analysis as such. It is not a live-runtime parity result and cannot satisfy runtime-dependent dimensions by implication.
- Treat `overall_result` as resolver output. A producer may submit dimension evidence, but may not promote the aggregate unless the deterministic resolver confirms all required evidence and identity constraints.

**Required future regression:** Regions navigation/text/edit smoke = `PASS`, with Behavioral/Role/Whole-Screen Visual evidence absent, must yield `overall_result != PASS`. Add a separate case proving Reference-vs-Model analysis with no live runtime remains non-final. These belong to planned Wave C4; no verification schema, policy, resolver, or CapTrack artifact was changed for this Reality Fund.

The existing baseline already identifies overlapping verification authorities (`evidence-contract.md`, `evidence-levels.md`, `verification-layers.md`, `ui-parity.md`, and parity schema) and notes that schema shape does not compute all cross-field aggregation. This Reality Fund supplies a concrete promotion failure for the future resolver mapping; it does not authorize parallel policy or schema authorities.

### MxAgile/mxcli Skill Authority Overlap Reality Fund (user-supplied, 2026-11-02)

**Evidence class:** `USER-SUPPLIED REALITY`; the reported CapTrack sessions and their transcripts were not re-inspected as part of this checkpoint.

Across several real CapTrack verification runs, agents reportedly reconstructed technical execution paths from mxcli capabilities/help, repository scripts, and Playwright helpers even when MxAgile mission/runtime/verification contracts or a resolved recipe were already available. The reported examples are:

- **Runtime:** PostgreSQL, credentials, MB_SSO, and AfterStartup were investigated despite a known local HSQLDB recipe with the default database identity.
- **Role parity:** separate demo-user credentials were investigated despite an authorized Mendix Demo User Switcher route after MBAdmin login.
- **Fixture/Regions parity:** agents repeated model queries for seed/demo microflows, bootstrap-script reads, Playwright helper inspection, and individual `mx_login` / `mx_wait` helper inspection instead of consuming resolved verification/fixture routes.
- An initial mxcli model query reportedly failed to parse and was not needed for the mission's execution path.

The intended authority boundary is:

| Owner | Authority |
|---|---|
| MxAgile Core / Mission Contract | WHAT, WHY, required evidence, authorization, and lifecycle |
| Existing MxAgile resolver | Selected tool and complete executable recipe |
| mxcli capability / skill | Technical capability and exact supported syntax for the selected binary |
| Consumer agent | Execute the resolved recipe and return structured results; do not reconstruct an already-resolved route |

**Load-graph audit status:** this fund identifies the investigation targets; it does not establish exact automatic/on-demand mxcli skill loads or per-run read counts. Which mxcli skill bodies were loaded, which overlapping MxAgile policies were read in the same run, whether an mxcli skill stated normative routing, and the number of repeated tool/policy reads remain `NOT_OBSERVABLE` until tied to the relevant transcript and harness load evidence. The reported unnecessary model query/parser error is a user-supplied failure observation; no aggregate failure count, attributable cost, or general frequency is inferred here.

**Design rule:** an mxcli skill may document execution help/capability syntax but must not become a second MxAgile mission, lifecycle, verification, or route authority. When a resolved recipe exists, execute it unchanged. Exploration is permitted only after a concrete step fails with evidenced cause.

**Future regression:** for a Regions Role/Visual verification with runtime, fixture, and demo-user switch recipes resolved, assert that the agent executes those routes and does not start PostgreSQL discovery, credential guessing, arbitrary model queries, independent AfterStartup exploration, or repeated helper inspection unless a resolved step fails. This is audit/design evidence for the planned resolver work only; no separate fix or C1/C4 implementation was started.

The campaign transcript proves these explicit policy accesses through commit cutoff:

| Evidence type | Policy | Calls / returned bytes | Interpretation |
|---|---|---:|---|
| Direct `Read` | `external-change-reconciliation.md` | 1 / 1,806 B | Actual file read. |
| Bash read/search path | `external-change-reconciliation.md` | 1 / 7,499 B | Exact path in a read-oriented Bash command; result may be excerpted. |
| Bash read/search path | `local-runtime-profile.md` | 1 / 1,960 B | Actual command names the path; returned result is partial relative to 51 KB source. |
| Bash read/search path | `ui-parity.md` | 1 / 3,266 B | Actual command names the path; partial result. |
| Bash read/search path | `update-contract.md` | 2 / 15,807 B | Repeated same-policy path in a post-update/contract-re-sync route. |
| Context Mode file route | `update-contract.md` | 1 / 2,954 B | One explicit file-route result. |

The Main log also shows one invocation of `mxagile-visual-verification`; project-skill body size is 13,690 B. Other runtime/verification/lifecycle policy names appear in commands or retrieved Context Mode output, but a mention/search result does not prove the full source body was loaded. Exact per-policy body reads for `development-runtime.md`, `credential-discovery.md`, `runtime-strategy.md`, `runtime-startup-recovery.md`, `verification-scenario.md`, `test-identity-lifecycle.md`, and others are `NOT_OBSERVABLE` unless an exact path-read event exists.

The local Copilot session index found no benchmark commit reference, no `mxcli run --local`/HSQLDB campaign turns, and no policy read path for this campaign. It contains useful non-token proxies for three MxAgile-repository sessions:

| Mission sample | Turns | File events | What is measurable |
|---|---:|---:|---|
| Compatibility closure | 20 | 362 | Session metadata and file-event count only; bytes/tokens unavailable. |
| External-change final integration | 56 | 984 | File-event count; 951 `read_file` events and 14 `apply_patch` events in the session store. |
| Release-readiness commit | 3 | 40 | Session/file-event proxy only, not a standalone suite context measurement. |
| Simple implementation-only session | — | — | `NOT_OBSERVABLE` in the retrieved sample set. |
| Migration mission | — | — | `NOT_OBSERVABLE` in the retrieved sample set. |
| Copilot Runtime Verification / UI Parity | — | — | No matching local Copilot campaign session; CapTrack evidence is Claude Code. |

These are examples, not comparable cost baselines. `session_files` counts file events/path records, not bytes or unique policy-body tokens.

## 5. Policy Inventory and Primary Recommendation

Sizes are source-file bytes at the current repository baseline. “Consumers” are static direct references, not proof of actual loading. Generated platform copies are excluded from the canonical policy inventory; policies are not individually generated as harness authorities. Size alone does not determine the recommendation.

| Policy | Purpose / authority | Bytes | Declared consumers | Load, overlap, executable neighbor | Primary |
|---|---|---:|---|---|---|
| `acceptance-campaign.md` | Campaign taxonomy and gate contract | 5,888 | Acceptance, VPL | Acceptance-only procedure; schemas describe artifacts | ON_DEMAND |
| `agent-delegation.md` | Work-package routing, handoff/result authority | 12,345 | Orchestrator | Handoff/result schemas and routing writer exist; actual model attestation is missing | RESOLVERIZE |
| `autonomous-remediation.md` | Eligibility for autonomous finding repair | 5,504 | Acceptance | Overlaps finding classification; load only at remediation decision | ON_DEMAND |
| `backlog-sync.md` | External Board scope and sync rules | 4,311 | Discovery, Refinement, Orchestrator | Board helpers exist; policy owns authorization boundary | ON_DEMAND |
| `capability-discovery.md` | Capability query and interpretation | 8,682 | Startup router | `Get-MxAgileCapabilities.ps1` is authoritative implementation | RESOLVERIZE |
| `commit-authority.md` | Git commit authorization and safety | 13,210 | Orchestrator | `git_index_integrity.py` covers index facts, not commit authority | ON_DEMAND |
| `consistency-check.md` | Mendix CE/consistency workflow | 1,508 | Implementation, Quality Gate | mxcli is execution authority | ON_DEMAND |
| `context-lifecycle.md` | Context Epoch/pressure/resume contract | 19,552 | Context subsystem | Duplicated by `docs/context-lifecycle.md`, schema, and checkpoint scripts; contains UNKNOWN/NORMAL contradiction | MERGE/DEDUP |
| `context-transition.md` | Compaction/epoch transition procedure | 12,670 | Context subsystem | Duplicated by `docs/context-transition.md`; transition resolver and hooks implement part | RESOLVERIZE |
| `credential-discovery.md` | Secret-source discovery/bootstrap | 13,907 | Acceptance, Discovery, UI, Orchestrator | Runtime route must select actual backend first; no secret values in state | ON_DEMAND |
| `design-contract-intake.md` | Design Contract identity and mapping | 30,960 | Discovery, Mocketeer, Refinement, TC | Many schema-backed identity rules; highly specific | ON_DEMAND |
| `development-runtime.md` | Runtime modes, lifecycle, readiness | 26,063 | Acceptance, Discovery, Implementation, UI, Orchestrator, Quality Gate | Overlaps runtime strategy/profile and command examples | MERGE/DEDUP |
| `evidence-contract.md` | Comparison identity, captures, promotion, storage | 19,854 | Acceptance, UI, System Check, Test Generate, Visual Verify | Focus should remain identity/capture/promotion/storage/retention; maturity duplicates Evidence Levels | SHORTEN |
| `evidence-levels.md` | Evidence maturity authority | 8,623 | Acceptance, Discovery, Refinement, UI, Orchestrator | Conflicts/overlaps with five-layer `verification-layers.md` vocabulary | KEEP |
| `execution-intent.md` | Session intent classification | 2,646 | Orchestrator | Startup routing; no standalone state transition helper | KEEP |
| `external-change-reconciliation.md` | Change-Set/watermark reconciliation authority | 8,343 | Startup router | `reconcile_external_changes.py` and `reconciliation_git.py` execute much of the algorithm | RESOLVERIZE |
| `gap-verification-repair.md` | GAP classification and repair authority | 17,763 | Acceptance, Implementation, Mocketeer, UI | Overlaps observation/finding/remediation pipeline | MERGE/DEDUP |
| `impact-resolution.md` | Finding-to-REQ/SPEC candidates and authority limits | 16,853 | Acceptance, Mocketeer, Refinement | `resolve_impact.py` resolves structured candidates, not mutation authority | RESOLVERIZE |
| `implementation-control.md` | Implementation item sequencing/control | 7,933 | Implementation, Gate-to-Ready | Checklist and process-state are structured | RESOLVERIZE |
| `intake-completeness.md` | Intake readiness check | 1,489 | Discovery | Intake-only | ON_DEMAND |
| `legacy-completion-reconciliation.md` | Historical wave/requirement completion classification | 21,517 | Orchestrator | Overlaps completion/release narrative; no single executable classifier | RESOLVERIZE |
| `lifecycle-resync.md` | Startup/resume state reconstruction | 26,858 | Startup router | State/schema sources exist; no deterministic end-to-end lifecycle resolver | RESOLVERIZE |
| `local-runtime-profile.md` | Project mxcli/runtime profile and browser target | 51,181 | Acceptance, Discovery, Implementation, UI, Orchestrator, Q, System, Test, Visual | Binary resolver returns path/source only; no capability/recipe output | RESOLVERIZE |
| `migration-dfc-to-mxagile.md` | DFC-AI migration procedure | 34,371 | Migration flow | Installer/bootstrap helpers; narrow consumer | ON_DEMAND |
| `mission-completion.md` | Completion hierarchy and phase continuation | 29,041 | Implementation, Orchestrator | Duplicates `lifecycle.yaml` and release checkpoint semantics | RESOLVERIZE |
| `mockup-analysis.md` | Mockup analysis procedure | 7,793 | UI, Discovery | Specific to Analyze mode | ON_DEMAND |
| `mockup-lifecycle.md` | Target revision/active-target rules | 12,518 | Acceptance, Implementation, Mocketeer, UI | `revision.schema`, `page.schema`, project-status builder | RESOLVERIZE |
| `mockup-materialization.md` | Render exact active target | 11,892 | UI | Specific visual/reference procedure | ON_DEMAND |
| `observe-before-mutate.md` | Pre-mutation parity/refinement gate | 8,388 | UI, Visual Verify | State fields exist; repeats parity dimensions/finding rules | RESOLVERIZE |
| `operating-mode.md` | Studio Pro/MCP/mxcli authority routing | 13,686 | Implementation, Orchestrator | Detector exists; policy reconstructs mode/tool route in prose | RESOLVERIZE |
| `ownership-guard.md` | Core/project artifact ownership | 6,531 | Orchestrator | Installer and injection contract encode some ownership facts | REFERENCE_ONLY |
| `parity-finding-reconciliation.md` | Observation, contract, scope, classification | 16,963 | Acceptance | Overlaps `gap-verification-repair`, `impact-resolution`, `autonomous-remediation` | MERGE/DEDUP |
| `platform-portability.md` | Cross-platform constraints | 7,712 | No direct agent ref | Relevant only for portability/porting tasks | ON_DEMAND |
| `project-compatibility.md` | Doctor diagnostics and compatibility | 19,404 | System Check, TC | `project_compatibility.py` owns deterministic doctor logic | RESOLVERIZE |
| `project-knowledge.md` | Canonical project artifact map and legacy artifact classification | 10,060 | UI | Overlaps legacy classification in `reconciliation.md` | MERGE/DEDUP |
| `project-release-checkpoint.md` | Project/release review trigger and completion | 24,899 | Orchestrator | Completion criteria also live in `mission-completion.md` and `lifecycle.yaml` | RESOLVERIZE |
| `reconciliation.md` | Core update, Discovery/Refinement, legacy artifact reconciliation | 13,070 | Acceptance, Orchestrator, System Check | Legacy artifact classification duplicates `project-knowledge.md`; not same as legacy completion | MERGE/DEDUP |
| `representative-fixture-contract.md` | Fixture semantics/readiness | 10,650 | No direct agent ref | Narrow runtime/acceptance prerequisite; schema/data checks only partial | ON_DEMAND |
| `runtime-startup-recovery.md` | Bounded startup failure recovery | 18,358 | Acceptance, Implementation, UI | Only needed after selected runtime fails | ON_DEMAND |
| `runtime-strategy.md` | Local-first vs Docker routing intent | 8,032 | Acceptance, UI, Orchestrator, Q, Visual | Overlaps runtime profile and development runtime command guidance | SHORTEN |
| `safety-rules.md` | Universal safety plus controlled recovery | 10,830 | Most agents | Always-on kernel is mixed with rare recovery procedure | SHORTEN |
| `scss-engineering.md` | SCSS implementation patterns | 8,676 | Implementation, UI | Styling-specific | ON_DEMAND |
| `source-priority.md` | Concern-specific source authority/conflict table | 9,521 | Discovery, Implementation, Mocketeer, UI, Orchestrator, Gate-to-Ready | `mxagile-project.schema` validates declarations; no resolver output | RESOLVERIZE |
| `spa-mockup-bundle.md` | SPA bundle/revision handling | 9,193 | UI | Bundle-only concerns | ON_DEMAND |
| `test-contract-derivation.md` | TC/PP derivation rules | 8,865 | Test Contract skill | Schema validates structure; layer defaults duplicate `verification-layers` | RESOLVERIZE |
| `test-defect-protection.md` | Test vs application vs infrastructure classification | 10,576 | Acceptance, Test Generate | Classification and escalation rules partly overlap materialization | ON_DEMAND |
| `test-harness-cleanup.md` | Cleanup boundaries for test workspaces | 4,278 | No direct agent ref | Test-harness-only | ON_DEMAND |
| `test-identity-lifecycle.md` | Bootstrap vs requested role identity | 10,030 | Acceptance, Discovery, UI | Identity lifecycle is a distinct late runtime gate | ON_DEMAND |
| `test-staleness.md` | TC/PP/VPL staleness and action mapping | 8,003 | Acceptance, TC | Duplicates materialization action table | MERGE/DEDUP |
| `test-workflow.md` | Test execution choices | 2,256 | No direct agent ref | Harness-specific testing procedure | ON_DEMAND |
| `tool-instruction-conflict.md` | Tool/config authority precedence | 3,992 | A, D, I, UI, Q, System, Test Generate | Short universal pre-tool invariant plus detailed conflict procedure | SHORTEN |
| `ui-element-selection.md` | Pattern-to-widget selection | 15,913 | UI, Gate-to-Ready | Widget-choice procedure only | ON_DEMAND |
| `ui-parity.md` | Seven-dimension parity kernel, statuses, aggregation, procedures | 34,824 | UI, System, Visual Verify | Schema covers shape/identity, not all cross-field aggregation | SHORTEN |
| `update-contract.md` | Post-Core-update synchronization and same-session re-read | 13,643 | No direct agent ref | Update installer writes handoff; startup block routes here | ON_DEMAND |
| `user-orientation.md` | Fresh project/user orientation | 8,032 | Orchestrator | Only no prior state or explicit orientation request | ON_DEMAND |
| `verification-gap-taxonomy.md` | TC/PP/fixture/evidence gap classification | 8,887 | Discovery | Gap/action mappings overlap materialization and staleness | RESOLVERIZE |
| `verification-layers.md` | STATIC/MODEL/BUILD/RUNTIME/FRONTEND and security dimensions | 6,653 | Acceptance, VPL | Duplicates maturity in Evidence Levels; schema owns allowed enum | MERGE/DEDUP |
| `verification-materialization.md` | PRESERVE/EXTEND/REASSESS/REMATERIALIZE/REEXECUTE/INVALIDATE | 12,296 | Acceptance, VPL | Canonical action authority; duplicated in staleness/taxonomy | RESOLVERIZE |
| `verification-scenario.md` | Role/data/viewport scenario construction | 10,972 | UI | Scenario schema validates structure; procedure is on demand | ON_DEMAND |

`SOURCE` means canonical policy source. Per-policy generated duplicates: none; installer Core copies are managed Core payloads, and platform projections point at agent/skill sources rather than compiling each policy into a new authority. Policy files can still be inlined by a skill/agent/harness when explicitly read; the benchmark log only proves the file reads listed above.

## 6. Resolver and Structured Contract Inventory

| Existing authority/contract | Executable today | What it resolves | Missing boundary / caveat |
|---|---|---|---|
| `.mxagile/capabilities.yaml` + `capabilities.schema.json` + `Get-MxAgileCapabilities.ps1` | Yes | Core capability config, current-session Harness markers, Context Mode installation/tools/health when actually observed | Adapter `supported` is declarative; each capability needs explicit `configured` vs `runtime_attested` state. Delegation model alias mapping currently returns `resolved_model` without proving the chosen runtime model. |
| `harness-adapter.schema.json` + per-harness adapter YAML | Partial | Adapter capability/configuration declarations | Schema has no universal `attestation_state`/`observed_at` field separating docs/config from current-run evidence. |
| Delegation Handoff/Result schemas + `Save-MxAgileRoutingDecision.ps1` / result writer | Yes | Bounded task, scope, fingerprints, requested profile, fallback/result state | Existing `model_resolution` fields describe static mapping/request/fallback; add no second schema until current output is extended with observed model and attestation provenance. |
| `Resolve-MxAgileMxcli.ps1` | Yes | Project-declared/local executable path and source; blocks unauthorized PATH fallback | Does not resolve mxcli version, runtime capabilities, backend options, DB identifier syntax, or a full argument array. |
| `check-studio-pro-status.ps1` + `operating-mode.md` | Partial | Read-only process/project association | Script emits JSON facts; policy maps facts to mode and tool authority. No shared structured `operating_mode/tool_authority` output. `Get-MxAgileTransitionCapabilities.ps1` can infer Claude from settings-file presence, which is configuration evidence, not current-session attestation. |
| `Get-MxAgileContextPressure.ps1` + `Get-MxAgileModelPolicy.ps1` | Yes | Measured pressure and configured model/window thresholds | No reliable local request/token read ledger. `context-lifecycle.md` contradicts its own UNKNOWN rule by saying no measurement means NORMAL. |
| Context epoch schema + Read/Write/Sync/Rollover/Pre/Post-Compaction helpers | Yes, feature/config conditional | Checkpoint shape, preservation, transition preparation and re-sync | Narrative 17-step/state-machine logic remains duplicated in docs/policy/scripts; hook execution and policy reattachment require runtime evidence. |
| `.mxagile/lifecycle.yaml`, `mission-state.schema.json`, `process-state.schema.json`, `context-epoch.schema.json` | Structured state | Wave phase/gates, mission completion criteria, prerequisite state, evidence/checkpoints | Multiple distinct scopes are legitimate, but `mission-completion`, release checkpoint, orchestrator and context docs restate transitions. No single full lifecycle resolver. |
| `resolve_impact.py` + `build_artifact_index.py` | Yes | Page/REQ/SPEC/scenario/task trace candidates, freshness/fingerprint | Returns candidates/facts only; policy retains mutation/user-authority decisions. This is the right boundary. |
| `reconcile_external_changes.py` + `reconciliation_git.py` + reconciliation-state schema | Yes | Worktree/commit change-set, watermark, impact candidates, safety checks | Do not duplicate its algorithm in natural-language reconciliation policies. |
| `project_compatibility.py` + artifact schemas | Yes | Deterministic Doctor compatibility diagnostics and safe-repair classification | It is diagnostic, not lifecycle authority; completion docs must not duplicate doctor decision logic. |
| `build_project_status.py` + `project-status.schema.json` | Yes | Read-only board/status projection, evidence/freshness counts | Explicitly returns operating mode/capabilities unavailable; it does not resolve session authority. |
| `tests/run-impact-tests.py` | Yes | Changed-path to regression suites/tier | Test-runner authority only. It does not resolve project verification gaps/actions. |
| Verification Contract/VPL/Scenario/Parity/Evidence schemas | Validation | Artifact shape, enums, identity and traceability fields | No unified `resolve_verification_gap -> action -> layers -> fixture/identity -> materialization` executable. Schema descriptions do not enforce every cross-field rule. |
| Source authority in `mxagile-project.schema.json` | Validation only | Allows concern values for ui_visual/ui_interaction/navigation/business_logic/data_rules | No resolver returns winning sources, applied declarations, provenance and conflict state; agents reconstruct `source-priority.md`. |

**Resolver principle:** reuse these contracts first. Do not create a second runtime/lifecycle/model authority. Extend the owning helper/output or add only an ephemeral result shape where current schemas have no suitable state. Persist new state only if existing lifecycle/mission schema lacks a field required for durable decisions.

## 7. Runtime Cluster Finding

### Reality recipe and existing knowledge

At the CapTrack snapshot, framework policy recorded Core `db_name = "default"`, required project-local mxcli path/version and command-specific help, and separately discussed local `db_type`. Its canonical autonomous examples used `--db-name default`; the user-reported current CapTrack mxcli help exposed `--dbname default`. This is a versioned CLI spelling mismatch, not a reason to hard-code either spelling as eternal Core syntax.

The project-local `Resolve-MxAgileMxcli.ps1` resolves binary path/source only. The consumer assembled the start command from fragments, so local HSQLDB was selected but the DB identifier was omitted. The complete recipe was not one data object handed to the executing agent.

### Observed runtime route

| UTC time | Evidence |
|---|---|
| 08:20:13 | Assistant text first mentions PostgreSQL. |
| 08:29:29 | Assistant invokes `mxcli help run`. |
| 08:31:09 | Local/detached HSQLDB invocation, no DB-name option. |
| 09:10:06–09:10:48 | Non-local `mxcli run`/AfterStartup investigation. |
| 09:11:34 | Another local/detached HSQLDB invocation, no DB-name option. |
| 09:12:40 | User supplies the missing `--dbname default` hint. |
| 09:13:19 | Logged local invocation includes `--db-name default`; the transcript does not use the exact user-reported `--dbname` spelling. |

The transcript does not prove that the logged `--db-name` syntax was accepted or that the expected DB was selected; the user-reported working `--dbname` recipe is kept as authoritative reality evidence, with the transcript spelling discrepancy marked `NOT_OBSERVABLE`/unresolved. Post-start fixture and role gaps remain separate from backend startup.

`AVOIDABLE_WORKFLOW_BRANCH = JA`: direct HSQLDB starts without the required identifier precede the user correction, and an AfterStartup investigation occurs before the complete recipe is handed over. No attributable cost for that branch is available. The branch is a real workflow inefficiency, not proof that the entire 21.5h session was waste.

## 8. Reality Benchmark: CAPTRACK_REGIONS_2026-11-02

### User/provider report

| Model | Input | Output | Cache Read | Cache Write | Cost |
|---|---:|---:|---:|---:|---:|
| Opus 4.6 | 4.1k | 36.4k | 5.5m | 212.5k | $4.99 |
| Sonnet 4.6 | 20.1k | 356.1k | 55.1m | 1.9m | $28.96 |
| **Total** | — | — | — | — | **$33.95** |

API duration 2h 50m 44s; wall duration 21h 30m 54s. The cost split is not evidence of automated model routing. Main model changes were user-controlled.

### Transcript-derived, commit-bounded metadata

Bound: campaign commit timestamp `2026-11-02T10:50:55Z`; post-commit analysis turns excluded.

- Main: 262 unique API request IDs through cutoff; Opus 24 requests, Sonnet 238. Main model provenance is `USER_CONTROLLED`.
- Children: 13 direct depth-1 fork transcripts, 349 unique API request IDs. All 13 definitions request `model: inherit`; actual model was Opus for 8 and Sonnet for 5, matching Main's model at spawn. No Child invocation carried `model`, `profile`, or `model_profile` input fields.
- Compaction: 2 Main markers (preTokens 167,509 and 167,444); 4 Child markers in two Sonnet forks (175,675; 175,012; 169,980; 167,233).
- Direct child handoffs: 13, 18,277 UTF-8 bytes total. Child result returns: 13, 14,846 bytes total. Handoffs are much smaller than the inherited context.
- Fork cache reads: 35.25m transcript-recorded tokens; Main cache reads: 25.55m. Forks account for about 58% of transcript cache reads. This is context inheritance, not a model cost attribution.
- Tool counts through cutoff: Bash 411, Context Mode 81 (48 batch execute, 17 execute, 9 execute-file, 6 search, 1 doctor), direct Read 43, Agent calls 26 in all logs. Thirteen are Main-to-child invocations. Each direct child log has one `Agent` tool result saying “Fork started — that fork is you”; no distinct grandchild transcript exists, so those 13 are not counted as extra child agents.
- Direct Read: 43 calls across 29 distinct files, 182,013 result bytes. Repeated project reads include the regions page inventory and `FINDINGS.md` (4 calls each, across 3 transcripts). This is a concrete repeated-read signal, not proof every repeated read was unnecessary.
- Context Mode returned 550,728 UTF-8 bytes; Bash returned 385,392 bytes. These outputs may overlap with direct reads and are not additive unique-context bytes.
- Main returned 13 fork result blocks, approximately 1.1k chars each. Child generation was much larger than the compact result delivered to Main; transcript output and provider usage are separate measures.

Provider-reported usage and deduplicated JSONL `message.usage` sums do not reconcile exactly, especially uncached input and output. Provider totals are used for billing; per-agent dollars and cost-per-dimension are `NOT_OBSERVABLE`. Do not calculate cost per line or infer routing quality from the Sonnet/Opus cost ratio.

### Load/failure findings from this campaign

- Startup instructions are present by the Claude harness contract, but the transcript does not record an `InstructionsLoaded` event for every file. Session-start automatic instruction content is reconstructed from the committed `CLAUDE.md`/`AGENT.md` and official Claude load rules, not from a per-request byte trace.
- One explicit `Read` of `external-change-reconciliation.md` returned 1,806 bytes. Bash read/search commands naming `external-change-reconciliation.md`, `local-runtime-profile.md`, `ui-parity.md`, and `update-contract.md` returned 7,499; 1,960; 3,266; and 15,807 bytes respectively. `update-contract.md` also had one Context Mode file-route return of 2,954 bytes. These may be excerpts; do not claim each was a full-body load.
- `development-runtime.md`, `credential-discovery.md`, `runtime-strategy.md`, and `runtime-startup-recovery.md` are not shown as direct file-read paths in the saved tool log. User-provided Reality Evidence names the PostgreSQL/MB_SSO branch; exact policy-read order and the full credentials question exchange are `NOT_OBSERVABLE`.
- Local Copilot store has no matching CapTrack commit/recipe turn and no token/cache event table. The Claude log is the only direct benchmark session source located.
- The Claude log contains the user's campaign/commit marker and one child metadata record without `finished: true`; parent result is non-error. Completion for that child metadata is `NOT_OBSERVABLE`, not presumed failed.

### User-visible value and normalization

One committed workpackage reached a partial verification outcome: target/revision updated; structure/content and AppAdmin read-only verified; CAP_Ceko and E2 remain fixture-blocked. The provider cost covers the whole manual-model-switching session and additional integrated framework/project work. Therefore:

- `cost per completed workpackage`: not comparable enough to calculate.
- `cost per successfully verified dimension`: not attributable to a complete billing denominator.
- User escalations: one recipe correction is directly identified; total user-escalation count for the whole wall duration is `NOT_OBSERVABLE` here.
- Lines changed: provider report `+1,213/-1,474`; commit `+5,984/-5` across 7 files. Definitions/scope differ; no cost-per-line metric.

## 9. Lifecycle, Verification, Source, and Finding Redundancy

### Lifecycle and mission completion

`lifecycle.yaml` is the machine-readable wave/phase/gate definition. `process-state.schema.json` holds per-wave state; `mission-state.schema.json` holds user mission criteria and blockers; `context-epoch.schema.json` holds resume/evidence context. These are different scopes, not candidates to merge into one monolithic document.

Redundant prose exists between `lifecycle-resync.md`, `orchestrator.md`, `mission-completion.md`, `project-release-checkpoint.md`, `context-lifecycle.md`, `docs/context-lifecycle.md`, and `context-transition.md`/`docs/context-transition.md`. `context-lifecycle.md` is explicitly disabled by default, while the general product Lifecycle Re-Sync is still a startup contract; those must not be conflated. `project_status.py` is a projection, not a lifecycle authority, and reports operating mode/capabilities as unavailable.

A direct contradiction exists: `context-lifecycle.md` says UNKNOWN means no measurement and cannot authorize rollover, but its threshold section later says “Agent meldet NORMAL wenn keine Messung verfügbar ist.” `Get-MxAgileContextPressure.ps1` returns UNKNOWN without a real measurement. Keep UNKNOWN as authority and resolve the prose contradiction in a future approved wave.

### Verification and evidence

- `evidence-levels.md` defines STATIC/MODEL/BUILD/RUNTIME/BROWSER.
- `verification-layers.md` defines STATIC/MODEL/BUILD/RUNTIME/FRONTEND and maps BROWSER to FRONTEND.
- `verification-plan.schema.json` accepts the latter enum; both policies repeat semantics. One maturity authority should own definitions; the other should own only the domain mapping/security dimensions.
- `verification-materialization.md` is the best existing action authority for PRESERVE/EXTEND/REASSESS/REMATERIALIZE/REEXECUTE/INVALIDATE. `test-staleness.md` repeats the action table and distinctions; `verification-gap-taxonomy.md` repeats mappings such as EVIDENCE_STALE→REEXECUTE. `verification-plan.schema.json`, `test-contract.schema.json`, and `verification-scenario.schema.json` already encode the artifact shapes and allowed layer values.
- `parity-verification.schema.json` enforces dimensions, statuses, identity fields and capture structure. Its descriptions and `ui-parity.md` duplicate aggregation semantics; no shared aggregation resolver was found in the scripts inventory. Keep `ui-parity.md` as one kernel policy, not ten new policies; use schema/executable validation for completeness and cross-field aggregation, and load reverse/fresh-full/interaction procedures only when needed.
- `evidence-contract.md` already centers comparison identity, capture groups, promotion and storage. Remove any duplicated evidence-maturity mapping only after its status/source is proven in the evidence-level authority.
- GAP flow repeats observe → classify → reconcile → authorize → mutate → reverify across `observe-before-mutate`, `parity-finding-reconciliation`, `gap-verification-repair`, `autonomous-remediation`, and `impact-resolution`. The process-state fields and Finding schema are machine-readable, but the whole disposition pipeline is not executed by one resolver. `reconcile_external_changes.py` is an existing deterministic authority and should not be weakened or copied.

### Source authority and project knowledge

`mxagile-project.schema.json` already validates five `source_authority` concerns. `source-priority.md` provides the resolution matrix, but no resolver returns applied declarations, company/core fallback, decision overrides, winning source, provenance, and conflict state. Do not add a competing authority schema before extending the project config/resolver boundary.

`project-knowledge.md` classifies durable project knowledge; `reconciliation.md` repeats a Legacy Artifact Classification table. Deduplicate that classification at one authority. Keep distinct from `legacy-completion-reconciliation.md`, which classifies historical lifecycle completion. Preserve the current identity contract: `page_id` stable, `page_name` mutable Mendix binding, filename convention only. `page.schema.json` encodes this, but old `<PageName>.yaml` path examples remain in `project-knowledge.md` and should not be treated as authority.

## 10. Policy Dependency / Load Matrix

Policy-source sizes are exact current working-tree bytes. Static consumer references are routing evidence only, not actual load evidence. `STARTUP` means the managed startup block explicitly requires/conditionally routes it. Otherwise a file is on demand unless the selected harness or a matching agent/skill loads it.

| Policy | B | Purpose / declared consumers | Load/overlap and executable equivalent | One primary recommendation |
|---|---:|---|---|---|
| `acceptance-campaign.md` | 5,888 | Campaign kinds/gates; Acceptance/VPL | Acceptance-only; schemas provide shape | ON_DEMAND |
| `agent-delegation.md` | 12,345 | Main/child routing; startup/Orchestrator | Existing handoff/result/routing schemas and save/read scripts; runtime model attestation absent | RESOLVERIZE |
| `autonomous-remediation.md` | 5,504 | Finding repair permission; Acceptance | Overlaps finding disposition | ON_DEMAND |
| `backlog-sync.md` | 4,311 | Board context/scope; Discovery/Refinement/Orchestrator | Board helpers; authority remains policy | ON_DEMAND |
| `capability-discovery.md` | 8,682 | Optional capability query; startup | `Get-MxAgileCapabilities.ps1` is executable owner | RESOLVERIZE |
| `commit-authority.md` | 13,210 | Commit permission; Orchestrator | Git index guard covers integrity, not authority | ON_DEMAND |
| `consistency-check.md` | 1,508 | Mendix CE workflow; Implementation/Q | mxcli performs checks | ON_DEMAND |
| `context-lifecycle.md` | 19,552 | Context Epoch, pressure, resume | Duplicate `docs/context-lifecycle.md`; schemas/helpers partially execute | MERGE/DEDUP |
| `context-transition.md` | 12,670 | Compaction/epoch procedure | Duplicate `docs/context-transition.md`; transition/checkpoint helpers | RESOLVERIZE |
| `credential-discovery.md` | 13,907 | Secret-source/bootstrap; A/D/UI/O | Route-specific credential discovery; depends on runtime recipe | ON_DEMAND |
| `design-contract-intake.md` | 30,960 | DC identity/mapping; D/Refinement/Mocketeer/TC | Schema-backed identity constraints; narrow consumer | ON_DEMAND |
| `development-runtime.md` | 26,063 | Runtime modes/readiness; A/D/I/UI/O/Q | Duplicates runtime strategy/profile command/state prose | MERGE/DEDUP |
| `evidence-contract.md` | 19,854 | Identity/capture/promotion/storage; A/UI/Visual | Evidence maturity overlaps `evidence-levels.md` | SHORTEN |
| `evidence-levels.md` | 8,623 | Evidence-maturity authority; A/D/Refinement/UI/O | Duplicates the layer descriptions in `verification-layers.md` | KEEP |
| `execution-intent.md` | 2,646 | User intent classification; Orchestrator | Startup routing; no standalone resolver | KEEP |
| `external-change-reconciliation.md` | 8,343 | Change-set/watermark authority; STARTUP | `reconcile_external_changes.py`/`reconciliation_git.py` | RESOLVERIZE |
| `gap-verification-repair.md` | 17,763 | GAP class/repair permission; A/I/Mocketeer/UI | Overlaps observation/finding/remediation pipeline | MERGE/DEDUP |
| `impact-resolution.md` | 16,853 | Finding→REQ/SPEC candidate; A/Mocketeer/Refinement | `resolve_impact.py` resolves facts, not mutation authority | RESOLVERIZE |
| `implementation-control.md` | 7,933 | Checklist execution; I/Gate-to-Ready | Checklists/process-state are structured | RESOLVERIZE |
| `intake-completeness.md` | 1,489 | Intake readiness; D | Intake-only | ON_DEMAND |
| `legacy-completion-reconciliation.md` | 21,517 | Historical lifecycle scope; Orchestrator | No single deterministic classification resolver | RESOLVERIZE |
| `lifecycle-resync.md` | 26,858 | Startup/resume reconstruction; STARTUP/O | Schemas/store helpers exist, but no full lifecycle resolver | RESOLVERIZE |
| `local-runtime-profile.md` | 51,181 | mxcli/runtime/browser profile; A/D/I/UI/O/Q/Visual | Binary resolver is path-only; no capabilities/recipe result | RESOLVERIZE |
| `migration-dfc-to-mxagile.md` | 34,371 | DFC migration procedure | Migration-only helpers; legitimate long reference | ON_DEMAND |
| `mission-completion.md` | 29,041 | Completion hierarchy/continuation; I/O | Duplicates lifecycle and release-checkpoint semantics | RESOLVERIZE |
| `mockup-analysis.md` | 7,793 | Mockup Analyze procedure; UI/D | Analyze-only | ON_DEMAND |
| `mockup-lifecycle.md` | 12,518 | Active target/revision; A/I/Mocketeer/UI | `revision.schema`, `page.schema`, status builder | RESOLVERIZE |
| `mockup-materialization.md` | 11,892 | Render exact target; UI | Specific visual procedure | ON_DEMAND |
| `observe-before-mutate.md` | 8,388 | Pre-UI-mutation gate; UI/Visual | Process-state stage exists; repeats parity/finding rules | RESOLVERIZE |
| `operating-mode.md` | 13,686 | Studio Pro/MCP/mxcli route; I/O | `check-studio-pro-status.ps1` yields facts, policy maps authority | RESOLVERIZE |
| `ownership-guard.md` | 6,531 | Core/project ownership; O | Installer/injection contracts overlap | REFERENCE_ONLY |
| `parity-finding-reconciliation.md` | 16,963 | Observation/interpretation/scope; A | Overlaps GAP repair, impact and remediation | MERGE/DEDUP |
| `platform-portability.md` | 7,712 | Porting constraints | No direct agent ref; cross-platform only | ON_DEMAND |
| `project-compatibility.md` | 19,404 | Doctor semantics; System/TC | `project_compatibility.py` executes diagnostic rules | RESOLVERIZE |
| `project-knowledge.md` | 10,060 | Canonical artifact map/legacy classification; UI | Legacy classification overlaps reconciliation | MERGE/DEDUP |
| `project-release-checkpoint.md` | 24,899 | Project/release checkpoint; O | Completion levels overlap mission-completion/lifecycle | RESOLVERIZE |
| `reconciliation.md` | 13,070 | Core/Discovery/Refinement reconciliation; A/O/System | Legacy artifact classification overlaps project-knowledge | MERGE/DEDUP |
| `representative-fixture-contract.md` | 10,650 | Fixture semantics/readiness | Narrow runtime/acceptance prerequisite | ON_DEMAND |
| `runtime-startup-recovery.md` | 18,358 | Failure-only runtime recovery; A/I/UI | Recovery procedure, not startup kernel | ON_DEMAND |
| `runtime-strategy.md` | 8,032 | Local-first/Docker intent; A/UI/O/Q/Visual | Duplicates runtime profile/modes | SHORTEN |
| `safety-rules.md` | 10,830 | Universal safety + controlled recovery; most agents | Always-on and rare recovery detail mixed | SHORTEN |
| `scss-engineering.md` | 8,676 | SCSS specifics; I/UI | Styling-only | ON_DEMAND |
| `source-priority.md` | 9,521 | Concern authority; D/I/Mocketeer/UI/O/Gate | Schema config exists, no winner/provenance/conflict resolver | RESOLVERIZE |
| `spa-mockup-bundle.md` | 9,193 | SPA bundle details; UI | Bundle-specific | ON_DEMAND |
| `test-contract-derivation.md` | 8,865 | TC/PP derivation; TC skill | Schema validates; repeats layer defaults | RESOLVERIZE |
| `test-defect-protection.md` | 10,576 | Test/app/infrastructure distinctions; A/Test Generate | On failure only; overlaps materialization | ON_DEMAND |
| `test-harness-cleanup.md` | 4,278 | Test cleanup | Test-harness-only | ON_DEMAND |
| `test-identity-lifecycle.md` | 10,030 | Initial login vs requested role; A/D/UI | Late runtime gate | ON_DEMAND |
| `test-staleness.md` | 8,003 | TC/PP/VPL staleness; A/TC | Repeats materialization action mapping | MERGE/DEDUP |
| `test-workflow.md` | 2,256 | Test execution procedure | Test-only | ON_DEMAND |
| `tool-instruction-conflict.md` | 3,992 | Tool/source precedence; A/D/I/UI/Q/System/TC | Startup requires before CLI; retain short invariant, move long arbitration to resolver | SHORTEN |
| `ui-element-selection.md` | 15,913 | Pattern→widget; UI/Gate-to-Ready | Widget decision only | ON_DEMAND |
| `ui-parity.md` | 34,824 | Seven dimensions/status/aggregation/procedures; UI/System/Visual | Schema covers shape, not all cross-field aggregation | SHORTEN |
| `update-contract.md` | 13,643 | Post-update contract resync | Installer handoff, only after update | ON_DEMAND |
| `user-orientation.md` | 8,032 | Fresh/orientation; O | No prior lifecycle state or user asks how | ON_DEMAND |
| `verification-gap-taxonomy.md` | 8,887 | Coverage/binding/evidence/fixture gap types; D | Gap→action mapping repeats materialization/staleness | RESOLVERIZE |
| `verification-layers.md` | 6,653 | Layer/security-dimension semantics; A/VPL | Five-layer names duplicate evidence maturity | MERGE/DEDUP |
| `verification-materialization.md` | 12,296 | Impact action authority; A/VPL | Canonical actions, duplicates in staleness/taxonomy | RESOLVERIZE |
| `verification-scenario.md` | 10,972 | Role/data/viewport scenario; UI | Scenario schema validates structure; full procedure is specific | ON_DEMAND |

`ON_DEMAND` is not a statement that a policy body was observed in the CapTrack session. It is the intended bundle routing. A full-size policy read is counted only where the actual tool event proves it.

## 11. Target Architecture

### Minimal Consumer Kernel

Every mission needs only: current user objective/scope, project root and safety boundary, one authoritative lifecycle/resume position, current tool authority/capability state with evidence source, open blocker/next step, and an explicit rule that unavailable evidence is not PASS. Keep universal safety invariants here; do not include recovery recipes, parity procedure, migration steps, or release tables.

### Capability/Resolver Layer

Use existing structured owners first:

1. `Get-MxAgileCapabilities.ps1` remains the current-session capability entrypoint; distinguish configured/declarative values from attested runtime facts in its existing output.
2. Resolve a structured `operating_mode/tool_authority` once from `check-studio-pro-status.ps1` evidence plus `operating-mode.md`; consumers consume it. Do not infer a healthy MCP route from adapter presence.
3. Extend the existing project-local mxcli resolver boundary: capability evidence (absolute path/version/help), complete resolved recipe, route/status, expected DB identity. The policy remains normative; no competing runtime authority.
4. Reuse lifecycle schemas/helpers for phase/mission/epoch; provide a deterministic transition/completion result rather than reimplementing state machines in agents.
5. Reuse verification schemas and `resolve_impact.py` facts; centralize gap/action/layer/fixture/identity decisions into one resolver result only after mapping the existing schemas. Keep product/finding authorization policy normative.
6. Reuse `project_compatibility.py`, `reconcile_external_changes.py`, `reconciliation_git.py`, and `run-impact-tests.py`; do not recreate their algorithms.
7. Add runtime attestation as an evidence field/provenance in existing delegation/capability output. `configured: supported` and `runtime_attested: observed` must never be conflated. Main model control provenance must allow `USER_CONTROLLED`; child requested/inherited model and actual model are separate.

### Mission Bundles

| Bundle | Load when | Core content |
|---|---|---|
| Runtime | Runtime/browser evidence required | Tool authority, project-local mxcli capability, full recipe, readiness/failure layers; credentials, fixture, identity and SSO only at their stage. |
| UI/Parity | UI baseline, parity, or mutation | Seven-dimension kernel + immutable identity; load fresh-full, reverse parity, interaction and capture procedure only when in scope. |
| Acceptance | Acceptance campaign selected | TC/VPL status and evidence sufficiency; fixture/identity/browser procedures conditional on proof points. |
| Migration | DFC-AI artifacts detected or explicit migration | Migration guide + migration agent; no startup preload. |
| Release | Feature scope reaches release checkpoint or user asks readiness | Completion/release resolver result + selected review profile. |
| Recovery | Specific Git integrity/runtime/startup failure | Safety kernel always; detailed controlled recovery only for the corresponding failure. |
| External change | Valid Git baseline/watermark and change reconciliation required | Structured change-set helper/result, then only affected project authorities. |

### On-Demand Reference Policy

Move examples, historical reality narratives, tool-specific troubleshooting, and large procedure details behind concise kernels or dedicated reference pages. Keep one canonical authority for each decision vocabulary; compiled projections remain generated, never counted as new sources.

## 12. Wave Plan, Risks, and Regression Selection

The evidence confirms C0 first, but adjusts C1/C2 dependency: Runtime Recipe needs an already resolved tool authority. Build a minimal machine-readable authority result before the recipe consumer, then implement the runtime recipe as the first high-reality consumer.

| Wave | Priority and causal overhead in this benchmark | Existing regression candidates (not run) |
|---|---|---|
| **C0 Instrumentation** | First. Persist source/projection/load events, exact bytes, file-read hashes/counts, Context Mode output sizes, handoff/result sizes, compaction IDs/tokens, requested-vs-actual model and manual override provenance. This session could be measured only because local Claude logs happened to exist. | `test-injection-contract.ps1`, `test-managed-block.ps1`, `test-platform-portability.ps1`, `test-agent-delegation.ps1`; add focused telemetry fixtures only after approval. |
| **C2 minimal Operating Mode authority** | Precondition to C1: consumers currently interpret process detection and tool routing from prose; ensure `LIVE-SP-CURRENT` cannot fall back to mxcli after MCP failure. | `test-operating-mode-detection.ps1`, `test-capability-discovery-routing.ps1`, `test-agent-delegation.ps1`. |
| **C1 Runtime Recipe** | Highest direct reality: two HSQLDB starts omit the default DB identifier; capability discovery, recipe handoff, invocation and state check must be separate. | `test-mxcli-runtime-resolution.ps1`, `test-local-runtime-profile.ps1`, `test-runtime-orchestration.ps1`, `test-runtime-strategy.ps1`, `test-runtime-startup-recovery.ps1`. |
| **C3 Lifecycle/Mission** | After C0/C2: startup block and long prose describe phase/mission completion alongside lifecycle, mission and context schemas; reduce repeated Re-Sync/continuation logic. | `test-startup-priority.ps1`, `test-session-bootstrap.ps1`, `test-context-epoch-schema.ps1`, `test-context-lifecycle-operational.ps1`, `test-context-transition-coordinator.ps1`, `test-legacy-completion-reconciliation.ps1`. |
| **C4 Verification decisions** | Centralize the observed multi-file policy mapping for gaps/actions/layers/fixture/identity; schema shape alone does not compute resolution. | `test-verification-gap-taxonomy.ps1`, `test-verification-lifecycle.ps1`, `test-verification-scenarios.ps1`, `test-ui-parity.ps1`, `test-scope-aware-verification.ps1`, `test-agent-delegation-results.ps1`. |
| **C4 Verification decisions** | Centralize the observed multi-file policy mapping for gaps/actions/layers/fixture/identity; add deterministic aggregate authority so smoke or Reference-vs-Model evidence cannot be promoted to full live parity without required dimensions, sufficiency, freshness, and comparison identity. | Existing candidates: `test-verification-gap-taxonomy.ps1`, `test-verification-lifecycle.ps1`, `test-verification-scenarios.ps1`, `test-ui-parity.ps1`, `test-scope-aware-verification.ps1`, `test-agent-delegation-results.ps1`; add the Regions smoke-only and no-live-runtime regression cases. |
| **C5 Source authority / Finding / Impact** | Reduce per-agent reconstruction of source-priority and repeated observe/classify/reconcile stages; retain authorization boundaries. | `test-impact-resolver.ps1`, `test-project-knowledge.ps1`, `test-legacy-completion-reconciliation.ps1`, `test-reconciliation-board.ps1`, `test_external_change_reconciliation.py`. |
| **C6 Policy deduplication / compaction** | Last, after resolvers establish authority and behavioral fixtures; shorten startup kernel, preserve procedures on demand, reconcile duplicate context docs and evidence-layer vocabulary. | `test-injection-contract.ps1`, `test-managed-block.ps1`, `test-platform-portability.ps1`, `test-context-lifecycle-golden-scenarios.ps1`, `test-verification-economics-regression.ps1`. |

Risks: changing layer vocabulary may invalidate existing VPLs; runtime DB option names vary by mxcli version; compaction/session hooks differ by harness; source authority can be project/Company-specific; legacy completion and legacy artifact classification are separate; forks can defeat bounded context even when their task prompt is compact; generated projection drift must be tested without treating projections as authorities.

## 13. Benchmark Comparison Contract

For each approved wave and a later comparable bounded UI/runtime/parity workpackage, capture the same measures:

- automatically injected instruction bytes by source and exact projection hash;
- loaded policy/skill/agent bodies and repeated reads, with READ vs search/reference distinction;
- Context Mode result bytes and source identity;
- unique provider request IDs, model, input/output/cache read/cache write, and cost when available;
- Main/Child identity, requested model/profile, actual model, route provenance, fork inheritance, handoff/result bytes, and completion state;
- compaction/resume count, checkpoint identity, and preTokens;
- completed workpackage, verified dimensions, fixture/identity blockers, user corrections/escalations, and commit;
- session index proxies (turns/file events) separately from provider token/cost data.

Do not treat cache reads as savings. Do not infer dollars from context bytes. Do not compare absolute costs without a comparable outcome. If completion or cost attribution differs, report `NOT_COMPARABLE`, not a normalized ratio.

## 14. Approval Boundary

**Phase 1 complete. No production policy, schema, resolver, hook, or CapTrack artifact was changed.** The only new artifact is this requested report. No tests, parity, runtime, or release gates were run.

```text
CONTEXT_ARCHITECTURE_BASELINE_COMPLETE = JA
IMPLEMENTATION_APPROVAL_REQUIRED = JA
STOP_FOR_APPROVAL = JA
```
