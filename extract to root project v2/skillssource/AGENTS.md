# [PROJEKTNAME] — Maia Coding Instructions

> **Projektkontext (Ziel, Module, Stack, Sprint-Struktur):** siehe `projekt.md` im Projektstamm.
> Diese Datei enthält Maia-spezifische Mendix-Programmierregeln und Domain-Konventionen.
> Nicht hier: Tool-Routing, mxcli-Befehle (→ `CLAUDE.md`).

---

## Domain Model Conventions

### Entity Naming
- **Language:** English (PascalCase)
- **Style:** Singular nouns, domain-specific
- **Prefixes:** None on entities. Use module folders for grouping.

### Attribute Naming
- Boolean: Must start with `Is`, `Has`, `Can`, `Should`, `Was`, `Will`
- DateTime: Suffix `At` (e.g., `CreatedAt`, `UpdatedAt`)
- String identifiers: Suffix `Code` or `Key`

### Association Naming
- Pattern: `Parent_Child` (e.g., `Facility_Tenant`, `Group_Facility`)
- Always qualify: `Module.AssociationName`

---

## Security & Access Rules

### Role Model
<!-- TODO: Projektspezifische Rollen eintragen -->
- `Administrator` — ...
- `[Rolle]` — ...

### XPath Constraints (mandatory on EVERY entity)
Every persistent entity MUST have XPath constraints per module role.
No entity without access rules at Production security level.

```
// Pattern: Filter by current user's tenant context
[Module.Entity_Tenant/[Module.UserTenantRole_User/[Module.UserTenantRole_Account = [%CurrentUser%] and isActive = true]]]
```

---

## Microflow / Nanoflow Conventions

### Naming Schema
| Prefix | Zweck |
|---|---|
| `ACT_` | User-triggered actions (button click) |
| `SUB_` | Sub-microflows (reusable logic) |
| `VAL_` | Validation microflows |
| `SEC_` | Security/access check microflows |
| `CORE_` | Core business logic |
| `NAV_` | Navigation helpers |

### Error Handling
- Use `ON ERROR ROLLBACK` for all commits in critical flows
- Log errors with `LOG ERROR NODE 'ModuleName' 'message'`
- Show user-friendly messages (no stack traces)

---

## Page & UI Conventions

### Layout
- Desktop: use `Atlas_Default` layout
- Mobile: use `Atlas_Phone_Default` or `Atlas_Tablet_Default`
- Always set a page Title

### Page Naming
- Pattern: `Entity_NewEdit`, `Entity_Overview`, `Entity_View`
- Popups: `Entity_Popup_Action`

---

## Testing & Quality

### Per Story
- At least one happy-path test
- XPath constraints verified with test data

### Definition of Done
- No CE errors (Consistency Errors)
- Lint passes (`mxcli lint`)
- Access rules present on all new entities

---

## Module-Specific Rules

<!-- TODO: Für jedes Modul spezifische Regeln in skillssource/_modules/<modul>/ ablegen -->
See `skillssource/_modules/` for module-specific conventions.

## Agent Test Workflow

Read `skillssource/agent-test-workflow.md` before Docker or browser verification.
The isolated runner creates one random Administrator only for the initial login;
the existing demo-user switcher is the subject of the browser test.