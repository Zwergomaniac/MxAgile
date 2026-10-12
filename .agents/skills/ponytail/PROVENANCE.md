# Ponytail — Provenance Record

| Field | Value |
|-------|-------|
| upstream_repository | https://github.com/DietrichGebert/ponytail |
| upstream_path | skills/ponytail/SKILL.md |
| pinned_commit | 9b58c1ffb790c075ca32e70a89cf1d80588f4abf |
| license | MIT |
| import_date | 2026-10-12 |
| content_status | locally_adapted |

## Adaptations Summary

Added "MxAgile: Smallest Complete Change Override" section at the end of SKILL.md.
The override defines what "complete" means in the MxAgile context and clarifies that
Ponytail's laziness principle does not permit skipping framework obligations.
The upstream content is otherwise unchanged.

## Update Procedure

1. `git ls-remote https://github.com/DietrichGebert/ponytail.git HEAD` to check SHA.
2. If changed: `curl -s https://raw.githubusercontent.com/DietrichGebert/ponytail/<new-sha>/skills/ponytail/SKILL.md`
3. Compare with current content above the MxAgile override section.
4. Review the diff; update the upstream section if changes are compatible.
5. Update `pinned_commit` and `import_date` in this file.
6. Update `.claude/skills/ponytail/SKILL.md` (Claude adapter) to match.
7. Commit: `chore(agent): update ponytail to <new-sha>`

## Rollback Procedure

```powershell
git rm -r .agents/skills/ponytail/ .claude/skills/ponytail/
# Remove "ponytail" line from External Skills table in CLAUDE.md
git commit -m "chore(agent): remove ponytail skill"
```
