# MxAgile Core Update Contract

Policy governing how consumer agents discover, verify, and update MxAgile Core.

---

## 1. Core Installation Identity

After every fresh install or Core update, the consumer project contains a machine-readable
provenance record at `.mxagile/state/core-provenance.json` with the following canonical fields:

| Field | Semantics |
|---|---|
| `schema_version` | Always `"1"` |
| `flavor` | Backward-compatible semantic flavor; preserves an established product flavor instead of replacing it with generic `company-layer` |
| `product_flavor` | Established semantic product flavor, or `null` when unknown; never guessed from a Core ref or Layer name |
| `installation_flavor` | `core` or `company-layer`, independent of product identity |
| `artifact_contract` / `previous_artifact_contract` | Current/prior normalized installed-schema snapshot and fingerprint; missing current identity is unobservable |
| `recovery_tools` | Installed Python tools and Epoch Writer SHA256 hashes binding the narrowly scoped recovery helpers |
| `source` | Distribution URL or local path used during installation |
| `source_type` | `"git"` or `"local"` |
| `ref` | Git branch/tag used (e.g. `"main"`); empty for local sources |
| `commit` | Full 40-char SHA of the installed distribution commit; `null` when unavailable |
| `version` | Framework version string from `.mxagile/version.yaml` (e.g. `"1.1"`) |
| `installed_at` | ISO8601 timestamp of install/update |
| `install_mode` | `"install"` (first install) or `"update"` (Core sync) |
| `previous_commit` | Prior commit SHA, populated on update |
| `previous_version` | Prior version string, populated on update |
| `previous_installed_at` | Prior install timestamp, populated on update |
| `distribution.canonical_url` | Authoritative MxAgile distribution URL |
| `distribution.update_entry_point` | Script that owns Core update |
| `distribution.update_flag` | Required flag for update mode |
| `distribution.distribution_owned` | List of distribution-owned scripts (see §3) |

On update: the current fields are written fresh from the actual update source.
Stale source-path fields from prior installs are NOT preserved into the new record.
`previous_*` fields capture only the immediately prior state, not a full history.

Projects installed before this contract was introduced will have no `core-provenance.json`.
This is expected. The absence does not indicate a broken installation.

---

## 2. Commit Hash Is the Primary Currency Signal

Version strings (e.g. `"1.1"`) are human-readable labels. They are NOT sufficient to
determine whether a consumer project is current:

- Two distinct commits may carry the same version string.
- A consumer at version 1.1 installed three months ago may lack substantial content
  that was added to the 1.1 line after their install date.

**Rule**: Currency is determined by comparing the installed `commit` SHA against the
upstream `commit` SHA at the distribution source for the configured `ref`.

Checking procedure: `git ls-remote <source> <ref>` (read-only, no clone needed).

**Null semantics** — explicit, non-negotiable:

| installed `commit` | upstream SHA | Currency verdict |
|---|---|---|
| non-null SHA | same SHA | CURRENT |
| non-null SHA | different SHA | UPDATE_AVAILABLE |
| `null` | any | PROVENANCE_INCOMPLETE / UNVERIFIED — **never CURRENT** |
| any | unavailable | SOURCE_UNAVAILABLE / UNVERIFIED — **never CURRENT** |

`null == null` is **not** proof of currency. Two unknowns cannot be compared.

Similarly for projections: `generated_from_core_commit == null` means projection currency
is UNKNOWN — never CURRENT.

Distribution currency, artifact-contract compatibility and product/Company identity are
separate. A same-version or same-commit schema delta still requires current contract
reconciliation. A commit-only update with unchanged contract and sources does not restart a
completed artifact migration, but still invalidates loaded session context. Core `ref`/commit
never replace Company Layer provenance. Unknown prior product identity remains unknown.

---

## 3. Distribution vs Consumer Ownership

The following scripts are **distribution-owned** — they live in the MxAgile distribution
repository, not in consumer projects. Their absence in a consumer project is **correct and
expected**, never a defect:

- `scripts/install-core.ps1` — Core installer/updater
- `scripts/setup-agent-system.ps1` — Agent system orchestrator
- `scripts/generate-mxagile-platform-skills.ps1` — Platform projection generator

