# Mocketeer Knowledge Migration Map

The seven canonical skill files are under `products/MxMocketeer/skills/`. Their full
domain knowledge remains in the relevant skill text; only the full Golden HTML is an
optional asset. `install-core.ps1` copies these
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
| `knowledge/golden-mockuphtml.txt` | `MOVE_TO_ASSET` | Full HTML source at `skills/mocketeer-mockup-generation/assets/golden-mockup.txt`; `.txt` supports Copilot upload and the contents remain HTML; load only for a needed generation example, calibration or Golden check; never business authority |
| `system-prompt.md` | `RETAIN_AS_PRODUCT_DOCUMENTATION` | Always-on identity, safety, and stop conditions; stays within the Agent Builder limit |
| `suggested-prompts.md` | `RETAIN_AS_PRODUCT_DOCUMENTATION` | Product Owner entry-point configuration |
| `agent-builder-setup.md` | `RETAIN_AS_PRODUCT_DOCUMENTATION` | Host packaging and installation guide |
| `future-plan-next-steps.md` | `OBSOLETE_AFTER_MIGRATION` | Historical seven-skill proposal marked superseded; not an active authority |

The seven skills are authored once under `products/MxMocketeer/skills/`. The normal
installer copies them into consumer `.mxagile/skills/`; the existing generator
projects those installed files to Claude, GitHub Copilot, and portable/Concord paths.
Microsoft Copilot users add the same seven `SKILL.md` files manually and associate the
unchanged `golden-mockup.txt` HTML-source asset with generation. User mockup sources are
uploaded as `.txt` containing the complete HTML document. No ZIP, flattened master, duplicate reference
source or host-specific domain source is maintained.

## Projection Closure Decision

Ownership was checked against `docs/injection-contract.md` and the Generated headers:
all local Mocketeer files under `.claude`, `.github` and `.agents` were host projections,
not canonical sources. They are removed from the framework repository. Only the
Mocketeer product sources remain. No general MxAgile projection was removed.

Consumer installation/update and disposable packaging/test fixtures stage the canonical
skill directories into `.mxagile/skills/` and deterministically generate host copies.
The generator no longer projects directly from framework `products/` sources. Foreign
host skills fail closed; verified legacy bundle retirement remains supported.

## Hybrid Session Bootstrap Decision

On 2026-11-12, before this adjustment, sizes were:

| Skill | Bytes | Approximate tokens (characters / 4) |
|---|---:|---:|
| business-flows | 20,627 | 5,127 |
| design-contract | 20,477 | 5,097 |
| discovery | 11,414 | 2,832 |
| handoff | 6,912 | 1,703 |
| mockup-generation | 30,778 | 7,684 |
| preservation | 1,079 | 270 |
| refinement | 13,009 | 3,243 |
| Total | 104,296 | about 26,000 |

After the hybrid adjustment (UTF-8 working-tree bytes, newline-sensitive):

| Skill | Bytes | Approximate tokens (characters / 4) |
|---|---:|---:|
| business-flows | 20,888 | 5,192 |
| design-contract | 20,738 | 5,162 |
| discovery | 14,920 | 3,709 |
| handoff | 7,173 | 1,769 |
| mockup-generation | 4,323 | 1,081 |
| preservation | 1,346 | 337 |
| refinement | 13,270 | 3,308 |
| Total | 82,658 | about 20,600 |

Combined skill text is 82,218 characters, down from 103,814 (about 21% less), including
the added common session protocol. Token counts are estimates, not host tokenizer
measurements. The main prompt is 7,878 canonical-LF characters, with 122 characters
remaining under the 8,000 limit.

The Golden HTML alone was 27,038 characters (about 6,760 tokens). Its exact code is
unnecessary to understand the product and is now a losslessly moved optional asset.
Business terminology, role/observer semantics, interaction analysis, contract rules,
flow relations, transformation and preservation rules, assessment and handoff remain
inline. No broad reference extraction was justified. Existing canonical machine schemas
remain at their current `.mxagile/schemas/` paths; the skills point to those authorities.

All seven skills are read once per session/current revision, not once per task. The
Discovery skill owns the common session contract; every other entry routes to it.
Bootstrap records are transient context only. A relevant update invalidates them;
Context Compaction requires checking and rebuilding missing baseline knowledge.

Automated tests validate these instruction contracts and host projection/asset parity.
Actual Microsoft Copilot/Claude/Concord read behavior requires the manual host matrix in
`tests/preservation-acceptance.md`. It must not be reported PASS from static checks alone.
The REV37 Interaction-/Effect-Coverage Audit remains separate. The supplied external
REV37 was inspected read-only: 14 interactions, 20 nested effects and all eight cases
are mapped to actual declarations and source anchors in `interaction-coverage-audit.md`.
All 33 cited IDs resolve and the source hash remained unchanged. Runtime acceptance
and real Mendix enforcement are not verified; they are not reported as passed.

## Verification Snapshot

| Check | Result |
|---|---|
| Seven skills, session initialization/reuse, update/compaction, lazy assets, Copilot access contract and source-only layout | PASS, 13 Python tests; instruction-contract evidence, not live-host traces |
| Product static validation, prompt budget and Golden HTML/JSON | PASS, 210/0 |
| Business Flow / Golden contract validation | PASS, 20/0 |
| Cross-contract drift | PASS, 39/0 |
| Role semantics | PASS, 48/0 |
| Consumer injection, semantic/asset parity, reproducible updates, changed-source updates, foreign-skill protection, framework source-only behavior | PASS, 224/0; includes Windows PowerShell 5.1 execution |
| Core Fresh Install and actual Core update | PASS, Test-GenericInstallation; identical installed sources, seven entries and Golden asset bytes on three hosts |
| General-platform portability / documentation | PASS, 47/0 and 63/0; general MxAgile projections preserved |
| Impact-rule regression | PASS, 43/43 |
| Framework host copies | Removed after ownership/content verification; only consumer/fixture projections remain |
| Original inline domain knowledge / extracted Golden content | Preserved; compared with committed baseline using explicit UTF-8 decoding |
| Static Development/Fast Gate | PASS; impact mapping has zero unmapped paths |
| Impact Regression aggregate / Full Release Gate | NOT RUN |
| Microsoft Copilot session acceptance | NOT_VERIFIED; short manual smoke and host matrix in tests/preservation-acceptance.md |
| REV37 contract and source | Read-only audit complete; all 33 cited IDs resolve; input SHA-256 unchanged |
| REV37 browser behavior / real Mendix enforcement | NOT VERIFIED |

No consumer project or REV37 source was modified. Application divergences remain for
the next PO/Mocketeer revision and subsequent MxAgile Reconciliation, not framework fixes.
This work is committed after the closure Development/Fast Gate; no push or Full Release
Gate is performed. Live-host acceptance remains distinct from automated evidence.