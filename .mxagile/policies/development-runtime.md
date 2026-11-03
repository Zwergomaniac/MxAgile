# Development Runtime

Canonical guidance for warm local development runtime during Implementing.

## Three Concerns

MxAgile distinguishes three independent concerns:

| Concern | Purpose | Tools | Phase |
|---|---|---|---|
| **A. Model Validation** | Syntax, references, consistency | Selected project-local mxcli validation capabilities | Implementing + Verifying |
| **B. Development Runtime** | Warm local runtime for iterative feedback | C1-resolved interactive recipe | Implementing |
| **C. Formal Verification** | Quality Gate, UI-Agent Verify, Acceptance-Agent | C1-resolved recipe, Playwright, evidence contracts | Verifying |

A running development app is NOT Verification.

Runtime inspection during Implementing is development feedback.
Formal verification remains in the Verifying phase.

The runtime mechanism for formal verification follows the escalation model in
`policies/runtime-strategy.md`: local runtime preferred (Level 3); Docker only when
container-parity is required or local runtime cannot provide valid evidence.

## Runtime Modes

MxAgile distinguishes runtime intent from invocation syntax. C2 determines permitted tool
authority; C1 resolves the exact binary/version and complete runtime argument array. Consumers
MUST execute `resolved_runtime_recipe` unchanged and MUST NOT reconstruct mxcli commands from
examples in this policy.

### Interactive Implementation Mode

Used during Implementing when a developer/agent is actively iterating on model changes. The
recipe may request watch behavior only when the selected binary advertises the required syntax.

| Property | Value |
|---|---|
| Runtime lifecycle | Interactive / warm |
| Purpose | Hot-apply model changes, avoid full restarts |
| Lifecycle | Foreground/interactive, remains running across iterations |
| Termination | Developer/agent-initiated or session end |
| Phase | Implementing |

### Autonomous Verification Mode

Used when an agent needs unattended runtime startup for verification, testing, or
evidence collection. The runtime starts, becomes reachable, serves requests, and
is terminated after verification completes.

| Property | Value |
|---|---|
| Runtime lifecycle | Unattended / bounded |
| Purpose | Start → ready → serve → test → terminate |
| Lifecycle | Background/unattended, no interactive model watching |
| Termination | After verification complete or on failure |
| Phase | Verifying (also used for autonomous Discovery browser evidence) |

Autonomous verification does not modify the model during the runtime lifecycle. Its recipe
represents the bounded start → ready → verify → terminate sequence; the selected binary's help
owns any corresponding command options.

### Mode Selection

The runtime mode is determined by the agent's current purpose, not the lifecycle phase:

| Agent / Context | Mode |
|---|---|
| Implementation-Agent iterating on model changes | Interactive |
| Quality Gate runtime check (Verifying) | Autonomous |
| UI-Agent Verify mode | Autonomous |
| Acceptance-Agent campaigns | Autonomous |
| Discovery-Agent browser evidence | Autonomous |
| Developer explicitly requesting iterative/watch behavior | Interactive |

Both modes consume the same project profile and authority contracts. Only runtime purpose and
lifecycle semantics differ; exact argv remains owned by the resolved recipe.

## Default Inner Development Loop

For runtime-relevant iterative implementation, resolve an interactive C1 recipe and reuse a
compatible warm runtime. The recipe and selected binary determine whether model changes are
applied continuously or require a restart; this policy does not define the command line.

### When to Start

Start the development runtime when runtime feedback becomes useful.
Do NOT blindly start it at the beginning of every Implementing phase.

Runtime feedback is typically NOT yet useful for:
- Enum creation
- Initial domain model construction
- Structural setup without visual components
- Non-visual preparatory work

Runtime feedback becomes particularly valuable for:
- Pages and navigation
- Interactions and UI behavior
- Microflow behavior observable at runtime
- Validation behavior
- Visual iteration against mockup/UI-inventory obligations

### When to Stop

- When no longer needed for the current implementation scope
- When environment cleanup requires it
- Before transitioning into formal verification that requires a different runtime environment
- The runtime MAY remain running across the Implementing exit if the formal verification
  environment does not conflict — this is an operational decision, not a lifecycle rule

## Runtime Reuse

Avoid unnecessary full runtime restart cycles.

When the agent determines that runtime feedback is useful:

1. **Detect** whether a suitable local runtime is already running
2. **Reuse** it if available and compatible
3. **Start** a new warm local runtime only if none is running
4. **Keep available** across iterative implementation changes
5. Reuse the resolved interactive recipe for subsequent runtime feedback

