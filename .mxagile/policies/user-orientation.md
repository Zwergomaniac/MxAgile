# User Orientation Policy

## PURPOSE

Provide lightweight, non-blocking orientation to users who are:
- New to an MxAgile-enabled project (fresh initialization);
- Working in a project just adopted from an existing codebase; or
- Explicitly asking how MxAgile works.

Orientation communicates:
1. What MxAgile does in this project.
2. The basic lifecycle.
3. The important concepts/keywords.
4. That the user can simply describe the desired outcome.
5. That MxAgile re-synchronizes existing project state and routes work through the appropriate process.

Orientation is NEVER a gate. It does not block lifecycle progress, require confirmation,
or create any lifecycle state.

**Architectural owner:** `orchestrator.md` detects orientation intent and routes here.
This policy is not a separate lifecycle phase, not an agent, and not a tutorial system.

---

## TRIGGERS

### A. PROJECT_INITIALIZED

**Detection:** `.mxagile/` directory exists AND `planning/lifecycle/process-state.yaml` is absent
AND `.concord/scratch/process-state.yaml` is absent.

Emit after Startup Re-Sync confirms no prior lifecycle state exists. Then immediately continue
to the user's actual request (if any). Do NOT wait for confirmation.

### B. PROJECT_ADOPTED

**Detection:** `.mxagile/migration/state.yaml` exists with `status: complete` AND
`planning/lifecycle/process-state.yaml` is absent AND `.concord/scratch/process-state.yaml`
is absent.

Emit after Startup Re-Sync confirms migration complete but no lifecycle work started yet.
Then immediately continue to the user's actual request (if any). Do NOT wait for confirmation.

Adoption does NOT invalidate existing project evidence. State this clearly.

### C. EXPLICIT_HELP

**Detection:** User intent matches the concept of "how does this work" or "help with MxAgile".
Canonical intent patterns include:
- "how does MxAgile work"
- "what can I do with MxAgile"
- "how do I use MxAgile"
- "how should I continue"
- "what is MxAgile"
- "mxagile help"
- "help" (in an MxAgile project context without specific task context)

Use semantic intent recognition. Do not require exact string matching.

Explicit help may be slightly richer than automatic orientation. Provide current project
state when available from canonical sources.

---

## CONTENT BUDGET

Automatic orientation (PROJECT_INITIALIZED / PROJECT_ADOPTED):
- Approximately 5–10 concise content lines.
- One paragraph maximum per topic.
- Do NOT enumerate all agents, skills, policies, or internal routing tables.

Explicit help:
- Compact lifecycle map (one line per concept).
- Current project state (when canonically available from process-state.yaml).
- 2–4 contextually relevant next-action examples.

The invariant: **SHORT AND ACTIONABLE.**

---

## CORE VOCABULARY

Expose only this vocabulary. Do not introduce aliases where canonical terms already exist.

| Term | Meaning |
|------|---------|
| **System Check** | Verify the project and framework installation are technically healthy |
| **Re-Sync** | Determine the actual current repository and lifecycle state |
| **Discovery** | Determine what should be built or changed |
| **Refinement** | Make requirements, business rules, and decisions precise enough to implement |
| **Implementation** | Build confirmed, refined scope |
| **Verification / Acceptance** | Prove the result satisfies expectations technically and functionally |
| **Decision Required** | A genuine business or product decision is missing — work cannot proceed without it |

---

## OUTPUT TEMPLATES

### PROJECT_INITIALIZED

> **MxAgile is configured for this project.**
>
> Just describe what you want to achieve — MxAgile determines the current project state
> and routes the work through the appropriate process.
>
> **Typical flow:** Discovery → Refinement → Implementation → Verification → Acceptance
>
> **Useful starting points:**
> - *System Check* — verify project and framework health
> - *Re-Sync* — determine actual project state after any interruption
> - *Decision Required* — signals when a real business decision is missing
>
> For existing work, MxAgile first re-synchronizes project state and then continues
> through the appropriate phase.

### PROJECT_ADOPTED

> **MxAgile is now integrated into this existing project.**
>
> Existing requirements, decisions, and evidence remain relevant and are preserved.
> Adoption does not invalidate existing project knowledge.
> Project state is re-synchronized before new work continues.
>
> **Typical flow:** Discovery → Refinement → Implementation → Verification → Acceptance
>
> Describe what you want to achieve — MxAgile routes the work based on actual repository state.

### EXPLICIT_HELP

> **MxAgile — Quick Reference**
>
> | What you need | MxAgile concept |
> |---|---|
> | Is the installation healthy? | **System Check** |
> | What is the current project state? | **Re-Sync** |
> | New idea / change / new input | **Discovery** |
> | Requirements need to be clearer | **Refinement** |
> | Confirmed scope to build | **Implementation** |
> | Prove the result works | **Verification / Acceptance** |
> | Real business uncertainty blocks progress | **Decision Required** |
>
> **You do not need to select an agent or skill.** Simply describe what you want to achieve —
> MxAgile determines the current state and routes the work.
>
> [CURRENT_STATE — render only when canonical state is available from process-state.yaml:]
> ---
> **Current project position:** [wave / phase from planning/lifecycle/process-state.yaml]
> **Suggested next actions:** [2–4 contextually derived actions from current state]

---

## CONTEXTUAL STATE RULE

When emitting EXPLICIT_HELP and canonical lifecycle state is available
(`planning/lifecycle/process-state.yaml` or `.concord/scratch/process-state.yaml`), read it
and report current phase/wave. Report only fields actually present in the canonical record.

Do NOT reconstruct speculative state. If canonical state is absent or incomplete, say so
concisely: *"No lifecycle state found — ready to begin Discovery."*

Do not invent current state for presentation purposes.

---

## NO-GATE RULE

Orientation MUST NOT:
- Block lifecycle progress.
- Require user confirmation before proceeding.
- Mark any lifecycle gate PASS or FAIL.
- Create or modify `planning/lifecycle/process-state.yaml`.
- Create or modify `.concord/scratch/process-state.yaml`.
- Create any DECISION_REQUIRED record.
- Prevent execution of the user's original request.

Orientation is always:
    brief orientation → re-sync if required → continue original intent

Never:
    orientation → WAIT FOR CONFIRMATION

---

## NO-TRACKING RULE (P0)

Orientation MUST NOT write or read any of:
- `last_seen_user`, `last_orientation_user`, `onboarding_completed_by`
- `last_visit`, `inactive_since`, any per-user timestamp
- Any session-history or onboarding-state file

Triggers are based purely on canonical repository/lifecycle state, never on personal or
session-history tracking.

---

## CONTINUE-ORIGINAL-INTENT RULE

If the user's message contains a real work request in addition to orientation intent, the agent:
1. Emits brief orientation.
2. Runs Startup Re-Sync if required.
3. Continues the original work request without stopping.

Example: "How does MxAgile work, then continue my current task."
→ Brief orientation → Re-Sync → continue the task. No stop, no confirmation gate.

---

## FUTURE SCOPE — NOT IMPLEMENTED IN P0

The following capabilities are explicitly deferred. No P0 infrastructure change is needed to
support them later.

**Returning User Orientation (P1 — future scope):**
- Orientation triggered by meaningful inactivity (e.g., N days since last session).
- "What changed since last time?" based on Core revision or lifecycle delta.
- Phase-specific re-orientation after a long pause.
- Framework-change orientation (new MxAgile Core version installed).

None of these require any P0 infrastructure. P0 leaves no coupling to these deferred features.
