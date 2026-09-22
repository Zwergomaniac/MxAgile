# Migration Policy: DFC-AI → MxAgile

This policy governs the safe, non-destructive migration of a project from the DFC-AI framework
to MxAgile. The migration agent is the sole consumer of this document.

---

## 1. Pre-Conditions

Before starting, verify:

- `.dfc-ai/version.yaml` exists (confirms DFC-AI installation)
- `.mxagile/lifecycle.yaml` does NOT exist (migration not yet complete)
- `.mxagile/migration/` exists (bootstrap was installed by `install-core.ps1`)
- A Mendix `.mpr` file exists in the project root

If any pre-condition fails, stop and report.

---

## 2. Phase 1 — Inventory (read-only)

Enumerate all artifacts. Never write during this phase.

### 2.1 DFC-AI Framework Artifacts (will be removed)

Identify all framework-owned artifacts:

| Marker | Path |
|---|---|
| Canonical source | `.dfc-ai/` (entire directory) |
| Generated platform agents | `.claude/agents/dfc-*.md` |
| Generated platform skills (Claude) | `.claude/skills/dfc-*/SKILL.md` |
| Generated platform skills (Copilot) | `.github/skills/dfc-*/SKILL.md` |
| Generated platform skills (Codex) | `.agents/skills/dfc/` |
| Generated platform skills (Grok) | `.grok/skills/dfc/` |
| Generated platform skills (Hermes) | `.hermes/skills/dfc/` |
| DFC-AI scripts | `scripts/generate-dfc-platform-skills.ps1`, `scripts/setup-agent-system.ps1`, `scripts/apply-project-agent-instructions.ps1`, `scripts/reconcile-derived-artifacts.ps1` |
| Legacy injection marker content | `AGENTS.md` block between `<!-- BEGIN PROJECT AGENT INSTRUCTIONS -->` and `<!-- END PROJECT AGENT INSTRUCTIONS -->` |
| Copilot injection marker content | `.github/copilot-instructions.md` (same OLD markers) |

### 2.2 Project Artifacts (must be preserved)

These carry real project knowledge and must survive migration unchanged:

| Category | Paths |
|---|---|
| Project knowledge | `projekt.md`, `input-resources/` |
| Requirements stories | `planning/stories/REQ-*.md` |
| Implementation checklists | `planning/checklists/W*-implementation-checklist.yaml` |
| Execution planning | `planning/execution-waves.md`, `planning/dependency-matrix.md`, `planning/traceability.md` |
| UI inventory | `planning/ui-inventory/*.yaml` |
| Wave reports | `planning/wave-reports/` |
| Architecture decisions | `sprints/decisions.md` |
| Handover state | `AGENT-HANDOVER.md` (current, if any) |
| Wave completion reports | `Abschlussbericht-*.md` |
| Concord memory | `.concord/project-memory.md`, `.concord/plans/` |
| Unresolved items | Any file containing `DECISION REQUIRED` or `TODO` |

### 2.3 Mendix Application (never touched)

These files are out of scope for migration entirely:

- `*.mpr` — the Mendix model file
- `mprcontents/`, `modules/`, `javasource/`, `javascriptsource/`
- `resources/`, `theme/`, `themesource/`, `theme-cache/`
- `userlib/`, `vendorlib/`, `widgets/`

### 2.4 AGENT.md — Inspect for Project Knowledge

Read `AGENT.md`. It contains two layers:

- **Framework layer**: `## Verbindlicher DFC-AI-Workflow` section and references to `.dfc-ai/`
  → Remove these on migration
- **Project layer**: coding conventions, module naming rules, project-specific workflow rules
  → Preserve in migrated `AGENT.md`

Extract and preserve the project-specific sections before migration.

---

## 3. Phase 2 — Migration Plan

After inventory, present a plan to the developer:

1. What will be preserved (list)
2. What will be removed (list of DFC framework artifacts)
3. What will be written (MxAgile bootstrap files, brownfield baseline)
4. What requires developer decisions (unresolved `DECISION REQUIRED` items)

**Wait for explicit developer confirmation before Phase 3.**

---

## 4. Phase 3 — Brownfield Baseline

Write the brownfield baseline BEFORE removing any DFC artifacts.

### 4.1 Write `.mxagile/state/brownfield-baseline.yaml`

```yaml
brownfield_baseline: true
origin: dfc-ai
baseline_date: <ISO 8601 date>
note: "Pre-existing Mendix implementation migrated from DFC-AI. No MxAgile lifecycle phases were performed historically."
prior_framework:
  name: dfc-ai
  version: <value from .dfc-ai/version.yaml, or "unknown">
preserved_artifacts:
  stories_count: <count of planning/stories/REQ-*.md>
  checklists_count: <count of planning/checklists/W*-implementation-checklist.yaml>
  decisions_present: <true/false>
  ui_inventory_present: <true/false>
  requirements_present: <true/false>
dfc_completed_waves: []  # list any wave names with complete checklists
```

