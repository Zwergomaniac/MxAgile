# Project Setup and Installation

This guide explains how to set up a new or update an existing Mendix project with MxAgile.

## Public Bootstrap Entry Points

| Script | Purpose |
|---|---|
| `mxagile-setup.ps1` | **Canonical** generic setup — detects state, installs or updates |
| `mxagile-setup-company-layer.ps1` | **Canonical** Company Layer setup — detects Core + Layer state independently |
| `install-mxagile.ps1` | **Deprecated** — compatibility wrapper, delegates to `mxagile-setup.ps1` |
| `install-mxagile-company-layer.ps1` | **Deprecated** — compatibility wrapper, delegates to `mxagile-setup-company-layer.ps1` |

The setup scripts detect project state automatically:

- **FRESH PROJECT** → performs `INSTALL`
- **EXISTING MXAGILE PROJECT** → performs `UPDATE`

You do not need to decide whether to run an install or update script.

## Prerequisites

Before you begin, please ensure you have the following tools installed on your system:

*   **Git:** For version control (required to acquire the MxAgile distribution).

## Setup Process

### Run the Setup Script

Choose the setup script based on your requirements:

*   **Generic Setup:** Use for general projects without specific company-layer requirements.
    Uses the canonical Core URL (`https://github.com/Zwergomaniac/MxAgile.git`) by default.
    ```powershell
    .\mxagile-setup.ps1
    ```

*   **Company Layer Environment:** Independently detects MxAgile Core state and Company Layer
    state, then performs the correct operation for each. The Company Layer Git source is
    always explicit: pass `-CompanyLayerGitUrl <git-url>` (optional `-CompanyLayerRef`) or set
    `MXAGILE_COMPANY_LAYER_URL`. There is no built-in default source.
    ```powershell
    .\mxagile-setup-company-layer.ps1 -CompanyLayerGitUrl "<git-url>"
    ```

Both scripts will:

1.  **Detect project state:** Report `FRESH_PROJECT` or `EXISTING_MXAGILE_PROJECT`.
2.  **Report selected operation:** `INSTALL` or `UPDATE` for Core (and Layer separately for Company Layer).
3.  **Report protected state:** `.mxagile/layers/`, `.mxagile/state/`, `.mxagile/migration/` are never overwritten.
4.  **Safety Check:** Validate that a single `.mpr` project file exists in the root.
5.  **Install or Update:** Bootstrap MxAgile from scratch or synchronize an existing installation.
6.  **Setup Agents:** Configure the agent system (platform projections for all supported agents).
7.  **Layer Management:** (Company Layer script only) Install or update the Company Layer company layer.

### Step 2: Synchronize Agent Environment

**IMPORTANT:** If you make any changes to the `.mxagile/` directory, run the generator script to keep your agent configurations updated:

```powershell
.\scripts\generate-mxagile-platform-skills.ps1
```

### Step 3: Initial Git Commit (Recommended)

After the initialization is complete, it is highly recommended to initialize your own Git history:

```bash
# Remove the template's git history
rmdir .git /s /q

# Initialize your own repository
git init
git add .
git commit -m "Initial commit: Set up MxAgile project structure"
```

---

## Core Update / Synchronization (existing MxAgile installations)

Re-run the same setup script from the new distribution — it detects the existing installation and performs an `UPDATE` automatically:

```powershell
# Generic Core update (detects existing installation, performs UPDATE)
.\mxagile-setup.ps1

# Company Layer environment update (detects Core + Layer independently, updates both)
.\mxagile-setup-company-layer.ps1
```

The public entry points (`mxagile-setup.ps1`, `mxagile-setup-company-layer.ps1`) always select the
correct operation. There is no separate update command.

Internally, `scripts/install-core.ps1` is the canonical installer invoked by all entry points.

### Update completion and running sessions

