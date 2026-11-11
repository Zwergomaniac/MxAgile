### Implementation Follow-through (2026-11-05)

**Fixed in this run:** Task Inspect v2 now supports the six evidence-backed typed targets and a
lossless Doctor migration; `expect` may be absent/blank without schema invalidation, but Doctor
keeps semantic acceptance at `EXPECTATION_MISSING` / `DECISION_REQUIRED`. The C2 route now emits
structured `user_interaction`; the orchestrator and always-on router suppress a mode choice for
conclusive results and defer ambiguity questions to the rechecked mutation boundary. The Company Layer
flavor-transition UPDATE path now has direct regression coverage. Generic Mendix UserRole identity
guidance was committed across Implementation, UI, Acceptance, Maintainer, Brownfield, Builder Kit,
and Mocketeer producers. No Role.Name string, wildcard, or substring fallback is allowed.

**Consumer evidence (read-only):** Reference project reports installed Core version `1.10.0` / commit
`f62c57b10df2edd51f630aa96aef8ae8922c42df`. This predates commits `ff78c99`, `e3a535c`, and
`6717daa`; its installed Task schema/Doctor therefore remain stale until a normal Core update.
Board `/api/status` returned `BLOCKED` with 159 diagnostics (123 `UNASSIGNED`, 13 `SCHEMA_ERROR`,
9 `LEGACY_VARIANT`, 6 `WAVE_ASSIGNMENT_MISSING`, 4 `UNSUPPORTED_VARIANT`, 3 `MISSING`, 1
`FRESHNESS_UNKNOWN`); 13 Task schema errors align with the stale pre-Inspect contract. The same
read-only endpoint alternated between HTTP 200 and 503 `status_unavailable` / `RuntimeError`; no
server log exposing the underlying exception was available. Historical `/api/reference`,
`/api/capture`, `/api/diagnostic-source` paths return 404 because current Core routes are
`/reference/`, `/capture/`, and `/diagnostic-source/`. Reference project was not modified. Its Findings
directory is absent, so the Board's `findings: unavailable` / zero items is expected, not a
reproduced projection defect.

**Remaining blockers:**

- UserRole Identity is implemented as a framework contract and regression, but no project MPR is
  available here to run Mendix model validation for an invalid `%UserRole_<Name>%` token or a Role
  rename. This remains `PARTIALLY_FIXED` until a project-owned MPR/version check proves R1/R2.
- Board Runtime remains `PARTIALLY_FIXED`: Core route/cache contracts pass, but the live consumer
  status endpoint intermittently returns a generic 503 RuntimeError and no diagnostic server log
  is available. The stale consumer needs its normal Core update before a meaningful after-update
  comparison.
- Workspace root pollution remains `PARTIALLY_FIXED`: current helpers/policies route known
  screenshots and temporary workcopies to `.concord`/Temp and focused cleanup suites pass, but no
  current consumer run with traceable output paths reproduced the reported root-level artifacts.
- Child Model Runtime Reality remains `STILL_OPEN`: the current VS Code Copilot child interface
  exposes no host-attested actual child model/profile. The read-only Explore child spawned for this
  work had no requested model/profile and returned no runtime model metadata; requested/actual
  child model is `NOT_OBSERVABLE`, not inferred.
- Synthetic verification fixture vs. canonical domain authority remains `FIXED_CURRENT_MAIN`:
  existing Mocketeer and representative-fixture contracts distinguish design/mock data from
  business authority; no new schema was added.

**Focused verification:** `test-operating-mode-detection.ps1` 77/77; `test-capabilities-resolver.ps1`
38/38; `test-core-provenance.ps1` 75/75; `test_project_status.py` 85/85;
`test-role-access-semantics.ps1` 48/48; `test-injection-contract.ps1` 81/81;
`test-mocketeer-validation.ps1` 203/203; `test-documentation-consistency.ps1` 59/59;
`test-workcopy-hygiene.ps1` 50/50; `test-project-knowledge.ps1` 42/42;
`test_board_http.py` 13/13; and `test_board_performance.py -k p7` 3/3. The Full Release Gate was
interrupted during the earlier implementation sequence; its aggregate status remains
`INCOMPLETE`, not PASS, and no partial suite output is used as release evidence.

**Commits created:** `ff78c99` (typed Task Inspect and Role Identity contracts), `e3a535c`
(C2 zero-question consumer contract), and `6717daa` (Company Layer flavor update provenance regression).
The baseline/reconciliation update is a separate documentation change. No unresolved Child Model,
Board runtime, or root-pollution finding is included in a completed implementation commit.

No additional detector, parity, fixture, or finding resolver is planned.
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

Generated copies are not counted as additional normative authorities. Their bytes are counted only where the harness can inject their descriptions or bodies. The analysis used repository sources at `91e8cec`, the Example Project campaign commit `c34c4c285d4c91764b899286afd1767bb959c6aa`, Claude Code transcript metadata, the local Copilot session index, and current Claude/Copilot load documentation. The Example Project repository was inspected read-only; its pre-existing dirty files were left untouched.

Evidence labels used below:

- `OBSERVED`: recorded in a transcript, provider report, commit, file-access event, or measured byte count.
- `HARNESS CONTRACT`: documented harness behavior; not proof that a particular file appeared in an individual request.
- `DECLARED`: adapter/configuration says a capability is supported or requested.
- `NOT_OBSERVABLE`: the available logs do not establish the fact.

The local Copilot SQLite index has no per-event token/usage table and did not contain the Example Project campaign commit or recipe turns. Claude JSONL logs did contain the campaign. Provider usage remains authoritative for billed totals; transcript-derived token sums do not fully reconcile and are reported separately.

## 1. Load Graph

### Canonical source and projection

`.mxagile/` is the agent-agnostic Core source. `generate-mxagile-platform-skills.ps1` produces Claude/Copilot/Codex/Grok/OpenCode/Hermes skill projections and Claude agent projections. `apply-project-agent-instructions.ps1` injects the startup router as a managed block. `install-core.ps1` distributes Core files and runs the setup/generator path. Neither a generated file's presence nor the setup script itself proves that its full body is in a particular request.

The framework repository's root `CLAUDE.md` is **FRAMEWORK_DEVELOPMENT_ONLY**. It describes Core development and is not the consumer project's runtime instruction contract. `skillssource/AGENTS.md` is a project-knowledge router/template source, distinct from `.mxagile/` and from generated harness agents.

### Claude Code consumer session

| Classification | Example Project evidence and load behavior |
|---|---|
| `ALWAYS_LOADED` | Claude Code loads root `CLAUDE.md` and expands its `@AGENT.md` import. At campaign commit, `CLAUDE.md` was 13,296 bytes and `AGENT.md` 13,672 bytes. Replacing the 9-byte import directive yields about 26,959 bytes of project instruction content, including a 6,715-byte managed MxAgile startup block. User-level instructions are also in scope; current profile files measured 239 bytes (`~/.claude/CLAUDE.md`) and 460 bytes (`RTK.md`), but their exact campaign-time snapshot is `NOT_OBSERVABLE`. |
| `ALWAYS_LOADED` metadata | Claude's available skill descriptions and custom-agent descriptions contribute a listing/selection context. Example Project commit contains 87 project `SKILL.md` files: 1,399,522 body bytes and 20,645 description characters. Nine custom agents contain 142,799 body bytes and 1,037 description characters. Claude's description budget can truncate listings; exact descriptions delivered in each request are `NOT_OBSERVABLE`. |
| `ON_DEMAND` | Full skill bodies load on invocation/relevance. The campaign invoked `mxagile-visual-verification` once; its projected body is 13,690 bytes. The other 86 skill bodies were available but are not evidence of being loaded. |
| `ON_DEMAND` | Custom-agent bodies load when selected/spawned. The campaign's 13 children are Claude `fork` transcripts, not the generated MxAgile custom agents; their custom-agent bodies are not shown as invoked. |
| `GENERATED_PROJECTION` | The 12 generated MxAgile skills total 109,145 bytes in `.claude/skills/`; their descriptions total 935 characters. The nine custom-agent descriptions are 1,037 characters. These are projections of canonical `.mxagile/` bodies, not separate authorities. |
| `REFERENCE_ONLY` | Policy links in the startup block, agent bodies, and skills are routing instructions. A link is not evidence that the target policy was read. |

Claude's documented fork behavior is decisive here: a fork inherits the entire parent conversation/system/tools, while a non-fork subagent gets a fresh context and task handoff. Child cache reads therefore include inherited context; this is a measured context mechanism, not MxAgile model-profile routing. Project skill bodies and their reattachment after compaction have their own lifecycle; direct session evidence for exactly which skill text was reattached is `NOT_OBSERVABLE`.

### Copilot consumer session

VS Code Copilot automatically includes `.github/copilot-instructions.md` when the Copilot harness is selected. Custom instructions are additive and may include `AGENTS.md` or applicable `*.instructions.md`. Skills are progressive: discovery/description first, full `SKILL.md` body when relevant or explicitly invoked, then supporting resources only when referenced. Custom agent files become context when selected or spawned. At the Example Project commit, `.github/copilot-instructions.md` was 22,660 bytes; this was not the harness used for the Claude/Bedrock benchmark.

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
| Example Project `CLAUDE.md` at `c34c4c28` | 13,296 B | Contains startup block and `@AGENT.md` include. |
| Example Project `AGENT.md` at `c34c4c28` | 13,672 B | Expanded project instructions. |
| Effective project instruction source | about 26,959 B | `CLAUDE.md` with the 9-byte import directive replaced by `AGENT.md`; exact harness serialization not captured. |
| MxAgile managed startup block | 6,715 B | Exact managed block in Example Project `CLAUDE.md`; current Core script block is 6,702 B. |
| Generated Copilot instructions | 22,660 B | Separate harness projection; not loaded in the Claude benchmark. |
| Example Project project skills | 87 files / 1,399,522 B | All bodies on disk; not all bodies enter context. |
| Example Project project skill descriptions | 20,645 chars | Listing source size; exact post-budget descriptions delivered are `NOT_OBSERVABLE`. |
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
REALITY_BENCHMARK_ID: EXAMPLE_PROJECT_REGIONS_2026-11-02
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
- `SCN-REGIONS.yaml` records `overall_result: PARTIAL`; Findings and Change-Set were updated.
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
- The user-reported project-local `./mxcli help run` documented `--dbname default` for the actual Example Project binary, a different spelling from the policy example.

Observed active sequence: PostgreSQL was discussed at 08:20Z; `mxcli help run` was read at 08:29Z; an HSQLDB local invocation at 08:31Z omitted the DB identifier; another HSQLDB invocation at 09:11Z also omitted it; `AfterStartup` troubleshooting occurred around 09:10Z; the user supplied the missing `--dbname default` hint at 09:12Z. A later logged invocation included `--db-name default`, while the supplied Reality Evidence says the working binary option was `--dbname default`. This syntax discrepancy is unresolved in the saved transcript. The user reports that the HSQLDB runtime itself starts; the missing fixtures/identities are separate blockers.

