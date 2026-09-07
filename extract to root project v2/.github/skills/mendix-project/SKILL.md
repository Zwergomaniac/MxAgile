---
name: mendix-project
description: Use for any Mendix project task, model question, MDL change, security change, page change, navigation change, Docker build, Playwright test, MPR-v2 operation, Concord workflow, or agent customization in this repository.
---

# Mendix Project Skill

This repository has one canonical Mendix skill library at `.ai-context/skills/`.
Before acting, load `.ai-context/skills/README.md` and then the narrowest relevant
skill. For agent-related work, also load `.ai-context/skills/agents.md`.

## Required Routing

- For Mendix model reads or writes, use Studio Pro MCP / Concord first when available.
- For Mendix how-to questions, use the grounded Concord knowledge route instead of memory.
- Before microflows, load `write-microflows.md`.
- Before domain-model changes, load `generate-domain-model.md`.
- Before pages, load `create-page.md` or `alter-page.md`.
- Before security, load `manage-security.md`.
- Before navigation, load `manage-navigation.md`.
- Before Docker or browser tests, load `docker-workflow.md`, `test-app.md`, and `skillssource/agent-test-workflow.md`.

## Safety

- Never run Git write commands in this Mendix project.
- Never destructively modify model elements without explicit confirmation in the same turn.
- Never modify `[Spec.md]` or files under `input-resources/` unless explicitly requested.
- Never expose, print, commit, or store credentials in MDL, logs, screenshots, or reports.
- Before and after model actions, perform the MPR-v2 materialization checks described in `AGENTS.md`.
- Board snapshots are read-only; the Mendix Epics Board remains authoritative.

## Canonical Test Workflow

Use `scripts/run-docker-isolated.ps1`. It creates one random Administrator only for
the initial login, then tests the existing demo-user switcher. Do not create one
temporary user per demo role. Keep the detailed workflow in
`skillssource/agent-test-workflow.md` and the technical skills in `.ai-context/skills/`.
