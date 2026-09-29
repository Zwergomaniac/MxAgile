# Local Runtime Profile

Authoritative contract for project-declared local runtime configuration in MxAgile.

## Purpose

A project's local runtime environment often differs from what mxcli derives automatically from
the `.mpr` filename or its built-in defaults. This policy defines how projects declare, discover,
and apply project-specific local runtime configuration so that agents can start the correct
runtime consistently, without trial-and-error.

Related policies:
- `policies/development-runtime.md` — warm local loop, when to start/stop, verification invariants
- `policies/credential-discovery.md` — credential discovery order, secret safety, bootstrap contract
- `policies/runtime-strategy.md` — Local First, Docker By Verification Need escalation model

## Project-Declared Local Runtime Profile

Projects declare local runtime configuration in `mxagile-project.yaml` under the `local_runtime`
key. See `.mxagile/schemas/mxagile-project.schema.json` for the full field contract.

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

When multiple sources specify the same local runtime parameter, the authoritative order is:

```
1. Explicit CLI argument (session-scoped, highest priority)
        |
2. mxagile-project.yaml local_runtime section (project-declared)
        |
3. Company Layer local runtime defaults (.mxagile/layers/<id>/runtime-defaults.yml)
        |
4. mxcli-derived defaults (e.g., db_name from .mpr filename, app port 8080)
        |
5. MxAgile Core fallback defaults (lowest priority)
```

**Critical rule:** An mxcli-derived default (level 4) MUST NOT override an explicit project-local
configuration (level 2). If `db_name: default` is declared in `mxagile-project.yaml`, that value
is authoritative. The name mxcli would derive from the `.mpr` filename is irrelevant.

Do not silently fall through to a lower-precedence level if a higher-precedence source exists.

---

## Studio Pro Local Database Compatibility

mxcli derives a database name from the `.mpr` filename (e.g., `MyApp.mpr` → database `myapp`).
An existing Studio Pro local project may use a different database name (commonly `default`).

**Do NOT generalize that every Studio Pro database is named `default`.**

Apply the following contract:

1. **Explicit `local_runtime.db_name` in `mxagile-project.yaml`** — use it, no further analysis needed.
2. **No explicit declaration, but existing Studio Pro evidence is discoverable** — inspect available
   non-secret metadata (project-level settings, mxcli config, `.mendix/` files) to identify the
   likely database name. Report the selected configuration. Do not guess destructively.
3. **No explicit declaration, no discoverable evidence** — use documented mxcli behavior (derived
   from `.mpr` filename). Validate reachability. Report the selected configuration.
4. **Multiple plausible databases exist and evidence is ambiguous** — do not pick one without
   reporting the ambiguity. Request developer input only when ambiguity materially blocks progress.

When a database connection fails after using the derived name, check whether `local_runtime.db_name`
should be declared in `mxagile-project.yaml` before diagnosing the connection further.

---

## Local Runtime Constant Overrides

Projects may declare runtime constant overrides in `mxagile-project.yaml` under
`local_runtime.constant_overrides`.

### Application

Overrides are applied via mxcli `--constant` flags at startup. Each override becomes:

```
--constant "<name>=<resolved_value>"
```

Where `resolved_value` is:
- The `value` field if specified (non-secret)
- The value read from `.env.mendix[env_key]` if `env_key` is specified (secret)

### Constraints

- Constants are project/Company Layer declared. MxAgile Core does NOT hard-code any constant names.
- Non-secret constant values (`value:`) may be stored in tracked `mxagile-project.yaml`.
- Sensitive constant values MUST use `env_key:` references — the actual value stays in `.env.mendix`.
- Local overrides are ONLY applied to local development/test runtime (`mxcli run --local`).
  They are NOT applied to Docker builds, CI, or production environments.
- Agents MUST NOT edit `config.json` as the authoritative mechanism for constant overrides,
  because mxcli may regenerate `config.json` and overwrite manual edits.
- The effective override set (constant names and non-secret values only) MUST be reported before
  startup so the developer can verify the correct set is being applied.
- Runtime startup confirmation that overrides were accepted is required before declaring
  APPLICATION_REACHABLE (see Runtime Pipeline State Model below).

