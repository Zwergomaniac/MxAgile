# Project Knowledge

Canonical contract for which MxAgile artifacts constitute versioned project knowledge,
where they belong, whether they are Git-tracked, and how a fresh developer or agent session
can reconstruct the current accepted project state.

## The Principle

**PROJECT KNOWLEDGE IS VERSIONED PROJECT STATE.**

Any non-secret artifact required for collaboration, lifecycle re-sync, future agent sessions,
review, traceability, Refinement, implementation reasoning, verification, acceptance, or
historical understanding must be in canonical Git-tracked project state.

Not in:
- Agent scratch (`.concord/scratch/`)
- Tool temporary directories (`.concord/screenshots/`, Playwright working dirs)
- Ignored browser output
- Local session state

---

## Artifact Classification

| Class | Git tracked | Persistence | Examples |
|---|---|---|---|
| **CANONICAL** | YES | Permanent | Requirements, Specs, Tasks, Decisions, source mockups, target mockups, UI inventories |
| **GENERATED** | YES | Reproducible | Platform projections (`generated`, do not manually edit) |
| **EVIDENCE** | YES (after promotion) | Permanent | Promoted screenshots, parity reports, evidence manifests |
| **TEMPORARY** | NO (gitignored) | Ephemeral | `.concord/` screenshots, agent scratch, temp tool output |
| **SECRET** | NEVER | Local only | `.env.mendix`, credentials, tokens |

---

## Canonical Project Artifact Map

| Artifact Type | Canonical Path | Git Tracked | Immutable/Evolving | Owner Phase |
|---|---|---|---|---|
| Source mockups | `input-resources/ui-ux/` | YES | IMMUTABLE | Discovery |
| Archived source mockups | `input-resources/ui-ux/_archive/` | YES | IMMUTABLE | Discovery |
| Refined target mockups | `planning/target-mockups/` | YES | EVOLVING | Refinement |
| Target mockup history | `planning/target-mockups/_history/` | YES | IMMUTABLE | Refinement |
| Requirements | `requirements/REQ-NNN.yml` | YES | EVOLVING | Discovery |
| Specs | `specs/SPEC-NNN.yml` | YES | EVOLVING | Refinement |
| Tasks | `planning/tasks/TASK-NNN.yml` | YES | EVOLVING | Implementing |
| Decisions | `planning/decisions/` | YES | EVOLVING | Refinement |
| UI inventories | `planning/ui-inventory/<PageName>.yaml` | YES | EVOLVING | Discovery |
| Verification scenarios | `planning/scenarios/<SCN-ID>.yaml` | YES | EVOLVING | Refinement |
| Parity reports | `planning/parity/<PageName>_parity.yaml` | YES | EVOLVING | Verifying |
| Promoted screenshots | `planning/evidence/screenshots/` | YES | IMMUTABLE | Verifying |
| Evidence manifests | `planning/evidence/manifests/` | YES | EVOLVING | Verifying |
| Execution waves | `planning/execution-waves.md` | YES | EVOLVING | Planning |
| Migration state | `.mxagile/migration/state.yaml` | YES | EVOLVING | Migration |
| Lifecycle/wave state (canonical) | `planning/lifecycle/process-state.yaml` | YES | EVOLVING | All phases |
| Local session state cache | `.concord/scratch/process-state.yaml` | NO | Ephemeral | All phases |
| Temp screenshots | `.concord/screenshots/` | NO | Ephemeral | Verifying |
| Agent scratch | `.concord/scratch/` | NO | Ephemeral | All phases |
| Platform projections | `.claude/`, `.github/`, `.agents/` etc. | YES (GENERATED) | Reproducible | Generator |
| Secrets | `.env.mendix` | NEVER | Local | All phases |

### Provenance Maintenance

Every evolving artifact must record how and why it changed:
- Requirements/Specs/Tasks: revision history via Git + `updated` field
- Decisions: `planning/decisions/` entry per significant decision
- Target mockups: `target_mockup_version` + `target_mockup_reason` in UI inventory
- Parity reports: `verified_at` + `evidence_upgrade.reconstructed_dimensions`
- Evidence manifests: `promoted_at` per artifact

---

## Decisions

Architectural, UI, and implementation decisions must be recorded in `planning/decisions/`.

Each decision file: `planning/decisions/DEC-NNN.md` or `planning/decisions/DEC-NNN.yaml`.

Minimum content:
- Date
- Context (what was being decided)
- Decision made
- Rationale
- Alternatives considered
- Affected artifacts

Do NOT use `sprints/decisions.md` as the canonical location for new decisions in MxAgile
projects. The canonical location is `planning/decisions/`.

---

## GitIgnore Contract

### Must NOT Be Ignored (Project Knowledge)

The `.gitignore` MUST NOT accidentally exclude:
- `planning/` and all its subdirectories
- `requirements/`, `specs/`
- `input-resources/` (source mockups, requirement docs)
- `planning/evidence/screenshots/` (promoted canonical evidence)
- `planning/parity/` (parity reports)
- `planning/scenarios/` (verification scenarios)
- `planning/evidence/manifests/` (evidence manifests)

