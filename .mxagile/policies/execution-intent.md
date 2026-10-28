# Policy: MCP Route Evidence

This policy resolves the old execution-intent prompt. Operating mode is a
technical fact determined by `policies/operating-mode.md`, not a user-selected
preference. A known mode and a healthy tool route must be used without asking
the user to choose between LIVE-SP and headless operation.

## Evidence Levels

| Evidence | What it proves | What it does not prove |
|---|---|---|
| MCP server configured in a file | Configured | Running, reachable, healthy, or bound to this project |
| `mcp__<server>__*` tool appears in the active tool set | The harness offers the tool | Successful operation or correct project context |
| Successful non-mutating MCP call | The endpoint answered that call | Same-project identity unless the result/context confirms it |
| Same-project identity confirmed | Route is bound to the current project | Authorization for an operation not allowed by the operating-mode contract |

Use the existing agent-visible MCP tools to make a read-only probe only when a
Mendix operation needs that route. Do not invent a health result, infer health
from configuration/tool presence, or load a long policy for each tool choice.
For project identity, compare the normalized absolute current `.mpr` path with
identity returned by the endpoint when available. Similar project names are not
identity evidence. If the endpoint cannot provide enough evidence, its route is
unknown for this operation.

## Routing

- `LIVE-SP-CURRENT`: Studio-Pro-MCP first. Concord MCP is the existing fallback
  only after a successful read-only call and same-project context confirmation.
  Never use mxcli for model mutations, including `mxcli exec`, and never fall
  back to mxcli after MCP failure.
- `CLOSED-AUTONOM` and `LIVE-SP-OTHER`: use the existing autonomous mxcli route
  for the current project when available and authorized. Never interact with a
  foreign Studio Pro process.
- `AMBIGUOUS-SP-STATE`: continue safe non-model work, then recheck immediately
  before a model mutation. If still ambiguous, ask one precise question at that
  boundary and do not mutate through mxcli.

Concord availability alone does not make the project LIVE-SP. A resolved
operating mode does not need a user confirmation, and an unchanged mode is not
re-asked during the same session. Re-detect at Startup Re-Sync and use the
existing mutation-boundary recheck; do not blindly cache mode or MCP health.

Explicit user preferences can select among routes already permitted by the
operating-mode contract. They cannot make an unsafe mxcli mutation permissible
in `LIVE-SP-CURRENT`.