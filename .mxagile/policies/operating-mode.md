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

`Get-MxAgileCapabilities.ps1 -ResolveOperatingMode -Format json` is the C2 resolver and sole
owner of current detection, effective mode, and `operating_mode.tool_authority`. Reuse that
structured result for the session and perform its existing recheck at the first model-mutation
boundary; do not call the detector separately or reconstruct routes from prose.

C2 does not probe MCP tools, attest mxcli availability, or resolve runtime argv. Only pass
`HEALTHY` plus an exact bound project path after a successful current-session read-only probe.
An MCP route is usable only with an exact binding to the current project.
Configuration and namespace presence are not health or project-identity evidence. If a probe
conflicts with the current `.mpr`, C2 returns `AMBIGUOUS-SP-STATE`; an unavailable LIVE-SP route
is `BLOCKED`, never an mxcli fallback. In `LIVE-SP-CURRENT`, no mxcli model mutation is allowed.

For `CLOSED-AUTONOM` / `LIVE-SP-OTHER`, C2 marks mxcli permitted, not available. Resolve its
binary and runtime recipe separately through `local-runtime-profile.md`. Resolve instruction
conflicts through `tool-instruction-conflict.md`.

---

## Branch Integration Route

Mode detection does not change for model integration. The Mendix-aware merge route is Studio Pro (`LIVE-SP-*`, `Merge Changes Here`,
Concord for conflict analysis/resolution). `CLOSED-AUTONOM` may use another route only after it is validated as equivalent and safe.
The decision (`preflight`) and the completion gate (`postcheck`) are defined in `policies/mendix-integration.md`; they add no new
mutation authority.

## C2 Detection Contract

Project root and `.mpr` identity, headless behavior, detector timeout, exit-state mapping,
cross-signal conflicts, and route status are resolved by C2. Consume its structured result and
preserve `UNKNOWN` / `AMBIGUOUS-SP-STATE`; do not recreate or locally repair its state machine.

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

A conclusive C2 result is the mode decision, not a recommendation. Never present a follow-up
choice such as `CLOSED-AUTONOM / LIVE-SP / Other`, and never ask the user to confirm a detected
`CLOSED-AUTONOM` or `LIVE-SP-OTHER` result. Consume `tool_authority.user_interaction`: a concrete
mode has `mode_choice_required: false` and `question_policy: NONE`. Explicit user instructions
that conflict with detected facts are handled by the existing execution-intent/source-authority
rules; they do not justify a generic mode menu.

Asking is ONLY permitted when ALL of the following are true:
1. Detection has been attempted (Step 3 above was executed).
2. The result is AMBIGUOUS-SP-STATE.
3. The ambiguity blocks the NEXT ACTUAL MENDIX MODEL MUTATION (not startup).
4. A recheck at the mutation boundary did not resolve the ambiguity.
The structured route uses `question_policy: MUTATION_BOUNDARY_AFTER_RECHECK` for ambiguous/unresolved
modes; it does not authorize a startup question by itself.

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
