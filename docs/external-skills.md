# External Skills Integration

This document covers the Ponytail and Superpowers-derived skills added to the
MxAgile framework development repository.

## 1. Why These Skills Were Added

Gateway telemetry shows approximately 90% of token consumption comes from requests
with context lengths above 150k tokens. Before the planned context-lifecycle architecture
change, the goal of this integration is to make the Framework Agent more disciplined,
verification-oriented and resistant to unnecessary implementation complexity.

The following problems motivated the addition:

- Agents over-engineer solutions when simpler options exist (→ ponytail)
- Agents propose fixes without finding root cause (→ systematic-debugging)
- Agents claim completion without running verification (→ verification-before-completion)
- Agents implement code review feedback blindly without technical evaluation (→ receiving-code-review)
- Agents need a structured way to request review without burning coordinator context (→ requesting-code-review)
- Agents need a structured diagnostic approach when sessions go wrong (→ diagnosing-agent-session)

## 2. Which Skills Are Active

| Skill | Status | Trigger |
|-------|--------|---------|
| `ponytail` | Active | `/ponytail`, "be lazy", "simplest solution", "yagni" |
| `systematic-debugging` | Active | `/systematic-debugging` |
| `verification-before-completion` | Active | `/verification-before-completion` |
| `requesting-code-review` | Active | `/requesting-code-review` |
| `receiving-code-review` | Active | `/receiving-code-review` |
| `diagnosing-agent-session` | Active | `/diagnosing-agent-session` |

### Deliberately Inactive Superpowers Capabilities

The following upstream Superpowers capabilities were intentionally not integrated because
they would introduce a second orchestration authority or lifecycle:

| Capability | Reason Not Integrated |
|-----------|----------------------|
| Universal startup/bootstrap lifecycle | Would conflict with MxAgile session start |
| Automatic brainstorming before every task | Replaces MxAgile's discovery phase |
| Replacement planning lifecycle | MxAgile owns planning |
| Automatic subagent-driven development | MxAgile controls orchestration |
| Automatic worktree creation | MxAgile controls branching |
| Universal TDD for all Mendix/model changes | Not universally applicable; model changes need different approach |
| Independent branch-finishing lifecycle | MxAgile controls completion |
| Automatic parallelization | MxAgile controls orchestration |

## 3. Precedence Model

External skills are implementation aids. The precedence order is:

1. **Explicit current user instruction** — always highest priority
2. **MxAgile safety, lifecycle, scope and evidence contracts** — includes all policies in `.mxagile/policies/`, lifecycle gates in `.mxagile/lifecycle.yaml`, and the orchestration model in `.mxagile/orchestrator.md`
3. **Repository-specific rules** — CLAUDE.md
4. **External skills** — Ponytail, Superpowers-derived skills

If an external skill instruction conflicts with MxAgile policy, MxAgile policy wins.

## 4. MxAgile "Smallest Complete Change" Interpretation

Ponytail's core principle is "be lazy: smallest complete change." In this repository,
"complete" is specifically defined to always include:

- Scope and ownership correctness (framework / company-layer / consumer-project)
- Security
- Input validation and error handling at trust boundaries
- Migration safety (no breakage during in-place update)
- Update and rollback safety
- Evidence preservation (existing verified functionality not silently invalidated)
- Runtime verification where a lifecycle gate requires it
- Acceptance gates (not skipped to appear smaller)
- Documentation (CLAUDE.md, docs/, provenance records)
- Existing validated test coverage

This interpretation is documented in each ponytail SKILL.md under "MxAgile: Smallest Complete Change Override."

## 5. Supported Agent Harnesses and Discovery Paths

### Claude Code

Skills are discovered from `.claude/skills/<name>/SKILL.md`.

Confirmed discovered (visible in system-reminder after file creation):
- `ponytail`
- `systematic-debugging`
- `verification-before-completion`
- `requesting-code-review`
- `receiving-code-review`
- `diagnosing-agent-session`

### Other Harnesses (OpenCode, Grok, Hermes, Codex, Copilot)

