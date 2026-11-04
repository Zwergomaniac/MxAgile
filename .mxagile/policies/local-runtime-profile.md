# Local Runtime Profile

Authoritative contract for project-declared local runtime configuration in MxAgile.

## Purpose

A project's local runtime environment often differs from what mxcli derives automatically from
the `.mpr` filename or its built-in defaults. This policy defines how projects declare, discover,
and apply project-specific local runtime configuration so that agents can start the correct
runtime consistently, without trial-and-error.

Related policies:
- `policies/tool-instruction-conflict.md` — technical source authority, tool selection, and capability conflicts
- `policies/development-runtime.md` — warm local loop, when to start/stop, verification invariants
- `policies/credential-discovery.md` — credential discovery order, secret safety, bootstrap contract
- `policies/runtime-strategy.md` — Local First, Docker By Verification Need escalation model
- `policies/runtime-configuration-reconciliation.md` — on-demand constant/configuration discrepancy diagnosis

## Project-Declared Local Runtime Profile

Projects declare local runtime configuration in `mxagile-project.yaml` under the `local_runtime`
key. See `.mxagile/schemas/mxagile-project.schema.json` for the full field contract.

### Company Layer Runtime Defaults

The current Company Layer contract does not define a machine-readable runtime-default schema
or active runtime-profile source. The recipe resolver MUST NOT scan `.mxagile/layers/` or infer
values from arbitrary layer files. Runtime values must be present in the project-declared
`local_runtime` profile or be supplied as an explicit session override. Adding Company Layer
runtime defaults later requires a canonical schema and explicit source/provenance contract.

## mxcli Binary and Command Contract

Before every mxcli invocation, identify any project-owned binary path/version declaration in
the current project instructions or configuration. Resolve that exact path with the
distributed helper; when no path is declared, the project's canonical root binary is
selected before PATH:

```powershell
$resolveMxcliParams = @{ ProjectRoot = $ProjectRoot }
if ($projectDeclaredMxcliPath) {
   $resolveMxcliParams.ConfiguredPath = $projectDeclaredMxcliPath
}
$resolvedMxcli = & .mxagile/tools/Resolve-MxAgileMxcli.ps1 @resolveMxcliParams
$mxcliPath = ($resolvedMxcli | ConvertFrom-Json).path
```

Omit `-ConfiguredPath` when no project path is declared. Run `& $mxcliPath --version` and
record the absolute path and exact version as non-secret preparation metadata. Use that
same path for every command in the operation. Do not invoke bare `mxcli` or choose by PATH
precedence.

If the project-local binary is missing, use the canonical `install-mxcli.ps1` acquisition
path where installation is authorized, or report the missing-tool prerequisite. PATH may
be used only when the project contract explicitly permits it; then pass
`-AllowPathFallback` and report `PATH_EXPLICIT_FALLBACK`. A missing explicitly declared
binary must never silently fall through to a different executable.

Before using a version-sensitive command or flag, inspect its command-specific `--help` or
the capability contract using the selected `$mxcliPath`. Do not infer support from a skill,
another mxcli version, or a remembered invocation. If help contradicts the required command
contract, stop with `TOOL_CAPABILITY_GAP`; do not switch binaries or silently alter the
requested behavior. Resolve competing instructions using
`policies/tool-instruction-conflict.md`.

## Runtime Capability Resolution

This is the single capability-resolution path for runtime, UI/functional parity, acceptance,
browser, and visual verification. Run it before database credential discovery or any
environment/credential escalation whenever a local runtime may be needed.

Use the existing project-distributed `Resolve-MxAgileMxcli.ps1` with `-ResolveRecipe` for
the machine-readable recipe. Pass the current structured C2 result through
`-OperatingModeResolutionJson`; this resolver does not repeat Studio Pro detection or call
MCP tools. It resolves only the selected project binary, obtains that binary's `--version`
and `help run`, reads the declared project runtime profile, and returns either
`status: RESOLVED` with the complete recipe or an explicit blocked/ambiguous result. Do not
start the runtime unless the status is `RESOLVED`. Optional backend, DB-name override,
detached-start, and runtime overrides are explicit request inputs; they do not override the
binary's advertised syntax. No repository-wide discovery or automatic startup invocation is
performed.