The `distribution.distribution_owned` array in `core-provenance.json` is the authoritative
list for the installed version.

**Consumer-owned** artifacts (never touched by Core update):
- `.mxagile/layers/` — Company Layer content
- `.mxagile/migration/` — Migration history
- `.mxagile/state/` — Framework-internal state (including provenance files)
- `planning/lifecycle/process-state.yaml` — Durable lifecycle state
- `requirements/`, `specs/`, `planning/tasks/` — Project artifacts

**Generated projections** (regenerated by setup, owned by the distribution mechanism):
- `.claude/skills/mxagile-*/`, `.claude/agents/mxagile-*.md`
- `.github/skills/mxagile-*/`
- `.agents/skills/mxagile/`, `.grok/skills/mxagile/`, `.opencode/skills/mxagile/`, `.hermes/skills/mxagile/`

---

## 4. No-Filesystem-Guessing Invariant

MxAgile Core source discovery **must** come from `core-provenance.json` or explicit
installer configuration. Agents MUST NOT search arbitrary local filesystem locations for:

- Historical repository names (MxAi-Dev-System, DFC-AI, MxAgile-Dev, etc.)
- Guessed development repositories on the local machine
- Machine-specific absolute paths
- Any path not referenced in authoritative provenance

If authoritative source provenance is absent or invalid:
- Report `SOURCE_UNAVAILABLE` or `PROVENANCE_INCOMPLETE`
- Do not compensate through broad filesystem search
- Prompt the user to run setup with the explicit `-DistributionSource` parameter

## 5. Update Lifecycle, Partial State, and Context Invalidation

The Company Layer setup is a multi-stage update. The canonical recovery record is
`.mxagile/state/update-transaction.json` while a transaction is active; the installed
files and their current provenance remain the source of truth for what is actually
installed. `.mxagile/state/last-update-result.json` is only the last attempt's handoff,
not current state. Compare its `installed_at`/commit and transaction ID with current
`core-provenance.json` and Company Layer `provenance.json` before relying on it.

Update states:

| State | Meaning | Delivery |
|---|---|---|
| `BLOCKED_BEFORE_MUTATION` | Preflight or host permission stopped the operation before project mutation. A host-level denial may not be persistable because the installer never ran. | No update occurred; inspect current provenance, then retry only through the authorized host path. |
| `UPDATE_IN_PROGRESS` | A transaction was persisted before Core mutation and has not reached a terminal update result. | Read-only diagnosis only; do not write or spawn a write-capable child. Resume only with the same source/ref target and `-ResumeUpdate`. |
| `PARTIAL_UPDATE` | Core and Company Layer are at different targets, or a stage failed without a verified cross-layer rollback. | Delivery and delegation are blocked until the same-target resume or explicitly approved recovery completes. |
| `UPDATE_FAILED_ROLLED_BACK` | A failed Layer stage restored its prior Layer projection and manifest; this does not imply Core rollback. | Reconcile current provenance; if Core changed, the overall transaction remains `PARTIAL_UPDATE`. |
| `UPDATE_INSTALLED_RESTART_REQUIRED` | All requested update stages installed; the current session's loaded contracts are stale. | No new delivery write/delegation until the installed contracts and lifecycle are re-read. Restart only when the host cannot safely re-read them in-session. |
| `COMPATIBILITY_NOT_VERIFIED` | Current Doctor evidence is missing, invalid, stale, or unavailable. | No compatibility claim; run the current installed Doctor and resolve the re-sync boundary before delivery. |
| `READY` | Session-derived state after current provenance, final Doctor, installed contracts, and lifecycle re-sync are all verified. | Delivery may proceed within the re-synced mission/wave/scope. `READY` is not inferred from a historical handoff. |

The canonical cross-layer strategy is resumable partial update, not automatic Core rollback.
After requested Core/Layer stages complete: observe contract delta -> persist scoped contract
plan -> apply only deterministic safe repairs -> defer review/real decisions -> rebuild derived
compatibility -> final Doctor -> invalidate/re-read context -> canonical lifecycle re-sync.
The existing migration state holds a nested contract record; historical root `complete`
flags do not prove current compatibility. NEEDS_HUMAN is an intentional unresolved decision,
not failed installation. No ordinary delivery or Epoch write may bypass that boundary.

