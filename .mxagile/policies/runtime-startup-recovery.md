# Runtime Startup Recovery

Governs evidence-first startup diagnosis, bounded deterministic recovery, and human-gate
semantics when `mxcli run --local` does not reach `APPLICATION_REACHABLE`.

Related policies:
- `policies/development-runtime.md` — runtime pipeline stages, ownership model, stale process detection
- `policies/local-runtime-profile.md` — Gradle lock/dependency-sync stall diagnosis and recovery
- `policies/runtime-strategy.md` — local-first escalation model
- `policies/test-defect-protection.md` — APPLICATION_DEFECT / TEST_DEFECT / TEST_INFRASTRUCTURE_GAP

---

## Core Principle

A startup timeout, startup silence, or failed APPLICATION_REACHABLE probe is an observation,
not a diagnosis.

Observation alone MUST NOT establish any of:
- machine load or insufficient performance
- infrastructure failure
- application defect
- human/external gate

Root-cause claims require supporting evidence gathered from the available diagnostics before
any classification is recorded or reported.

---

## Startup Failure Response: Evidence-First Model

When a startup attempt does not reach `APPLICATION_REACHABLE` within the configured timeout:

```
STARTUP TIMEOUT / PROBE FAILURE
    →
GATHER DIAGNOSTIC EVIDENCE (see Evidence Inventory below)
    →
CLASSIFY FAILING STAGE
    →
INSPECT STALE / ORPHAN PROCESSES AND RESOURCES
    →
ATTEMPT BOUNDED DETERMINISTIC RECOVERY where authorized
    →
APPLICATION_REACHABLE?
    YES → record recovery; resume pending verification
    NO  → try next materially different justified recovery path
    →
RECOVERY PATHS EXHAUSTED?
    YES → TEST_INFRASTRUCTURE_GAP / external blocker / human gate as appropriate
    NO  → continue next recovery step
```

Attempt all bounded deterministic recovery paths before declaring an external blocker.
Deterministic recovery before human escalation is mandatory: do NOT declare an external
infrastructure blocker or human gate while deterministic recovery paths remain untried.

---

## Evidence Inventory

Collect the following signals before classifying a startup failure. Not all signals will be
available in every environment; record availability.

| Signal | Source | What to check |
|---|---|---|
| Startup command exit state | mxcli process exit code | Non-zero exit; any error message |
| mxcli console output | mxcli stdout/stderr | Error lines, stage markers, last emitted line |
| Build/runtime log files | mxcli-managed log paths | Build errors, runtime crash output |
| mxbuild processes (current session) | Process list filtered to mxbuild | Running / exited; command-line project path match |
| mxbuild processes (previous sessions) | Process list — PIDs NOT from current invocation | File-lock holders on deployment/web paths |
| mxcli processes | Process list filtered to mxcli | Competing runtime instances |
| Deployment/web path lock state | Filesystem lock on `deployment/web/` or equivalent | File locked by a non-current process |
| Port occupancy | `app_port` in use? | Previous session runtime still running |
| Database reachability | Can the resolved db_name be reached? | DB connection error vs runtime error |
| Gradle daemon state | `dependency_sync_state` from process-state | Stall / lock-contention detected (local-runtime-profile.md) |
| Local runtime profile | `mxagile-project.yaml local_runtime` | Misconfigured port, db_name, or constants |
| Prerequisite state | `process-state.yaml prerequisite_state` | Which stage was last reached in this session |

Collect ALL available signals before asserting any root cause.

---

## Failing Stage Classification

Use the Runtime Pipeline Stage Model from `policies/development-runtime.md` to determine
where the pipeline stalled:

| Observed failure point | Most likely stage | First evidence to gather |
|---|---|---|
| mxcli exits immediately or with error | `PREREQUISITE_DISCOVERY` | mxcli exit code and message |
| No build output; no progress | `DEPENDENCY_SYNC` | Gradle lock state (local-runtime-profile.md) |
| Build output stops mid-way; process persists | `BUILD_IN_PROGRESS` | mxbuild process list, deployment/web lock state |
| Build appears to complete but app never responds | `BUILD_SUCCEEDED` | Port occupancy, runtime log, mxbuild exit |
| Runtime started but HTTP probe fails | `RUNTIME_STARTED` | Database reachability, runtime crash log |
| HTTP probe reaches login page but Playwright fails | `APPLICATION_REACHABLE` | Playwright version, browser install, auth config |

Record the classified stage in `prerequisite_state.runtime_pipeline_stage`.

---

## Orphan / Stale Build Process Handling

### Failure Class

A previous local build/runtime attempt may leave mxbuild or mxcli processes alive after the
session terminates. These orphan processes retain file locks on resources required by the next
startup:

- `deployment/web/` — compiled frontend assets
- Model compilation artifacts
- Any mxbuild-managed build cache paths

A new startup attempt competing with an orphan process enters a lock-contention state and
stalls until the orphan releases the lock (which it never will) or until the startup times out.

This failure mode is silent: no error is emitted; the process appears to stall in
`BUILD_IN_PROGRESS`.

### Detection Contract

When a startup stalls at or near `BUILD_IN_PROGRESS` with no error output:

```
1. Identify all running mxbuild processes
2. For each process: classify ownership (see Ownership Classification below)
3. If any process matches STALE_OWNED_BUILD: apply Safe Build Recovery Ladder
4. If no stale process found: check deployment/web/ lock state independently
   (lock file may outlive the process that created it)
5. Record classification in prerequisite_state.blocked_operation
```

### Ownership Classification

Use the same principles as `policies/development-runtime.md` — Runtime Ownership Model,
extended to cover mxbuild:

| Classification | Evidence | Action |
|---|---|---|
| `OWNED_BUILD` | PID recorded by current session; project path matches | Ongoing build — wait for completion |
| `STALE_OWNED_BUILD` | PID not from current session; project path matches; no active build output in past N seconds | Eligible for bounded cleanup |
| `FOREIGN_BUILD` | Belongs to a different project, session, or user | Do NOT terminate; classify and report |
| `UNKNOWN_BUILD` | mxbuild process exists; ownership cannot be determined | Do NOT terminate; classify and report |

Sufficient ownership evidence for `STALE_OWNED_BUILD` requires at least TWO of:
- Command-line arguments match expected project path
- Process start time predates the current MxAgile session
- No build output has been emitted by this PID in the past 60 seconds
- The deployment/web lock corresponds to this PID

### Safe Build Recovery Ladder

Apply in order. Stop at the first step that resolves the stall.

```
STEP 1: REPORT AND WAIT
    Record: stale mxbuild PID, project path, evidence basis
    Wait up to developer_wait_window (default: 30s) for organic resolution

STEP 2: TERMINATE STALE_OWNED_BUILD PROCESS
    Only when:
      - Classification = STALE_OWNED_BUILD (confirmed, not assumed)
      - Evidence basis meets two-signal minimum
      - This is an authorized autonomous runtime-recovery context
    Action: terminate only the specific stale mxbuild PID
    Record termination evidence in prerequisite_state.blocked_operation

STEP 3: VERIFY LOCK RELEASED
    Confirm deployment/web/ and other build artifacts are no longer locked
    If lock persists after process termination: wait up to 10s; then record as
    LOCK_ORPHANED and escalate to developer

STEP 4: RETRY STARTUP
    Proceed with the startup sequence from PREREQUISITE_DISCOVERY
    This is a materially different recovery path — not a blind retry

STEP 5: ESCALATE TO DEVELOPER (when owner is FOREIGN_BUILD or UNKNOWN_BUILD)
    FOREIGN_BUILD escalates to developer: report PID, project path, evidence, recommended action
    UNKNOWN_BUILD escalates to developer: report PID, ownership classification, recommended action
    Do NOT proceed autonomously when foreign build work may be affected
```

### Prohibited Actions