1. Determine the current operating mode and permitted tool authority per
   `policies/operating-mode.md`. For runtime work, this selects the authorized project tool;
   it does not imply a database backend or prove that a capability exists.
2. Resolve the project-declared or project-local mxcli using the resolver above. Record its
   absolute path, source, and exact `--version`. Never substitute a PATH mxcli unless the
   project contract explicitly permits that fallback.
3. Ask that exact binary for its `run` command help. Use the help invocation advertised by
   that binary (the current mxcli form is `help run`; use an advertised equivalent only when
   the binary does not support it). Do not use remembered syntax or help from another version.
4. From the returned help, determine whether autonomous local run is supported, which
   isolated/local database backends it offers, and the exact option spelling, values, and
   placement needed to select one. The help output from the resolved binary is the authority
   for concrete CLI syntax; MxAgile policies define only intent and routing requirements.
5. Apply this route order:
   - Honor an explicit verification target that requires a particular environment/backend,
     and project policy such as `runtime.verification: docker`.
   - Otherwise, for `local_first`, choose a supported isolated local backend offered by this
     mxcli for verification before requiring an external database. A declared `db_type` is
     provisioning metadata, not by itself a requirement to use that backend for parity.
   - Use an external database only when the verification contract requires it, no suitable
     local backend is offered, or the selected local route cannot provide the required
     evidence. State the reason before changing routes.
   - For `purpose: implementation` or `purpose: development`, honor a declared
     `local_runtime.db_type` as the project's interactive runtime backend. If the selected
     binary does not advertise that backend as local, block with a capability result; never
     substitute PostgreSQL merely because the declared HSQLDB recipe is unavailable.
6. Construct the invocation only from this binary's help and the resolved project profile.
   Do not copy backend options or syntax into consumer-specific instructions. Do not retry
   another backend or binary silently.

### Resolved Runtime Recipe

Keep these three stages distinct:

1. **Capability discovery** records what the selected mxcli version actually supports.
2. **Recipe resolution** combines that evidence with operating mode, verification purpose,
   project runtime profile, and applicable Core defaults into one complete recipe.
3. **Invocation** executes that recipe without reconstructing, dropping, or substituting
   arguments.

Before startup, the coordinating agent MUST resolve and publish one `resolved_runtime_recipe`
in the active mission/verification context. If UI, parity, visual, browser, and acceptance
work is delegated, every handoff MUST reference the same recipe artifact/context; do not
resolve separate recipes per consumer. A consumer without the recipe must stop before runtime
startup and request it from the coordinator, not rebuild it locally. The recipe MUST contain,
at minimum: verification purpose and requested capability;
operating mode and tool authority; absolute executable path, resolution source, and exact
version; evidence of discovered local-run/backend capability; selected backend class and
project/environment/database identifier with its source; the complete executable argument
array from the selected mxcli help; expected post-start backend/identifier; and readiness,
fixture, identity, and authentication checks required by the scenario. The recipe is not ready
if any required value or invocation argument is unresolved.

The recipe's argument array is the sole invocation authority. A consumer MUST execute the
resolved executable and arguments exactly; it MUST NOT rebuild the command from known flags,
append a guessed option, or omit an argument because it appears unrelated to the selected
backend. If any argument must change, the central resolver must re-resolve and republish the
entire recipe before execution. Persisted recipes and handoffs contain no secret values: a
secret-bearing argument is represented by its authoritative key/reference and redacted in
reports. The runtime owner resolves that reference only at the credential-consuming operation;
the actual value is never copied into the recipe artifact or agent handoff.

External mxcli skill examples for `run --local` describe that tool's standalone defaults; they
are not C1 recipes. C1 MUST NOT rely on an mxcli default or derive `db_name` from the `.mpr`
filename. The database identity must come from `local_runtime.db_name` or an explicit,
authorized session override, and C1 emits it using the exact option advertised by the selected
binary. Do not infer or rediscover identity from the project folder or deployment files.
Without an explicit identity, C1 blocks with `DB_IDENTITY_UNRESOLVED`.

### Post-Launch Recipe Verification

After launch, verify the achieved state against the same recipe before interpreting login or
fixture failures:

- Confirm the runtime is reachable using the existing readiness gate.
- Confirm the selected backend and database/environment identifier from authoritative startup
  output or a supported runtime-status/inspection command. If the tool does not expose a
  value, record `NOT_EXPOSED`; do not claim it was verified.
- Check the scenario's required fixture/data state, then test identity/role availability, then
  authentication, keeping each result separate.
- If a required recipe argument was omitted/rejected, or observed backend/identifier differs,
  classify `RUNTIME_RECIPE_MISMATCH`, invalidate downstream fixture/login diagnosis for this
  attempt, and re-resolve/re-run the complete recipe. Do not report the resulting empty
  database or login failure as an independent PostgreSQL, fixture, or credential root cause.

Only mark `RUNTIME_VERIFICATION_READY` when runtime readiness and every fixture, identity,
and authentication prerequisite required by the verification scenario are confirmed.

An external PostgreSQL/database failure MUST NOT trigger a credential request until this
resolution has completed and all suitable local routes for the verification purpose have been
considered. Discover database credentials only for the selected route. Test-login credentials
are a separate prerequisite and are checked before browser login, not used as a gate for
starting a local runtime that does not require them.

### Runtime Failure Layers and Evidence

Use the closest existing MxAgile classification; the uppercase labels below are diagnostic
layers, not additional lifecycle states:

| Layer | Classification |
|---|---|
| No permitted/resolved project mxcli | `TOOL_RESOLUTION_FAILURE` (`TOOL_CAPABILITY_GAP` when the required command cannot be verified) |
| No suitable isolated local backend in the resolved mxcli help | `LOCAL_RUNTIME_CAPABILITY_UNAVAILABLE`; continue only to a justified route allowed by `runtime-strategy.md` |
| Selected local capability exists but startup fails | `LOCAL_RUNTIME_START_FAILED` / existing `RUNTIME_START_FAILED` or `TEST_INFRASTRUCTURE_GAP`, based on observed cause |
| Runtime is reachable but required seed/demo data is absent | `FIXTURE_BLOCKED` / `MOCK_DATA_UNAVAILABLE` |
| Runtime and fixture exist but requested identity/role is unavailable | `TEST_IDENTITY_BLOCKED` / existing `TEST_IDENTITY_UNAVAILABLE` or `ROLE_SWITCH_BLOCKED` |
| Runtime, fixture, and identity exist but the declared auth route prevents login | `AUTHENTICATION_BLOCKED` / existing `AUTHENTICATION_INFRASTRUCTURE_FAILURE` or `CREDENTIAL_VALIDATION_FAILED`, based on evidence |
| All prerequisites required by the scenario are verified | `RUNTIME_VERIFICATION_READY` |

Never infer or try default/demo credentials. Use only current authoritative project,
Company-Layer, fixture, or test-identity declarations. A missing fixture or identity after a
successful local runtime start is not a PostgreSQL failure.

The mission/verification report MUST make the route reproducible without secrets. Record:
requested capability and verification purpose; operating mode/tool authority; resolved mxcli
path, source, and version; discovered local-run capability and offered backend class; selected
route/backend; whether a fallback was used and why; runtime start/readiness result; fixture
state; test-identity and authentication state; and the exact user-escalation reason, if any.
Never record credential values, tokens, or credential-bearing connection strings.

## Browser Base URL and Allowed Origin

Before Playwright/browser navigation, resolve the exact URL for the selected project and
runner:

1. An explicit current-session URL override, when authorized for this verification.
2. `mxagile-project.yaml local_runtime.app_url` when declared.
3. The selected runner's existing project configuration (`baseURL` or equivalent) when no
   project `app_url` is declared.
4. The schema/Core default `http://localhost:8080` only when no higher source exists.

Read the selected runner's configuration as well: for `playwright-cli`, inspect
`.playwright/cli.config.json` including `network.allowedOrigins`; for `@playwright/test`,
inspect the project `playwright.config.*` including `use.baseURL`, browser channel/binary,
and projects/viewports. These are runner configuration, not interchangeable sources for
the canonical project URL. If project `app_url` and a runner `baseURL` disagree, resolve the
project/tool contract conflict before navigation. Never silently replace the project URL.

Compare origins exactly: scheme, host, and effective port must match. `localhost` and
`127.0.0.1` are different origins even if they reach the same loopback interface. When an
`allowedOrigins` list exists, the selected URL's origin must be present in that list. An
allowlist authorizes an origin; it does not select or rewrite the base URL. Preserve any
configured base path when navigating.