Core updates replace shared generated contracts and may touch consumer/host projections; the
Company Layer updater owns a bounded backup/rollback only for the Layer directory and its state
manifest. There is no safe repository-wide Core rollback. If Core succeeds and Layer fails,
preserve the new Core, retain the previous Layer after its local rollback, persist `PARTIAL_UPDATE`,
and allow only an explicit same-target resume or a reviewed recovery path. Never label this overall
operation `UPDATE_SUCCESS`.

The transaction records previous/target Core identity, previous/target Layer identity, completed
stages, failed stage and exact failure, generated artifact paths, migrations, rollback/backup state,
compatibility status, context state, and resume availability. The Layer updater writes the resolved
target version/commit before applying artifacts and records rollback outcome. A new session checks
the active transaction before normal work; `UPDATE_IN_PROGRESS` or `PARTIAL_UPDATE` is a mandatory
delivery/child-write guard, not a suggestion.

Context-invalidating events include Core/Company/Project Layer update, generated agent/skill/policy
or schema replacement, branch/HEAD change, lifecycle-state change, external repository changes,
conversation compaction, and newly consumed child-agent results. Use the existing lifecycle re-sync
and source-fingerprint checks; do not create a second lifecycle state machine. A successful update
sets the context stale and requires re-sync. If the host cannot safely reload the installed context,
report `UPDATE_INSTALLED_RESTART_REQUIRED`; otherwise re-read, re-sync, and derive `READY` for that
session. `COMPATIBILITY_NOT_VERIFIED` remains separate from the update installation outcome.

---

## 5. Update Discovery

A consumer agent can determine the update procedure entirely from `core-provenance.json`:

```
distribution.canonical_url      → where to fetch the distribution
distribution.update_entry_point → which script to run (scripts/install-core.ps1)
distribution.update_flag        → -IsUpdate $true
```

Conceptually:
```
pwsh -File scripts/install-core.ps1 -ProjectRoot <project> -IsUpdate $true
  [+ ProvenanceCoreSource, ProvenanceCoreRef, ProvenanceCoreCommit from setup script]
```

The public entry point is `mxagile-setup.ps1` (or the Company Layer variant), which
handles distribution acquisition, commit resolution, and invokes `install-core.ps1`.
Use that public entry point for "MxAgile updaten"; do not invoke the installer
with only `-ProjectRoot`, which defaults to fresh-install semantics and loses
previous provenance. Direct distribution invocations must pass the recorded
update flag and resolved source/ref/commit parameters.
From Bash, prefer `pwsh -NoProfile -File <distribution>/mxagile-setup.ps1
-ProjectRoot <project> -DistributionSource <source> -NonInteractive`.
Do not pass an unquoted PowerShell `$true` through Bash: shell expansion can
silently select install mode instead of update mode.

Do NOT create a second competing update mechanism. Do NOT create a second Core distribution
channel. Extend the existing mechanism only.

### Mandatory post-update compatibility and agent completion

This contract also applies to follow-up verification such as "ist mxagile korrekt
aktualisiert?". Commit equality answers Core currency only, never project health.
Read this contract and current compatibility evidence again before answering.

A plain request such as "MxAgile updaten" includes the read-only post-update
Doctor without another user question. The completion sequence is:
`FRAMEWORK_INSTALLED` -> Doctor -> `PROJECT_COMPATIBILITY_CHECKED` -> agent report.
Installer exit 0 means framework installation succeeded, NOT project compatibility.
The same check runs on repeated updates, even when the Core commit is unchanged.

After setup, read `.mxagile/state/last-update-result.json`, the installer-owned
handoff for this invocation. Check it against the current Core provenance and
the observed installer outcome; a prior result is not proof of this run. It is
diagnostic evidence only, never lifecycle authority. If the result is absent
(for example, updating from an older distribution), run the installed Doctor
directly with `doctor --project-root . --format json` and consume its result.
Never infer compatibility from framework version, commit, installer exit 0,
migration completion, or a previous Doctor result.
Do not filter completion output to version/commit or `[OK] Core` lines and then
infer overall success. Read the structured handoff even if a log filter shows
framework installation succeeded; compatibility and session re-sync are required.

