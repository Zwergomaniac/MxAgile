# Evidence Levels

Canonical classification for the maturity of verification evidence in the MxAgile lifecycle.

## The Problem

An agent can observe the same concern at different evidence maturities:
- A field exists in the Requirements document (STATIC)
- A field exists as a Mendix entity attribute (MODEL)
- The field renders correctly in a running application (RUNTIME)
- The field renders correctly in the browser with representative data and the correct role (BROWSER)

These are NOT equivalent. A Discovery PASS backed only by STATIC evidence does not prove the
same things as one backed by BROWSER evidence.

This policy defines the four levels, their meaning, and which gates require which level.

## Evidence Level Definitions

### LEVEL 1 — STATIC

Source: document/artifact analysis without executing anything

Examples:
- Requirements document analysis
- Mockup HTML/CSS analysis (without running a browser)
- Story specification review
- UI-inventory YAML inspection

Properties:
- Does NOT require a running application
- Does NOT require a running database
- Can be performed purely from file system artifacts
- Fastest to produce; weakest verification

Tag in reports: `evidence: static`

### LEVEL 2 — MODEL

Source: Mendix model inspection via mxcli

Examples:
- `mxcli DESCRIBE MICROFLOW` output
- `mxcli SHOW ENTITIES` output
- `mxcli check` and `mxcli lint` results
- `mxcli docker check` consistency results

Properties:
- Requires mxcli access to the `.mpr` file
- Does NOT require a running application
- Can detect model defects before any deployment
- Faster than runtime; stronger than static

Tag in reports: `evidence: model`

### LEVEL 2.5 — BUILD

Source: The strongest available Mendix semantic/build-time validation — consistency checks that go
beyond model structure into behavior under Mendix's semantic rules.

Examples (semantically):
- XPath constraint in entity access rule is syntactically and semantically valid
- Microflow referenced from navigation is reachable from at least one role
- Container/model parity (e.g. `mxcli docker check` where supported)
- Security expression consistency: entity access rule and page access rule agree for the same entity + role

Properties:
- Requires mxcli access to the `.mpr` file
- Does NOT require a running application
- Stronger than MODEL: validates model consistency under semantic rules, not just structure
- Weaker than RUNTIME: does not prove runtime behavior, only build-time correctness
- Optional layer: when no semantic build capability is available, `exclusion_reason: INFRASTRUCTURE_UNAVAILABLE`
- `mxcli check` (syntax) and `mxcli DESCRIBE` (structure) are NOT equivalent to BUILD
  unless they also verify semantic properties (XPath validity, security expression semantics)

Tag in reports: `evidence: build`

### LEVEL 3 — RUNTIME

Source: Running application state — local warm runtime

Examples:
- Application starts and reaches a healthy state
- Pages can be reached by URL
- Database is accessible and seeded with representative data
- mxcli runtime logs without critical errors

Properties:
- Requires `mxcli run --local --watch` (or equivalent) to be running
- Requires credentials/database to be configured and accessible
- Requires mock/seed data for non-empty scenarios
- Does NOT require a browser session — verifies runtime viability

Tag in reports: `evidence: runtime`

### LEVEL 4 — BROWSER

Source: Browser-rendered application with role + data + viewport

Examples:
- Page rendered in browser with representative data
- UI element visible and interactable per `.mx-name-*` selectors
- Navigation flow completed
- Role-specific data scope verified via browser session
- Interaction state triggered and screenshot captured
- Mockup-to-application comparison performed

Properties:
- Requires RUNTIME (Level 3) as prerequisite
- Requires browser-accessible application
- Requires applicable role session (logged in as correct demo/test user)
- Requires representative data state (not empty unless empty IS the scenario)
- Requires defined viewport
- Strongest verification; most complete

Tag in reports: `evidence: browser`

## Required Evidence by Gate

