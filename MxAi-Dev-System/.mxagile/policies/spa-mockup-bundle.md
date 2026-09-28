# SPA Mockup Bundle

Canonical contract for SPA (Single Page Application) mockup bundles in MxAgile.

## The SPA Bundle Model

A MxAgile mockup is a complete executable SPA prototype bundle — NOT a collection of independent HTML files.

| Concept | Description | Lifecycle unit |
|---|---|---|
| **Mockup Bundle** | Complete executable SPA directory: `index.html`, `js/`, `css/`, `assets/`, etc. | Versioning unit (REV-NNN) |
| **Screen / Page** | A logical application screen navigable within the bundle | Traceability unit (PAGE-NNN) |
| **Flow** | A navigation path through multiple screens | Impact analysis label (FLOW-ID) |

**One bundle = one revision chain.** Multiple independent bundles in one project each have their own revision chain.

**One screen = one PAGE-NNN identifier.** Screen identity is stable across bundle revisions. PAGE-CALENDAR remains PAGE-CALENDAR in REV-001 through REV-010.

## Source Bundle

The source bundle is the original customer/project-supplied or agent-generated mockup. It is IMMUTABLE after acceptance.

```
input-resources/
  ui-ux/
    <mockup-name>/          # Source bundle (immutable)
      index.html
      js/
      css/
      assets/

    <mockup-name>_archive/  # Superseded source versions
      <date>/
        index.html
        ...
```

Source bundle archival: when a new source version arrives, move the old source to `_archive/<mockup-name>_<YYYY-MM-DD>/` before updating. Do NOT silently overwrite.

A new source version MUST NOT automatically rebase an accepted target revision. Source and target authority remain independent.

## Target Bundle

The target bundle is the mutable working acceptance target. It begins as a copy of the source and may be refined through the Autonomous Refinement process.

```
planning/
  target-mockups/
    <mockup-name>/          # Mutable working target bundle
      index.html
      js/
      css/
      assets/

      _history/             # Immutable accepted revisions (never delete)
        REV-001/
          index.html
          js/
          css/
          assets/
          revision.yaml     # Revision manifest (see schemas/revision.schema.json)

        REV-002/
          ...
          revision.yaml
```

## Working State vs. Accepted Revision

| State | Description | Where | Mutable |
|---|---|---|---|
| **Working target** | Current active bundle being refined | `planning/target-mockups/<mockup-name>/` | YES — edited during Refinement |
| **Accepted revision** | Immutable snapshot of an accepted working state | `planning/target-mockups/<mockup-name>/_history/REV-NNN/` | NO — never modified after creation |

**Intermediate working edits do NOT create revisions.** Multiple HTML/JS/CSS edits during an active Refinement session are all working-state changes. Only explicit developer acceptance creates exactly one new REV-NNN.

**Gate-to-ready check:** if the working target bundle hash differs from the latest accepted revision hash, the working target has unaccepted changes. Gate-to-ready MUST report `WORKING_TARGET_UNACCEPTED_DEVIATION` and BLOCK. It does NOT convert working state into an accepted revision.

## Acceptance Lifecycle

```
Developer proposes UI change
  -> Agent proposes target bundle edit
  -> Developer reviews diff
  -> Developer accepts
  -> Decision recorded in planning/decisions/DEC-NNN.md
  -> create_revision.py archives working bundle as REV-NNN
  -> revision.yaml created with bundle_hash, acceptance_decisions: [DEC-NNN], lifecycle_trigger: refinement_accepted
  -> UI inventory updated: target_revision: REV-NNN, bundle_hash: sha256:...
  -> Gate-to-ready passes revision check
```

Only the `create_revision.py` script creates revisions. Agents and gates reference revisions; they do NOT create them.

## Bundle Hash Algorithm

The bundle hash provides deterministic, platform-independent identity for a complete bundle state.

**Algorithm (SHA-256 sorted manifest):**

1. Enumerate all files in the bundle directory recursively.
2. **Exclude:** `revision.yaml`, `_history/` directory and its contents.
3. For each included file:
   a. Compute `rel_path` = canonical relative path from bundle root, forward slashes, no leading `./`.
   b. Compute `file_hash` = SHA-256 of raw file bytes (binary mode, no line-ending normalization).
4. Sort all `(rel_path, file_hash)` pairs by `rel_path` (lexicographic ascending).
5. Build manifest string: join `<rel_path>:<file_hash>` lines with `\n`.
6. Compute bundle_hash = SHA-256 of the UTF-8 encoded manifest string.
7. Format: `sha256:<hex_digest>`.

