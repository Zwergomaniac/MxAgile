# MxAgile Context Optimization

**MxAgile 1.5 — Context Optimization & Capability Discovery**

Context Optimization is an optional layer that reduces token consumption through two independent adapters: RTK (command output) and Context Mode (WARM context externalization). Both are off by default. Neither affects MxAgile lifecycle authority.

## Authority Model

MxAgile remains the **sole authority** for all lifecycle decisions. Context optimization adapters are subordinate and may not:

- Change evidence states (VERIFIED / FAILED / UNVERIFIED / STALE / SUPERSEDED)
- Decide gate completion or mission completion
- Determine lifecycle phase
- Decide whether Re-Sync may be skipped
- Replace canonical MxAgile evidence artifacts

## RTK — Command Output Optimization

### Upstream Assessment

| Field | Value |
|-------|-------|
| Repository | `https://github.com/rtk-ai/rtk` |
| Assessed version | 0.37.2+ |
| Assessed date | 2026-10-13 |
| License | Apache-2.0 |
| Windows support | Yes (since v0.37.2) |
| Integration mechanism | Claude Code PreToolUse hook (`rtk hook claude`) |
| Scope | Bash tool calls only — built-in tools (Read, Grep, Glob) unaffected |
| Telemetry | Disabled by default; opt-in via `rtk telemetry enable` |

### What RTK Does

RTK intercepts Bash shell commands and compresses output before it enters the model context window. Four strategies: smart filtering, grouping, truncation, deduplication. Token estimates use `bytes / 4` — approximate but consistent.

RTK does NOT intercept Claude Code built-in tools (Read, Grep, Glob). Those continue to route normally.

### Installation

**Windows:**
```
winget install rtk-ai.rtk
```

**macOS/Linux:**
```
brew install rtk
```

Do not run remote installer scripts (`curl | sh`). Use the package manager.

### Wiring the Hook

After installation, wire the Claude Code PreToolUse hook:

```
rtk init -g
```

Verify:
```
rtk init --show
```

This mutates `~/.claude/settings.json`. Requires explicit user authorization.

Uninstall:
```
rtk init -g --uninstall
```

### Enabling in Project Config

```yaml
# .mxagile/config.yaml
context_optimization:
  enabled: true
  rtk:
    enabled: true
    preserve_raw_evidence: true
```

### Output Safety Classification

MxAgile assigns each command a safety classification:

| Class | Meaning | Examples |
|-------|---------|---------|
| `LOSSLESS_REQUIRED` | Complete canonical output must be preserved | playwright test, mxcli test, security scans, migration verification |
| `COMPACT_SAFE` | Compact representation preserves actionable result | git status/log, npm list, tsc, docker ps |
| `BYPASS` | Pass through without optimization | Unsupported commands, failures, uncertain semantics |

For `LOSSLESS_REQUIRED` commands, raw output is preserved alongside the RTK-optimized summary. The `preserve_raw_evidence: true` setting (default) enables this.

### Fallback

MxAgile falls back to native command execution when RTK is not installed, disabled, crashes, or rejects a command. Original exit-code semantics are preserved. Fallback is reported diagnostically.

**Non-idempotent commands are never re-run through a fallback path after uncertain execution.**

### Integration Definition

Full technical specification: `.mxagile/integrations/rtk.yaml`

---

## Context Mode — WARM Context Externalization

### Upstream Assessment

| Field | Value |
|-------|-------|
| Repository | `https://github.com/mksglu/context-mode` |
| Assessed version | 1.0.33+ |
| Assessed date | 2026-10-13 |
| License | **ELv2 (Elastic License v2)** |
| Redistribution | **NOT permitted by MxAgile** — must be installed by the developer |
| Windows support | Yes |
| Integration mechanism | Claude Code plugin + MCP tools |
| Storage | SQLite at `~/.context-mode/` |

### License Warning

Context Mode uses the **Elastic License v2 (ELv2)**. ELv2 is source-available but **not OSI open source**. It restricts redistribution in commercial products. MxAgile does NOT vendor or redistribute Context Mode. You must install it separately. Always review the current license before commercial use.

