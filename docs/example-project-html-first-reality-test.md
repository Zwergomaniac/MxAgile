# Example Project HTML-First Reality Test

## Goal

Compare the existing Mendix-native `Region_Overview` baseline with a new parallel HTML-First experiment page. Both pages use the same active REV-020 authority, roles, and test data. Do not overwrite or convert the baseline page.

## Preconditions

1. Update Example Project to the MxAgile revision containing the UI settings resolver, Builder capability discovery, FULL mockup lifecycle, and Board Page Previews.
2. Confirm both pages' stable `page_id` values in `planning/ui-inventory/`. Do not use display names as override keys.
3. Project Authority must explicitly authorize the Builder Kit installation in Example Project. MxAgile does not install it automatically. Install the upstream `mendix-page-designer-html-mode` agent for the active harness and verify that the manifest and agent file are present.
4. Check the current harness using `Get-MxAgileCapabilities.ps1 -Format json -ResolveBuilderKit`. Require `installed: true`, `agent_available_for_harness: true`, and current-session `agent_delegable: true` before HTML-First routing. A null/unknown value blocks the route; do not silently fall back to Native.
5. The existing `Region_Overview` remains the Native baseline. The experiment is a separate authorized `PAGE-*` identity.

## Project Configuration

Keep project defaults Native and turn HTML First on only for the experiment page. Set mockup verification to FULL for the comparison and keep the runtime available after successful visual verification.

```yaml
ui:
  implementation:
    html_first: false
    overrides:
      PAGE-001: # Replace with the experiment page's canonical page_id from Example Project.
        html_first: true
  verification:
    mockup_driven: full
  runtime:
    leave_running_after_visual_verification: true
```

Resolve each page through the same shared resolver used by the Board:

```powershell
python .mxagile/tools/build_project_status.py --resolve-ui-settings --project-root . --page-id PAGE-<id>
```

The baseline should resolve to `MENDIX_NATIVE`; only the experiment should resolve to `HTML_FIRST`. Changing the setting does not convert an existing page.

## Build and Preview

1. Bind the experiment page to the same accepted REV-020 target as the baseline.
2. Delegate only the HTML feature work to `mendix-page-designer-html-mode`. Keep the Builder Agent bounded to the page and return its Mendix Artifact Report to the Main Agent.
3. Put source under `themesource/<module>/public/<feature>/`. Add the exact HTML entrypoint as `html_source` in the experiment page's canonical UI inventory record.
4. Open the Board `UI & Pages` tab and use `DESIGN PREVIEW` for fast HTML/CSS/JS iteration. This is static design feedback only; it proves no Mendix integration, roles, security, business flow, or runtime parity.
5. Keep the existing Native baseline unchanged. Do not resolve REV-020 authority conflicts R03/R04 in the Builder Agent.

## Mendix Integration and Verification

The Builder Artifact Report must be reviewed by the Main Agent for:

- Entities and associations
- Entity access rules and affected roles
- JavaScript Actions and their signatures
- Microflows and Nanoflows, including parameters and error behavior
- Pages, host Container, Events widget, and bindings
- HTML/JS/CSS source files
- Blocking items and open Studio Pro tasks
- Required integration verification

Project Authority performs required Studio Pro model setup. Mendix remains authoritative for persistence, roles, access rules, transactions, and business logic. Verify those rules with Ceko and E2 using the same representative test data on both pages. Record the role, expected result, observed result, and evidence for each check.

After integration, run the real local Mendix Runtime and verify both pages against REV-020. The canonical mode is `mockup_driven: full`: active reference, implementation, Runtime Evidence, scoped delta recheck, classification of all relevant deltas, parent workstream re-sync, then completion decision. `ACTIONABLE`, `UNKNOWN`, or `NOT_VERIFIED` keeps the parent active. `AUTHORITY_CONFLICT` is never PASS. HTML Preview is never Runtime Evidence.

