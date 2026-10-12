# Requesting Code Review — Provenance Record

| Field | Value |
|-------|-------|
| upstream_repository | https://github.com/obra/superpowers |
| upstream_path | skills/requesting-code-review/SKILL.md |
| pinned_commit | bb92a77741419a4ab5f06e711a283343f1ada0c3 |
| license | MIT |
| import_date | 2026-10-12 |
| content_status | locally_adapted |

## Adaptations Summary

The upstream skill assumes a Superpowers subagent-driven development environment where
dispatching reviewer subagents is automatic and mandatory after each task. Added
"MxAgile Override" section that restricts automatic subagent dispatch: in this repository,
dispatch requires explicit user or MxAgile mission approval.

"your human partner" references replaced with "the user".
Reference to `code-reviewer.md` template retained as conceptual guidance (template file
not present in this repository; agent must construct context manually or obtain it separately).

## Update Procedure

1. `git ls-remote https://github.com/obra/superpowers.git HEAD` to check SHA.
2. If changed: `curl -s https://raw.githubusercontent.com/obra/superpowers/main/skills/requesting-code-review/SKILL.md`
3. Review diff; update upstream content section, preserve MxAgile override.
4. Update `pinned_commit` and `import_date` in this file.
5. Update `.claude/skills/requesting-code-review/SKILL.md` (Claude adapter) to match.
6. Commit: `chore(agent): update requesting-code-review to <new-sha>`

## Rollback Procedure

```powershell
git rm -r .agents/skills/requesting-code-review/ .claude/skills/requesting-code-review/
# Remove "requesting-code-review" line from External Skills table in CLAUDE.md
git commit -m "chore(agent): remove requesting-code-review skill"
```
