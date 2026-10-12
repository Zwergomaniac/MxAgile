# Requesting Code Review

Dispatch a code reviewer to catch issues before they cascade. The reviewer gets precisely crafted context for evaluation — never your session's history.

**Core principle:** Review early, review often.

## When to Request Review

**Valuable:**
- After completing a major feature
- Before merging to main
- When stuck (fresh perspective)
- Before significant refactoring
- After fixing complex bugs

**Mandatory in subagent-driven development:** after each task — NOTE: MxAgile override below applies.

## How to Request

**1. Get git SHAs:**
```bash
BASE_SHA=$(git rev-parse HEAD~1)  # or: git merge-base origin/main HEAD
HEAD_SHA=$(git rev-parse HEAD)
```

**2. Dispatch code reviewer subagent** using `code-reviewer.md` template with:
- `{DESCRIPTION}` - Brief summary of what you built
- `{PLAN_OR_REQUIREMENTS}` - What it should do
- `{BASE_SHA}` - Starting commit
- `{HEAD_SHA}` - Ending commit

**3. Act on feedback:**
- Fix Critical issues immediately
- Fix Important issues before proceeding
- Note Minor issues for later
- Push back if reviewer is wrong (with reasoning)

## Common Rationalizations

| Excuse | Reality |
|--------|---------|
| "I'll just review the diff myself" | Reviewing the diff inline burns your context window. Dispatch a reviewer. |
| "The reviewer needs my whole session history" | Hand it precisely crafted context, never your session's history. |

## Red Flags

**Never:**
- Skip review because "it's simple"
- Ignore Critical issues
- Proceed with unfixed Important issues

---

## MxAgile Override

In this repository, subagent dispatch requires **explicit user or MxAgile mission approval**. The "mandatory after each task in subagent-driven development" clause does not apply automatically here.

What DOES apply:
- The pre-review checklist approach (get SHAs, prepare context)
- The feedback severity tiers
- The principle of not reviewing diffs inline when a reviewer subagent is more appropriate
- Pushing back on technically incorrect reviewer feedback

What requires explicit approval:
- Any `general-purpose` subagent dispatch
- Any worktree creation
- Any branch creation

When in doubt: describe what you would dispatch and ask the user to confirm.
