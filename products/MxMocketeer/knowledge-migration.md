# Mocketeer Knowledge Migration Map

The seven canonical skill files are under `products/MxMocketeer/skills/`. Their full
knowledge is embedded in the relevant skill text. `install-core.ps1` copies these
product-owned sources into the consumer `.mxagile/skills/` tree before the existing
platform generator runs. Old `products/MxMocketeer/knowledge/*.txt` sources were
migrated without retaining reference-file copies.

| Legacy source | Disposition | Canonical destination and authority |
|---|---|---|
| `knowledge/design-contract.txt` | `MIGRATE_TO_SKILL_CORE` + `RETAIN_AS_CANONICAL_SCHEMA` | Full schema and migration contract embedded in `skills/mocketeer-design-contract/SKILL.md`; MxAgile JSON Schemas remain machine validators for framework artifacts |
| `knowledge/discovery-assessment.txt` | `MIGRATE_TO_SKILL_CORE` | Full assessment and interview guidance embedded in `skills/mocketeer-discovery/SKILL.md` |
| `knowledge/business-flows.txt` | `MIGRATE_TO_SKILL_CORE` | Full structured-flow contract embedded in `skills/mocketeer-business-flows/SKILL.md`; `.mxagile/schemas/business-flow.schema.json` remains the framework machine schema |
| `knowledge/refinement-transformations.txt` | `MIGRATE_TO_SKILL_CORE` | Full Transformation Spec and preservation mechanics embedded in `skills/mocketeer-refinement/SKILL.md` |
| `knowledge/mendix-design-guide.txt` | `MIGRATE_TO_SKILL_CORE` | Full Mendix candidate and role/UserRole guidance embedded in `skills/mocketeer-mockup-generation/SKILL.md` |
| `knowledge/mxagile-handoff.txt` | `MIGRATE_TO_SKILL_CORE` | Full product-side handoff content embedded in `skills/mocketeer-handoff/SKILL.md`; MxAgile lifecycle policies remain downstream authority |
| `knowledge/interaction-analysis.md` | `MIGRATE_TO_SKILL_CORE` | Full cross-role/scope interaction guidance embedded in `skills/mocketeer-business-flows/SKILL.md` |
| `knowledge/golden-mockuphtml.txt` | `MIGRATE_TO_SKILL_CORE` | Full example embedded in `skills/mocketeer-mockup-generation/SKILL.md`; example only, never business authority |
| `system-prompt.md` | `RETAIN_AS_PRODUCT_DOCUMENTATION` | Always-on identity, safety, and stop conditions; stays within the Agent Builder limit |
| `suggested-prompts.md` | `RETAIN_AS_PRODUCT_DOCUMENTATION` | Product Owner entry-point configuration |
| `agent-builder-setup.md` | `RETAIN_AS_PRODUCT_DOCUMENTATION` | Host packaging and installation guide |
| `future-plan-next-steps.md` | `OBSOLETE_AFTER_MIGRATION` | Historical seven-skill proposal marked superseded; not an active authority |

The seven skills are authored once under `products/MxMocketeer/skills/`. The normal
installer copies them into consumer `.mxagile/skills/`; the existing generator
projects those installed files to Claude, GitHub Copilot, and portable/Concord paths.
Microsoft Copilot users add the same seven full `SKILL.md` files manually. No ZIP,
flattened skill, separate reference source, or host-specific content source is maintained.