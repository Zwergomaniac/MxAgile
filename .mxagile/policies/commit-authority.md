# Commit Authority Policy

Governs when an AI agent may create a local git commit versus when it must propose
one for developer confirmation. Applies to all agents on all platforms.

This policy supplements but does not replace `policies/safety-rules.md`.
All universal safety rules apply at all times.

## Three Operation Types

### LOCAL_CHECKPOINT_COMMIT
- Creates a new commit in the local working tree only
- Records a coherent intermediate repository state
- Reversible through normal subsequent commits or `git revert`
- No effect on remote repositories
- Permitted under bounded autonomous delegation when all preconditions pass

### PUSH
- Transmits local commits to a remote repository
- Changes shared/remote repository state
- Cannot be recalled once accepted by the remote
- **ALWAYS requires explicit user authorization** — never inferred from commit authority

### DESTRUCTIVE_HISTORY_OPERATION
- `git reset --hard`
- `git rebase` of shared history
- `git commit --amend` of published commits
- `git push --force` / `git push --force-with-lease`
- `git clean -f`
- Any history rewriting that removes or replaces existing commits
- **ALWAYS prohibited** unless explicitly requested by the user in the same turn

Push authority is never implied by commit authority.
Destructive operation authority is never implied by commit or push authority.

---

## Authority Levels

### INTERACTIVE_COMMIT_APPROVAL

**Use when:**
- The user has not delegated autonomous checkpoint commit authority
- The repository or project rules explicitly require human review before commit
- The proposed commit includes changes outside the authorized scope
- The staged diff cannot be confidently bounded to the current mission
- Risk cannot be deterministically assessed

**Behavior:**
1. Prepare the commit message and staged diff description
2. Present as a commit proposal to the developer
3. Continue unrelated safe read/analysis/preparation work while awaiting confirmation
4. Stop only mutations that depend on the uncommitted checkpoint

### AUTONOMOUS_CHECKPOINT_COMMITS

**Use when ALL of the following hold:**
- The user has explicitly delegated autonomous execution for the current mission
- The mission or prompt authorizes cohesive commits, checkpoints, or autonomous progression
- The repository is on an appropriate working branch
- The staged diff is bounded to the authorized mission scope
- No unrelated user changes are included
- All required preconditions in this policy pass
- No push follows
- No destructive history operation is performed

**Behavior:**
1. Validate all preconditions (see Autonomous Commit Preconditions below)
2. Create the local checkpoint commit
3. Record the commit hash in the mission state
4. Continue to the next deterministic action without waiting for confirmation
5. Include all commit hashes in the final mission report
6. Do NOT produce a final mission report merely because a commit was created

### COMMIT_BLOCKED

**Use when ANY of the following hold:**
- Staged content contains unrelated or unknown changes that cannot be excluded
- Required validation for the current checkpoint fails without explicit WIP baseline classification
- Branch protection or repository policy prohibits local commits
- Secrets or sensitive data are detected in staged content
- Commit signing or another mandatory repository control cannot be satisfied
- Repository state is internally inconsistent (e.g., unresolved merge conflict markers)
- A higher-priority safety/compliance/repository rule explicitly prohibits the commit

**Behavior:**
1. Do NOT create the commit
2. Report the specific blocker clearly
3. Continue safe unblocked work where possible
4. Do not bundle the blocked changes with unrelated safe changes

---

## Precedence Rules

The following sources are ordered from highest to lowest priority:

1. **Mandatory repository controls** — branch protection, signing enforcement,
   compliance/legal requirements. These cannot be overridden by any user delegation.

2. **Organizational security rules** — `policies/safety-rules.md` destructive-operation
   and secrets prohibitions. These cannot be overridden.

3. **Project AGENT.md / CLAUDE.md / AGENTS.md commit instructions** — project-specific
   confirmation requirements. These apply by default.

4. **Explicit current user mission delegation** — when the user explicitly authorizes
   autonomous local checkpoint commits for the active mission, this overrides
   project-level default "confirm before commit" instructions, subject to rules 1–2.

5. **Agent defaults** — INTERACTIVE_COMMIT_APPROVAL in the absence of higher guidance.

**Key principle:** A project instruction may require confirmation by default.
An explicit current user mission may authorize bounded local checkpoint commits
unless a higher-priority security, compliance, or repository rule prohibits them.

The agent MUST NOT ignore explicit autonomous checkpoint authority merely because
a generic project template contains a "confirm before commit" instruction.

However, user delegation CANNOT override:
- Mandatory branch protection
- Secret/credential protection
- Signing enforcement
- Destructive-operation restrictions

---

## User Prompt Interpretation

The following phrases count as bounded autonomous checkpoint authority when no higher
rule prohibits it:

