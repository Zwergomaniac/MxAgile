# Skill: Technical Test Generation

Generate concrete test implementations (mxcli inspect commands, Playwright steps) from a
Verification Plan (VPL-NNN). Answers HOW tests are technically run.

This skill bridges the WHAT (test contract) + WHICH (verification plan) to executable test actions.
Generated test steps are regeneratable implementation details — they are NOT canonical Test Contract identity.

## When to Run

Run this skill during the Verifying phase, before acceptance campaigns execute.
The Acceptance Agent calls this skill per proof point to obtain concrete execution steps.

## Inputs Required

1. `planning/test-contracts/TC-NNN.yaml` with `status: active`.
2. `planning/verification-plans/VPL-NNN.yaml` with `status: active`.
3. `planning/checklists/W*-implementation-checklist.yaml` — maps artifacts to model names.

## Generation Per Layer

### MODEL layer

Produce an `inspect:` block per proof point:

```yaml
inspect:
  entity: <EntityName>
  expect: "Access rule for <ROLE> grants <operation>"  # operation-aware when proof point has operation field
```

or:

```yaml
inspect:
  microflow: <Module>.<MicroflowName>
  expect: "<high-level behavior assertion>"
```

For operation-aware proof points: the `expect` clause must reflect the specific operation disposition
(READ access allowed, DELETE access forbidden, etc.).

### BUILD layer

Produce a semantic validation assertion:

```yaml
build_check:
  semantic_target: <entity_access_rule | navigation_reachability | security_expression>
  target_detail: "<EntityName> / <MicroflowName> / <expression>"
  expect: "<semantic correctness assertion>"
  execution_adapter: auto  # resolved by project toolchain — not a hard-coded command
```

The `execution_adapter: auto` directive means the Acceptance Agent resolves the concrete build-time
command from the project's available toolchain. Do not hard-code commands that may not exist.

### RUNTIME layer

Produce a runtime assertion:

```yaml
runtime_check:
  action: trigger_microflow | create_entity | delete_entity | navigate_to_page
  target: <MicroflowName | EntityName | PageName>
  operation: READ | CREATE | UPDATE | DELETE | EXECUTE  # if operation-aware proof point
  role: <ROLE-NNN>
  data_state: <empty | populated>
  expect: "<observable outcome at runtime>"
```

### FRONTEND layer

Produce Playwright steps using the preferred locator strategy:

```yaml
playwright:
  role_session: <ROLE-NNN>
  data_state: <empty | populated>
  viewport: desktop
  steps:
    - navigate: <PageURL or PageName>
    - assert_accessible: { role: "button", name: "Create Site" }   # preferred: accessible role/name
    - assert_labeled: { label: "Site Name" }                        # or: associated label
    - assert_test_id: { test_id: "btn-create" }                    # or: deliberate test identifier
    - assert_text: { text: "Create" }                               # or: stable visible text
    - assert_mx_name: { name: "btnCreate" }                         # fallback: Mendix mx-name
    - fill: { label: "Site Name", value: "<value>" }
    - click: { role: "button", name: "Save" }
    - assert: "<expected outcome>"
  screenshot: planning/evidence/screenshots/actual/<scenario-slug>.png
```

**Locator preference order (mandatory):**
1. `getByRole()` — accessible role + name (most stable, semantically meaningful)
2. `getByLabel()` — field associated with a form label
3. `getByTestId()` or explicit `data-testid` — deliberate stable test identifier if available
4. `getByText()` — stable visible text where appropriate
5. `.mx-name-<widgetName>` — Mendix widget name (fallback; regenerate if renamed)
6. DOM/CSS structural selector — last resort only; note as brittle

For negative proof points (`role: !ROLE-NNN`):
```yaml
playwright:
  role_session: <ROLE-NNN-that-should-NOT-have-access>
  steps:
    - navigate: <PageURL>
    - assert_not_accessible: { role: "button", name: "Delete Site" }  # VISIBILITY
    - navigate_direct: <DirectActionURL>                               # ACCESSIBILITY test
    - assert_redirected_to: "/access-denied"  # or equivalent
```

For operation-aware proof points (`operation: DELETE, authorization_disposition: EXPLICITLY_FORBIDDEN`):
- Generate both VISIBILITY (element not shown) and ACCESSIBILITY (direct action blocked) checks.

## Forbidden Adapters

The following patterns are **FORBIDDEN** in all generated test steps. They access Mendix-internal
browser or runtime interfaces that are undocumented, version-fragile, and do not simulate real
user journeys. An LLM generating test steps must never emit them.

**Never generate:**
- `window.mx.data.*` — Mendix JS Data API (internal runtime bridge)
- `window.mx.ui.*` — Mendix JS UI API
- `mx.ui.openForm(...)` or any `mx.ui.*` call
- `runtimeOperation` IDs or action-handler identifiers (undocumented XAS internals)
- Direct XAS endpoint calls (`/xas/`, `executeAction`, or equivalent internal XHR)
- `page.evaluate(() => window.mx...)` — any expression injecting Mendix JS SDK calls into the page

**Use instead (mandatory):**
- Real Playwright user journeys: `navigate`, `click`, `fill`, `waitForURL`, assertions on visible state.
- Locator preference order defined above: `getByRole()` → `getByLabel()` → `getByTestId()` →
  `getByText()` → `.mx-name-*` → DOM/CSS last resort.

**Authorization proofs requiring server-side enforcement** must use the RUNTIME layer
(`runtime_check:` blocks with `action: trigger_microflow`, `create_entity`, `delete_entity`, etc.),
not FRONTEND Mendix JS API calls. VISIBILITY alone (UI element hidden) does **NOT** satisfy
AUTHORIZATION proof — both dimensions are independent and must be covered by their required layers.

**When a FRONTEND step can only be expressed via a forbidden adapter:**

Classify the generation failure as `TEST_ADAPTER_GAP` (see `policies/test-defect-protection.md`),
not as `TEST_INFRASTRUCTURE_GAP`. Assess alternatives before concluding the evidence path is
unavailable:
1. Can a Playwright user journey substitute? (preferred)
2. Can a RUNTIME `runtime_check:` cover the authorization dimension?

Only if no supported adapter path exists after both alternatives are assessed may the Proof Point
be recorded as lacking a viable execution path.

## Naming Convention for Screenshots

Follow `policies/evidence-contract.md` semantic naming:
`<page>-<role>-<data_state>-<dimension>[-<variant>].png`

Example: `SiteRegistry-ROLE-MANAGER-populated-authorization-create.png`

## Regeneration on TECHNICAL_TEST_DEFECT

When a proof point fails as `TECHNICAL_TEST_DEFECT` (see `policies/test-defect-protection.md`):
- Regenerate technical steps (locators, step sequence, test data references) using this skill.
- Do NOT change the canonical `claim` or `authorization_disposition` in the Test Contract.
- Validate the regenerated steps against the original `claim` before re-running.

## Output Format

The Acceptance Agent receives generated test steps as an in-memory execution plan.
May be written to `.concord/scratch/test-gen-<wave>.yaml` (gitignored) for debugging.

## Limitations

- Locators are regeneratable details — they may change without affecting the canonical proof obligation.
- If the checklist is missing an artifact name, use a placeholder; resolve from mxcli output before running.
- Do not generate steps for proof points with `status: stale` or `status: not_applicable`.
- Do not generate BUILD steps when the layer has `exclusion_reason: INFRASTRUCTURE_UNAVAILABLE`.
