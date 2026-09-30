# SCSS Engineering

Canonical MxAgile contract for project-specific SCSS authoring in Mendix applications.

All agents that produce or modify SCSS follow this policy. The full rule lives here once.
No agent duplicates this content; they reference this file.

---

## Source Ownership — Validate Before Styling

Before writing a single SCSS declaration, determine whether the target file is
**project-owned** or **protected**.

### Protected Sources — DO NOT Modify

An agent MUST NOT write project-specific styling directly into:

| Source type | Examples |
|---|---|
| Mendix Standard/System modules | `themesource/atlas_core/web/`, `themesource/atlas_web_content/web/` |
| Marketplace modules | `themesource/datawidgets/web/`, `themesource/communitycommons/web/`, any module fetched from the Mendix Marketplace |
| Company Layer platform modules | `themesource/MB_UI/web/` or equivalent Layer-managed sources (unless the Layer contract explicitly grants project modification rights) |

The existence of a technically writable SCSS file does NOT authorize modifying it.

Modifying a protected source creates a maintenance hazard: the next upstream update or Core install overwrites the change silently.

### Project-Owned Sources — Safe to Modify

| Source | When to use |
|---|---|
| `themesource/{ProjectModule}/web/` | Primary home for all project-specific SCSS. Use when the project has its own Mendix module (standard for all non-trivial projects). |
| `theme/web/custom-variables.scss` | Sass variable overrides: brand colors, typography sizes, spacing tokens. Referenced by `@import "custom-variables"` in Atlas core. |
| `theme/web/` (other files) | Only for the bootstrap/exclusion variable pattern supported by the theme layer. Not a general-purpose styling destination. |

If the project does not yet have a dedicated Mendix module for styling, use `theme/web/` as the fallback only. Prefer creating a project module (`themesource/{ProjectModule}/web/`) for any non-trivial project.

### Upstream Override Pattern

When upstream styling MUST be overridden (Atlas Design System, Marketplace widget visuals):

1. Write the override in the **project-owned** source (`themesource/{ProjectModule}/web/` or `theme/web/`).
2. Use a CSS specificity rule or Sass variable override at the appropriate inheritance point.
3. Do NOT modify the upstream file.
4. Document the override in a comment naming the upstream source it targets.

---

## main.scss Is the Composition Root

`themesource/{ProjectModule}/web/main.scss` (and `theme/web/main.scss`) are **composition roots**.
Their purpose is to declare which SCSS partials are active — not to contain implementation.

### main.scss SHOULD contain

- `@import`, `@use`, or `@forward` statements composing other partials
- Custom variable overrides that are genuinely global (e.g., `$brand-primary: #003d6a`)
- Bootstrap-level declarations that must appear before all partials

### main.scss MUST NOT become the default location for

- Page-specific selectors (`.overview-page`, `.customer-form`)
- Component-specific styling (`.kpi-card`, `.status-badge`)
- Feature-specific selectors
- Parity fixes or gap remediation
- Responsive overrides for individual screens
- Temporary visual corrections

Appending implementation directly to `main.scss` because it already exists and is easy to find is the primary failure mode this contract prevents.

---

## SCSS Concern Classification

Before creating styling, classify the concern. Use the project's **existing** partial structure where present. Do not impose a new directory hierarchy onto projects that already have a coherent convention.

Where no structure exists, apply the smallest structure that makes the concern navigable:

| Concern type | Example partial location |
|---|---|
| Component | `scss/components/_kpi-card.scss` |
| Page-level | `scss/pages/_overview.scss` |
| Layout | `scss/layouts/_sidebar.scss` |
| Feature | `scss/features/_hr-import.scss` |
| Responsive | `scss/responsive/_mobile-nav.scss` |
| Utility | `scss/utilities/_spacing.scss` |
| Application theme | `_app-theme.scss` (root level, after variables) |

These are conceptual examples only — use names and hierarchy that reflect the actual project.

---

## Decision Rule — Partial vs. main.scss

Apply in order:

1. **Does an appropriate existing partial already own this concern?**
   → Extend it.

2. **Is this a new coherent concern not yet covered by any partial?**
   → Create a focused partial. Name it after the stable UI concern it owns.
   → Add the `@import` / `@use` / `@forward` to `main.scss`.

3. **Is the change trivial AND genuinely part of bootstrap/composition?**
   → `main.scss` may contain it. Justify if non-obvious.

Do not create a new partial for a single CSS declaration. Do not create partials named after implementation history (`_fix.scss`, `_parity-fix-2026-10.scss`).

---

## File Granularity

**Too coarse (avoid):**
```
main.scss  ←  3000 lines containing every UI feature
```

**Too fine (avoid):**
```
_card-border.scss
_card-shadow.scss
_card-padding.scss
```

Group styling by **stable UI ownership** — things that change together belong together.

---

## SCSS Naming

Name files and classes after the UI they describe, not the agent session that produced them.

### Preferred

```
_overview.scss          ← page concern
_sidebar.scss           ← layout concern
_kpi-card.scss          ← component concern
_status-badge.scss      ← component concern
_hr-import.scss         ← feature concern
```

### Prohibited

```
_fix.scss
_new-fix.scss
_parity-fix.scss
_temp.scss
_claude-changes.scss
_scss-update-2026.scss
```

The codebase must describe the UI, not the history of who edited it.

---

## Existing main.scss — Do Not Automatically Refactor

When a project already has implementation code in `main.scss` that violates this contract:

- Do NOT automatically extract and restructure existing code on an unrelated task.
- DO apply the contract to the concern currently being implemented or modified.
- Extracting the affected coherent concern into a partial (and updating the import) is encouraged when it is safe and scoped.
- A broad SCSS cleanup is a dedicated refactoring task — it is NOT incidental scope.

---

## Parity and Mockup Remediation

Visual gap fixes identified by parity verification are production UI implementation.
They must follow the same contract as all other styling:

1. Classify the concern (component? page? layout? responsive?)
2. Find or create the appropriate partial
3. Implement the fix in the partial
4. Verify main.scss composes the partial

**Anti-pattern:**
```
# parity run identifies: KPI card has wrong badge color
-> agent appends .kpi-card .badge { color: red; } directly to main.scss
```

**Correct:**
```
# parity run identifies: KPI card has wrong badge color
-> concern: component (_kpi-card.scss or equivalent)
-> extend existing partial or create _kpi-card.scss
-> main.scss: add @import if not already present
```

---

## Validation — What Can Be Enforced

### AUTOMATICALLY ENFORCEABLE (quality gate integration)

The following checks CAN be run programmatically:

| Check | Mechanism |
|---|---|
| Project-owned SCSS file imports all defined partials | Parse `@import` / `@use` / `@forward` in main.scss, compare against partial files |
| No rule references a protected source in `mdlsource/` | `mxcli describe` output + grep for hardcoded styling in Standard/System module pages |
| SCSS class used in model has a matching rule | `check-missing-scss-classes.ps1` (project-local, manual) |

These checks are ADVISORY. Run them as diagnostics; do not fail the quality gate on stylistic granularity.

### AGENT GUIDANCE (not automated)

The following CANNOT be reliably enforced by line counts or heuristics and remain explicit agent contract:

- main.scss is composition root (not implementation destination)
- New concerns receive focused partials
- File names describe UI concerns, not session history
- Upstream overrides stay in project-owned sources
- Parity fixes follow the same structure as new styling
- Unrelated existing styling is not automatically restructured

---

## Relationship to Other Policies

- `policies/observe-before-mutate.md` — SCSS is an implementation mutation; parity analysis MUST precede it
- `policies/evidence-levels.md` — writing SCSS is STATIC evidence (not proof of visual correctness)
- `policies/ui-element-selection.md` — SCSS overrides should not substitute for choosing the right widget
- `policies/ui-parity.md` — parity fixes ARE production UI implementation and must follow this contract
