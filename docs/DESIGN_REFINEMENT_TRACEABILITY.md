# Design Refinement Traceability

This document outlines the mechanisms for maintaining traceability between design mockups, technical specifications, and implemented Mendix artifacts.

## 1. Baseline Detection
The design baseline is managed by `scripts/refine.py`. This script:
- Parses current HTML mockups within the project structure.
- Compares the current mockup state against the established baseline.
- Generates `mockup-report.md`, which records structural elements and styling properties. This report serves as the source of truth for design validation.

## 2. Change Detection
To detect deviations, we employ a hierarchical hashing mechanism:
- **Mockup Hashing**: A composite hash is generated for each mockup file, incorporating DOM structure and critical CSS properties.
- **YAML Hashing**: A content hash is generated for `Page YAML` files, representing the current Mendix page configuration.
- **Detection Trigger**: Whenever the current hash of a mockup differs from the hash recorded in the last successful refinement run, the system marks the corresponding component for re-evaluation.

## 3. Artifact Graph
Traceability is maintained through a relational graph structure connecting artifacts:

`Mockup` → `Page YAML` → `Requirement` → `Feature Spec` → `Plan` → `Task` → `Mendix Artifact`

- **Nodes**: Represent individual development or design assets.
- **Edges**: Represent explicit dependencies and derivation paths, allowing for precise impact analysis when a node changes.

## 4. Stale Propagation
To ensure consistency, we implement a recursive stale-propagation logic:
1. **Change Identification**: A hash mismatch in an upstream node (e.g., `Mockup`) triggers an invalidation event.
2. **Marking**: The modified artifact is marked as `STALE`.
3. **Recursive Traversal**: The system traverses the Artifact Graph downstream, applying the `STALE` status to all direct and indirect dependents.
4. **Actionable Reporting**: The process culminates in a report listing the impacted artifacts, explicitly identifying which downstream components (e.g., `Tasks`, `Mendix Artifacts`) require manual review or automated re-synchronization.