- "work autonomously"
- "use cohesive commits" / "use checkpoints"
- "do not stop for deterministic steps"
- "continue until scope is complete"
- "no need for confirmation before commits"
- "do not push"
- "autonomous mission" / "autonomous execution" / "autonomous delivery"

The framework does NOT require one exact magic sentence. Context and intent matter.

The following do NOT imply commit authority:
- "take a look"
- "investigate"
- "analyze"
- "check" / "review"
- Any request that does not explicitly delegate execution authority

---

## Autonomous Commit Preconditions

Before every autonomous checkpoint commit, all of the following must be verified:

1. **Branch identified** — current branch name is known and is a working branch
2. **Working tree classified** — `git status` has been read; all changes are
   identified as belonging to the authorized mission scope
3. **Authorized scope confirmed** — staged changes correspond to a coherent
   completed phase of the current mission
4. **Unrelated user changes excluded** — any changes outside the authorized scope
   are unstaged and preserved; they must not be committed
5. **Generated/runtime/cache files excluded** — build outputs, compiled binaries,
   `.concord/scratch/` state, and other non-repository artifacts are not staged
6. **Secrets scan passes** — no credentials, tokens, passwords, PATs, or API keys
   in staged content; `.env.mendix`, `.mcp.json`, and similar files are not staged
7. **Required validation passes** — model/build/lint/tests required for this
   checkpoint have passed, or known failures are explicitly baseline-classified
   with a documented rationale
8. **Staged diff reviewed** — the agent has read the full staged diff and confirms
   it matches the intended checkpoint state
9. **Commit message accurate** — the message describes the completed work; it does
   not reference future plans, callers, or ephemeral task identifiers
10. **Lifecycle state consistent** — internal process-state is coherent with the
    claimed checkpoint; no open gates that this commit falsely implies are closed
11. **No push follows** — confirmed that no `git push` command will follow this commit

If any precondition fails:
- Do not include the failing changes in the commit
- Continue unrelated safe work where possible
- Report the specific precondition failure

---

## Commit Granularity

Checkpoint commits must be coherent and independently resumable.

**Suitable granularity:**
- Core update / reconciliation complete
- Lifecycle / architecture / Wave planning cluster
- One coherent implementation cluster
- One parity-repair cluster
- Verification and evidence cluster
- Final acceptance state

**Avoid:**
- One commit per trivial file change
- One giant commit mixing unrelated lifecycle phases
- Committing knowingly inconsistent partial transitions
- Ending an autonomous mission with all changes staged but uncommitted
  without a documented blocker

An interrupted autonomous session must leave either:
- A clean committed checkpoint at the last coherent boundary, OR
- Explicitly classified uncommitted work with machine-readable resume status
  in `process-state.yaml`

Staged-only state (changes staged but not committed) is NOT a valid terminal
state for an unattended autonomous mission without a documented blocker.

---

## Continue After Commit

A successful local checkpoint commit is NOT a user-interaction gate.

After committing, the agent MUST:
1. Record the commit hash
2. Perform a lifecycle re-sync if required by the mission state
3. Identify the next deterministic action
4. Continue the mission without waiting for user confirmation

The agent MUST NOT produce a final mission report merely because a commit was created.
Stop only when the mission's genuine stop conditions are reached.

---

## Project Instruction Generation

Project instruction templates (AGENT.md, CLAUDE.md, AGENTS.md, copilot-instructions.md)
MUST NOT contain an unconditional "ask before every git commit" rule that does not
acknowledge autonomous mission delegation.

Generated project instructions MUST use conditional wording such as:

```
## Git Commit Authority

Default: propose commits interactively and wait for developer confirmation.

When the current user mission explicitly delegates autonomous local checkpoint commits:
- Commit coherent validated changes without waiting for confirmation.
- Never push without separate explicit authorization.
- Never perform destructive history operations (reset --hard, rebase of shared
  history, amend of published commits, force push).
- List all commit hashes in the final mission report.
- See policies/commit-authority.md for the complete authority model.
```

Existing projects receive the corrected wording through normal Core update /
projection regeneration, without overwriting unrelated project instructions.

---

## Integration with Operating Mode Detection

`CLOSED_AUTONOM` (Studio Pro closed, full filesystem access) permits bounded local
checkpoint commits when the current mission delegates them. This mode MUST NOT
be used as a reason to block local commits that fall within bounded mission scope.

`STUDIO_PRO_ACTIVE_CURRENT_PROJECT` may restrict model-level mutations but MUST NOT
block commits of safe planning, documentation, or lifecycle work.

`AMBIGUOUS_STUDIO_PRO_STATE` MUST block only conflict-prone model mutations,
not all repository checkpointing.

These operating modes must not create contradictory autonomy models that prevent
safe local checkpoint commits within bounded mission scope.