### Example

```yaml
constant_overrides:
  - name: UserCommons.DisableMxAdmin
    value: "False"
    purpose: "Enables local bootstrap admin login disabled by production default"
  - name: MyModule.ApiEndpoint
    value: "http://localhost:9000"
    purpose: "Points to local mock API instead of production"
  - name: MyModule.ApiSecret
    env_key: LOCAL_API_SECRET
    purpose: "Local API secret — value stays in .env.mendix"
```

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
   Classify each key: PRESENT / MISSING / EMPTY
   If MISSING or EMPTY: enter SECRET_INPUT_REQUIRED state per credential-discovery.md
   Do NOT proceed to runtime start until required credentials are PRESENT

4. START LOCAL RUNTIME WITH DECLARED CONFIGURATION
   Apply local_runtime.db_type, db_name, constant_overrides, app_port
   Report the effective configuration (non-secret values only) before starting

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

## Watch-Mode Startup Semantics

`mxcli run --local --watch` is the canonical warm local development loop.

The intended startup semantics are:

```
1. Cold start: mxcli dependency sync + mxbuild compilation + runtime boot
2. APPLICATION_REACHABLE confirmed (HTTP response)
3. BROWSER_RENDERED confirmed (Playwright loads application)
4. AUTHENTICATED_SESSION_READY confirmed (bootstrap login validated)
5. Watch loop active: mxcli detects model changes and applies them without full restart
```

Agents MUST NOT begin Playwright interaction until BROWSER_RENDERED is confirmed.
Agents MUST NOT begin role/scenario execution until AUTHENTICATED_SESSION_READY is confirmed.

If mxcli starts watch mode in a single invocation and manages the full cold-start → readiness
→ watch loop internally, do NOT add extra restarts or invocation layers.

---

## Gradle Dependency-Sync Stall Diagnosis and Safe Recovery

### Root Failure Mode

```
mxcli run --local
    ->
managed Java dependency resolution (Gradle Tooling API)
    ->
Tooling API waits on ~/.gradle/caches/modules-2/modules-2.lock
    ->
lock is owned by a Gradle daemon from a previous completed or interrupted run
    ->
that daemon is alive but performing no build work
    ->
new run makes no progress indefinitely
```

The failure is silent: no error is emitted; the process simply does not advance past DEPENDENCY_SYNC.

---

### Ownership

| Responsibility | Owner |
|---|---|
| Detect DEPENDENCY_SYNC stage | MxAgile |
| Detect lack of progress within the stage | MxAgile |
| Classify stall precisely (not generic BLOCKED) | MxAgile |
| Identify lock-owner PID where technically possible | MxAgile |
| Classify owner as ACTIVE vs STALE | MxAgile |
| Own dependency-sync process lifecycle | mxcli |
| Expose PID of Gradle processes it starts | mxcli (upstream finding) |
| Emit sync-in-progress vs sync-stalled signal | mxcli (upstream finding) |
| Avoid holding lock after build completion | mxcli (upstream finding) |

---

### Detection Contract

Track `dependency_sync_state` in `prerequisite_state` (see `process-state.schema.json`).

| State | Meaning | Trigger |
|---|---|---|
| `not_started` | DEPENDENCY_SYNC stage not yet reached | Before mxcli starts dependency sync |
| `active` | Sync is progressing (Gradle output seen, files changing) | Observable forward progress within progress window |
| `long_running` | Sync has taken longer than expected but progress is still observable | Age > normal_threshold AND progress still visible |
| `stalled` | No observable progress within the stall detection window | Age > stall_threshold AND no forward progress signals |
| `lock_contended` | Lock file exists AND a live non-build process holds it | Stalled AND lock file detected AND owner PID identified |
| `unknown` | Cannot determine state (mxcli provides no signal) | Fallback when no mxcli-readable output is available |

**Critical distinction:** A `long_running` sync must NOT be classified as `stalled` merely because
it exceeds a fixed time threshold. `stalled` requires absence of forward progress signals, not just
elapsed time.

