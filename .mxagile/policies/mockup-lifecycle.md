# Mockup Lifecycle

Canonical contract for the lifecycle of source and target mockups in MxAgile.

This policy covers both single-file legacy mockups and SPA mockup bundles.
For full SPA bundle contract, see `policies/spa-mockup-bundle.md`.

## Two Mockup Roles

| Role | Description | Mutability |
|---|---|---|
| **Source mockup** | Original artifact as provided by the project/customer, or generated and approved in the UI-Agent Generate cycle | IMMUTABLE — never modified after acceptance |
| **Target mockup** | The active acceptance target used for verification — may be the source or a refined/updated version | UPDATABLE under explicit decision process |

## Lifecycle Status Model

Every revision (SPA bundle) and every named mockup target (single-file) carries a `lifecycle_status`:

| `lifecycle_status` | Meaning |
|---|---|
| `SOURCE` | This revision IS the source (first revision, no accepted refinement yet). The source mockup and target mockup are identical. |
| `REFINED_TARGET` | This is the currently **active** acceptance target. Exactly ONE revision per mockup may carry this status at any time. |
| `SUPERSEDED_TARGET` | A previously active target that has been replaced by a newer `REFINED_TARGET`. Retained for audit; never used for new verification. |

**Transition rules (atomic):**
1. At project start: first revision gets `lifecycle_status: SOURCE` and `active_target: true`.
2. When a refinement is accepted: new revision gets `lifecycle_status: REFINED_TARGET` and `active_target: true`. The previously active revision transitions to `lifecycle_status: SUPERSEDED_TARGET` and `active_target: false`. Both changes happen atomically (enforced by `create_revision.py`).
3. The original `SOURCE` revision is never re-labeled; it remains `SOURCE` and `active_target: false` once superseded.
4. A `REJECTED` revision is never stored in `_history/`. It never receives a `lifecycle_status`.

**Active Target Invariant:** At any point in time, exactly ONE revision per mockup bundle may have `active_target: true`. Violating this invariant is a SCHEMA ERROR, not a recoverable state.

## Refinement Status Model

A proposed refinement goes through the following `refinement_status` states:

| `refinement_status` | Meaning |
|---|---|
| `PROPOSED` | Refinement candidate exists (working bundle changed or single-file target proposed). Not yet developer-accepted. |
| `ACCEPTED` | Developer explicitly accepted this revision (backed by DEC-NNN entry). Only ACCEPTED revisions are archived in `_history/`. |
| `REJECTED` | Developer explicitly rejected this revision. The prior active target remains active. Rejected proposals are NOT stored in `_history/`. |

An agent MAY propose a refinement. An agent MUST NOT claim a revision is ACCEPTED without an explicit developer confirmation backed by a `planning/decisions/DEC-NNN.yml` entry.

## Platform Boundary Scope Rule

Not all screens visible in a source mockup represent fachliche application pages.

**Authentication and session management** are typically delivered by platform modules (e.g. a company authentication module in Mendix). A mockup may contain login, password, or initial-setup screens purely as navigational scaffolding or demo entry points.

**Rules:**
1. Any screen identified as an authentication, password management, or session management page MUST be classified as `platform_boundary: true` in the UI inventory.
2. A `platform_boundary: true` screen is NOT derived as a fachliche application page.
3. A `platform_boundary: true` screen does NOT generate a REQ-NNN, SPEC-NNN, or implementation task.
4. Demo role-switcher screens are classified `platform_boundary: true` — they are test-only mechanisms, not productive login or user management.
5. The project's `source_authority` config may override this classification for specific concerns. Document the override as a DEC-NNN with `decision_type: platform_boundary`.

**Example:** Login, password-reset, and session management pages in a typical enterprise mockup are `platform_boundary: true`. The fachliche role model (e.g. Admin, Coordinator, Contributor, Reviewer) remains fully valid and must be preserved in the Design Contract, requirements, and test contracts.

## Artifact Locations

### Single-File Legacy Mockups

| Artifact | Location | Description |
|---|---|---|
| Source mockup | `input-resources/ui-ux/<name>.html` | Original. Never moved, never modified. |
| Source archive | `input-resources/ui-ux/_archive/<name>_<date>.html` | Previous source versions, timestamped |
| Target mockup | `planning/target-mockups/<PageName>.html` | Active acceptance target; may differ from source |
| Target history | `planning/target-mockups/_history/<PageName>_<date>.html` | Previous accepted target versions |
| UI inventory | `planning/ui-inventory/<PageName>.yaml` | Extracted from the active target (not the source) |
| Parity verification | `planning/parity/<PageName>_parity.yaml` | Verification results against the active target |

### SPA Bundle Mockups

