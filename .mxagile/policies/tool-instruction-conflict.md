# Tool and Instruction Conflict Resolution

Canonical contract for resolving contradictory technical instructions before using a tool,
CLI, MCP endpoint, or tool-provided skill.

## Authority and Source Identity

First identify who owns the statement. A project-authored `CLAUDE.md`, `AGENTS.md`, or
`AGENT.md` may be a project contract. An MxAgile-managed/generated block or platform skill
is a projection of its canonical source, not a second authority. External/tool-provided
skills are advisory guidance, not project configuration.

Resolve the requested behavior in this order:

1. Explicit current user scope, authorization, and safety constraints.
2. Applicable MxAgile safety, lifecycle, scope, and evidence invariants. Project instructions
   cannot waive these invariants.
3. Explicit project-owned configuration and contracts for the current project.
4. Compatible Company Layer requirements and defaults where the project has not declared a
   value. Existing project-over-Company-Layer precedence applies to project configuration.
5. MxAgile Core defaults and generic policies where no higher-authority project or Company
   declaration applies.
6. Harness-generated instructions, which must agree with their canonical source; resolve
   drift in the source/projection, not by choosing whichever copy was loaded last.
7. External or tool-provided skills, which may suggest a method but cannot override any
   higher-authority contract.

This hierarchy selects the intended behavior; it does not prove that a tool can implement
it. The selected tool's actual version and current command/tool capabilities are a separate
execution gate.

## Conflict Resolution Before Execution

When two sources disagree about a binary, command, flag, runtime profile, identity, role
switch, navigation path, or evidence behavior:

1. Identify each source, owner, scope, and whether it is current, generated, or historical.
2. Resolve project-specific values using the applicable project/Company/Core precedence.
   Do not treat generated harness projections or external skills as project declarations.
3. Resolve the intended executable using `policies/local-runtime-profile.md`. Record its
   absolute path and exact version; do not invoke an unqualified PATH command.
4. Before using version-sensitive syntax, inspect command-specific help or a capability
   contract from that exact executable. A skill's flag example is not evidence that the
   installed version supports it.
5. If the selected executable does not support the required command or flag, stop that
   operation and report `TOOL_CAPABILITY_GAP`. Do not substitute another PATH binary,
   silently drop the option, or change the requested semantics.
6. If two applicable project/Company contracts remain contradictory, do not choose
   arbitrarily. Report `TOOL_CONTRACT_CONFLICT`, cite the conflicting sources and the
   safe decision needed, and continue unrelated safe work.

These classifications are diagnostic outcomes, not new lifecycle states. Do not persist
them as process state unless an existing schema explicitly provides a suitable field.

## Tool-Specific Boundaries

- **mxcli:** The project-pinned or project-local executable is selected before PATH. Every
  invocation uses its resolved absolute path. See `policies/local-runtime-profile.md`.
- **Concord / MCP:** Skill text or configured endpoints do not prove that a tool is loaded,
  healthy, or bound to the current project. Follow `policies/operating-mode.md` and the
  active-session capability probe; never infer capability from a historical log.
- **Other external/tool skills:** Treat examples as unverified until they match the current
  project contract and the selected tool's actual capabilities.

Historical reports and logs may be cited as evidence or investigation clues. They are not
operative configuration when current project declarations, helpers, or executable tests
exist.