Portable skill content lives in `.agents/skills/<name>/SKILL.md`.
These harnesses can load skills from `.agents/skills/` using their native skill-loading
mechanism. No adapter files for non-Claude harnesses have been created yet; add them
following the pattern in `.mxagile/adapters/<harness>/skills.yaml` when needed.

## 6. Upstream Revisions and Licenses

| Skill | Upstream Repository | Pinned Commit | License |
|-------|--------------------| --------------|---------|
| ponytail | https://github.com/DietrichGebert/ponytail | `9b58c1ffb790c075ca32e70a89cf1d80588f4abf` | MIT |
| systematic-debugging | https://github.com/obra/superpowers | `bb92a77741419a4ab5f06e711a283343f1ada0c3` | MIT |
| verification-before-completion | https://github.com/obra/superpowers | `bb92a77741419a4ab5f06e711a283343f1ada0c3` | MIT |
| requesting-code-review | https://github.com/obra/superpowers | `bb92a77741419a4ab5f06e711a283343f1ada0c3` | MIT |
| receiving-code-review | https://github.com/obra/superpowers | `bb92a77741419a4ab5f06e711a283343f1ada0c3` | MIT |
| diagnosing-agent-session | https://github.com/obra/superpowers (adapted) | `bb92a77741419a4ab5f06e711a283343f1ada0c3` | MIT |

Both upstream repositories are MIT-licensed. License terms are preserved by
attribution in each PROVENANCE.md file.

## 7. How Updates Are Reviewed and Applied

For each skill:

1. Check for upstream changes:
   - Ponytail: `git ls-remote https://github.com/DietrichGebert/ponytail.git HEAD`
   - Superpowers: `git ls-remote https://github.com/obra/superpowers.git HEAD`

2. If SHA changed, fetch new content:
   ```
   curl -s https://raw.githubusercontent.com/<repo>/main/skills/<name>/SKILL.md
   ```

3. Review the diff manually. Assess:
   - Does the change conflict with the MxAgile override sections?
   - Does it introduce new dependencies or infrastructure references?
   - Is the license still MIT?

4. Update the SKILL.md files and PROVENANCE.md (pinned_commit, import_date).
5. Commit with `chore(agent): update <skill-name> to <new-sha>`.

Do not run upstream installer scripts. Do not enable hooks from upstream repositories
without explicit review.

## 8. How to Disable or Remove Skills

### Remove a single skill

```powershell
git rm -r .agents/skills/<name>/ .claude/skills/<name>/
# Remove the skill's row from the External Skills table in CLAUDE.md
git commit -m "chore(agent): remove <name> skill"
```

### Remove all external skills

```powershell
git rm -r .agents/skills/ponytail/ .agents/skills/systematic-debugging/ `
         .agents/skills/verification-before-completion/ `
         .agents/skills/requesting-code-review/ `
         .agents/skills/receiving-code-review/ `
         .agents/skills/diagnosing-agent-session/ `
         .claude/skills/ponytail/ .claude/skills/systematic-debugging/ `
         .claude/skills/verification-before-completion/ `
         .claude/skills/requesting-code-review/ `
         .claude/skills/receiving-code-review/ `
         .claude/skills/diagnosing-agent-session/