The desired pattern:

Model change → validate and apply through the authorized project tool route → observe runtime
feedback when useful → adjust → next model change. Model mutation syntax belongs to the selected
tool's current command contract; this policy defines no mxcli argv.

## Recovery

If the development runtime terminates unexpectedly or does not reach APPLICATION_REACHABLE:

### Evidence-First Rule

A startup timeout, startup silence, or failed APPLICATION_REACHABLE probe is an observation,
not a diagnosis. Observation alone MUST NOT establish:
- machine load or insufficient performance
- infrastructure failure
- application defect
- human/external gate

Gather available diagnostic evidence before classifying. Full evidence inventory and bounded
recovery model: `policies/runtime-startup-recovery.md`.

### Recovery Steps

1. Gather diagnostic evidence (mxcli output, stale processes, build log, port state)
2. Classify the failing stage (DEPENDENCY_SYNC, BUILD_IN_PROGRESS, RUNTIME_STARTED, etc.)
3. Inspect for stale/orphan mxbuild or mxcli processes from previous sessions
4. Apply bounded deterministic recovery (see `policies/runtime-startup-recovery.md`)
5. If APPLICATION_REACHABLE is established: resume verification — no new mission
6. If all safe recovery paths exhausted: escalate as TEST_INFRASTRUCTURE_GAP

A local runtime failure during Implementing MUST NOT automatically:
- Fail the lifecycle phase
- Invalidate gate-to-ready
- Transition to Verifying
- Mark completed implementation items as failed

Preserve completed valid implementation work regardless of runtime state.

## Project-Declared Local Runtime Profile

`mxagile-project.yaml` is the project configuration source; its schema owns the profile fields.
Before a runtime start, consume the existing C2 authority and the single C1
`resolved_runtime_recipe` from `policies/local-runtime-profile.md`. The recipe owns the selected
binary/version, supported capability, route, database identity, exact argv, and readiness checks.
This policy describes lifecycle intent only; it does not duplicate runtime flags or DB precedence.

## Runtime Configuration Authority

Project/core precedence, default DB identity, Company Layer boundaries, and supported runtime
overrides are defined only by `policies/local-runtime-profile.md` and the selected project schema.
Do not derive database identity from the project or `.mpr` name, scan layers for runtime defaults,
or reconstruct a route from these lifecycle instructions.

## Credential Gate

Resolve the complete C1 recipe before discovering credentials. Check only credentials required
by that route using `policies/credential-discovery.md`; a suitable local route must not be blocked
by unrelated external-database credentials. Bootstrap/test identity remains a later, separate
readiness gate. The credential policy owns discovery, secret handling, and resume semantics.

## Runtime and Database Identity

The C1 recipe is the sole authority for the effective backend, database/environment identity,
selected binary, and complete invocation. If it is unavailable or cannot express a required
identity, block only that runtime operation with the recipe's explicit result. Never append a
flag, derive a database from a filename, switch routes silently, or reinterpret a database
error as a credential diagnosis. See the C1 policy for the full input/provenance contract.

## Runtime Pipeline State Model

The local runtime startup has distinct stages. Agents MUST distinguish them.

| Stage | Meaning |
|---|---|
| `PREREQUISITE_DISCOVERY` | Credential and config discovery in progress |
| `DEPENDENCY_SYNC` | mxcli/Gradle dependency sync in progress |
| `BUILD_IN_PROGRESS` | mxbuild compilation underway |
| `BUILD_SUCCEEDED` | Compilation complete — NOT yet reachable |
| `RUNTIME_STARTED` | Mendix runtime process launched — NOT yet HTTP-reachable |
| `APPLICATION_REACHABLE` | HTTP endpoint responds (login page loads) |
| `BROWSER_RENDERED` | Playwright browser has loaded the application |
| `AUTHENTICATED_SESSION_READY` | Bootstrap login complete, role confirmed |

Record the achieved stage in `prerequisite_state.runtime_pipeline_stage` in process-state.

**Critical distinctions:**
- `BUILD_SUCCEEDED` ≠ `APPLICATION_REACHABLE`
- `RUNTIME_STARTED` ≠ `BROWSER_RENDERED`
- `APPLICATION_REACHABLE` ≠ `AUTHENTICATED_SESSION_READY`

Full contract: `policies/local-runtime-profile.md — Runtime Pipeline State Model`

