# Mocketeer Interaction Coverage Audit

## Audit Status

**FINDINGS — REV37 contract and runtime-source inspected read-only on 2026-11-12.**
Source supplied by the user:
`D:\MTC\Mendix\Projekte\CapTrack\CapTrack-devrick\input-resources\ui-ux\20261104_fte-plannung_rev37_functional-gaps-closed.html`.
Size: 567,868 bytes, 5,579 lines. SHA-256:
`515409263B6FD3B8417AD4C413FE47693B14FCB26866756E2E37A4FBA52C2F67`.
No input file was changed, copied into the framework, or executed. Older revisions
were not needed for the eight current-state cases. Browser interaction, cross-user
execution and Mendix enforcement are **NOT VERIFIED**, not PASS.

The embedded `#mocketeer-spec` starts on source line 377. JSON parses successfully;
`mockup.id` is `fte-plannung`, revision 37, predecessor 36, schema version `1.0`.
The product-specific layout contains 125 requirements, 61 decisions, 25 business
rules, 14 `interaction_metadata` entries and 20 nested effects. It has no top-level
`roles`, `screens` or `flows` arrays. The three top-level `permissions` records concern
AppAdmin; other role/scope assertions occur in requirements and source code.
Do not silently treat this layout as the generic contract or invent missing flow IDs.

`DECLARED` below means an assertion in the supplied contract, preserving its original
status, not independent confirmation of stakeholder approval. Source-code inspection
is identified separately; it is not an `OBSERVED` browser outcome.

Sources inspected: the migrated Design Contract and Business Flow material now embedded
in `skills/mocketeer-design-contract/SKILL.md` and
`skills/mocketeer-business-flows/SKILL.md`, plus the MxAgile Business Flow, Page,
Revision, and Test Contract schemas and the Design Contract Intake, Test Contract
Derivation, Impact Resolution, and Test Staleness policies.

## Current Contract Surface

- `screens[].interaction_states[]` can declare a trigger, initial/resulting UI state,
  visual/data/navigation/permission effects, persistence, role references, and nested
  typed UI effects. Effects can have stable IDs, preconditions, source IDs, target,
  affected roles/screens, downstream artifacts, and required action.
- `flows[].steps[]` can declare user/system actions, actor roles, screen/requirement/
  decision references, conditional transitions, and an `effects[]` reference list.
- Roles and permissions can state capabilities and organizational/data scopes. Explicit
  `cannot[]` entries can produce negative authorization proof points.
- Revision deltas can identify changed effects, roles, screens, source IDs, and
  downstream artifacts. MxAgile marks affected Test Contracts for review and can derive
  positive/negative role proof points after canonical Requirements exist.

These are useful building blocks, but the documented top-level Design Contract has no
shared `effects[]` registry even though the Business Flow schema describes step
`effects[]` as references to `effects[]`. That reference boundary is not consistently
defined or validated. Further, `affected_roles` does not mean “these roles observe this
effect”; permission scope does not bind that scope to a specific notification or
observation. `status` values describe lifecycle/decision disposition, not a complete
DECLARED / INFERRED / OBSERVED / PROPOSED provenance model.

## Coverage Matrix

The matrix rates generic contract capability, not REV37 population. The fixture-specific
evidence and classifications follow below; generic expressibility is not actual coverage.

Codes: `AE` = ALREADY_EXPRESSIBLE; `EN` = EXPRESSIBLE_BUT_NOT_NORMALIZED;
`RP` = PRESENT_ONLY_IN_REQUIREMENT_PROSE; `RT` = PRESENT_ONLY_IN_MOCKUP_RUNTIME;
`IM` = INFERRED_BY_MXAGILE; `NE` = NOT_EXPRESSIBLE as a first-class structured
relationship; `AM` = AMBIGUOUS / no runtime observation established.

| Information element | 1 Transfer / decision | 2 User notification | 3 Revoked scope / save | 4 Team merge | 5 Historical month | 6 Center switch | 7 Team control | 8 Hierarchy sync |
|---|---|---|---|---|---|---|---|---|
| Actor identity (person or system) | EN | EN | EN | EN | EN | EN | EN | EN |
| Actor role | AE | AE | AE | AE | AE | AE | AE | AE |
| Interaction and trigger | EN | EN | EN | EN | EN | EN | EN | EN |
| Preconditions | EN | EN | EN | EN | EN | EN | EN | EN |
| Previous state | AE | EN | AE | EN | AE | EN | AE | EN |
| Business state change | EN | EN | EN | EN | EN | EN | EN | EN |
| Observer actor/role | EN | NE | EN | EN | EN | EN | EN | EN |
| Observer scope | EN | EN | EN | EN | EN | EN | EN | EN |
| Positive visible/business effect | EN | EN | EN | EN | EN | EN | EN | EN |
| Explicit effect-specific negative observers | NE | NE | EN | NE | EN | NE | EN | NE |
| Follow-up interaction | EN | EN | EN | EN | EN | EN | EN | EN |
| Multi-interaction causal link | EN | EN | EN | EN | EN | EN | EN | EN |
| Requirement references | AE | AE | AE | AE | AE | AE | AE | AE |
| Decision/business-rule references | EN | EN | EN | EN | EN | EN | EN | EN |
| Mendix candidates/downstream references | AE | AE | AE | AE | AE | AE | AE | AE |
| Test Contract derivable | EN | EN | EN | EN | EN | EN | EN | EN |
| Positive and negative role evidence | EN | EN | EN | EN | EN | EN | EN | EN |
| Revision reconciliation of the whole chain | EN | EN | EN | EN | EN | EN | EN | EN |
| DECLARED / INFERRED / OBSERVED / PROPOSED provenance | EN | EN | EN | EN | EN | EN | EN | EN |
| Browser/Mendix execution evidence | AM | AM | AM | AM | AM | AM | AM | AM |

