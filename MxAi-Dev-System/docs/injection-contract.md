# MxAgile Injection Contract

```
schema_version: 1
framework_version: 1.1
```

---

## Overview

The Injection Contract defines the authoritative ownership, update behavior, and rerun semantics for every file and directory that MxAgile touches during installation and agent setup.

It answers the question: "Who owns this file, who writes it, and what happens when the installer runs again?"

Consumers of this contract include:

- **Installers** (`install-core.ps1`, `mxagile-init.ps1`, `setup-agent-system.ps1`) — must respect ownership boundaries
- **Generators** (`apply-project-agent-instructions.ps1`, `generate-mxagile-platform-skills.ps1`) — must implement idempotent rerun semantics
- **Agents** — must understand which files they may edit and which are managed or generated
- **Tests** — validate that actual installer/generator behavior matches this contract

---

## Artifact Classification

| Category | Definition |
|----------|-----------|
| `CREATE` | Created once (on init) from a template or as empty placeholder. NOT overwritten on rerun if it already exists. |
| `COPY` | Copied from a source location. Overwritten on rerun. |
| `GENERATE` | Produced by a generator script from canonical source. Always overwritten on rerun. Do not manually edit. |
| `MANAGED_BLOCK` | File is shared: user content is preserved; MxAgile writes only within its managed block. Block is replaced on every run. |
| `PRESERVE` | Read but never overwritten by MxAgile tooling. |
| `RUNTIME` | Downloaded/installed at runtime (e.g., mxcli binary). Not in source control. |
| `NEVER_TOUCH` | MxAgile must never read or write these files. |

---

## Artifact Table

