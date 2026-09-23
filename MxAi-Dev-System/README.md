# MxAgile Framework

MxAgile is a specification-driven, Mendix-native development framework powered by AI agents.
It governs the full lifecycle from Discovery through Refinement, Implementation, and Verification,
with a structured evidence contract that supports team collaboration and safe Core updates.

---

## What Is MxAgile?

MxAgile provides:
- **Agents** that understand Mendix: Discovery, Refinement, Implementation, Acceptance
- **Lifecycle contracts** for traceability from mockup through runtime parity
- **Intent-driven Mendix element selection** (pattern before widget, not data-shape defaults)
- **Multidimensional UI parity** (visual, content, structure, state, interaction, responsive, role)
- **Canonical project knowledge** stored in Git-tracked project files — not in agent scratch

## Core, Company Layer, and Project Knowledge

| Layer | Description |
|---|---|
| **Core** | Framework policies, agent instructions, schemas — installed/updated via `mxagile-setup.ps1` |
| **Company Layer** | Extensions for a specific company (UI library, conventions, credentials) — installed alongside Core |
| **Project Knowledge** | Requirements, Specs, Tasks, Decisions, mockups, parity evidence — owned by the project |

Project Knowledge survives Core updates unchanged. Core updates add new capabilities; they do not
discard existing Requirements, Specs, Decisions, or accepted Discovery/Refinement.

---

## Installation and Update

Run from the project root in PowerShell:

```powershell
# Generic MxAgile (detects fresh install vs. update automatically)
.\mxagile-setup.ps1

# Mercedes-Benz environment (installs/updates Core and Mercedes Company Layer)
.\mxagile-setup-mercedes.ps1
```

> `install-mxagile.ps1` and `install-mxagile-mercedes.ps1` are **deprecated** compatibility
> wrappers. They delegate to the setup scripts above.

After changing canonical `.mxagile/` sources, regenerate platform projections:

```powershell
.\scripts\generate-mxagile-platform-skills.ps1
```

---

## What Happens After a Core UPDATE?

A Core UPDATE **preserves all existing project knowledge**. It does NOT restart Discovery or Refinement.

Post-update flow:
1. `mxagile-setup.ps1` → Core UPDATE (preserves `.mxagile/layers/`, project-owned files)
2. **Lifecycle re-sync** — agent reads current `process-state.yaml` and resumes from current position
3. **Project structure inventory** — map existing artifacts to canonical locations
4. **Reconciliation** — classify existing Discovery/Refinement/evidence, preserve what is valid
5. **Gap identification** — identify only what is missing or stale
6. **Continue lifecycle** — reopen only affected scope

Full policy: `.mxagile/policies/reconciliation.md`

---

## Lifecycle Re-Sync

If an agent session is interrupted or a fresh agent starts, it reconstructs lifecycle state from:

1. `planning/lifecycle/process-state.yaml` — canonical durable lifecycle state (Git-tracked)
2. `planning/` — implementation checklist, scenarios, parity reports
3. `requirements/`, `specs/` — current Requirements and Specs
4. `planning/decisions/` — accepted decisions

`.concord/scratch/process-state.yaml` is a local session cache (gitignored). Deleting it
must not destroy canonical lifecycle knowledge.

A fresh agent detects existing Discovery/Refinement and **reconciles** rather than restarts.

Full policy: `.mxagile/policies/lifecycle-resync.md`

---

## Discovery Reconciliation

**Existing Discovery does NOT restart after a Core update.**

Discovery Reconciliation classifies each existing finding as: REUSABLE, RECONSTRUCTABLE,
INCOMPLETE, STALE, CONFLICTING, or MISSING — then supplements or reopens only affected scope.

Full policy: `.mxagile/policies/reconciliation.md — Discovery Reconciliation Contract`

---

## Refinement Reconciliation

**Existing accepted Refinement decisions do NOT restart after a Core update.**

Accepted product/design decisions, widget selections, and UI intent are preserved.
Only the decisions actually invalidated by new evidence are reopened.

Full policy: `.mxagile/policies/reconciliation.md — Refinement Reconciliation Contract`

---

## Evidence Reconciliation

When parity contracts become richer (new dimensions added), existing parity results are
conservatively upgraded:
- `REUSABLE` evidence → preserved with reference
- `LEGACY_EVIDENCE` → migrated with provenance
- Missing dimensions → `NOT_VERIFIED`, requiring targeted re-verification only

**Full Reconciliation** = full scope accounting + conservative evidence reuse + targeted re-verification.
It does NOT mean re-running all browser tests.

Full policy: `.mxagile/policies/ui-parity.md — Full Reconciliation`

---

## Canonical Project Locations

| Artifact | Location | Git tracked |
|---|---|---|
| Source mockups (immutable) | `input-resources/ui-ux/` | YES |
| Refined target mockups | `planning/target-mockups/` | YES |
| Requirements | `requirements/REQ-NNN.yml` | YES |
| Specs | `specs/SPEC-NNN.yml` | YES |
| Tasks | `planning/tasks/TASK-NNN.yml` | YES |
| Decisions | `planning/decisions/` | YES |
| UI inventories | `planning/ui-inventory/` | YES |
| Verification scenarios | `planning/scenarios/` | YES |
| Parity reports | `planning/parity/` | YES |
| Promoted screenshots | `planning/evidence/screenshots/` | YES |
| Evidence manifests | `planning/evidence/manifests/` | YES |
| Lifecycle/wave state | `planning/lifecycle/process-state.yaml` | YES |

Full canonical artifact map: `.mxagile/policies/project-knowledge.md`

---

## What Is Temporary?

The `.concord/` directory is **gitignored** — it holds ephemeral runtime and tool output:
- `.concord/scratch/process-state.yaml` — session lifecycle state (reconstruct each session)
- `.concord/screenshots/` — temporary browser screenshots before promotion

Accepted findings and promoted screenshots must be in `planning/` to survive a fresh clone.

---

## What Must Never Be Committed?

- `.env.mendix` — local credentials (database passwords, test user passwords)
- Any file containing secret values

Full policy: `.mxagile/policies/project-knowledge.md — GitIgnore Contract`

---

## Reference Documentation

| Topic | Location |
|---|---|
| Installation and Core update | [`docs/installation.md`](docs/installation.md) |
| Architecture overview | [`docs/architecture.md`](docs/architecture.md) |
| Canonical schemas | [`docs/schemas.md`](docs/schemas.md) |
| Company Layers | [`docs/company-layers.md`](docs/company-layers.md) |
| Lifecycle policies | [`.mxagile/policies/`](.mxagile/policies/) |
| Reconciliation | [`.mxagile/policies/reconciliation.md`](.mxagile/policies/reconciliation.md) |
| UI parity contract | [`.mxagile/policies/ui-parity.md`](.mxagile/policies/ui-parity.md) |
| Project knowledge / Git tracking | [`.mxagile/policies/project-knowledge.md`](.mxagile/policies/project-knowledge.md) |
| Injection contract | [`docs/injection-contract.md`](docs/injection-contract.md) |
