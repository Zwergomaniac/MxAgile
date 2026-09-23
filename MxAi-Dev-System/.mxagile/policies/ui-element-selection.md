# UI Element Selection

Canonical contract for selecting Mendix UI elements during Discovery, Refinement, and
Implementation. Prevents premature widget lock-in and ensures selections satisfy the full
UI contract, not just the data shape.

## The Principle

**SELECT BY USER INTENT AND UI CONTRACT.**
**NOT by data shape alone.**
**NOT by implementation convenience.**
**NOT by Mendix default.**

An entity attribute does NOT imply a Text Box.
Multiple objects do NOT imply Data Grid 2.
A read-only value does NOT imply a disabled input.

The selection process is always:

```
1. What does the user need to perceive?
2. What does the user need to do?
3. Is the content editable or display-only?
4. What information hierarchy, density, and responsive behavior is intended?
5. What interaction occurs on selection, filtering, sorting?
6. What role-specific behavior exists?
7. What does the mockup visually communicate?
8. Which Company Layer / design-system components are available?
   → Only then: propose a Mendix implementation pattern.
```

---

## Separate UI Pattern from Mendix Widget

Discovery identifies the **UI Pattern** before naming a widget.

### UI Pattern Examples

| Pattern | Description |
|---|---|
| `dense_analytical_table` | Column-aligned, sortable, filterable, paged — desktop-oriented |
| `compact_comparison_matrix` | Fixed rows/columns, cell values, no standard paging |
| `responsive_record_list` | Repeated records, adapt from multi-column desktop to single-column mobile |
| `card_collection` | Visual cards with image/icon, title, summary — not tabular |
| `kpi_tile_group` | Metric values, labels, trend indicators — not a grid |
| `timeline` | Events in chronological order, typically vertical |
| `master_detail_explorer` | List/tree on left, detail panel on right |
| `form` | Labeled input fields, structured editing, save/cancel actions |
| `read_only_detail_panel` | Display of a single record's attributes — no editing affordance |
| `label_value_summary` | Short list of key:value pairs — no table chrome needed |
| `editable_inline_table` | Table with inline editing per row |
| `selection_list` | Pick one or more items from a list |
| `filter_bar` | Filter/search controls above a content area |
| `hierarchical_tree` | Parent/child navigation structure |
| `dashboard_chart` | Chart/graph representation of data |
| `status_summary` | Icons or badges summarizing current state per item |

A UI pattern is NOT yet a Mendix widget. Do NOT skip from pattern identification
directly to a widget name.

---

## Widget Suggestions Are Hypotheses

When a Mendix widget is proposed during Discovery or Analyze, record it as:

```yaml
widget_candidate: "DataGrid2"
candidate_confidence: preliminary
```

NOT as a decided implementation, until the proposal has been validated against:

- Functional requirements
- Visual contract (mockup comparison)
- Interaction contract
- Responsive contract
- Role / security contract
- Company Layer constraints
- Available Mendix capabilities

### Candidate Confidence Levels

| Level | Meaning |
|---|---|
| `preliminary` | Initial best-guess from pattern analysis; not yet assessed against fit criteria |
| `assessed` | Fit criteria evaluated (see Data Grid 2 Fit Check); rationale documented |
| `validated` | Browser-verified in the running application; runtime evidence supports the choice |

Refinement must advance candidate_confidence from `preliminary` to `assessed` before gate-to-ready.
`validated` requires runtime evidence from UI-Agent Verify mode.

---

## Data Grid 2 Is Not the Default for Collections

Data Grid 2 MAY be appropriate when the UI contract genuinely calls for tabular behavior.

**Valid fit signals for Data Grid 2:**
- Column-based comparison of multiple records
- Large tabular dataset
- User-controlled sorting by column
- User-controlled column filtering
- Paging or virtual scrolling for performance
- Column personalization is a feature requirement
- Dense desktop-oriented data management tool
- The mockup is unambiguously a table with defined columns

**Data Grid 2 MUST NOT be selected merely because:**
- Multiple objects exist
- The data source is a list or entity retrieval
- The agent knows how to create a grid quickly
- Filters might theoretically be useful someday
- The mockup has horizontally aligned values

### Data Grid 2 Fit Check

Before finalizing Data Grid 2, the following 10 questions must be answered:

