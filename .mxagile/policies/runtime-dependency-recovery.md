# Runtime Dependency-Sync Recovery

Failure-only contract for diagnosing and recovering Gradle dependency-sync stalls during an
authorized C1 local-runtime start. Consume the resolved runtime recipe and record state in the
existing `prerequisite_state.dependency_sync_state`; this policy introduces no second runtime
state machine.

Related contracts:
- `policies/local-runtime-profile.md` — C1 recipe, selected binary, runtime identity, and stage model
- `policies/runtime-startup-recovery.md` — general startup diagnosis, process ownership, and recovery bounds
- `schemas/process-state.schema.json` — durable dependency-sync sub-state

## State and Progress

| State | Meaning | Trigger |
|---|---|---|
| `not_started` | Dependency sync not yet reached | Before mxcli starts dependency sync |
| `active` | Forward progress observed | Gradle output or files advance within the progress window |
| `long_running` | Slow but still progressing | Age exceeds the normal threshold while progress remains visible |
| `stalled` | No observable forward progress | Stall threshold elapsed without progress signals |
| `lock_contended` | Stall with a detected lock and owner evidence | Lock-owner classification completed |
| `unknown` | State cannot be determined | No reliable mxcli or host signal is available |

`long_running` MUST NOT be classified as `stalled` merely because a fixed duration elapsed.
A `stalled` state requires absence of forward progress signals, not merely elapsed time.

### Forward progress signals

- Gradle output lines advancing
- Files under `~/.gradle/caches/` being modified
- mxcli logs showing download or resolution activity
- Recent Gradle daemon log entries

Use a two-tier threshold: `normal_threshold` defaults to 120 seconds before progress checks;
`stall_threshold` defaults to 60 seconds of silence after that point. Project startup timeout
configuration may bound the overall startup but does not by itself prove a stall.

## Lock-Owner Classification

When state is `stalled`, inspect the lock at `~/.gradle/caches/modules-2/modules-2.lock`.
If absent, classify as `unknown_stall`, not lock contention. If present, identify its owner only
with supported OS locking information; do not guess with `wmic` or infer ownership from idleness.

| Owner | Evidence | Action |
|---|---|---|
| `NO_OWNER` | No live process holds the lock | Stale lock candidate; remove only after confirming no writes are active |
| `ACTIVE_BUILD` | Owner is building or output is progressing | Do NOT terminate; wait or escalate |
| `STALE_LEFTOVER` | Prior lifecycle owner, no active build work | Eligible for safe recovery after owner confirmation |
| `UNIDENTIFIED` | Owner cannot be attributed | Do NOT terminate; report and escalate |
| `OWN_LIFECYCLE` | Process belongs to the current mxcli run | Monitor for progress; do not classify as a stall |

## Safe Recovery Ladder

Apply in order and stop at the first resolving step:

1. **Report and wait.** Record the state, lock file path, owner classification, and PID when known.
   Wait up to the configured developer wait window (default 30 seconds).
2. **Recommend `gradle --stop`** only for confirmed `STALE_LEFTOVER`; await developer
   confirmation unless the active autonomous recovery contract explicitly authorizes it.
3. **Execute `gradle --stop`** only with that permission and confirmed stale ownership; verify
   lock release before restarting mxcli.
4. **Escalate** for `ACTIVE_BUILD` or `UNIDENTIFIED`; do not proceed autonomously while live
   build work may be interrupted.
5. **Hard termination** is last resort and requires all conditions below.

Hard termination requires positive evidence that state is `lock_contended`, owner is confirmed
`STALE_LEFTOVER`, `gradle --stop` failed or is unavailable, no recent active build output exists,
the owning mxcli lifecycle ended, and no user/CI build session is active. Terminate only the
specific stale owner PID. Hard termination must be recorded in `blocked_operation` with evidence.

## Prohibited Recovery

MxAgile MUST NOT automatically kill arbitrary Java/Gradle processes. Never:

- Delete lock files as a startup routine or before confirming no writes in progress
- Kill all Java processes or kill all Gradle daemons without owner check
- Kill a process merely because it exists or appears idle
- Delete Gradle caches or cache subsets
- Restart mxcli while the previous run still owns the lock

A reduced Gradle daemon idle timeout is optional mitigation, not resolution. Do not blindly
override project `gradle.properties` or assume the setting prevents lock contention.

## Repeated-Run Contract

Before a second local start after a stopped or interrupted run:

1. Check whether a process from the first run remains active.
2. Check whether its lock is still held.
3. If there are no active processes and no held locks, proceed normally.
4. If locks are held, apply the owner classification and Safe Recovery Ladder; do not spawn
   competing dependency-sync or build pipelines.

### Concurrent run prevention

Do not silently start a competing runtime/build pipeline while the first run still owns resources.

The dependency-sync sub-state is subordinate to `runtime_pipeline_stage = DEPENDENCY_SYNC`; it
does not replace that pipeline stage. Record `completed` after sync succeeds.

## mxcli Upstream Finding

Observed failure: an idle Gradle daemon retaining `modules-2.lock` can leave a later sync waiting
without an error or structured progress/stall signal. Expected mxcli improvements:

- Expose the PID of each Gradle daemon started by mxcli
- Emit a structured `dependency_sync_stalled` event with cause, lock path, and owner PID
- Distinguish sync progress from a stall and provide a bounded sync timeout with a clear exit
- Scope any daemon cleanup to mxcli-owned daemons

Until those signals exist, MxAgile's host inspection remains evidence-limited and must preserve
`UNKNOWN`/`unknown` when ownership or progress is not observable.