# MxAgile Repository Development Instructions

## Purpose

This repository develops the MxAgile framework itself.

Do not confuse framework development with a Mendix project that has MxAgile installed.

## Architecture

The public Bootstrap entry points are:

- install-mxagile.ps1
- install-mxagile-mercedes.ps1

Both delegate actual installation to:

- scripts/install-core.ps1

`install-core.ps1` is also the canonical entry point for existing-project Core synchronization.
It retires stale framework-owned artifacts and re-installs the current Core payload while
preserving project-owned state, migration history, and Company Layers.

Do not duplicate installation behavior in the public bootstrap scripts.

## Source of Truth

.mxagile/ is the agent-agnostic source for MxAgile framework skills and agents.

Platform projections are generated artifacts.

Do not manually edit generated MxAgile projections.

After changing canonical agent/skill sources, use the canonical projection generator.

## Agent Instruction Architecture

AGENT.md is the neutral project-instruction source used by MxAgile installations.

Platform-specific files such as AGENTS.md, CLAUDE.md and Copilot instructions are
projections/adapters.

Changes to injected Agent behavior should normally originate from the canonical source,
not individual platform projections.

## Company Layers

Company Layers are external extensions of MxAgile Core.

The canonical installer supports:

- Git source
- explicit Local source

Do not introduce an implicit local Company Layer fallback.

## Architecture Overview

```mermaid
flowchart LR
    CA[.mxagile/\ncanonical source]
    GEN[generate-mxagile-platform-skills.ps1]
    APA[apply-project-agent-instructions.ps1]

    CA -->|skills + agents| GEN
    GEN -->|GENERATED projections| CP[.claude/skills/\n.github/skills/\n.agents/skills/mxagile/\netc.]

    NI[AGENT.md\nneutral project instructions]
    NI -->|managed block| APA
    APA -->|MANAGED_BLOCK| PE[AGENTS.md\nCLAUDE.md\ncopilot-instructions.md]
```

Generated platform projections must not be manually maintained.
Canonical source changes flow through the generator.

## Brownfield Artifact Canonicalization

Framework migration (DFC-AI → MxAgile) and artifact canonicalization are distinct lifecycles.

A project with `status: complete` in `.mxagile/migration/state.yaml` AND
`artifact_canonicalization: pending` is in valid HYBRID mode — migration complete,
canonicalization not yet started. Normal MxAgile project work can proceed in hybrid mode.

Canonicalization converts legacy `.md` stories to canonical `.yml` artifacts
(`requirements/REQ-NNN.yml`, `specs/SPEC-NNN.yml`, `planning/tasks/TASK-NNN.yml`).
See `.mxagile/skills/migration.md` and `docs/schemas.md`.

## Reference Documentation

- [docs/injection-contract.md](MxAi-Dev-System/docs/injection-contract.md) — authoritative artifact ownership contract
- [docs/architecture.md](MxAi-Dev-System/docs/architecture.md) — detailed architecture diagrams
- [docs/schemas.md](MxAi-Dev-System/docs/schemas.md) — canonical artifact schema contract (Requirement/Spec/Task)
- [docs/installation.md](MxAi-Dev-System/docs/installation.md) — installation and Core update guide

## mxcli

`mxcli.exe` is the required Mendix engineering tool.

- Installer: `scripts/install-mxcli.ps1`
- Updater: `scripts/install-mxcli.ps1` (distributed to projects as `update-mxcli.ps1`)
- Ownership: MxAgile Core

Do not change mxcli installation without updating the canonical installer.

## Testing Strategy

- Tier 0: parser/static/marker validation — run first, run often
- Tier 1: managed block fixtures, injection snapshot, platform projection tests
- Tier 2: canonical install into disposable fixture project
- Tier 3+: E2E bootstrap (expensive — run on significant changes only)

See `tests/` directory for existing test suite.
