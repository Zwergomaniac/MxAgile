# MxMocketeer v3

MxMocketeer is a discovery, requirements, UI/UX, and HTML mockup agent for Mendix and digital transformation projects. Product Owners and key users develop clickable prototypes through conversation. Requirements, decisions, roles, rules, assumptions, and traceability travel invisibly as an embedded Design Contract inside the same HTML file.

## Skills

```
products/MxMocketeer/
    system-prompt.md          — always-on identity, safety, and stop conditions
    suggested-prompts.md      — Product Owner starter prompts
    agent-builder-setup.md    — packaging and host setup guide
    README.md

    skills/mocketeer-*/SKILL.md — seven substantive, canonical product skills
    skills/mocketeer-mockup-generation/assets/golden-mockup.html — optional example
    tests/
        preservation-acceptance.md
        test-mocketeer-validation.ps1
        test_mocketeer_skills.py
```

## Setup

1. Paste `system-prompt.md` into the Agent **Instructions** field.
2. Add the seven `skills/mocketeer-*/SKILL.md` files to Microsoft Copilot as seven
    independent Skills. Each file includes substantive domain guidance and the required
    two-field YAML frontmatter. Make the generation skill's Golden HTML asset separately
    retrievable as described in `agent-builder-setup.md`.
3. For consumer repositories, run the normal MxAgile setup/update. `install-core.ps1`
    copies these seven product skills into `.mxagile/skills/`, then
    `generate-mxagile-platform-skills.ps1` projects them into Claude, Copilot, and
    portable/Concord discovery directories.
4. Claude/Concord users receive the same source through the normal MxAgile installer;
    there is no product-specific bundler or alternate package.
5. Add the entries from `suggested-prompts.md`, name the agent **MxMocketeer v3**, and
    publish with limited pilot scope.
6. Run the preservation acceptance procedure before broad rollout.

See `agent-builder-setup.md` for the manual Copilot steps and the normal MxAgile
installer/generator paths.

## Product Owner Usage

**New design:** Start a conversation → answer focused questions → receive HTML mockup.

**Refinement:** Upload existing HTML → request change → agent reads current mockup and Design Contract, preserves unrelated content, produces next complete revision.

**Handoff:** Upload finalized mockup → request readiness review → open business questions identified → hand to development / MxAgile.

## Design Contract

Every MxMocketeer output is a self-contained HTML file containing:
- Visible clickable prototype (HTML + CSS + JavaScript)
- Embedded machine-readable Design Contract (`<script type="application/json" id="mocketeer-spec">`)

The contract preserves requirements, decisions, roles (with positive and explicit negative capabilities), business rules, flows, states, assumptions, open questions, and traceability across iterative refinements.

The optional `assessment` block records maturity dimensions, identified gaps, and readiness state (`PROTOTYPE_READY`, `REFINEMENT_REQUIRED`, `HANDOFF_READY`, `BLOCKED`). A visually complete prototype is not automatically development-ready.

Canonical schema content: `skills/mocketeer-design-contract/SKILL.md`

## Golden Reference Mockup

The complete Golden Mockup HTML is
`skills/mocketeer-mockup-generation/assets/golden-mockup.html`; it is sample material,
not business authority. Load it only for a needed generation example, visual calibration
or Golden check, never automatically during bootstrap or Discovery.

The mockup demonstrates: multiple roles, positive/negative permissions, search/filter, create dialog, validation, role-switching, empty state, spec-footer, traceability attributes, stable IDs, and a complete Design Contract.

## Session Loading

At first Mocketeer work in a new session, read all seven SKILL.md once. They retain
the shared product model, domain contracts and quality gates. Reuse this knowledge
for subsequent tasks; apply needed skills and load additional resources only on demand.
Keep bootstrap status only in transient context, tied to the available skill revision.
New sessions or relevant updates require bootstrap again; after Context Compaction,
verify and reconstruct missing baseline knowledge before work. See the Discovery
skill's Session Initialization contract and `agent-builder-setup.md` for host access.

## Validation

Run the product checks from the repository root:

```powershell
pwsh products/MxMocketeer/tests/test-mocketeer-validation.ps1
```

The product suite validates Design Contract compatibility and preservation.
`tests/test_mocketeer_skills.py` validates seven distinct skill triggers, exact
frontmatter, retained inline domain knowledge, session loading rules and lazy Golden assets.
`tests/test-injection-contract.ps1` validates host projections;
`tests/test-core-installer.ps1 -SelectedTests Test-GenericInstallation` validates the
fresh consumer install path.

## Architectural Boundary

MxMocketeer is an upstream design product. Its seven full canonical skills live under
`products/MxMocketeer/skills/`. `install-core.ps1` copies them into consumer
`.mxagile/skills/`; the existing generator creates host discovery projections. MxAgile
policies remain authoritative for intake, reconciliation, planning, and verification.

Mocketeer host copies are not versioned or generated alongside the product in this
framework repository. Consumer installation/update and disposable packaging/test
fixtures generate `.claude/skills/mocketeer-*`, `.github/skills/mocketeer-*` and
`.agents/skills/mocketeer-*` from staged sources. General MxAgile projections retain
their existing ownership contract. See `docs/injection-contract.md`.
