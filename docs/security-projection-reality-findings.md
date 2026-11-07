# Security Projection: extraction spike and reality-findings triage

Date: 2026-11-07. Baseline: HEAD `8cf7013` plus concurrent uncommitted Board work (not touched).
Contract and schema: `.mxagile/policies/security-projection.md`, `.mxagile/schemas/security-matrix.schema.json`.

## 1. mxcli extraction spike (v0.20.0, read-only)

| Need | Source used | Result |
|---|---|---|
| App security (level, strict mode, guest, demo users) | `SHOW PROJECT SECURITY --json` | reliable |
| User Roles and Module Role mapping | `SHOW USER ROLES --json` + `DESCRIBE USER ROLE <n> --json` (MDL text parsed) | reliable; mapping exists only in the MDL text |
| Module Roles | `SHOW MODULE ROLES --json` | reliable |
| Page / Microflow grants | `SHOW SECURITY MATRIX --json` (+ `SHOW PAGES/MICROFLOWS`) | reliable; matrix lists only granted resources, ungranted are inferred from the complete listing |
| Nanoflow grants | **not in matrix, not in DESCRIBE NANOFLOW**; `mxcli bson dump --type nanoflow` field `AllowedModuleRoles` | reliable, one process per nanoflow, uses a debug-level tool |
| Entity rules, members, XPath | `SHOW ACCESS ON <entity> --json` (only entities with `AccessRules > 0`) | reliable; JSON has XPath verbatim, human output does not escape quotes |
| Entity CRUD letters in matrix | `SHOW SECURITY MATRIX` Entity rows | **lossy** (no members, no XPath); deliberately ignored |
| Workflow access | matrix text says it is controlled by microflows/UserTask targeting | not extracted |
| `DESCRIBE APP SECURITY`, `LIST ...` (public docs) | | **do not exist** in v0.20.0 (parse errors); documented syntax was not trusted |

Reality evidence:
- Real project `Digitales-Labor/LabormaterialVerwaltung.mpr` (read-only; 116 entities, 81 pages, 184
  microflows, 16 nanoflows): all sections complete, schema valid, 3 consecutive runs gave the same
  fingerprint (third run did not rewrite), 61 s / 51 s / 75 s.
- Cross-check of 25 entities (41 member lists): projection members equal the independent
  `DESCRIBE ENTITY` GRANT statements (read/write lists); the only 3 differences were the checking
  script matching two rules with the same role set, which the projection correctly keeps as two rules
  (one XPath-constrained, `[id='[%CurrentUser%]']`, verbatim).
- XPath and member-level survival: this project has one real XPath rule; additionally a throw-away copy
  of an empty Mendix app in a temp directory received an XPath rule (`[Country = 'DE']`) via mxcli and
  was extracted losslessly. The opt-in real test `RealMxcli` passes against it. CapTrack was not
  available on this machine, so it was **not verified**.
- Not shown: stability across mxcli versions; scale beyond ~120 entities.

Conclusion: usable for deterministic extraction with the stated limitations. Option C (optional) is
recommended, Option B after one CapTrack reality run.

## 2. Reality findings triage

### K1 Long-runner / KeyboardInterrupt: NOT_OBSERVABLE (cause), policy ALREADY_FIXED (uncommitted)
- No log of the incident exists in the repository; the only `KeyboardInterrupt` occurrences are handlers
  in `serve_project_board.py` and `test_parity_gallery.py` (they absorb it, they do not raise it).
- `tests/run-full-regression-logged.ps1` pipes `pwsh run-all-tests.ps1` through `Tee-Object`; a console
  interrupt delivered to the foreground process group reaches the whole pipeline, so a host-side
  cancel, a console Ctrl+C or a terminal reuse are indistinguishable from inside the framework.
- Observed in this session: the host moved a call that exceeded its 120 s timeout to the background and
  kept it alive instead of interrupting it. That is one host's behaviour, not a general guarantee.
- Whether a host cancels tool calls cannot be determined from the framework. No watchdog, no repeat of
  Full Regression. The working-tree `test-workflow.md` section "Laufende Prozesse und Ergebnissemantik"
  already requires own session, no foreign commands, `INCOMPLETE` + unknown interrupter if unproven.
  That text and its tests are in uncommitted foreign changes (`test-workflow.md`,
  `test-verification-lifecycle.ps1`); this patch does not touch or commit them.
- Change: none.

### K2 Long-runner evidence semantics: ALREADY_FIXED (uncommitted in the working tree)
The same working-tree text and `test-verification-lifecycle.ps1` lines 113-127 pin: SILENT is not HUNG,
interrupted aggregate = `INCOMPLETE`, external blocker = `BLOCKED` not FAIL, a separate suite does not make
an interrupted aggregate PASS, no invented counts, no automatic expensive retry. Change: none. Risk: until
the owner commits it, HEAD lacks it.

### K3 Child model observability: NOT_OBSERVABLE (retained)
`agent-delegation.md` states a requested model/effort "is not proof of the actual model or accepted
effort"; adapters carry no host-confirmed actual-model field; nothing in this host's tool results
reports the actual child model. A→C stay known, D stays `NOT_OBSERVABLE`. Change: none.

### K4 Wave reality evidence: ALREADY_FIXED / sufficient
HEAD `build_project_status.py` already derives waves, Task→Wave mapping (`wave_id`, gap
`TASK_WAVE_MAPPING_PARTIAL`), per-wave checklists and phase from `process-state.yaml`; `lifecycle-resync.md`
reconstructs Wave inventory after interruption; `implementation-control.md` (commit `c74382e`) requires
the split/cohesion rationale in `planning/execution-waves.md`. The rationale is human-readable text, not
machine-extracted — deliberately, to avoid a second Wave data model. Change: none.

### K5 Mocketeer compatibility: NO_UPDATE_NEEDED (for the in-repo product)
`products/MxMocketeer` (design-intent/mockup agent) contains no reference to Task/Wave, lifecycle resync,
delegation/model routing, verification evidence or the security matrix; its role contract
(`mendix-design-guide.txt`, commit `ff78c99`) treats entities/XPath/mxcli as unconfirmed candidates and
is unaffected. The Security Projection is downstream and read-only. Mocketeer installations in other
repositories were not inspected: `NOT_ENOUGH_EVIDENCE` for those. No Mocketeer file was changed.
