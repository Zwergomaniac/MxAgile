# Operating Mode and MCP Routing

## Authority and Evidence

The operating mode is determined by `.mxagile/policies/operating-mode.md` and
the existing `scripts/check-studio-pro-status.ps1` detector, distributed to
`.mxagile/tools/check-studio-pro-status.ps1` on install/update. Do not ask the user
to choose a mode when the technical evidence is conclusive.

| Evidence | Meaning |
|---|---|
| Current `.mpr` resolved to a normalized absolute path; Studio Pro PID command line matches that complete path argument | `LIVE-SP-CURRENT` |
| No Studio Pro process is positively detected | `CLOSED-AUTONOM` |
| Studio Pro is running but no process matches the current `.mpr` | `LIVE-SP-OTHER`; current project may use the autonomous route |
| Detector fails, times out, or cannot establish process/project identity | `AMBIGUOUS-SP-STATE`; never infer `CLOSED-AUTONOM` |

The detector uses the current project path, normalized with `GetFullPath`, and
requires a complete command-line argument match. A similar project name or a
substring match is not project identity. This is path identity, not a persistent
Mendix project GUID; aliases such as junctions or different mapped drives may
remain indistinguishable without additional evidence.

MCP evidence has separate levels:

| Evidence | What it establishes |
|---|---|
| MCP configuration | Configured only |
| Tool appears in active tool namespace | Offered by the harness, not necessarily healthy |
| Successful non-mutating MCP call | The endpoint answered that call |
| Response/context confirms the current `.mpr` | Same-project route evidence |

The capability resolver does not probe Studio Pro or Concord MCP health. Agents
must not report health or project affinity from configuration or tool presence
alone. Probe with an existing read-only MCP operation only when a model
operation needs that route. If no operation can establish health and project
context, that route remains unknown/unusable for the operation.
If Studio-Pro-MCP reports a different project than the process detector, treat
the conflicting evidence as `AMBIGUOUS-SP-STATE`, not `LIVE-SP-CURRENT`.

## Routing

| Mode | Route |
|---|---|
| `LIVE-SP-CURRENT` | Studio-Pro-MCP first. Concord MCP is the existing fallback only after a successful read-only call and same-project context confirmation. Do not use mxcli for model mutations, including `mxcli exec`; do not fall back to mxcli after MCP failure. |
| `CLOSED-AUTONOM` | Use the existing autonomous mxcli route when available and authorized. |
| `LIVE-SP-OTHER` | Use the autonomous route for the current project. Do not touch the foreign Studio Pro process. |
| `AMBIGUOUS-SP-STATE` | Continue safe non-model work. Recheck at the mutation boundary; if still ambiguous, ask one precise question and do not mutate through mxcli. |

Read-only mxcli operations remain subject to their own operation contract. An
mxcli installation does not override LIVE-SP routing or authorize a prohibited
model mutation.

## Freshness and Escalation

Re-detect at Startup Re-Sync and use the existing recheck immediately before a
model mutation and after a pause/resume. Do not cache mode indefinitely. Do not
ask again in the same unchanged session after a conclusive result.

Ask only when the detector remains `AMBIGUOUS-SP-STATE` at the next actual model
mutation boundary, after recheck. State what could not be established (for
example, whether a running process has the current `.mpr` open). A known mode
with an unavailable MCP route is not a request to choose a mode: block that
specific mutation and report the unavailable evidence.

## Scope and Limitations

- Studio Pro process/project identity is locally detected from the process
  command line; endpoint-to-process identity is not independently probed by the
  capability resolver.
- MCP health and project context are only as strong as an observed successful
  read-only call and the identity information exposed by that tool.
- The regression suite checks policy and wiring. It does not simulate a real
  Studio Pro process or live MCP server; those require a harness-level runtime
  test.

Canonical contracts: `.mxagile/policies/operating-mode.md`,
`.mxagile/policies/execution-intent.md`, and `.mxagile/capabilities.yaml`.