1. Is the mockup genuinely tabular (defined stable columns are part of the user mental model)?
2. Are sorting and/or filtering ACTUAL requirements — not hypothetical future wishes?
3. Is paging or virtual scrolling required given the expected data volume?
4. Is the expected mobile/narrow-width behavior achievable with Data Grid 2?
5. Does the design require card-like rows, complex row content, or responsive restructuring?
6. Are cell interactions and visual states (e.g., status badges, inline edit) supportable?
7. Can the Company Layer / design system style it to the required level of fidelity?
8. Does virtualization or personalization help — or add unnecessary complexity?
9. Would List View, a card layout, or custom repeated composition better match the mockup?
10. Has the choice been validated in the running browser with representative data?

A Data Grid 2 recommendation without this analysis is a `preliminary` candidate only.
Advancing to `assessed` requires documented answers.

### Alternatives to Data Grid 2

Before selecting Data Grid 2, compare it against:

- List View (built-in, responsive, flexible content per row)
- Gallery widget / card layout
- Layout grid with repeated content
- Template-based responsive list composition
- Matrix-specific custom composition
- Master/detail pattern
- Chart or KPI representation
- Company Layer component
- Project-specific reusable component

Do not prohibit Data Grid 2. Require demonstrated fit.

---

## Read-Only Display Must Not Default to Input Controls

A value being stored in an entity attribute does NOT imply that a Text Box, combo box,
or other input control should represent it when the purpose is display.

### Semantic Distinction

| Semantic | Purpose | Widget Class |
|---|---|---|
| **Display** | Communicates information | Text, Dynamic Text, badge, KPI value, card content, label/value pair, formatted text, icon+text, table cell text |
| **Input** | Invites or permits change | Text Box, Date Picker, Combo Box, Check Box, Radio Buttons, Input Reference Set Selector |

### When to Use Input Controls

Use an input widget ONLY where:
- Editing is intended for this role at this point in the flow
- The editing affordance is appropriate (the user expects to be able to change the value)
- Interaction and accessibility semantics match (e.g., form submission pattern)
- The visual contract supports form-control presentation (mockup shows an editable field)

### Display-Only Patterns

For read-only information, consider:

| Pattern | Mendix Implementation |
|---|---|
| Simple text value | Text widget with expression |
| Dynamic attribute value | Dynamic Text |
| Formatted / rich text | Text widget with formatting or HTML snippet |
| Label/value pair | Layout container + Text widgets |
| Status indicator | Badge, icon, CSS-class-driven Text |
| KPI metric | Text with styled container |
| Card content | Layout/Container with Text widgets |
| Table cell | Column content in Data Grid 2 / List View content |
| Custom styled value | Container with Text widget + design-system classes |

### Disabled Input Anti-Pattern

A disabled or read-only input control:
- Still visually communicates editability affordance to some users
- Adds form chrome (borders, background) inappropriate for pure display
- May create accessibility confusion (is this focusable? can it be changed?)
- Is therefore NOT an automatic fallback for read-only values

