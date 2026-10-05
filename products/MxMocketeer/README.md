# MxMocketeer v3

MxMocketeer is a discovery, requirements, UI/UX, and HTML mockup agent for Mendix and digital transformation projects. Product Owners and key users develop clickable prototypes through conversation. Requirements, decisions, roles, rules, assumptions, and traceability travel invisibly as an embedded Design Contract inside the same HTML file.

## Package Structure

```
products/MxMocketeer/
    system-prompt.md          — agent instructions (paste into M365 Copilot Agent Builder)
    suggested-prompts.md      — six Product Owner starter prompts
    agent-builder-setup.md    — step-by-step configuration guide
    README.md

    knowledge/
        design-contract.txt   — Design Contract v1 schema and preservation rules
        mendix-design-guide.txt — Mendix-aligned design guidance
        mxagile-handoff.txt   — handoff mapping to development / MxAgile
        golden-mockuphtml.txt — complete golden reference mockup (HTML source in TXT)

    tests/
        preservation-acceptance.md        — manual acceptance test procedure
        test-mocketeer-validation.ps1     — automated static validation (Tier 0)
```

## Setup Order

1. Open Microsoft 365 Copilot Agent Builder (or equivalent).
2. Paste `system-prompt.md` into the **Instructions** field.
3. Upload all four files from `knowledge/` as knowledge.
4. Add the six entries from `suggested-prompts.md` as suggested prompts.
5. Name the agent **MxMocketeer v3**.
6. Publish with limited scope for pilot testing.
7. Run `tests/preservation-acceptance.md` before broad rollout.

See `agent-builder-setup.md` for full configuration guidance.

## Product Owner Usage

**New design:** Start a conversation → answer focused questions → receive HTML mockup.

**Refinement:** Upload existing HTML → request change → agent reads current mockup and Design Contract, preserves unrelated content, produces next complete revision.

**Handoff:** Upload finalized mockup → request readiness review → open business questions identified → hand to development / MxAgile.

## Design Contract

Every MxMocketeer output is a self-contained HTML file containing:
- Visible clickable prototype (HTML + CSS + JavaScript)
- Embedded machine-readable Design Contract (`<script type="application/json" id="mocketeer-spec">`)

The contract preserves requirements, decisions, roles (with positive and explicit negative capabilities), business rules, flows, states, assumptions, open questions, and traceability across iterative refinements.

Schema reference: `knowledge/design-contract.txt`

## Golden Reference Mockup

`knowledge/golden-mockuphtml.txt` contains the complete HTML source of the golden reference mockup, including embedded CSS, JavaScript, synthetic mock data, and embedded Design Contract. It is HTML content stored as a TXT file for M365 Copilot knowledge upload.

The mockup demonstrates: multiple roles, positive/negative permissions, search/filter, create dialog, validation, role-switching, empty state, spec-footer, traceability attributes, stable IDs, and a complete Design Contract.

## Validation

Run the automated Tier 0 validation from the repository root:

```powershell
pwsh products/MxMocketeer/tests/test-mocketeer-validation.ps1
```

Validates: required files, system prompt character count, golden mockup completeness (HTML/CSS/JS/Design Contract), JSON integrity, ID uniqueness and reference resolution, company-neutral content, and knowledge file completeness.

## Architectural Boundary

MxMocketeer is an upstream design product. It produces the Design Contract. It does not consume or generate MxAgile canonical artifacts. That mapping is described in `knowledge/mxagile-handoff.txt` and is a separate work package.
