# Security Projection

## Purpose

The Security Projection is a **generated, read-only evidence artifact** that describes the security
configuration of a Mendix model in a normalized, machine-readable form (`security-matrix.yaml`).

- Authority: the **Mendix model**. The projection never replaces it and is never edited by hand.
- Projection: `mxcli` model inspection -> normalization -> `security-matrix.yaml`.
- Consumers: MxAgile agents, verification, drift detection, impact analysis, later the Board (read-only).
- Evidence class: **MODEL SECURITY**. It proves what the model configures. It does not prove what a
  running application does for a user (RUNTIME OBSERVED BEHAVIOR); neither proves the other.

Generator: `scripts/security_projection.py` (distributed as `.mxagile/tools/security_projection.py`),
entry point `generate-security-matrix.ps1`. Schema: `.mxagile/schemas/security-matrix.schema.json`.
Default output in a project: `.mxagile/state/security/security-matrix.yaml` (Project Runtime state,
preserved on Core update).

## Artifact Contract (schema_version 1)

| Section | Content |
|---|---|
| `generated` | `generated_at`, `generator`, `source: mendix-model`, `mxcli_version`, `project_revision` (git HEAD of the project, else `null`), `complete`, per-section `sections` status, `warnings`, semantic `fingerprint` |
| `security` | `level`, `check_security`, `strict_mode`, `demo_users_enabled`, `guest_access`, `guest_user_role`, `admin_user` |
| `roles` | `user_roles` (each with its `module_roles`, `manage_all_roles`) and the list of all `module_roles`; the two concepts are never merged |
| `pages` / `microflows` / `nanoflows` | `<Module.Name>: {grants: [module roles]}`; every resource of the complete listing appears, an empty list means no grant was reported |
| `entities` | `access_rules[]`: `roles`, `create`, `delete`, `read{granted, members}`, `write{granted, members}`, `default_member_access`, `xpath` (verbatim or `null`) |
| `effective_access` | per **application User Role**: union of its Module Roles' page/microflow/nanoflow grants; entities keep the contributing rules |
| `findings` | few deterministic snapshot-only findings (`SEC-*`) |
| `change_context` | `last_generated`, `source_revision`, `model_dirty`, `last_model_commit`, `previous_fingerprint`, `reason` |
| `drift` | structural drift against the previous snapshot (`null` on first generation) |

Members: `members` is a sorted list, or `"*"` only when every listed member and the default for unlisted
members is granted. Inherited and association members keep their qualified name; own members are short.
Pages, microflows and nanoflows are grant lists by Module Role (Mendix "allowed roles").

### Unknown over invented

A section that cannot be extracted is `null`, its `sections.<name>` is `failed`, a warning is recorded and
`complete: false`. `effective_access` is only computed when all of roles, pages, microflows and
nanoflows are complete. Nothing is synthesized. Not extracted in V1: workflow access (mxcli states it is
controlled through triggering microflows/UserTask targeting), navigation reachability, page-to-flow
dependency analysis.

### Determinism

Everything is sorted; null/unknown is always `null`; XPath is preserved byte-for-byte from the mxcli JSON
(never from human-readable output, which does not escape quotes). `generated.fingerprint` hashes only the
semantic body (security..findings). `generated`, `change_context` and `drift` never influence it. If a
regeneration yields the same fingerprint and completeness, **the file is not rewritten** (no timestamp
noise, previous drift is preserved); `--force` rewrites.

## Raw vs Effective Access

Raw (module-role) sections are the audit layer. `effective_access` is derived by exactly one rule:
User Role -> its Module Roles -> union of grants (additive in Mendix). Entity access is **not flattened**:
each entity lists the contributing rules (with `via_module_roles`, XPath and member lists) plus a
summary per right: `none | unconditional | conditional` (conditional = granted only by rules with an
XPath constraint). Do not collapse rules into a single boolean; do not union member lists across rules
with different XPath. XPath is never evaluated.

## Change Context and Reason

Establishable reliably: generation time, mxcli version, project git revision, whether the model
directory is dirty, the last commit touching the model directory (technical provenance only; it is
not proof that commit changed security), previous fingerprint, and the structural drift.

Not establishable: why security changed, which requirement/task/decision caused it, who changed it.
`reason` is `{type: unknown, reference: null, text: null}` unless a human/agent passes
`--reason-type requirement|task|decision|finding --reason-ref <ID> [--reason-text]`. A reason without a
reference is rejected by the generator and by the schema. Never derive a reason from commit messages,
branch names or plausibility.