**AVOIDABLE_WORKFLOW_BRANCH = JA.** Evidence: an external-DB-oriented diagnostic branch preceded capability resolution; logged local HSQLDB starts omitted the identifier; recipe completion followed a user correction. The logs do not support an attributable dollar amount or a claim that every PostgreSQL/SSO/AfterStartup investigation was unnecessary.

## 4. Load and Read Anatomy
### Verification/Parity Reality Fund (user-supplied, 2026-11-02)

**Evidence class:** `USER-SUPPLIED REALITY`; the underlying Example Project artifacts were not re-inspected as part of this audit update.

The Regions run first passed four minimum smoke checks: expected text fragments, Regions title, successful navigation, and presence of any edit control/action. That evidence was later promoted to `overall_result: PASS` for Regions parity even though complete Behavioral, Role, and Whole-Screen Visual parity had not been established. A separate Mockup-vs-Mendix-Model analysis was also initially described as complete SOLL/IST parity while live-runtime evidence was still absent.

This is a resolver/authority failure, not a request for an ad-hoc parity patch. It sharpens the existing C4 design target:

- Keep `SMOKE` as its own evidence class. Navigation, text, and edit-control smoke may pass while full parity remains `NOT_VERIFIED` or `PARTIAL`; smoke alone can never produce parity `PASS`.
- Preserve structured dimension results separately, at minimum: `Contract`, `Model`, `Structural/Runtime`, `Behavioral`, `Role`, and `Whole-Screen Visual`.
- Derive the aggregate deterministically from the required dimensions, evidence sufficiency, freshness, and reference/comparison identity. Missing required evidence must resolve to `NOT_VERIFIED` / `PARTIAL`, never an agent-authored `PASS`.
- Label reference-vs-model analysis as such. It is not a live-runtime parity result and cannot satisfy runtime-dependent dimensions by implication.
- Treat `overall_result` as resolver output. A producer may submit dimension evidence, but may not promote the aggregate unless the deterministic resolver confirms all required evidence and identity constraints.

**Required future regression:** Regions navigation/text/edit smoke = `PASS`, with Behavioral/Role/Whole-Screen Visual evidence absent, must yield `overall_result != PASS`. Add a separate case proving Reference-vs-Model analysis with no live runtime remains non-final. These belong to planned Wave C4; no verification schema, policy, resolver, or Example Project artifact was changed for this Reality Fund.

The existing baseline already identifies overlapping verification authorities (`evidence-contract.md`, `evidence-levels.md`, `verification-layers.md`, `ui-parity.md`, and parity schema) and notes that schema shape does not compute all cross-field aggregation. This Reality Fund supplies a concrete promotion failure for the future resolver mapping; it does not authorize parallel policy or schema authorities.

### MxAgile/mxcli Skill Authority Overlap Reality Fund (user-supplied, 2026-11-02)

**Evidence class:** `USER-SUPPLIED REALITY`; the reported Example Project sessions and their transcripts were not re-inspected as part of this checkpoint.

Across several real Example Project verification runs, agents reportedly reconstructed technical execution paths from mxcli capabilities/help, repository scripts, and Playwright helpers even when MxAgile mission/runtime/verification contracts or a resolved recipe were already available. The reported examples are:

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
| Copilot Runtime Verification / UI Parity | — | — | No matching local Copilot campaign session; Example Project evidence is Claude Code. |

These are examples, not comparable cost baselines. `session_files` counts file events/path records, not bytes or unique policy-body tokens.

### Additional Reality Failure Paths (2026-11-03)

The user supplied three further workflow failure paths from the same Regions parity campaign.
They extend the failure analysis below; they do not revise the provider totals or the
commit-bounded transcript measurements above.

| Failure path | Reality evidence | Observable count / benchmark treatment |
|---|---|---|
| Smoke promoted to parity | Text, reachability, navigation, and an edit control were present; this was incorrectly reported as `overall_result: PASS`. | Occurrence reported; exact count, turns, reads, calls, and output bytes `NOT_OBSERVABLE`. |
| Screenshot promoted to visual PASS | A Runtime screenshot existed before Reference-vs-Runtime rendering and comparison; after both images were opened and compared, the correct result was `visual_whole_screen = FAIL`. | One described sequence; exact turns, reads, calls, and output bytes `NOT_OBSERVABLE`. |
| Disposition lost between waves | At least one reconciled `REFERENCE_GAP` was later treated as implementation scope, causing Requirements/Decision re-reconciliation. | At least one repeated reconciliation is reported; exact count, turns, policy reads, calls, and output bytes `NOT_OBSERVABLE`. |

These are user-supplied observations, not transcript-derived counters. Do not add estimated
tokens, cost, wall time, or policy-read totals. The resolver and persisted-disposition
reconciliation are recorded in Section 16.

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
| `local-runtime-profile.md` | Project mxcli/runtime profile and browser target | 51,181 | Acceptance, Discovery, Implementation, UI, Orchestrator, Q, System, Test, Visual | Opt-in `Resolve-MxAgileMxcli.ps1 -ResolveRecipe` plus `mxcli_runtime_recipe.py` consume explicit C2 and selected-binary help. No Company Layer runtime schema/source exists, so layers are not scanned or inferred. | C1 IMPLEMENTED |
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

At the Example Project snapshot, framework policy recorded Core `db_name = "default"`, required project-local mxcli path/version and command-specific help, and separately discussed local `db_type`. Its canonical autonomous examples used `--db-name default`; the user-reported current Example Project mxcli help exposed `--dbname default`. This is a versioned CLI spelling mismatch, not a reason to hard-code either spelling as eternal Core syntax.

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

## 8. Reality Benchmark: EXAMPLE_PROJECT_REGIONS_2026-11-02

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
- Local Copilot store has no matching Example Project commit/recipe turn and no token/cache event table. The Claude log is the only direct benchmark session source located.
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
| `local-runtime-profile.md` | 51,181 | mxcli/runtime/browser profile; A/D/I/UI/O/Q/Visual | Existing resolver now composes an opt-in complete recipe from C2, selected binary version/help, and project `local_runtime`; Company Layer runtime defaults remain unsupported until a canonical schema/source exists. | C1 IMPLEMENTED |
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

`ON_DEMAND` is not a statement that a policy body was observed in the Example Project session. It is the intended bundle routing. A full-size policy read is counted only where the actual tool event proves it.

## 11. Target Architecture

### Minimal Consumer Kernel

Every mission needs only: current user objective/scope, project root and safety boundary, one authoritative lifecycle/resume position, current tool authority/capability state with evidence source, open blocker/next step, and an explicit rule that unavailable evidence is not PASS. Keep universal safety invariants here; do not include recovery recipes, parity procedure, migration steps, or release tables.

### Capability/Resolver Layer

Use existing structured owners first:

1. `Get-MxAgileCapabilities.ps1` remains the current-session capability entrypoint; distinguish configured/declarative values from attested runtime facts in its existing output.
2. Resolve a structured `operating_mode/tool_authority` once from `check-studio-pro-status.ps1` evidence plus `operating-mode.md`; consumers consume it. Do not infer a healthy MCP route from adapter presence.
3. C1 extends the existing project-local mxcli resolver boundary: capability evidence (absolute path/version/help), complete resolved recipe, route/status, expected DB identity, and required checks. It consumes one explicit C2 result and does not probe Studio Pro again. The policy remains normative; no competing runtime authority. Company Layer runtime defaults remain unsupported because the repository defines no structured layer source/schema.
4. Reuse lifecycle schemas/helpers for phase/mission/epoch; provide a deterministic transition/completion result rather than reimplementing state machines in agents.
5. C4 reuses verification schemas and `resolve_impact.py` facts. The existing read-only project-status builder now owns `resolve_parity_status` over seven UI dimensions and the six evidence-matrix dimensions, with evidence sufficiency, validated contract hashes, identity/freshness, capture provenance, and explicit AMBIGUOUS precedence. Keep product/finding authorization policy normative.
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

The original plan placed C0 first and C2 as a precondition for C1. The repository has since completed C1 and C4; this table records their implementation outcomes while preserving C3/C5/C6 as future work.

| Wave | Priority and causal overhead in this benchmark | Existing regression candidates (not run) |
|---|---|---|
| **C0 Instrumentation** | First. Persist source/projection/load events, exact bytes, file-read hashes/counts, Context Mode output sizes, handoff/result sizes, compaction IDs/tokens, requested-vs-actual model and manual override provenance. This session could be measured only because local Claude logs happened to exist. | `test-injection-contract.ps1`, `test-managed-block.ps1`, `test-platform-portability.ps1`, `test-agent-delegation.ps1`; add focused telemetry fixtures only after approval. |
| **C2 minimal Operating Mode authority** | IMPLEMENTED as the C2 resolver; retain a planned consumer-integration follow-up for the redundant mode-choice dialog. When target identity is known and detection conclusively says the project is not open, consume `CLOSED-AUTONOM` as final and continue without asking the user to select the same state. Escalate only on ambiguity, conflict, or an explicit user override. | Extend `test-operating-mode-detection.ps1` with a coordinator/dialog contract asserting zero questions for known-target + Studio-Pro-closed, and one precise question only for ambiguous/conflicting evidence; retain `test-capability-discovery-routing.ps1` and `test-agent-delegation.ps1`. |
**C2 Operating-Mode Dialogue Reality Fund (planned follow-up; no ad-hoc resolver):** the detector
already emits `CLOSED-AUTONOM` when the target project identity is known and a successful lookup
finds no matching Studio Pro project. The reported consumer dialog nevertheless asks the user to
choose `CLOSED-AUTONOM` / `LIVE-SP` / `Other`, treating the detected result as only a recommendation.
The next C2 consumer-integration change must make that result terminal for the mode decision and
continue autonomously with zero user questions. Ask only when Studio Pro exists but target identity
is unknown, multiple candidate instances exist, detector/lock/project evidence conflicts, or an
explicit user instruction contradicts detection. Keep this as C2 dialogue-consumer work; do not add
a second detector or mode resolver.

**Acceptance:** target identity known + successful closed-project detection ⇒ effective
`CLOSED-AUTONOM` ⇒ autonomous continuation and zero user questions. Ambiguous/conflicting cases
remain non-autonomous at the relevant mutation boundary and ask one precise question. A passing
detector check alone does not satisfy this regression; verify the consumer dialogue/orchestration.

