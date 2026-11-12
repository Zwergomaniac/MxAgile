---
name: mocketeer-mockup-generation
description: turns confirmed discovery inputs and a design contract into a locally executable clickable html mockup. use when a product owner asks to create a first mockup or implement already-confirmed presentation and interaction intent.
---

# Mocketeer Mockup Generation

## Session Entry

At first Mocketeer work in a session, read all seven skills once and follow
`mocketeer-discovery` Session Initialization and recovery rules. Reuse that shared
model for later tasks; load extra references/assets only for the current workflow.

Apply the inline Design Contract and Mendix guidance; use `mocketeer-design-contract`
for the full product contract. The Golden Mockup is an optional asset, not bootstrap context.

- Build the smallest coherent, meaningfully testable flow from confirmed inputs.
- Use semantic HTML, responsive layout, keyboard/focus support, synthetic mock data,
  and visible loading/empty/error/success/disabled/read-only/no-permission states where
  relevant.
- Keep role visibility distinct from security enforcement. Mendix entities, microflows,
  XPath, and deployment mechanisms are candidates, not confirmed implementation facts.
- Embed exactly one valid `#mocketeer-spec` JSON block and preserve stable traceability IDs.
- Do not infer business rules from sample data or add unconfirmed behavior.

For complex cross-role or stateful behavior, invoke `mocketeer-business-flows` before
generation. For an existing file, use `mocketeer-refinement` instead.

---

# Mendix Design Guide for MxMocketeer

## Purpose
This file helps MxMocketeer generate realistic Mendix-aligned mockups without anticipating technical refinement.

## Suitable Design Concepts
- Pages, layouts, navigation, and reusable UI components
- Lists, data grids, forms, dialogs, tabs, and filters
- Role-dependent visibility and editability
- Validation, error, loading, empty, and no-permission states
- Responsive behavior and accessibility
- Business data objects, statuses, and relationships as candidates
- Actions, validations, data sources, and navigation as microflow candidates
- Integrations described functionally only: purpose, direction, data, trigger, error handling

## Boundaries
MxMocketeer does not make final decisions about:
- Module and entity names
- XPath constraints
- Microflow/nanoflow implementation
- Persistence or integration architecture
- Deployment, operations, or credentials
- Specific mxcli commands

## Good Handoff vs. Bad Handoff
**Good:** "A manager can create, edit, and deactivate sites; deletion is an open question."
**Bad:** "ACT_SaveSite calls SUB_WriteAudit on entity Core.Site" — unacceptable without a confirmed technical basis.

## Roles and Security
Visibility is not complete security. The mockup documents what users may see/do and may not see/do from a business perspective. The later Mendix implementation must enforce page, microflow, and entity/attribute access separately.

Role names in a Design Contract express business/test identity; they are not instructions to compare `System.UserRole.Name` strings. When implementation XPath refers to a concrete Mendix User Role, use the documented `[%UserRole_<RoleName>%]` system variable and verify it against the actual project role. Never substitute wildcard or substring matching. Keep capabilities such as `CanEditRegions` distinct from role identity; scope, context, lifecycle, and status rules may still apply. See MxAgile `policies/implementation-control.md` for the canonical implementation contract.

## Design Quality
- Small, coherent flows rather than disconnected screens
- Clear actions and understandable feedback
- Mock data visibly marked as mock data
- Relevant alternative and error states represented
- Respect the general design language and visual hierarchy without copying platform-specific runtime components into the mockup


---

## Optional Golden Asset

Load `assets/golden-mockup.html` only when mockup generation needs a concrete example,
visual calibration, or a Golden Mockup check. Generation alone does not require the
asset if the inline guidance and confirmed inputs suffice. Never load it during
session bootstrap or Discovery. The example is not business authority.
