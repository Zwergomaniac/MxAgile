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

## Credential and Configuration Discovery Before Runtime Start

Before attempting to start the local runtime, automatically discover project credential
and configuration sources.

Required pre-start discovery (in order):

1. **Inspect `.env.mendix`** — project-local credential file; check required keys
2. **Inspect other local config** — `.env*`, mxcli configuration, project settings
3. **Classify each required credential** — PRESENT / MISSING / EMPTY / INVALID
4. **Use discovered credentials** — do NOT fall back to assumed defaults when a project
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

Preference order:

1. Existing project or runtime configuration (if present, e.g. `.env.mendix`)
2. Normal `mxcli run --local` behavior (mxcli defaults)
3. Supported provisioning options (`--ensure-db` where environment supports it)
4. Supported fallback options (`--db-type` alternatives)
5. Explicit developer decision only when genuinely required

Do not hardcode PostgreSQL or HSQLDB as universal defaults. Different environments
(native Windows, devcontainer, CI) have different database availability.

If runtime startup fails with a database error: first perform credential discovery per
`policies/credential-discovery.md` before asking the developer. Use mxcli-supported
diagnostics and options. A DB-AUTH failure after correct credential discovery is a
diagnostic matter — not authorization for credential mutation.

## Verification Invariants

These hold at all times:

- Application starts successfully ≠ Verification started
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
