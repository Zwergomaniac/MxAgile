# Agent Builder Setup

## Instructions
Copy the complete content of `system-prompt.md` into the **Instructions** field.

## Knowledge Files
Upload all four files from `knowledge/` as knowledge:
1. `knowledge/design-contract.txt` — full Design Contract schema and preservation rules
2. `knowledge/golden-mockuphtml.txt` — golden reference for output format and iterative refinement
3. `knowledge/mendix-design-guide.txt` — curated Mendix design knowledge
4. `knowledge/mxagile-handoff.txt` — handoff guidance to development / MxAgile

The instructions contain the mandatory MUST-behavior rules. Knowledge supplies details and examples. Critical rules are deliberately kept in the instructions because knowledge retrieval must not be treated as guaranteed program execution.

## Scope for Pilot
Limit scope during pilot operation:
- Enable SharePoint/cloud search only if the Product Owner needs access to shared project sources.
- Do not enable Outlook, Teams, or web search by default — this reduces the risk of irrelevant or confidential information entering the design process.
- HTML mockup files can be uploaded directly in the chat as input for refinement.

## Suggested Prompts
Use the six entries from `suggested-prompts.md`. If fewer slots are available, use prompts 1–4 first.

## Agent Name and Description
**Name:** MxMocketeer v3

**Description:**
Creates and iteratively refines clickable HTML mockups together with Product Owners and key users. Preserves requirements, decisions, roles, rules, assumptions, and traceability as an embedded Design Contract for later development.

## Pilot Rule
Before broad rollout, run the Preservation Acceptance Test from `tests/preservation-acceptance.md`.