| **C1 Runtime Recipe** | IMPLEMENTED: opt-in composer consumes explicit C2, selected binary version/help, project profile, runtime purpose, and required checks; emits complete args and explicit blockers. CLI spellings remain help-dependent. No automatic startup probing or layer scan. Company Layer runtime defaults have no supported structured source and are not inferred. | Focused `test-mxcli-runtime-resolution.ps1` / `test_runtime_recipe.py`; runtime orchestration semantics remain separately owned by its contracts. |
| **C3 Lifecycle/Mission** | After C0/C2: startup block and long prose describe phase/mission completion alongside lifecycle, mission and context schemas; reduce repeated Re-Sync/continuation logic. | `test-startup-priority.ps1`, `test-session-bootstrap.ps1`, `test-context-epoch-schema.ps1`, `test-context-lifecycle-operational.ps1`, `test-context-transition-coordinator.ps1`, `test-legacy-completion-reconciliation.ps1`. |
| **C4 Verification decisions** | IMPLEMENTED: schema v3 and `build_project_status.resolve_parity_status` distinguish SMOKE / REFERENCE_VS_MODEL / LIVE_PARITY; compute from required dimensions, per-matrix typed evidence, verified contract-source hashes, freshness and identity; expose provenance/blockers; unresolved precedence is AMBIGUOUS. Board and UI-Agent consume the same authority. | Focused `test_project_status.py` resolver/Board fixtures and `test-ui-parity.ps1`, including Regions smoke-only and no-live-runtime coverage. |
| **C5 Source authority / Finding / Impact** | Reduce per-agent reconstruction of source-priority and repeated observe/classify/reconcile stages; retain authorization boundaries. | `test-impact-resolver.ps1`, `test-project-knowledge.ps1`, `test-legacy-completion-reconciliation.ps1`, `test-reconciliation-board.ps1`, `test_external_change_reconciliation.py`. |
| **C6 Policy deduplication / compaction** | Last, after resolvers establish authority and behavioral fixtures; shorten startup kernel, preserve procedures on demand, reconcile duplicate context docs and evidence-layer vocabulary. | `test-injection-contract.ps1`, `test-managed-block.ps1`, `test-platform-portability.ps1`, `test-context-lifecycle-golden-scenarios.ps1`, `test-verification-economics-regression.ps1`. |

**Bounded C6 input, not completion of C6 — Mendix UserRole Identity Reality Fund:** the generic
role-identity kernel, agent/skill guidance and R1–R3 regression are now in `HEAD` (`ff78c99`).
Project-specific Mendix compilation and Role rename/refactoring behavior remain unverified without
an MPR, so this is not a blanket rename-safety claim. Broader C6 policy deduplication still waits
for the listed resolvers.

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

**Phase 1 complete. No production policy, schema, resolver, hook, or Example Project artifact was changed.** The only new artifact is this requested report. No tests, parity, runtime, or release gates were run.

```text
CONTEXT_ARCHITECTURE_BASELINE_COMPLETE = JA
IMPLEMENTATION_APPROVAL_REQUIRED = JA
STOP_FOR_APPROVAL = JA
```

## 15. Post-Phase-1 Implementation Status (2026-11-02)

This addendum records implementation after the Phase-1 snapshot above; it does not rewrite the measured baseline or its original approval boundary.

**C1 Runtime Recipe: IMPLEMENTED.** The existing `Resolve-MxAgileMxcli.ps1` entry point retains path/source resolution and adds opt-in `-ResolveRecipe`. It consumes explicit C2 authority, selected-binary version/help evidence, project `local_runtime`, purpose, and required checks; the Python composer emits exact supported arguments or explicit blockers. CLI spelling remains help/version-dependent. The repository has no machine-readable Company Layer runtime-default source, so the resolver does not scan or infer layer values; current inputs are project profile or explicit session overrides.

**C4 Parity Aggregate: IMPLEMENTED.** The existing read-only `build_project_status.py` owns `resolve_parity_status` and an on-demand single-report CLI. New UI parity reports use schema v3 while v1/v2 remain available as legacy inputs. `SMOKE` and `REFERENCE_VS_MODEL` cannot produce full live parity PASS. The resolver preserves the existing seven UI dimensions and six evidence-matrix dimensions, requires per-dimension/per-matrix typed evidence, validates Requirement/Decision source hashes for Contract PASS, checks bound comparison identity and target freshness, and requires `whole_screen_review.comparison_result` plus a non-empty summary to agree with the Visual matrix. Reference/runtime capture sides and reviewed IDs must match the current identity and role/state scope. It returns explicit `BLOCKED`, `STALE`, `NOT_OBSERVABLE`, `UNKNOWN`, or `AMBIGUOUS` states with provenance. The existing Board gallery consumes the same result and retains the producer claim separately. The existing canonical Finding store also carries revisioned, hash-bound authority dispositions consumed through Project Status.

**C4 Reality coverage:** synthetic tests exercise smoke suppression, model-only suppression, typed-evidence sufficiency, validated Contract source hashes, identity/freshness mismatch, unresolved precedence, no-capture and unbound-identity Board paths, screenshots without a comparison result, explicit comparison-result mismatch, actual visual FAIL/PARTIAL results, and an eligible LIVE_PARITY Board PASS. Finding fixtures verify V4–V6: `REFERENCE_GAP` prohibits app implementation, `AUTHORITY_CONFLICT` blocks semantic implementation, and changed source fingerprints require a newer persisted reconciliation revision. These tests use no external Mendix runtime or Example Project artifacts.

**Context boundary:** no C0 telemetry was made automatic; no broad startup reads, repository scans, persistent telemetry store, second operating-mode detector, or separate parity resolver were added. The on-demand parity CLI resolves only the supplied report request. C2 remains the sole tool-authority aggregator; C1 consumes its explicit result.

The Phase-1 baseline contains user-supplied mxcli skill-authority Reality evidence. Exact skill-load events and per-run read counts remain `NOT_OBSERVABLE` until supported by transcript-bound harness evidence; no separate workaround was implemented.

### Historical Pre-Consolidation Verification Status

- Final impact plan: Tier 3, 19 suites, no unmapped paths. Impact Regression: **PASS** (1088.01 s).
- Focused post-gate checks: credential discovery 66/66, local runtime profile 122/122, UI-driven contract 72/72, projection mapping 1/1. Earlier C1 runtime resolution passed 30/30; UI parity passed 127/127.
- The single Full Release Gate run returned **FAIL**: Tier 0 had failures in `test-credential-discovery.ps1`, `test-local-runtime-profile.ps1`, and `test-ui-driven-contract.ps1`; Tier 1 and Tier 2 passed. The assertions were aligned with the resolved-recipe and semantic-fidelity contracts, then each affected suite passed in focused runs. The Full Release Gate was not repeated, so full-release status remains **NOT PASSED**.
- No checkpoint commit was amended and no push was performed.

## 16. Supplemental Example Project Reality and C4 Reconciliation (2026-11-03)

**Evidence class:** user-supplied Example Project campaign observations. Raw campaign transcripts and
provider logs were not supplied in this turn, so only facts stated in the Reality Evidence are
recorded; turns, read counts, tool-call counts, output volume, tokens, and cost are not inferred.

### A. Evidence Promotion Failure

The campaign reports two failures: minimum navigation/text/edit-control smoke was promoted to
whole-parity `PASS`; later, a runtime screenshot was reported as whole-screen `PASS` before the
active reference had been rendered, opened, and actually compared. After the user's correction,
both sides were opened and compared and the result was `FAIL` due to visual gaps.

Reconciliation against the current C4 contract:

- **Already covered:** `SMOKE` cannot establish live parity; `REFERENCE_VS_MODEL` cannot imply
  runtime evidence; screenshots prove capture, not comparison; current comparison identity,
  freshness, role/state scope, paired reference/runtime captures, and visually reviewed capture
  IDs are required.
- **Added in C4:** schema v3 and `resolve_parity_status` require an explicit
  `whole_screen_review.comparison_result` and non-empty `comparison_summary`, require the result
  to agree with `evidence_matrix.visual_whole_screen_parity.status`, and block a missing result.
  A contradictory result remains `AMBIGUOUS`; an actual `FAIL` or `PARTIAL` is preserved.
- **Regression result:** V1 smoke PASS plus missing visual evidence → aggregate is not PASS;
  V2 captures without a comparison result → visual status is not VERIFIED/PASS; V3 an actual
  comparison gap → visual and aggregate results remain FAIL/PARTIAL as submitted and resolved.

These are synthetic resolver tests, not a new Example Project or Regionen-specific implementation.

### B. Authority-Disposition Persistence

The campaign reports at least one previously classified `REFERENCE_GAP` being reinterpreted as
application implementation scope in a later wave, requiring Requirements/Decision re-reconciliation.
The exact number of repeated tool calls, policy reads, and agent turns is `NOT_OBSERVABLE` from the
supplied evidence.

Reconciliation against the current C4/Project Status contract:

- **Already persisted:** canonical Findings under `planning/findings/FIND-*.yml` now carry a
  revisioned `authority_disposition` with classification, authoritative source hashes, allowed
  and prohibited actions, unresolved decision, evidence references/fingerprint, and reconciliation
  timestamp. This uses the existing Finding store, not a new state store.
- **Already consumed:** the read-only Project Status projection verifies current source/evidence
  hashes. Later implementation consumes an action only when `status: RESOLVED` and
  `consumable: true`; stale, missing, unobservable, or ambiguous dispositions route to
  `RECONCILE` and do not fall back to an old implementation action.
- **Regression result:** V4 `REFERENCE_GAP` forbids app implementation solely to match an
  unresolved reference; V5 `AUTHORITY_CONFLICT` blocks semantic implementation; V6 changed
  authority/fingerprint makes the disposition stale until a new explicit reconciliation and
  revision are persisted.

V1–V6 are covered by existing `test_project_status.py` resolver/projection fixtures and
`test-ui-parity.ps1`; no parallel C4 resolver or Regionen-specific test architecture was added.

Executable regression owners in `tests/test_project_status.py` are:

- V1: `ParityStatusResolverTests.test_regions_style_smoke_never_promotes_missing_parity_dimensions`.
- V2: `ParityStatusResolverTests.test_whole_screen_screenshots_without_comparison_result_do_not_verify_visual_parity`.
- V3: `ParityStatusResolverTests.test_whole_screen_comparison_gap_is_preserved_as_fail_or_partial`.
- V4–V6: `ProjectStatusTests.test_persisted_authority_disposition_gates_later_implementation`.

These invoke the parity resolver or Project Status projection and assert resolved/blocked/stale
behavior, rather than relying on policy-string presence.

### 17. Bounded Policy Consolidation Pass

#### Measured Baseline

Counts are canonical `.mxagile/policies/*.md` source files, measured as UTF-8 file bytes and
Unicode code points. Line counts split on LF. Policy bodies are not counted from generated copies.