After successful visual verification, follow the C1 runtime decision contract and the Project preference `leave_running_after_visual_verification: true`; leave a healthy compatible runtime running. Stop it only under the existing explicit or technical/safety rules.

## A/B Measurements

Record observed values only; do not estimate missing measurements.

| Measure | Native baseline | HTML-First experiment |
|---|---|---|
| Startup and time to first useful view | | |
| Fast preview iterations | | |
| Runtime verification iterations | | |
| HTML/JS implementation edits | | |
| Mendix model artifacts added or changed | | |
| Runtime restarts | | |
| Ceko verification | | |
| E2 verification | | |
| Security/access verification | | |
| REV-020 parity by required dimension | | |
| Open findings / authority conflicts | | |

Use the same REV-020 revision, roles, data, viewport set, and test sequence for both pages. Keep the Native and HTML-First results separate in the evidence records.

## Passive Observability Handoff

Observe the normal project run without adding prompts or extra lifecycle steps. Capture only facts available from the active harness, logs, status endpoints, and project evidence. Mark unavailable measurements `NOT_OBSERVABLE`; never estimate them.

Record where observable:

- SessionStart hooks, startup duration, unexpected provisioning, runtime downloads, Java sync, and database provisioning
- Requested/effective model profile and loaded MxAgile/Builder skills
- Agent and subagent routing, capability result, Builder invocation, and Artifact Report handoff
- Runtime recipe, explicit DB identity, START/REUSE/WATCH-RELOAD/RESTART/LEAVE_RUNNING/STOP
- Fast preview loops, real runtime loops, restarts, implementation iterations, and second UI-change maintenance effort
- Parent re-sync, user questions, parity/function/security results, and remaining conflicts

The observation must not dominate the normal project workflow. Record source and timestamp for each measurement.

## Readiness Gate

The experiment can start only when the Page override resolves correctly, the Builder Kit is installed for the authorized harness, the exact agent is available and delegable in the current session, no Native fallback is possible for the HTML-First page, and the active REV-020 authority is unambiguous for the dimensions being tested. R03/R04 remain unresolved `AUTHORITY_CONFLICT` unless their authoritative owner resolves them; the Builder Agent must not decide them.

## Compatibility Migration Note

Read-only inspection of the local Example Project checkout on 2026-11-05 found 39 blockers in the older Board: 14 diagnostics against a standalone interaction-state file, 10 against `SCN-REGIONS.yaml`, 14 across seven tasks, and one interaction-metadata ID mismatch. The current Core scanner recognizes the two standalone interaction filename families but did not yet recognize the legacy `PAGE-INTERACTION-STATES-REV5.yaml` form. After the Core scanner fix, a read-only projection of the same checkout reduced this to 24 blockers; the consumer project itself was not changed.

Recommended migration sequence:

1. Update Example Project to a Core build containing the standalone interaction filename compatibility fix, then restart its Board server. Do not move or rename `PAGE-INTERACTION-STATES-REV5.yaml` or `interaction-metadata-rev9.yaml` into canonical Page records; they are analysis artifacts, not Pages.
2. Preserve `SCN-REGIONS.yaml` as historical scenario/smoke evidence. Its prior smoke PASS must not be upgraded to current parity PASS. Create a new schema-valid parity record through the normal verification workflow, bind it to the active REV-020 Page identity, and record only evidence actually re-collected.
3. Keep the existing TASK statuses and meanings. The Core Task v2 contract now supports typed `entity`, `microflow`, `association`, `rule`, `snippet`, and `page` targets, with optional `expect`. The Doctor can losslessly migrate a single legacy structured target without changing its type or target. A task without an authoritative `expect` remains `EXPECTATION_MISSING` / `DECISION_REQUIRED`; target-existence output is not semantic acceptance. Do not delete inspect claims or derive expected outcomes from implementation prose.
4. Re-run the read-only compatibility projection after the Core update. Resolve the remaining schema diagnostics individually; do not bulk-rewrite or mark the project compatible merely to close the Board panel.