**Forward progress signals:**
- Gradle output lines advancing
- Files under `~/.gradle/caches/` being modified
- mxcli log output showing download/resolution activity
- Gradle daemon log entries (`~/.gradle/daemon/`) showing recent activity

A sync that is slow but still producing output is `long_running`, not `stalled`.

---

### Stall Detection Window

Apply a two-tier threshold:

1. `normal_threshold` — elapsed time within which no progress check is triggered (default: 120s)
2. `stall_threshold` — elapsed time without progress signals after which `stalled` is declared (default: 60s of silence after `normal_threshold`)

Both thresholds may be overridden in `local_runtime.startup_timeout_seconds`.

---

### Lock-Owner Classification

When `dependency_sync_state = stalled`, inspect the lock:

```
1. Locate lock file: ~/.gradle/caches/modules-2/modules-2.lock
2. If lock file does not exist: stall is NOT lock-contention; classify as unknown_stall
3. If lock file exists:
   a. Identify owning process PID using OS-supported locking info (not wmic guessing)
   b. If PID identified: classify owner using the table below
   c. If PID not identifiable: classify as lock_contended (unidentified owner)
```

| Classification | Evidence | Action |
|---|---|---|
| `NO_OWNER` | Lock file exists but no live process holds it | Lock is stale/orphaned; may be deleted safely after confirming no writes in progress |
| `ACTIVE_BUILD` | Owner PID is actively running a Gradle build (output progressing) | Do NOT terminate; report contention; wait or escalate to developer |
| `STALE_LEFTOVER` | Owner PID exists but belongs to a daemon from a previous completed or interrupted lifecycle, no build work active | May be eligible for safe recovery (see Safe Recovery Ladder) |
| `UNIDENTIFIED` | Lock held by unknown process; PID not determinable | Do NOT terminate; escalate to developer with diagnostic info |
| `OWN_LIFECYCLE` | Owner PID was spawned by the current mxcli run | Not a stall — monitor for progress |

---

### Safe Recovery Ladder

Apply recovery in order. Stop at the first step that resolves the stall.

```
STEP 1: REPORT AND WAIT (always first)
    Record dependency_sync_state: lock_contended
    Report: lock file path, owner classification, PID if known
    Wait up to developer_wait_window (default: 30s) for organic resolution

STEP 2: RECOMMEND SUPPORTED COMMAND (when owner = STALE_LEFTOVER)
    Recommend: gradle --stop (stops all daemons for the current user)
    This is a supported Gradle command — not arbitrary process termination
    Await developer confirmation before executing unless in autonomous mode with explicit permission

STEP 3: EXECUTE gradle --stop (with permission)
    Only when:
      - owner = STALE_LEFTOVER confirmed
      - explicit developer permission OR autonomous mode with recovery permission declared
    After execution: verify lock is released before restarting mxcli

STEP 4: ESCALATE TO DEVELOPER (when owner is ACTIVE_BUILD or UNIDENTIFIED)
    Report complete diagnostic: lock path, owner PID, owner classification, recommended action
    Do NOT proceed autonomously when live build work may be interrupted

STEP 5: HARD PROCESS TERMINATION (last resort only — see Hard-Kill Conditions)
    Only when all conditions in the Hard-Kill Conditions section are met
```

---

### Hard-Kill Conditions

Hard process termination of a Gradle/Java process requires ALL of the following positive evidence:

1. `dependency_sync_state = lock_contended`
2. Owner classification = `STALE_LEFTOVER` (confirmed, not assumed)
3. `gradle --stop` was attempted and failed (or is not available in the environment)
4. The owner PID is NOT associated with any active build output in the past N seconds
5. The owner PID was spawned by a previous mxcli lifecycle that has since terminated
6. No user/CI build session is active that could own the PID

When all conditions are met: terminate only the specific stale owner PID. Do NOT terminate all
Java processes or all Gradle daemons.

Hard termination must be recorded in `prerequisite_state.blocked_operation` with evidence.

---

### Prohibited Recovery Actions

**MxAgile MUST NOT automatically kill arbitrary Java/Gradle processes.** Process termination
without positive stale-owner evidence is not canonical MxAgile behavior.

These actions are NEVER allowed as routine or automatic recovery:

| Prohibited Action | Why |
|---|---|
| Delete `~/.gradle/caches/**/*.lock` as startup routine | Deletes locks that may be protecting live builds |
| Kill all Java processes (`wmic ... kill`) | Terminates unrelated development tools, IDEs, servers |
| Kill all Gradle daemons without owner check | May interrupt active builds in other terminal sessions |
| Kill a process merely because it is idle or exists | Idle ≠ orphaned; daemon may be reused by next build |
| Delete `~/.gradle/caches/` or subsets | Destroys build cache; causes long re-download |
| Restart mxcli without releasing the lock | Spawns a competing runtime pipeline |

---

### Idle-Timeout Mitigation (Optional)

A reduced Gradle daemon idle timeout (`org.gradle.daemon.idletimeout` in `gradle.properties`) may
reduce the probability of stale daemons holding locks by causing them to exit sooner after inactivity.

**This is mitigation only, not resolution:**
- The lifecycle problem (lock contention after previous run) still occurs at timeout boundaries
- The timeout does not guarantee the daemon exits before the next run starts
- Projects may already have this configured; do not blindly override it

Evaluation: `gradle.properties: org.gradle.daemon.idletimeout=<ms>` or `--daemon-idle-timeout` flag.

---

### Repeated-Run Contract

A second local run after a stopped or interrupted first run must be safe:

```
RUN #1 lifecycle (completed or interrupted)
    ->
State: runtime_pipeline_stage = any (stopped/failed/complete)
    ->
Before RUN #2: bounded diagnosis
    1. Check whether any mxcli/Gradle process from RUN #1 is still active
    2. Check whether any lock files from RUN #1 are still held
    3. If NO active processes AND NO held locks: proceed with RUN #2 normally
    4. If active processes from RUN #1: apply Lock-Owner Classification
    5. If held locks: apply Safe Recovery Ladder
    ->
RUN #2 proceeds only after resources from RUN #1 are confirmed released or classified
```

**Concurrent run prevention:**
- RUN #2 must not silently spawn competing runtime/build pipelines when RUN #1 still owns resources
- If RUN #1 is still in DEPENDENCY_SYNC or BUILD_IN_PROGRESS: report and block RUN #2
- Record in `prerequisite_state.dependency_sync_state` for session resumability

---

### Integration with Runtime Pipeline Stages

```
PREREQUISITE_DISCOVERY
    ->
DEPENDENCY_SYNC (track dependency_sync_state: active | long_running | stalled | lock_contended)
    ->
BUILD_IN_PROGRESS (only after DEPENDENCY_SYNC completes cleanly)
    ->
BUILD_SUCCEEDED
    -> ...
```

`dependency_sync_state` is a sub-state of `DEPENDENCY_SYNC` pipeline stage.
It does NOT replace or compete with `runtime_pipeline_stage`.
When DEPENDENCY_SYNC completes: `dependency_sync_state = completed` (or absorbed into next stage).

---

### Upstream Finding for mxcli

**Observation:** An idle Gradle daemon retaining `modules-2.lock` causes the next dependency sync to
stall indefinitely without any error or timeout, with no structured signal distinguishing
sync-in-progress from sync-stalled.

**Expected mxcli behavior:**
1. Expose the PID of any Gradle daemon it starts, so MxAgile can trace ownership precisely
2. Detect Gradle daemon lock contention during dependency sync and emit a structured event:
   `{"event":"dependency_sync_stalled","cause":"gradle_lock","lock_path":"...","owner_pid":N}`
3. Either terminate its own stale daemons before dependency sync, or expose a `--kill-daemons`
   option that applies only to mxcli-managed daemons
4. Emit a heartbeat/progress signal during dependency sync (e.g., every 30s) so clients can
   distinguish slow-but-active from stalled
5. Apply a bounded sync timeout with a clear error exit rather than waiting indefinitely

**Impact if not resolved:** MxAgile must use platform-specific process inspection heuristics
(inherently fragile, OS-dependent, not reliably deterministic) instead of authoritative mxcli
signals, resulting in diagnostic uncertainty and risk of incorrect recovery.

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
