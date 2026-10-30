# Policy: Operating-Mode Detection

Defines how MxAgile agents MUST determine the operating mode at session start and before
model mutations. Replaces ad-hoc user questions with deterministic process detection.

---

## Why This Policy Exists

An autonomous assignment must not stop at startup to ask "Is Studio Pro open?" or
"Which mode should I use?". The required information can be obtained deterministically
from the current machine state. Asking before attempting detection is a framework defect.

---

## Operating Modes

### CLOSED-AUTONOM

Conditions (any one sufficient):
- No `studiopro.exe` process is running on this machine.
- Studio Pro is running but reliably associated with a DIFFERENT `.mpr` file.
- `check-studio-pro-status.ps1` returns `isOpen = false` AND `anyStudioProRunning = false`.
- Running on Linux/headless/CI where Studio Pro cannot exist.

Behavior:
- Continue all lifecycle-authorized deterministic work autonomously.
- Do NOT ask the user to confirm the absence of Studio Pro.
- Record basis: `operating_mode: CLOSED-AUTONOM`, `detection_source`, `detected_at`.

### LIVE-SP-CURRENT

Conditions (all required):
- `check-studio-pro-status.ps1` returns `isOpen = true` for the current `.mpr`.
- PID and the normalized absolute `.mpr` path are confirmed. Path matching is
  case-insensitive on Windows and must match a complete command-line argument,
  not a project-name or path substring.

Behavior:
- Apply safe coexistence contract (see `policies/consistency-check.md`).
- Do NOT silently perform external model writes that can conflict with Studio Pro.
- Continue safe read-only / planning / SCSS / test / documentation work.
- Coordinate or delay only the specific mutation that could conflict.
- Do NOT stop the entire assignment.

### LIVE-SP-OTHER

Conditions:
- `check-studio-pro-status.ps1` returns `isOpen = false` AND `anyStudioProRunning = true`.
- At least one `studiopro.exe` PID exists but none is associated with the current project.

Behavior:
- Treat the current project as CLOSED-AUTONOM.
- Do NOT touch, inspect, kill or manage the foreign Studio Pro process.
- Record: `operating_mode: LIVE-SP-OTHER`, foreign PIDs in `other_studio_pro_pids`.

### AMBIGUOUS-SP-STATE

Conditions (any one triggers):
- `check-studio-pro-status.ps1` exits with code 2 (detector error).
- Permission denied reading process list (OS restriction) — AMBIGUOUS-SP-STATE, not falsely closed.
- `anyStudioProRunning` is `$null` (detection unavailable).
- Conflicting signals from multiple evidence sources.
- A successful Studio-Pro-MCP identity probe reports a different project from
  the `.mpr` confirmed by the process detector.
- Process exists but project path in command line cannot be read.

Behavior:
- Continue all safe reads, planning, analysis, artifact preparation, SCSS, tests and
  other non-Mendix-model work.
- Delay ONLY the first Mendix model mutation that could conflict with Studio Pro.
- Retry detection before the mutation boundary.
- If ambiguity remains at the mutation boundary, ask ONE precise question that reports
  what was detected (see User Question Policy below).
- Do NOT block the entire assignment at startup.

---

## Tool Routing After Mode Detection

`operating_mode` is determined by the process/project detector above. MCP health
and project context determine whether an MCP route is usable; they do not create
another operating-mode state machine.

If Studio-Pro-MCP exposes project identity and a successful read-only probe
conflicts with the detector's current `.mpr` path, use the existing
`AMBIGUOUS-SP-STATE` for that conflict. Never call it `LIVE-SP-CURRENT` for the
current project until a recheck resolves the disagreement.

Before choosing a tool for any Mendix model operation, use the current mode and
the following routing contract:

Resolve conflicting project/Core/Company/harness/external tool instructions per
`policies/tool-instruction-conflict.md`. A tool listed by a skill or configured in a file is
not proof that its current-session capability is loaded or usable.

| Mode | Model mutation route | mxcli |
|---|---|---|
| `LIVE-SP-CURRENT` | Studio-Pro-MCP first. Concord MCP is the existing fallback only when a successful read-only probe confirms it is healthy and bound to this project. | Never use mxcli for model mutations, including `mxcli exec`. Do not fall back to mxcli after an MCP failure. Read-only mxcli operations remain subject to their own operation contract. |
| `CLOSED-AUTONOM` | Autonomous route | Use mxcli when available and authorized. |
| `LIVE-SP-OTHER` | Autonomous route for the current project; do not touch the foreign Studio Pro process. | Use mxcli when available and authorized for the current project. |
| `AMBIGUOUS-SP-STATE` | Safe non-model work only until the required recheck resolves the mode. | No model mutation through mxcli while mode is ambiguous. |