| Measure | Before | After | Change |
|---|---:|---:|---:|
| Canonical policy files | 59 | 61 | +2 |
| Policy lines | 17,490 | 16,679 | -811 (-4.64%) |
| Policy characters | 792,013 | 758,180 | -33,833 (-4.27%) |
| UTF-8 bytes | 795,331 | 761,324 | -34,007 (-4.28%) |

The two additional files are on-demand specializations extracted from the broadly referenced C1
profile: `runtime-dependency-recovery.md` (112 lines / 6,101 bytes) for Gradle stalls and
`runtime-configuration-reconciliation.md` (109 lines / 5,934 bytes) for project-constant/Studio-Pro
configuration discrepancies. Neither is read for an ordinary C1 recipe resolution.

#### Basal and Startup Footprint

The repository injector places the managed startup router into AGENTS/Copilot instructions and
the Claude managed block; the project instruction body is inline for AGENTS/Copilot and imported
for Claude. It does **not** inline any `.mxagile/policies/*.md` body. Policy links are routing
contracts, not proof of body loading. Actual per-session policy reads remain `NOT_OBSERVABLE`
without transcript-bound load evidence.

| Startup footprint | Before | Current |
|---|---:|---:|
| Managed startup router | 92 lines / 6,702 UTF-8 B | 42 lines / 3,138 UTF-8 B |
| Policy bodies automatically inlined by injector | 0 | 0 |

The original router reduction was already in the active worktree and is not attributed as authored
by this consolidation pass. Regression exposed that its 37-line intermediate form had dropped
explicit optional-capability and same-session update-completion details; those five lines are now
restored in the 42-line final router. It remains 50 lines / 3,564 bytes smaller than the measured
92-line baseline and 62 bytes under the 3,200-byte startup budget. Routing covers safety/Re-Sync,
tool conflict, C2's structured operating-mode
result, external changes, delegation, optional capability discovery, update completion, and
current Finding dispositions. Capability resolution remains on-demand only; install/update
re-sync is conditional on an update. A routed read is not an automatically loaded body.

#### Final Classification

Each of the 61 canonical policies has exactly one class. `KEEP/BASAL` means the contract must be
available at the general startup/command boundary; it does not mean the file body is inlined.

**KEEP/BASAL (3)** — cross-cutting safety and session/tool boundary:
`lifecycle-resync.md`, `safety-rules.md`, `tool-instruction-conflict.md`.

**KEEP/ON-DEMAND (46)** — distinct capability/task boundaries with no duplicate authority removed:
`acceptance-campaign.md`, `agent-delegation.md`, `autonomous-remediation.md`,
`backlog-sync.md`, `capability-discovery.md`, `commit-authority.md`, `context-lifecycle.md`,
`context-transition.md`, `credential-discovery.md`, `design-contract-intake.md`,
`execution-intent.md`, `external-change-reconciliation.md`, `impact-resolution.md`,
`implementation-control.md`, `intake-completeness.md`, `legacy-completion-reconciliation.md`,
`migration-dfc-to-mxagile.md`, `mission-completion.md`, `mockup-analysis.md`,
`mockup-lifecycle.md`, `mockup-materialization.md`, `observe-before-mutate.md`,
`ownership-guard.md`, `platform-portability.md`, `project-compatibility.md`,
`project-knowledge.md`, `project-release-checkpoint.md`, `reconciliation.md`,
`representative-fixture-contract.md`, `runtime-configuration-reconciliation.md`,
`runtime-dependency-recovery.md`,
`runtime-startup-recovery.md`, `scss-engineering.md`, `source-priority.md`,
`spa-mockup-bundle.md`, `test-contract-derivation.md`, `test-defect-protection.md`,
`test-harness-cleanup.md`, `test-identity-lifecycle.md`, `test-workflow.md`,
`ui-element-selection.md`, `update-contract.md`, `user-orientation.md`,
`verification-layers.md`, `verification-materialization.md`, `verification-scenario.md`.

**SHRINK (12)** — policy remains; repeated semantics are delegated to its existing authority:
`consistency-check.md`, `development-runtime.md`, `evidence-contract.md`,
`evidence-levels.md`, `gap-verification-repair.md`, `local-runtime-profile.md`,
`operating-mode.md`, `parity-finding-reconciliation.md`, `runtime-strategy.md`,
`test-staleness.md`, `ui-parity.md`, `verification-gap-taxonomy.md`.

**MERGE (0):** none. These boundaries still carry distinct procedures or authorization semantics;
no giant replacement policy was created.

**DELETE (0):** none. No policy was wholly redundant after tracing its consumers.

#### Consolidations Made

- **C1:** `local-runtime-profile.md`, `development-runtime.md`, `runtime-strategy.md`,
  workflow/agent/orchestrator/lifecycle/schema consumers now route runtime argv, backend and DB
  identity through the C1 recipe. Concrete CLI examples and the contradictory Company Layer
  precedence ladder were removed from policy consumers. Exact syntax remains selected-binary-help
  owned.
- **Failure-only runtime recovery:** the Gradle stall/lock procedure is extracted from
  `local-runtime-profile.md` into the on-demand `runtime-dependency-recovery.md`; schemas, recovery
  policies, tests, and impact mapping reference that owner.
- **C2:** `operating-mode.md` delegates detector/state classification and route output to
  `Get-MxAgileCapabilities.ps1 -ResolveOperatingMode`; `orchestrator.md` and CE0066 handling
  consume that structured result instead of running a second detector or rebuilding routes.
- **C4:** `ui-parity.md` and `evidence-contract.md` no longer duplicate aggregate/promotion logic;
  `build_project_status.resolve_parity_status` owns sufficiency, comparison result, statuses,
  identity, freshness, and promotion. `gap-verification-repair.md` and
  `parity-finding-reconciliation.md` refer to the revisioned Finding disposition instead of
  carrying duplicate classification/action matrices.
- **Verification vocabulary:** `verification-layers.md` owns five layer semantics and security
  dimensions; `evidence-levels.md` retains only gate maturity, legacy tag mapping, and recording.
  `verification-materialization.md` owns revision actions; `test-staleness.md` owns status
  transitions; `verification-gap-taxonomy.md` owns gap classification only.
- **Runtime strategy:** Local First/Docker-by-verification-need now has one decision table; concrete
  mxcli flags and runtime argv are not repeated in consumers.

`KEEP/BASAL` policies intentionally retain only general safety, Re-Sync, and command-authority
boundaries. Detailed runtime recovery, parity, migration, fixtures, and workflow procedures remain
task-triggered.

No C0 telemetry, startup scan, automatic probing, external-layer scan, or Regionen-specific rule
was introduced. UNKNOWN / NOT_OBSERVABLE / BLOCKED / AMBIGUOUS behavior was retained.

#### Final C1/C2/C4 Policy Boundary Review

The review explicitly challenged the prior `MERGE (0)` / `DELETE (0)` result against policies
whose decision algorithms moved to C1, C2, or C4. The table records the independent contract
that remains for every current policy; a resolver owning one algorithm does not automatically
replace a policy's distinct authorization, lifecycle, evidence, or recovery contract.

**KEEP/BASAL (3)**

| Policy | Independent contract boundary |
|---|---|
| `lifecycle-resync.md` | Reconstruct and preserve current lifecycle state at startup/resume. |
| `safety-rules.md` | Cross-cutting safety and mutation prohibitions. |
| `tool-instruction-conflict.md` | Resolve instruction-source precedence before tool use. |

**KEEP/ON-DEMAND (46)**

| Policy | Independent contract boundary |
|---|---|
| `acceptance-campaign.md` | Acceptance campaign scope, gates, evidence, and outcomes. |
| `agent-delegation.md` | Bounded semantic work packages, handoffs, and result authority. |
| `autonomous-remediation.md` | Eligibility and approval to apply a confirmed repair. |
| `backlog-sync.md` | External Board synchronization without granting scope authority. |
| `capability-discovery.md` | When optional capabilities may be queried and how results are used. |
| `commit-authority.md` | Authorization and preconditions for Git commits. |
| `context-lifecycle.md` | Context epoch, pressure, resume, and checkpoint lifecycle. |
| `context-transition.md` | Compaction/epoch transition steps and context preservation. |
| `credential-discovery.md` | Route-specific credential discovery and secret handling. |
| `design-contract-intake.md` | Identity and mapping of an incoming Design Contract. |
| `execution-intent.md` | Classify request intent before choosing a lifecycle route. |
| `external-change-reconciliation.md` | Git delta, Finding impact, and watermark reconciliation. |
| `impact-resolution.md` | Resolve candidate Requirement/Task links without authorizing mutation. |
| `implementation-control.md` | Ordered implementation controls and required approvals. |
| `intake-completeness.md` | Required intake evidence before Discovery readiness. |
| `legacy-completion-reconciliation.md` | Reconcile historical completion claims to current artifacts. |
| `migration-dfc-to-mxagile.md` | Preserve knowledge and map artifacts during DFC migration. |
| `mission-completion.md` | Mission completion, continuation, and scope boundaries. |
| `mockup-analysis.md` | Extract structured semantics from a mockup. |
| `mockup-lifecycle.md` | Active target revision identity and lifecycle. |
| `mockup-materialization.md` | Materialize/render the exact accepted target artifact. |
| `observe-before-mutate.md` | Enforce observation and reconciliation before mutation. |
| `ownership-guard.md` | Distinguish Core-owned from project-owned artifacts. |
| `platform-portability.md` | Cross-platform constraints for install and engineering commands. |
| `project-compatibility.md` | Doctor diagnostics and compatibility reporting after Core updates. |
| `project-knowledge.md` | Canonical project artifact map and legacy knowledge boundaries. |
| `project-release-checkpoint.md` | Release checkpoint, scope freeze, and completion evidence. |
| `reconciliation.md` | Core update, Discovery/Refinement, and legacy-artifact reconciliation. |
| `representative-fixture-contract.md` | Representativeness and readiness of verification fixtures. |
| `runtime-configuration-reconciliation.md` | Rare project-constant/Studio-Pro discrepancy disposition with secret safeguards. |
| `runtime-dependency-recovery.md` | Failure-only Gradle stall and lock-owner recovery. |
| `runtime-startup-recovery.md` | Staged runtime startup diagnosis and bounded recovery. |
| `scss-engineering.md` | SCSS implementation and design-system constraints. |
| `source-priority.md` | Concern-specific source authority and conflict resolution. |
| `spa-mockup-bundle.md` | SPA mockup bundle and revision handling. |
| `test-contract-derivation.md` | Derive canonical Test Contracts from accepted requirements. |
| `test-defect-protection.md` | Separate application defects from test/infrastructure failures. |
| `test-harness-cleanup.md` | Cleanup boundaries for test-created workspaces and identities. |
| `test-identity-lifecycle.md` | Separate bootstrap identity from requested verification roles. |
| `test-workflow.md` | Choose and execute the applicable test workflow. |
| `ui-element-selection.md` | Select Atlas/UI elements from established interaction patterns. |
| `update-contract.md` | Same-session re-sync and structured update completion. |
| `user-orientation.md` | Orient only when no current project state is established. |
| `verification-layers.md` | Verification-layer and security-dimension semantics. |
| `verification-materialization.md` | Decide which proof artifacts/actions become stale after change. |
| `verification-scenario.md` | Construct role/state/viewport verification scenarios. |

