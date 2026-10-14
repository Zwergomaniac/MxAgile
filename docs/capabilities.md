# MxAgile Capability Discovery

**MxAgile 1.5 — Context Optimization & Capability Discovery**

## Overview

MxAgile 1.5 introduces a machine-readable Capability Registry and a single authoritative resolver. Any agent or human can determine which Framework capabilities exist, are available in the current environment, and are enabled for the project — without relying on model memory.

## Capability State Model

Each capability has six orthogonal state dimensions:

| State | Meaning |
|-------|---------|
| `SUPPORTED` | The installed Framework version knows how to use this capability |
| `AVAILABLE` | Required environment/dependencies detected and compatible |
| `ENABLED` | Project configuration allows use |
| `ACTIVE` | Capability is actually in use right now |
| `DEGRADED` | Operating partially or via fallback (e.g., dependency version mismatch) |
| `UNAVAILABLE` | Required dependency absent or incompatible |

**Important distinctions:**
- `SUPPORTED=true, AVAILABLE=false` — Framework supports it but dependencies are missing
- `AVAILABLE=true, ENABLED=false` — Ready to use, but not activated in project config
- `ENABLED=true, UNAVAILABLE=true` — Config says enabled, but dependency is absent; reports honestly as UNAVAILABLE, not ACTIVE

## Resolver

The single authoritative source for capability state is:

```powershell
scripts/Get-MxAgileCapabilities.ps1
```

This script combines Framework version, capability registry (`.mxagile/capabilities.yaml`), project configuration (`.mxagile/config.yaml`), and environment detection to produce a resolved inventory.

### Human-readable output

```
scripts/Get-MxAgileCapabilities.ps1
```

Example output:
```
MxAgile 1.5 — Capability Status
Project: /path/to/project

  [CONTEXT-LIFECYCLE]
  Context Lifecycle
    Status:  [SUPPORTED — not configured]
    Reason:  Available but not enabled in project configuration

  [CONTEXT-OPTIMIZATION]
  RTK Command Output Optimization
    Status:  [UNAVAILABLE]
    Reason:  rtk not found in PATH
    Dep:     RTK (Rust Token Killer) — NOT DETECTED (rtk not found in PATH)

  Context Mode WARM Retrieval
    Status:  [UNAVAILABLE]
    Reason:  context-mode not found in PATH
```

### Machine-readable JSON (for agents)

```powershell
scripts/Get-MxAgileCapabilities.ps1 -Format json
```

Returns a structured JSON object that agents can parse without interpretation. Use this when answering questions such as:
- "Can MxAgile optimize command output?"
- "Which context features are currently active?"
- "Why is automatic rollover unavailable?"
- "What optional features would help this mission?"

### Single capability detail

```powershell
scripts/Get-MxAgileCapabilities.ps1 -Capability rtk_optimization
```

### Upgrade awareness

```powershell
# Check what's new since this project's last-seen Framework version
scripts/Get-MxAgileCapabilities.ps1 -CheckUpgrades -UpdateDiscoveryState
```

Compares the current Framework version against `.concord/capability-discovery.yaml` (gitignored local state). Reports new capabilities introduced since the last-seen version. The `-UpdateDiscoveryState` flag writes the current version so the next check has a baseline.

## Capability Registry

The registry lives at `.mxagile/capabilities.yaml`. It is machine-readable YAML and is consumed exclusively through the resolver. Do not load it directly into every agent conversation — use the resolver instead.

Schema: `.mxagile/schemas/capabilities.schema.json`

## Registered Capabilities (MxAgile 1.5)

### Context Lifecycle Category

| ID | Name | Introduced | Default |
|----|------|------------|---------|
| `context_lifecycle` | Context Lifecycle | 1.2 | off |
| `checkpoint_resume` | Checkpoint & Resume | 1.3 | off |
| `manual_rollover` | Manual Context Epoch Rollover | 1.4 | off |
| `pressure_recommendations` | Context Pressure Recommendations | 1.4 | off |
| `auto_rollover` | Automatic Context Epoch Rollover | 1.4 | off |

Enablement order: `context_lifecycle` → `checkpoint_resume` → `manual_rollover` → `pressure_recommendations` → `auto_rollover`

See `docs/context-lifecycle.md` for full documentation.

### Context Optimization Category

| ID | Name | Introduced | Default | External Dep |
|----|------|------------|---------|--------------|
| `rtk_optimization` | RTK Command Output Optimization | 1.5 | off | RTK >=0.37.2 (Apache-2.0) |
| `context_mode_integration` | Context Mode WARM Retrieval | 1.5 | off | context-mode >=1.0.33 (ELv2) |

See `docs/context-optimization.md` for installation and configuration.

### Knowledge Graph Category

