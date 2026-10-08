# Development Runtime

Canonical guidance for warm local development runtime during Implementing.

## Three Concerns

MxAgile distinguishes three independent concerns:

| Concern | Purpose | Tools | Phase |
|---|---|---|---|
| **A. Model Validation** | Syntax, references, consistency | `mxcli check`, `mxcli lint`, `mxcli docker check` | Implementing + Verifying |
| **B. Development Runtime** | Warm local runtime for iterative feedback | `mxcli run --local --watch` | Implementing |
| **C. Formal Verification** | Quality Gate, UI-Agent Verify, Acceptance-Agent | Local or Docker per runtime-strategy, Playwright, mxcli DESCRIBE | Verifying |

A running development app is NOT Verification.

Runtime inspection during Implementing is development feedback.
Formal verification remains in the Verifying phase.

The runtime mechanism for formal verification follows the escalation model in
`policies/runtime-strategy.md`: local runtime preferred (Level 3); Docker only when
container-parity is required or local runtime cannot provide valid evidence.

## Runtime Modes

MxAgile distinguishes two runtime invocation modes. Both use `mxcli run --local`
but differ in `--watch` usage and lifecycle semantics.

### Interactive Implementation Mode

Used during Implementing when a developer/agent is actively iterating on model changes.

| Property | Value |
|---|---|
| `--watch` | PREFERRED |
| Purpose | Hot-apply model changes, avoid full restarts |
| Lifecycle | Foreground/interactive, remains running across iterations |
| Termination | Developer/agent-initiated or session end |
| Phase | Implementing |

Interactive base command:

```
mxcli run --local -p <project>.mpr --watch
```

### Autonomous Verification Mode

Used when an agent needs unattended runtime startup for verification, testing, or
evidence collection. The runtime starts, becomes reachable, serves requests, and
is terminated after verification completes.

| Property | Value |
|---|---|
| `--watch` | NOT_USED |
| Purpose | Start → ready → serve → test → terminate |
| Lifecycle | Background/unattended, no interactive model watching |
| Termination | After verification complete or on failure |
| Phase | Verifying (also used for autonomous Discovery browser evidence) |

Autonomous base command:

```
mxcli run --local -p <project>.mpr
```

`--watch` is omitted in autonomous mode because:
1. Autonomous verification does not modify the model during the runtime lifecycle
2. `--watch` monitors for file changes and may not complete unattended cold-start
   reliably in all background execution contexts
3. The verification loop is start → ready → test, not edit → apply → inspect

### Mode Selection

The runtime mode is determined by the agent's current purpose, not the lifecycle phase:

| Agent / Context | Mode |
|---|---|
| Implementation-Agent iterating on model changes | Interactive |
| Quality Gate runtime check (Verifying) | Autonomous |
| UI-Agent Verify mode | Autonomous |
| Acceptance-Agent campaigns | Autonomous |
| Discovery-Agent browser evidence | Autonomous |
| Developer explicitly requesting `--watch` | Interactive |

Both modes are subject to the same DB Identity Resolution, Credential Discovery,
and Configuration Precedence rules. Only the `--watch` flag and lifecycle semantics differ.

## Default Inner Development Loop

For runtime-relevant iterative implementation, prefer the warm local development loop:

```
mxcli run --local -p <project>.mpr --watch
```

This is the *base command*. The effective command is constructed after full profile resolution.
See § Base Command vs. Effective Command and § DB Identity Resolution below.

`--watch` enables the runtime to detect and apply model changes automatically,
avoiding full restart cycles between iterations.

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
5. **Let `--watch`** handle change propagation where supported

The desired pattern:

```
MDL change
    -> validate (mxcli check)
    -> execute (mxcli exec)
    -> warm runtime applies/reloads change
    -> inspect when useful
    -> adjust
    -> next MDL change
```

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

Before starting the local runtime, read the `local_runtime` section from `mxagile-project.yaml`
(if present). This section declares project-specific configuration that overrides mxcli defaults.

Key fields: `db_type`, `db_name`, `db_host`, `app_port`, `constant_overrides`,
`admin_username_env_key`, `admin_password_env_key`.

**Full contract:** `policies/local-runtime-profile.md`

