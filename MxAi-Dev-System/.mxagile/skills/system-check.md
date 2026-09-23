# MxAgile System Check

**SAFETY NOTICE — READ-ONLY OPERATION**

This skill is entirely READ-ONLY. You MUST NOT perform any of the following:
- Write, create, or delete any file
- Run any installation or initialization script
- Execute `mxcli` with state-changing arguments
- Perform any git commit, checkout, reset, merge, or push
- Modify AGENTS.md, CLAUDE.md, or any other project file

Permitted read-only operations: read files, list directories, run `mxcli --version`, run `git status` / `git log` / `git diff` (read-only only).

---

Run this check systematically in section order. After completing all sections, produce the full Markdown report described at the end. Run in a FRESH agent session started after installation for the most reliable results.

---

## A. Environment

1. Report the current working directory / repo root.
2. Search the project root for any `*.mpr` file. Report its path if found, or `NOT_FOUND` if absent.
3. Report which agent platform you believe you are running on (Claude Code, GitHub Copilot, OpenAI Codex, Grok, OpenCode, Hermes, or unknown). Mark the confidence as `high` or `low`.

---

## B. MxAgile Discovery

Check each of the following and report YES/NO for existence:

1. `.mxagile/` directory exists?
2. `.mxagile/version.yaml` — if present, read and report `version` field value.
3. `.mxagile/skills/` directory exists and contains at least one `*.md` file? List skill filenames.
4. `.mxagile/agents/` directory exists?
5. `.mxagile/layers/` directory exists?

---

## C. Instruction Discovery

For each file below:
- Check if it exists.
- Count every occurrence of `<!-- MXAGILE:MANAGED:START -->` (call this START_COUNT).
- Count every occurrence of `<!-- MXAGILE:MANAGED:END -->` (call this END_COUNT).
- Assess the managed block status:
  - `VALID` — START_COUNT == 1 AND END_COUNT == 1
  - `DUPLICATE` — START_COUNT > 1 OR END_COUNT > 1
  - `MISSING` — START_COUNT == 0 AND END_COUNT == 0
  - `MALFORMED` — counts mismatch (START != END, but neither is >1 in a duplicate scenario)
- Also check for OLD markers `<!-- BEGIN PROJECT AGENT INSTRUCTIONS -->` — report `OLD_MARKERS_FOUND: true/false`.

Files to check:
- `AGENT.md` — only check existence (no managed block expected)
- `AGENTS.md`
- `CLAUDE.md`
- `.github/copilot-instructions.md`

---

## D. Skill Discovery

1. List all directories under `.claude/skills/` that have the `mxagile-` prefix.
2. List all directories under `.github/skills/` that have the `mxagile-` prefix.
3. Check `.agents/skills/mxagile/` — list files if present. Note: old installs may use `dfc/` instead; if found, report as stale naming.
4. Check `.grok/skills/mxagile/` — list files if present (check `dfc/` as stale fallback).
5. For each discovered skill location: is `mxagile-system-check` present?
6. Report any expected standard skills that appear to be missing from discovered locations.

---

## E. Tooling

1. Check if `mxcli.exe` or `mxcli` exists in the project root. Report path if found.
2. Check if `update-mxcli.ps1` exists in the project root.
3. If `mxcli` is present: run `./mxcli --version` (or `mxcli.exe --version`) and report the exact output. If it fails, report `ERROR: <message>`.

---

## F. Project Structure

Check existence (YES/NO) of each:
- `specs/` directory
- `requirements/` directory
- `planning/tasks/` directory
- `.mxagile/state/` directory

Also check migration and canonicalization state:
- `.mxagile/migration/` directory exists?
- `.mxagile/migration/state.yaml` — if present, read and report the `status` and `artifact_canonicalization` fields verbatim.
  Classify the project lifecycle state:
  - `status: complete` + `artifact_canonicalization: pending` → **HYBRID** (migration complete, canonicalization pending)
  - `status: complete` + `artifact_canonicalization: complete` → **FULLY_NATIVE**
  - `status: complete` + `artifact_canonicalization` field absent → **HYBRID_PRE_WP10** (pre-WP-10 install, field not yet reconciled)
  - `status: in_progress` → **MIGRATION_IN_PROGRESS** (active DFC-AI migration — normal project work blocked)
  - state.yaml absent → **NO_MIGRATION_STATE** (fresh install or DFC migration not started)

> **Note — Migration Axis vs. Reconciliation Axis:** `project_lifecycle_state` classifies the DFC-AI → MxAgile migration only. It is orthogonal to post-UPDATE reconciliation status. A project reporting `FULLY_NATIVE` may still require post-UPDATE reconciliation. Always check Section I (Lifecycle State and Reconciliation Detection) for current reconciliation requirements before recommending any lifecycle action.

