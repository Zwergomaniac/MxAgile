# Evidence Contract

Canonical contract for browser evidence artifacts in MxAgile: what counts as evidence,
how temporary tool output becomes canonical project evidence, and what must be Git-tracked.

## Evidence Is Not the Complete Verdict

A browser screenshot may prove visual state. It does NOT automatically prove:
- Correct rendered text (content parity)
- Correct information hierarchy (structural parity)
- Correct role permissions (role parity)
- Correct interaction behavior (interaction parity)
- Correct responsive transformation (responsive parity)

Screenshots support evidence. They are not the evidence contract itself.

---

## Temporary vs. Canonical Evidence

| Category | Location | Git tracked | Persistence |
|---|---|---|---|
| **Temporary tool output** | `.concord/screenshots/` (gitignored) | NO | Ephemeral — cleared between runs |
| **Canonical project evidence** | `planning/evidence/screenshots/` | YES | Permanent project record |
| **Parity reports** | `planning/parity/` | YES | Permanent project record |
| **Evidence manifests** | `planning/evidence/manifests/` | YES | Permanent project record |
| **Agent scratch** | `.concord/scratch/` (gitignored) | NO | Ephemeral — not relied on after session |

`.concord/` is fully gitignored by project convention. It is for ephemeral runtime and tool output.

Canonical evidence MUST NOT remain in `.concord/` after promotion.

---

## Evidence Promotion Contract

When browser tooling produces temporary screenshots or output:

```
1. Browser/tool produces artifact in .concord/screenshots/ (temporary)
2. MxAgile agent validates the artifact (does it prove what we claim?)
3. For intentionally retained evidence:
   a. Copy to planning/evidence/screenshots/<scenario-id>/<semantic-name>.png
   b. Record in evidence manifest with:
      - artifact_id, type, path, dimension, description
      - provenance (original .concord/ path for audit trail)
      - promoted_at date
4. Reference from parity-verification YAML
5. Temporary copy in .concord/ may be cleaned up
```

### Semantic Naming

Canonical evidence should be identifiable by concept:

```
planning/evidence/screenshots/
  SCN-CUSTOMER-ADMIN-POPULATED/
    visual_desktop_default.png
    content_nav_groups_dom.png     (DOM assertion capture)
    state_empty_form.png
    state_validation_error.png
    responsive_phone_reflow.png
  SCN-CUSTOMER-READONLY-POPULATED/
    role_readonly_display.png
```

Do NOT use timestamps as the primary identifier. Timestamp is metadata in the manifest, not
the filename.

### What to Promote

Promote screenshots when they serve as evidence of:
- Discovery baseline (showing pre-implementation state)
- Parity finding (PASS or FAIL)
- Refinement (showing agreed target)
- Implementation validation (post-implementation state)
- Acceptance (final approved state)
- Regression evidence (documenting known-good state)

Do NOT promote:
- Debug/retry captures
- Ephemeral intermediate steps
- Duplicate screenshots providing no additional information

### Automatic Promotion

The UI-Agent Verifying-Modus is responsible for:
1. Running Playwright scenarios
2. Generating evidence in `.concord/screenshots/`
3. Selecting materially relevant captures
4. Copying them to `planning/evidence/screenshots/<scenario-id>/`
5. Creating or updating the evidence manifest entry
6. Referencing the canonical path in the parity-verification report

Developers are NOT required to manually discover and move timestamped screenshots.

---

## Evidence Manifest

The evidence manifest (`planning/evidence/manifests/<wave-id>-evidence-manifest.yaml`) provides
the canonical index mapping:

```
Requirement / acceptance clause
    -> verification scenario (SCN-...)
    -> role + data state + viewport
    -> parity dimensions verified
    -> evidence artifacts (screenshots, DOM assertions, navigation traces)
    -> parity result
```

Schema: `.mxagile/schemas/evidence-manifest.schema.json`

### Traceability Chain

A complete evidence trace for a UI acceptance clause looks like:

```yaml
# planning/evidence/manifests/W01-evidence-manifest.yaml
entry_id: EVD-SCN-CUSTOMER-ADMIN-POPULATED
scenario_id: SCN-CUSTOMER-ADMIN-POPULATED
screen_id: PAGE-CUSTOMER-OVERVIEW
role: Admin
data_state: populated
viewport: desktop-1440
verified_at: "2026-09-23"
parity_result: FAIL
target_mockup: planning/target-mockups/Customer_Overview.html
parity_report_path: planning/parity/Customer_Overview_parity.yaml
traceability:
  requirements: [REQ-001, REQ-005]
  acceptance_clauses: ["Admin can see all customer records", "Navigation shows Stammdaten group"]
artifacts:
  - artifact_id: EVD-SCREENSHOT-VISUAL-DEFAULT
    type: screenshot
    dimension: visual
    path: planning/evidence/screenshots/SCN-CUSTOMER-ADMIN-POPULATED/visual_desktop_default.png
    description: "Admin overview page - visual baseline"
    passed: true
  - artifact_id: EVD-DOM-NAV-GROUP
    type: dom_text_assertion
    dimension: content
    path: planning/evidence/screenshots/SCN-CUSTOMER-ADMIN-POPULATED/content_nav_groups_dom.png
    description: "Navigation group DOM text - 'Master Data' found where 'Stammdaten' expected"
    passed: false
```

---

## Content Parity Evidence

Screenshot images alone are INSUFFICIENT for content parity. Content parity requires
DOM text assertions.

For each content target (navigation group labels, headings, button captions, etc.):
1. Extract DOM text via Playwright (`page.locator(selector).innerText()`)
2. Assert against expected value from UI inventory / target mockup
3. Record the assertion in the evidence manifest as `dom_text_assertion`
4. Capture a screenshot of the relevant area for visual context

The evidence manifest must record both the DOM assertion result and the screenshot,
clearly linked to the content parity dimension.

---

## Evidence Levels and Promotion

| Evidence Level | Promotion Required | Git Tracked |
|---|---|---|
| STATIC (mockup HTML Playwright) | Mockup files already in `input-resources/ui-ux/` | YES (mockups) |
| MODEL (mxcli inspect) | No screenshots — model inspection output referenced in parity report | YES (parity report) |
| RUNTIME (HTTP reachable, no Playwright) | No promotion needed | N/A |
| BROWSER (Playwright against running app) | Full promotion contract applies | YES (promoted screenshots + manifest) |

BROWSER evidence that is not promoted to `planning/evidence/` is TEMPORARY and provides
no collaboration value after the session ends.

---

## Semantic Evidence Identity

Every promoted evidence artifact must be attributable to:

| Metadata | How Recorded |
|---|---|
| Lifecycle phase | Evidence manifest `entry_id` prefix or scenario context |
| Screen | `screen_id` in manifest entry |
| Role | `role` in manifest entry |
| Data state | `data_state` in manifest entry |
| Viewport | `viewport` in manifest entry |
| Active target | `target_mockup` in manifest entry |
| Parity dimension | `dimension` field in artifact |
| Parity result | `parity_result` + `passed` per artifact |

Do not rely on filenames alone for this metadata.

---

## Non-Promotion Rule

Not every screenshot must be promoted. Do NOT commit transient/debug captures. The evidence
manifest makes intentional retention explicit — if it is not in the manifest, it need not
be committed.

The decision to promote is made by the agent at the time of scenario execution, guided by:
- Does this materially prove a finding (PASS or FAIL)?
- Is this a regression baseline?
- Would a fresh developer/agent need this to understand the current state?

---

## Evidence Lifecycle Stages

Every evidence artifact progresses through a deterministic lifecycle:

```
CAPTURE → EVALUATE → PROMOTE → REFERENCE → SUPERSEDE
```

### CAPTURE

Tool or automation produces an artifact in a temporary location (`.concord/screenshots/`,
Playwright output directory, or other tool-specific working directory).

Temporary artifacts have zero collaboration value after the session ends. They are
ephemeral by design and may be cleaned up without notice.

### EVALUATE

Agent examines the artifact and determines:
- Does it materially prove something (PASS, FAIL, or state transition)?
- Is it a meaningful baseline or regression reference?
- Is it a duplicate of existing evidence with no additional information?

Artifacts that fail evaluation are not promoted. They remain in their temporary location
and may be cleaned up.

### PROMOTE

Evaluated artifacts are copied to their canonical persistent location:
- `planning/evidence/screenshots/<scenario-id>/` for screenshots
- Recorded in the evidence manifest with full provenance metadata

Promotion follows the existing semantic naming and manifest recording rules above.

### REFERENCE

