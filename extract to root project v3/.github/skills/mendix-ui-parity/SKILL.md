---
name: mendix-ui-parity
description: "Explore HTML mockups and Mendix pages in a real browser, derive Soll-Ist UI behavior, implement Atlas-compatible styling with semantic classes instead of inline styles, and verify parity with Playwright screenshots and DOM assertions."
argument-hint: "Mockup, Mendix page, role, and states to compare"
user-invocable: true
---

# Mendix UI Parity

Use this skill before implementing or reviewing any user-facing Mendix page that has a mockup, screenshot, or visual acceptance expectation.

## 1. Establish the reference

- Read `input-resources/README.md` and the relevant story/specification.
- Open the mockup in a real browser.
- Exercise every relevant role, tab, menu, toggle, filter, validation, modal, and responsive state.
- Save screenshots under `.concord/screenshots/` and record observed behavior under `.concord/tasks/` or a versioned planning report.
- Record exact labels, field order, required fields, disabled states, empty states, error text, and visible data effects.

## 2. Inspect the Mendix implementation

- Read the page and widget tree from the current MPR/model.
- Identify page layout, widget names, data sources, actions, and existing classes.
- Locate the owning project theme and existing SCSS conventions.
- Treat Marketplace modules as read-only dependencies.
- If login is explicitly accepted as platform behavior for the project, begin UI
	parity after the authenticated landing state and do not count login as an open
	UI gap unless authentication is the target.
- If a Mendix developer-license/session limit appears during capture, treat it
	as a runtime lifecycle condition. Restart the disposable app/container, wait
	for a healthy runtime, and retry capture before marking UI comparison blocked.

## 3. Styling policy

- Do not use inline `Style` properties for product styling.
- Use the project's platform UI module and its layouts as the default foundation
	for every page and popup. Preserve the platform module's standard top
	navigation on normal pages and popups unless explicitly overridden by a
	confirmed platform constraint. A fixed left custom navigation is additive and
	must not replace the platform navigation.
- Prefer existing Atlas layout and design properties.
- For reusable styling, add semantic classes such as `app-page-header`, `app-kpi-grid`, or `app-admin-sidebar` to project-owned theme SCSS.
- Do not fill `main.scss` with component styles. Keep `main.scss` as a small
	import entry point and place grouped styles in partials such as
	`_navigation-sidebar.scss`, `_masterdata-grid.scss`, or `_admin-shell.scss`.
- Keep spacing, color, typography, focus, and responsive rules in SCSS/CSS classes, not duplicated per widget.
- Use design tokens or CSS variables already defined by the theme; introduce project tokens only for stable domain concepts.
- Do not modify Marketplace theme/module sources for application-specific visual requirements.

## 4. Implement and verify

- Work first in a disposable project/model copy.
- Use stable Mendix widget names for browser assertions.
- Verify desktop and mobile viewports.
- Assert semantic behavior with DOM selectors and visible text; use screenshots to compare composition, spacing, hierarchy, and state.
- Check that text fits, controls do not overlap, focus/disabled states are visible, and navigation remains usable.
- Re-run the same interactions against the Mendix app used for the mockup.
- Only after MxBuild and UI checks pass, transfer changes to the canonical model.

## 5. Evidence format

| State | Reference behavior | Mendix behavior | Visual parity | Interaction parity | Data parity | Decision |
|---|---|---|---|---|---|---|

Classify differences as:

- `P0`: broken flow, inaccessible control, or wrong data effect
- `P1`: important layout, content, or responsive mismatch
- `P2`: minor visual or copy mismatch
- `INFO`: intentional difference documented by story or platform constraint

Write regression tests only after the expected behavior is confirmed. Each test must cover the named widget, user action, resulting state, and any persisted data effect.