---

## G. Company Layer

1. Check `.mxagile/layers/` for subdirectories. If none: report `NOT_APPLICABLE`.
2. For each layer subdirectory found:
   a. Does `layer.json` exist? If yes, read and report `id` and `name` fields.
   b. Does `provenance.json` exist? If yes, read and report `source_type` and `source` fields.
   c. Does a nested `.git/` directory exist? If YES, this is a **contract violation** — report `FAIL: nested .git found`.
   d. Does `.mxagile/state/manifest.<layer-id>.md` exist?
3. Report overall layer status: PASS (all layers clean), FAIL (any nested .git), NOT_APPLICABLE (no layers).

---

## H. Behavioral Contract — Agent Self-Assessment

**Label this section clearly: "Agent Understanding Check (self-assessed — not filesystem verified)"**

Answer each question from your available instructions (loaded CLAUDE.md, AGENTS.md, skill files, etc.):

1. **Canonical source directory**: What is the canonical MxAgile source directory?
   - Expected: `.mxagile/`
   - Your answer: [answer] — PASS / FAIL / UNKNOWN

2. **Required Mendix tooling**: What is the required Mendix engineering tool?
   - Expected: `mxcli`
   - Your answer: [answer] — PASS / FAIL / UNKNOWN

3. **Canonical lifecycle**: Read `.mxagile/lifecycle.yaml` — does it exist and define the canonical phases?
   - Expected: File exists; `phases` block defines `discovery`, `refinement`, `implementing`, `verifying`; `initial_phase: discovery`
   - Your answer: [phases found in lifecycle.yaml, or MISSING if file absent] — PASS / FAIL / UNKNOWN

4. **Files not manually maintained**: What files should NOT be manually maintained?
   - Expected: Generated platform projections (`.claude/skills/mxagile-*/`, `.github/skills/mxagile-*/`, `.agents/skills/mxagile/`, `.claude/agents/mxagile-*.md`, etc.)
   - Your answer: [answer] — PASS / FAIL / UNKNOWN

5. **Ownership model**: How should ownership of AGENTS.md / CLAUDE.md be understood?
   - Expected: Shared — MxAgile owns only the managed block; user owns all content outside the block
   - Your answer: [answer] — PASS / FAIL / UNKNOWN

6. **Canonical artifact format**: What is the canonical format and location for Requirements, Specs, and Tasks?
   - Expected: `requirements/REQ-NNN.yml` (ID: field), `specs/SPEC-NNN.yml`, `planning/tasks/TASK-NNN.yml`; schemas in `.mxagile/schemas/`; contract in `docs/schemas.md`
   - Your answer: [answer] — PASS / FAIL / UNKNOWN

7. **Core update mechanism**: How is an existing MxAgile installation updated to a new Core version?
   - Expected: Run `install-core.ps1` from the new distribution — stale framework-owned artifacts are retired (Step 1c.1) before the canonical payload is copied; protected directories (layers/, state/, migration/) are preserved; no manual file copying
   - Your answer: [answer] — PASS / FAIL / UNKNOWN

8. **Framework migration vs artifact canonicalization**: Are these the same lifecycle?
   - Expected: NO — framework migration installs MxAgile Core over a DFC-AI project; artifact canonicalization is a separate subsequent lifecycle that converts legacy `.md` stories to `.yml` canonical artifacts; a project with `status: complete` + `artifact_canonicalization: pending` is in HYBRID mode (valid, not an error)
   - Your answer: [answer] — PASS / FAIL / UNKNOWN

---

## Report Format

After completing all checks, produce the following Markdown report verbatim in structure (fill in the actual values):

````markdown
# MxAgile System Check

Overall: PASS | PASS_WITH_WARNINGS | FAIL

## Summary
[One paragraph summarizing findings, calling out any failures or warnings.]

## A. Environment
- Working directory: [path]
- Mendix project (.mpr): [path or NOT_FOUND]
- Detected platform: [platform] (confidence: high | low)

## B. MxAgile Discovery
- .mxagile/: YES | NO
- version.yaml: [version or NOT_FOUND]
- .mxagile/skills/: YES ([count] skills) | NO
- .mxagile/agents/: YES | NO
- .mxagile/layers/: YES | NO

## C. Instruction Discovery
- AGENT.md: PRESENT | MISSING
- AGENTS.md: managed_block=[status], start=[N], end=[N], old_markers=[true|false]
- CLAUDE.md: managed_block=[status], start=[N], end=[N], old_markers=[true|false]
- .github/copilot-instructions.md: PRESENT | MISSING, managed_block=[status], start=[N], end=[N], old_markers=[true|false]