**SHRINK (12)**

| Policy | Independent contract retained after authority delegation |
|---|---|
| `consistency-check.md` | Consistency workflow consumes C2-selected tools; it does not redetect operating mode. |
| `development-runtime.md` | Runtime lifecycle/readiness remains; C1 owns the executable recipe. |
| `evidence-contract.md` | Capture identity, storage, and retention remain; C4 owns aggregation/promotion. |
| `evidence-levels.md` | Gate maturity and recording remain; `verification-layers.md` owns layer vocabulary. |
| `gap-verification-repair.md` | GAP type/severity and repair acceptance remain; Finding owns action disposition. |
| `local-runtime-profile.md` | Runtime profile inputs/overrides remain; C1 owns argv/backend/database resolution. |
| `operating-mode.md` | User questions, mutation re-checks, and failure semantics remain; C2 owns detection/routes. |
| `parity-finding-reconciliation.md` | Observation/authority reconciliation remains; Finding/Project Status own action currentness. |
| `runtime-strategy.md` | Local-first versus Docker-by-verification-need remains; C1 owns invocation details. |
| `test-staleness.md` | Test-state transitions remain; materialization owns revision-action mapping. |
| `ui-parity.md` | UI dimensions, proof types, and comparison procedure remain; C4 owns sufficiency/aggregate promotion. |
| `verification-gap-taxonomy.md` | Gap/fixture classifications remain; materialization owns remediation actions. |

#### Merge/Delete Challenge

| Candidate | Decision | Reason |
|---|---|---|
| `development-runtime.md` + `runtime-strategy.md` | Keep separate; both remain `SHRINK`. | One owns runtime lifecycle/readiness; the other selects verification hosting and escalation. Merging would combine distinct triggers and enlarge a frequently referenced procedure. |
| `gap-verification-repair.md` + `parity-finding-reconciliation.md` | Keep separate; both remain `SHRINK`/on-demand. | GAP kind/severity/repair acceptance and observation-to-authority reconciliation are orthogonal; C4 removed the duplicated action mapping. |
| `evidence-levels.md` + `verification-layers.md` | Keep separate; both remain `SHRINK`/on-demand. | Evidence maturity and verification/security dimension describe different axes; the duplicated vocabulary was removed. |
| `ui-parity.md` + `evidence-contract.md` | Keep separate; both remain `SHRINK`. | UI-specific proof procedure differs from evidence identity/retention; only aggregate sufficiency and promotion moved to C4. |
| `local-runtime-profile.md` + `runtime-configuration-reconciliation.md` | Keep separate. | C1 profile/recipe inputs are normal runtime authority; discrepancy diagnosis is a rare, confirmation-bound reconciliation path and the old duplicate block is gone. |
| `local-runtime-profile.md` + `runtime-dependency-recovery.md` | Keep separate. | General runtime profile and Gradle lock/stall recovery have different trigger frequency and action boundaries. |

No current policy is fully replaced by C1/C2/C4: each resolver replaced a decision algorithm, while
the retained policies above own independent input, authorization, lifecycle, evidence, or recovery
contracts. Thus `MERGE (0)` / `DELETE (0)` remains a defensible result, not a file-count target; the
prior duplication was removed through delegation and shrinkage without creating a collection
policy. The 61-policy count includes two justified, failure-only Runtime extensions.

### Failed-Suite Contract Reconciliation (2026-11-03)

The single authorized post-consolidation Full Release Gate exited with code 1:
Fast Gate PASS, Tier 0 FAIL (11 suites), Tier 1 FAIL (3 suites), Tier 2 PASS,
Full Regression FAIL (14 suites). This result remains historical FAIL; focused repairs
do not retroactively turn it into PASS. No new Full Release Gate, commit, or push was performed.

Only the failed test contracts were changed in this reconciliation. Production behavior and
canonical policy sources were not changed. Assertions now check the consumer's route and the
retained requirement at its canonical owner rather than require duplicate prose or retired
metadata/CLI spellings. EXTEND preservation, credential safety, BUILD proof strength, C4
comparison/identity requirements, and bounded Git recovery remain covered.

RF-004 was checked against the current C2 implementation, not merely relabeled: isolated tests
execute the real detector adapter and mode/route resolver functions with synthetic process
output. Timeout retains UNKNOWN, null observations, detector source and TIMEOUT reason; on
Windows it yields AMBIGUOUS-SP-STATE with no mutation route. An MPR lock alone cannot establish
LIVE-SP or execution intent. The existing positive headless-platform exemption is retained.
No missing production semantics were demonstrated. Validation ran on Windows; the headless
branch was not executed on a non-Windows host.

| Previously failed suite | Focused post-repair evidence |
|---|---|
| `test-credential-discovery.ps1` | PASS: 66 checks |
| `test-execution-intent.ps1` | PASS: 36 checks |
| `test-extend-semantics.ps1` | PASS: 36 checks |
| `test-hardening-rf004-sp-detector.ps1` | PASS: 12 checks |
| `test-lifecycle-resync.ps1` | PASS: 115 checks |
| `test-orientation.ps1` | PASS: 47 checks |
| `test-mockup-materialization.ps1` | PASS: 78 checks |
| `test-project-knowledge.ps1` | PASS: 42 checks |
| `test-verification-economics-regression.ps1` | PASS: 39 checks |
| `test-verification-scenarios.ps1` | PASS: 133 checks |
| `test-wp2-lifecycle-extensions.ps1` | PASS: 224 checks |
| `test-git-index-integrity.ps1` | Its one failed Python contract method: PASS; green Git fixtures not rerun |
| `test-git-recovery.ps1` | Its one failed Python contract method: PASS; green Recovery fixtures not rerun |
| `test-mxcli-runtime-resolution.ps1` | Contract-only PASS: 29 checks; green recipe behavior suite explicitly skipped |

The HSQLDB/default-database recipe remains covered by
`test_runtime_recipe.py::RuntimeRecipeTests.test_composes_default_db_recipe_from_c2_profile_and_help`.
Removing the obsolete fixed argv example from the generic-policy assertion does not remove
that behavior requirement. Default full-suite execution still runs the recipe behavior suite;
`-ContractOnly` permits this focused rerun without repeating its prior green evidence.

All original failing assertions have successful focused follow-up evidence. No remaining blocker
from those failures is known. A new Fast Gate, Impact Regression, and Full Regression were not
run in this repair step; the existing interrupted Impact stays INCOMPLETE and the previous Full
Regression stays FAIL. New release evidence requires separate authorization.

### Parked SessionStart Provisioning Follow-Up

Classification: **REAL ISSUE / FOLLOW-UP**, excluded from the current changeset completion.
The reported first-run session downloaded Mendix Runtime 11.16.0, synchronized 22 Java
dependencies, and attempted PostgreSQL provisioning, failing because `initdb` was unavailable.
The reported installation's exact mxcli version and hook contents were not supplied.

Read-only inspection of upstream mxcli at commit
`6094f471fc01535ea51886aeaf03f1b530c9445b` established the generated Claude SessionStart route:
`.claude/settings.json` -> `.claude/bootstrap-mxcli.sh` ->
`run --local --setup --ensure-db`. The current template invokes this inside a shell block
using `"$MXCLI"`, with output piped to `tee`. The existing Core installer fixup only removes
the old `exec ./mxcli run --local ...` form, so it does not neutralize this newer form.
Concord as the session origin does not establish a separate Concord-owned hook.

This hook can bypass the C1 on-demand recipe and backend selection: setup still provisions
runtime/dependencies/DB, and `--ensure-db` selects PostgreSQL provisioning rather than HSQLDB.
Runtime downloads are normally per version and preserved user cache; missing Java JARs and
unavailable PostgreSQL can trigger work again in later sessions. A cached runtime does not
establish a running app, usable DB, or verified fixture.

Follow-up scope: robust handling of current framework-installed mxcli hook forms, preservation
of legitimate tooling bootstrap, and targeted regression for on-demand runtime/DB provisioning.
No installer/hook fix, new policy, or test for this finding was added here. The original
14-suite failure baseline and the focused repair evidence above remain separate.

### Authorized Full Release Attempt After Repairs (2026-11-03)

Status: **INCOMPLETE**, not PASS and not a demonstrated test-suite FAIL.
Exactly one new canonical invocation (`python tests/run-impact-tests.py --tier release`)
was started at 14:41:12 +01:00 after explicit user authorization. Tier 2 was not disabled.
Fast Gate completed with PASS (2.25 seconds). The saved log proceeds through Tier 0 and
part of Tier 1, but ends at `EXECUTING [Tier 1]: test-git-index-integrity.ps1`; its last
write is 14:49:56. There is no final Tier 0/1/2 summary or Full Regression result.

The terminal reports exit code 1, but the wrapper's post-run result marker was never
written. A subsequent read-only process observation found no matching gate/runner/Git-index
test processes. Therefore this attempt did not complete normally; the interruption cause
is UNPROVEN. Do not classify the unfinished Git-index suite as a functional failure or
infer a successful gate from the already completed output.

Evidence prefix in the local Temp directory: `mxagile-context-release-20261103-144039`.
The `.log`, `.before.json`, and `.planner.log` files are retained outside the repository.
After observing the incomplete execution, a fresh read-only comparison against the saved
baseline found HEAD unchanged at `c767ca4150d9bd7c812fba6f581c168dc9be86d6`, zero file-hash
differences, and zero Git-status differences. No gate-induced changes were detected.
Only this report was subsequently updated to record the outcome.

No automatic retry, fix, commit, or push was performed. The prior Full Regression remains
historical FAIL; the focused repairs remain PASS; this new Full Regression attempt remains
INCOMPLETE. The SessionStart provisioning follow-up remains parked and unimplemented.
Further execution or code changes require renewed user authorization.

### Eigener Gesamtbericht: Zusammengesetzte Verifikation (2026-11-03)