Tool namespace presence means a tool is offered by the harness. It does NOT by
itself prove health, successful operation, or correct project context. Count an
MCP route as usable only after a successful non-mutating call and evidence that
the endpoint is bound to the current project. Configuration files and installed
tools are not runtime evidence. If no available MCP operation can establish that
evidence, do not claim the route is healthy. In `LIVE-SP-CURRENT`, block the
specific mutation rather than trying mxcli.

Mode detection must happen before mxcli/Studio-Pro-MCP/Concord-MCP selection.
Re-use the Startup Re-Sync result and its existing mutation-boundary recheck; do
not run a second Studio Pro detector or ask the user when the evidence is
conclusive.

---

## Detection Algorithm

Execute in this exact order. Stop at the first conclusive result.

### Step 1 — Establish project root and .mpr path

```
lifecycle-resync.md § Projektroot-Bestimmung
    → locate *.mpr in project root
    → $currentMpr = resolved absolute path
```

If no `.mpr` file exists: environment is NOT a Mendix project workspace.
Studio Pro detection does not apply. Proceed as CLOSED-AUTONOM.

### Step 2 — Platform check (headless / Linux / CI)

Check: `$IsLinux -or $IsMacOS -or (Test-Path '/proc')`

If TRUE: Studio Pro cannot run. Classify as CLOSED-AUTONOM immediately.
Record `detection_source: platform_headless`.

### Step 3 — Run the canonical detector

```powershell
& ./.mxagile/tools/check-studio-pro-status.ps1 -ProjectPath $currentMpr -Json -TimeoutSeconds 10
```

The detector runs with a bounded timeout. A slow or frozen WMI/CIM subsystem MUST NOT
hang the agent indefinitely. Default timeout: 10 seconds.

Parse JSON output. Interpret exit codes:

| Exit | JSON result | Mode |
|---|---|---|
| 0 | isOpen=true | LIVE-SP-CURRENT |
| 1 | isOpen=false, anyStudioProRunning=false | CLOSED-AUTONOM |
| 1 | isOpen=false, anyStudioProRunning=true | LIVE-SP-OTHER |
| 2 | error contains "TIMEOUT" | AMBIGUOUS-SP-STATE (UNKNOWN) |
| 2 | error / anyStudioProRunning=null | AMBIGUOUS-SP-STATE |

For exit 1:
- `anyStudioProRunning = false` → CLOSED-AUTONOM
- `anyStudioProRunning = true` → LIVE-SP-OTHER
- `anyStudioProRunning = $null` → AMBIGUOUS-SP-STATE

**CRITICAL — Timeout MUST NOT become CLOSED-AUTONOM:**

A detection timeout means the result is UNKNOWN (AMBIGUOUS-SP-STATE).
Repository/runtime evidence cannot prove CLOSED-AUTONOM from a timeout alone.

```
detector timed out
    ↓
detection_state = UNKNOWN
    ↓
operating_mode  = AMBIGUOUS-SP-STATE
    ↓
NOT CLOSED-AUTONOM
```

Rationale: The detector failing to complete does NOT prove Studio Pro is absent.
It only proves the detection did not succeed within the time bound.
Setting CLOSED-AUTONOM based on a timeout is a false-safety assumption.

### Step 4 — Inspect project lock (supplementary)

If the project directory contains a Mendix lock file (`.mpr.lock`, `.lock`, or similar),
treat it as corroborating **project-affinity evidence** for LIVE-SP-CURRENT.

**IMPORTANT:** MPR lock evidence MUST NOT:
- Directly imply user execution intent (`studio_pro_live`)
- Override a TIMEOUT result (a lock + timeout → still AMBIGUOUS-SP-STATE, not LIVE-SP-CURRENT)
- Be treated as conclusive without corroborating Step 3 evidence

Combine with Step 3 result only. MPR busy/locked → project-affinity evidence only.

### Step 5 — Classify

Apply the mode definitions above. Record:
- `operating_mode`
- `studio_pro_pid` (if relevant)
- `studio_pro_project_path` (if detected)
- `other_studio_pro_pids` (if LIVE-SP-OTHER)
- `detection_source` (script_exit_0 / script_exit_1_no_sp / script_exit_1_other_sp / platform_headless / script_failed / script_timeout)
- `detection_confidence` (high / medium / ambiguous / unknown)
- `detected_at` (ISO timestamp)

