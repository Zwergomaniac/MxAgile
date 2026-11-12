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

## Canonical Skills and Host Discovery
The seven full canonical skill files are under `skills/mocketeer-*/SKILL.md`.
Each includes its complete domain knowledge and exact `name`/`description` YAML
frontmatter. There are no separate reference files to upload or retrieve.

For Microsoft Copilot Agent Builder, add the seven individual files as seven Skills:

```text
skills/mocketeer-discovery/SKILL.md
skills/mocketeer-design-contract/SKILL.md
skills/mocketeer-refinement/SKILL.md
skills/mocketeer-preservation/SKILL.md
skills/mocketeer-business-flows/SKILL.md
skills/mocketeer-mockup-generation/SKILL.md
skills/mocketeer-handoff/SKILL.md
```

For Claude/Concord consumer repositories, run normal MxAgile setup/update.
`install-core.ps1` copies the seven product-owned skill files into
consumer `.mxagile/skills/`, then `generate-mxagile-platform-skills.ps1` writes:

- Claude: `<project>/.claude/skills/<skill-name>/SKILL.md`
- Microsoft Copilot: `<project>/.github/skills/<skill-name>/SKILL.md`
- Portable/Concord: `<project>/.agents/skills/<skill-name>/SKILL.md`

The normal MxAgile installer/generator is the only consumer-repository delivery
mechanism. Updates refresh the seven consumer copies and regenerate host projections
from the product-owned sources. `docs/mxagile-knowledge-graph.md` remains internal
MxAgile documentation and is not one of the seven skills.

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
