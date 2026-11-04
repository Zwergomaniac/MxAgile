# Project Compatibility Doctor and Controlled Repair

## Authority and scope

Framework installation, migration completion, current artifact compatibility, and
evidence freshness are separate facts. Doctor is a deterministic read-only
projection, not another lifecycle state machine. Historical `migration: complete`
and `artifact_canonicalization: complete` do not substitute for a current check.

`FRAMEWORK_INSTALLED` means the payload was distributed. A Doctor result records
`PROJECT_COMPATIBILITY_CHECKED` with `COMPATIBLE`, `PARTIAL`, or `BLOCKED`.
`COMPATIBLE` corresponds to `PROJECT_COMPATIBLE`, and `PARTIAL` to
`PROJECT_PARTIALLY_COMPATIBLE`. `repair_status` is `PROJECT_REPAIR_REQUIRED`,
`DECISION_REQUIRED`, or null. No result is persisted as new lifecycle authority.
Missing Python, PyYAML, jsonschema, or schemas is unavailable verification, never
passed verification. Session/model freshness can remain unknown independently.

## Commands in an installed project

```powershell
python -m pip install -r .mxagile/tools/requirements.txt
python .mxagile/tools/project_compatibility.py doctor --project-root .
python .mxagile/tools/project_compatibility.py doctor --project-root . --format json
python .mxagile/tools/project_compatibility.py repair --project-root . --dry-run
python .mxagile/tools/project_compatibility.py repair --project-root . --apply --plan-hash <approved-hash>
```

Framework development uses `scripts/project_compatibility.py` instead.
Doctor exits 0/1/2 for compatible/partial/blocked; operational failures exit 3.
The installer reports installation and compatibility separately and never repairs
project artifacts. Doctor and dry run never create project files or caches.

## Diagnostic contract

The Project Status schema defines `compatibility` and each diagnostic's stable
ID, severity, category, relative source path, parser line/column, artifact type,
board area, repairability, proposed rule, authority, and blocking flag.
Messages never contain parser snippets, validator values, or raw source content.
Coverage distinguishes recognized, parsed, invalid, and unassigned artifacts.
Partial counts cover recognized valid records, not an asserted complete inventory.

Missing sources are MISSING, invalid syntax/schema/IDs are INVALID, unsupported
variants are UNSUPPORTED, missing assignments UNASSIGNED, conflicting authority
AMBIGUOUS, drift STALE, and unattested freshness UNKNOWN. Valid sibling records
remain visible. Duplicated artifact IDs are excluded from authoritative counts.

## Identity and provenance rules

Page identity is the `page_id` field, independent of both filename and Mendix
implementation name. New UI-Agent output uses `planning/ui-inventory/<page_id>.yaml`;
historical descriptive filenames such as `Customer_NewEdit.yaml` remain readable as
storage-only legacy variants. `page_name` records the current Mendix implementation
binding and may change without changing `page_id`. Duplicate valid `page_id` values
are blocking and never resolve by filename or name similarity. Long-lived artifacts
reference Page IDs; a functional Requirement does not change when its implementation
binding changes.

New Test Contracts use `planning/test-contracts/TC-NNN.yaml`. For compatibility,
`TC-NNN-<ASCII descriptive suffix>.yaml` is a documented legacy variant only if
the internal ID is exactly that numeric prefix and the complete canonical schema
validates. Duplicate IDs or conflicting internal IDs are never accepted.

An explicit `wave_id` remains authoritative. Missing assignments can be repaired
only by `migrated_from_checklist_v1`: `migrated_from` must name one existing,
parseable `planning/checklists/W*-implementation-checklist.yaml`, the exact wave
must exist in canonical process state, and any declared checklist wave must agree.
No task-ID/title similarity is used. A contradiction is DECISION_REQUIRED.
`assignment_provenance` preserves the rule and exact source; `migrated_from`
is retained. Workpackages are never invented; absence is reported separately.

## Legacy Compatibility Matrix

This matrix separates observed legacy shapes from verified framework producers. Example Project's CCM
report identifies the checked Core baseline as MxAgile 1.9.0; SCR-002 records an earlier 1.8.0
installation. The exact producer/version for each individual legacy artifact remains unverified.
Compatibility does not authorize editing Example Project or accepting arbitrary fields.

