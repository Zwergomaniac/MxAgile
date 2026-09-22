# Project Setup and Installation

This guide explains how to set up a new Mendix project using the MxAgile template.

## Prerequisites

Before you begin, please ensure you have the following tools installed on your system:

*   **Python:** Version 3.8 or higher.
*   **Pip:** The Python package installer (usually included with Python).
*   **Git:** For version control.

## Setup Process

Setting up a new MxAgile project involves running the appropriate installer.

### Run the Installation Script

Choose the installation script based on your requirements:

*   **Generic Setup:** Use for general projects without specific company-layer requirements. Uses the canonical Core URL (`https://github.com/Zwergomaniac/MxAgile.git`) by default.
    ```powershell
    .\install-mxagile.ps1
    ```

*   **Mercedes-Benz Environment:** Use when working with Mercedes-Benz specific standards. This will automatically fetch and apply the necessary company layer and use the canonical Core URL.
    ```powershell
    .\install-mxagile-mercedes.ps1
    ```

Both scripts will:

1.  **Safety Check:** Validate that a single `.mpr` project file exists in the root.
2.  **Initialize Environment:** Check for Python, install dependencies, and create the required directory structure.
3.  **Setup Agents:** Configure the agent system according to project needs.
4.  **Layer Management:** (Mercedes script only) Automatically resolve and configure the Mercedes-Benz company layer.

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

`install-core.ps1` is the canonical entry point for **both** fresh installation and existing-project Core synchronization. You do not need a separate update command.

To update an already-installed MxAgile project to a newer Core version, re-run the same installer from the new distribution:

```powershell
# Generic Core update
.\scripts\install-core.ps1 -ProjectRoot <path-to-your-project>

# Mercedes environment update (also refreshes Company Layer)
.\scripts\install-core.ps1 -ProjectRoot <path-to-your-project> `
    -CompanyLayerSource <layer-git-url> `
    -CompanyLayerSourceType git `
    -CompanyLayerRef main
```

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

*   Adding HTML mockups to the `input-resources/ui-ux/` directory and running `scripts/mxagile-refine.ps1`.
*   Defining your features by creating requirement and specification files in the `requirements/` and `specs/` directories.