## Watch-Mode Startup Semantics

The C1 recipe selects an interactive or autonomous runtime lifecycle from current help evidence.
Do not add restart layers or modify its argv unless a resolved recipe step fails and a fresh
recipe is published.

Agents MUST NOT begin Playwright interaction until `BROWSER_RENDERED` is confirmed.
Agents MUST NOT begin role/scenario execution until `AUTHENTICATED_SESSION_READY` is confirmed.

Full contract: `policies/local-runtime-profile.md — Watch-Mode Startup Semantics`

## Readiness Detection

Prefer authoritative signals over fragile process-tree assumptions:

1. **mxcli machine-readable output** — structured readiness event or log entry
2. **HTTP response from `app_url`** — login page or application root
3. **Runtime log output** — documented Mendix runtime readiness messages
4. **Port listener check** — `app_port` accepting connections

Do NOT use Windows `wmic` process-tree queries as the PRIMARY readiness signal.

Full contract: `policies/local-runtime-profile.md — Readiness Detection Preference Order`

## Dependency-Sync Failure Route

Do not load recovery details for a normal or progressing C1 runtime start. If dependency sync
stalls or a Gradle lock is suspected, use the failure-only contract in
`policies/runtime-dependency-recovery.md`; it owns diagnosis, owner classification, and bounded
recovery.

## Verification Invariants

These hold at all times:

- Application starts successfully ≠ Verification started
- `BUILD_SUCCEEDED` ≠ Application reachable
- `APPLICATION_REACHABLE` ≠ Verification started
- Runtime inspection during Implementing ≠ UI-Agent Verify
- Visually checking work while implementing ≠ Acceptance passed
- Successful development-runtime start ≠ Wave verified

Formal Verifying requirements (Quality Gate, UI-Agent Verify, Acceptance-Agent)
are unchanged and cannot be satisfied by development runtime usage.

## Lifecycle Boundary

The development runtime exists within the Implementing phase as a development aid.

It introduces a second concurrent state dimension:

| Dimension | Example values |
|---|---|
| **Lifecycle state** | `implementing` |
| **Runtime state** | `not_started`, `running_warm`, `stopped`, `failed` |

Runtime state MUST NOT cause a lifecycle transition.

A developer saying "start the app" or "show me the page" during Implementing is a
legitimate development observation request — it does not change lifecycle state.

## Runtime Ownership Model

Before starting, reusing, or terminating a runtime, classify it:

| Classification | Evidence | Action |
|---|---|---|
| `OWNED_RUNTIME` | PID recorded by this MxAgile session; project path matches; ports match | Safe to manage (reuse, monitor, terminate) |
| `REUSABLE_RUNTIME` | Compatible project/config/db; ownership positively identified | Reuse when safe; do not restart unnecessarily |
| `FOREIGN_RUNTIME` | Belongs to another project/session/user | Do NOT terminate; classify and report |
| `STALE_OWNED_RUNTIME` | Previously owned by MxAgile; ownership provable; lifecycle no longer active | May terminate autonomously with evidence |
| `UNKNOWN_RUNTIME` | mxcli process exists but ownership cannot be established | Do NOT terminate; classify and report |

### Ownership Evidence

Sufficient ownership evidence requires at least TWO of:

- PID recorded in process-state by this MxAgile session
- Command-line arguments match expected project path
- Runtime/app/admin ports match expected configuration
- Process start time is consistent with this session's lifecycle

### Termination Rules

Never blindly execute `pkill mxcli`, `killall mxcli`, or arbitrary PID termination.

Before terminating ANY mxcli process:

1. Classify it using the table above
2. Verify ownership evidence (minimum TWO matching signals)
3. Only `STALE_OWNED_RUNTIME` may be terminated autonomously
4. `FOREIGN_RUNTIME` and `UNKNOWN_RUNTIME`: classify and report, do not kill
5. Record termination evidence in process-state

A process MUST NOT be terminated merely because:
- Its executable is mxcli
- It is old
- A port is occupied
- It appears idle

### Stale Process Detection Before Startup

Before starting a new runtime:

1. Check for existing mxcli processes matching the project path
2. Check for existing mxbuild processes matching the project path (they may hold file locks on
   `deployment/web/` or model compilation artifacts independently of mxcli)
3. Classify each process: OWNED / REUSABLE / FOREIGN / STALE_OWNED / UNKNOWN
   (for mxbuild: OWNED_BUILD / STALE_OWNED_BUILD / FOREIGN_BUILD / UNKNOWN_BUILD)