| Path | Category | Source | Producer | Ownership | Update Behavior | Rerun Behavior |
|------|----------|--------|----------|-----------|-----------------|----------------|
| `.mxagile/` | COPY | `MxAi-Dev-System/.mxagile/` | `mxagile-init.ps1` creates dirs; framework NOT copied by installer | MxAgile Framework | Recreated if missing | Idempotent (dirs only, no content overwrite) |
| `AGENT.md` | CREATE | Empty placeholder | `mxagile-init.ps1` | Project / User | Preserve existing | Skip if exists |
| `AGENTS.md` | MANAGED_BLOCK | `AGENT.md` content (full) | `apply-project-agent-instructions.ps1` | Shared: user owns file, MxAgile owns managed block | Replace block content | Replace block, preserve surrounding user content |
| `CLAUDE.md` | MANAGED_BLOCK | `@AGENT.md` reference | `apply-project-agent-instructions.ps1` | Shared: user owns file, MxAgile owns managed block | Replace block content | Replace block, preserve surrounding user content |
| `.github/copilot-instructions.md` | MANAGED_BLOCK | `AGENT.md` content (full) | `apply-project-agent-instructions.ps1` | Shared: user owns file, MxAgile owns managed block | Replace block content | Replace block, preserve surrounding user content |
| `.claude/skills/mxagile-*/SKILL.md` | GENERATE | `.mxagile/skills/*.md` | `generate-mxagile-platform-skills.ps1` | MxAgile (generated — do not edit) | Overwrite on rerun | Always regenerated |
| `.github/skills/mxagile-*/SKILL.md` | GENERATE | `.mxagile/skills/*.md` | `generate-mxagile-platform-skills.ps1` | MxAgile (generated — do not edit) | Overwrite on rerun | Always regenerated |
| `.claude/agents/mxagile-*.md` | GENERATE | `.mxagile/agents/*.md` | `generate-mxagile-platform-skills.ps1` | MxAgile (generated — do not edit) | Overwrite on rerun | Always regenerated |
| `.agents/skills/mxagile/` | GENERATE | `.mxagile/skills/*.md` | `generate-mxagile-platform-skills.ps1` | MxAgile (generated — do not edit) | Overwrite on rerun | Always regenerated |
| `.grok/skills/mxagile/` | GENERATE | `.mxagile/skills/*.md` | `generate-mxagile-platform-skills.ps1` | MxAgile (generated — do not edit) | Overwrite on rerun | Always regenerated |
| `.opencode/skills/mxagile/` | GENERATE | `.mxagile/skills/*.md` | `generate-mxagile-platform-skills.ps1` | MxAgile (generated — do not edit) | Overwrite on rerun | Always regenerated |
| `.hermes/skills/mxagile/` | GENERATE | `.mxagile/skills/*.md` | `generate-mxagile-platform-skills.ps1` | MxAgile (generated — do not edit) | Overwrite on rerun | Always regenerated |
| `update-mxcli.ps1` | COPY | `MxAi-Dev-System/scripts/install-mxcli.ps1` | `install-core.ps1` | MxAgile | Overwrite on rerun | Always copied |
| `mxcli.exe` | RUNTIME | mxcli download service | `install-mxcli.ps1` (via `mxagile-init.ps1`) | MxAgile | Update via `update-mxcli.ps1` | Skip if exists and up-to-date |
| `.mxagile/layers/{id}/` | COPY (from Git/Local) | Company Layer Git/Local source | `fetch-layer.ps1` or `install-core.ps1` | Company Layer | Replace on reinstall | Replace existing |
| `.mxagile/layers/{id}/provenance.json` | GENERATE | Installation metadata | `fetch-layer.ps1` / `install-core.ps1` | MxAgile | Overwrite on reinstall | Always regenerated |
| `.mxagile/state/manifest.{id}.md` | GENERATE | Layer install metadata | `fetch-layer.ps1` | MxAgile | Overwrite on reinstall | Always regenerated |
| `requirements/` | CREATE | Empty directory | `mxagile-init.ps1` | Project | Never overwrite content | Idempotent (skip if exists) |
| `specs/` | CREATE | Empty directory | `mxagile-init.ps1` | Project | Never overwrite content | Idempotent (skip if exists) |
| `planning/tasks/` | CREATE | Empty directory | `mxagile-init.ps1` | Project | Never overwrite content | Idempotent (skip if exists) |
| `.gitignore` entries | MANAGED | N/A | `apply-project-agent-instructions.ps1` | Shared | Append missing entries | Idempotent (no duplicates appended) |

---

## Managed Block Contract

### Marker Format

```
<!-- MXAGILE:MANAGED:START -->
[MxAgile-managed content here]
<!-- MXAGILE:MANAGED:END -->
```

### Legacy Markers (Backward Compatibility)

Old markers detected and migrated automatically on the next run of `apply-project-agent-instructions.ps1`:

```
<!-- BEGIN PROJECT AGENT INSTRUCTIONS -->
[old managed content]
<!-- END PROJECT AGENT INSTRUCTIONS -->
```

When old markers are detected, the script:
1. Removes the old block
2. Re-inserts the content using the new canonical markers
3. Preserves all user content outside the block

### Semantics

| State | Condition | Behavior |
|-------|-----------|----------|
| `MISSING` | 0 START + 0 END | Insert block at end of existing user content |
| `VALID` | 1 START + 1 END | Replace block in-place (new or old markers) |
| `DUPLICATE` | >1 START or >1 END | **FAIL** — script exits non-zero with diagnostic message |
| `MALFORMED` | START count ≠ END count (but not duplicate) | **FAIL** — script exits non-zero with diagnostic message |

### Never-Touch Invariant

User content outside the managed block MUST NEVER be modified. This applies to:
- Content before `<!-- MXAGILE:MANAGED:START -->`
- Content after `<!-- MXAGILE:MANAGED:END -->`

The only permitted operation on these regions is preserving them verbatim.

### Content by Target File

