# Verification Layers

Policy defining the five evidence layers for MxAgile verification, their semantics, and the four
security verification dimensions. Consumed by `skills/verification-plan.md` and
`schemas/verification-plan.schema.json`.

## The Five Layers

### STATIC

Source: document/artifact analysis without executing anything.

Use for:
- Confirming artifact existence (requirement, test contract, UI inventory)
- Verifying schema compliance (JSON/YAML structure)
- Presence checks in mockup HTML without rendering

Cannot prove: runtime behavior, role enforcement, data persistence.

Tag: `evidence: static`

### MODEL

Source: Mendix model inspection via mxcli DESCRIBE, SHOW, check, lint.

Use for:
- Entity/attribute existence and type
- Microflow existence and high-level structure
- Security rule presence (entity access, page access)
- Navigation reachability (page reachable from menu/button in model)
- Association cardinality

Cannot prove: runtime behavior, actual data access filtering, UI rendering.

Tag: `evidence: model`

### BUILD

Source: The strongest available Mendix semantic/build-time validation — checks that go beyond
model structure into consistency under Mendix's semantic rules.

What BUILD validates (semantically):
- XPath constraint in entity access rule is syntactically and semantically valid
- Microflow referenced from navigation is reachable from at least one role (no dead navigation)
- Consistency between entity access rule and page access rule for the same entity + role
- Container/model parity (e.g. `mxcli docker check` where supported)
- Any other semantic-level consistency check available in the project's toolchain

Cannot prove: runtime behavior, actual data filtering at runtime, UI rendering, access enforcement.

Tag: `evidence: build`

**Execution adapter:** The concrete mechanism is environment-dependent. The project's toolchain
determines which commands achieve BUILD-level validation. If no semantic build capability is
available in the environment: `exclusion_reason: INFRASTRUCTURE_UNAVAILABLE` in the Verification Plan.

**BUILD ≠ static/mxcli check:** `mxcli check` and `mxcli DESCRIBE` satisfy MODEL evidence.
They are NOT BUILD unless they also verify semantic consistency (XPath validity, security expression
semantics, navigation reachability). Do not silently treat a passing MODEL check as a BUILD PASS.

### RUNTIME

Source: Running application state via `mxcli run --local --watch`.

Use for:
- Application startup without errors
- Page reachability by URL with a live session
- Data persistence: entity created/updated/deleted successfully
- Business rule enforcement at runtime (server-side validation)
- Microflow execution result when triggered

Cannot prove: UI element visibility per role, viewport layout, Playwright interaction flow.

Tag: `evidence: runtime`

### FRONTEND

Source: Browser-rendered application via Playwright, with role session + data state + viewport.

Use for:
- UI element visible/hidden per role (prefer accessible role/label; `.mx-name-*` as fallback)
- User interaction flow (click, fill, submit, navigate)
- Role-specific data scope (user sees only permitted records)
- Mockup-to-application UI comparison
- Validation error display
- Navigation guard (redirect / access denied page)

Requires RUNTIME as prerequisite.

Tag: `evidence: browser` (maps to FRONTEND in layer vocabulary)

## Security Verification Dimensions

These four dimensions are ORTHOGONAL. A role may pass one dimension but fail another.
All four must be explicitly assessed when security proof points are present.

### VISIBILITY

**What it checks:** Whether a UI element (page, section, button, field, navigation item) is
rendered or hidden for a given role.

**Not the same as:** Authorization. A hidden button still represents a security gap if the
server action behind it is accessible without it.

Verification layer: **FRONTEND** (must be browser-rendered). MODEL can predict visibility from
widget-level access rules but only FRONTEND confirms actual render.

### ACCESSIBILITY

**What it checks:** Whether a page or action can be reached via URL, deep link, or API call —
even if not shown in the UI. Tests navigation guards and access denied redirects.

**Not the same as:** Visibility. A hidden button may still be accessible by direct URL.

Verification layer: **RUNTIME** (requires live session) + **FRONTEND** (confirm redirect/guard page).

### AUTHORIZATION

**What it checks:** Whether the server enforces the permission when the action is actually executed —
independent of whether UI shows or hides the trigger.

**Not the same as:** Visibility or Accessibility. Authorization is the server-side enforcement contract.
A user might reach a page (ACCESSIBILITY) and see a button (VISIBILITY) but the server must still
refuse execution without the required permission.

Verification layer: **RUNTIME** (server must reject or allow) or **MODEL** (entity access rule present).

### DATA_SCOPE

**What it checks:** Whether a user can only retrieve data within their permitted scope —
enforced via XPath constraints on entity access rules.

**Not the same as:** Authorization. DATA_SCOPE is about which records a permitted user can access,
not whether they can execute the action at all.

Verification layer: **MODEL** (XPath constraint present) + **RUNTIME** (query returns scoped result) +
**FRONTEND** (user sees only scoped records in browser).

## Dimension × Layer Mapping

| Dimension | STATIC | MODEL | BUILD | RUNTIME | FRONTEND |
|---|---|---|---|---|---|
| VISIBILITY | - | partial | - | - | required |
| ACCESSIBILITY | - | partial | - | required | confirm |
| AUTHORIZATION | - | partial | build check | required | - |
| DATA_SCOPE | - | required | build check | required | confirm |

`required` = must pass. `partial` = necessary but insufficient. `confirm` = validates observed outcome.

## Choosing Layers for a Proof Point

Use the defaults from `policies/test-contract-derivation.md`, then apply these overrides:

1. **No RUNTIME available** (infrastructure gap): fall back to MODEL. Record `PARTIAL` gap.
2. **No browser tooling** (Playwright not configured): FRONTEND layer unavailable. Record gap.
3. **BUILD layer unavailable**: set `exclusion_reason: INFRASTRUCTURE_UNAVAILABLE` in VPL.
4. **Security proof point**: always include at least MODEL + the dimension's required layer(s).
5. **Negative authorization proof** (`role: !ROLE-NNN`): always include FRONTEND to confirm
   the UI reflects the restriction, and RUNTIME to confirm server enforcement.