**Ergebnis:** Vollstaendige Inventarabdeckung mit erfolgreicher Einzeltest-Evidenz.
**Kein kanonischer Full-Gate-PASS:** Die beiden abgebrochenen Full-Gate-Versuche bleiben
INCOMPLETE. Dieser ausdruecklich beauftragte Bericht kombiniert vorhandene Log-Evidenz
mit einem separaten manuellen Restlauf; er ersetzt keine finale Runner-Aggregation.

#### Evidenz und Abgrenzung

- Ausgangslauf: `mxagile-context-release-retry-20261103-151104.log` im lokalen Temp-Verzeichnis.
  Fast Gate PASS (2.84 Sekunden); 93 abgeschlossene Suite-Ausgabeabschnitte vor dem
  unterbrochenen Layer-Update-Test. Line-by-line-Pruefung fand keine fehlgeschlagenen
  Assertions oder Python-Fehlerzusammenfassungen. Die Fortsetzung zum jeweils naechsten
  Suite-Header belegt die Rueckkehr der vorherigen Suite; individuelle Exitcodes wurden
  dort nicht dauerhaft gespeichert. Deshalb bleibt dies Log-Evidenz, kein nachtraeglich
  rekonstruierter kanonischer Gate-PASS.
- Manueller Restlauf: `mxagile-manual-remainder-20261103-191639.results.json` sowie separate
  stdout/stderr-Logs pro Suite im Temp-Verzeichnis. 26/26 Suiten PASS, alle Exitcode 0,
  keine Skips, Timeouts oder Ausfuehrungsfehler. Ausfuehrung seriell von 19:16:58 bis
  19:51:05 +01:00, rund 34 Minuten. Nur der unterbrochene Layer-Update-Test und die
  25 noch nicht gestarteten Suiten wurden ausgefuehrt; keine abgeschlossene Suite des
  Ausgangslaufs wurde erneut gestartet.
- Sicherheitsgrenze des manuellen Laufs: 30 Minuten pro eigenem Testprozess. Keine Suite
  erreichte diese Grenze; keine Timeout-bedingte Prozessbeendigung war erforderlich.
- Gegen das aktuelle Inventar geprueft: 119 eindeutige Suiten abgedeckt, keine fehlenden
  oder doppelt angerechneten Suiten. Die 26 neuen Ergebnisse wurden den vorhandenen
  93 Abschnitten nur fuer diesen eigenstaendigen Bericht zugeordnet.

| Tier | Vorhandene abgeschlossene Log-Abschnitte | Neuer manueller Restlauf | Inventarabdeckung |
|---|---:|---:|---:|
| Tier 0 | 72 | 0 | 72/72 |
| Tier 1 | 21 | 18 PASS | 39/39 |
| Tier 2 | 0 | 8 PASS | 8/8 |
| Gesamt | 93 | 26 PASS | 119/119 |

#### Manueller Restlauf

Alle folgenden Suiten wurden vollstaendig, ohne `-ContractOnly` oder Teiltestauswahl,
ausgefuehrt. PASS wird hier durch den gespeicherten Exitcode 0 und fehlende Skip-Marker
belegt; verschachtelte Verhaltenstests der jeweiligen Suite wurden mit ausgefuehrt.

| Suite | Tier | Ergebnis | Dauer (Sekunden) |
|---|---:|---|---:|
| `test-layer-update.ps1` | 1 | PASS | 359.20 |
| `test-managed-block.ps1` | 1 | PASS | 22.90 |
| `test-materialization-contract.ps1` | 1 | PASS | 19.22 |
| `test-migration-crash-safety.ps1` | 1 | PASS | 36.91 |
| `test-migration-provenance.ps1` | 1 | PASS | 44.12 |
| `test-mxagile-dev-cli.ps1` | 1 | PASS | 109.07 |
| `test-mxcli-binary-cache.ps1` | 1 | PASS | 14.64 |
| `test-mxcli-runtime-resolution.ps1` | 1 | PASS | 14.45 |
| `test-parity-gallery.ps1` | 1 | PASS | 56.63 |
| `test-project-status.ps1` | 1 | PASS | 42.80 |
| `test-reconciliation-board.ps1` | 1 | PASS | 566.48 |
| `test-session-bootstrap.ps1` | 1 | PASS | 15.95 |
| `test-spa-bundle-revision.ps1` | 1 | PASS | 15.37 |
| `test-startup-priority.ps1` | 1 | PASS | 15.51 |
| `test-transformation-behavioral.ps1` | 1 | PASS | 39.70 |
| `test-utf8-idempotency.ps1` | 1 | PASS | 33.40 |
| `test-workcopy-hygiene.ps1` | 1 | PASS | 70.38 |
| `test-wp10-artifact-schemas.ps1` | 1 | PASS | 29.26 |
| `test-bootstrap-generic.ps1` | 2 | PASS | 67.15 |
| `test-capability-discovery-routing.ps1` | 2 | PASS | 97.59 |
| `test-core-installer.ps1` | 2 | PASS | 79.33 |
| `test-init-idempotency.ps1` | 2 | PASS | 34.56 |
| `test-install-bootstrap-regression.ps1` | 2 | PASS | 48.59 |
| `test-local-updater.ps1` | 2 | PASS | 19.52 |
| `test-ps51-compatibility.ps1` | 2 | PASS | 14.90 |
| `test-setup-detection.ps1` | 2 | PASS | 178.38 |

Relevante neue Detailnachweise: Project Status 80 Python-Tests PASS; Parity Gallery
13 Python-Tests PASS; C1 Runtime Resolution 30 Vertragspruefungen und 12 Recipe-
Verhaltenstests PASS. Layer-Update, Board-Reconciliation und saemtliche Tier-2-Suiten
sind nicht mehr offen. Erwartete Fehler-/Rollback-Szenarien innerhalb dieser Suiten
sind keine fehlgeschlagenen Tests, wenn ihre Assertions und der Suite-Exit erfolgreich sind.

#### Repository und verbleibende Grenzen

Die Vorher-Fingerprints des Ausgangslaufs und des manuellen Restlaufs sind identisch.
Nach Ende des Restlaufs: HEAD weiterhin `c767ca4150d9bd7c812fba6f581c168dc9be86d6`,
null Dateihash-Abweichungen und null Git-Status-Abweichungen gegen dessen Vorher-Basis.
Der bestehende Dirty State wurde erhalten; die Tests erzeugten keine unerwartete
versionierte oder nicht ignorierte Repository-Aenderung. Erst danach wurde dieser
Gesamtbericht ergaenzt.

Keine bekannten fehlenden Suiten oder beobachteten Testfehler in der zusammengesetzten
Inventarabdeckung. Fast Gate bleibt separat PASS aus dem Ausgangslauf; ein separater
neuer Impact Regression wurde nicht ausgefuehrt. Kanonischer Full Regression bleibt
INCOMPLETE, nicht PASS. Keine Produktionslogik, Runner-/Resume-/Performance-Optimierung
oder SessionStart-Follow-up-Behebung wurde umgesetzt; kein Commit und kein Push.

Die rein lesende Fortschrittsabfrage liegt ausserhalb des Repositories unter
`%TEMP%/Get-MxAgileManualProgress.ps1`; sie aendert weder Tests noch Gate-Semantik.
Die Log-/JSON-Belege bleiben lokal im Temp-Verzeichnis und sind nicht Git-versioniert.

### Akzeptierter Entwicklungs-Checkpoint (2026-11-03)

Der Maintainer hat die zusammengesetzte Verifikation mit 119/119 abgedeckten Suiten
und keinem bekannten verbleibenden Testfehler ausdruecklich als ausreichend belastbar
fuer diesen Entwicklungs-/Reality-Test-Zyklus akzeptiert. Der urspruengliche Context-/
Policy-/C4-Hardening-Auftrag wird auf dieser Basis als lokaler Git-Checkpoint abgeschlossen.

Die fehlende kanonische Full-Gate-PASS-Evidenz bleibt **akzeptierte technische
Verifikationsschuld**. Kanonischer Full Release Gate: **INCOMPLETE**, niemals nachtraeglich
PASS. Diese auf den aktuellen Zyklus begrenzte Maintainer-Entscheidung aendert keine
allgemeine Framework-Gate-Semantik und ist keine Produktions-/Release-Freigabe.
Weitere Gate-/Host-Diagnose und Framework-Optimierungen werden vor dem naechsten
Reality-Test nicht begonnen. Der naechste Arbeitsstrang ist der Reality-Test im realen
Projekt und wird durch diesen Checkpoint nicht automatisch gestartet.

## Historical Reality Reconciliation (2026-11-05)

### Baseline and Method

The initial reconciliation baseline was `f62c57b10df2`, and reviewed the commits from
2026-11-03 through 2026-11-05 (`953ac4f`, `964033e`, `c3d4a76`, `a1e0f9d`, `828aa02`,
`f62c57b`). The subsequent implementation follow-through created `ff78c99`, `e3a535c`, and
`6717daa`; the final classifications and Wave Plan below reflect code at `6717daa`, not only
the initial snapshot.
Items 1–2 and 25–29 in the supplied reconciliation note are method/decision instructions,
not additional findings.

At reconciliation start, Task Inspect v2 and Mendix UserRole identity were uncommitted overlays;
they were then committed in the follow-through above. Reference project was not modified as part of this
work. The report itself is documentation-only relative to `6717daa`.

Keep these evidence stages distinct: `documented`, `configured`, `installed`, `projected`,
`discoverable`, `resolved`, `executed`, and `runtime-attested` are not synonyms. A policy or
adapter declaration alone does not establish consumer execution. Missing consumer evidence is
recorded as `NOT_OBSERVABLE`, not inferred as fixed or broken.