Promoted evidence is referenced from:
- Parity verification reports (`planning/parity/`)
- Acceptance campaign results (`planning/acceptance-campaigns/`)
- GAP records and repair reports
- Wave reports

An evidence artifact not referenced by any active report has no standing in the
verification lifecycle. Unreferenced promoted evidence should be reviewed during
evidence reconciliation.

### SUPERSEDE

When new evidence is collected for the same scenario, dimension, role, and viewport:
1. The new evidence is promoted under the same canonical path (overwriting the file).
2. The evidence manifest entry is updated with the new `promoted_at` date.
3. If historical traceability is required: the old evidence is moved to
   `planning/evidence/screenshots/<scenario-id>/_history/<YYYY-MM-DD>/` before
   the new evidence replaces it.
4. The `_history/` subdirectory preserves traceability without polluting the
   current evidence namespace.

Only evidence explicitly required for traceability (audit, compliance, dispute resolution)
needs to be preserved in `_history/`. Routine supersession may overwrite in place.

---

## Reference vs. Runtime Evidence

Evidence artifacts MUST be distinguishable by source:

| Source | Meaning | Manifest field |
|---|---|---|
| `mockup` | Captured from the target mockup/design rendered in Playwright | `source: mockup` |
| `application` | Captured from the running Mendix application | `source: application` |
| `reference` | External design reference (PDF, image, Figma export) — not runtime-produced | `source: reference` |

`reference` evidence is immutable input material. It MUST NOT be confused with or
overwritten by runtime application evidence. Store reference material in
`input-resources/` (existing convention), not in `planning/evidence/screenshots/`.

When a report cites evidence, the source classification must be unambiguous:
- "Screenshot matches design" requires both `mockup`/`reference` AND `application` artifacts.
- "Application renders correctly" requires `application` evidence only.
- A comparison finding requires evidence from both sides with distinct source tags.

---

## Canonical Evidence Index

A developer or agent seeking the current authoritative UI evidence for a scenario
MUST be able to locate it without knowing which automation tool produced it or
when it was captured.

The canonical evidence index is the **evidence manifest** (`planning/evidence/manifests/`):

```
Developer wants to find: current UI evidence for a specific screen + role
    → Read the active evidence manifest for the current wave
    → Find the entry matching the scenario_id, screen_id, and role
    → Follow the artifact paths to the promoted evidence files
    → The promoted path IS the canonical current location
```

### Index Properties

1. **Single entry point:** The evidence manifest for the active wave is THE index.
   There is no secondary evidence directory structure to discover.
2. **Scenario-indexed:** Evidence is found by scenario context (screen + role + data state),
   not by tool, timestamp, or capture session.
3. **Current by default:** The manifest always points to the latest promoted evidence.
   Historical evidence is in `_history/` subdirectories, not in the main path.
4. **Self-describing:** Each manifest entry carries enough metadata (screen_id, role,
   viewport, parity_result, verified_at) to evaluate relevance without opening the file.

### When No Manifest Exists

If no evidence manifest exists for the active wave, no promoted evidence exists.
Temporary evidence in `.concord/` is not discoverable through the canonical index
by design — it must be promoted first.

---

## Evidence Growth Management

Repeated verification runs MUST NOT create an indefinitely growing undifferentiated
screenshot archive.

### Growth Control Rules

1. **Supersession over accumulation:** New evidence for the same scenario replaces the
   current evidence at the canonical path. It does not create a new timestamped copy
   alongside the old one.

2. **Selective history preservation:** Only preserve historical evidence in `_history/`
   when traceability requires it (audit trail, disputed findings, regression baselines).
   Routine re-verification overwrites in place.

3. **Temporary cleanup:** `.concord/screenshots/` is ephemeral. Agents and tools may
   clean up temporary screenshots after promotion or after determining they are not
   promotable. Do not accumulate sessions of temporary screenshots.

4. **Manifest-driven retention:** If an evidence file is not referenced by any active
   manifest entry, it is a candidate for cleanup. Evidence referenced only by historical
   or superseded manifest entries may be archived or removed per project policy.

5. **Binary evidence economy:** Avoid committing large volumes of binary evidence to Git.
   Promote only meaningful evidence. A full parity run that produces 200 temporary
   screenshots should result in a bounded set of promoted screenshots (typically
   one per scenario × dimension × finding direction), not 200 committed files.