### Actual REV37 Evidence

All contract IDs below occur in the JSON on line 377. Source line anchors refer to
the hashed external file, not to generated framework files. `RT` in this table means
runtime implementation source only; it does not assert successful execution.

| Case | Actual declaration and structured metadata | Runtime-source anchor | Actual coverage / gap |
|---|---|---|---|
| 1 Transfer / decision | REQ-023, REQ-060; no dedicated transfer INT/effect chain | `canDecideTransfer`, `approveTransfer`, `rejectTransfer`, lines 833-883; notification actions 4875-4900 | RP + RT: target-unit decision guard and accept/reject branches exist in source; explicit notification observers/excluded scopes and stable causal links are not declared |
| 2 Per-user notification | REQ-059 explicitly requires per-user acknowledgement and isolation | `getPendingNotifs`, 890-904; acknowledgement handlers 4901-4910; center state keys 5519 | RP + conflicting RT: `A.notifAck` stores notification IDs without a user key; center dataset separation is not per-user isolation |
| 3 Revoked scope / save | REQ-121, DEC-056; no dedicated save-time INT/effect | `openEntryEditor`, 2515-2614; `commitMatrix` / `applyMatrixValue`, 4651-4705 | RP + RT: entry opening checks role/scope, but reviewed commit callbacks lack fresh role/scope authorization; period locks are not a replacement |
| 4 Team migration / merge | REQ-084/085/086, DEC-041, RULE-TEAM-001; INT-TEAM-MEMBER-MIGRATION, EFF-FIRST-TEAM-MOVE, EFF-TEAM-REMOVE-MOVE, EFF-TEAM-MODE-OFF-MERGE | `mergeData`, `deptToFirst`, `teamToTeam`, `teamsToDept`, 5298-5320 | EN + RT: targets, data movement, source IDs and affected views are declared; sum/dedup/history invariants require execution evidence; observer scopes are not normalized |
| 5 Historical month | REQ-090, DEC-043, RULE-HISTORY-001; INT-HISTORICAL-READONLY, EFF-HISTORICAL-MUTATION-BLOCK, EFF-HISTORICAL-NAVIGATION-REMAINS | historical predicates, wrappers and UI/capture guards, 5370-5413 | EN + RT: positive navigation and explicit negative mutating operations are declared; universal bypass-resistant enforcement is not proved by these UI paths |
| 6 Center switch | REQ-099/101/102, DEC-046, RULE-CENTER-005; INT-CENTER-DATASET-SWITCH has ordered `result` prose but no nested effects | `persistActive`, `activate`, `bindDatasetSwitcher`, 5552-5557 | EN + RT: save old dataset -> restore new -> replace identity/roles -> default view -> render is explicit; effect IDs and testable scoped transition links are missing |
| 7 Team control | REQ-116/118, DEC-051/053, RULE-TEAM-004; no dedicated control-change INT/effects | `myRoles`, `canEdit`, `canEditTeam`, 518-544; cached CU identity and dataset switch | RP + partial RT: role checks exist; no source-reviewed ownership-change transition proving immediate scope refresh and discard of unsaved edits |
| 8 HierarchyTree team sync | REQ-046/117/122, DEC-049/052/057, RULE-TEAM-005; no dedicated sync INT/effects | only HierarchyTree-labelled runtime path found is center-match UI 5565-5576, not automatic team sync | RP: automatic add/rename/archive, assignment-independent visibility and closure prerequisites are declared, but no linked sync chain or executing team-sync path was located |

### Case Findings

1. **Transfer.** Target-unit authorization is implemented in the reviewed decision
   path, but no transfer-specific interaction/effect IDs bind actor, preconditions,
   notification recipient, accept/reject result and later observer views. Positive
   target-role and negative out-of-scope test claims need explicit declaration, not
   inference from `canEditTeam` alone.
2. **Per-user notifications: material source/contract mismatch.** REQ-059 explicitly
   says another user's notification remains. The collector filters on an ID-only
   `A.notifAck` array and both acknowledgement handlers append only that ID. It also
   scans departments/teams without an explicit visibility check in the collector.
   Do not report user isolation or correct observer scope as covered. Verify with two
   actual identities and record per-user persistence and exclusion expectations.