| Fund | Current-main evidence and reconciliation | Classification | Action |
|---|---|---|---|
| 3. Local Runtime Recipe | C1 resolves the project-local binary, selected-version help, backend/DB identity and complete argv; `mxcli_runtime_recipe.py` and the selected-binary resolver own construction. `test_runtime_recipe.py` covers the default DB recipe. | `FIXED_CURRENT_MAIN` | Keep historical recipe-loss regression; do not add more policy examples. |
| 4. Runtime Recipe Propagation | Runtime orchestration consumes the resolved recipe and readiness checks; tests cover exact invocation/handoff and do not reconstruct flags from prose. | `FIXED_CURRENT_MAIN` | Keep propagation regression; consumer runtime after later updates remains a separate evidence question. |
| 5. mxcli Skill / MxAgile Authority Overlap | `tool-instruction-conflict`, C1 recipe contracts, and orchestration tests separate mission/evidence authority, resolver recipe, syntax help, and execution. No second orchestration authority is present. | `FIXED_CURRENT_MAIN` | Preserve the route-consumption regression; no parallel skill workflow. |
| 6. Operating-Mode redundant user gate | C2 now emits `tool_authority.user_interaction` from the final effective mode; the orchestrator and always-on startup router consume it. Known-target closed detection returns `CLOSED-AUTONOM` / `NONE`; an MCP identity conflict becomes ambiguous and defers one question to the rechecked mutation boundary. | `FIXED_CURRENT_MAIN` | Keep `test-operating-mode-detection.ps1` L14–L16 and conflict L11a. No detector refactor. |
| 7. CLOSED-AUTONOM vs AMBIGUOUS-SP-STATE / user authority | C2 treats mode as a technical fact; `execution-intent.md` permits user preferences only among routes already allowed. Ambiguity is rechecked at the mutation boundary and cannot be converted to autonomous model mutation by a mode selection. `test-execution-intent.ps1` covers the boundary. | `FIXED_CURRENT_MAIN` | Retain the explicit-user-vs-unsafe-route regression; no second state machine. |
| 8. Builder Kit Capability Refresh | Capability, installed/projected agent presence, current-session discoverability, and delegability are separate. A stale loaded session requires the existing restart/re-sync outcome; fresh-session discovery is the expected path. Resolver and update-routing suites cover this distinction. | `SUPERSEDED` | Do not add same-session refresh; keep restart-required semantics. |
| 9. Demo User Switcher / Role Verification | C1 recipe and test-identity/credential policies resolve the declared role-switch helper before credential discovery; runtime recipes carry the demo-user-switch requirement. Focused credential/runtime suites cover ordering. | `FIXED_CURRENT_MAIN` | Preserve the resolved-route-before-credentials regression; no new credential search path. |
| 10. UserRole Identity | Current main documents Mendix's `[%UserRole_<RoleName>%]` XPath system variable and ID-association form across Implementation, UI, Acceptance, Maintainer, Brownfield, Builder Kit, and Mocketeer producers. `mxcli v0.20.0 describe --help` exposes `userrole`; official Mendix XPath docs confirm the token forms. R1–R3 regression forbids free-text/fuzzy matching and separates identity from capability. | `PARTIALLY_FIXED` | No Mendix MPR is available here to run the wrong-role CE1613 compile check or rename/refactoring test. Do not claim automatic rename support; validate the token against each target project/version before implementing. |
| 11. Parity Smoke Promotion | C4 `resolve_parity_status` keeps `SMOKE` distinct and does not allow smoke-only evidence to promote full parity. Resolver tests cover missing dimensions. | `FIXED_CURRENT_MAIN` | Keep the historical smoke-only regression. |
| 12. Screenshot / Visual Promotion | C4 requires a bound comparison identity, reviewed paired captures, and an actual whole-screen comparison result consistent with the visual matrix; screenshot existence alone is insufficient. | `FIXED_CURRENT_MAIN` | Keep no-comparison and mismatch regressions; no screenshot-only PASS. |
| 13. Parity Aggregator | The existing Project Status resolver deterministically accounts for required dimensions, evidence sufficiency, identity, freshness, and ambiguity; no second aggregator is needed. | `FIXED_CURRENT_MAIN` | Preserve V1–V3 resolver/Board regressions. |
| 14. Authority Disposition Persistence | Canonical Findings persist revisioned authority/source fingerprints and allowed/prohibited actions; Project Status rejects stale dispositions. V4–V6 tests cover later-consumer gating. | `FIXED_CURRENT_MAIN` | Preserve the existing persisted-disposition regressions. |
| 15. Representative Fixture States | `representative-fixture-contract.md`, role-coverage schema and scope-aware tests distinguish identity, role, scope, representative state, positive/negative scenarios, and `FIXTURE_BLOCKED`. | `FIXED_CURRENT_MAIN` | Retain the fixture-state regression inventory; no second fixture model. |
| 16. Synthetic Verification Data vs Canonical Domain Authority | Mocketeer marks mock data and forbids deriving business rules from sample data; representative fixtures are project-owned verification preconditions, not requirement authority. The boundary exists across current guidance/tests; no separate domain fixture schema is justified by this evidence. | `FIXED_CURRENT_MAIN` | Keep the sample-data/non-authority regression; do not add a parallel fixture contract. |
| 17. Reconciliation Watermark / jsonschema | Core distributes `.mxagile/tools/requirements.txt`; the Doctor detects missing `jsonschema` and fails closed. A read-only reference project `/api/status` request successfully produced schema diagnostics without a validator-unavailable diagnostic, demonstrating the dependency was available for that request. | `FIXED_CURRENT_MAIN` | Preserve fail-closed missing-dependency coverage; do not claim installer auto-provisioning. |
| 18. Board Runtime Reality | Current Board uses `/reference/`, `/capture/`, and `/diagnostic-source/`; historical `/api/reference`, `/api/capture`, and `/api/diagnostic-source` paths are not current contracts. `test_board_http.py` verifies current routes and `test_board_performance.py -k p7` verifies snapshot/cache reuse. Read-only reference project status returned HTTP 200 once and intermittent 503 `status_unavailable` / `RuntimeError`; successful status was BLOCKED with 159 diagnostics, including 13 schema errors. Installed Core was 1.10.0 / commit `f62c57b`; its Task schema/Doctor predate the now-committed Task Inspect fix. | `PARTIALLY_FIXED` | No reference project writes. Consumer still needs the normal Core update, then an authorized route/status/performance recheck. The 503 cause is not exposed by the endpoint or available server log. |
| 19. HTTP Client Disconnect | `serve_project_board.py` catches expected reset/abort/broken-pipe exceptions and emits compact `CLIENT_DISCONNECT`; Board HTTP tests cover each exception and next-request survival. | `FIXED_CURRENT_MAIN` | Retain the disconnect regression; no further handler change. |
| 20. Findings Projection | Project Status reads canonical `planning/findings/*.yml`, projects lifecycle/counts, and Board renders available records. Read-only reference project status reports Findings unavailable/zero items; direct directory inventory found no `planning/findings/` directory, so no canonical records existed to project. | `FIXED_CURRENT_MAIN` | Keep the canonical projection and explicit unavailable-state behavior; no second Finding store. |
| 21. Flavor Change Provenance | Company Layer setup uses the canonical `.mxagile/lifecycle.yaml` marker to select UPDATE and passes `-IsUpdate $coreInstalled` at both Core call sites. Core provenance retains the prior commit/version/install timestamp. New focused C4–C9 assertions cover this cross-flavor update path. | `FIXED_CURRENT_MAIN` | Keep the regression; no `previous_flavor` field is warranted by the current contract. |
| 22. Workspace Root Pollution | Test-workcopy/temp cleanup, harness cleanup policy, `.concord`/canonical evidence locations, and cleanup regressions cover known test-owned outputs. There is no single runtime-level inventory proving every mxcli/Playwright/Concord failure artifact is confined for every consumer route. | `PARTIALLY_FIXED` | Keep existing cleanup gates. Only add a targeted output-path regression if the current consumer reproduces root writes; do not add blanket cleanup or ignore rules. |
| 23. Child Model Runtime Reality | Handoff/result schemas and adapters record requested/static resolution, not independently observed actual child model. The Explore audit found no VS Code Copilot child-model return field; `profile_resolution: unknown` remains authoritative. The spawned Explore task had no requested model/profile and its tool result exposed no actual model metadata. | `STILL_OPEN` | Host API/telemetry attestation is unavailable in this environment. Keep actual child model/profile `NOT_OBSERVABLE`; do not add a schema field populated from adapter declarations or child self-report. |
| 24. Context-Cost Benchmark | The benchmark explicitly records Main model changes as `USER_CONTROLLED`; it is not evidence for automatic model routing. Current policy/telemetry guidance preserves requested-vs-actual provenance and cost attribution caveats. | `SUPERSEDED` | Retain as historical benchmark evidence only; do not create routing work from it. |

### Classification Summary

| Classification | Count |
|---|---:|
| `FIXED_CURRENT_MAIN` | 16 |
| `PARTIALLY_FIXED` | 3 |
| `CONTRACT_FIXED_BUT_CONSUMER_STALE` | 0 |
| `IMPLEMENTED_BUT_NOT_PROJECTED` | 0 |
| `IMPLEMENTED_BUT_NOT_USED` | 0 |
| `TEST_OR_FIXTURE_ONLY` | 0 |
| `SUPERSEDED` | 2 |
| `STILL_OPEN` | 1 |
| `UNKNOWN` | 0 |
| **Total Reality Funds** | **22** |

`FIXED_CURRENT_MAIN` means current code/contracts and focused regressions establish the fix; it does
not assert a fresh runtime pass in reference project. The incomplete Full Release Gate is not used as PASS.

### Updated Wave Plan

Only the three `PARTIALLY_FIXED` and one `STILL_OPEN` finding remain in the plan:

| Existing workstream | Remaining bounded work | Findings |
|---|---|---|
| C0 / delegation evidence | Add actual child-model attestation to the existing result path only when the harness supplies it; otherwise retain `NOT_OBSERVABLE`. Do not infer routing from adapters or cost benchmarks. | 23 `STILL_OPEN` |
| UserRole Identity validation | The generic model-bound policy and producers are committed. A project-owned MPR and Studio Pro/mxcli validation are still required to prove CE1613 on an invalid token and rename/refactoring behavior. | 10 `PARTIALLY_FIXED` |
| Board / consumer verification | Core route/cache behavior is tested. Reference project returned both status 200 and intermittent 503 `RuntimeError`; after normal Core update, recheck status, diagnostics, and route/cache timings with server logs available. No reference project writes in this run. | 18 `PARTIALLY_FIXED` |
| Output hygiene | Existing cleanup contracts stay. Reproduce current root pollution with source/path evidence before any cleanup change; no blanket deletion/ignore rule. | 22 `PARTIALLY_FIXED` |

No additional detector, parity, fixture, or finding resolver is planned. The planned Full Release
Gate was interrupted and remains `INCOMPLETE`; no summary or partial output upgrades it to PASS.

Historischer Status am 2026-11-03: Der mxcli-SessionStart-/Provisioning-Fund war ein
separates **REAL ISSUE / FOLLOW-UP**, geparkt und unimplementiert. Der aktuelle
Implementierungsstand ist im folgenden Reality Finding vom 2026-11-05 nachgetragen.
Der damalige Checkpoint blieb lokal; kein Push, Amend oder History Rewrite.

## Wave Lifecycle Reality Finding (2026-11-05)

**Framework state:** inspected at `6b5091d` after the recent commits. Waves are already
the lifecycle progression unit: `execution-waves.md` plans scope, `process-state.yaml`
records phase/gates per Wave, checklists/tasks carry implementation work, mission state
records active/in-scope Waves and blockers, and acceptance/wave reports carry completion
evidence. This is a lifecycle/execution primitive, not reporting metadata. The contracts
already require Wave-level verification and phase-boundary continuation.

