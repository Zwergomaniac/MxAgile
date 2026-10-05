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

## J. Core Installation Identity
- core-provenance.json: PRESENT | MISSING (PROVENANCE_INCOMPLETE)
- flavor: core | mercedes | UNKNOWN
- source: [url or path or UNKNOWN]
- source_type: git | local | UNKNOWN
- ref: [ref or UNKNOWN]
- commit: [40-char SHA or null]
- version: [version or UNKNOWN]
- installed_at: [ISO8601 or UNKNOWN]
- install_mode: install | update | UNKNOWN
- previous_commit: [SHA or null]
- distribution_owned: [list of scripts]

## K. Core Currency
- installed_commit: [SHA or null]
- upstream_commit: [SHA | UNKNOWN | SOURCE_UNAVAILABLE]
- currency: CURRENT | UPDATE_AVAILABLE | UNVERIFIED | PROVENANCE_INCOMPLETE
- currency_note: [reason when not CURRENT]
- projections_currency: CURRENT | STALE | UNKNOWN

## L. Project Template Health
- project_name: [resolved name | UNRESOLVED_TEMPLATE_VALUE]
- template_markers: NONE | [list of unresolved markers]
- encoding_health: OK | ENCODING_CORRUPTION_SUSPECTED
- legacy_references: NONE | [list of obsolete path patterns detected]

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
  core_installation:
    status: PASS | PROVENANCE_INCOMPLETE
    file_present: true | false
    flavor: core | mercedes | UNKNOWN
    source: "url or path" | UNKNOWN
    source_type: git | local | UNKNOWN
    ref: "main" | UNKNOWN
    commit: "40-char sha" | null
    version: "1.1" | UNKNOWN
    installed_at: "ISO8601" | UNKNOWN
    install_mode: install | update | UNKNOWN
    previous_commit: "sha" | null
    distribution_owned: [list of script paths]
  core_currency:
    status: CURRENT | UPDATE_AVAILABLE | UNVERIFIED | PROVENANCE_INCOMPLETE
    installed_commit: "sha" | null
    upstream_commit: "sha" | UNKNOWN | SOURCE_UNAVAILABLE
    currency_note: "reason when not CURRENT"
    projections_currency: CURRENT | STALE | UNKNOWN
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
  project_template_health:
    project_name: "resolved name" | UNRESOLVED_TEMPLATE_VALUE
    template_markers: []
    encoding_health: OK | ENCODING_CORRUPTION_SUSPECTED
    legacy_references: []
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

## J. Core Installation Identity

Read `.mxagile/state/core-provenance.json`:

1. If the file is **absent**: report `PROVENANCE_INCOMPLETE`. This is expected for projects installed before this contract was introduced — proceed, but note the gap.
2. If **present**, read and report:
   - `flavor` — "core" or "mercedes"
   - `source` — distribution URL or local path used during install
   - `source_type` — "git" or "local"
   - `ref` — git branch/tag (e.g. "main")
   - `commit` — full SHA of the installed distribution commit (null = unknown)
   - `version` — framework version string (e.g. "1.1")
   - `installed_at` — ISO8601 timestamp
   - `install_mode` — "install" or "update"
   - `previous_commit` — SHA of the prior commit on last update (null on fresh install)
   - `distribution.canonical_url` — authoritative update source URL
   - `distribution.update_entry_point` — script that owns Core update
   - `distribution.distribution_owned` — list of distribution-owned scripts

3. **Distribution-owned scripts**: scripts listed in `distribution.distribution_owned` are NOT consumer project artifacts. Their absence in a consumer project is **correct and expected** — never diagnose a missing distribution-owned script as a consumer defect. Do not search local filesystems for these scripts when the provenance record identifies the canonical source.

4. **No-filesystem-guessing invariant**: MxAgile Core source discovery must come from `core-provenance.json` or explicit installer configuration. Do not search arbitrary local filesystem locations for historical repository names (e.g. MxAi-Dev-System, DFC-AI), guessed development repositories, or machine-specific paths. If authoritative source provenance is unavailable or invalid, report `SOURCE_UNAVAILABLE` — do not compensate through broad filesystem search.

---

## K. Core Currency

**Offline rule**: If upstream cannot be queried, do NOT claim CURRENT. Report `currency: UNVERIFIED`.

1. Read `core-provenance.json`. If absent: `currency: PROVENANCE_INCOMPLETE` — skip this section.

2. Identify the installed commit from `commit` field. If null: `currency: UNVERIFIED (COMMIT_UNKNOWN)` — version string alone is not sufficient for currency. A null commit means the exact Core identity is unknown; it is **never** classified as CURRENT.

3. **If `source_type == "git"` and `source` is a URL**:
   - Attempt: `git ls-remote <source> <ref>` to resolve current upstream HEAD SHA (read-only, no clone needed).
   - If successful:
     - `installed_commit == upstream_commit` → `CURRENT`
     - `installed_commit != upstream_commit` → `UPDATE_AVAILABLE`
     - Report both SHAs.
   - If command fails (network, auth, timeout): `currency: UNVERIFIED — SOURCE_UNAVAILABLE`
   - Do NOT run `git clone` to check currency.

4. **If `source_type == "local"`**:
   - Attempt `git -C <source> rev-parse HEAD` to get current local HEAD.
   - If source path unavailable: `currency: UNVERIFIED — LOCAL_SOURCE_UNAVAILABLE`.

