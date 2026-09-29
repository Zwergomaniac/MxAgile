# MxAgile Artifact Canonicalization Skill

This skill provides the structured process to convert legacy DFC-AI/hybrid project
artifacts into canonical MxAgile format after framework migration is complete.

## When to use

After `artifact_canonicalization: pending` in `.mxagile/migration/state.yaml`.
Framework migration (`mxagile_installed` step) must already be complete.

## Artifact contract

Canonical MxAgile artifacts live at:

| Artifact  | Canonical location            | Schema                                    |
|-----------|-------------------------------|-------------------------------------------|
| Requirement | `requirements/REQ-NNN.yml`  | `.mxagile/schemas/requirement.schema.json` |
| Spec        | `specs/SPEC-NNN.yml`        | `.mxagile/schemas/spec.schema.json`        |
| Task        | `planning/tasks/TASK-NNN.yml` | `.mxagile/schemas/task.schema.json`      |

Legacy sources (preserved until retired):

| Legacy artifact          | Canonical target                |
|--------------------------|---------------------------------|
| `planning/stories/REQ-*.md` | `requirements/REQ-NNN.yml`   |
| `planning/checklists/*.yaml` | `planning/tasks/TASK-NNN.yml` |

**Source files are never deleted without explicit confirmation.**

## Canonicalization process

### 1. Pre-flight check

Verify framework migration is complete:
```
.mxagile/lifecycle.yaml must exist
.mxagile/migration/state.yaml must have status: complete OR mxagile_installed step done
```

Read current `artifact_canonicalization` value from `state.yaml`:
- `pending`: proceed
- `in_progress`: resume from last state in `canonicalization-state.yaml`
- `complete`: report that canonicalization is already done

### 2. Inventory

List all legacy artifacts:
```
planning/stories/REQ-*.md         -> target: requirements/REQ-NNN.yml
planning/checklists/*.yaml        -> target: planning/tasks/TASK-NNN.yml
```

Identify any existing canonical artifacts in `requirements/` and `planning/tasks/`
to avoid overwriting already-converted files.

### 3. Dry-run preview

```powershell
.\scripts\migrate-stories.ps1 -ProjectRoot <path> -DryRun
```

Review the proposed conversion. Flag any files where:
- ID cannot be determined from frontmatter or filename
- Title or description would be empty
- Spec assignment for tasks is ambiguous

Present the plan to the developer. Get approval for any ambiguous items before proceeding.

### 4. Conversion

```powershell
.\scripts\migrate-stories.ps1 -ProjectRoot <path> [-Phase requirements|tasks|all]
```

The script calls `scripts/canonicalize_artifacts.py` which:
- Parses YAML frontmatter from `.md` files
- Extracts sections: title, description, target_users, acceptance_criteria, business_rules, open_items
- Writes `requirements/REQ-NNN.yml` conformant to the requirement schema
- Maps checklist items to `planning/tasks/TASK-NNN.yml`
- Persists progress to `canonicalization-state.yaml` (resumable)

### 5. Post-conversion validation

The script automatically validates output after conversion:
```powershell
.\scripts\migrate-stories.ps1 -ProjectRoot <path> -ValidateOnly
```

Validation checks:
- All `requirements/*.yml` files parse as valid YAML
- All have `ID:` field matching `REQ-NNN` pattern
- `ID:` matches filename stem
- All `planning/tasks/*.yml` have `ID:`, `spec:`, `action:` fields

### 6. Artifact index rebuild

After validation:
```python
python scripts/build_artifact_index.py <project-root>
```

Verify the index contains the expected nodes and edges.

### 7. State update

The script automatically updates `artifact_canonicalization: complete` in `state.yaml`
when all artifacts validate successfully.

Verify manually:
```
cat .mxagile/migration/state.yaml | grep artifact_canonicalization
```

### 8. Source retirement (optional, after developer confirmation)

```powershell
.\scripts\migrate-stories.ps1 -ProjectRoot <path> -RetireSource
```

Adds `archived: true` to frontmatter of source `.md` files.
Source files are NOT deleted. They remain as audit trail.

## Guidelines

### Manual decisions required

Present to the developer before proceeding if:
- A story has no `req_id` in frontmatter AND the filename cannot be parsed as `REQ-NNN`
- A checklist task cannot be assigned to a spec (leave `spec: "[SPEC-REQUIRED]"` with `open_items`)
- Content appears in an unknown section that cannot be mapped to a schema field

### Historical evidence preservation

Canonical artifacts include:
- `migrated_from: "planning/stories/REQ-001.md"` — provenance
- `migration_date: "2026-09-22"` — when converted
- `source: migrated` — provenance flag

This supports audit and semantic equivalence verification.

### Content loss guard

If a significant section of the source `.md` cannot be mapped to a schema field,
add it to `open_items` with prefix `PRESERVED: ...` so no content is silently discarded.

## Safety policy

- Source files under `planning/` are NEVER deleted without explicit user confirmation
- Conversion output is validated before `artifact_canonicalization` is set to `complete`
- If validation fails, state remains `in_progress` and errors are reported
- Canonicalization is resumable: re-running skips already-converted artifacts
