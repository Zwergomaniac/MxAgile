# UI Parity

Canonical contract for multi-dimensional UI parity verification in MxAgile.

## Purpose

A single `parity: PASS` recorded under the original single-dimension schema is not equivalent
to seven independent PASS results under this contract. Historical results are preserved under
their original contract semantics using `LEGACY_EVIDENCE`. New results require dimensional
evidence for each applicable dimension.

This policy defines the seven parity dimensions, their canonical statuses, aggregation rules,
evidence requirements, and the mandatory regression scenario.

Full schema: `.mxagile/schemas/parity-verification.schema.json`

Related policies:
- `policies/verification-scenario.md` — material scenario matrix, role/data/viewport coverage, mock-data prerequisites, decomposition, timeout policy
- `policies/evidence-contract.md` — screenshot lifecycle, temporary vs. canonical evidence, evidence manifest, promotion contract
- `policies/observe-before-mutate.md` — enforced lifecycle order: observe → parity → reconcile → refine → implement

---

## The Seven Parity Dimensions

Each dimension is evaluated independently and recorded separately.

| Dimension | What it verifies |
|---|---|
| **visual** | Colors, spacing, layout proportions, visual hierarchy, styling |
| **content** | Rendered text: labels, headings, navigation names, button captions, column headers, placeholders, status values |
| **structure** | Component arrangement: sections, columns, groupings, tab order, component types |
| **state** | UI states: empty, error, loading, selected, disabled, filtered — all documented states from the UI inventory |
| **interaction** | Actions: button clicks, navigation flows, field focus, form submission, selection |
| **responsive** | Behavior at declared viewports: desktop, tablet, phone — layout reflow, overflow, visibility |
| **role** | Role-specific rendering: what each role sees/can do; correct access restriction behavior |

---

## Canonical Dimension Statuses

| Status | Meaning |
|---|---|
| `PASS` | Dimension satisfies the contract for this page at this evidence level |
| `FAIL` | Concrete material deviation found — dimension does NOT satisfy contract |
| `PARTIAL` | Some aspects pass; minor issues found; no material deviations |
| `NOT_VERIFIED` | Not yet checked — no verification has been performed for this dimension |
| `CONFLICT` | Evidence contradicts requirements — requires developer resolution |
| `NOT_APPLICABLE` | Dimension is not relevant for this page or component |
| `LEGACY_EVIDENCE` | Migrated from a pre-dimensional parity record; provenance preserved, not re-verified |
| `STALE` | Was PASS but the active target mockup or requirement has changed since `verified_at` — re-verification required before claiming PASS |

---

## Aggregation Rules

```
overall_result = PASS
    when ALL required dimensions have result = PASS

overall_result = FAIL
    when ANY required dimension has result = FAILED

overall_result = PARTIAL
    when NO required dimension is FAILED
    AND at least one required dimension is PARTIAL or CONFLICT

overall_result = NOT_VERIFIED
    when NO browser verification has been performed
    (all required dimensions are NOT_VERIFIED or LEGACY_EVIDENCE)
```

A required dimension that is `FAILED`, `PARTIAL`, `NOT_VERIFIED`, `CONFLICT`, or `STALE`
**MUST prevent overall PASS**.

`LEGACY_EVIDENCE` dimensions do not prevent overall PASS if the remaining required dimensions
all PASS — but the overall result must note the partial evidence coverage.

`NOT_APPLICABLE` requires a `not_applicable_rationale` in the dimension record. Without rationale,
it is treated as `NOT_VERIFIED`.

---

## Mandatory Regression Scenario: Visual PASS + Content FAIL = Overall FAIL

This scenario must be representable in the framework:

```yaml
# Sidebar: colors are correct but grouping labels are wrong
dimensions:
  visual:
    result: PASS
    evidence:
      - type: screenshot
        description: "Sidebar background color and icon tinting match design"
        passed: true
  content:
    result: FAIL
    deviations:
      - concern: sidebar_grouping_labels
        description: "Navigation group 'Stammdaten' implemented as 'Master Data'; mockup shows German labels throughout"
        severity: material
        dimension: content
overall_result: FAIL
```

This scenario proves that `visual: PASS` does NOT imply `content: PASS` and does NOT imply
`overall: PASS`. Both dimensions must pass independently.

---

## Dimension Evidence Requirements

### visual
Evidence required: screenshot from the running application at the declared viewport.
Must be compared against `target_mockup` reference screenshot.
Screenshot stored under `.concord/screenshots/app/{PageName}_visual.png`.

Key concerns: layout proportions, color application, spacing, visual hierarchy, component
styling, responsive visual adjustments.

### content
Evidence required: browser DOM text extraction (`dom_text` evidence type).

**First-class content targets:**
- Navigation group names
- Navigation item labels
- Page headings and section headings
- Field labels
- Button captions
- Placeholder text
- Status values / badge text
- Column headers (in grids/tables)
- Error and validation messages
- Localized text (verify correct locale is active)

Do NOT accept screenshots alone as content parity evidence. DOM text extraction is required
for content verification because screenshots do not prove exact text rendering.

