# Project Setup and Installation

This guide explains how to set up a new or update an existing Mendix project with MxAgile.

## Public Bootstrap Entry Points

| Script | Purpose |
|---|---|
| `mxagile-setup.ps1` | **Canonical** generic setup — detects state, installs or updates |
| `mxagile-setup-mercedes.ps1` | **Canonical** Mercedes setup — detects Core + Layer state independently |
| `install-mxagile.ps1` | **Deprecated** — compatibility wrapper, delegates to `mxagile-setup.ps1` |
| `install-mxagile-mercedes.ps1` | **Deprecated** — compatibility wrapper, delegates to `mxagile-setup-mercedes.ps1` |

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

*   **Mercedes-Benz Environment:** Independently detects MxAgile Core state and Mercedes
    Company Layer state, then performs the correct operation for each.
    ```powershell
    .\mxagile-setup-mercedes.ps1
    ```

Both scripts will:

1.  **Detect project state:** Report `FRESH_PROJECT` or `EXISTING_MXAGILE_PROJECT`.
2.  **Report selected operation:** `INSTALL` or `UPDATE` for Core (and Layer separately for Mercedes).
3.  **Report protected state:** `.mxagile/layers/`, `.mxagile/state/`, `.mxagile/migration/` are never overwritten.
4.  **Safety Check:** Validate that a single `.mpr` project file exists in the root.
5.  **Install or Update:** Bootstrap MxAgile from scratch or synchronize an existing installation.
6.  **Setup Agents:** Configure the agent system (platform projections for all supported agents).
7.  **Layer Management:** (Mercedes script only) Install or update the Mercedes-Benz company layer.

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

# Mercedes environment update (detects Core + Layer independently, updates both)
.\mxagile-setup-mercedes.ps1
```

The public entry points (`mxagile-setup.ps1`, `mxagile-setup-mercedes.ps1`) always select the
correct operation. There is no separate update command.

Internally, `scripts/install-core.ps1` is the canonical installer invoked by all entry points.

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
- Agents must NOT manually copy framework files or reconstruct an installation — only `install-core.ps1` is authoritative.

---

## Next Steps

Your project is now fully set up and ready to use the MxAgile workflow. You can start by:

*   Adding HTML mockups to the `input-resources/ui-ux/` directory and invoking the Discovery Agent (UI-Agent Analyze mode).
*   Defining your features by creating requirement and specification files in the `requirements/` and `specs/` directories.