## Configuration Precedence

For **database name** (autonomous execution), the precedence is:

```
1. Explicit user/session CLI override
2. mxagile-project.yaml  local_runtime.db_name  (project-declared override)
3. MxAgile Core autonomous default:  db_name = "default"
```

mxcli's `.mpr`-derived database name is NOT part of the autonomous db_name precedence.
MxAgile does not delegate database identity to mxcli filename conventions.

For **other parameters** (app_port, constant_overrides, etc.):

```
1. Explicit user/session CLI override  (session-scoped)
2. mxagile-project.yaml  local_runtime section
3. Company Layer runtime defaults
4. mxcli-derived defaults  (e.g., app_port 8080 — but NOT db_name)
5. MxAgile Core fallback defaults
```

## Credential and Configuration Discovery Before Runtime Start

Before attempting to start the local runtime, automatically discover project credential
and configuration sources.

Required pre-start discovery (in order):

1. **Read `mxagile-project.yaml`** — apply `local_runtime` profile per precedence above
2. **Inspect `.env.mendix`** — project-local credential file; check required keys
3. **Inspect other local config** — `.env*`, mxcli configuration, project settings
4. **Classify each required credential** — PRESENT / MISSING / EMPTY / INVALID
5. **Use discovered credentials** — do NOT fall back to assumed defaults when a project
   source exists

If required credentials are MISSING or EMPTY after full discovery:
- Follow the bootstrap flow in `policies/credential-discovery.md`
- Request only the missing keys from the developer
- Never propose credential mutation (ALTER USER, password reset, etc.)
- Auto-resume after the developer populates the canonical secret source

A failed DEFAULT credential does NOT indicate that `.env.mendix` is wrong or missing.
The precedence order is: project-local config wins over framework defaults.

Complete credential discovery contract: `policies/credential-discovery.md`

## Database

### Database Identity (Autonomous Execution)

For autonomous local runtime execution, MxAgile resolves the database name per the
Configuration Precedence above. The Core autonomous default is `"default"`.

Report before startup:

```
effective_db_name: default
source: MXAGILE_CORE_DEFAULT   (or: SESSION_OVERRIDE / PROJECT_DECLARED)
```

Do NOT derive the database name from the `.mpr` filename for autonomous execution.
Do NOT use the project folder name, display name, or any naming convention as the DB
identity source. A hidden derived identity is not acceptable.

If the resolved effective_db_name does not exist or cannot be reached:
- Perform credential and configuration discovery per `policies/credential-discovery.md`
- Classify the actual failure precisely
- Do NOT switch to a project-derived database to make startup succeed
- Do NOT automatically create another database unless the canonical provisioning
  contract explicitly allows it

### Database Type

`db_type` is project metadata and provisioning input. It is NOT an autonomous-runtime flag.
Do NOT emit `--db-type` for `mxcli run --local` unless its CLI flag form is independently
verified for the installed mxcli version via `mxcli run --local --help`.

Do not hardcode PostgreSQL or HSQLDB as universal defaults. Different environments
(native Windows, devcontainer, CI) have different database availability.

### Base Command vs. Effective Command

The *base command* depends on the runtime mode (see § Runtime Modes above):

**Interactive Implementation base command:**

```
mxcli run --local -p <project>.mpr --watch
```

**Autonomous Verification base command:**

```
mxcli run --local -p <project>.mpr
```

The *effective command* is the base command expanded with resolved profile flags.
Agents MUST NOT execute the base command without first completing full profile
resolution — see `policies/local-runtime-profile.md`.

**Canonical effective command — Interactive Implementation** (when `--db-name` is supported):

```
mxcli run --local -p <project>.mpr --watch --db-name default
```

**Canonical effective command — Autonomous Verification** (when `--db-name` is supported):

```
mxcli run --local -p <project>.mpr --db-name default
```

where `default` is the resolved db_name (Core default unless overridden — see § DB Identity
Resolution). Additional constant_overrides and profile flags are appended after DB resolution.

**When `--db-name` is not supported by the installed mxcli:**
Do NOT start autonomously. Classify: `DB_IDENTITY_CONTROL_UNAVAILABLE`.
Report the exact capability gap. Do NOT fall back to `.mpr`-derived database name.