```yaml
# Example content evidence
content:
  result: FAIL
  evidence:
    - type: dom_text
      selector: ".mx-name-navigationTree1 .mx-group-header"
      expected: "Stammdaten"
      actual: "Master Data"
      passed: false
  deviations:
    - concern: navigation_group_label
      description: "Navigation group label mismatch: expected 'Stammdaten', found 'Master Data'"
      severity: material
      dimension: content
```

### structure
Evidence required: DOM selector checks (`dom_selector` evidence type) + screenshot.

Key concerns: section count and order, component grouping (fields within same section), tab
order, component types match inventory (e.g., List View where grid is expected), widget type
deviations.

### state
Evidence required: Playwright interaction to trigger each documented state + screenshot per state.

All `interaction_states` from the UI inventory must be exercised:
- Empty state
- Error/validation state
- Loading state (where applicable)
- Selected/focused state
- Disabled/read-only mode

```yaml
state:
  result: PASS
  evidence:
    - type: screenshot
      path: ".concord/screenshots/app/Customer_NewEdit_empty.png"
      description: "Empty form state verified"
      passed: true
    - type: interaction_test
      description: "Validation error state triggered by saving empty required field"
      passed: true
```

### interaction
Evidence required: Playwright action execution + navigation flow verification.

All `navigation` entries from the UI inventory must be exercised:
- Button clicks leading to navigation
- Cancel / back navigation
- Form submission flows
- Conditional navigation (where applicable)

### responsive
Evidence required: viewport-specific screenshot + overflow/reflow check.

Required viewports are derived from — not assumed:
- Requirement or Spec declaring responsive behavior
- Active target mockup showing responsive layout
- Declared Company Layer responsive constraints
- Project-declared Playwright config viewport profiles
- Known UI risk areas (e.g., complex grids, dense tables)

Do NOT require desktop + phone unconditionally. A project that has no responsive
requirement has `responsive: NOT_APPLICABLE` for those screens (with rationale).

Key concerns when responsive IS required: no horizontal overflow, column collapse/reflow,
navigation collapse to mobile menu, card layout transformation, touch target sizes.

### role
Evidence required: separate Playwright session per role + DOM comparison.

For each role declared in the page inventory:
- Login as that role
- Verify correct fields/buttons are visible/hidden
- Verify read-only controls vs. editable controls are role-correct
- Verify role-restricted navigation items are absent

---

## Content Parity: Special Cases

### Localization
When the application runs in a specific locale (e.g., de-DE), content verification must
confirm that the rendered text uses the correct locale. The Playwright config locale must
match the project locale. Dom text extraction is in the rendered language.

### Dynamic Content
For fields that display dynamic entity attribute values (not static UI text), content parity
verifies that the correct attribute is bound and that representative data appears, not that
a specific value matches.

### Placeholders
Input field placeholders are content and must match the UI inventory / mockup.
Empty inputs with incorrect placeholder text are a `content: FAIL`.

---

## Legacy Evidence Upgrade

### What NOT to Do

An existing `parity: PASS` result MUST NOT be converted to:

```yaml
dimensions:
  visual: { result: PASS }
  content: { result: PASS }
  structure: { result: PASS }
  state: { result: PASS }
  interaction: { result: PASS }
  responsive: { result: PASS }
  role: { result: PASS }
```

This would fabricate evidence that does not exist.

### What to Do Instead

Migrate the old result to `LEGACY_EVIDENCE` with provenance:

```yaml
dimensions:
  visual:
    result: LEGACY_EVIDENCE
    required: true
    legacy_provenance: "Original parity:PASS recorded 2026-08-15 under single-dimension schema. Screenshot available at .concord/screenshots/app/Page_default.png."
  content:
    result: NOT_VERIFIED
    required: true
    note: "Content dimension did not exist in original schema. Targeted re-verification required."
  structure:
    result: LEGACY_EVIDENCE
    required: true
    legacy_provenance: "Original structural comparison available in planning/ui-inventory/Page_comparison.yaml dated 2026-08-15."
  state:
    result: NOT_VERIFIED
    required: true
  interaction:
    result: NOT_VERIFIED
    required: true
  responsive:
    result: NOT_APPLICABLE
    required: false
    note: "Desktop-only project. Responsive verification not required."
  role:
    result: NOT_VERIFIED
    required: true
overall_result: NOT_VERIFIED
```

Then populate new dimensions only where EXISTING authoritative evidence proves them:
- If a screenshot exists: populate `visual` with `LEGACY_EVIDENCE` + provenance
- If a structural comparison file exists: populate `structure` with `LEGACY_EVIDENCE` + provenance
- For dimensions without existing evidence: set `NOT_VERIFIED` and add to `evidence_upgrade.gaps`

### Upgrade Process

1. **Schema upgrade** — structurally migrate to dimensional schema, set `evidence_upgrade.schema_upgraded: true`
2. **Evidence reconstruction** — populate dimensions where existing evidence exists
3. **Gap identification** — list dimensions requiring re-verification in `evidence_upgrade.gaps`
4. **Targeted re-verification** — run Playwright only for gaps, not the full suite
5. **Completion** — set `evidence_upgrade.reverification_completed: true` when all gaps closed

