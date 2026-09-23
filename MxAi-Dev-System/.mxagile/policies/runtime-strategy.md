# Runtime Strategy

**LOCAL FIRST. DOCKER BY VERIFICATION NEED.**

This is the canonical MxAgile runtime strategy contract.
All agents, skills, and projections follow this policy.

## The Contract

MxAgile distinguishes runtime *mechanism* from runtime *purpose*.
The mechanism must match the purpose. Using a heavier mechanism than the purpose requires
is waste; using a lighter mechanism than the purpose requires is invalid evidence.

## Escalation Model

Agents start at the lowest level that can provide authoritative evidence for the current
verification requirement. They escalate only when the current level cannot provide the
required evidence, fails for an environment-specific reason, or the acceptance criterion
explicitly targets a higher-level environment.

| Level | Mechanism | When to Use |
|---|---|---|
| **1** | Static / model validation | Syntax, references, lint, consistency (`mxcli check`, `mxcli lint`, `mxcli docker check`) |
| **2** | Warm local runtime | `mxcli run --local --watch` — iterative development feedback, UI iteration |
| **3** | Browser / Playwright against local runtime | Visual inspection, UI verification, acceptance tests — where local runtime is valid |
| **4** | Isolated Docker / container verification | Container-environment parity, deployable-build validation, CI without local runtime |
| **5** | Deployment / environment-specific verification | PAD, container deployment, environment-specific configuration |

Do NOT skip levels. Escalate only when justified.

## Verification Hosting Decision

When Playwright or browser verification is required, prefer the local runtime (Level 3)
unless one of the Docker-required conditions below applies.

**Playwright does NOT require Docker.** Playwright requires a running browser-accessible
application. Where the local runtime provides a valid running application, Playwright
operates against it directly.

## Docker IS For

Use Docker (Level 4+) only when the verification target specifically requires an isolated
or containerized environment:

- Container-environment parity testing
- Deployable-build validation (`mxcli docker build`)
- PAD / container deployment validation
- Container-specific configuration verification
- CI environments where local runtime is unavailable or inappropriate
- Failures suspected to be environment- or container-specific
- Final isolated verification when explicitly required by project or release policy
- `runtime.verification: docker` configured in `mxagile-project.yaml`

Do NOT use Docker merely as a generic synonym for "run the Mendix application."

## Docker is NOT Required For

| Change type | Required mechanism | NOT required |
|---|---|---|
| Page changed | Level 2–3 | Level 4 (Docker) |
| Microflow changed | Level 2–3 | Level 4 (Docker) |
| Nanoflow changed | Level 2–3 | Level 4 (Docker) |
| Styling changed | Level 2–3 | Level 4 (Docker) |
| Entity changed | Level 2–3 | Level 4 (Docker) |
| Association changed | Level 2–3 | Level 4 (Docker) |
| Playwright used | Level 3 against local runtime | Level 4 (Docker) |
| Browser verification required | Level 3 against local runtime | Level 4 (Docker) |
| UI-driven iteration | Level 2–3 | Level 4 (Docker) |
| Structural entity/association change | mxcli auto-reconcile; Level 2–3 | Level 4 (Docker rebuild) |

Structural model changes (entities, associations) may require a runtime restart.
The warm local runtime (`mxcli run --local --watch`) handles this automatically.
MxAgile does not maintain a separate "Docker rebuild required" flag for structural changes.
Trust the canonical mxcli runtime mechanism to determine the required apply level.

## Justified Escalation

When an agent cannot satisfy a verification requirement at the current level, it MUST:

1. State **what evidence is required**
2. State **why the current level cannot provide it**
3. State **what the higher level adds for this specific verification**
4. Escalate to the lowest level that resolves the gap

Silent fallback to Docker is not permitted.

## Rebuild-Batch Analysis

The warm local development architecture makes "Rebuild 1 / Rebuild 2 / Rebuild 3" style
batching obsolete for normal iterative development. The local runtime applies model changes
continuously; a "batch" exists only to amortize the cost of a slow-start mechanism.

Batching remains valid for:
- Formal isolated Docker builds (Level 4) — container builds are expensive; batch verified
  changes into a single container verification pass when sensible
- Explicit project release policy requiring a formal build before QA sign-off

Do NOT batch purely to observe model changes in a running application. Use the warm local
runtime for that.

## UI-Driven Integration

When `development.ui_driven = true`, the fast render/inspect loop is the primary feedback
mechanism. The loop is:

```
edit → render (local runtime) → inspect → screenshot → compare mockup → fix → repeat
```

NOT:

```
edit → full deployment build → container rebuild → restart → inspect
```

The local runtime (Level 2–3) must support this loop. Docker (Level 4) enters only when
the acceptance criterion specifically targets the container environment.

## Project Configuration

The runtime strategy can be configured in `mxagile-project.yaml`:

```yaml
runtime:
  verification: local_first   # default — Level 3 preferred, escalate to Docker as needed
  # verification: docker      # always use Docker for formal verification (legacy or explicit)
```

`local_first` (default): Prefer Level 2–3 for all normal implementation and verification.
Escalate to Level 4 only when Docker-required conditions are met.

`docker`: Always use Docker for formal verification. Use for projects where container parity
is always required or for projects migrating gradually from the legacy behavior.

Existing projects without a `runtime` section receive `local_first` behavior automatically.

## Decision Table

| Need | Preferred mechanism | May use Docker when |
|---|---|---|
| Model validation | `mxcli check`, `mxcli lint` | n/a |
| Consistency check | `mxcli docker check` (no build) | n/a |
| Fast implementation loop | `mxcli run --local --watch` | n/a |
| UI iteration | `mxcli run --local --watch` | n/a |
| Browser inspection | local runtime | local runtime fails |
| Mockup comparison | local runtime + browser | local runtime fails |
| Role verification | local runtime where valid | container-specific role config |
| Playwright UI verification | local runtime (Level 3) | container parity required |
| Structural model change | local runtime / auto-restart | n/a |
| Container parity | Docker | always |
| Deployable container build | Docker | always |
| Container-specific failure | Docker | always |
| Release-policy required build | Docker | always |
