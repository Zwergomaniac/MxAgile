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

### Contract migration before final Doctor

The canonical installer observes prior/current installed-schema fingerprints independently
of version and commit labels. It runs the installed compatibility producer's
`migrate --apply-safe` after installation and before final Doctor. The Company Layer setup
delegates to the same producer only after Core and Layer stages complete; a partial update
remains read-only. The result includes a separate `migration` record.

Only deterministic safe repairs are automatic. A missing Requirement successor remains
`NEEDS_HUMAN`; unsupported/reviewable artifacts remain `NEEDS_REVIEW`. Reviewed candidates
continue through the existing approved plan/hash repair path. Re-run contract reconciliation
after explicit source resolution, then re-read contracts and use the installed Epoch Writer.
Its preflight refuses unresolved migration, BLOCKED Doctor, an active update transaction or
conflicting/missing canonical Mission/Wave/phase before any Epoch write. Recovery does not
approve ordinary implementation or acceptance.

`contract_migration` is a surgical nested record in existing migration state. Historical DFC
and canonicalization flags remain unchanged, but cannot assert current-contract compatibility.
Core provenance distinguishes `product_flavor`, generic `installation_flavor`, and Core
source/ref/commit; preserved Company Layer provenance remains independent. Missing identity
is unobservable, never CURRENT. Equal-contract completed retries are idempotent.

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


