# Agent Builder Setup

## Instructions
Copy the complete content of `system-prompt.md` into the **Instructions** field.

### Canonical Text and Length Budget

The release representation is the complete UTF-8 prompt text with CRLF and bare
CR line endings normalized to LF. Each line break counts once. No trimming,
content removal or Unicode normalization is performed; a trailing newline counts.
Validation uses the resulting .NET string length, retains the 8000-character hard
limit and requires at least 100 characters of reserve (at most 7900 characters).
Git checkout line endings must not change this result.

Use the same canonical text for the Instructions field. From this product directory
in PowerShell, prepare the clipboard without changing the source file:

```powershell
$prompt = Get-Content ./system-prompt.md -Raw -Encoding UTF8
Set-Clipboard -Value ($prompt.Replace("`r`n", "`n").Replace("`r", "`n"))
```

## Knowledge Files
Upload all seven files from `knowledge/` as knowledge:
1. `knowledge/design-contract.txt` — Design Contract v1 schema, structured flows schema, maturity assessment schema, preservation rules
2. `knowledge/discovery-assessment.txt` — assessment dimensions (incl. DIM-BUSINESS_FLOWS), gap taxonomy, interview strategy, readiness rules
3. `knowledge/golden-mockuphtml.txt` — golden reference for output format and iterative refinement
4. `knowledge/mendix-design-guide.txt` — curated Mendix design knowledge
5. `knowledge/mxagile-handoff.txt` — handoff guidance to development / MxAgile, Business Flow producer obligations, revision delta, stable ID contract
6. `knowledge/business-flows.txt` — Business Flow schema, step types, FLOW-NNN/FLOWSTEP-NNN IDs, Mermaid generation, flow revision impact, flow-to-verification traceability
7. `knowledge/refinement-transformations.txt` — edit classification (LOCAL_EDIT, CROSS_CUTTING_EDIT, STRUCTURAL_REFACTOR, FULL_REGENERATION), Transformation Spec schema, safe target resolution, preservation validation, machine-readable handoff format

Note: `knowledge/knowledge-graph.txt` is NOT uploaded to M365. It is MxAgile repository/framework documentation for pipeline agents. See `docs/mxagile-knowledge-graph.md`.

The instructions contain the mandatory MUST-behavior rules. Knowledge supplies details and examples. Critical rules are deliberately kept in the instructions because knowledge retrieval must not be treated as guaranteed program execution.

## Scope for Pilot
Limit scope during pilot operation:
- Enable SharePoint/cloud search only if the Product Owner needs access to shared project sources.
- Do not enable Outlook, Teams, or web search by default — this reduces the risk of irrelevant or confidential information entering the design process.
- HTML mockup files can be uploaded directly in the chat as input for refinement.

## Suggested Prompts
Use the six entries from `suggested-prompts.md`. If fewer slots are available, use prompts 1, 2, 4, 3 (in that order).

## Agent Name and Description
**Name:** MxMocketeer v3

**Description:**
Creates and iteratively refines clickable HTML mockups together with Product Owners and key users. Preserves requirements, decisions, roles, rules, assumptions, and traceability as an embedded Design Contract for later development.

## Pilot Rule
Before broad rollout, run the Preservation Acceptance Test from `tests/preservation-acceptance.md`.