### 4.2 Do NOT claim MxAgile phase history

Do not set `phase: verifying` or similar in `process-state.yaml` to imply work was done
under MxAgile. The brownfield baseline is the starting point.

---

## 5. Phase 4 — Migration Execution (requires confirmation)

Execute only after developer confirms the plan.

### 5.1 Migrate AGENT.md

1. Read `AGENT.md`
2. Extract project-specific sections (keep)
3. Remove the `## Verbindlicher DFC-AI-Workflow` block and all `.dfc-ai/` references
4. Overwrite `AGENT.md` with the cleaned project-only content

### 5.2 Clean injection markers from AGENTS.md and copilot-instructions.md

Both files use OLD markers:
```
<!-- BEGIN PROJECT AGENT INSTRUCTIONS --> ... <!-- END PROJECT AGENT INSTRUCTIONS -->
```

These will be replaced by the new MXAGILE:MANAGED markers during MxAgile setup.
For now: remove the old-marker blocks entirely from both files.

### 5.3 Remove DFC-AI framework artifacts

Remove (in order):

1. `.dfc-ai/` (entire directory)
2. `.claude/agents/dfc-*.md`
3. `.claude/skills/dfc-*/` (entire subdirectories)
4. `.github/skills/dfc-*/` (entire subdirectories)
5. `.agents/skills/dfc/` (entire directory)
6. `.grok/skills/dfc/` (entire directory)
7. `.hermes/skills/dfc/` (entire directory)
8. `scripts/generate-dfc-platform-skills.ps1`
9. `scripts/setup-agent-system.ps1`
10. `scripts/apply-project-agent-instructions.ps1`
11. `scripts/reconcile-derived-artifacts.ps1`

**Do not remove**:
- mxcli-owned skills in `.claude/skills/` that do NOT have the `dfc-` prefix
- `.ai-context/skills/` (mxcli-owned)
- `.concord/` (Concord workspace)
- Any project-specific scripts (e.g., `sync-epics-stories.ps1`, board scripts)
- `scripts/` directory itself

---

## 6. Phase 5 — MxAgile Installation

Run the MxAgile setup using the canonical installer:

```powershell
# From the project root (or equivalent mechanism):
& "<mxagile-dev-tree>/scripts/setup-agent-system.ps1" -ProjectRoot $ProjectRoot
```

This will:
- Generate MxAgile platform skills and agents
- Inject MxAgile managed blocks (MXAGILE:MANAGED markers) into AGENTS.md, CLAUDE.md, etc.
- Install the canonical `.mxagile/` payload (lifecycle.yaml, orchestrator.md, skills, policies)

The presence of `.mxagile/lifecycle.yaml` after this step signals migration complete.

---

## 7. Phase 6 — Validation

After setup completes, verify:

- [ ] `.mxagile/lifecycle.yaml` exists (MxAgile lifecycle installed)
- [ ] `.mxagile/state/brownfield-baseline.yaml` exists (baseline preserved)
- [ ] `planning/stories/` contents unchanged (project knowledge preserved)
- [ ] `sprints/decisions.md` unchanged
- [ ] `*.mpr` file unchanged (Mendix model untouched)
- [ ] No `.dfc-ai/` directory remains
- [ ] No `dfc-` prefixed files remain under `.claude/agents/` or `.claude/skills/`
- [ ] `<!-- BEGIN PROJECT AGENT INSTRUCTIONS -->` marker absent from all files
- [ ] `.claude/agents/mxagile-migration-agent.md` present (migration agent available for follow-up)
- [ ] AGENTS.md and CLAUDE.md have `<!-- MXAGILE:MANAGED:START -->` marker

Report any validation failures before declaring migration complete.

---

## 8. Migration Complete State

After successful validation:

- Inform the developer that migration is complete
- Confirm what was preserved
- Suggest running the MxAgile system check:

  ```
  Run the MxAgile system check and output the complete diagnostic report.
  ```

- The brownfield baseline in `.mxagile/state/brownfield-baseline.yaml` is the reference
  for what was pre-existing. Future MxAgile lifecycle phases will build on this baseline.

---

## 9. Safety Rules (non-negotiable)

These rules cannot be overridden by developer instruction:

- Never delete `*.mpr` files
- Never modify files under `mprcontents/`, `modules/`, `javasource/`, `javascriptsource/`
- Never delete `planning/stories/`, `sprints/decisions.md`, or `projekt.md`
- Never delete `.concord/project-memory.md`
- Always write brownfield baseline BEFORE removing DFC artifacts
- Always show the plan and wait for confirmation before Phase 4

---

## 10. Aborted Migration

If migration is aborted mid-way:

- The project may be in a partial state
- Report clearly what was completed and what was not
- Do not attempt to clean up automatically
- Inform the developer to review and potentially restore from version control