If a failed attempt used a different origin than the resolved project URL, compare the
attempted URL with the configured `app_url` and `allowedOrigins`. When the mismatch is
confirmed, perform exactly one controlled retry with the canonical URL. If it succeeds,
classify the cause as `ORIGIN_MISMATCH`. If the canonical-origin attempt also fails, stop
with the observed browser failure and compact evidence; do not generate speculative
firewall, extension, enterprise-policy, loopback, web-security, browser-swap, or API/OQL
workaround hypotheses. Do not change browser binaries, security flags, Playwright versions,
listen addresses, or mxcli versions as part of this check.

### Non-Secret vs. Secret Values

`local_runtime` contains only NON-SECRET configuration and SECRET REFERENCES:

| Kind | Example | Stored in |
|---|---|---|
| Non-secret config | `db_type`, `db_name`, `db_host`, `app_port` | `mxagile-project.yaml` (tracked) |
| Secret reference | `db_password_env_key: MENDIX_DB_PASSWORD` | `mxagile-project.yaml` (key name only) |
| Secret value | The actual password | `.env.mendix` (gitignored, never tracked) |

Do NOT store actual usernames, passwords, tokens, or DSNs in `mxagile-project.yaml`.
Do NOT copy secret values out of `.env.mendix` into any tracked artifact.

### Example Project Profile

```yaml
# mxagile-project.yaml (project root)
local_runtime:
  db_type: hsqldb
  db_name: default
  constant_overrides:
    - name: UserCommons.DisableMxAdmin
      value: "False"
      purpose: "Enables local bootstrap admin login disabled by production default"
  app_port: 8080
  startup_timeout_seconds: 120
  admin_username_env_key: MENDIX_APP_ADMIN_USER
  admin_password_env_key: MENDIX_APP_ADMIN_PASSWORD
```

---

## Configuration Precedence

The C1 resolver is the sole authority that combines request overrides, the project
`local_runtime` profile, and applicable Core defaults. Do not reproduce its precedence table
or resolve those values independently in consumers. The selected binary's current help remains
the only authority for backend and CLI syntax.

---

## Database Identity

There is no framework-wide database identity default. The recipe composer requires an explicit
`local_runtime.db_name` or an authorized request override; otherwise it returns
`DB_IDENTITY_UNRESOLVED` and does not start the runtime. Project display names, folder names,
`.mpr` filename stems, and mxcli's implicit default are never identity sources. A project may
explicitly declare `default` if that is the identity required by its fixture/seed contract; C1
then reports that source as `PROJECT_DECLARED`.

```yaml
local_runtime:
   db_name: <explicit-project-database-name>
```

If the identity cannot be expressed with syntax advertised by the selected mxcli, the recipe
is blocked with `DB_IDENTITY_CONTROL_UNAVAILABLE`; do not start and do not guess another name.
Do not create a different database automatically to bypass an unavailable identity.
Credential discovery and recovery remain owned by their respective policies.

---

## Runtime Constant Configuration

`local_runtime.constant_overrides` is project configuration validated by the project schema.
Constant ownership, secret references, and Studio Pro/headless discrepancy diagnosis are
on-demand in `policies/runtime-configuration-reconciliation.md`. C1 includes overrides only when
selected-binary help confirms support; it owns the complete invocation.

---

## Bootstrap Login Contract

The lifecycle for obtaining a testable local application session is:

```
1. DISCOVER CREDENTIAL SOURCE
   Read credential_source from mxagile-project.yaml (default: .env.mendix)
   Follow full credential discovery order per policies/credential-discovery.md

2. IDENTIFY BOOTSTRAP ADMINISTRATOR REFERENCES
   Read admin_username_env_key and admin_password_env_key from local_runtime
   (or Company Layer credential declarations)
   Look up the values in .env.mendix — do NOT assume default values

3. VALIDATE REQUIRED VALUES ARE PRESENT
   Classify each login key: PRESENT / MISSING / EMPTY.
   If missing, enter SECRET_INPUT_REQUIRED per credential-discovery.md before attempting
   that login. Missing login credentials do not by themselves block local runtime startup.

4. START LOCAL RUNTIME WITH THE RESOLVED RECIPE
   Complete capability discovery and publish `resolved_runtime_recipe` as defined in the
   Runtime Capability Resolution section above. Resolve DB identity per
   development-runtime.md — DB Identity Resolution, then map it to the selected mxcli syntax
   using that exact binary's help. The recipe MUST include every required argument, including
   backend and database/environment identity. Consumers execute its executable and argument
   array unchanged; they MUST NOT reconstruct the command from this section or from remembered
   examples. Do NOT use mxcli's `.mpr`-derived db_name for autonomous execution.
   Report the resolved identity and source, runtime mode, backend class, and non-secret
   configuration before starting.

5. WAIT FOR APPLICATION READINESS
   Track pipeline stages (see Runtime Pipeline State Model below)
   Do NOT authenticate until APPLICATION_REACHABLE stage is confirmed
   Do NOT consider BUILD_SUCCEEDED as APPLICATION_REACHABLE

6. AUTHENTICATE
   Use configured bootstrap administrator credentials from .env.mendix
   Do NOT print, log, or record password values anywhere

7. VALIDATE EXPECTED BOOTSTRAP UI / IDENTITY
   Confirm the authenticated session shows expected role/page
   Record prerequisite_state.test_identities: ready in process-state

8. CONTINUE ROLE / BOOTSTRAP WORKFLOW
   Proceed with the blocked lifecycle activity
```

### Secret Safety in Bootstrap Login

- Never print passwords in any output, log, screenshot, or tracked artifact.
- Do NOT persist usernames/passwords into any tracked state file.
- Non-secret demo usernames (explicitly classified as public test identities) may appear in
  process-state `blocked_operation` for auto-resume context.
- After bootstrap, record only non-secret readiness classifications in process-state.

---

## Runtime Configuration Exception

If the project-declared constant set does not explain an observed Studio Pro/headless behavior
difference, or the effective local bootstrap behavior is in question, load the on-demand contract
in `policies/runtime-configuration-reconciliation.md`. It owns discrepancy classification,
developer confirmation, identity-workaround prohibitions, and downstream acceptance. The C1 recipe
remains the only authority for any resulting runtime invocation.

---

## Runtime Pipeline State Model

The local runtime startup has distinct stages that agents must track and distinguish.

Do NOT use a single "RUNNING" state for the entire startup sequence.

### Canonical Stages

| Stage | Meaning | Agent Contract |
|---|---|---|
| `PREREQUISITE_DISCOVERY` | Credential and config discovery in progress | Not yet started |
| `DEPENDENCY_SYNC` | mxcli dependency/Gradle sync in progress | Watch for abnormal stall |
| `BUILD_IN_PROGRESS` | mxbuild compilation underway | Not started |
| `BUILD_SUCCEEDED` | mxbuild completed successfully | NOT APPLICATION_REACHABLE |
| `RUNTIME_STARTED` | Mendix runtime process launched | Not yet HTTP-reachable |
| `APPLICATION_REACHABLE` | HTTP endpoint responds (login page loads) | May attempt authentication |
| `BROWSER_RENDERED` | Playwright-controlled browser has loaded the application | Ready for UI interaction |
| `AUTHENTICATED_SESSION_READY` | Bootstrap login completed, correct role/page confirmed | Ready for scenario execution |

### Forbidden Equivalences

Build success MUST NOT be treated as application readiness:

```
BUILD_SUCCEEDED != APPLICATION_REACHABLE
APPLICATION_REACHABLE != AUTHENTICATED_SESSION_READY
RUNTIME_STARTED != BROWSER_RENDERED
```

### Readiness Detection Preference Order

Use the most authoritative available signal. Do NOT default to process-tree heuristics.

1. **mxcli machine-readable output** — check whether mxcli emits a readiness event or
   structured log entry indicating the application is listening
2. **HTTP health/application response** — poll the configured `app_url` until it returns
   a valid HTTP response (login page or application root)
3. **Runtime log output** — watch for documented mxcli/Mendix runtime readiness messages
4. **Port/listener check** — verify the configured `app_port` is accepting connections

Do NOT rely on Windows `wmic` process-tree queries as the PRIMARY readiness signal.
Process-tree heuristics are fragile across environments. Use them only as a supplementary
diagnostic when authoritative signals are unavailable.

