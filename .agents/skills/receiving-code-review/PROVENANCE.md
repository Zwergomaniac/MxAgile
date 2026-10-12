# Receiving Code Review — Provenance Record

| Field | Value |
|-------|-------|
| upstream_repository | https://github.com/obra/superpowers |
| upstream_path | skills/receiving-code-review/SKILL.md |
| pinned_commit | bb92a77741419a4ab5f06e711a283343f1ada0c3 |
| license | MIT |
| import_date | 2026-10-12 |
| content_status | locally_adapted |

## Adaptations Summary

"your human partner" references replaced with "the user". Removed the GitHub Thread
Replies section (no GitHub API tool usage pattern required here). Condensed some
example blocks for brevity while preserving all behavioral rules. No MxAgile-specific
override required — the skill's emphasis on technical verification and YAGNI are fully
compatible with MxAgile's scope and evidence semantics.

## Update Procedure

1. `git ls-remote https://github.com/obra/superpowers.git HEAD` to check SHA.
2. If changed: `curl -s https://raw.githubusercontent.com/obra/superpowers/main/skills/receiving-code-review/SKILL.md`
3. Review diff; update content, preserve local adaptations noted above.
4. Update `pinned_commit` and `import_date` in this file.
5. Update `.claude/skills/receiving-code-review/SKILL.md` (Claude adapter) to match.
6. Commit: `chore(agent): update receiving-code-review to <new-sha>`

## Rollback Procedure

```powershell
git rm -r .agents/skills/receiving-code-review/ .claude/skills/receiving-code-review/
# Remove "receiving-code-review" line from External Skills table in CLAUDE.md
git commit -m "chore(agent): remove receiving-code-review skill"
```
