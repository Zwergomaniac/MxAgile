# Credential Discovery and Bootstrap

Authoritative contract for credential/configuration discovery and bootstrap during the
MxAgile development lifecycle.

## The Contract

**DISCOVER. RESOLVE. REQUEST ONLY IRREDUCIBLY HUMAN INPUT. VALIDATE. AUTO-RESUME.**

Before declaring any credential, authentication, database, API, or test-login blocker, an
agent MUST perform full automatic discovery of project-local configuration. Declaring a
blocker without performing this discovery is an agent fault, not a valid lifecycle state.

## Discovery Order

Before declaring any credential blocker, inspect these sources in order:

1. **`.env.mendix`** — project-local secret file (gitignored by convention)
   - Check whether the file exists
   - Inspect required key names (not values in output)
   - Classify each required key: PRESENT / MISSING / EMPTY
2. **`.env*` variants** — `.env`, `.env.local`, `.env.development`, etc.
3. **mxcli configuration** — mxcli runtime and project settings where accessible
4. **Mendix runtime configuration** — project-level runtime settings
5. **Database configuration** — project connection settings, configured DSN
6. **Company Layer configuration** — `.mxagile/layers/<id>/` if installed
7. **Project-local bootstrap scripts** — scripts that configure or seed the environment
8. **Documented bootstrap mechanisms** — any project/company documented setup procedure

Do NOT ask the developer where the configuration is before performing this discovery.

## Configuration Precedence

When multiple sources define the same credential or setting, resolve in this order:

1. **Explicit CLI argument** — highest priority (session-scoped)
2. **`.env.mendix`** — project-local secret file
3. **`.env*`** — other local environment files
4. **mxcli project configuration**
5. **Mendix project settings**
6. **Company Layer defaults**
7. **MxAgile Core defaults** — lowest priority

A failed default (position 7) does NOT override or invalidate an existing project-specific
configuration (positions 1-6). Discovering that a default credential fails is not evidence
that the project configuration is missing or invalid.

## What to Report (Secret-Safe)

When reporting credential readiness, report ONLY non-secret metadata:

| State | Meaning |
|---|---|
| `PRESENT` | Key exists and is populated |
| `MISSING` | Key does not exist in any discovered source |
| `EMPTY` | Key exists but has no value |
| `INVALID` | Key exists but value fails validation |
| `VALID` | Key exists, populated, and validated successfully |
| `USED` | Value was used for a successful operation |
| `NOT_USED` | Applicable source exists but was not consulted |

**NEVER include actual credential values in reports, process-state, screenshots, logs, or any
tracked artifact.** See `policies/safety-rules.md`.

## Capability Analysis

For each blocked capability, determine:

| Question | What to Determine |
|---|---|
| Which capability is blocked? | e.g. local PostgreSQL access, Mendix runtime login, Playwright test login |
| Which credential category? | e.g. database credentials, test-user credentials |
| Which canonical source provides it? | e.g. `.env.mendix`, mxcli config |
| Which specific keys are required? | Derive from project/company config — do not invent names |
| Is each required key PRESENT/MISSING/EMPTY/INVALID? | After full discovery |

Determine required key names from the canonical project or company configuration — not from
universal assumptions. Different projects and company layers may use different variable names.

## Bootstrap When File Missing

If the canonical local secret mechanism (e.g. `.env.mendix`) is defined by the project
contract but does not yet exist:

1. **Determine safe template mechanism** — does the project provide a `.env.mendix.template`
   or equivalent? Check company layer and project scripts.
2. **Create the bootstrap file autonomously** if a safe mechanism exists:
   - Include all required key names
   - Include non-secret defaults and placeholders where appropriate
   - Include safe non-secret configuration (database host, port, service names)
   - **Never include fabricated secret values**
3. **Protect from accidental version control** — ensure `.gitignore` covers the secret file

## Request Only Missing Values

When genuinely human-supplied secret input is the only unresolved prerequisite, ask the user.
This is correct autonomous behavior — asking for irreducibly human input is NOT a failure of
autonomy.

The request MUST:
- Name the specific canonical file/mechanism (e.g. `.env.mendix`)
- List ONLY the missing/empty keys
- State the non-secret purpose of each key
- NOT request keys that are already PRESENT
- NOT ask for existing values to be re-entered
- NOT ask the developer to paste secret values into conversation
- NOT invent or suggest credential values

Example request pattern:

```
Runtime verification requires local credentials that are not yet configured.

Please populate these missing entries in `.env.mendix`:

    MENDIX_DB_PASSWORD=
    MENDIX_APP_TEST_PASSWORD=

MENDIX_DB_PASSWORD   — local PostgreSQL password for the Mendix runtime database user
MENDIX_APP_TEST_PASSWORD — Playwright test login for role verification

Please enter the values directly in `.env.mendix`.
Do not send the secret values in this chat.

I will continue automatically after you have populated the file.
```

## Failure Classification

Use precise classifications rather than generic BLOCKED:

| Classification | Meaning | Agent Action |
|---|---|---|
| `CONFIG_NOT_DISCOVERED` | Required configuration source not found | Continue discovery; create bootstrap file if contract supports it |
| `CONFIG_INCOMPLETE` | Source found, required keys missing or empty | Bootstrap missing keys; request only those from user |
| `SECRET_INPUT_REQUIRED` | All automation done; user must supply secret values | Structured request to developer |
| `CREDENTIAL_VALIDATION_FAILED` | Credentials found but validation failed | Report failure, do not mutate; diagnose configuration source |
| `DATABASE_UNREACHABLE` | Database not accessible after correct config | Diagnose network/service state, not credentials first |
| `RUNTIME_START_FAILED` | App failed to start after correct credential use | Diagnose application/model error |
| `TEST_IDENTITY_UNAVAILABLE` | Test user not configured or credentials missing | Credential bootstrap for test identities |
| `MOCK_DATA_UNAVAILABLE` | Representative data not seeded | Check seeding mechanism; bootstrap if supported |
| `BROWSER_VERIFICATION_UNAVAILABLE` | Playwright/browser cannot connect | Diagnose runtime start; not a credential issue |

## Credential Mutation Prohibition

A failed assumed/default credential does NOT authorize ANY of:

- `ALTER USER ... PASSWORD`
- Password reset or rotation
- Account recreation
- Database user recreation
- Database reinitialization
- Credential overwrite
- Any destructive infrastructure change

The required response to a failed credential attempt is:

```
discover configuration → use actual configured values → validate → diagnose
```

NOT:

```
default failed → reset to default
```

Proposing or executing credential mutation as a response to authentication failure is a
framework violation. This applies even when the mutation would be technically achievable.

## Auto-Resume Contract

After the developer populates the required secret source, the agent MUST automatically continue
the previously blocked lifecycle activity.

Resume behavior:

1. **Re-read configuration** — inspect the canonical secret source again
2. **Validate** — attempt the previously failing operation
3. **Continue** — resume exactly where the lifecycle was blocked

The developer MUST NOT need to:
- Give a new command explaining what comes next
- Re-explain the blocked state
- Re-initiate the lifecycle

The agent retains and reconstructs:
- Blocked operation (from process-state `prerequisite_state` or lifecycle context)
- Missing prerequisite category
- Resume point in the lifecycle

The agent MUST NOT retain actual secret values between sessions.

## Persistent Non-Secret Readiness State

Non-secret prerequisite readiness may be recorded in `process-state.yaml` under
`prerequisite_state` for resume continuity.

Valid state values (non-secret classification only, never credential values):

```yaml
prerequisite_state:
  runtime_config: discovered    # .env.mendix found, keys inspected
  database: reachable           # connection validated (after correct credentials used)
  mock_data: ready              # representative data verified
  test_identities: configured   # test credentials verified as present
```

**Never record in process-state:**
- Passwords, tokens, DSNs containing credentials
- Usernames (if sensitive)
- Any reconstructible secret

The readiness state survives session re-sync by design — it records what has been verified,
not how it was verified.

## Company / Project Extension Model

MxAgile Core does not hard-code environment variable names, database users, or credential
structures. Projects and Company Layers extend the credential contract.

A Company Layer may define (in `.mxagile/layers/<id>/credentials.yml` or equivalent):

```yaml
required_credentials:
  - category: database_access
    description: Local PostgreSQL credentials for Mendix runtime database
    canonical_source: .env.mendix
    required_keys:
      - key: MENDIX_DB_USER
        purpose: PostgreSQL username for runtime database
        secret: false       # username is safe to show as key name only
      - key: MENDIX_DB_PASSWORD
        purpose: PostgreSQL password for runtime database
        secret: true        # value must never be shown
    validation: mxcli run --local --db-validate
    phases: [implementing, verifying]

  - category: test_identity
    description: Playwright test login credentials
    canonical_source: .env.mendix
    required_keys:
      - key: MENDIX_APP_TEST_USERNAME
        purpose: Demo user login for Playwright verification
        secret: false
      - key: MENDIX_APP_TEST_PASSWORD
        purpose: Demo user password for Playwright verification
        secret: true
    phases: [verifying]
```

MxAgile Core reads such declarations (where present) to:
- Know which keys are required for which phases
- Know which source to inspect
- Know which keys are safe to show as names vs. which to mask even as names
- Run the appropriate validation mechanism

In the absence of a Company Layer or project-specific declaration, MxAgile Core performs
discovery heuristically based on standard Mendix local development conventions.

## Session Request: One Request Per Configuration State

Do not repeatedly ask for the same missing values within the same configuration state.

If a developer answers that credentials are set, the agent checks once and continues.

If validation fails after the developer confirms they set the values, the agent:
1. Reports the validation result (non-secret metadata only)
2. Provides diagnostic information
3. Asks for developer assistance in diagnosis if needed

The agent does NOT loop indefinitely requesting the same values.