| ID | Name | Introduced | Default | External Dep |
|----|------|------------|---------|--------------|
| `graphify` | Graphify Code Graph | 1.0 | off | graphify >=0.9.28 |

## Safe Agentic Activation

An agent may safely activate a capability when:

1. The capability is `SUPPORTED` — Framework supports it
2. The capability is `AVAILABLE` — Dependencies detected and compatible
3. The capability is not already `ACTIVE`
4. Prerequisites (listed in `requires`) are enabled
5. The configuration change is project-local (agent may edit `.mxagile/config.yaml`)

**External installation** (RTK, Context Mode) requires explicit user authorization. An agent must:
1. Report that the capability is available but requires external installation
2. Describe what installation is needed (`user_approval_required: true` in registry)
3. Wait for user confirmation before proceeding

**Never** set `enabled: true` for a capability whose dependencies are absent — this creates a misleading `ENABLED` state that can never become `ACTIVE`.

## Recommendation Policy

Agents may proactively surface an optional capability when **all** of:
- It is relevant to the current task
- It is `SUPPORTED` and `AVAILABLE`
- It is not already `ACTIVE`
- Expected benefit is meaningful
- The same recommendation was not just dismissed

**Do not** recommend every optional feature on every startup. Do not block work because an optional optimization is disabled.

Examples:
- CLI-heavy mission → RTK optimization may be relevant
- Long-running multi-epoch mission → Context Lifecycle may be relevant
- Large historical search/retrieval workload → Context Mode may be relevant (if available)

## Authority Model

External optimization tools (RTK, Context Mode) are subordinate adapters. They may optimize output or externalize context. They have **no authority** over:

- Mission identity, lifecycle, and completion
- Context Epoch state and checkpoint validity
- Resume Contract and Re-Sync
- Scope and user overrides
- Gate state and acceptance state
- Evidence states (VERIFIED / FAILED / UNVERIFIED / STALE / SUPERSEDED)

When external tool output conflicts with canonical MxAgile evidence, MxAgile evidence wins.

## Upgrade Awareness

After a Framework update, agents can determine what new capabilities were introduced:

```powershell
scripts/Get-MxAgileCapabilities.ps1 -CheckUpgrades -Format json
```

The result includes an `upgrade_awareness.new_capabilities` array listing capability IDs introduced since `last_seen_version`. This supports upgrade UX without requiring a mandatory onboarding wizard.

**State file:** `.concord/capability-discovery.yaml` (gitignored, local only).

Agents should not repeatedly announce the same new capabilities. Check once per Framework version change and acknowledge with `-UpdateDiscoveryState`.

---

## Capability Summary UX (RF-Campaign: Section 14)

A normal MxAgile developer should not need to know feature names or read all documentation.
The Capability Resolver surfaces a concise summary when asked (e.g. `/mxagile status`,
"what can MxAgile do", "what optimizations are available").

### Desired Output Format

```
MxAgile 1.6

Core:
  Context Lifecycle       ACTIVE
  Checkpoint / Resume     ACTIVE
  Re-Sync                 ACTIVE

Optional optimization:
  RTK                     AVAILABLE (not enabled)
  Context Mode            UNAVAILABLE (not installed)
  Graphify                UNAVAILABLE (not installed)

Environment:
  Studio Pro              LIVE-SP-CURRENT (PID 1234)
  Concord MCP             not detected
```

**Rules:**
- Only surface the summary when explicitly requested or at system check.
- Do NOT flood every prompt with capability state.
- Only recommend optional capabilities when relevant to the current work.
- Do NOT repeatedly recommend capabilities the user just declined.
- Do NOT auto-install external dependencies.

### Recommendation Trigger Examples

| Current work | Relevant recommendation |
|-------------|------------------------|
| CLI-output-heavy mission | RTK (if AVAILABLE but not enabled) |
| Long historical context, multi-epoch workload | Context Mode (if AVAILABLE but not enabled) |
| Large cross-file code analysis | Graphify (if AVAILABLE but not enabled) |

---

## AI-First Capability Discovery (Section 15)

Agents must be able to answer intent-level questions without relying on model memory:

| User question | Resolver path |
|---------------|--------------|
| "Can MxAgile reduce context usage?" | `Get-MxAgileCapabilities.ps1 -Category context-optimization` |
| "Can this mission survive a new session?" | `Get-MxAgileCapabilities.ps1 -Capability checkpoint_resume` |
| "What optional optimizations are available?" | `Get-MxAgileCapabilities.ps1` |

The pattern is:

```
small routing instruction in always-loaded content
    ↓
Get-MxAgileCapabilities.ps1 (resolver)
    ↓
structured capability output
    ↓
agent provides relevant explanation based on actual state
```

Always-loaded instructions remain concise (routing only). Full capability details
come from the resolver on demand, not from static always-loaded text.