## Drift

Compare two snapshots, never human-readable diffs: `python security_projection.py diff <before> <after>`
(or the embedded `drift` block). Timestamps and provenance are ignored. Detected types: user role,
module role, role-mapping, page view, microflow execute, nanoflow execute added/removed; entity
create, delete, read-member, write-member added/removed; XPath changed / removed; security level;
guest access/role; strict mode / demo users / check-security changes. Snapshots with incomplete sections
report `comparable: false` and never turn a failed section into drift.

Severity (`info < security_relevant < high_impact < critical`) is a fact about the change, not a risk
score: removal = `info`; additions = `security_relevant`; entity DELETE added, write on `*` members,
XPath constraint removed (exact structural: constrained -> unconstrained), guest role change =
`high_impact`; PRODUCTION -> PROTOTYPE/OFF = `critical`. A changed XPath text is `entity_xpath_changed`
(direction not judged). Semantic XPath broadening is NOT assessed.

### Impact integration (no second engine)

Drift is a set of FACTS, in the sense of `policies/impact-resolution.md`: it decides nothing. A drift of
`high_impact` or `critical`, or any role-access change affecting visible elements
(`policies/observe-before-mutate.md`), is a role/permission change in the impact-resolution sense:
resolve affected Requirements through the existing resolver and classification vocabulary. This
policy adds no classification, state machine or resolver. Automatic consumption by the resolver or
verification runner is not implemented; agents read the drift block.

## Findings

Only deterministic, conservative, snapshot-only findings exist: `SEC-EXTRACTION-INCOMPLETE`,
`SEC-LEVEL-NOT-PRODUCTION`, `SEC-DEMO-USERS-IN-PRODUCTION`, `SEC-GUEST-ACCESS-ENABLED`,
`SEC-GUEST-ENTITY-WRITE`. They are visibility aids (module-owned entities such as OIDC login
entities legitimately trigger the guest finding), not vulnerabilities. "Role reaches a page whose
action it cannot execute" is not implemented: it needs page-to-flow reference analysis mxcli output
does not provide in the security queries.

## Role Testing

`effective_access.<UserRole>` may drive targeted expectations for role verification (page reachable,
microflow executable, entity member writable). It is MODEL evidence (same class as `mxcli_inspect` proof
points, `model_parity`). A browser/runtime `role_test` supplies RUNTIME evidence for `role_parity`.
A matching matrix does not satisfy a runtime role test and vice versa. Local fixtures remain local.

## Is it mandatory? Decision: OPTION C (optional generated evidence)

Evidence (spike, mxcli v0.20.0, 2026-11-07): extraction is reproducible and schema-valid on one real
116-entity project (all sections complete, three consecutive runs identical) and on a mxcli-created
fixture with XPath and member-level rules. Not yet proven: a reference-project class production project,
more than one real project, XPath on a real production model, and stability across mxcli versions
(mxcli describes itself as alpha). Cost is ~50-75 s for 116 entities/16 nanoflows because mxcli
reloads the project per query (one query per entity with rules and per nanoflow, 4 in parallel), so it is
unsuitable as an unconditional per-task scan.

Recommendation: keep it optional (C). Promote to **B** (required when the installed toolchain supports
deterministic extraction) after one successful reality run on reference project. Do not make it mandatory
(A) before then. Generate on demand: security-relevant model change, before security verification,
CI on Mendix model changes.

## Board consumer contract (read-only, not implemented)

A future Board reads `security-matrix.yaml` only; it must not call mxcli or re-parse mxcli output:

- Roles: `roles.user_roles`, `roles.module_roles`, `security`
- Pages / Flows: `pages`, `microflows`, `nanoflows`, per role `effective_access.<role>.*`
- Data: `entities.<E>.access_rules`, `effective_access.<role>.entities`
- Drift: `drift.changes[]` (`type`, `severity`, `kind`, `subject`, `detail`, `before/after` for settings)
- Findings: `findings[]`
- Trust: `generated.complete`, `generated.sections`, `generated.warnings`, `change_context.reason.type`

It must show `complete: false`, `null` sections and `reason.type: unknown` as such and must treat the
file as read-only and possibly stale (compare `source_revision`/`generated_at`).