| Cluster | Legacy shape → current shape | Historical producer evidence | Equivalence and migration/projection | Original mutation / ambiguity | Validation after projection |
|---|---|---|---|---|---|
| FW-A Test Contract | `proof_points[].traceability.requirement_ids[]` → same canonical PP-level field; TC-level `requirement_ids[]` remains broader contract coverage | Previous `test-contract.schema.json` rejected the field; exact project producer/version unknown | Direct relationship semantics; additive Contract v2 field, no rename or data conversion | No mutation required. Missing/empty PP list is allowed; duplicate IDs fail schema; unknown targets are reported, not invented | Full TC schema, canonical Requirement-target lookup, duplicate/ambiguous identity checks; artifact index emits distinct TC- and PP-provenance edges |
| FW-B Requirement source | `stakeholder` → category; `design_contract_revN` → `source: design_contract`, `source_ref: REV-N` | `stakeholder` and `security_review` occur in framework fixtures; Discovery documents `source: design_contract`; historical revision-string producer/version not found | `requirement_design_contract_revision_v1` projects only the exact `design_contract_rev<digits>` form; finite categories are enumerated | No mutation required. Unknown values and conflicting `source_ref` remain schema/authority diagnostics | Requirement v2 schema plus full artifact-reference validation; source reference remains provenance, not ACTIVE_TARGET authority |
| FW-C Process State (FINDING-013) | `runtime_verification`, `feature_scope`, `terminal_state`, or unknown audit keys at process-state root → no automatic target | Current producer/policy owns wave phase and gates in `planning/lifecycle/process-state.yaml`; exact historical producer/version for the reported keys not found | No equivalence established: runtime evidence belongs to parity records, feature-scope progress to mission state, terminal phases to lifecycle definitions | No mutation/projection. Wrong-authority fields are `DECISION_REQUIRED`; unknown fields remain schema errors. `done` remains the only configured terminal wave phase | Current process-state v1 schema; lifecycle/mission/parity authorities remain independently validated |
| FW-D Evidence Manifest (FINDING-012) | ISO-date `created` → `created_at`; `scenarios[]` → `entries[]` only when the complete transformed manifest validates | Current producer is `evidence-manifest.schema.json`; historical producer/version and original `scenarios` granularity are unverified | `evidence_manifest_created_v1` and `evidence_manifest_scenarios_v1` are read-only aliases; the entire transformed manifest must validate, including required `wave_id` | No mutation required. Missing/unknown `wave_id` is not inferred from filename, entries, or timeline; conflicts and non-equivalent payloads remain diagnostics. Stale result and capture provenance are copied unchanged | Full manifest schema, wave and Requirement reference checks, evidence-path checks; no state promotion or freshness update |
| FW-E Requirement date | ISO-date `created` → `created_at` | Current Requirement schema previously had neither field; exact historical producer/version unknown | `requirement_created_v1` maps a valid ISO date only | No mutation required. Conflicting values, malformed date, or any other shape is not projected | Full Requirement v2 schema and Doctor reference validation |
| FW-F Page/UI Inventory | Template-era `section_id` → `sections[].id`; navigation `target` → `leads_to_page` only when the legacy item also has `action_id`; current producer fields include `page_name`, `title`, `mockup_id`, structured roles | `.mxagile/templates/generic/ui-inventory/template.yaml` is direct producer evidence for these legacy properties; its version is not recorded | `page_section_id_v1` is an exact alias. The navigation target is only a projection when its action binding is already explicit; the old template omitted `action_id`, so those records do not validate through this rule. Page Contract v2 explicitly models the remaining producer fields and rejects unknown root/core nested properties | No mutation required. Missing action bindings, conflicting aliases, `page`/`source`/`screen_id`, unknown mockup references, and active-target drift are not guessed or rewritten | Full Page v2 schema, existing ACTIVE_TARGET/revision checks, and path/reference checks |
| FW-G Task Inspect (FINDING-011) | Current `inspect.entity` + `expect` and `inspect.microflow` + `expect` producer forms are both canonical | `.mxagile/skills/test-generate.md` documents both forms. FINDINGS.md reports 13 affected tasks; exact payload/version is not available | Task Contract v2 explicitly accepts an optional module-qualified entity name or microflow plus required `expect`; no unknown fields are projected | No physical migration or field deletion. Missing `expect`, missing target, malformed entity names, and unknown nested keys remain schema diagnostics | Full Task schema; producer output is schema-tested. The exact 13 project payloads remain unverified |
| FW-H Verification Impact (FINDING-014) | Non-TC `*-verification-impact.yaml` stored in `planning/test-contracts/` → unsupported artifact in a TC-only collection | FINDINGS.md identifies `REV14-verification-impact` as not a Test Contract; payload and producer/version are unavailable in this repository | No projection and no new Core schema without a verified payload/authority contract. Current TC discovery is restricted to `TC-*.yaml` | No physical move or mutation. Doctor reports `UNSUPPORTED_VARIANT` / `UNSUPPORTED`; it does not apply TC ID/schema rules or count the record as a Test Contract | TC records still require canonical TC identity and full schema. Whether the analysis belongs under another directory or needs a contract remains unresolved |
| FW-I Standalone Interaction Records (FINDING-015) | `interaction-metadata-*.yaml` / `interaction-states-*.yaml` in UI inventory → not Page records | Current UI-Agent/Page contract stores `interaction_states` inside a Page; historical standalone producer/version and payload are not available | No Page projection: standalone records have no established Page identity/authority. They are excluded from Page/Board target consumption and reported as `UNSUPPORTED_VARIANT` / `UNSUPPORTED` | No mutation, page ID, navigation, or relationship is invented. A dedicated record contract or authoritative migration requires payload evidence | Current Page schema remains strict; exact legacy interaction-record contract remains unresolved |
| FW-J Legacy Story Sources | `planning/stories/REQ-NNN*.md` alongside `requirements/REQ-NNN.yml` | Discovery historically writes story Markdown; `canonicalize_artifacts.py` consumes it as explicit migration input | No automatic superseded mapping from matching IDs. Project Status and Artifact Index read canonical Requirement YAML only, so story Markdown does not duplicate Board counts | No deletion or physical migration required for status/Board. Canonicalization remains an explicit controlled migration; unmatched stories remain historical source input | Doctor does not count story Markdown as Requirements; canonical references resolve only against unique Requirement YAML records |

