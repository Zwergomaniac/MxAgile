# Systematic Debugging — Provenance Record

| Field | Value |
|-------|-------|
| upstream_repository | https://github.com/obra/superpowers |
| upstream_path | skills/systematic-debugging/SKILL.md |
| pinned_commit | bb92a77741419a4ab5f06e711a283343f1ada0c3 |
| license | MIT |
| import_date | 2026-10-12 |
| content_status | locally_adapted |

## Adaptations Summary

The upstream skill references `root-cause-tracing.md`, `defense-in-depth.md`,
and `condition-based-waiting.md` as companion files within the Superpowers infrastructure.
References to these files have been removed or condensed since that infrastructure is not
present here. The four-phase structure, Iron Law, and all behavioral guidance are preserved.
"your human partner" references replaced with "the user".
Phase 4 step 1 reference to `superpowers:test-driven-development` removed (not present here).
Phase 4 step 3 reference to `superpowers:verification-before-completion` removed (use the
standalone `verification-before-completion` skill instead).

## Update Procedure

1. `git ls-remote https://github.com/obra/superpowers.git HEAD` to check SHA.
2. If changed: `curl -s https://raw.githubusercontent.com/obra/superpowers/main/skills/systematic-debugging/SKILL.md`
3. Compare with current content; preserve local adaptations noted above.
4. Update `pinned_commit` and `import_date` in this file.
5. Update `.claude/skills/systematic-debugging/SKILL.md` (Claude adapter) to match.
6. Commit: `chore(agent): update systematic-debugging to <new-sha>`

## Rollback Procedure

```powershell
git rm -r .agents/skills/systematic-debugging/ .claude/skills/systematic-debugging/
# Remove "systematic-debugging" line from External Skills table in CLAUDE.md
git commit -m "chore(agent): remove systematic-debugging skill"
```