| Gate / Phase | Standard (`ui_driven=false`) | UI-Driven (`ui_driven=true`) |
|---|---|---|
| gate-to-refinement: requirements coverage | STATIC | STATIC |
| gate-to-refinement: model analysis | MODEL | MODEL |
| gate-to-refinement: mockup analysis | STATIC (HTML rendered by Playwright against file://) | STATIC |
| gate-to-refinement: full UI Discovery PASS | MODEL | BROWSER (Level 4) for runtime-testable scope |
| gate-to-ready: all DECISION REQUIRED resolved | STATIC | STATIC |
| gate-to-ready: UI inventory complete | STATIC | STATIC |
| gate-to-ready: testability gate (test contract present) | STATIC | STATIC |
| quality-gate: model validation | MODEL | MODEL |
| quality-gate: build validation (when configured) | BUILD | BUILD |
| quality-gate: runtime readiness | RUNTIME | RUNTIME |
| UI-Agent Verify: field/button structure | BROWSER | BROWSER |
| Acceptance-Agent: REQUIREMENT campaign | per proof point required_layers | per proof point required_layers |
| Acceptance-Agent: ROLE campaign | per proof point required_layers | per proof point required_layers |
| Acceptance-Agent: RISK_CHANGE_IMPACT campaign | per proof point required_layers | per proof point required_layers |
| acceptance-gate: all campaigns passed | MODEL + RUNTIME or FRONTEND | MODEL + RUNTIME + FRONTEND |

## UI-Driven Discovery Evidence Gap

When `development.ui_driven = true`, Discovery produces:

- Mockup YAML inventory — evidence: STATIC (Playwright renders local HTML files)
- Screenshots of mockup states — evidence: STATIC
- Model analysis — evidence: MODEL
- Live UI comparison against running app — evidence: BROWSER

A Discovery PASS without BROWSER evidence is a **MODEL-ONLY DISCOVERY** or **PARTIAL DISCOVERY**.

This distinction MUST be recorded and MUST NOT be silently promoted to FULL UI DISCOVERY PASS.

## Evidence State Recording

Discovery and gate outcomes MUST record the highest evidence level achieved for each concern.

In `process-state.yaml` gate evidence, use:

```yaml
gates:
  gate_to_refinement:
    result: passed
    evidence:
      coverage: model           # highest evidence level for model/spec coverage
      ui_inventory: static      # UI inventory is static (mockup-only)
      live_ui_comparison: none  # runtime was blocked during discovery
    note: "MODEL-ONLY DISCOVERY — runtime blocked (DB-AUTH); live UI comparison deferred"
```

In planning/stories, annotate assumptions with their evidence level:

```
ASSUMPTION [evidence:model]: Entity Customer exists with Name attribute.
ASSUMPTION [evidence:static]: Login page has username/password fields per mockup.
TODO [evidence:none]: Verify data filtering per role against running app.
```

## Reconciliation

When later evidence contradicts an earlier finding:

```
previous: ASSUMPTION [evidence:static] — page layout matches mockup
later:     OBSERVED  [evidence:browser] — section ordering differs
result:    DISPROVED — story spec updated; checklist item created for correction
```

Do not erase the earlier finding — record the reconciliation.
Do not declare a full Discovery PASS retroactively for static-only work.

## Evidence Maturity in Refinement

Refinement MUST know the evidence level of each Discovery claim it consumes.

A refinement based on a `[evidence:static]` claim is weaker than one based on `[evidence:model]`.

If a claim is `[evidence:static]` but the acceptance criterion requires `[evidence:browser]`:
- Record the gap explicitly
- Refinement should identify this as a residual that requires runtime closure
- The implementation checklist should include a "verify at runtime" item for this claim

## STATIC vs RUNTIME: UI-Driven Examples

| Observation | Evidence Level | Valid for UI-Driven Acceptance? |
|---|---|---|
| SCSS class written in stylesheet | STATIC | NO |
| MDL executed successfully | MODEL | NO |
| Page exists in model | MODEL | NO |
| `mxcli check` passes | MODEL | NO |
| `mxcli docker check` passes | MODEL | NO |
| App starts without error | RUNTIME | Partial — layout not yet confirmed |
| Page renders in browser with data | BROWSER | YES (for that page+role+data combo) |
| Screenshot matches mockup with role context | BROWSER | YES |
