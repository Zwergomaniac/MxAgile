# Policy: Execution-Environment Intent

**MxAgile 1.5** — Focused fix on top of 1.5 Capability Discovery.

Defines the required behavior when the agent detects that Mendix Studio Pro
is open AND Concord MCP capabilities are available. This combination is a
strong signal that live/Studio-Pro execution MAY be appropriate, but it does
not by itself authorize that choice.

---

## Core Invariant

    ENVIRONMENT CAPABILITY ≠ USER INTENT

Studio Pro detected AND Concord MCP detected does NOT authorize the agent
to choose live execution automatically.

It only raises the confidence that live execution is feasible.

The agent MUST ask exactly once when the strong signal is present and the
user has not already expressed an execution preference.

---

## Concepts

This policy maintains strict separation between three concepts:

### A. Environment Detection

What can actually be observed right now?

| Signal | Possible States |
|--------|----------------|
| Studio Pro (for current project) | `detected` — LIVE-SP-CURRENT confirmed by `check-studio-pro-status.ps1` |
| | `not_detected` — CLOSED-AUTONOM or LIVE-SP-OTHER |
| | `unknown` — AMBIGUOUS-SP-STATE |
| Concord MCP | `detected` — `mcp__concord-v2-mcp__*` tools present in agent tool namespace |
| | `not_detected` — no such tools available to the agent |
| | `unknown` — tool namespace inaccessible or introspection unavailable |

`unknown` MUST NOT silently become `detected`.

`unknown` alone does NOT trigger the strong-signal prompt unless a separate
reliable mechanism in the environment confirms the required capability.

### B. Execution Intent

What does the user want?

| Value | Meaning |
|-------|---------|
| `unresolved` | No explicit preference stated and no prior valid session decision |
| `studio_pro_live` | User has selected Studio Pro / live mode |
| `normal_headless` | User has selected normal / headless mode |
| `other` | User has stated an explicitly different alternative |

Execution intent is a separate dimension from environment detection.
AVAILABLE capability does not imply CHOSEN intent.

### C. Framework / Agent Identity

**Out of scope for this policy.**

This policy does NOT decide whether Concord is an MxAgile agent,
what lifecycle authority it holds, or how it should relate to MxAgile
orchestration. Those are explicitly deferred architectural decisions.

This fix must remain compatible with either future outcome:

A. Concord may understand selected MxAgile concepts.
B. Concord may be intentionally isolated from MxAgile control knowledge.

---

## Signal Model

### Weak Signal

Conditions: Studio Pro detected (LIVE-SP-CURRENT) AND Concord MCP NOT
detected or UNKNOWN.

Required behavior: Do NOT interrupt normal work to ask about execution mode.
Continue with the standard LIVE-SP-CURRENT coexistence contract
(`policies/consistency-check.md`).

### Strong Signal

Conditions (all required):

- Studio Pro detected (operating_mode: LIVE-SP-CURRENT); AND
- Concord MCP detected (`mcp__concord-v2-mcp__*` tools available in the
  agent tool namespace)

Required behavior: If execution intent is unresolved → ask exactly once
(see User Question section below).

### Explicit User Intent

The user has stated an execution preference in the current request, in a
prior message that is still applicable to this session, or in the persisted
session state with `source: explicit_user`.

Required behavior: Do NOT ask. Honor the stated preference immediately.

If the stated mode becomes technically unavailable, report the discrepancy
rather than silently switching modes.

---

## Detection Mechanism

### Studio Pro Detection

Reuse the operating-mode detection result from Startup Re-Sync Step 1
(`policies/operating-mode.md`). Do NOT run a second Studio Pro detector.

| operating_mode | Studio Pro state (for intent) |
|----------------|-------------------------------|
| LIVE-SP-CURRENT | `detected` |
| CLOSED-AUTONOM | `not_detected` |
| LIVE-SP-OTHER | `not_detected` (for current project) |
| AMBIGUOUS-SP-STATE | `unknown` |

### Concord MCP Detection

**Primary signal — agent tool namespace:**

`concord_mcp.state = detected` if and only if at least one tool prefixed
`mcp__concord-v2-mcp__` appears in the agent's available tool set.

`concord_mcp.state = not_detected` if no such tool is present.

`concord_mcp.state = unknown` if the tool namespace is inaccessible or
the runtime context does not support tool namespace introspection.