3. **Revoked scope: material source/contract mismatch.** REQ-121 already supplies the
   missing business assertion: save-time reauthorization and complete rejection with
   no partial writes. `openEntryEditor` checks permission before creating the dialog;
   its `efSave` callback later validates fields/period locks and mutates captured data
   without a new `canEdit`/`canEditTeam` call. Matrix callbacks similarly retain their
   captured context. This is a source-reviewed gap, not an executed exploit or a claim
   about Mendix enforcement. Derive a negative UPDATE/EXECUTE proof point from REQ-121.
4. **Team migration.** Unlike the preliminary contract-only assessment, REV37 already
   declares concrete source/target moves and preservation criteria. The effects have
   stable IDs, `source_ids`, `affected_roles` and named downstream views, but no
   structured observer scopes or complete flow-step links. REQ-065/DEC-026's used-object
   deactivation rule and REQ-085/`teamToTeam` removal need lifecycle reconciliation;
   do not silently choose deletion semantics. Sum, deduplication and historical
   preservation checks remain required rather than inferred from `mergeData`.
5. **Historical month.** Explicit negative operation expectations already exist in
   EFF-HISTORICAL-MUTATION-BLOCK; EFF-HISTORICAL-NAVIGATION-REMAINS carries the positive
   counterpart. The predicate matches REQ-090's current-year acceptance criterion.
   Capture listeners, disabled controls and wrappers are only mockup source evidence;
   test already-open editors, keyboard/blur paths and backend guards independently.
6. **Center switch.** The ordered business sequence is already DECLARED in the custom
   metadata and RULE-CENTER-005, and is recognizable in the source. It must not be
   described as wholly absent. Normalization is missing: one prose result replaces
   typed effects and source/target scope assertions. REQ-099 explicitly limits this
   to a demo identity switch, not a production center-switch capability.
7. **Team control.** Immediate effect, retained history and discard of unsaved changes
   are explicitly DECLARED in REQ-118/DEC-053. Existing role predicates and cached
   `CU.roles` do not establish that change propagation happens immediately. No
   dedicated stable interaction/effect chain was found. New and removed owners/scopes
   need both positive and negative checks linked to REQ-118 and REQ-121.
8. **HierarchyTree.** Automatic team synchronization is DECLARED, not merely inferred.
   The located REV37 center-match path builds a synthetic candidate and links a center;
   it does not prove team add/rename/archive synchronization. Require evidence for the
   trigger, identity/idempotency, no-E4 visibility, archive preservation and month-close
   prerequisites; no new schema or fictitious flow IDs were added to fill the gap.

## Minimal Contract Decision

**Do not add `scenarios[]`.** Existing `flows[]`, interaction states, and typed effects
are the right homes for this information. Normalize the existing relationship first:
each flow step's `effects[]` must resolve to a stable nested `effect_id`, and ordinary
step ordering/branches should continue to use flow transitions rather than parallel
`caused_by` / `next_interaction` links.

REV37 confirms the requirements but also shows an existing custom `interaction_metadata`
layout. First define compatibility/intake mapping and stable effect-reference resolution
for that layout; do not flatten away its assertions or imply it already has generic flows.
The smallest likely additive extension is an optional effect-level declaration of observer
role, observation scope, and expected visibility (positive or explicitly negative),
plus a separate provenance value `DECLARED | INFERRED | OBSERVED | PROPOSED` for
interaction/effect assertions. Keep existing effect `status` for lifecycle and do not
promote INFERRED or OBSERVED facts to DECLARED. This is a **recommendation only**;
no schema was changed. The actual metadata, legacy field names and lifecycle/status
values must be reconciled before defining backward-compatible storage of these assertions.

## Reconciliation and Evidence Rules

- Compare declared Design Contract facts, MxAgile inferences, and observed mockup/app
  behavior as separate inputs. Preserve source, revision, and observation origin.
- Reconcile the affected interaction/effect IDs and their flow links; do not mark an
  entire unrelated Test Contract stale merely because the mockup revision changed.
- Derive positive and negative Test Contract proof points only from explicit declared
  role/scope assertions. An omitted observer is UNKNOWN, not implicitly forbidden.
- A confirmed Requirement/Decision/Business Rule remains the authority for its own
  concern. Mockup runtime behavior is OBSERVED evidence, not proof of PO intent.

## Follow-up Needed

Notification acknowledgement, save-time reauthorization and missing HierarchyTree
execution are application divergences for the next Mocketeer/Product Owner revision
round. After accepted clarification/revision, route their affected IDs through MxAgile
Reconciliation. Do not repair the external app or encode project-specific fixes into
this framework. The read-only findings remain fachliche evidence, not implementation.

The read-only contract/source inspection is complete; runtime acceptance is not.
Run the eight cases with explicit user/role/scope identities, particularly two-user
notification isolation and authorization revoked while an editor remains open. Record
positive and explicit negative observations separately and link them to the IDs above.
Then verify the real Mendix model/backend and reconcile only affected proof points.
No source app, legacy revision, framework schema, or business assertion was modified
by this audit. Reports and test evidence in the framework are the only audit outputs.