**Reference project evidence:** the read-only status report in this document records installed
Core `1.10.0` / commit `f62c57b`, `BLOCKED`, and six `WAVE_ASSIGNMENT_MISSING`
diagnostics among 159. This proves missing canonical Wave assignments for the diagnosed
artifacts, not that no Wave plan existed. No reference project `execution-waves.md`, process-state,
task/checklist inventory, or run transcript establishing Wave references/order was
available in this repository. Creation, use during implementation, and alignment of
verification with reference project Waves are therefore **NOT_OBSERVABLE**; do not infer them.

**Confirmed framework gap and correction:** Ready previously required only that the Wave
plan be “updated”; it did not specify semantic Task/Wave split criteria or require all
accepted in-scope Requirements to be assigned. Existing contracts now state those
boundaries using current artifacts. No Wave schema, Board surface, mandatory full-suite
run, or per-Wave subagent rule was added.

**Existing finding status (current framework contracts):** test-cost awareness —
`IMPLEMENTED`; proactive runtime/UI verification — `IMPLEMENTED` (consumer execution is
not inferred); local mxcli/database recipe — `IMPLEMENTED` in current Core, while stale
Reference project installation remains a separate update/recheck; HTML-first/Builder discovery —
`IMPLEMENTED` (actual consumer availability remains session-attested); spawn/model routing
— `PARTIALLY IMPLEMENTED` (actual child-model attestation remains open/unobservable);
LIVE-SP/CLOSED-AUTONOM routing — `IMPLEMENTED`; lifecycle interrupt/resume semantics —
`IMPLEMENTED` as policy/helpers, with context-hook invocation still configuration/runtime-dependent;
SessionStart provisioning normalization — `IMPLEMENTED` (the structural installer normalizer
removes known mxcli provisioning hooks; native mxcli suppression remains unverified without a
pinned project binary); dependency/Core-update management — `IMPLEMENTED` in `update-contract.md`,
without implying automatic provisioning or consumer update.

**Board interface note:** current project-status inventory uses both Wave plan and process
state, but planned scope is narrative/partial and state has no canonical update timestamp.
Any future Wave view should project a stable Wave ID and objective/scope, requirement/task
links, dependencies, phase/gates, explicit blockers/findings, verification references,
completion evidence, and freshness/provenance from those existing authorities. This
finding does not change Board UX or its API.

## Task/Wave Clarification (2026-11-05)

The current Task schema already represents a concrete action (`action`, `status`, optional
`depends_on` and `test`); optional `wave_id` and `workpackage_id` add links, not lifecycle.
A Wave groups the smallest useful set of related Tasks around one completion/recovery outcome.
The deterministic default is **KEEP RELATED WORK TOGETHER**; split only when an independent
outcome, dependency/gate, uncertainty result, recovery checkpoint, parallel path, or materially
separate context/verification makes the split useful. Task count is only a sanity signal.

Reference project's undo/recovery remains a valid conceptual **single Wave**: multiple Tasks inspect,
reconcile/restore, check consistency, and verify the shared outcome “reference project restored to the
intended state.” This is semantic grouping, not an instruction that every Task be a persisted
Task artifact for that historical operation.

Terminology is unchanged: Mission is the durable user objective/scope/completion boundary;
Acceptance Campaign is a Wave-scoped verification grouping; work packages remain optional Task
grouping or delegation handoff. None is added as a required intermediate planning level.

## Mendix-Concord Reality Hardening (2026-11-11)

### Scope and Evidence Boundary

This analysis was performed in the MxAgile framework repository, not in the downstream Mendix
project or its active Concord process. No downstream `AGENTS.md`, `CLAUDE.md`, Company Layer,
user-global Concord configuration, SessionStart log, process environment, stdout/stderr, exit code,
or loaded-instruction transcript was available. The current VS Code tool session did not expose the
Concord or Studio-Pro-MCP tool namespaces. Consequently, the exact production startup path and the
reported effective hook execution remain `NOT_OBSERVABLE`; they are not classified as “hook absent”
or “hook failed.”

### Confirmed Framework Facts

- `.vscode/mcp.json` in this framework repository declares `concord-v2-mcp` as a stdio server and
  `mendix-studio-pro` as an HTTP server at `localhost:7782`. This proves configuration only, not a
  live endpoint, same-project identity, loaded instructions, or write authorization.
- The configured Concord shim `scripts/start-concord-mcp.ps1` resolves a root `.mcp.json`. This
  framework workspace has no root `.mcp.json`; it does have `.vscode/mcp.json`. The shim therefore
  cannot be used to prove the consumer project's Concord startup. The downstream project may have
  a different configuration; this needs its read-only inventory before any correction.
- `install-core.ps1` structurally normalizes Claude `.claude/settings.json`, removing only
  unambiguous mxcli provisioning/bootstrap SessionStart hooks and preserving foreign/unknown hooks.
  The normalization does not emit a Lifecycle Re-Sync. The opt-in Claude compaction adapter is
  separate and requires explicit hook installation. No Concord SessionStart adapter is verified.
- Managed project instructions place Lifecycle Re-Sync before Brain and generic orientation, but
  startup delivery authorization is instruction-driven; no universal pre-tool hook can intercept
  Studio-Pro-MCP writes. The Mendix-Concord host's support for such interception is unknown.
- The C2/operating-mode contract separates LIVE-SP routing from operation authorization. A
  successful C2 route selects a permitted tool; it does not create mission, wave, scope, or gate
  authority. Capability tests verify this distinction.
- The Concord agent-delegation adapter is explicitly `unknown` for named agents, generic fork, and
  model selection. Concord MCP is a capability source, not a verified agent harness. Other hosts'
  delegation contracts do not transfer to Concord.
- The canonical UI-Agent previously read `.concord/scratch/process-state.yaml` directly to select
  its mode, contradicting the lifecycle authority contract. It now requires Startup Re-Sync and
  treats tracked `planning/lifecycle/process-state.yaml` as primary; scratch remains supplementary.
- Deep visual/runtime contracts already exist: Analyze/Verify preflight, executable mockup
  materialization, seven-dimensional parity, role/state coverage, and the Mendix-aware Playwright
  path. The UI-Agent previously bound Analyze to Discovery (`STATIC`) and Verify to Verifying
  (`BROWSER`), with no explicit request-intent override for a full gap/blocker request.
- Design Contract `source_superseded_by` was already preserved in story-spec provenance, but the
  canonical Requirement schema had no successor field and the artifact index had no REQ-to-REQ
  supersession edge. The worked example also pointed the new REQ back to the old REQ. These are
  concrete pipeline defects, independent of the unknown Concord hook.
- The Board server already had bounded background snapshot revalidation, metadata signatures, and
  source-churn retries. The browser had no revision polling. The Waves register was lexicographic;
  the separate Timeline API is newest-first for pagination and Recent Activity.
- Active bundle revision authority and Page-inventory drift were already computed, but a Page Hub
  without a matching `screen_ids` binding could fall back to its old mockup path. HTML-first source
  visibility was registry-only, and the source preview was labeled generically while allowing
  scripts in a sandbox.

### Root-Cause Classification

| Classification | Finding |
|---|---|
| PRIMARY ROOT CAUSE (framework) | Delivery authorization and tool routing are separate policies, but the Concord path has no verified instruction-injection/SessionStart contract and no universal tool-level mutation guard. The effective first broken invariant in the reported run cannot be located without downstream host evidence. |
| CONTRIBUTING FACTOR | UI-Agent phase selection trusted local Concord scratch rather than re-syncing the tracked lifecycle state; this is corrected in the canonical agent source and generated projections. |
| CONTRIBUTING FACTOR | Lifecycle phase alone selected STATIC Analyze versus BROWSER Verify; a request-depth evidence matrix now makes full gap/visual/dynamic intent require browser evidence without advancing lifecycle phase. |
| CONTRIBUTING FACTOR | Write-capable child context previously omitted explicit skills, capabilities, evidence destinations, and effective-model observability; the existing Handoff envelope is expanded. It remains host-consumed, not a Concord-enforced hook. |
| PRIMARY ROOT CAUSE (pipeline) | Canonical REQ supersession had no canonical `superseded_by` field or graph edge, allowing old accepted requirements to remain active without a machine-readable successor. It is now explicit, projected, and linked; ambiguous mappings are not inferred. |
| PROJECTION DEFECT | The Board did not refresh its browser snapshot, and Page Hub could mix an old inventory target with a newer accepted target without making the active revision primary. Both projection behaviors are corrected; the Board remains read-only. |
| PROJECTION LIMITATION | Unregistered HTML is not exhaustively discovered from arbitrary Mendix model/theme code. The Board now says “not registered in UI inventory” rather than claiming the source does not exist; unknown candidate associations remain unresolved. |
| PREVIEW LIMITATION | The Board cannot assemble a Mendix runtime page from source HTML. Its source preview is now labeled as a raw fragment/document source preview, lists direct CSS/JS references, disables script execution, and is explicitly not runtime or parity evidence. |
| UNSUPPORTED HOST CAPABILITY | Concord's named-agent/fork and model-selection support, effective child model, and loaded-skill evidence remain unknown. The reported “Opus requested / Sonnet 4.6 shown” cannot be resolved from this repository. |

### Changes and Verification

The framework now: polls a cached projection revision every two seconds; sorts Wave IDs in stable
natural order; renders Project Timeline oldest-to-newest while retaining newest-first API paging and
Recent Activity; starts the installed Board on a free loopback port with optional browser opening;
requires a canonical delivery envelope for write-capable children; makes supersession explicit; and
reports active-target drift, preview class, and direct CSS/JS dependencies. Startup instructions now
state that LIVE-SP/tool availability is not delivery authorization. These measures strengthen the
framework contract but do not claim a host-enforced Concord write intercept.

Focused checks passed during implementation, including Startup Priority, SessionStart normalization,
Lifecycle State, C2/C1 routing, Delegation/Handoff, Project Status, Artifact Index, Board HTTP,
Board Performance, External Reconciliation, Gallery, Injection, Core Provenance, and Chromium
Page-Hub viewport checks. The current full Release Gate result is recorded separately from the
historical 2026-11-03 FAIL/INCOMPLETE baseline after its single final run.

### Still Required for the Downstream Concord Finding

To determine whether the reported session used a different host path, collect read-only evidence
from that downstream project: effective `AGENTS.md`/`CLAUDE.md` and Company Layer instructions;
the actual `.vscode/mcp.json` and any `.mcp.json`/global Concord config; whether the session was new,
reused, or compacted; Concord process CWD/environment; exact child command; hook event/output/exit
code; active tool inventory; and post-incident branch/HEAD/lifecycle state. Until then, host startup,
instruction loading, C1 invocation, tool presence, and effective child model remain unverified.