**Secondary (configuration evidence — does NOT imply `detected`):**

- `.vscode/mcp.json` contains a `concord-v2-mcp` server entry → Concord MCP
  is CONFIGURED but not necessarily ACTIVE.
- `scripts/start-concord-mcp.ps1` exists → Concord MCP is INSTALLABLE but
  not necessarily RUNNING.

Configuration evidence alone MUST NOT produce `concord_mcp.state = detected`.
Only active tool availability in the agent tool namespace is sufficient.

**Detection limitation:** When running outside Claude Code IDE extension, or
in an environment that does not expose MCP tool namespaces, Concord MCP state
is `unknown`. UNKNOWN alone does not trigger the strong-signal prompt.

### Capability Registry

The capabilities `concord_mcp` and `studio_pro_mcp` are registered in
`.mxagile/capabilities.yaml`. The registry uses the standard state model
(SUPPORTED / AVAILABLE / ENABLED / ACTIVE). Do not confuse registry states
with the intent concepts in this policy:

- Registry AVAILABLE = the capability can be used
- Execution intent `studio_pro_live` = the user CHOSE to use it

---

## User Question

When the strong signal is present AND execution intent is unresolved, ask
exactly one concise question:

> Studio Pro und Concord MCP wurden erkannt. Soll ich diese Session im
> Studio-Pro-/Live-Modus durchführen oder normal/headless weiterarbeiten?
>
> 1. Studio Pro / Live
> 2. Normal / Headless

Do NOT frame this question as a lifecycle gate or mission-completion
condition. It is execution-intent resolution only.

This question MUST NOT:
- satisfy any lifecycle gate
- change mission phase or completion status
- promote UNVERIFIED / FAILED / STALE evidence states
- reset the current Context Epoch
- trigger a Context Epoch rollover

After the user answers, persist the decision (see Session Decision State)
and continue the original mission from the smallest safe resumption point.

---

## Suppression Conditions

DO NOT ask the execution-mode question when ANY of the following is true:

1. Execution intent is already resolved (`execution_intent.status: resolved`)
   AND environment signals have not materially changed since resolution.

