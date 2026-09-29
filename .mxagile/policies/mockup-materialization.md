# Mockup Materialization

Canonical contract for materializing expected UI target states before parity evaluation.

## The Root Gap This Policy Addresses

HTML source code ≠ rendered mockup behavior.

When a mockup contains JavaScript-driven UI state, reading source code alone is insufficient
evidence of what the target UI looks like for a given role, data state, or interaction state.
Parity against a dynamic mockup is only trustworthy when both sides have been observed at
equivalent evidence depth.

Related policies:
- `policies/mockup-analysis.md` — Playwright execution rules for mockup analysis
- `policies/mockup-lifecycle.md` — source vs refined target mockup contract
- `policies/ui-parity.md` — parity dimensions and aggregation
- `policies/verification-scenario.md` — material scenario derivation

---

## Mockup Type Classification

Before using a mockup as a parity target, classify it:

| Type | Description | Evidence Requirement |
|---|---|---|
| `static` | Pure HTML/CSS; no JavaScript that materially changes visible content, layout, or structure | Browser render confirms appearance; no separate JS execution scenarios needed |
| `executable` | JavaScript drives visible UI changes: role-dependent navigation/labels, dynamic content, interaction states, data-dependent layout | Full browser execution required per material scenario; source inspection alone is insufficient |
| `unknown` | Cannot determine from source alone whether JS materially affects UI | Treat as `executable`; execute in browser before classifying |

**Default: treat as `executable`** unless source inspection confirms no JS materially affects the target UI.

Recording in page YAML: `mockup_type: static | executable | unknown`  
Schema: `.mxagile/schemas/page.schema.json`

---

## Static Mockup Behavior

A `static` mockup's target state can be established from a single Playwright render per viewport.
No role-specific or interaction-specific rendering scenarios are required.

Scenarios involving a static mockup do NOT expand into roles × states — only one target materialization
is needed, because the source does not produce role-dependent or state-dependent differences.

A mockup that appears static but has role-dependent CSS visibility (e.g., `display:none` toggled by a
class injection) is `executable` — CSS class manipulation via JavaScript is a material change.

---

## Executable Mockup Contract

When `mockup_type = executable`, source-code reading alone is insufficient for target evidence.

Required: browser execution via Playwright (or equivalent renderer) for each **materially distinct**
scenario before parity evaluation begins.

"Materially distinct" follows the same principle as for the application scenarios:
- Two roles that produce identical rendered output → one materialization sufficient
- Two roles that differ in navigation grouping, visible labels, or actions → separate materializations required

Do NOT blindly materialize: every role × every state × every viewport.
Derive the material target scenario matrix first (see Material Target Scenario Derivation below).

---

## Material Target Scenario Derivation

For an executable mockup, determine which scenarios produce materially different rendered output:

1. Inspect the source: what JavaScript conditions change visible content, layout, or navigation?
2. Enumerate the conditions: roles, data states, interaction states, viewports
3. Test pairs of conditions: do role A and role B produce the same rendered DOM? Same navigation labels?
4. Require separate materialization ONLY where rendering differs materially

This mirrors `policies/verification-scenario.md — Role Coverage Model` but applies to the mockup side.

---

## Target Evidence Bundle

Before a material parity scenario is evaluated, a **target evidence bundle** must exist:

A target evidence bundle for a scenario is the minimum set of mockup-side evidence that establishes
the expected state with sufficient specificity for the required parity dimensions:

| Parity Dimension | Required Target Evidence |
|---|---|
| visual | Rendered screenshot at declared viewport |
| content | DOM/text assertions for all relevant labels, navigation names, headings, captions |
| structure | DOM selector snapshot of component hierarchy / navigation grouping |
| state | Screenshot + DOM snapshot per relevant interaction state |
| interaction | Recorded navigation trigger → expected outcome |
| responsive | Rendered screenshot at each relevant viewport |
| role | Rendered DOM per materially distinct role |

Evidence is only required for the dimensions the scenario covers.
A visual-only scenario needs only a rendered screenshot. A content scenario needs DOM text assertions.

---

## Below-the-Fold Evidence

Screenshots capture only what is visible in the configured viewport at the moment of capture.

**`NOT VISIBLE IN SCREENSHOT ≠ DOES NOT EXIST`**

When content/structure parity dimensions are being evaluated:
- Use DOM queries (not only screenshots) for navigation groups, sidebar items, and any content that
  may extend below the current viewport
- DOM selectors and `innerText()` queries operate on the full document, not just the visible area
- For structure parity, capture the complete navigation tree via DOM, not a viewport screenshot
- For responsive parity, verify that content reflows correctly — do not rely on a single phone-width
  screenshot to prove all required content is present and accessible