### What Context Mode Does

Context Mode externalizes bulky content to a local SQLite+FTS5 knowledge base. The agent can retrieve relevant content on demand via `ctx_search`. This prevents large exploratory results, historical analyses, and debugging findings from consuming active context window.

### Installation

**Claude Code (recommended):**
```
/plugin marketplace add mksglu/context-mode
/plugin install context-mode@context-mode
```
Then verify: `/context-mode:ctx-doctor`

**npm global:**
```
npm install -g context-mode
```

**MCP-only (no hooks):**
```
claude mcp add context-mode -- npx -y context-mode
```

Requires Claude Code plugin v1.0.33+. Installation requires explicit user authorization.

### Enabling in Project Config

```yaml
# .mxagile/config.yaml
context_optimization:
  enabled: true
  context_mode:
    enabled: true
```

### WARM Context Mapping

Context Mode is used only for **WARM** context — material that is not required on every turn but may be useful to retrieve:

- Historical analyses and exploratory search results
- Earlier debugging findings no longer in active scope
- Older tool-result detail superseded by later findings
- Contextual background information

**HOT context** (mission objective, lifecycle phase, gates, evidence states, next action) remains MxAgile-owned and is never externalized.

**COLD evidence** (test logs, acceptance reports, screenshots, runtime traces) remains in canonical MxAgile storage (`planning/lifecycle/`, `.concord/`). Context Mode may help locate COLD artifacts but cannot replace their canonical storage.

### Anti-Dual-Memory Guarantee

**Critical acceptance requirement:** Content returned by Context Mode is RETRIEVED context, not authoritative MxAgile evidence.

Example scenario:
```
MxAgile gate = UNVERIFIED
Context Mode ctx_search returns: "API test passed in epoch 1"
Required outcome: gate remains UNVERIFIED
```

The gate remains UNVERIFIED until MxAgile's own evidence rules establish a valid result. No retrieval provider may directly promote:
- `UNVERIFIED → VERIFIED`
- `FAILED → VERIFIED`
- `STALE → VERIFIED`

Retrieved content must be treated as background information requiring normal MxAgile provenance evaluation.

Test coverage: `tests/test-anti-dual-memory.ps1`

### Context Mode MCP Tools (MxAgile Usage)

| Tool | MxAgile Use |
|------|------------|
| `ctx_doctor` | Capability health check |
| `ctx_index` | Externalize eligible WARM content |
| `ctx_search` | Retrieve WARM context on demand |
| `ctx_stats` | Diagnostics and savings reporting |
| `ctx_execute` | Sandboxed code execution (not used for lifecycle) |

### Epoch Integration

Context Mode integrates with Context Epoch rollover as an optional step:

**Before rollover:**
1. MxAgile: Preserve COLD evidence
2. MxAgile: Preserve HOT mission state
3. **Context Mode (optional):** Externalize eligible WARM content via `ctx_index`
4. MxAgile: Checkpoint mission state
5. MxAgile: Validate checkpoint
6. MxAgile: Close Epoch

**After new Epoch:**
1. MxAgile: Load Resume Contract
2. MxAgile: Perform Re-Sync
3. MxAgile: Reconstruct HOT state
4. **Context Mode (optional):** Retrieve relevant WARM context via `ctx_search`

### Fallback

MxAgile continues when Context Mode is absent, disabled, unavailable, or temporarily failing. A missing Context Mode instance never prevents Resume, Re-Sync, checkpoint validation, evidence access, or normal agent operation.

### Integration Definition

Full technical specification: `.mxagile/integrations/context-mode.yaml`

---

## Detecting Capability State

Run the resolver to check current state:

```powershell
# Human-readable
scripts/Get-MxAgileCapabilities.ps1

# Machine-readable JSON
scripts/Get-MxAgileCapabilities.ps1 -Format json

# Specific capability
scripts/Get-MxAgileCapabilities.ps1 -Capability rtk_optimization
scripts/Get-MxAgileCapabilities.ps1 -Capability context_mode_integration
```

Full documentation: `docs/capabilities.md`
