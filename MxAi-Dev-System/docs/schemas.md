# MxAgile Canonical Artifact Schemas

This document defines the standard structure for the YAML-based lifecycle artifacts used in the MxAgile framework. These schemas are used by the `build_artifact_index.py` script to construct the project's traceability graph.

## General Principles

- All artifacts **must** have a unique `ID` field. This ID is the primary key for the artifact in the trace index.
- All other fields are optional unless specified.
- Relationships between artifacts are defined using keys that reference the `ID` of another artifact.

---

## Page (`pages/*.yml`)

Represents a UI page, screen, or significant component described in a mockup.

**Fields:**

- `ID` (string, required): The unique identifier for the page (e.g., `PAGE-01`).
- `description` (string): A brief description of the page's purpose.
- `sourceMockup` (string): The path to the source HTML mockup file.

**Example:**
```yaml
ID: PAGE-01
description: "The main customer dashboard page."
sourceMockup: "mockups/dashboard.html"
```

---

## Requirement (`requirements/*.yml`)

Represents an atomic, testable requirement.

**Fields:**

- `ID` (string, required): The unique identifier for the requirement (e.g., `REQ-01`).
- `description` (string): The requirement text, often in the format "As a [role], I want [action], so that [value]".
- `derivedFrom` (string): The `ID` of the `Page` artifact this requirement originates from. This creates a `DERIVED_INTO` edge in the graph (`Page -> Requirement`).

**Example:**
```yaml
ID: REQ-01
description: "The user must be able to see a list of their recent orders on the dashboard."
derivedFrom: PAGE-01
```

---

## Spec (`specs/*.yml`)

Represents a feature specification that groups one or more requirements into a logical unit of work.

**Fields:**

- `ID` (string, required): The unique identifier for the spec (e.g., `SPEC-01`).
- `description` (string): A brief description of the feature to be implemented.
- `requirements` (list of strings): A list of `ID`s for all the `Requirement` artifacts that this spec implements. This creates `IMPLEMENTED_BY` edges in the graph (`Requirement -> Spec`).

**Example:**
```yaml
ID: SPEC-01
description: "Build the 'Recent Orders' widget on the customer dashboard."
requirements:
  - REQ-01
```

---

## Task (`planning/tasks/*.yml`)

Represents a concrete, actionable task for a developer or agent to execute.

**Fields:**

- `ID` (string, required): The unique identifier for the task (e.g., `TASK-01`).
- `description` (string): A description of the work to be done.
- `spec` (string): The `ID` of the `Spec` artifact this task helps to implement. This creates an `IMPLEMENTED_BY` edge in the graph (`Spec -> Task`).

**Example:**
```yaml
ID: TASK-01
description: "Create the datasource microflow and list view for the 'Recent Orders' widget."
spec: SPEC-01
```