2. The current request or active session contains an explicit user execution
   preference (e.g., "headless", "mach das direkt in Studio Pro", "use
   Concord", "normal mode"). Recognize semantic equivalents, not only the
   literal phrases.

3. The signal is only weak (Studio Pro detected but Concord MCP not detected
   or unknown).

4. Neither Studio Pro nor Concord MCP is detected.

5. The operating mode is not LIVE-SP-CURRENT (e.g., headless platform,
   CLOSED-AUTONOM, LIVE-SP-OTHER).

6. The question has already been answered in the current relevant session
   without a material change in environment reality since the answer.

7. The task does not involve choosing an execution path (e.g., documentation
   review, planning, or analysis that does not require model mutations).

8. The current platform is Linux / macOS / headless / CI (Studio Pro cannot
   exist on these platforms).

---

## Session Decision State

Persist the execution environment detection result and the resolved intent
in `.concord/scratch/process-state.yaml` alongside the existing
`operating_mode` fields. This is session-scoped state — NOT durable project
truth across sessions.

Schema extension:

```yaml
execution_environment:
  studio_pro:
    state: detected | not_detected | unknown
    detected_at: "<ISO timestamp>"
    detection_source: check-studio-pro-status | platform_headless
  concord_mcp:
    state: detected | not_detected | unknown
    detected_at: "<ISO timestamp>"
    detection_source: mcp_tool_probe

execution_intent:
  status: unresolved | resolved
  mode: studio_pro_live | normal_headless | other | null
  source: explicit_user | user_confirmation | environment_change | null
  environment_basis:
    studio_pro: detected | not_detected | unknown
    concord_mcp: detected | not_detected | unknown
  resolved_at: "<ISO timestamp or null>"
```

On each fresh session: re-detect environment, then re-evaluate intent
resolution per Startup Re-Sync Step 1b (`orchestrator.md`).

Do NOT trust prior session environment detection without re-running it.

---

## Re-Sync Behavior

On Startup Re-Sync or applicable lifecycle Re-Sync:

### Case A: Environment unchanged, intent already resolved

Conditions:
- `execution_intent.status: resolved` in session state; AND
- Current environment signals match `environment_basis` (same studio_pro
  and concord_mcp states as when the decision was made).

Result: Do NOT ask again. Use the resolved intent as-is.

### Case B: Studio Pro or Concord MCP capability disappeared

Conditions:
- `execution_intent.mode: studio_pro_live`; AND
- Current Studio Pro detection is `not_detected` or `unknown`, OR
  current Concord MCP detection is `not_detected` or `unknown`.

Result: Do NOT silently continue as if live execution is still available.

Surface the changed environment:

> Zuvor war die Studio-Pro-/Live-Ausführung ausgewählt. Studio Pro oder
> Concord MCP ist nicht mehr verfügbar. Die Session wird im Normal/Headless-
> Modus fortgesetzt bis die Live-Umgebung wiederhergestellt ist.

Set `execution_intent.source: environment_change` and resolve to
`normal_headless`.

### Case C: Normal/headless previously chosen, strong signal still present

Conditions:
- `execution_intent.mode: normal_headless`; AND
- Current environment still shows the strong signal.

Result: Do NOT repeatedly ask merely because the strong signal remains.
The user's prior choice is still valid. Honor `normal_headless`.

---

## Relationship to Operating Mode (SP-on)

The intended conceptual flow is:

```
environment detection (check-studio-pro-status.ps1)
    ↓
operating_mode determined (LIVE-SP-CURRENT / CLOSED-AUTONOM / etc.)
    ↓
strong signal? (LIVE-SP-CURRENT AND concord_mcp detected)
    ↓
intent unresolved?
    ↓
ask exactly once
    ↓
user selects Studio Pro/live
    ↓
existing LIVE-SP-CURRENT coexistence behavior (policies/consistency-check.md)
```

NOT:
```
Studio Pro detected → automatically studio_pro_live
Concord MCP detected → automatically studio_pro_live
```

LIVE-SP-CURRENT is an environment fact (operating mode).
`studio_pro_live` is a user decision (execution intent).

These are separate concepts. LIVE-SP-CURRENT does NOT imply `studio_pro_live`
intent without user confirmation when Concord MCP is simultaneously available.

The existing SP-on / LIVE-SP-CURRENT coexistence semantics (`policies/
consistency-check.md`, `policies/commit-authority.md`) remain fully intact.
This policy adds the intent-resolution layer on top; it does not replace or
modify operating-mode detection behavior.

---

## User Override Priority

Explicit user instruction has higher priority than any environment signal
or recommendation. Examples:

- Studio Pro + Concord MCP detected + user says "headless" → `normal_headless`
  without question.
- Studio Pro + Concord MCP detected + user says "mach das direkt in Studio Pro"
  → `studio_pro_live` without question.
- User says "nicht über Studio Pro" → `normal_headless`; do not suggest
  live mode.

When the user's preferred mode becomes technically unavailable, report that
fact rather than silently switching if the change would materially affect
execution.

---

## Interrupt / Resume Compatibility

Execution-mode clarification MUST NOT:
- satisfy an unrelated lifecycle gate
- change mission phase or completion status
- promote UNVERIFIED / FAILED / STALE evidence states
- reset the current Context Epoch
- trigger a Context Epoch rollover

After clarification, continue the original mission from the smallest safe
resumption point.

---

## Detection Limitations

| Aspect | Limitation |
|--------|-----------|
| Concord MCP active-tool probe | Reliable only inside Claude Code IDE extension with `concord-v2-mcp` MCP server configured and running. Not reliable outside Claude Code or in headless agent contexts. |
| Studio Pro MCP endpoint | Not separately probed by this policy. Studio Pro availability is determined by process-level `check-studio-pro-status.ps1` only. |
| Concorde/MxAgile identity | Whether Concord is or should be an MxAgile lifecycle agent is an explicitly deferred architectural decision. This policy does not resolve it. |

---

## Integration Points

| Consumer | Where this policy applies |
|----------|--------------------------|
| `orchestrator.md § Startup Re-Sync` | Step 1b — evaluate execution intent after operating mode |
| `policies/operating-mode.md` | Step 1 provides the studio_pro detection result reused here |
| `.concord/scratch/process-state.yaml` | Session state extended with execution_environment + execution_intent |
| `.mxagile/capabilities.yaml` | `concord_mcp`, `studio_pro_mcp` capabilities registered |
