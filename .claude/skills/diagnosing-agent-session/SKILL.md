---
name: diagnosing-agent-session
description: >
  Structured diagnosis of failed, inefficient or confused agent sessions.
  Intake before analysis: scope the problem before reading anything. Every
  finding cites path:line — no citation, no finding. Use when a session went
  wrong (repeated work, ignored plans, stumbles, unexpected cost, skill that
  did not fire) or when building a bug report. Adapted from diagnosing-superpowers
  (obra/superpowers); see .agents/skills/diagnosing-agent-session/PROVENANCE.md.
---

# Diagnosing Agent Sessions

## Purpose

Pin down with the user what went wrong in an agent session: repeated work, ignored plans, poor results, excessive tokens, confused behavior. Read transcripts and report findings with evidence.

**Core principle:** Every finding cites `path:line`. No citation, no finding. Every number comes from the transcript or a command you ran — never from memory.

## Hard Rules

- **Read-only.** Never modify, move or delete a session file.
- **Intake before analysis.** Nothing in steps 2–4 starts until the problem is scoped.
- **No framework diagnosis.** Report evidence; let maintainers decide.
- **Context safety.** One transcript line can be large. Read targeted ranges, not full files indiscriminately.
- **Approval gates.** No issue or comment before the user approves the exact text.

## Workflow

### Step 1: Problem Intake

Ask one question at a time until you can write a statement naming:
- Which session(s)
- Turn range if known
- What was expected
- What happened
- The observable that matters (wall-clock, tokens, repeated actions, one specific action)

"It took too long" is a complaint, not a problem statement. Do not proceed to step 2 until scoped.

A request already scoped to one specific event or question is itself the statement — answer it, then ask.

### Step 2: Locate

Resolve each session to verified absolute filesystem paths. Confirm a past session by quoting its first prompt and timestamp. List every candidate you rejected with the reason.

Common Claude Code transcript locations:
- `~/.claude/projects/<project-hash>/` — project-scoped sessions
- Session files are JSON with timestamped turns

### Step 3: Triage

Read the region around the reported problem yourself. Focus on:

| Complaint | Focus first |
|-----------|-------------|
| "Took too long" | Token count per turn, stumbles, retry loops |
| "Extra work / repeated actions" | Plan loading, where divergence started |
| "Too expensive" | Token concentration, large context turns |
| "Ignored the plan" | Plan loading event, session compaction points |
| "Skill didn't fire" | Skill file presence, trigger conditions in transcript |

### Step 4: Report

Write findings with citations. Distinguish:
- **Confirmed** — cites specific `path:line` from transcript
- **Inferred** — pattern observed across multiple lines, no single citation
- **Unknown** — insufficient transcript access; state what is missing

Report format:
```
## Finding: [brief title]
Evidence: [path:line — quote]
Assessment: [what this shows]
Classification: Confirmed / Inferred / Unknown
```

## Red Flags

| Thought | Reality |
|---------|---------|
| "Problem is obvious, skip intake" | The problem statement scopes everything. Ask. |
| "I'll reconstruct what they meant" | You cannot reconstruct what they wanted. Write the questions and stop. |
| "I'll sweep everything now, ask later" | An unscoped sweep spends their budget on the wrong question. Ask first. |
| "The price per token is well known" | Numbers you did not compute from the transcript are invented. Cite or drop. |