5. **Projections currency** — read `.mxagile/state/projections-manifest.json`:
   - If absent: `projections_currency: UNKNOWN`
   - If `generated_from_core_commit == null` OR `installed commit == null`: `projections_currency: UNKNOWN` — null values do **not** prove currency; `null == null` is not a match.
   - If both are non-null and equal: `CURRENT`
   - If both are non-null but different: `STALE` — projections were not regenerated after this Core update; re-run setup to regenerate.

---

## L. Project Template Health

Check relevant project instruction files for unresolved template markers, encoding corruption, and obsolete framework path references.

Files to check: `skillssource/AGENTS.md`, `projekt.md`, `AGENTS.md`, `AGENT.md`

1. **Project name resolution**:
   - Read `mxagile-project.yaml`. Extract `name:` field.
   - If `name` is absent or equals `[PROJEKTNAME]`: report `project_name: UNRESOLVED_TEMPLATE_VALUE`
   - If resolved: report `project_name: [actual name]`

2. **Unresolved template markers** — scan the files above for known framework template placeholders:
   - `[PROJEKTNAME]` — unresolved project name
   - `[Rolle]`, `[Modul]`, `[PROJEKTNAME]-playwright` — other template slots
   - `<!-- TODO: Projektspezifische Rollen` — role authoring TODO
   - `<!-- TODO:` generally — identify if it is a framework template marker or project-authored TODO
   - Classify each as: `UNRESOLVED_TEMPLATE_VALUE` | `PROJECT_AUTHORING_REQUIRED` | `PROJECT_AUTHORED`
   - Do NOT flag general project-authored TODOs as framework defects.

3. **Encoding corruption detection** (conservative — safety net, not repair):
   - Scan framework-managed instruction files for characteristic CP1252→UTF-8 mojibake patterns:
     - `Ã¤` (corrupted ä), `Ã¶` (ö), `Ã¼` (ü), `Ã„` (Ä), `Ã–` (Ö), `Ãœ` (Ü), `ÃŸ` (ß)
     - `â€"` (em dash), `â€˜` / `â€™` (curly quotes)
   - If any pattern found: report `encoding_health: ENCODING_CORRUPTION_SUSPECTED`
   - Do NOT attempt automatic repair. Report which file and pattern was found.
   - Primary fix is re-running setup from the current distribution (encoding reads are now correct).

4. **Legacy framework path references** — scan for obsolete framework path prefixes in instruction files:
   - `.dfc-ai/` — pre-MxAgile DFC-AI framework paths
   - If found: report as `LEGACY_REFERENCE` with the file and line
   - Where a safe canonical MxAgile equivalent exists (e.g., `.dfc-ai/policies/test-workflow.md` → `.mxagile/policies/test-workflow.md`), note the replacement but do NOT auto-repair project-owned prose.
   - If ambiguous: report as migration debt for manual review.

**Classification taxonomy:**
- `UNRESOLVED_TEMPLATE_VALUE` — a framework template slot not yet replaced by project identity
- `PROJECT_AUTHORING_REQUIRED` — a section marked for project-specific content; not yet written
- `LEGACY_REFERENCE` — references obsolete framework paths from a prior framework version
- `ENCODING_CORRUPTION_SUSPECTED` — characteristic mojibake detected; re-run setup to restore

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

**If `core_installation.status == PROVENANCE_INCOMPLETE`:**
  "Core installation provenance absent. This is expected for projects installed before the provenance contract was introduced. Run setup again to write provenance: `mxagile-setup.ps1 -ProjectRoot <path>`"

**If `core_currency.status == UPDATE_AVAILABLE`:**
  "Core update available. Installed commit: [installed_commit]. Upstream commit: [upstream_commit]. Run: `mxagile-setup.ps1 -ProjectRoot <path>` from the latest distribution."

**If `core_currency.projections_currency == STALE`:**
  "Generated projections are stale relative to installed Core. Re-run setup or regenerate: run setup from the installed distribution."

**If `core_currency.status == UNVERIFIED`:**
  "Core currency cannot be verified (upstream unavailable or commit unknown). This does NOT mean the installation is out of date — it means currency is unverifiable from here. Check manually when network access is available."

**If `project_template_health.project_name == UNRESOLVED_TEMPLATE_VALUE`:**
  "Project name not yet materialized. Add `name: \"Your Project Name\"` to `mxagile-project.yaml` and re-run setup to materialize instruction file templates."

**If `project_template_health.template_markers` is non-empty:**
  "Unresolved template markers found. Review each item: UNRESOLVED_TEMPLATE_VALUE items require filling in `mxagile-project.yaml.name` and re-running setup; PROJECT_AUTHORING_REQUIRED items require direct project-specific authoring."

**If `project_template_health.encoding_health == ENCODING_CORRUPTION_SUSPECTED`:**
  "Encoding corruption detected in instruction files. This indicates repeated Core updates ran under Windows PowerShell 5.1 with an old installer. Re-run setup from the current distribution to restore correct UTF-8 encoding. Do not attempt manual repair."

**If `project_template_health.legacy_references` is non-empty:**
  "Legacy DFC-AI framework path references found. These are migration debt. Review each item and update to the current .mxagile/ equivalent if a safe canonical replacement exists, or consult the project's migration history."

**If PASS with no lifecycle issues:**
  "Installation verified. MxAgile is correctly installed and operational."

Note: All lifecycle reconciliation and re-verification actions should be driven by a new agent
session reading the installed framework policies. The developer only needs to confirm and direct;
the agent derives the required steps from the installed framework.
````