The final agent response MUST contain:
- Framework: previous and new version/commit (UNKNOWN when unavailable), and
  update successful YES/NO from the installer outcome.
- Project Compatibility: Doctor executed YES/NO, compatibility state
  (`COMPATIBLE`, `PARTIAL`, `BLOCKED`, or `NOT_VERIFIED`), and `repair_status`.
- Blocking diagnostics: redacted category and relative source path, plus
  SAFE_DETERMINISTIC, AGENT_REPAIRABLE, DECISION_REQUIRED, and UNSUPPORTED counts. These count
  diagnostic findings, not distinct files or approved repair operations.

Keep a compatible result compact (no diagnostic dump). For incompatible results,
include UNASSIGNED tasks and other nonblocking diagnostics needed to explain the
state; reference the handoff for remaining details. Do not copy secret values or
source contents. If Python, dependencies, schemas, or valid Doctor output are
unavailable, report `NOT_VERIFIED` with the concrete reason, never PASS. Framework
installation may still be successful. A failed installer remains a failed update;
do not use an older successful handoff to override it.

### Same-session contract re-sync before completion

Installing files does not reload instructions already loaded by the agent host.
`projections_currency: CURRENT` proves disk generation only, not loaded session
currency. Treat pre-update policies, skills and managed instructions as stale,
including when setup was invoked by an old session without this contract loaded.
The installer emits `RE_SYNC_REQUIRED` as a handoff, not proof of a reload.

Before the same session reports completion:
1. Re-read the installed `.mxagile/state/core-provenance.json` and
  `.mxagile/state/projections-manifest.json`; verify their non-null commit match.
2. Explicitly read the installed `.mxagile/policies/update-contract.md`,
  `.mxagile/policies/project-compatibility.md`, `.mxagile/policies/lifecycle-resync.md`,
  `AGENT.md`, and the active harness managed instruction projection (for example
  `.github/copilot-instructions.md`, `CLAUDE.md` or `AGENTS.md`). Re-read any
  active MxAgile agent/skill used for this update or verification from disk.
  Previously loaded text and a regenerated manifest are not these read operations.
3. Apply the existing Lifecycle Re-Sync read-only, preserving delivery state.
  Report `CONTRACTS_RE_SYNCED` only after these observed reads succeed; do not
  write a session attestation into the installer-owned result.
4. Consume the invocation-bound Doctor handoff as above (or run Doctor if missing),
  then report Framework Update and Project Compatibility separately, with Doctor
  executed, blocking diagnostic count and all four repairability counts. Unknown
  counts are UNKNOWN, never zero. Report repair need via `repair_status`; it must
  not disappear behind a CURRENT commit or a nonblocking compatibility state.

If the host cannot safely apply the re-read contracts, required reads fail, or
projection identity cannot be verified, report `UPDATE_INSTALLED_RESTART_REQUIRED`:
Framework update SUCCESS when installation succeeded; Project compatibility
NOT_VERIFIED for this session, with the concrete reload/re-sync gap. Preserve any
observed Doctor result as separate diagnostic evidence, not an overall healthy
verdict. Request explicit reload/re-sync or a new session only for this gap.
No unconditional restart is required when the read-only re-sync succeeds.

The automatic step runs Doctor only, never repair. SAFE_DETERMINISTIC availability
is not a green result before repair. Actual repairs follow the existing
project-compatibility and mission/autonomy contracts; DECISION_REQUIRED never
authorizes an automatic business decision. No lifecycle/wave changes, evidence
promotion, or finding closure are authorized by an update or Doctor result.

---

## 6. Offline and Network-Degraded Behavior

When upstream cannot be queried during system-check:

- Do NOT claim `CURRENT`
- Report `installed_commit: <known SHA>` (the locally stored commit)
- Report `upstream_commit: UNKNOWN`
- Report `currency: UNVERIFIED — SOURCE_UNAVAILABLE`

An unverified currency status does NOT mean the installation is out of date. It means
currency is unverifiable from the current network context.

---

## 7. Projections Currency

Generated platform projections carry their generation provenance in
`.mxagile/state/projections-manifest.json`:

| Field | Semantics |
|---|---|
| `generated_at` | ISO8601 timestamp of last generation |
| `generated_from_core_commit` | Core commit at generation time |
| `generated_from_core_version` | Core version at generation time |
| `generator` | Generator script name |
| `generator_owned_by` | Always `"distribution"` |

