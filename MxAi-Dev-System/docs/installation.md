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

### Step 4: Initial Git Commit (Recommended)

After the initialization is complete, it is highly recommended to initialize your own Git history:

```bash
# Remove the template's git history
rmdir .git /s /q

# Initialize your own repository
git init
git add .
git commit -m "Initial commit: Set up MxAgile project structure"
```

## Next Steps

Your project is now fully set up and ready to use the MxAgile workflow. You can start by:

*   Adding HTML mockups to the `input-resources/ui-ux/` directory and running `scripts/mxagile-refine.ps1`.
*   Defining your features by creating requirement and specification files in the `requirements/` and `specs/` directories.


