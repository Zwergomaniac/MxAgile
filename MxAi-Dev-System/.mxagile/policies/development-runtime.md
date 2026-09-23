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

## Default Inner Development Loop

For runtime-relevant iterative implementation, prefer the warm local development loop:

```
mxcli run --local -p <project>.mpr --watch
```

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

If the development runtime terminates unexpectedly:

1. Classify the problem: application/model defect, environment issue, database prerequisite,
   port conflict, unsupported environment
2. Determine whether restart is useful given the remaining implementation scope
3. Restart if appropriate — do not abandon valid implementation work because of a runtime failure

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

Apply runtime configuration in this explicit order (highest wins):

```
1. Explicit CLI argument (session-scoped)
2. mxagile-project.yaml  local_runtime section
3. Company Layer runtime defaults
4. mxcli-derived defaults (e.g., db_name from .mpr filename)
5. MxAgile Core fallback defaults
```

An mxcli-derived database name (level 4) MUST NOT override an explicit `local_runtime.db_name`
declaration (level 2). If the project declares `db_name: default`, use `default`. Do NOT
silently let mxcli re-derive a different name from the `.mpr` filename.

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

Local runtime may have database prerequisites. MxAgile does not prescribe a universal
database type.

Apply in this order:

1. **`local_runtime.db_type` / `db_name` in `mxagile-project.yaml`** — authoritative when present
2. **Normal `mxcli run --local` behavior** — mxcli-derived database name from `.mpr` filename
3. **Supported provisioning options** — `--ensure-db` where the environment supports it
4. **Supported fallback options** — `--db-type` alternatives
5. **Explicit developer decision** — only when genuinely required

Do not hardcode PostgreSQL or HSQLDB as universal defaults. Different environments
(native Windows, devcontainer, CI) have different database availability.

If runtime startup fails with a database error: first perform credential discovery per
`policies/credential-discovery.md` before asking the developer. Use mxcli-supported
diagnostics and options. A DB-AUTH failure after correct credential discovery is a
diagnostic matter — not authorization for credential mutation.

When no `local_runtime.db_name` is declared and startup fails with a database-not-found error,
consider whether the Studio Pro local database was created with a different name than mxcli
derives from the `.mpr` filename. Inspect available non-secret metadata before prompting the
developer. Full contract: `policies/local-runtime-profile.md — Studio Pro Local Database Compatibility`.

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