If MxAgile currently lacks an authoritative signal for a stage, document this as a gap
that belongs in mxcli, not a reason to hard-code platform-specific workarounds.

### Stage Tracking in process-state

Record the achieved pipeline stage in `prerequisite_state.runtime_pipeline_stage` (see
`.mxagile/schemas/process-state.schema.json`). This enables accurate resume after interruption.

---

## Runtime Lifecycle Semantics

The C1 recipe selects an interactive or autonomous lifecycle from the requested purpose and
the selected binary's current help. Consumers MUST use that recipe unchanged; this policy does
not define runtime command syntax.

See `policies/development-runtime.md` — Runtime Modes for the full mode contract.

### Interactive Mode Startup Sequence

```
1. Cold start: mxcli dependency sync + mxbuild compilation + runtime boot
2. APPLICATION_REACHABLE confirmed (HTTP response)
3. BROWSER_RENDERED confirmed (Playwright loads application)
4. AUTHENTICATED_SESSION_READY confirmed (bootstrap login validated)
5. Watch loop active: mxcli detects model changes and applies them without full restart
```

### Autonomous Mode Startup Sequence

```
1. Cold start: mxcli dependency sync + mxbuild compilation + runtime boot
2. APPLICATION_REACHABLE confirmed (HTTP response)
3. BROWSER_RENDERED confirmed (Playwright loads application)
4. AUTHENTICATED_SESSION_READY confirmed (bootstrap login validated)
5. Ready for verification — no watch loop; runtime serves requests until terminated
```

Agents MUST NOT begin Playwright interaction until BROWSER_RENDERED is confirmed.
Agents MUST NOT begin role/scenario execution until AUTHENTICATED_SESSION_READY is confirmed.

If the selected binary manages cold-start, readiness, and interactive updates in one invocation,
do NOT add extra restarts or invocation layers.

---

## Dependency-Sync Failure Route

`dependency_sync_state` is a sub-state of `DEPENDENCY_SYNC`, not a second runtime stage. When
there is no observable progress or a Gradle lock is suspected, load the failure-only contract
in `policies/runtime-dependency-recovery.md`. Do not load or execute that recovery procedure for
a normal C1 recipe resolution or a progressing dependency sync.

---

## Playwright Toolchain Reproducibility Policy

### Version Policy

1. **Prefer stable releases** — do NOT use alpha, beta, or release-candidate Playwright versions
   in production verification paths unless explicitly approved and tested.
2. **Declare supported version** — projects should specify a minimum Playwright CLI version
   in their `package.json` or equivalent lockfile.
3. **No unexplained alpha dependencies** — a transitive Playwright alpha package in a
   workflow-critical path must be explicitly identified, approved, and have a documented
   path to a stable release.
4. **Validate compatibility** — before using Playwright for formal verification, confirm the
   installed CLI version meets the declared minimum.
5. **Lockfile behavior** — the Playwright lockfile (npm/yarn/pnpm lock) must be committed and
   respected. Do NOT allow open-range dependency resolution in critical paths.
6. **Browser installation** — ensure `playwright install` has been run for the required browsers.
   Chromium is the canonical default for MxAgile verification.
7. **Update mechanism** — Playwright updates are deliberate, not automatic. An update requires:
   - Version bump in lockfile
   - `playwright install` for new browser binaries
   - Regression test pass before use in verification

### Version Validation

Before formal verification using Playwright:

```
1. Check installed @playwright/cli version
2. Verify it meets the declared minimum (from package.json or project config)
3. If below minimum or on alpha: enter TOOL_VERSION_INVALID state
4. Report the version mismatch — do NOT proceed with verification
5. Await developer resolution (update or explicit approval)
```

### Upstream Finding

**Observation:** In the REAL acceptance run, `@playwright/cli` was older than the available
stable version, and a transitive Playwright alpha package appeared in the dependency graph.

**Expected behavior:** The `ensure-playwright-cli` script and package dependencies should
enforce a minimum stable version and reject alpha transitive dependencies in critical paths.

**Recommended action:** Review `scripts/ensure-playwright-cli.ps1` and the `.playwright/`
`package.json` to add explicit minimum version constraints and alpha-rejection logic.