A disabled input MUST be justified by a specific rationale (e.g., "maintain visual alignment
with adjacent editable fields in this form", or "design system requires consistent form chrome").

---

## Role-Dependent Display/Edit Contract

Do not assume one widget must serve every role and state.

Evaluate whether:
- Editable roles receive an input control
- Read-only roles receive a display component
- Or a single component with explicit mode-specific rendering is appropriate

The selection must preserve:
- Role restrictions (roles without edit permission must not see editable controls)
- Accessibility (correct ARIA roles for display vs. input)
- Visual clarity (no false editability affordance for read-only roles)
- Mockup intent (if the mockup shows a form for one role and a panel for another, implement both)

---

## Company Layer / Design System First

Before selecting a raw Mendix default widget, inspect the available Company Layer and
design-system components.

### Selection Order

```
1. Company Layer component (if installed and covers the pattern)
        |
2. Project-specific reusable component
        |
3. Standard Mendix widget with supported custom content
        |
4. Standard Mendix widget (default configuration)
        |
5. Custom widget — only with documented necessity
```

For projects with a Company Layer:
- Check `.mxagile/layers/*/modules/` for available UI components
- Check Company Layer documentation for preferred patterns
- Prefer Company Layer components where they satisfy the UI contract

Do not hard-code specific Company Layer names into MxAgile Core. Core defines the selection
process. Company Layer exposes available capabilities.

---

## Widget Escalation Ladder

Do not jump to custom widgets as the first response to a styling mismatch.

```
1. Configured standard widget
   → meets functional and visual contract?  YES → select it
        |
2. Standard widget with supported custom content / CSS class extension
   → meets visual contract?  YES → select it
        |
3. Company Layer component
   → covers the pattern?  YES → select it
        |
4. Project reusable composition (page fragments, building blocks)
   → exists and fits?  YES → use it
        |
5. Custom widget — document necessity, justify over alternatives
```

### Custom Widget Conditions

A custom widget requires:
- Documented failure of all preceding options to satisfy the UI contract
- Concrete justification (not "Data Grid 2 looks wrong")
- Scope agreement with the project/Company Layer team
- Test coverage plan

### Avoiding the Opposite Failure Mode

Do not conclude that a standard widget's limitations automatically require a custom widget.
The opposite failure mode is:

```
Data Grid 2 is imperfect
    -> build custom React widget immediately
```

This is wrong. Use the lowest-complexity solution that satisfies the contract.
The escalation ladder above defines the correct intermediate steps.

---

## Accessibility and Semantics

Widget selection must account for:

| Concern | Implication |
|---|---|
| Keyboard navigation | Input controls must be focusable and operable by keyboard |
| Screen reader labels | All inputs need accessible names; display-only text needs correct roles |
| Table semantics | Use tabular markup only when the content is genuinely tabular |
| Form semantics | Use form patterns only where editing is intended |
| Status semantics | Status values should use ARIA live regions or role="status" where appropriate |
| Disabled/read-only communication | Disabled does not mean read-only in all AT contexts |
| Responsive reflow | Complex tables may be inaccessible on narrow viewports |

Do not choose input controls for display-only content because data binding is convenient.
Correct accessibility semantics matter for widget choice.

---

## Performance and Scale

Data volume affects widget selection:

| Scale | Consideration |
|---|---|
| Small list (< 50 records) | List View, card composition — no pagination needed |
| Medium list (50–500 records) | Server-side paging useful — List View or Data Grid 2 |
| Large dataset (500+ records) | Virtualization, server-side sort/filter — Data Grid 2 or equivalent |
| Real-time update | Data Grid 2 vs. alternative depends on update granularity |

Performance rationale must be documented when it influences the widget selection decision.
Do not reject or choose Data Grid 2 based solely on styling preference.

---

## Implementation Reconsideration

During runtime comparison, if the chosen widget cannot achieve the required design or
interaction without brittle or uncontrolled workarounds, reassess rather than pile workarounds.

A previous widget suggestion is not immutable.

If the running application reveals that the selected widget cannot satisfy the UI contract:
1. Reassess the selected pattern using the fit criteria
2. Compare alternatives (see Data Grid 2 Fit Check and Escalation Ladder)
3. Update the Spec/Task with the corrected selection and rationale
4. Replace the widget when justified — do not delay because a suggestion was written earlier
5. Preserve evidence explaining the change so traceability is maintained

Do not endlessly pile SCSS overrides onto a widget that fundamentally does not fit.

## Default Widgets Are Implementation Options, Not Visual Acceptance

A standard widget is acceptable only if it can satisfy the approved UI contract.

The following is not sufficient:
- Widget exists in Mendix
- Widget compiles and deploys without errors
- Widget displays data in some form

Acceptance also requires:
- Intended interaction behavior
- Intended information hierarchy
- Intended visual presentation (within acceptable deviation)
- Intended responsive behavior
- Intended role behavior
- Browser-verified design-system fit (where applicable)

A widget that meets the first three criteria but fails the rest is NOT accepted.

## Live Widget-Fit Validation

Final widget selection is not complete until validated in the running application.

Evidence must include (where applicable):
- Correct role performing the intended interaction
- Representative data (not empty state only)
- Appropriate viewport (desktop and/or mobile as required)
- Key interaction executed and verified
- Screenshot under `.concord/screenshots/app/`
- Mockup comparison showing acceptable parity
- Responsive check at required viewports

A widget verified only in Studio Pro model structure is:
```
candidate_confidence: assessed
```
not:
```
candidate_confidence: validated
```

`validated` requires browser evidence from UI-Agent Verify mode.

---

## Existing Project Reconciliation

On the next UI Discovery/Refinement cycle for a project with previously generated widget
suggestions, audit existing pages for:

- Unjustified Data Grid 2 usage (no fit check documented)
- Read-only values rendered as disabled/read-only input boxes
- Default widget styling contradicting mockups
- Desktop-only grids where responsive list/card behavior is required
- Overuse of disabled controls as the read-only pattern
- Candidate widget suggestions that were never runtime-validated

For each finding:
1. Document as a `candidate_confidence: preliminary` reassessment item
2. Apply the Data Grid 2 Fit Check or Read-Only Display Contract as applicable
3. Update the Spec/Task with a corrected selection and rationale
4. Validate in the running browser before closing the item

Do not retroactively invalidate completed acceptance evidence for previous releases.
Apply this reconciliation to in-progress and future waves only, unless a specific regression
is confirmed.
