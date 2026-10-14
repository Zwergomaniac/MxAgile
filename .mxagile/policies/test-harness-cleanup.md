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
- `*.mxunit` files
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

---

## Required Lifecycle

```
1. PRE-TEST SNAPSHOT
   → git status (record baseline)
   → Note which files are modified/untracked BEFORE harness activation

2. TEST HARNESS ACTIVATION
   → Harness injects artifacts (MxTest, mxunit, etc.)
   → Run acceptance test campaign

3. CLEANUP
   → Identify newly introduced files vs. pre-test baseline
   → Classify each change (see Artifact Classification above)
   → Remove TEMPORARY_TEST_HARNESS_ARTIFACT entries deterministically
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

```
*.mxunit
javasource/mxtest/
themesource/mxtest/
deployment/mxtest/
```

### Patterns that require classification before cleanup

```
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
