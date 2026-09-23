# Mockup Lifecycle

Canonical contract for the lifecycle of source and target mockups in MxAgile.

## Two Mockup Roles

| Role | Description | Mutability |
|---|---|---|
| **Source mockup** | Original artifact as provided by the project/customer, or generated and approved in the UI-Agent Generate cycle | IMMUTABLE — never modified after acceptance |
| **Target mockup** | The active acceptance target used for verification — may be the source or a refined/updated version | UPDATABLE under explicit decision process |

## Artifact Locations

| Artifact | Location | Description |
|---|---|---|
| Source mockup | `input-resources/ui-ux/<name>.html` | Original. Never moved, never modified. |
| Source archive | `input-resources/ui-ux/_archive/<name>_<date>.html` | Previous source versions, timestamped |
| Target mockup | `planning/target-mockups/<PageName>.html` | Active acceptance target; may differ from source |
| Target history | `planning/target-mockups/_history/<PageName>_<date>.html` | Previous accepted target versions |
| UI inventory | `planning/ui-inventory/<PageName>.yaml` | Extracted from the active target (not the source) |
| Parity verification | `planning/parity/<PageName>_parity.yaml` | Verification results against the active target |

## Source Mockup Contract

The source mockup is the evidence of customer/project intent.

- NEVER modify a source mockup after it has been accepted
- NEVER use a source mockup as the rendering target for autonomous refinements
- Move superseded source mockups to `_archive/` with a date suffix
- Source mockup provenance is recorded in the UI inventory `source_mockup` field
- The source mockup is always the authoritative reference for scope disputes

## Target Mockup Contract

The target mockup is the active binding reference for implementation and verification.

On project start:
- Target mockup = source mockup (no distinction needed)
- Record `target_mockup: input-resources/ui-ux/<name>.html` in the UI inventory

When refinement produces a materially different accepted design:
- Create a refined target in `planning/target-mockups/<PageName>.html`
- Record the old target in `planning/target-mockups/_history/` with a date suffix
- Update the UI inventory `target_mockup` field to the new path
- The source mockup remains UNCHANGED
- Record the change in `sprints/decisions.md` with: what changed, why, who accepted it

Future browser verification MUST use the active target, not the original source, to avoid
comparing against an obsolete design.

## Provenance Fields

In `planning/ui-inventory/<PageName>.yaml`:

```yaml
source_mockup: input-resources/ui-ux/customer-newedit.html   # Original, immutable
target_mockup: planning/target-mockups/Customer_NewEdit.html  # Active target for verification
target_mockup_version: "2026-09-15"                           # Date of last accepted change
target_mockup_reason: "Refined after CapTrack round-1 parity findings — content labels corrected"
```

In `planning/parity/<PageName>_parity.yaml`:

```yaml
source_mockup: input-resources/ui-ux/customer-newedit.html
target_mockup: planning/target-mockups/Customer_NewEdit.html  # What was verified against
```

When `source_mockup = target_mockup`, no refinement has occurred.

## Source-Priority Resolution for Mockup Conflicts

When source mockup and target mockup differ:

- **Visual and interaction decisions**: target mockup is authoritative (it incorporates accepted refinements)
- **Scope disputes**: source mockup is authoritative (it reflects original customer intent)
- **Content disputes**: requires explicit developer/customer decision if target differs from source

A conflict between source and target mockup that was not explicitly decided is a
`DECISION REQUIRED` item, not a silent override.

## Autonomous Refinement

The UI-Agent MAY propose a refined target mockup when:
- Parity analysis reveals a deviation between source mockup and implemented reality
- The implemented version satisfies the business contract but differs from the source visual
- The deviation is minor and within the project's accepted visual tolerance

Autonomous refinement process:
1. Propose the refined target to the developer
2. Show the diff between source mockup and proposed target
3. Wait for developer acceptance
4. On acceptance: create the target file, update the inventory, record the decision
5. On rejection: revert to source mockup as target; plan an implementation correction

An agent MUST NOT silently adopt an implementation shortcut as the new target.

## Decision Required Behavior

When source and target mockup conflict without explicit acceptance:
- Record `DECISION REQUIRED: target_mockup_conflict` in `open_items` of the relevant Requirement
- Set `parity.target_mockup_status: conflict` in the UI inventory
- Do NOT proceed with verification until the conflict is resolved

## Version and History Behavior

- Target mockup version tracks the date of the last accepted change
- History files are NEVER deleted — they are the audit trail of design decisions
- When the source mockup is updated (new version from customer): archive the old source, update `source_mockup` reference, reset `target_mockup` to the new source
- Do NOT automatically rebase the target against a new source — check for conflicts first