| Target File | Managed Block Content |
|-------------|----------------------|
| `AGENTS.md` | Full content of `AGENT.md` |
| `CLAUDE.md` | `@AGENT.md` (Claude-specific include syntax) |
| `.github/copilot-instructions.md` | Full content of `AGENT.md` (Copilot does not support `@`-includes) |

---

## Company Layer Contract

Company Layers are external extensions of MxAgile Core installed into `.mxagile/layers/{layer-id}/`.

### Required Files in Layer Source

| File | Required | Description |
|------|----------|-------------|
| `layer.json` | YES | Must contain `id` (string, no spaces) and `name` (string) fields |
| `provenance.json` | Generated by installer | Written by `fetch-layer.ps1` or `install-core.ps1`; contains `source_type` and `source` (plus `resolved_revision` for Git sources) |

### Optional Files in Layer Source

| File/Dir | Description |
|----------|-------------|
| `glossary.yml` | Domain-specific glossary |
| `modules/` | Mendix module definitions |
| `platform-modules.yml` | Platform module declarations |

### Installation Rules

1. **Destination**: `.mxagile/layers/{layer-id}/` where `layer-id` comes from `layer.json`.
2. **`.git/` directory**: The installer MUST strip any nested `.git/` directory. Presence of `.git/` in an installed layer is a **contract violation**.
3. **Provenance**: `provenance.json` is written by the installer — never committed in the layer source.
4. **State manifest**: `.mxagile/state/manifest.{layer-id}.md` is written after successful installation.

### Detecting a Violation

The `mxagile-system-check` skill checks for nested `.git/` in installed layers and reports `FAIL` if found.

---

## Platform Projection Naming

| Platform | Skill Directory | Agent Directory | Skill Name Prefix |
|----------|----------------|-----------------|-------------------|
| Claude Code | `.claude/skills/mxagile-{name}/SKILL.md` | `.claude/agents/mxagile-{name}.md` | `mxagile-` |
| GitHub Copilot | `.github/skills/mxagile-{name}/SKILL.md` | N/A | `mxagile-` |
| OpenAI Codex | `.agents/skills/mxagile/{name}.md` | N/A | (file name only) |
| Grok | `.grok/skills/mxagile/{name}.md` | N/A | (file name only) |
| OpenCode | `.opencode/skills/mxagile/{name}.md` | N/A | (file name only) |
| Hermes | `.hermes/skills/mxagile/{name}.md` | N/A | (file name only) |

Note: The directory name `dfc/` is a **stale legacy naming** that was superseded by `mxagile/`. Old installs may have `.agents/skills/dfc/` etc. — these should be treated as stale and migrated.

---

## NEVER_TOUCH Paths

MxAgile tooling must never read or modify these paths:

| Path | Reason |
|------|--------|
| `*.mpr` | Mendix project database — binary, tool-managed |
| `requirements/**` | Project requirements content — user-owned |
| `specs/**` | Project specifications — user-owned |
| `planning/**` | Project planning content — user-owned |
| `input-resources/**` | User-provided input artifacts |
| User content outside MxAgile managed blocks | Ownership invariant |
| `.concord/` | Local runtime state |

---

## Known Issues and Notes

### mercedes-benz layer `.git/` in dev repo (tracked in git status as staged for deletion)

The development repository temporarily contained a nested `.git/` inside the `company-layers/mercedes-benz/` directory. This was staged for deletion and has no impact on installed projects — `install-core.ps1` strips `.git/` on install (`-Exclude ".git"` in `Copy-Item`). The `mxagile-system-check` skill will flag this as a violation if found in any installed layer.

### `dfc/` → `mxagile/` directory naming migration

Skills generated for Codex, Grok, OpenCode, and Hermes used `dfc/` directory naming in earlier versions. The canonical naming is `mxagile/`. Projects installed with older versions may have stale `dfc/` directories. Rerunning `generate-mxagile-platform-skills.ps1` generates the correct `mxagile/` directories. Old `dfc/` directories should be removed manually or via cleanup tooling.
