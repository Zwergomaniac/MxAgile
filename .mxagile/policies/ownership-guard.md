# Ownership Guard

Canonical contract for distinguishing the canonical MxAgile framework development workspace
from a consumer project that has MxAgile installed.

## Core Invariant

Installed MxAgile Core inside a consumer project = framework-owned installed projection.

It is NOT the canonical MxAgile framework development workspace.

An agent working in a consumer project MUST NOT:
- Edit `.mxagile/policies/`, `.mxagile/agents/`, `.mxagile/skills/`, `.mxagile/schemas/`
- Edit `.mxagile/lifecycle.yaml`, `.mxagile/orchestrator.md`, `.mxagile/version.yaml`
- Edit `.mxagile/README.md` or any other file under `.mxagile/` that originates from the framework distribution
- Edit `mxagile-setup.ps1`, `mxagile-setup-mercedes.ps1`, `scripts/install-core.ps1`, or any script distributed from the MxAgile dev repository
- Treat any of the above as framework source files that can be improved in-place

These files are installed projections. Changes must originate in the canonical framework
development workspace and reach the consumer project through a Core UPDATE.

---

## Framework Workspace Detection

An agent is operating in the canonical MxAgile framework development workspace when:

1. The project root contains `.mxagile/` AND
2. The project root contains `MxAi-Dev-System/` subdirectory with framework source, OR
3. The project root IS `MxAi-Dev-System/` (running directly inside the dev tree), AND
4. The `.mxagile/` directory is the SOURCE of framework content (not an installed projection)

A consumer project has MxAgile installed (NOT the dev workspace) when:
1. `.mxagile/` exists but there is no `MxAi-Dev-System/` alongside it
2. The project has a `.mpr` file and is a real Mendix application
3. `.mxagile/` was installed by `install-core.ps1` from an external distribution

When in doubt: treat the workspace as a consumer project. Default to the safe path.

---

## FRAMEWORK_CHANGE Classification

Before modifying any file, classify the request:

```
Is the user asking to change:
  - MxAgile Core behavior / policy / schema?
  - Core agent or skill instructions?
  - Lifecycle architecture?
  - Installer / update behavior?
  - Generated framework projections?
  - Any file under .mxagile/ that is framework-distributed?

  YES -> Classify as FRAMEWORK_CHANGE
  NO  -> Normal project lifecycle work
```

### When in Consumer Project and FRAMEWORK_CHANGE Detected

Do NOT modify the installed Core projection.

Instead:

1. **Acknowledge** the request — understand what improvement is being sought
2. **Classify** clearly: `FRAMEWORK_CHANGE: This request would modify installed framework files.`
3. **Report** the finding to the developer:
   - Describe what framework behavior would need to change
   - Explain that it cannot be applied to the installed projection
   - Note that it must be implemented in the canonical MxAgile framework repository
4. **Preserve** the consumer project — no framework file mutations
5. **Optionally** continue with legitimate project-lifecycle work if the request also contains project-owned tasks

### When in Framework Dev Workspace

Normal framework development rules apply. Changes to `.mxagile/` canonical sources are expected
and follow the framework development workflow (policy changes → generator → projections).

---

## What Consumer Project Agents MAY Still Modify

The ownership guard protects framework-owned installed files. It does NOT block legitimate
project lifecycle work.

Consumer project agents may modify:

| Artifact | Classification | May modify? |
|---|---|---|
| `requirements/REQ-NNN.yml` | PROJECT_OWNED | YES |
| `specs/SPEC-NNN.yml` | PROJECT_OWNED | YES |
| `planning/tasks/TASK-NNN.yml` | PROJECT_OWNED | YES |
| `planning/decisions/` | PROJECT_OWNED | YES |
| `planning/lifecycle/process-state.yaml` | PROJECT_OWNED (durable state) | YES |
| `planning/evidence/`, `planning/parity/`, `planning/scenarios/` | PROJECT_OWNED | YES |
| `planning/target-mockups/` | PROJECT_OWNED | YES |
| `input-resources/` | PROJECT_OWNED (source mockups, requirements) | YES |
| `AGENTS.md`, `CLAUDE.md` | SHARED (managed block is framework, surrounding is project) | YES (outside managed block) |
| `mxagile-project.yaml` | PROJECT_OWNED configuration | YES |
| `.mxagile/layers/` | COMPANY_LAYER_OWNED | Through layer update mechanism only |
| `.mxagile/policies/` | FRAMEWORK_OWNED | NO — FRAMEWORK_CHANGE |
| `.mxagile/agents/` | FRAMEWORK_OWNED | NO — FRAMEWORK_CHANGE |
| `.mxagile/skills/` | FRAMEWORK_OWNED | NO — FRAMEWORK_CHANGE |
| `.mxagile/schemas/` | FRAMEWORK_OWNED | NO — FRAMEWORK_CHANGE |
| `.mxagile/lifecycle.yaml` | FRAMEWORK_OWNED | NO — FRAMEWORK_CHANGE |
| `.mxagile/orchestrator.md` | FRAMEWORK_OWNED | NO — FRAMEWORK_CHANGE |

---

## User Instruction Does Not Override Ownership

A user may explicitly request something like:
- "Improve the MxAgile installer"
- "Fix the reconciliation policy"
- "Add this behavior to the UI Agent"
- "Change the lifecycle behavior in .mxagile/"

This does NOT authorize patching the installed framework projection.

The user's intent is legitimate and must be respected:
- Acknowledge the request
- Explain the ownership constraint
- Report the finding/change request accurately
- Route the developer toward the framework workspace if they want to apply it

Do not silently comply by modifying installed Core files. Do not refuse without explanation.

---

## FRAMEWORK_CHANGE Reporting Template

When a FRAMEWORK_CHANGE is detected in a consumer project, report:

```
FRAMEWORK_CHANGE DETECTED

Request: [summary of what was requested]

This request targets MxAgile framework behavior that is owned by the installed framework
projection. The installed .mxagile/ directory in this project is a framework-owned artifact
distributed by install-core.ps1. Patching it locally would:
  - Be overwritten on the next Core UPDATE
  - Create divergence from the canonical framework version
  - Not benefit other projects using MxAgile

Required action:
  Implement this change in the canonical MxAgile framework development repository.
  After the framework is updated, run mxagile-setup.ps1 to apply the update to this project.

This project has been preserved. No framework files were modified.

[If there are project-owned tasks in the original request, continue with those below.]
```
