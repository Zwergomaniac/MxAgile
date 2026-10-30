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

## Repair contract

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

CapTrack is reality evidence only in the framework mission. After framework
validation, commit and update, a separate authorized reality test runs Doctor,
reviews the exact plan, applies permitted repairs, reruns validation, and checks
Board coverage against actual project artifacts. No claim of repaired CapTrack
is permitted before that separate evidence exists.