### DB Identity Resolution (Required Before Autonomous Start)

Before an autonomous agent starts a local runtime, it MUST resolve the effective database
identity. Autonomous execution without a confirmed, explicitly-sourced DB identity is unsafe.

```
1. Explicit user/session CLI override present?
   YES  → use it; source: SESSION_OVERRIDE

2. local_runtime.db_name declared in mxagile-project.yaml?
   YES  → use it; source: PROJECT_DECLARED

3. Neither present → apply MxAgile Core autonomous default
        db_name = "default"
        source: MXAGILE_CORE_DEFAULT
```

Do NOT derive the database name from the `.mpr` filename.
Do NOT use project folder name, display name, or any naming convention.
These are NOT acceptable sources for autonomous DB identity.

Record before startup in `prerequisite_state.runtime_config`:

```
effective_db_name: <resolved>
source: SESSION_OVERRIDE | PROJECT_DECLARED | MXAGILE_CORE_DEFAULT
```

A `.mpr` filename rename MUST NOT silently alter the autonomous MxAgile runtime database
identity. Before and after any rename, the autonomous effective db_name remains `"default"`
unless the user explicitly overrides it (source: SESSION_OVERRIDE or PROJECT_DECLARED).

If `--db-name` is not available in the installed mxcli:
- Classify: `DB_IDENTITY_CONTROL_UNAVAILABLE`
- Report the exact capability gap
- Do NOT start autonomously
- Do NOT fall back to `.mpr`-derived name

If runtime startup fails with a database error after correct credential discovery:
This is a diagnostic matter — not authorization for credential mutation.
Diagnose using mxcli-supported tools. Do NOT switch to a different database to make
startup succeed. Full contract: `policies/local-runtime-profile.md — Studio Pro Local
Database Compatibility`.

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

`mxcli run --local --watch` manages the full cold-start → readiness → watch loop in one
invocation. Do NOT add extra restart layers unless mxcli provides evidence that they are needed.

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

## Gradle Lock / Dependency-Sync Handling

If dependency sync appears stalled, classify it precisely before taking any action.

MxAgile responsibility: detect the stage, detect abnormal lack of progress, produce a precise
diagnosis. MxAgile MUST NOT automatically kill arbitrary Java/Gradle processes.

If a Gradle daemon appears to hold a dependency lock:
- Report the lock file path and which daemon may hold it
- Recommend `gradle --stop` (stops user's daemons) if supported
- Escalate to developer if action requires confirmation

Full contract: `policies/local-runtime-profile.md — Gradle Lock / Dependency-Sync Handling`

## Verification Invariants

These hold at all times:

- Application starts successfully ≠ Verification started
- `BUILD_SUCCEEDED` ≠ Application reachable
- `APPLICATION_REACHABLE` ≠ Verification started
- Runtime inspection during Implementing ≠ UI-Agent Verify
- Visually checking work while implementing ≠ Acceptance passed
- `mxcli run --local` succeeds ≠ Wave verified

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

## Watch-Mode Decision

| Context | `--watch` | Reason |
|---|---|---|
| Interactive Implementation | PREFERRED | Enables hot-apply of model changes during iterative development |
| Autonomous Verification | NOT_USED | Verification does not modify models; `--watch` may not complete unattended cold-start in background contexts |
| Background Execution | NOT_USED | Use `mxcli run --local` without `--watch`; wait for `APPLICATION_REACHABLE` via readiness gate |
| Developer-Requested Watch | PREFERRED | Explicit developer request overrides default mode selection |

## Development Runtime vs. Test Runtime

`mxcli run --local` is the **development runtime** — used for warm local development feedback
during Implementing (governed by this policy).

`mxcli test --local` is a **distinct test runtime** contract, if supported by mxcli.

The MxAgile Core autonomous default (`db_name = "default"`) applies to `mxcli run --local`
autonomous execution. A separate verified test-runtime contract governs test-database
identity independently. Do NOT conflate these two contexts.

Do NOT apply development-runtime DB defaults to test-runtime commands or vice versa.
The boundary is: this policy owns `mxcli run --local` database identity.
