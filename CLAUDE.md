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