`mockup_id` is upstream Design Contract identity; `mockup_name` identifies the SPA
bundle directory. They are not aliases. Page Contract v2 requires `mockup_name`
when `target_revision` is present; no bundle identity is inferred from `mockup_id`.
The legacy template's unbound revision example was removed. Current producer
instructions, canonical ACTIVE_TARGET and full revision/path validation remain
authoritative; missing identity and reference drift are never guessed or repaired.

### Projection and Version Rules

Schemas marked `x-mxagile-contract-version: 2` are Requirement, Test Contract, Evidence Manifest,
Page, and Task. Task v2 accepts the existing bounded `inspect.entity` producer form; Task records
do not require an in-artifact schema version or physical migration. Test Contract records may use `schema_version: 1` or `2`; new producers write `2` and
v1 remains readable. Process State remains v1 and was not broadened. Read-only projections return
deep copies, are idempotent, preserve source bytes, and never write project artifacts. A projection
is exposed as `LEGACY_VARIANT` / `SAFE_DETERMINISTIC` only when the projected whole artifact
validates. Conflicts fail closed. Physical migration is not required for these shapes; the
existing repair apply path does not rewrite these alias forms.

Evidence projection never changes `parity_result`, verification timestamps, capture IDs, capture
groups, provenance, or Requirement/Proof-Point links. `scenarios` is not treated as equivalent
merely because it is an array: the target `entries` schema and post-projection references must pass.

## Repair contract

### Explicit migration rules (current schema contract)

Rules live here and in `scripts/project_compatibility.py`, not in a second registry.

| Rule | Source / target | Preconditions and transform | Conflict / preserved semantics | Idempotence / validation |
| --- | --- | --- | --- | --- |
| migrated_from_checklist_v1 | Legacy checklist provenance / current task schema | One existing parseable exact W*-implementation-checklist.yaml; wave exists; declared wave agrees; append wave_id and assignment_provenance | Explicit contradictory wave or checklist declaration defers; task status, original provenance and all other bytes retained | Explicit wave prevents repeat; full task schema + Doctor after apply |
| QUOTE_TEXT_SCALAR | Invalid plain YAML text scalar / same current artifact schema | Parser points to an allowed single-line text field containing colon; quote exact scalar | No comments, tags, anchors, lifecycle fields or ambiguous indentation; same text value | Valid YAML is unchanged; entire artifact schema + scoped revalidation |

