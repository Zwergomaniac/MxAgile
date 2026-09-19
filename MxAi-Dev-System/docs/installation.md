# MxAgile Installation

The `MxAgile` framework is designed to be integrated into an existing Mendix project.

## Automated Installation (Recommended)

The easiest way to install MxAgile is by using the provided installer script. This script will fetch the latest version of the framework and copy the necessary files into your project.

1.  **Download the Installer**
    Download the `install-mxagile.ps1` script from the root of the template repository.

2.  **Run in your Project Root**
    Place the script in the root directory of your Mendix project and run it from a PowerShell terminal:

    ```powershell
    ./install-mxagile.ps1 -RepositoryUrl "https://github.com/your-org/mxagile-template.git"
    ```

    Replace the `-RepositoryUrl` with the actual URL of the MxAgile template repository.

3.  **What it Does**
    The script will automatically:
    - Clone the template repository into a temporary folder.
    - Copy the `.mxagile` and `scripts` directories into your project.
    - Clean up the temporary folder.

## Manual Installation

If you prefer, you can install the framework manually:

1.  Clone or download this template repository.
2.  Copy the following directories into the root of your Mendix project:
    - `.mxagile`
    - `scripts`
3.  (Optional) Copy the artifact directories (`requirements`, `specs`, `planning`, `waves`) to use as a starting point.

## Next Steps

Once installed, you can begin the MxAgile workflow:
- Create artifacts (e.g., in `requirements/` and `specs/`).
- Run `scripts/mxagile-build-trace-index.ps1` to update the project index.
- Run `scripts/mxagile-plan.ps1` or `scripts/mxagile-plan-wave.ps1` to generate Mendix MDL scripts.
