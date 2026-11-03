# Runtime Configuration Reconciliation

On-demand contract for project-local runtime constants and confirmed differences between Studio
Pro local behavior and C1-resolved headless runtime behavior. This policy does not select a
runtime, define CLI syntax, or override `local-runtime-profile.md` / the selected binary's help.

## Project Constant Overrides

Projects declare non-secret local constants in `mxagile-project.yaml` under
`local_runtime.constant_overrides`. The schema owns the fields. C1 includes an override in the
resolved recipe only when the selected binary's current help advertises the required control;
consumers execute that recipe unchanged. This policy does not define the option spelling.

- Non-secret values may be stored inline in the project configuration.
- Sensitive values use `env_key` references; the value stays in `.env.mendix` and never enters
  tracked artifacts, reports, or handoffs.
- Constant overrides apply only to an authorized local development/test recipe, not Docker,
  CI, or production.
- Do not edit `config.json` as an authoritative mechanism; mxcli may regenerate it.
- Do NOT globally force a specific constant value as a MxAgile Core default; each project owns
  its intentional local value.
- Report constant names and non-secret values before startup; confirm that the resolved runtime
  accepted the configured override before declaring the application reachable.
- MxAgile Core must not hard-code module-specific constant names or globally force a value.

Example project declaration:

```yaml
local_runtime:
  constant_overrides:
    - name: ModuleName.DisableMxAdmin
      value: "False"
      purpose: "Enables the declared local bootstrap administrator"
    - name: MyModule.ApiSecret
      env_key: LOCAL_API_SECRET
      purpose: "Local API secret; value remains in .env.mendix"
```

## Runtime Configuration Discrepancy

A module constant default may intentionally reflect production behavior while a project has a
different local development intent. Studio Pro may apply a project-level local configuration
that is not visible to headless tooling. A headless authentication or behavior failure may be
classified `RUNTIME_CONFIGURATION_DISCREPANCY` only when all conditions hold:

1. The headless local runtime failure is observed.
2. Studio Pro local execution of the same project and database succeeds for the same operation.
3. The project's `local_runtime.constant_overrides` is absent or does not cover the relevant
   constant.
4. No authoritative secret or other project configuration explains the failure.

This is not `CREDENTIAL_VALIDATION_FAILED`, `SECRET_INPUT_REQUIRED`, or `RUNTIME_START_FAILED`.
Do not diagnose it from a login failure alone.

### Studio Pro Parity Evidence

Before classification, compare the same project, database, and operation in Studio Pro and through
the C1-resolved local recipe. Check the project declaration and documented Studio Pro run
configuration for the relevant constant. If Studio Pro also fails, this discrepancy is not
established. Do not infer constant names or values from unrelated model artifacts.

### Override Ownership

| Category | Authority | Lifetime |
|---|---|---|
| Module default | Constant declared in the Mendix model | Model lifetime |
| Project local override | `mxagile-project.yaml local_runtime.constant_overrides` | Tracked; survives sessions |
| Production/environment override | CI/CD or deployment configuration | Deployment-scoped |
| Diagnostic override | Explicit current-session request consumed by C1 | Session-only; not a durable fix |

A diagnostic override that proves project intent must be converted into a project declaration
before the discrepancy is considered resolved.

## Resolution and Safety

When the discrepancy is confirmed:

1. Identify the constant whose model default differs from the intended local behavior.
2. Confirm that local intent with the developer; do not make a project-wide decision autonomously.
3. Record the intended value and purpose in `local_runtime.constant_overrides` using the schema.
4. Re-resolve the complete C1 recipe; do not append or reconstruct a command argument.
5. Restart only through the updated recipe and verify that the previously failing operation succeeds.
6. Resume verification only after the configured identity and readiness checks pass.

Agents MUST NOT create or modify test identities, reset passwords, change roles, bypass SSO, or
continue through an undocumented identity substitution to mask this discrepancy. Evidence from
an unresolved configuration discrepancy is not valid runtime evidence.

For an existing project, identify its documented local intent, declare the applicable constants,
commit the project-owned configuration, and re-resolve C1. Do not patch generated mxcli files,
modify the model, or recreate the database as a workaround.

## Validation Boundary

Framework tests can validate schema, C1 propagation, policy coherence, and the prohibition on
identity workarounds. They do not prove downstream behavior for a real Mendix application. Full
framework checks are `FRAMEWORK_VALIDATION`; a real project must separately pass
`DOWNSTREAM_RUNTIME_ACCEPTANCE`. That acceptance remains required before declaring the
discrepancy fully resolved and marking downstream status `VERIFIED`. Confirm that C1 uses the
declared value, no generated runtime file was patched, and the intended bootstrap identity can
authenticate.

## mxcli Upstream Finding

Some Studio Pro local runs may apply effective constants that headless runs do not reproduce.
The downstream tool should document how it exposes or reads that project-local configuration.
Until such a supported mechanism exists, MxAgile requires explicit project intent in
`local_runtime.constant_overrides` and selected-binary help evidence from C1.
