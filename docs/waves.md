# Planning in Waves

To manage complexity and group related features, MxAgile uses the concept of "Waves". A wave is a collection of specifications (`.spec` files) that are planned and implemented as a single unit.

## How it Works

1.  **Define Specs:** First, create individual `spec` files for each distinct piece of functionality (e.g., a new entity, a new page, a modified process).

2.  **Group in a Wave:** Create a new `.wave` file in the `/waves` directory. This file lists all the `Spec` IDs that should be included in the wave.

    **Example: `waves/WAVE-01_Initial_Features.wave`**
    ```
    ID: WAVE-01
    Description: The first wave, implementing core customer features.
    Spec: SP-001
    Spec: SP-002
    ```

3.  **Update the Index:** Run the trace indexer to make the framework aware of the new wave and its contents.
    ```powershell
    ./scripts/mxagile-build-trace-index.ps1
    ```

4.  **Plan the Wave:** Use the `mxagile-plan-wave.ps1` script with the wave's ID. This script will find all associated specs, process them, and generate a single, combined `.mdl` script for the entire wave.

    ```powershell
    ./scripts/mxagile-plan-wave.ps1 -WaveId WAVE-01
    ```

5.  **Result:** The output will be a file like `planning/plans/WAVE-01.mdl`, which contains all the Mendix changes for the entire wave, ready to be executed.

This approach allows developers to work on small, manageable specs while still delivering larger, coordinated feature sets to the Mendix application.
