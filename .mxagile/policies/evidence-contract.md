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