| Artifact | Location | Description |
|---|---|---|
| Source bundle | `input-resources/ui-ux/<mockup-name>/` | Original directory. Never modified after acceptance. |
| Source archive | `input-resources/ui-ux/<mockup-name>_archive/<YYYY-MM-DD>/` | Superseded source versions |
| Target bundle (working) | `planning/target-mockups/<mockup-name>/` | Mutable working target bundle |
| Accepted revision | `planning/target-mockups/<mockup-name>/_history/REV-NNN/` | Immutable accepted revision snapshot |
| Revision manifest | `planning/target-mockups/<mockup-name>/_history/REV-NNN/revision.yaml` | Acceptance metadata, bundle hash, DEC reference |
| UI inventory | `planning/ui-inventory/<PageName>.yaml` | Per-screen inventory; includes `mockup_name`, `target_revision` |
| Parity verification | `planning/parity/<PageName>_parity.yaml` | Per-screen results; includes `mockup_name`, `target_revision` |

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

When refinement produces a materially different accepted design (single-file):
- Create a refined target in `planning/target-mockups/<PageName>.html`
- Record the old target in `planning/target-mockups/_history/` with a date suffix
- Update the UI inventory `target_mockup` field to the new path
- The source mockup remains UNCHANGED
- Record the change in `planning/decisions/DEC-NNN.md` with: what changed, why, who accepted it

When refinement produces a materially different accepted design (SPA bundle):
- Edit the working bundle in `planning/target-mockups/<mockup-name>/`
- Get explicit developer acceptance (see `policies/spa-mockup-bundle.md` Acceptance Lifecycle)
- Record the Decision in `planning/decisions/DEC-NNN.md`
- Run `scripts/create_revision.py` to archive the working bundle as REV-NNN
- Update the UI inventory `target_revision` and `bundle_hash` fields
- The source bundle remains UNCHANGED

Future browser verification MUST use the active target, not the original source, to avoid
comparing against an obsolete design.

## Provenance Fields

In `planning/ui-inventory/<PageName>.yaml`:

**Single-file legacy fields** in `planning/ui-inventory/<PageName>.yaml`:

```yaml
source_mockup: input-resources/ui-ux/customer-newedit.html   # Original, immutable
target_mockup: planning/target-mockups/Customer_NewEdit.html  # Active target for verification
target_mockup_version: "2026-09-15"                           # Date of last accepted change
target_mockup_reason: "Refined after round-1 parity findings — content labels corrected"
```

**SPA bundle fields** in `planning/ui-inventory/<PageName>.yaml`:

```yaml
page_id: PAGE-DASHBOARD
mockup_name: demo-application                                   # Bundle this screen belongs to
source_mockup: input-resources/ui-ux/demo-application/index.html  # Bundle entry point (immutable)
target_revision: REV-005                                       # Latest accepted revision
bundle_hash: sha256:abc123...                                  # Hash of REV-005 bundle
```

In `planning/parity/<PageName>_parity.yaml`:

```yaml
# Single-file legacy:
source_mockup: input-resources/ui-ux/customer-newedit.html
target_mockup: planning/target-mockups/Customer_NewEdit.html

# SPA bundle:
mockup_name: demo-application
target_revision: REV-005
bundle_hash: sha256:abc123...
page_id: PAGE-DASHBOARD
```

When `source_mockup = target_mockup` (single-file) or no `target_revision` set (SPA), no refinement has occurred.

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
4. On acceptance: create/update the target file (single-file) or run `create_revision.py`
   (SPA bundle), update the inventory, record the decision in `planning/decisions/DEC-NNN.md`
5. On rejection: revert to source mockup as target; plan an implementation correction

An agent MUST NOT silently adopt an implementation shortcut as the new target.

## Decision Required Behavior

When source and target mockup conflict without explicit acceptance:
- Record `DECISION REQUIRED: target_mockup_conflict` in `open_items` of the relevant Requirement
- Set `parity.target_mockup_status: conflict` in the UI inventory
- Do NOT proceed with verification until the conflict is resolved

## Version and History Behavior

- Target mockup version (single-file) tracks the date of the last accepted change
- Target revision (SPA bundle) tracks the accepted REV-NNN
- History files and revision directories are NEVER deleted — they are the audit trail of design decisions
- When the source mockup is updated (new version from customer): archive the old source, update `source_mockup` reference, reset `target_mockup`/`target_revision` to the new source
- Do NOT automatically rebase the target against a new source — check for conflicts first

## Gate-to-Ready: Working Target Check (SPA Bundles)

If `development.ui_driven = true` and the project uses SPA bundle mockups:

1. Compute the current working bundle hash for each `mockup_name` using `artifact_hashing.hash_spa_bundle()`.
2. Compare against the `bundle_hash` in the UI inventory for each screen in that bundle.
3. If any working bundle hash ≠ recorded `bundle_hash` → `WORKING_TARGET_UNACCEPTED_DEVIATION`.
4. Gate-to-ready MUST report the deviation and BLOCK until the deviation is resolved by either:
   a. Accepting the change (creating a new REV-NNN via `create_revision.py`), or
   b. Reverting the working bundle to match the last accepted revision.

Gate-to-ready MUST NOT convert an unaccepted working bundle into an accepted revision.
Only `create_revision.py` creates revisions, and only after explicit developer acceptance
backed by a `planning/decisions/DEC-NNN.md` entry.