---

## Parity and the Verification Scenario Matrix

Parity verification is executed through the material scenario matrix, not independently per page.

Each `parity-verification.schema.json` file is produced by a specific verification scenario
(`scenario_id` field). The scenario defines which role, data state, viewport, and dimensions
are in scope. Full scenario contract: `policies/verification-scenario.md`.

A parity record becomes `STALE` when:
- The active target mockup version changes
- The Requirement acceptance clause changes
- The widget/component selection changes materially

STALE required dimensions prevent Full Parity PASS. Targeted re-verification is sufficient.

### Coverage Traceability

Every mandatory UI acceptance clause must map to at least one completed scenario.
Coverage gaps must be visible in `process-state.yaml` under `coverage_matrix_state.uncovered_clauses`.

## Evidence Contract Integration

Parity verification produces evidence artifacts that must be promoted from `.concord/screenshots/`
(temporary, gitignored) to `planning/evidence/screenshots/` (canonical, git-tracked).
A parity PASS without promoted evidence is `NOT_VERIFIED` for collaboration purposes.

The evidence manifest (`planning/evidence/manifests/`) provides the traceability chain:
`Requirement -> scenario_id -> role/data/viewport -> dimensions -> promoted evidence -> result`.

Full evidence contract: `policies/evidence-contract.md`.

---

## Targeted Re-Verification vs. Full Reconciliation

### Lazy Reconciliation

Generate only the missing/stale verification work.

```
For each page:
  1. Load existing parity-verification file (if any)
  2. Identify dimensions with result=NOT_VERIFIED or LEGACY_EVIDENCE
  3. Run Playwright only for those dimensions
  4. Leave validated dimensions untouched
```

Use lazy reconciliation when:
- Existing BROWSER evidence proves some dimensions
- Only specific dimensions were affected by recent changes
- Time or scope constraints apply

### Full Reconciliation

Full reconciliation means **full scope accounting**, not blind re-execution of everything.

```
FULL RECONCILIATION
    = FULL SCOPE ACCOUNTING
    + CONSERVATIVE EVIDENCE REUSE
    + TARGETED RE-VERIFICATION
```

For each existing evidence item, classify it first:

| Classification | Meaning | Action |
|---|---|---|
| `REUSABLE` | Current, authoritative, valid under new contract | Preserve and reference |
| `RECONSTRUCTABLE` | Can be derived from existing artifacts with provenance | Migrate with provenance |
| `LEGACY_INSUFFICIENT` | Exists but does not satisfy the new dimension contract | Targeted re-verification |
| `STALE` | Was valid but target/requirement has changed since `verified_at` | Targeted re-verification |
| `CONFLICTING` | Evidence contradicts requirements or other evidence | Refinement / resolution |
| `MISSING` | No evidence exists for this dimension | Targeted verification |

```
For each page:
  1. Load existing parity-verification file (if any)
  2. Classify each dimension's existing evidence
  3. Preserve REUSABLE dimensions — do NOT re-run them
  4. Reconstruct RECONSTRUCTABLE dimensions with provenance
  5. Run Playwright only for LEGACY_INSUFFICIENT, STALE, and MISSING dimensions
  6. Resolve CONFLICTING dimensions through Refinement
  7. Record new verified_at only for re-verified dimensions
```

Full scope accounting means every required parity dimension and every material scenario
is accounted for — either with valid evidence or with an explicit gap that has been addressed.

It does NOT mean discarding authoritative, current, valid evidence and re-running it
unconditionally.

Use full reconciliation when:
- Significant application changes were made
- Previous evidence is stale or provenance is unclear
- Preparing for a major release or CapTrack full reconciliation run

---

## CapTrack Full-Reconciliation Plan

CapTrack will use full reconciliation on the next acceptance cycle.

The plan:
1. Load all pages from `planning/ui-inventory/`
2. For each page: create or reset the parity-verification file
3. Run Playwright in `authenticated_session_ready` state
4. Verify all 7 dimensions per page
5. Special attention to content dimension (navigation labels, form labels, button captions)
6. Test mandatory regression scenario: visual PASS + content FAIL = overall FAIL
7. Record all results in `planning/parity/` directory
8. Update `process-state.yaml` with parity reconciliation progress

CapTrack is NOT modified in this framework task. The plan applies to the next REAL cycle.

---

## Observe Before Mutate Integration

The parity contract integrates with the Observe-Before-Mutate lifecycle rule:

```
baseline capture (initial parity verification)
    -> complete multi-dimensional parity analysis
    -> identify deviations per dimension
    -> Discovery reconciliation (update inventory if deviations reveal mismatches)
    -> Refinement accepted (updated widget/content choices)
    -> implementation mutation (SCSS, widget changes, content corrections)
```

An agent that modifies SCSS, widgets, or content before completing parity analysis
is in violation of the Observe-Before-Mutate contract.

See `policies/observe-before-mutate.md` for the enforceable lifecycle rule.