---

## Default Autonomy Rule

When detection produces CLOSED-AUTONOM or LIVE-SP-OTHER:

**The agent MUST continue autonomous work. It MUST NOT ask the user to confirm.**

Absence of a relevant Studio Pro process is an evidence-based conclusion, not an
optimistic assumption. It is derived from current observable machine state.

Do not treat "I cannot confirm Studio Pro is closed" as equivalent to
"Studio Pro might be open". Those are different epistemic states.

However:
- process detection failure is NOT equivalent to "Studio Pro definitely closed";
- permission errors or unavailable OS tooling MUST produce AMBIGUOUS-SP-STATE;
- do not fabricate certainty from absence of evidence.

---

## Mutation Recheck

Operating mode can change after session start (user opens Studio Pro mid-session).

RECHECK is required:
1. At lifecycle/session re-sync (Startup Re-Sync per `orchestrator.md`).
2. Immediately before the first Mendix model mutation through the mode-allowed route
  (Studio-Pro-MCP, Concord MCP, or mxcli as permitted above).
3. After a PAUSE/resume where process state may have changed.
4. When process evidence changes (e.g. lock file appears).

RECHECK is NOT required before every file read, YAML write, SCSS edit, or git operation.

Recheck cost is one script invocation. Do not skip it at the mutation boundary.

---

## User Question Policy

The agent MUST attempt deterministic detection BEFORE asking the user about Studio Pro.

Asking is ONLY permitted when ALL of the following are true:
1. Detection has been attempted (Step 3 above was executed).
2. The result is AMBIGUOUS-SP-STATE.
3. The ambiguity blocks the NEXT ACTUAL MENDIX MODEL MUTATION (not startup).
4. A recheck at the mutation boundary did not resolve the ambiguity.

When asking is permitted, the question MUST report what was detected:

> Studio Pro PID {pid} is running, but I cannot confirm whether it has
> `{currentMpr}` open (command line not readable). I can continue planning,
> SCSS, tests, and repository work. Before the first Mendix model mutation,
> please confirm whether Studio Pro has the current project open.

NEVER ask a generic context-free question such as:
- "Is Studio Pro open?"
- "Should I use CLOSED-AUTONOM?"
- "Are you currently editing the project?"

---

## Cross-Platform Behavior

### Windows (local developer workstation)

Studio Pro may be running. Full detection applies. Use `.mxagile/tools/check-studio-pro-status.ps1`.

`Get-CimInstance Win32_Process` is the correct mechanism (not `wmic`).
`Get-Process studiopro` is acceptable as a lightweight fallback but does not expose
the command line, so project correlation requires `Win32_Process`.

### Linux / macOS / headless / CI

Studio Pro cannot run on these platforms.

Classify as CLOSED-AUTONOM immediately in Step 2.
Do NOT call `check-studio-pro-status.ps1` (it will fail without Win32).
Do NOT ask whether Studio Pro is open.

Record `detection_source: platform_headless`.

---

## Process Safety

Detection NEVER implies permission to terminate a process.

MxAgile MUST NOT kill:
- Studio Pro (any PID)
- PID 4 / System
- Foreign Studio Pro processes
- Unknown processes
- Processes belonging to another project

This policy concerns DETECTION and ROUTING only.

Process termination is an entirely separate decision requiring explicit user authorization.

---

## State Persistence and Resume

Operating mode is session-scoped machine state. It is NOT durable project truth.

DO record in `.concord/scratch/process-state.yaml` (session cache, non-authoritative):
```yaml
operating_mode: CLOSED-AUTONOM
studio_pro_pid: null
detection_source: script_exit_1_no_sp
detection_confidence: high
detected_at: "2026-10-08T09:00:00Z"
```

DO NOT persist PIDs as authoritative across sessions.

On fresh session / resume:
1. Re-run detection (Steps 1–5 above).
2. Discard any prior session's operating mode without rechecking.
3. Continue from the valid lifecycle point once mode is established.

---

## Integration Points

| Consumer | Where operating-mode applies |
|---|---|
| `orchestrator.md` § Startup Re-Sync | First operating-mode check after project root is established |
| `orchestrator.md` § Implementing | Recheck before the first model mutation through the selected route |
| `policies/implementation-control.md` | Tool availability by mode |
| `policies/consistency-check.md` | CE0066: already calls detector before opening SP |
| `scripts/check-studio-pro-status.ps1` | Canonical detector source |
| `.mxagile/tools/check-studio-pro-status.ps1` | Installed copy, refreshed by every Core install/update |
