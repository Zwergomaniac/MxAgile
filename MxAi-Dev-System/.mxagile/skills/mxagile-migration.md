---
name: mxagile-migration
description: Guides the migration of project artifacts from legacy planning structures (planning/stories, planning/checklists) to the MxAgile framework (requirements/, planning/tasks/).
triggers:
  - "migrate project"
  - "migrate story"
  - "migration guide"
---

# MxAgile Migration Skill

This skill provides a structured process to migrate legacy project artifacts to the MxAgile framework.

## Migration Process

1. **Assessment & Analysis**
   - List all files in `planning/stories/` and `planning/checklists/`.
   - Read files to understand content and dependencies.

2. **Mapping**
   - Map each story from `planning/stories/` to a structured format in `requirements/`.
   - Map each checklist from `planning/checklists/` to a task definition in `planning/tasks/`.

3. **Proposed Plan**
   - Present the plan to the human, highlighting any manual decisions required (e.g., mapping ambiguity).
   - Ask for approval before proceeding.

4. **Execution & Cleanup (Post-Approval Only)**
   - Perform the migration by creating new files in `requirements/` and `planning/tasks/`.
   - Verify the new files using `mxcli check` if applicable.
   - *Only after* successful verification and user explicit confirmation, delete the original files in `planning/stories/` and `planning/checklists/`.

## Guidelines

- **Manual Decisions**: If an artifact cannot be mapped automatically, describe the ambiguity clearly to the human and wait for clarification.
- **Human Approval**: Mandatory for the final move/deletion step.

## Safety Policy

- **Do not delete any source files** under `planning/` until the migration is validated and explicitly approved by the user.