Schema diagnostics are classified individually. Missing GWT id/given/when/then,
proof_points and other required content, unknown enums (including confirmed), missing Task inspect
targets/expectations, and unrecognized inspect fields require decisions, not invented content. Extra fields
require bounded agent review; no automatic deletion is authorized absent a
documented lossless migration contract. A file can therefore have both
DECISION_REQUIRED and AGENT_REPAIRABLE diagnostics. Unsupported formats remain
separate from reviewable schema constraints.

No historical canonical page/source -> page_id/source_mockup mapping contract was
found in the framework schema history at this hardening baseline. No rename/drop
rule is authorized merely by similar names. Conflicting old/new values never
authorize automatic migration. Evidence references likewise require unique
canonical authority, not timeline inference.

Missing scratch checklist provenance can be AGENT_REPAIRABLE when schema-valid
canonical Evidence Manifests explicitly trace the task's Requirement/Spec to one
existing wave. This supplies bounded review authority, not an automatic assignment
rule. Multiple or missing candidate waves remain DECISION_REQUIRED.

DEC-NNN.md records are retained as historical read-only identities; their text is
not interpreted as current status, counted as confirmed, or forcibly migrated.
Unknown filenames/variants retain their original unsupported diagnostics.

- SAFE_DETERMINISTIC: schema-valid minimal quoting of a single-line text field
  whose colon is the parser error, or the exact provenance rule above.
- AGENT_REPAIRABLE: canonical authority is known but a semantic review is needed.
- DECISION_REQUIRED: contradictory or missing authority; never autonomously solved.
- UNSUPPORTED: no implemented transformation rule.

Scalar quoting applies only to documented text fields, not status, gates, IDs,
phase, active target, or evidence fields. Scalars involving comments, YAML tags,
anchors, aliases, flow syntax, or ambiguous indentation are not automatically
repaired. Quoting must preserve the exact text value and validate the whole file.
Comments and ordering elsewhere are retained; files are not reformatted.

Dry run produces exact file scope, before/after byte fingerprints, diagnostic IDs,
source/contract fingerprints, and a plan hash. Arbitrary text previews are redacted
to prevent secret leaks. This is not permission to log original values. Review
the local scoped artifacts without copying sensitive values into reports.
Apply recomputes the plan, rejects stale inputs, validates replacements, writes
each file atomically, reruns Doctor and Builder, and rejects new blocking findings
or unresolved targeted diagnostics. Existing unrelated problems can remain.
On failure, only written files are restored to their original bytes; concurrent
edits are never overwritten by rollback and require manual recovery.

No repository-wide git commands, resets, cleans, commits, or lifecycle promotions
are part of repair. Compatibility does not fulfill gates, accept requirements,
close findings, answer decisions, or verify evidence.

## Bounded agent repair

Input is the structured diagnosis plus only its affected canonical artifacts and
their named authorities. Do not start a new free-form repository-wide discovery.
Agent review must establish the intended meaning and approval under the existing
mission/autonomy contract. The system check never authorizes or applies repair.

To submit reviewed candidates, place only the exact diagnosed relative paths in
an external candidate directory and run `repair --dry-run --candidate-dir <dir>`.
Apply must repeat that directory and the reviewed plan hash. Candidates must parse,
validate against their schema, and preserve protected status/gate/identity values;
invalid-source semantic reconstruction and all unsupported cases remain deferred.
The post-check must remove targeted diagnostics without introducing blockers.
This mechanical check is not a substitute for agent review of business meaning.

## Safety and reality test

Only canonical status sources are inspected. Never read or log `.env.mendix`,
credentials, tokens, or arbitrary machine state. Reject path traversal and symlink
components. Diagnostic source links return redacted metadata, never raw invalid
source contents. Diagnostic data is rendered as text, not HTML.

Example Project is reality evidence only in the framework mission. After framework
validation, commit and update, a separate authorized reality test runs Doctor,
reviews the exact plan, applies permitted repairs, reruns validation, and checks
Board coverage against actual project artifacts. No claim of repaired Example Project
is permitted before that separate evidence exists.