# Diagnosing Agent Sessions — Provenance Record

| Field | Value |
|-------|-------|
| upstream_repository | https://github.com/obra/superpowers |
| upstream_path | skills/diagnosing-superpowers/SKILL.md |
| upstream_skill_name | diagnosing-superpowers |
| pinned_commit | bb92a77741419a4ab5f06e711a283343f1ada0c3 |
| license | MIT |
| import_date | 2026-10-12 |
| content_status | substantially_adapted |

## Upstream-to-Local Name Mapping

`diagnosing-superpowers` → `diagnosing-agent-session`

The upstream skill name encodes the Superpowers product. The local name encodes the
general capability (diagnosing agent sessions) without product dependency.

## Adaptations Summary

The upstream skill is deeply integrated with the Superpowers infrastructure:
- `~/.superpowers/diagnosing-superpowers/<session-id>/` workspace directory
- `templates/case.md`, `templates/report.md`, `templates/bundle-README.md`
- `prompts/analyst-common.md` and dimension-specific prompt files
- `prompts/scrub.md`, `prompts/scrub-audit.md` for bundle creation
- `references/session-discovery.md`, `references/context-safety.md`, `references/github-issues.md`
- 7-step parallel analyst subagent dispatch

None of this infrastructure exists in this repository.

The adapted skill preserves:
- The intake-before-analysis hard rule (do not analyze until problem is scoped)
- The structured 4-step workflow (intake → locate → triage → report)
- The citation requirement (every finding cites path:line)
- The read-only hard rule
- The red flags table
- The quick reference complaint-to-focus mapping

Removed:
- Superpowers workspace directory creation
- Parallel analyst subagent dispatch
- Bundle creation and scrubbing workflow
- GitHub issue filing workflow
- "Similar sessions" sweep step

These capabilities remain available if Superpowers is separately installed.

## Update Procedure

1. `git ls-remote https://github.com/obra/superpowers.git HEAD` to check SHA.
2. If changed: `curl -s https://raw.githubusercontent.com/obra/superpowers/main/skills/diagnosing-superpowers/SKILL.md`
3. Review diff for changes to hard rules, intake rules, or triage approach.
4. Apply compatible changes to the adapted SKILL.md.
5. Update `pinned_commit` and `import_date` in this file.
6. Update `.claude/skills/diagnosing-agent-session/SKILL.md` (Claude adapter) to match.
7. Commit: `chore(agent): update diagnosing-agent-session to superpowers <new-sha>`

## Rollback Procedure

```powershell
git rm -r .agents/skills/diagnosing-agent-session/ .claude/skills/diagnosing-agent-session/
# Remove "diagnosing-agent-session" line from External Skills table in CLAUDE.md
git commit -m "chore(agent): remove diagnosing-agent-session skill"
```
