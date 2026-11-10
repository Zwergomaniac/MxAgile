# Policy: Test-Harness Cleanup Discipline (RF-007)

Defines the required discipline for managing repository-state mutations introduced
by test harnesses (e.g. MxTest) during acceptance campaigns.

Related policies:
- `policies/test-workflow.md` — Playwright/browser verification workflow
- `policies/test-contract-derivation.md` — test contract structure
- `policies/mission-completion.md` — final completion cleanliness gate

---

## Problem

Test-endpoint and acceptance harness operations (MxTest, mxunit, Playwright setup)
may inject artifacts into the repository:

- MxTest module/model content
- model units the harness materializes (only with explicit ownership, see below)
- `javasource/mxtest/`
- `themesource/mxtest/`
- Project settings changes (module activation, security settings)
- Additional database tables or constants from the test module

These injected artifacts can pollute the working tree and cause:
- False "dirty working tree" signals
- Post-campaign cleanup confusion
- Unintended commits of test harness artifacts
- Missed distinction between test artifacts and application changes

---

## Artifact Classification

Before executing acceptance tests and after completing them, classify repository changes:

| Class | Definition | Treatment |
|-------|-----------|----------|
| `REQUIRED_APPLICATION_CHANGE` | Change introduced by the mission itself (implementation change) | Commit normally; preserve |
| `REQUIRED_ACCEPTANCE_EVIDENCE` | Verification plan, wave report, acceptance log | Commit as evidence artifact |
| `TEMPORARY_TEST_HARNESS_ARTIFACT` | Injected by the test harness; not part of the application; reversible | Remove/restore deterministically after test |
| `UNEXPECTED_OR_UNKNOWN` | Change not explained by the above | Do NOT automatically delete; classify first |

### Canonical Mendix Model Artifacts

In projects where `mprcontents/**/*.mxunit` units exist next to the project `.mpr` (MPRv2 project
format), those units ARE the canonical model. Each document is one unit. Together with the `.mpr`
they are productive project artifacts, never temporary test output by default.

- Ownership of a temporary test-harness artifact is **never inferred from a file extension**.
  `*.mxunit` → temporary → restore/delete is forbidden.
- Cleanup may change a canonical model artifact (`*.mpr`, `mprcontents/**/*.mxunit`) only with
  **explicit ownership**: recorded at harness injection, with explicit model-unit acknowledgement, and
  unchanged content since then.
- A model unit whose content changed after the harness run (fachliche Änderung, Studio Pro save,
  mxcli mutation) has no provable harness ownership any more → preserve and classify.
- An untracked canonical unit created by legitimate model materialization is not deleted because
  of its extension.
- Same semantics in the main checkout and in every linked worktree. Ownership records are
  worktree-local and never authorize cleanup in another worktree.

### Explicit Ownership and Cleanup Plan

Record ownership immediately after harness injection:

`python .mxagile/tools/test_harness_cleanup.py --project-root . --record <paths...> --harness MxTest`
(add `--model-unit` only for model units the harness itself created; framework development:
`scripts/test_harness_cleanup.py`).

Before cleanup, derive the read-only plan:

`python .mxagile/tools/test_harness_cleanup.py --project-root .`

Only `removable` entries may be deleted (`delete-untracked`) or restored (`restore-from-HEAD`).
Every `preserved` entry stays untouched and must be classified (`REQUIRED_APPLICATION_CHANGE`,
`REQUIRED_ACCEPTANCE_EVIDENCE`, `UNEXPECTED_OR_UNKNOWN`). A missing or invalid ownership record means
nothing is removable. The planner never deletes, restores or writes the index.

---

## Required Lifecycle

```
1. PRE-TEST SNAPSHOT
   → git status (record baseline)
   → Note which files are modified/untracked BEFORE harness activation

2. TEST HARNESS ACTIVATION
   → Harness injects artifacts (MxTest module content, javasource/mxtest/, etc.)
   → Record explicit ownership of injected paths (test_harness_cleanup.py --record)
   → Run acceptance test campaign

3. CLEANUP
   → Identify newly introduced files vs. pre-test baseline
   → Derive the read-only cleanup plan (test_harness_cleanup.py)
   → Classify each change (see Artifact Classification above)
   → Remove only plan-`removable` TEMPORARY_TEST_HARNESS_ARTIFACT entries deterministically
   → Preserve REQUIRED_APPLICATION_CHANGE and REQUIRED_ACCEPTANCE_EVIDENCE

4. POST-TEST VERIFICATION
   → git status AFTER cleanup
   → Remaining changes must be explainable (REQUIRED_APPLICATION_CHANGE or REQUIRED_ACCEPTANCE_EVIDENCE)
   → UNEXPECTED_OR_UNKNOWN changes: do NOT delete; report to developer
```

---

## .gitignore Usage Rules

Use `.gitignore` ONLY when:
1. The file type is **always** a transient artifact across all projects (never source).
2. Adding it to `.gitignore` does NOT hide repository mutations that should be detected.

Do NOT use `.gitignore` to solve harness pollution by hiding everything.

Rationale: A `.gitignore` that silences harness artifacts also silences accidental
mutations that should be detected and reviewed.

---

## MxTest Specific Rules

### Patterns typically TEMPORARY_TEST_HARNESS_ARTIFACT

Still subject to explicit ownership; a pattern match alone never authorizes removal.

```
javasource/mxtest/
themesource/mxtest/
deployment/mxtest/
```

### Patterns that require classification before cleanup

```
*.mpr                              # canonical model database — productive artifact
mprcontents/**/*.mxunit            # canonical model units (MPRv2) — productive artifacts
resources/mxtest/                  # may contain test evidence
planning/lifecycle/                # may contain acceptance reports (REQUIRED_ACCEPTANCE_EVIDENCE)
.mxagile/                          # NEVER remove framework artifacts automatically
```

### MxTest module activation in Mendix project settings

If MxTest activation modifies project settings (`.mpr` configuration):
1. Record the pre-test settings state.
2. Restore after test unless the activation is an intentional permanent addition.
3. Do NOT commit activated MxTest as an application change.

---

## Completion Gate Integration (RF-010)

The Final Completion Cleanliness check in `policies/mission-completion.md` MUST
run AFTER the last test-harness action, not before.

If remaining changes are TEMPORARY_TEST_HARNESS_ARTIFACT:
→ Clean them deterministically.
→ Re-run git status verification.
→ Only then claim clean completion.

If remaining changes are UNEXPECTED_OR_UNKNOWN:
→ Do NOT claim clean completion.
→ Report the unknown changes for developer review.
