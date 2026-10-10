# Test Identity Lifecycle

Governs the authorized creation, use, and cleanup of test identities in MxAgile verification.

Complements:
- `policies/credential-discovery.md` — credential discovery order; mutation prohibition
- `policies/local-runtime-profile.md` — prohibition on test identity creation to mask configuration mismatch
- `policies/representative-fixture-contract.md` — scope-aware fixture completeness

---

## Fundamental Distinction

A **test identity** used for isolated verification is a temporary verification artifact.

It MUST NOT silently become a canonical project artifact.

```
TEMPORARY VERIFICATION ARTIFACT  ≠  CANONICAL PROJECT ARTIFACT
```

A canonical project artifact is any entity, user, role assignment, organizational object,
or seed-data record that is:
- committed to version control, OR
- seeded by a project-owned bootstrap/seed script that runs outside isolated test scope, OR
- referenced from project requirements, decisions, or specifications as permanent state.

---

## When Test Identity Creation Is Authorized

Test identity creation is authorized ONLY when ALL of the following hold:

1. **Isolation scope confirmed**: the creation occurs within an isolated verification context
   (Docker-isolated container, test-specific database, or transaction-scoped test fixture).
2. **Purpose is verification, not workaround**: the identity is created to provide representative
   role/scope coverage for a test contract proof point — NOT to mask a runtime configuration
   discrepancy (see `policies/local-runtime-profile.md` § Agent Prohibition).
3. **Cleanup mechanism exists**: a cleanup path is defined before creation begins
   (see Lifecycle Phases below).
4. **Identity does not duplicate an existing canonical identity**: if a project already
   defines a representative test identity for this role, reuse it.

Test identity creation is **NOT authorized** when:
- The goal is to work around a `RUNTIME_CONFIGURATION_DISCREPANCY`.
- The isolation scope cannot guarantee cleanup.
- No cleanup mechanism has been defined.
- A canonical test identity already covers this role/scope combination.

---

## Lifecycle Phases

Every authorized test identity has a defined lifecycle:

```
AUTHORIZED
  → CREATED (within isolated scope)
    → USED (verification runs)
      → CLEANUP (scope exit triggers cleanup)
        → VERIFIED_CLEAN (no persistent mutation remains)
```

### Happy Path

1. Scope opens (container start, transaction begin, or explicit test-scope marker).
2. Identity created within scope.
3. Verification runs using identity.
4. Scope closes: cleanup removes the identity and any dependent model mutations.
5. Repository state is unchanged from pre-test state.

### Verification Failure Path

When verification fails before cleanup:

1. Scope closes due to failure.
2. Cleanup is executed regardless — failure does not bypass cleanup.
3. If cleanup itself fails: the PERSISTENT_MUTATION status is recorded (see below).
4. The test is reported as having a cleanup obligation, not as isolated.

### Interrupted Execution Path

When the agent is interrupted mid-verification before cleanup completes:

1. Record the open scope in `process-state.yaml` under `test_identity_lifecycle`:
   ```yaml
   test_identity_lifecycle:
     open_scopes:
       - scope_id: "<scope-identifier>"
         created_at: "<ISO-date>"
         identity_ref: "<non-secret identifier>"
         cleanup_status: PENDING
   ```
2. On resume: check for open scopes before starting new verification.
3. Attempt cleanup of all PENDING scopes before proceeding.
4. If cleanup succeeds: set `cleanup_status: COMPLETED`.
5. If cleanup fails: set `cleanup_status: FAILED` and surface as PERSISTENT_MUTATION.

### Repeated Execution (Idempotency)

When the same isolated test is run multiple times:

- The second run MUST NOT create a duplicate identity if one already exists from a prior run.
- Check for existing identity before creating.
- If the prior identity was not cleaned up: either reuse it (if the scope still exists) or
  clean it up before creating a new one.
- A test that produces duplicate identities on repeated runs is NOT idempotent and
  MUST be corrected.

---

## Model Pollution Classification

### ISOLATED: No Persistent Mutation

The verification left no permanent trace in project sources, production database, or
committed artifacts. Repository state before and after the test is identical.

**Required for all authorized isolated tests.**

### PERSISTENT_MUTATION: Unintended Canonical Change

A test identity or dependent model mutation survived the test scope and:
- Is present in the live project database outside the isolated scope, OR
- Appears in version-controlled project sources, OR
- Is referenced from a commit, requirement, or specification.

**This is a defect in the test infrastructure, not in the application.**

Required response:
1. Classify as PERSISTENT_MUTATION in the campaign result.
2. Record the specific mutation (identity name, object type, scope affected).
3. Do NOT proceed with dependent verification claims until the mutation is resolved.
4. Do NOT treat the test as isolated when reporting results.
5. Initiate cleanup before the next verification run.

### ACCUMULATED_TEST_ARTIFACTS: Accumulation Detected

Multiple test identity records (or equivalent disposable objects) with recognizable
generated-identity patterns (random suffixes, sequential numbering, `test_`, `demo_`,
`auto_`, timestamp-based names) have accumulated in project sources.

**Detection rule:** If 3 or more identities matching a generated-identity pattern exist
in project-accessible sources without corresponding canonical declarations in
requirements/specifications, classify as ACCUMULATED_TEST_ARTIFACTS.

Required response:
1. Do not automatically delete — the developer must confirm.
2. Surface the accumulation with the list of candidate identities.
3. Classify each as: `CANONICAL` (intentional, keep), `STALE_TEST_ARTIFACT` (cleanup),
   or `UNKNOWN` (requires developer decision).
4. Only after developer decision: execute cleanup for STALE_TEST_ARTIFACT entries.

---

## Repository Cleanliness Requirement

After any isolated verification test completes (success or failure):

```
git status  (or equivalent)
→ no new untracked files matching generated-identity patterns
→ no modified project-source files containing test identity data
→ no database seed scripts containing temporary test identities
```

If this check fails, the test has a PERSISTENT_MUTATION that must be resolved before the
test result can be reported as isolated.

---

## Scope-Isolation Mechanisms (Generic)

The framework does not prescribe one implementation. Accepted mechanisms include:

| Mechanism | Isolation guarantee | Cleanup trigger |
|---|---|---|
| Docker-isolated container (ephemeral) | Full — container disposal removes all state | Container stop/remove |
| Transaction-scoped test (rollback after test) | Full — rollback removes all state | Transaction rollback |
| Explicit test-scope marker + registered cleanup hook | Partial — depends on hook execution | Scope-close event |
| None | None — all mutations are permanent | N/A |

"None" is not an accepted isolation mechanism for test identities.

If no isolation mechanism is available, the test infrastructure MUST declare this explicitly:

```yaml
isolation_mechanism: none
mutation_is_permanent: true
persistent_mutation_acknowledged: true
```

In this case the test is NOT classified as isolated and its results MUST be reported
with `fixture_isolation: NONE` rather than as a standard isolated test.

---

## Integration Points

- `policies/credential-discovery.md` § test_identity — credential category definition
- `policies/local-runtime-profile.md` § Agent Prohibition — no identity creation to mask config mismatch
- `policies/representative-fixture-contract.md` — when a test identity is also a representative scope fixture
- `schemas/process-state.schema.json` — `test_identity_lifecycle.open_scopes` tracking
- `tests/verify-demo-user-switcher.test.sh` — example of properly scoped test identity use