### Must Be Ignored (Ephemeral / Secret)

The `.gitignore` MUST exclude:
- `.concord/` — all ephemeral runtime scratch, temporary screenshots, process-state
- `.env.mendix` — project credentials
- `.env*` — environment secrets
- `mxcli.exe`, `.mxcli/` — binary tools
- `deployment/`, `packages/` — build output
- `.mendix-cache/` — Mendix local cache
- `.testing*/`, `tests/temp-project/` — test fixtures
- Browser tool caches and working directories (e.g., `.playwright/`, `.browserstate/`)

### Verification

The canonical `.gitignore` must be tested (see `tests/test-project-knowledge.ps1`) to confirm:
- `planning/lifecycle/process-state.yaml` is NOT ignored (canonical durable lifecycle state)
- `planning/evidence/screenshots/` is NOT ignored
- `planning/parity/` is NOT ignored
- `.concord/screenshots/` IS ignored
- `.concord/scratch/process-state.yaml` IS ignored (local session cache only)
- `.env.mendix` IS ignored

---

## Fresh Clone Collaboration Test

A fresh developer clone or fresh agent session must be able to reconstruct the current
accepted project state from the repository alone, WITHOUT access to:
- Previous developer's local tool cache
- Playwright temporary directory
- Agent scratch (`.concord/scratch/`)
- Terminal history
- Browser session
- Any untracked files

Except for:
- Intentionally local secret values (`.env.mendix`)
- Reproducible runtime/build dependencies (fetched by `mxagile-setup.ps1`)

### What Must Be Reconstructable

From a fresh clone, a developer/agent must be able to:
1. Find source mockups in `input-resources/ui-ux/`
2. Find the active acceptance target in `planning/target-mockups/`
3. Understand Requirements, Specs, Tasks from their canonical paths
4. Understand decisions from `planning/decisions/`
5. Understand the UI inventory from `planning/ui-inventory/`
6. Understand current parity state from `planning/parity/`
7. Trace a parity finding to its evidence via `planning/evidence/manifests/`
8. View promoted screenshots from `planning/evidence/screenshots/`

If any of these require access to `.concord/` or local temporary files, the project is
violating the collaboration contract.

### Non-Reconstructable (Correct)

From a fresh clone, the following are correctly NOT reconstructable:
- Current application runtime state (must start runtime)
- Secret credential values (must configure `.env.mendix`)
- Process-state.yaml (must re-sync lifecycle)
- Playwright browser cache

---

## Discovery and Refinement Output

Discovery produces durable artifacts that must be promoted:
- UI inventories in `planning/ui-inventory/`
- Verification scenarios in `planning/scenarios/`
- Parity findings in `planning/parity/`
- Promoted screenshots in `planning/evidence/screenshots/`

Discovery may use `.concord/scratch/` during analysis. Accepted findings must be promoted
to canonical locations before the session ends.

Refinement produces:
- Updated Requirements/Specs (`requirements/`, `specs/`)
- Decisions (`planning/decisions/`)
- Updated target mockups (`planning/target-mockups/`)
- Updated UI inventories (`planning/ui-inventory/`)

A Refinement conclusion that exists only in agent scratch is NOT accepted Refinement.

---

## Legacy Artifact Classification

Before moving, removing or replacing any legacy artifact, classify it:

| Classification | Meaning |
|---|---|
| `DURABLE_PROJECT_KNOWLEDGE` | Unique knowledge still needed — migrate to canonical location |
| `HISTORICAL_EVIDENCE` | Supports existing parity/Discovery/Refinement claim — preserve with traceability |
| `DUPLICATE` | Identical canonical copy exists — prove equivalence before removing |
| `OBSOLETE_GENERATED` | Old generated artifact — regenerate from current source, remove old |
| `TEMPORARY` | Ephemeral scratch or tool output — remove when no longer required |
| `SECRET_LOCAL` | Local credential file — do not migrate, preserve gitignored behavior |
| `UNKNOWN` | Unclear — preserve and classify before cleanup |

**Do NOT delete `UNKNOWN` artifacts automatically.**

Full classification and cleanup contract: `policies/reconciliation.md — Legacy Artifact Classification`

## Legacy Evidence Migration

Existing projects may have evidence in non-canonical locations from earlier framework versions:
- `input-resources/screenshots/` (legacy location)
- `.concord/screenshots/` (temporary, should have been promoted)
- `planning/wave-reports/` (wave reports may contain embedded evidence)

Migration:
1. Identify legacy evidence by location
2. Determine if it represents durable project knowledge
3. If durable: promote to canonical location with provenance record
4. If ephemeral or superseded: record as legacy with note
5. Do NOT silently delete historical evidence

---

## Multiple Project Structures

Projects accumulating artifacts from multiple framework generations must be rationalized:
1. Identify legacy locations using evidence-inventory during full reconciliation
2. Preserve provenance (where it came from, when)
3. Migrate/promote durable knowledge to canonical locations
4. Update references in Requirements/Specs/Tasks
5. Do NOT perpetuate parallel conventions after migration