| Prohibited | Reason |
|---|---|
| `pkill mxbuild`, `killall mxbuild`, kill all Java processes | Terminates active builds in other sessions/projects |
| Delete deployment/web/ contents as a startup routine | Destroys build output that may be shared |
| Terminate process merely because it exists or appears idle | Idle ≠ orphaned |
| Terminate without two-signal ownership evidence | Ownership must be confirmed, not assumed |
| Cleanup scope beyond attributable current project/tooling session | Risk of disrupting unrelated builds; bounded to current project/tooling only |

---

## Recovery Path Catalog

Recovery paths are materially different if they address different root causes or use
structurally different approaches. A blind retry of the same command is NOT a recovery path.

| Recovery path | Root cause it addresses | Materially different from |
|---|---|---|
| Wait for lock release | Transient lock released by other process | Timeout-only retry |
| Terminate STALE_OWNED_BUILD + retry | mxbuild orphan holding file locks | Simple retry |
| `gradle --stop` + retry | Gradle daemon stall (see local-runtime-profile.md) | Simple retry |
| Alternate port | Port conflict with a non-mxagile process | Same-port retry |
| Alternative startup path (different flags) | Misconfigured or unsupported flag | Identical-command retry |
| DB connectivity recovery | Database not reachable | Build-stage recovery |
| Credential re-resolution | Credential expired or not loaded | Build-stage recovery |

### Recovery Bounds

- Each distinct recovery path may be attempted ONCE per startup attempt.
- Retrying the same path after it has already failed is only justified when a materially
  different diagnostic step was performed between the attempts and produced new evidence.
- Do NOT attempt more than 3 total startup attempts per recovery session without recording
  a `STARTUP_RECOVERY_EXHAUSTED` classification and halting.

---

## Human-Gate Semantics

The following are NOT human/external gates:

| Situation | Correct classification |
|---|---|
| Startup timed out | RUNTIME_STARTUP_FAILURE — gather evidence |
| Startup retry needed | Deterministic recovery — proceed |
| Log inspection required | Deterministic diagnostic step — proceed |
| Stale/orphan process detected from this project | Deterministic cleanup — proceed when authorized |
| Alternative startup path available | Deterministic recovery — proceed |
| APPLICATION_REACHABLE after recovery | Continue pending verification — do NOT treat as new mission |

The following ARE legitimate human/external gates:

| Situation | Reason |
|---|---|
| All safe deterministic recovery paths exhausted | Agent cannot make further progress without external action |
| Cleanup requires authority the agent does not have (e.g., FOREIGN_BUILD ownership) | Risk of disrupting another developer's work |
| DB provisioning or network configuration required | Infrastructure outside MxAgile's autonomous scope |
| mxcli version or environment prerequisite not met | Tool-layer gap — not a recoverable application state |
| Credentials genuinely missing after full discovery | Follow `policies/credential-discovery.md`; request only missing keys |

### Terminal-State Guard Integration

Before declaring `MISSION_BLOCKED` due to a runtime infrastructure gap, verify:

1. All evidence has been gathered (Evidence Inventory above)
2. All safe deterministic recovery paths have been tried
3. The remaining blockage genuinely requires human authority or external resources
4. Unrelated verification work (MODEL, BUILD, non-runtime proof points) has been completed or
   is also blocked by the same root cause

A runtime startup failure that blocks only FRONTEND/RUNTIME proof points MUST NOT block
non-runtime proof points. Continue what can be completed autonomously.
See `policies/mission-completion.md — Partial Blockers`.

---

## Failure Classification After Bounded Recovery

Apply these classifications only AFTER evidence has been gathered and recovery attempted:

| Classification | Condition | Action |
|---|---|---|
| `APPLICATION_DEFECT` | Application reachable, authenticated, test executed correct path → unexpected result | Route to Implementing |
| `TEST_DEFECT` | Canonical expectation outdated or test implementation broken | Follow `policies/test-defect-protection.md` |
| `TEST_INFRASTRUCTURE_GAP` | Test harness/tooling failure unrelated to application behavior | Record; do not attribute to application |
| `RUNTIME_STARTUP_FAILURE` | Application never reached APPLICATION_REACHABLE after bounded recovery exhausted | Record; continue non-runtime work |
| `STARTUP_RECOVERY_EXHAUSTED` | All safe recovery paths tried; application still unreachable | Escalate to human gate with full diagnostic |
| `STALE_PROCESS_RECOVERED` | Orphan/stale process detected, terminated, and startup succeeded | Record; continue verification |

**Prohibited classifications from observation alone:**
- `MACHINE_LOAD_FAILURE` — requires CPU/memory evidence
- `INFRASTRUCTURE_FAILURE` — requires network/service/environment evidence
- `ENVIRONMENT_PERFORMANCE_ISSUE` — requires performance measurement evidence

These classifications require supporting signals. Timeout alone does not establish them.

**Additional prohibitions:**

Do not mutate application behavior merely to force a runtime startup.
Do not mutate credentials speculatively in response to a startup failure.
Do not classify a startup timeout as an APPLICATION_DEFECT.
Do not classify a TEST_INFRASTRUCTURE_GAP as terminal while deterministic recovery remains.

---

## Lessons-Learned Classification

When a runtime incident produces a reusable insight, classify before recording:

| Class | Definition | Recording rules |
|---|---|---|
| `PROJECT_SPECIFIC` | Knowledge applies only to this project's configuration, environment, or tooling setup | Record in project `.concord/` or `planning/`; NEVER in MxAgile Core |
| `GENERIC_MXAGILE_CANDIDATE` | Pattern generalizes across projects and tooling versions; confirmed by direct evidence | Candidate for MxAgile Core policy update; requires generalization review |
| `MXCLI_TOOLING_BEHAVIOR` | Observation about mxcli behavior that projects cannot control | Document as upstream finding for mxcli; do NOT silently become a project business rule |

### Recording Rules

1. Only proven facts may be recorded as lessons. A successful recovery path or direct diagnostic
   evidence is required before any lesson is written.
2. A lesson hypothesis during a session is NOT a lesson until confirmed by evidence.
3. Project-specific runtime knowledge MUST NOT be written into Core policy.
4. A `GENERIC_MXAGILE_CANDIDATE` becomes Core only after an explicit generalization step:
   - The pattern must be confirmed in at least the current context
   - The lesson must be expressed without project-specific identifiers, PIDs, paths, or timings
   - The lesson must be reviewed as part of a framework change (see CLAUDE.md)
5. `MXCLI_TOOLING_BEHAVIOR` lessons are recorded as upstream findings in the style of the
   Gradle lock finding in `policies/local-runtime-profile.md — Upstream Finding for mxcli`.

### Example Classifications

| Observation | Class | Reason |
|---|---|---|
| "Orphan mxbuild retaining deployment/web lock blocks next startup silently" | `GENERIC_MXAGILE_CANDIDATE` | Pattern applies to any mxbuild-based project; not project-specific |
| "After cleaning stale runtime, CapTrack started in 47s" | `PROJECT_SPECIFIC` | Timing is project/machine-specific |
| "mxcli does not expose stale mxbuild PID in any structured output" | `MXCLI_TOOLING_BEHAVIOR` | Tooling gap; upstream finding for mxcli |

---

## Agent Orientation

Agents performing runtime or browser work under this policy:

- implementation-agent (startup during Implementing warm loop)
- acceptance-agent (startup for Verifying evidence)
- ui-agent (startup for browser-level evidence)

Rules for all three:

1. **Diagnose before blocking.** Gather evidence before classifying a startup failure.
2. **Evidence before root-cause claim.** A timeout is not a diagnosis.
3. **Bounded recovery before human escalation.** Try all safe deterministic paths.
4. **APPLICATION_REACHABLE resumes the verification mission.** It does not start a new mission.
5. **Successful recovery does not invalidate prior evidence.** Continue the interrupted campaign.
6. **Partial blockers do not terminate the whole mission.** Complete what is unblocked.