## D. Skill Discovery
- .claude/skills/ mxagile-* dirs: [list or NONE]
- .github/skills/ mxagile-* dirs: [list or NONE]
- .agents/skills/mxagile/: [list or NOT_FOUND]
- mxagile-system-check present: YES | NO (by platform)

## E. Tooling
- mxcli: FOUND ([path]) | NOT_FOUND
- mxcli version: [version or NOT_FOUND or ERROR]
- update-mxcli.ps1: PRESENT | MISSING

## F. Project Structure
- specs/: YES | NO
- requirements/: YES | NO
- planning/tasks/: YES | NO
- .mxagile/state/: YES | NO
- .mxagile/migration/: YES | NO
- migration state: [status value or NOT_FOUND]
- artifact_canonicalization: [value or NOT_FOUND]
- project lifecycle state: HYBRID | FULLY_NATIVE | HYBRID_PRE_WP10 | MIGRATION_IN_PROGRESS | NO_MIGRATION_STATE

## G. Company Layer
- Layers found: [list of IDs or NONE]
- [For each layer:] [id]: layer.json=[OK|MISSING], provenance.json=[OK|MISSING], .git=[ABSENT(OK)|PRESENT(FAIL)], manifest=[OK|MISSING]

## H. Agent Understanding (Self-Assessed)
- Canonical source: [PASS|FAIL|UNKNOWN]
- Required tooling: [PASS|FAIL|UNKNOWN]
- Lifecycle order: [PASS|FAIL|UNKNOWN]
- Generated files: [PASS|FAIL|UNKNOWN]
- Ownership model: [PASS|FAIL|UNKNOWN]
- Artifact format: [PASS|FAIL|UNKNOWN]
- Core update mechanism: [PASS|FAIL|UNKNOWN]
- Migration vs canonicalization: [PASS|FAIL|UNKNOWN]

## Machine-Readable Diagnostic

```yaml
mxagile_system_check:
  schema_version: 1
  timestamp: [ISO8601]
  platform:
    detected: claude_code | copilot | codex | unknown
    confidence: high | low | unknown
  overall: PASS | PASS_WITH_WARNINGS | FAIL
  discovery:
    status: PASS | FAIL
    mxagile_dir: true | false
    version: "1.1" | NOT_FOUND
  instructions:
    status: PASS | PASS_WITH_WARNINGS | FAIL
    agent_md:
      present: true | false
    agents_md:
      managed_block: VALID | DUPLICATE | MISSING | MALFORMED | OLD_MARKERS
      start_count: N
      end_count: N
    claude_md:
      managed_block: VALID | DUPLICATE | MISSING | MALFORMED | OLD_MARKERS
      start_count: N
      end_count: N
    copilot_instructions:
      present: true | false
      managed_block: VALID | DUPLICATE | MISSING | MALFORMED | OLD_MARKERS
  skills:
    status: PASS | FAIL | NOT_APPLICABLE
    claude_skills: [list]
    copilot_skills: [list]
    system_check_present: true | false
  tooling:
    status: PASS | FAIL
    mxcli:
      detected: true | false
      version: "x.y.z" | NOT_FOUND | ERROR
    updater:
      detected: true | false
  project_structure:
    status: PASS | PASS_WITH_WARNINGS
    specs: true | false
    requirements: true | false
    planning_tasks: true | false
    migration_dir: true | false
    migration_status: complete | in_progress | NOT_FOUND
    artifact_canonicalization: pending | in_progress | complete | NOT_FOUND
    project_lifecycle_state: HYBRID | FULLY_NATIVE | HYBRID_PRE_WP10 | MIGRATION_IN_PROGRESS | NO_MIGRATION_STATE
    # migration axis only — FULLY_NATIVE does not imply post-UPDATE reconciliation complete; see lifecycle_state section
  company_layers:
    status: PASS | PASS_WITH_WARNINGS | FAIL | NOT_APPLICABLE
    detected: [list of layer IDs]
    violations: [list of issues]
  behavioral_contract:
    status: PASS | FAIL | UNKNOWN
    note: "Self-assessed — not filesystem verified"
    checks:
      canonical_source: PASS | FAIL | UNKNOWN
      mendix_tooling: PASS | FAIL | UNKNOWN
      lifecycle: PASS | FAIL | UNKNOWN
      ownership: PASS | FAIL | UNKNOWN
      artifact_format: PASS | FAIL | UNKNOWN
      core_update_mechanism: PASS | FAIL | UNKNOWN
      migration_vs_canonicalization: PASS | FAIL | UNKNOWN
  lifecycle_state:
    canonical_state_present: true | false
    legacy_state_in_scratch: true | false
    current_wave: "W01" | NOT_FOUND
    current_phase: discovery | refinement | ready | implementing | verifying | done | NOT_FOUND
    mutation_eligibility: blocked | allowed | violation_detected | NOT_FOUND
    schema_reconciliation_needed: true | false
    evidence_gaps_count: N
    legacy_evidence_unreconciled: true | false
    reconciliation_required_before_implementation: true | false
    legacy_artifacts: [list of detected legacy locations]
    required_actions: [list of specific next-step actions derived from findings]
  warnings: []
  failures: []
```

