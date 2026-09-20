# Project Setup and Installation

This guide explains how to set up a new Mendix project using the MxAgile template.

## Prerequisites

Before you begin, please ensure you have the following tools installed on your system:

*   **Python:** Version 3.8 or higher.
*   **Pip:** The Python package installer (usually included with Python).
*   **Git:** For version control.

## Setup Process

Setting up a new MxAgile project involves two main steps.

### Step 1: Get the Project Files

Clone this template repository to your local machine to serve as the foundation for your new Mendix project.

```bash
git clone <URL_of_this_repository> "MyNewMendixProject"
cd MyNewMendixProject
```

### Step 2: Run the Initialization Script

The `mxagile-init.ps1` script is the single entry point for setting up the project environment and framework structure. Open a PowerShell terminal in the project root and run the following command:

```powershell
.\scripts\mxagile-init.ps1
```

This interactive script will:

1.  **Check for Dependencies:** It verifies that Python and Pip are available in your system's PATH.
2.  **Install Python Packages:** It automatically installs all required Python libraries by running `pip install -r requirements.txt`.
3.  **Create Directories:** It creates the standard MxAgile folder structure (`.mxagile`, `specs`, `requirements`, etc.) if they don't already exist.
4.  **Prompt for Company Layer:** It will detect available "Company Layers" (like `mercedes-benz`) in the `.mxagile/layers` directory and ask if you want to apply one for company-specific standards.

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

## Next Steps

Your project is now fully set up and ready to use the MxAgile workflow. You can start by:

*   Adding HTML mockups to the `input-resources/ui-ux/` directory and running `scripts/mxagile-refine.ps1`.
*   Defining your features by creating requirement and specification files in the `requirements/` and `specs/` directories.