If `generated_from_core_commit` differs from the installed `commit` in
`core-provenance.json`, projections are **stale**. Re-run setup to regenerate.

If no manifest exists, projections currency is **UNKNOWN** — they may or may not be current.

## 8. Multi-Layer Update Transaction and Recovery

The Company Layer setup updates Core before the installed Company Layer. Core and Layer do not
share a safe repository-wide rollback: `update-layer.ps1` can restore only the Layer-owned directory
and its state manifest. Therefore the canonical strategy is **resumable partial update**, not
automatic Core rollback.

`.mxagile/state/update-transaction.json` is the active operational transaction marker. It is not
pipeline lifecycle authority and is removed only after all requested update stages, final Doctor,
and last-result handoff have completed. `.mxagile/state/last-update-result.json` remains the
last-attempt handoff; it is not current installed state. Current Core/Layer provenance and a fresh
read-only Doctor outrank any historical handoff. A failed/in-progress transaction must be compared
against those current records before resume.

| State | Meaning and allowed work |
|---|---|
| `BLOCKED_BEFORE_MUTATION` | Preflight failed before Core/Layer mutation. Read-only diagnosis and correction of the blocking precondition are allowed. A host Permission denial that prevents the installer process from starting cannot be persisted by MxAgile; report the host's denial as observed evidence, not an installer result. |
| `UPDATE_IN_PROGRESS` | Active transaction with persisted targets/stages. Read-only inspection only; no delivery writes or write-capable delegation. Resume only with the same Core source/ref/commit and Company Layer repository/ref using `-ResumeUpdate`. |
| `PARTIAL_UPDATE` | Core and Company Layer differ, or a stage failed before cross-layer completion. Delivery and write delegation are prohibited. Preserve current provenance, Layer backup/rollback evidence, and exact failure; resume only the recorded target or perform an explicitly reviewed recovery. |
| `UPDATE_FAILED_ROLLED_BACK` | A component updater restored its own prior projection. This is a component result; if Core already advanced, the overall transaction remains `PARTIAL_UPDATE`. |
| `UPDATE_INSTALLED_RESTART_REQUIRED` | All requested update stages completed, but the currently loaded host context is stale. Re-read installed contracts and perform lifecycle Re-Sync in-session when safe; restart only when the host cannot safely reload them. No delivery write/delegation before that boundary. |
| `COMPATIBILITY_NOT_VERIFIED` | Current Doctor could not produce a valid result. Installation status and compatibility remain separate; no healthy/READY claim. |
| `READY` | Session-derived only after current Core/Layer provenance, final Doctor, installed contracts, and lifecycle position are verified. Never derive READY from the last-result handoff alone. |

The transaction records previous and target Core/Layer identities, completed and failed stages,
exact failure, affected generated artifact paths, migrations, Doctor/compatibility status,
context-invalidated state, restart/Re-Sync requirements, and component rollback/resume evidence.
Layer target version/commit is recorded after target manifest resolution and before Layer mutation.
If the process ends with an active marker, the next session must detect it before normal delivery.

Context-invalidating events include Core, Company Layer, or Project Layer updates; regeneration of
agent/skill/policy/schema projections; branch/HEAD changes; lifecycle changes; external changes;
conversation compaction; and child-agent results. Use the existing lifecycle Re-Sync and source
fingerprints rather than introducing a second lifecycle state machine. A same-session re-read may
be sufficient when the host safely exposes the installed contracts; otherwise the state remains
`UPDATE_INSTALLED_RESTART_REQUIRED` until a fresh session performs Re-Sync.

---

## 8. Content Fingerprint — Architectural Decision

A commit hash is sufficient for normal distributed installs from the canonical Git source.

A content fingerprint (hash of `.mxagile/` directory contents) would add value for:
- Detecting local drift (modified `.mxagile/` files after install)
- Damaged installations where files were edited or deleted

**Decision**: Content fingerprinting is NOT implemented in this version. The commit hash
provides sufficient integrity for the primary consumer update use case. If local drift
detection becomes a production requirement, a `content_hash` field can be added to
`core-provenance.json` at `schema_version: "2"` without breaking existing consumers.
