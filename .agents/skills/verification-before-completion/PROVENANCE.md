# Verification Before Completion — Provenance Record

| Field | Value |
|-------|-------|
| upstream_repository | https://github.com/obra/superpowers |
| upstream_path | skills/verification-before-completion/SKILL.md |
| pinned_commit | bb92a77741419a4ab5f06e711a283343f1ada0c3 |
| license | MIT |
| import_date | 2026-10-12 |
| content_status | locally_adapted |

## Adaptations Summary

Condensed some examples for brevity. The "Regression tests (TDD Red-Green)" example
retained in full. Agent delegation pattern retained. All Iron Law, gate function,
failure modes and rationalization prevention content is unchanged.
Removed "I'm tired" rationalization row (adequate coverage in other rows).
No MxAgile-specific override required — the skill is fully aligned with MxAgile's
evidence requirement and acceptance gate semantics.

## Update Procedure

1. `git ls-remote https://github.com/obra/superpowers.git HEAD` to check SHA.
2. If changed: `curl -s https://raw.githubusercontent.com/obra/superpowers/main/skills/verification-before-completion/SKILL.md`
3. Review diff for changes to the Iron Law, gate function or failure modes.
4. Update `pinned_commit` and `import_date` in this file.
5. Update `.claude/skills/verification-before-completion/SKILL.md` (Claude adapter) to match.
6. Commit: `chore(agent): update verification-before-completion to <new-sha>`

## Rollback Procedure

```powershell
git rm -r .agents/skills/verification-before-completion/ .claude/skills/verification-before-completion/
# Remove "verification-before-completion" line from External Skills table in CLAUDE.md
git commit -m "chore(agent): remove verification-before-completion skill"
```