4. If REUSABLE: assess compatibility (project path, db_name, app_port)
5. If compatible REUSABLE: reuse instead of starting new
6. If STALE_OWNED or STALE_OWNED_BUILD: terminate with evidence before starting new
7. If FOREIGN or UNKNOWN (any process type): report and choose alternate path or escalate

Full mxbuild orphan detection and Safe Build Recovery Ladder:
`policies/runtime-startup-recovery.md — Orphan / Stale Build Process Handling`

Record runtime ownership in process-state:

```yaml
prerequisite_state:
  runtime_ownership: owned | reusable | none
  runtime_owner_pid: <PID>
```

## Readiness Gate Contract

A mandatory readiness gate separates runtime startup from any consumer interaction
(Playwright, test execution, authenticated operations).

### Gate Levels

| Level | Meaning | Required Before |
|---|---|---|
| `APPLICATION_REACHABLE` | HTTP endpoint responds with valid page/login | Playwright navigation, any HTTP interaction |
| `BROWSER_RENDERED` | Playwright browser has loaded the application | Any DOM interaction, screenshot, selector query |
| `AUTHENTICATED_SESSION_READY` | Bootstrap login complete, role/page confirmed | Role scenario execution, authenticated tests |

### Prohibited Inferences

Tests MUST NOT infer application readiness from:

- mxcli process existence
- Shell start command returning
- Build compilation succeeding (`BUILD_SUCCEEDED` is not readiness)
- Port number expectation (e.g. 8080)
- Fixed sleep/delay

### Readiness Validation Sequence

Before any Playwright or test interaction:

1. Wait for `APPLICATION_REACHABLE` — HTTP poll until valid response
2. Wait for `BROWSER_RENDERED` — Playwright page load confirmed
3. Wait for `AUTHENTICATED_SESSION_READY` — login + role verification (when auth required)
4. Only then: begin test execution

If readiness is not achieved within `startup_timeout_seconds`:
- Classify as `RUNTIME_STARTUP_FAILURE`
- Do NOT fail application proof points
- Record as `TEST_INFRASTRUCTURE_GAP`

### Startup Timeout

Default: `startup_timeout_seconds` from `local_runtime` profile (default: 120s).
The timeout covers the full pipeline from start to `APPLICATION_REACHABLE`.
Individual stages have no separate timeout; the overall pipeline timeout governs.

## Test Failure Classification (Runtime Infrastructure)

When a test fails, classify the root cause before attributing the failure:

| Classification | Evidence | Correct Action |
|---|---|---|
| `RUNTIME_STARTUP_FAILURE` | Application never reached `APPLICATION_REACHABLE` | Record as infrastructure gap; proof points remain UNEXECUTED |
| `RUNTIME_READINESS_FAILURE` | chrome-error://, connection refused, timeout before page load | Record as infrastructure gap; proof points remain UNEXECUTED |
| `AUTHENTICATION_INFRASTRUCTURE_FAILURE` | Login page loaded but authentication mechanism failed (not credentials) | Record as infrastructure gap |
| `TEST_INFRASTRUCTURE_GAP` | Test tooling failure unrelated to application behavior | Record as gap; do not attribute to application |
| `APPLICATION_DEFECT` | Application reachable + authenticated + test exercised correct path = unexpected result | Route to Implementing |

### Mandatory Classification Before Attribution

This failure mode MUST NOT occur:

```
runtime not ready → Playwright gets chrome-error:// → application PP fails
```

Instead:

```
runtime not ready → TEST_INFRASTRUCTURE_GAP / RUNTIME_STARTUP_FAILURE → application PP remains UNEXECUTED
```

Demo-user switch failures caused solely by an unavailable application MUST NOT be
classified as demo-user/application defects. The runtime must be confirmed operational
before application behavior is evaluated.

## Runtime Mode Decision

| Purpose | Recipe lifecycle |
|---|---|
| Interactive implementation | Warm, iterative runtime feedback |
| Autonomous verification | Bounded start, readiness, evidence, and termination |

The C1 resolver determines whether the selected binary can provide the requested behavior.
Consumers do not select or append version-sensitive options.

## Development Runtime vs. Test Runtime

Development and test runtimes are distinct purposes. Each must use the existing resolver or
test contract that owns its route and identity; do not copy the development profile's DB identity
or options into a test invocation. This policy owns lifecycle intent, not command syntax.