**What is included:**
- `index.html` and all `.html` files
- All `.js`, `.css` files
- All image/binary assets (`*.png`, `*.jpg`, `*.svg`, `*.ico`, `*.woff`, `*.woff2`, etc.)
- JSON data/config files bundled with the mockup
- Any other file directly owned by the mockup

**What is excluded:**
- `revision.yaml` (manifest itself — circular)
- `_history/` directory (archived revisions — not part of the working bundle)
- `node_modules/` (external dependencies — not mockup-owned content)
- `.DS_Store`, `Thumbs.db`, OS metadata files
- Editor swap files (`*.swp`, `~*`)

**Line-ending behavior:** raw bytes are hashed without normalization. The algorithm is portable: the same files produce the same hash on Windows and Linux because raw bytes are used.

**Implementation:** `scripts/artifact_hashing.py` — `hash_spa_bundle(bundle_dir, exclude_revision_yaml=True)`.

## Screen Identity

PAGE-NNN identifiers are assigned during UI-Agent Analyze mode and remain stable across all revisions of the bundle. A screen does not change its PAGE-NNN because the bundle was revised.

```
REV-001: PAGE-CALENDAR, PAGE-CHILD-DETAIL, PAGE-DASHBOARD
REV-005: PAGE-CALENDAR, PAGE-CHILD-DETAIL, PAGE-DASHBOARD  <- same IDs
```

New screens added in a revision receive new PAGE-NNN IDs. Removed screens are marked superseded in the UI inventory.

## SPA Navigation and Entry Point

The entry point is normally `index.html`. The UI-Agent MUST:
1. Launch Playwright against the bundle entry point (NOT open each `.html` independently).
2. Navigate within the SPA to discover screens.
3. Assign and record a stable PAGE-NNN for each discovered logical screen.

Opening individual HTML files within a SPA bundle as independent mockups is INCORRECT. The bundle must be launched from its entry point to observe correct navigation, state, and JavaScript behavior.

## Impact Scope and Staleness

When a revision is accepted with `impact_scope: targeted`, only evidence for screens listed in `affected_screens` becomes STALE.

When `impact_scope: full` or `cross_cutting`, all evidence for the bundle becomes STALE.

When `impact_scope: unknown` (default), treat as `full` — conservative.

An agent may PROPOSE `targeted` or `non_material` impact classification. It MUST NOT unilaterally apply this classification to preserve evidence when product authority is changing. The developer must CONFIRM non-material classification explicitly in the DEC record.

## Flow Labels

Navigation flows may be labeled with a `flow_id` string on `navigation[]` entries in page inventory YAMLs:

```yaml
navigation:
  - action_id: ACT-CALENDAR-FILTER
    leads_to_page: PAGE-CALENDAR
    flow_id: FLOW-CALENDAR-NAVIGATION
    condition: null
```

`flow_id` is an optional label, NOT an independent artifact type. It enables `affected_flows` reporting in revision.yaml without requiring a separate artifact catalog.

## Single-File Legacy Compatibility

Projects with single-file `.html` mockups (pre-SPA model) continue to work using existing fields:
- `source_mockup: input-resources/ui-ux/<name>.html`
- `target_mockup: planning/target-mockups/<PageName>.html`
- `target_mockup_version: YYYY-MM-DD`

Single-file mockups do NOT have `mockup_name`, `target_revision`, or `bundle_hash`. The revision model ONLY applies to SPA bundle projects.

Mixed projects (some SPA bundles, some single-file) are valid. Each mockup type uses its own fields.

## UI Inventory Fields for SPA Bundles

For screens inside a SPA bundle, the page inventory YAML must include:

```yaml
page_id: PAGE-CALENDAR
mockup_name: kidscompass-web          # bundle this screen belongs to
target_revision: REV-005              # last accepted revision
bundle_hash: sha256:abc123...         # hash of REV-005 bundle
source_mockup: input-resources/ui-ux/kidscompass-web/index.html  # bundle entry point
```

`source_mockup` for SPA screens points to the bundle entry point (`index.html`), not a per-screen file. The `page_id` is the screen's stable identity within the bundle.

## Multiple Bundles

A project may have multiple independent mockup bundles:

```
input-resources/ui-ux/
  admin-portal/       # bundle 1
  user-app/           # bundle 2

planning/target-mockups/
  admin-portal/       # working target for bundle 1
  user-app/           # working target for bundle 2
```

Each bundle has its own `_history/REV-NNN/` revision chain. Revisions in one bundle do not affect the other.
