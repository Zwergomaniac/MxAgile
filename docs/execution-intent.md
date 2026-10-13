# Execution-Environment Intent

**MxAgile 1.5** — Focused fix on top of 1.5 Capability Discovery.

---

## Overview

When an agent session starts in a Mendix project, the combination of:

1. Mendix Studio Pro open for the current project (LIVE-SP-CURRENT); AND
2. Concord MCP capabilities available (`mcp__concord-v2-mcp__*` tools in
   the agent tool namespace)

...is a **strong signal** that the user may want work performed through
Studio Pro / Concord / live-mode capabilities.

However, this signal is **NOT sufficient to infer user intent**. The agent
MUST detect the environment automatically but MUST NOT choose the execution
mode automatically.

---

## Key Concepts

### Environment vs Intent

| Concept | Question answered | Where defined |
|---------|-------------------|---------------|
| Environment detection | What is currently running? | `policies/operating-mode.md` (Studio Pro), `policies/execution-intent.md` (Concord MCP) |
| Execution intent | What does the user WANT? | `policies/execution-intent.md` |

These are separate dimensions. Available capability does not imply chosen intent.

### Signal Strength

| Signal | Conditions | Agent behavior |
|--------|-----------|----------------|
| **Strong** | LIVE-SP-CURRENT AND Concord MCP detected | Ask exactly once if intent unresolved |
| **Weak** | LIVE-SP-CURRENT but Concord MCP not detected | No interrupt — continue with coexistence contract |
| **Explicit** | User has stated a preference | Honor it; do not ask |

---

## Detection Mechanism

### Studio Pro

Detected by the existing `scripts/check-studio-pro-status.ps1` during
Startup Re-Sync Step 1 (`orchestrator.md`). No second detector is run.

| Operating mode | Studio Pro state |
|----------------|-----------------|
| LIVE-SP-CURRENT | `detected` |
| CLOSED-AUTONOM | `not_detected` |
| LIVE-SP-OTHER | `not_detected` (for current project) |
| AMBIGUOUS-SP-STATE | `unknown` |

### Concord MCP

**Primary signal**: `mcp__concord-v2-mcp__*` tools in the agent tool namespace.

- `detected` — at least one such tool is available.
- `not_detected` — no such tools present.
- `unknown` — tool namespace inaccessible (e.g., outside Claude Code IDE).

**Configuration evidence** (`.vscode/mcp.json`, `scripts/start-concord-mcp.ps1`)
indicates the MCP is *configured* but NOT necessarily *active*. Configuration
alone does NOT produce `detected`.

---

## The Execution-Intent Question

When the strong signal is present and execution intent is unresolved, the
agent asks exactly once:

> Studio Pro und Concord MCP wurden erkannt. Soll ich diese Session im
> Studio-Pro-/Live-Modus durchführen oder normal/headless weiterarbeiten?
>
> 1. Studio Pro / Live
> 2. Normal / Headless

This question:
- Does NOT satisfy any lifecycle gate
- Does NOT change mission completion status
- Does NOT promote or alter evidence states
- Does NOT trigger a Context Epoch rollover

---

## When Clarification Is Suppressed

| Condition | Reason |
|-----------|--------|
| Intent already resolved + environment unchanged | Prior answer still valid |
| Explicit user preference in current request | User intent is clear |
| Weak signal only (no Concord MCP) | Threshold not met |
| Neither SP nor Concord MCP detected | No signal |
| Platform is Linux/macOS/CI | Studio Pro cannot exist |
| Task does not require execution path choice | Not relevant |

---

## Session State

Stored in `.concord/scratch/process-state.yaml` (gitignored, session cache):

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

This state is session-scoped. On each fresh session environment is re-detected
and the prior intent evaluated for continued validity.

---

## Re-Sync Behavior

| Case | Conditions | Result |
|------|-----------|--------|
| A — Unchanged | Intent resolved + same environment | Use prior choice; do not ask |
| B — Capability gone | Prior `studio_pro_live` + SP or Concord disappeared | Surface change; resolve to `normal_headless` |
| C — Headless chosen | Prior `normal_headless` + strong signal still present | Honor prior choice; do not ask again |

---

## Relationship to Operating Mode

LIVE-SP-CURRENT is the **operating mode** (environment fact, determined by
process detection).

`studio_pro_live` is the **execution intent** (user decision, determined by
this policy).

```
check-studio-pro-status.ps1
    → operating_mode: LIVE-SP-CURRENT
    → (+ Concord MCP detected)
    → ask once (if unresolved)
    → execution_intent: studio_pro_live / normal_headless
    → existing LIVE-SP-CURRENT coexistence contract applies
```

The existing SP-on / LIVE-SP-CURRENT coexistence semantics are fully
preserved. Execution-intent resolution is an additive layer.

---

## Capability Registry

The capabilities `concord_mcp` and `studio_pro_mcp` are registered in
`.mxagile/capabilities.yaml`. The standard state model applies:

- SUPPORTED — `.vscode/mcp.json` has the server entry
- AVAILABLE — MCP tools are active in the agent tool namespace
- ACTIVE — Currently in use

Do not confuse AVAILABLE (capability state) with `studio_pro_live` (user intent).

---

## Detection Limitations

- **Concord MCP probe**: Reliable inside Claude Code IDE extension only. Unknown outside.
- **Studio Pro MCP endpoint**: Not separately probed; process detection is used.
- **Concorde/MxAgile identity architecture**: Explicitly out of scope. Whether
  Concord is or should be an MxAgile lifecycle agent is a deferred design decision.
  This feature is compatible with either future outcome.

---

## Policy Reference

Full behavioral contract: `.mxagile/policies/execution-intent.md`

Integration point in Startup Re-Sync: `orchestrator.md § Schritt 1b`

Capability registry: `.mxagile/capabilities.yaml` — `concord_mcp`, `studio_pro_mcp`