Below-the-fold evidence must be captured explicitly when:
- Navigation contains items that may be scrolled off-screen at the tested viewport height
- Sidebar labels appear in a scrollable container
- Card/list content extends beyond the screenshot area
- Any Requirement references content that is not guaranteed visible at default viewport scroll

---

## Equivalent State Enforcement

A valid parity comparison must verify equivalent scenarios on both sides:

```
TARGET SIDE:
  screen
  role (or "all roles" if static)
  data state (or "no data required" if static)
  viewport
  interaction state

ACTUAL SIDE:
  same screen
  same role
  same data state (representative mock data loaded)
  same viewport
  same interaction state
```

Do NOT compare:
- Default mockup state (no role, no data) against a role-specific populated application state
- Desktop mockup viewport against mobile application state
- Unauthenticated mockup view against authenticated application session

The scenario definition (`verification-scenario.schema.json`) records both sides implicitly through
the shared `scenario_id`. Both target evidence and actual evidence reference the same scenario.

---

## Target vs Actual Evidence Separation

The evidence manifest must explicitly distinguish:

```yaml
target_evidence:           # collected from the mockup / active target
  - type: screenshot
    source: mockup
    path: planning/evidence/screenshots/target/<scenario-id>/visual_desktop.png
  - type: dom_text_assertion
    source: mockup
    selector: ".mx-group-header"
    expected: "Stammdaten"

actual_evidence:           # collected from the running application
  - type: screenshot
    source: application
    path: planning/evidence/screenshots/actual/<scenario-id>/visual_desktop.png
  - type: dom_text_assertion
    source: application
    selector: ".mx-name-navigationTree1 .mx-group-header"
    actual: "Master Data"
```

A future developer or agent must be able to determine from the manifest:
- What was expected (target evidence)
- What was observed (actual evidence)
- Why the comparison result was PASS or FAIL

Full manifest schema: `.mxagile/schemas/evidence-manifest.schema.json`

---

## Authoritative Context Before Parity

Before determining a difference between target and actual is a defect, resolve the applicable
authoritative context from canonical sources, in priority order:

1. **Requirement** — does a Requirement specify the expected behavior?
2. **Spec** — does a Spec clarify the implementation target?
3. **Accepted Decision** — is there a Decision that resolved this question previously?
4. **Active refined target mockup** — if Refinement produced a refined target, that is authoritative
5. **Source mockup** — if no refined target exists, source is the active target
6. **Company Layer constraints** — override mockup preferences for UI component selection

Use the existing source-priority contract (`policies/source-priority.md`) when sources conflict.

A difference that is explained by an accepted Decision or a Company Layer constraint is NOT a parity
defect — it should be recorded as `PASS` with a rationale note, not as `FAIL`.

---

## Legacy Mockup Evidence Reconciliation

Existing screenshot libraries in legacy locations (e.g., `.concord/screenshots/mockup/`, old project
snapshot directories) must not be silently ignored or deleted during reconciliation.

Apply the general legacy evidence classification from `policies/project-knowledge.md`:

| Classification | Action |
|---|---|
| `HISTORICAL_EVIDENCE` (useful, unique) | Promote to `planning/evidence/screenshots/target/<scenario-id>/` with provenance |
| `DUPLICATE` (canonical copy exists) | Prove equivalence; keep canonical; remove after validation |
| `STALE` (target/source has since changed) | Do not promote as-is; re-materialize if needed |
| `UNKNOWN` | Preserve; classify before cleanup |

Record provenance in the evidence manifest: original path, capture date (if determinable), associated
scenario, and classification reasoning.

---

## Discovery Integration

When Discovery encounters an executable mockup:
- Classify the mockup type during UI-Agent Analyze mode
- Record `mockup_type` in the page YAML
- For executable mockups, execute in Playwright per material target scenario
- Record discovered dynamic states as `interaction_states` in the page YAML
- Do NOT mark Discovery complete when known dynamic states remain unobserved

For existing projects:
- Reconcile existing Discovery — do NOT restart
- Missing target-state knowledge reopens only the affected Discovery scope
- If existing Discovery already captured the rendered states, classify as REUSABLE

---

## Refinement Integration

If browser execution of an executable mockup reveals information that source-code inspection missed
(e.g., navigation grouping differs by role):

```
Reconcile affected Discovery
    ->
Apply source priority (policies/source-priority.md)
    ->
Reopen affected Refinement only if an actual target decision is required
```

Do NOT reopen unrelated accepted Refinement. A new rendering finding that confirms an existing
accepted decision does not reopen Refinement.

---

## Source/Target Change Invalidation

When the active target mockup changes in a way that materially affects a scenario:
1. Mark affected target evidence as `STALE`
2. Mark dependent parity records as `STALE`
3. Re-materialize only the affected scenario(s)
4. Do NOT invalidate unrelated target evidence

This follows the existing `STALE` status contract in `policies/ui-parity.md`.