## I. Lifecycle State and Reconciliation Detection

This section enables a fresh agent to determine what lifecycle actions are required after a
Core UPDATE or fresh clone, without the developer needing to specify internal reconciliation phases.

1. **Canonical lifecycle state**: Does `planning/lifecycle/process-state.yaml` exist?
   - If YES: read and report current wave/phase/gate status
   - If NO but `.concord/scratch/process-state.yaml` exists: report that legacy location detected; migration to canonical location needed
   - If neither exists: report NO_LIFECYCLE_STATE (fresh project or not yet started)

2. **Schema reconciliation needed**: Do any parity records in `planning/parity/` have `schema_version` below current (1) or lack `overall_result`? Report YES/NO/NOT_APPLICABLE.

3. **Evidence gaps**: Check both canonical parity records AND legacy evidence locations:
   - **Canonical gaps**: Are there parity records in `planning/parity/` with `overall_result: NOT_VERIFIED` or required dimensions with `result: NOT_VERIFIED` (`required: true`)? Report count.
   - **Legacy evidence unreconciled**: Does `.concord/screenshots/mockup/` contain any files AND no canonical evidence manifest exists under `planning/evidence/`? If YES: report `LEGACY_EVIDENCE_UNRECONCILED: true`. An `evidence_gaps_count` of 0 in this state does NOT mean evidence is complete — it means no canonical parity baseline has been established yet. Do NOT interpret zero canonical-manifest gaps as overall evidence completeness before legacy evidence has been reconciled and promoted.

4. **Legacy artifact locations detected**:
   - `planning/stories/` directory exists? (legacy format; canonical: requirements/REQ-NNN.yml)
   - `sprints/decisions.md` exists? (legacy; canonical: planning/decisions/)
   - `.concord/screenshots/mockup/` has content? (legacy evidence; should be promoted to planning/evidence/)

5. **Mutation eligibility**: Does `planning/lifecycle/process-state.yaml` have `mutation_eligibility: blocked`? Report current value.

---

## Important: Fresh Session Required
This check is most reliable when run in a NEW agent session started after installation.
The test verifies discovery from the installed repository, not from installation context.

## Next Steps

Based on findings, derive specific next actions:

**If FAIL on any section A–H:**
  List specific corrective actions for each failure.

**If lifecycle state section I shows NO_LIFECYCLE_STATE:**
  "No prior lifecycle state found. Begin Discovery when ready."

**If lifecycle state section I shows wave/phase:**
  "Lifecycle re-sync: currently at Wave [X], Phase [Y]. Resume from this position."

**If `canonical_state_present: false` AND reconstructed phase is `implementing`, `verifying`, or `done`:**
  "Canonical lifecycle state absent. Implementation MUST NOT resume based on historical artifact reconstruction alone. `reconciliation_required_before_implementation: true`. Required: run reconciliation to establish `planning/lifecycle/process-state.yaml` with verified `mutation_eligibility` before any implementation action."

**If legacy artifact locations detected:**
  "Legacy artifacts found. Run: 'Perform project structure reconciliation per policies/reconciliation.md'"

**If evidence gaps detected:**
  "Evidence gaps found for [count] required dimensions. Run: 'Identify targeted re-verification scenarios per policies/ui-parity.md'"

**If `legacy_evidence_unreconciled: true`:**
  "Legacy mockup evidence found at `.concord/screenshots/mockup/` without canonical evidence manifest. `evidence_gaps_count: 0` does NOT indicate evidence completeness in this state. Run: 'Reconcile and promote legacy evidence per policies/reconciliation.md and policies/evidence-contract.md before assessing evidence gaps.'"

**If schema reconciliation needed:**
  "Parity schema upgrade required. Run: 'Upgrade parity records per policies/ui-parity.md — Existing Evidence Upgrade'"

**If PASS with no lifecycle issues:**
  "Installation verified. MxAgile is correctly installed and operational."

Note: All lifecycle reconciliation and re-verification actions should be driven by a new agent
session reading the installed framework policies. The developer only needs to confirm and direct;
the agent derives the required steps from the installed framework.
````