# Remove "External Skills" section from CLAUDE.md
git commit -m "chore(agent): remove all external skills (Ponytail + Superpowers)"
```

## 9. Known Limitations

- **diagnosing-agent-session**: The upstream `diagnosing-superpowers` skill includes
  parallel analyst subagent dispatch, bundle creation, scrubbing and GitHub issue filing
  that depend on Superpowers infrastructure. These capabilities are not available in the
  adapted version. If full Superpowers session diagnostics are needed, install Superpowers
  separately.

- **requesting-code-review**: The upstream skill references a `code-reviewer.md` template
  that is part of Superpowers infrastructure. This template is not present in this
  repository. The agent must construct context manually or use the code-review skill
  available in the Claude Code harness.

- **Live discovery validation**: Discovery was confirmed for the Claude Code harness by
  observing the skills appear in the system-reminder after file creation. Live-agent
  invocation in other harnesses has not been tested. See validation report in this doc.

- **Other harnesses**: Only Claude Code adapters are provided. Other harnesses (OpenCode,
  Grok, Hermes, Codex, Copilot) need their own adapter files if required.

## 10. Relationship to Future Context-Lifecycle Implementation

The next mission will implement context epochs, durable resume and lifecycle
re-synchronization. This integration does not implement those features.

The external skills added here support the next mission by:
- Establishing verification discipline before the architecture change begins
- Providing systematic debugging capability for the complex migration work ahead
- Providing the pre-review and post-review behavioral protocols

The external skills must NOT be modified during the context-lifecycle mission.
If a conflict is discovered, address it in a separate commit.

## Overlap and Conflict Analysis

### MxAgile vs. Ponytail

| Aspect | Potential Conflict | Resolution |
|--------|--------------------|------------|
| "Smallest change" | Ponytail could be interpreted as "skip verification gates to be smaller" | MxAgile override section defines what "complete" means |
| Session scope | Ponytail is active "for the whole session" | MxAgile lifecycle phase takes precedence; ponytail cannot override a lifecycle gate |
| No conflict: "be lazy about the solution" | Aligns with MxAgile's avoid-over-engineering principle | — |

### MxAgile vs. Superpowers Skills

| Skill | Potential Conflict | Resolution |
|-------|--------------------|------------|
| requesting-code-review | "Mandatory after each task in subagent-driven development" | MxAgile override: explicit approval required for subagent dispatch |
| systematic-debugging | "Create failing test first" | Compatible; MxAgile's verification requirement is consistent |
| verification-before-completion | None | Fully aligned; reinforces MxAgile's acceptance gate semantics |
| receiving-code-review | None | Fully aligned; YAGNI principle consistent with MxAgile scope separation |
| diagnosing-agent-session | Superpowers infrastructure references | Resolved by adaptation: infrastructure-dependent steps removed |

### No conflicts found with:
- MxAgile lifecycle phases
- MxAgile evidence semantics
- Company-layer separation
- Framework vs. consumer-project scope

## Validation Report

### A. Discovery

**Result: CONFIRMED for Claude Code harness.**

Evidence: Skills `ponytail`, `systematic-debugging`, `verification-before-completion`,
`requesting-code-review`, `receiving-code-review`, `diagnosing-agent-session` appeared in
the Claude Code system-reminder immediately after `.claude/skills/<name>/SKILL.md` files
were created. The harness reads `.claude/skills/*/SKILL.md` and surfaces them as available
skills.

Discovery for other harnesses: NOT VERIFIED (no adapter files for other harnesses yet).

### B. Precedence

**Result: STRUCTURALLY VALIDATED via CLAUDE.md and skill content.**

- CLAUDE.md explicitly states the 4-level precedence (user > MxAgile > repo > external skills).
- Each skill's MxAgile override section documents what MxAgile contracts override.
- Ponytail's MxAgile override explicitly prohibits removing verification gates.
- requesting-code-review's MxAgile override restricts automatic subagent dispatch.
- No skill claims authority over MxAgile lifecycle, acceptance gates or evidence semantics.

Live agent execution test: NOT PERFORMED (would require agent invocation).

### C. Routing

**Result: STRUCTURALLY VALIDATED via skill descriptions.**

- Debugging work → systematic-debugging (description: "use when encountering any bug, test failure or unexpected behavior")
- Completion claims → verification-before-completion (description: "use before claiming tests pass, bugs are fixed...")
- Ordinary work → no external skill auto-loaded (skills are trigger-based)
- Session diagnosis → diagnosing-agent-session

Routing does not load all skills; each is trigger-based with specific conditions.

### D. Regression

**Result: SEE TESTS (tests/test-external-skills.ps1)**

The test covers: skill presence, provenance completeness, CLAUDE.md precedence content,
absence of global hooks, no gitmodules added.

MxAgile regression tests: NOT RE-RUN here (run `pwsh tests/run-fast-tests.ps1` separately).

### E. Repository Hygiene

Verified:
- No global changes (no ~/.claude/settings.json modifications)
- No hooks enabled from upstream repositories
- No .gitmodules added
- No unrelated dependency updates
- No Graphify changes
- No MxAgile runtime or consumer-project contract changes
- No AGENT.md created (out of scope for this mission)
