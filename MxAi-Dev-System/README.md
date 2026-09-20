# MxAgile Framework

Welcome to MxAgile, a framework for specification-driven, Mendix-native application development powered by AI agents.

## Core Engineering Tools

MxAgile uses `mxcli` as its core engineering layer. 

*Note: The current `mxcli.exe` binary in the root will be migrated to a fully reproducible download/bootstrap process in a future development phase.*

## Core Concepts

MxAgile is built on a few key principles to ensure a traceable, verifiable, and maintainable development lifecycle:

*   **Mockup-Driven:** Development starts with simple HTML mockups that define the UI and user interaction.
*   **Living Specifications:** Requirements are captured in "living" specification documents that evolve with the project but serve as a stable contract for implementation.
*   **Refinement Engine:** Changes to mockups or requirements trigger a refinement process that analyzes the impact of the change, preventing uncontrolled, breaking changes downstream.
*   **Script-Driven Orchestration:** The workflow is orchestrated by a series of PowerShell scripts (`mxagile-*.ps1`) that prepare and manage tasks for AI agents.
*   **Mendix-Native:** The framework is built for Mendix and uses `mxcli` and MDL as its core engineering layer.

For a deep dive into the architecture, see the [MxAgile Major Evolution document](./majorchange.md).

## Getting Started

Setting up a project with MxAgile is designed to be simple.

### Agent Environment Synchronization

**IMPORTANT:** Whenever changes are made within the `.mxagile/` directory, you MUST run the generator script to synchronize your agent environment:

```powershell
.\scripts\generate-mxagile-platform-skills.ps1
```

This ensures that agent configurations (`.claude/`, `.github/`, `.agents/`, etc.) stay in sync with the core platform definitions.

### Prerequisites

*   Python 3.8+ (with Pip)
*   Git

### Installation

1.  Clone this repository to your local machine.
2.  Open a PowerShell terminal in the project root directory.
3.  Run the appropriate installer script:

    *   **Generic MxAgile:**
        ```powershell
        .\install-mxagile.ps1
        ```

    *   **Mercedes-Benz Environment:**
        ```powershell
        .\install-mxagile-mercedes.ps1
        ```

These scripts use the canonical Core URL (`https://github.com/Zwergomaniac/MxAgile.git`) by default.

## Basic Workflow

The high-level workflow in MxAgile follows these steps:

1.  **`init`**: Initialize the project structure.
2.  **Create Mockups**: Add HTML mockups to `input-resources/ui-ux/`.
3.  **`refine`**: Run the refinement engine to analyze mockup changes and their impact.
4.  **Create Specs**: Group requirements into feature specifications in the `specs/` directory.
5.  **`plan` & `tasks`**: Use the planning scripts to generate an implementation plan and decompose it into actionable tasks for an AI agent.
6.  **Implement**: Use an AI agent, guided by the prepared tasks, to write Mendix MDL scripts.
7.  **Validate & Converge**: Use the framework's validation and convergence scripts to ensure the implementation meets the specification.

## Key Scripts

The core workflow is driven by PowerShell scripts located in the `/scripts` directory. The most important ones are:

*   `mxagile-init.ps1`: Sets up a new project.
*   `mxagile-refine.ps1`: Analyzes changes in mockups.
*   `mxagile-check-quality.ps1`: Runs quality checks against a specification file.
*   `mxagile-plan.ps1`: Generates an implementation plan for a spec.
*   `mxagile-trace.ps1`: Traces the relationships between different artifacts (e.g., requirements, specs, tasks).

## Directory Structure

*   `.mxagile/`: Contains the core framework configuration, state, and company layers.
*   `input-resources/`: Your source materials, including HTML mockups in `ui-ux/`.
*   `requirements/`: Contains atomic, testable requirement files.
*   `specs/`: Contains "living specification" files that group requirements into features.
*   `planning/`: Contains generated plans and tasks.
*   `scripts/`: Contains all the PowerShell and Python scripts that drive the framework.

## Further Reading

*   **Installation Guide:** [./docs/installation.md](./docs/installation.md)
*   **Company Layers Guide:** [./docs/company-layers.md](./docs/company-layers.md)
*   **Planning with Waves:** [./docs/waves.md](./docs/waves.md)