Framework currency is not project compatibility. After setup, consume the invocation-bound
`.mxagile/state/last-update-result.json`: report framework success, Doctor executed,
compatibility, blocking diagnostics and all four repairability counts separately.
Missing verification is `NOT_VERIFIED`, never a healthy-project verdict.

Generated instructions on disk do not reload a running agent session. The installer hands
off `RE_SYNC_REQUIRED`; before completion, explicitly re-read the installed contracts and
active instructions/skills using `.mxagile/policies/update-contract.md`. Successful read-only
re-sync permits `CONTRACTS_RE_SYNCED` without restarting. If it cannot be applied safely,
report `UPDATE_INSTALLED_RESTART_REQUIRED` and compatibility `NOT_VERIFIED` for that session.
These rules also apply to follow-up questions about whether the update was correct.

For Bash callers, use the public setup script with `-ProjectRoot`, `-DistributionSource`
and `-NonInteractive`. Do not send an unquoted PowerShell `$true` through Bash to a direct
installer invocation. Do not reduce completion to filtered version/commit or `[OK] Core`
lines: the Example Project reality regression ran Doctor successfully but discarded its `BLOCKED`
result through exactly that filter, then answered from commit equality alone.

### BLOCKED Delivery: bound Framework self-update recovery

A migration-blocked Delivery can discover and install a verified Core correction without
opening Delivery authority. The installed `framework_update_recovery.py` accepts only the
current Consumer root, an existing provenance-authorized Git source, an explicit ref and
its pinned commit. `check` and `preflight` are read-only; the latter binds the payload,
current provenance/contract/transaction and canonical projection preflight to a plan hash.
Foreign projection conflicts stop before Core or recovery-state mutation. Arbitrary setup
filenames, other sources/roots, shell chains and extra arguments confer no authority.

```powershell
$root = 'D:\Mendix\Your Project'
$tool = Join-Path $root '.mxagile\tools\framework_update_recovery.py'
$source = 'https://github.com/Zwergomaniac/MxAgile.git' # Must match existing provenance.
$ref = 'experiment/control-plane-sak-principles'
$target = python -B $tool check --project-root $root --source $source --ref $ref | ConvertFrom-Json
$preview = python -B $tool preflight --project-root $root --source $source --ref $ref --commit $target.commit | ConvertFrom-Json
# Run only after the actual User approves this exact source/ref/commit and plan.
python -B $tool apply --project-root $root --source $source --ref $ref --commit $target.commit --plan-hash $preview.plan.plan_hash --human-reference USER-CONFIRMED-UPDATE --run-id RUN-CURRENT-SESSION --human-confirmed
```

The dedicated operation invokes only the canonical `scripts/install-core.ps1` with fixed
arguments and the existing update transaction. Company Layers and Product provenance are
preserved, not independently updated. A partial transaction requires a fresh approved
preflight and `resume` with the same source/ref/commit; ordinary writes remain blocked.
Publication remains a separate authorization.

**Legacy bootstrap boundary:** already shipped guards cannot learn a new command grammar
before their own update. They continue to deny agent-driven discovery/update. An explicitly
authorized maintainer must perform the one-time, visible terminal operation using the
verified new distribution's `scripts/framework_update_recovery.py` instead of `$tool`.
The chosen distribution must already contain this implementation; uncommitted working-tree
files are not a Git distribution. No Hook-Off, settings/guard patch, hidden agent process,
permanent bypass or general PowerShell permission is permitted. Authorization is revocable
before invocation; interrupted mutation uses the existing transaction recovery. Physical
rollback is available only where the existing transaction reports it, not as an invented
whole-project rollback guarantee. Previous provenance and migration history are retained.

A successful dedicated update reports `INSTALLED_RESTART_REQUIRED` and a stale Context.
The canonical handoff also sets `restart_required: true` and
`session_contract.state: SESSION_RESTART_REQUIRED`. Disk updates and host registration do
not prove that a running session has reloaded its authority. Restart the host session;
only then may the actual User-confirmed restart be acknowledged in a **different Run**:

```powershell
python -B $tool acknowledge-restart --project-root $root --update-id UPDATE-EXACT-ID-FROM-APPLY --human-reference USER-ACTUAL-RESTART --run-id RUN-NEW-SESSION --human-confirmed
```

This is an explicit Human evidence contract, not cryptographic host attestation. An agent
must not invent a restart confirmation. The ignored runtime record in
`.mxagile/state/runs/framework-update-recovery.json` blocks Human Resolve and canonical
Epoch re-sync until acknowledgment validates current installed tool/contract provenance.
Acknowledgment does **not** clear migration, Doctor or lifecycle blockers. Continue with
the new Guard, bound Human Resolution, migration completion, fresh Doctor, lifecycle
reconciliation and canonical Context re-sync. Neither update nor acknowledgment promotes
a Mission/Wave or authorizes Requirements, Product code, Mendix model, Navigation, Security,
normal writing children or publication. The read-only reload exception above does not
replace this dedicated restart barrier. See the
[canonical recovery contract](../.mxagile/policies/project-compatibility.md#framework-self-update-recovery-and-legacy-bootstrap).

### Contract migration before final Doctor

The canonical installer observes prior/current installed-schema fingerprints independently
of version and commit labels. It runs the installed compatibility producer's
`migrate --apply-safe` after installation and before final Doctor. The Company Layer setup
delegates to the same producer only after Core and Layer stages complete; a partial update
remains read-only. The result includes a separate `migration` record.

Only deterministic safe repairs are automatic. A missing Requirement successor remains
`NEEDS_HUMAN`; unsupported/reviewable artifacts remain `NEEDS_REVIEW`. Reviewed candidates
continue through the existing approved plan/hash repair path. Human successor decisions use
the dedicated installed `project_compatibility.py resolve`, not ordinary YAML Edit or shell
manipulation. Obtain the live binding with `resolve --dry-run --project-root <absolute-root>
--format json`. The mutating command requires the exact diagnostic/migration identity,
source path/field/fingerprint, valid successor value, Run ID, actual Human decision reference
and `--human-confirmed`. The installed hook grants only `HUMAN_RESOLUTION_WRITE` for this
integrity-bound command. Other writes remain blocked.

Resolve changes only the authorized source field, retains recovery/audit receipts in the
existing migration record, and re-evaluates migration without repairing other sources.
An identical repeat is `ALREADY_RESOLVED`; conflicting or stale resolutions cannot overwrite.
After complete migration, fresh Doctor follows, then lifecycle reconciliation, contract
re-read and the installed Epoch Writer. Pending receipts and unresolved diagnostics block
re-sync; applied resolution receipts make an older Context checkpoint stale. Migration
completion and the APPLIED receipt are published in one atomic metadata replacement;
interrupted finalization remains NEEDS_HUMAN/PENDING and is recoverable through Resolve.

A BLOCKED Delivery does not prohibit a separately confirmed noncanonical documentation or
diagnostic assignment. Use the dedicated installed `auxiliary --dry-run` / `auxiliary
--apply` operation with a closed current User request, artifact role, exact target/content,
create/replace mutation, source fingerprint and approved plan hash. The actual matching
User reference and confirmation are mandatory. The bounded operation does not allow normal
Edit or arbitrary shell writes and cannot modify canonical contracts, Product code,
Requirements, Lifecycle or the model. Supported recipes are plain-text documentation and
findings; code/executable recipes are unavailable. See
[Bounded Auxiliary User interruption](../.mxagile/policies/project-compatibility.md#bounded-auxiliary-user-interruption)
for the complete command/request contract. The existing ignored runtime store retains an
interruption watermark; original Delivery remains blocked and must pass canonical recovery
and Context re-sync before resume.
Its preflight refuses unresolved migration, BLOCKED Doctor, an active update transaction or
conflicting/missing canonical Mission/Wave/phase before any Epoch write. Recovery does not
approve ordinary implementation or acceptance.

`contract_migration` is a surgical nested record in existing migration state. Historical DFC
and canonicalization flags remain unchanged, but cannot assert current-contract compatibility.
Core provenance distinguishes `product_flavor`, generic `installation_flavor`, and Core
source/ref/commit; preserved Company Layer provenance remains independent. Missing identity
is unobservable, never CURRENT. Equal-contract completed retries are idempotent.

### Projection preflight and partial-update resume

The canonical installer checks the future generator inputs and **all host targets before
Core mutation**. `TARGET_EMPTY_UNOWNED` also covers structurally empty trees containing
only normal directories (for example empty `assets/images/` plus empty siblings).
Recursive inventory must find no files, including hidden or zero-byte files and
ownership metadata, and no symlinks, junctions, reparse points or unsupported entries.
These empty subtrees are preserved on apply and repeated generation; all entries
remain subject to the same classifier and concurrent-change checks. Nonempty unknown
or foreign content, hidden files, invalid paths and reparse points block the complete plan.
The existing generator stages rendered bytes, validates apply ownership and publishes its
file-bound manifest only after every required output succeeds. Unexpected failures after
Core application retain `PARTIAL_UPDATE`, the old manifest and an explicit
`CORE_APPLIED_PROJECTIONS_PENDING` activation state; there is no whole-Core rollback.

Use the canonical distribution with explicit authorization:

```powershell
& .\scripts\install-core.ps1 -ProjectRoot $project -IsUpdate $true -ResumeUpdate
```

Resume validates the installed schema/tool identity and source bytes against the installed
commit's locally available Git objects. It repairs that Core, not the newer runner version.
The same path handles a verified legacy Core-new/manifest-old state with **no transaction**;
unobservable or contradictory identities fail closed. Existing Company Layers remain
unchanged when no pending Layer target was recorded. For a known pending Company update,
resume the enclosing Company bootstrap with its recorded repository/ref instead.

Projection completion precedes safe contract migration, real human decisions, final Doctor,
canonical lifecycle reconciliation and Context Epoch re-sync. It never grants delivery by
itself. A second completed resume is read-only; unavailable Doctor evidence remains
`NOT_VERIFIED`, not PASS. The repair runner needs the installed commit's Git objects; an
archive without that history cannot prove a pinned installed-Core resume. The Company
bootstrap acquires a missing pinned commit into its own temporary Git clone before resume;
it never fetches into or rewrites the consumer's Git repository.

### What the update preserves

| Protected | Synchronized |
|---|---|
| `.mxagile/layers/` (Company Layer) | All other `.mxagile/` content (skills, agents, policies, schemas, templates) |
| `.mxagile/state/` (runtime state, brownfield baseline) | Generated platform projections (`.claude/`, `.github/`, `.agents/` skill dirs) |
| `.mxagile/migration/` (migration history, canonicalization state) | `mxcli.exe` (updated via `update-mxcli.ps1`) |
| `requirements/`, `specs/`, `planning/`, `*.mpr` (project artifacts) | |

Stale framework-owned files that were removed from the new Core version are retired before the new payload is copied, so the resulting installation is always equivalent to a fresh install of the same Core version.

### Safety contract

- The installer does NOT restart or reset migration history.
- A project with `status: complete` in `state.yaml` retains that status after an update.
- `artifact_canonicalization` state is preserved and not reset.
- Protection of project artifacts does not prohibit the scoped deterministic compatibility
  repairs authorized by this update; unrelated source bytes and history remain preserved.
- Agents must NOT manually copy framework files or reconstruct an installation — only `install-core.ps1` is authoritative.

---

## Next Steps

Your project is now fully set up and ready to use the MxAgile workflow. You can start by:

*   Adding HTML mockups to the `input-resources/ui-ux/` directory and invoking the Discovery Agent (UI-Agent Analyze mode).
*   Defining your features by creating requirement and specification files in the `requirements/` and `specs/` directories.


