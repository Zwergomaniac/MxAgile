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
The seven canonical skill files are under `skills/mocketeer-*/SKILL.md`.
Each retains substantive domain knowledge and exact `name`/`description` YAML
frontmatter. The complete Golden HTML is a separate optional asset at
`skills/mocketeer-mockup-generation/assets/golden-mockup.html`. No other knowledge
was moved to references merely to make the entries smaller.

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

Associate `assets/golden-mockup.html` with the generation skill, preserving the
relative asset path where the host supports skill directories. If Agent Builder
manages skills as separate files, expose the identical HTML as a separately named
retrievable asset, not as another skill or inline Instructions. Resolve the skill's
relative asset name to that resource without changing its content or semantics.
There is no ZIP or combined master skill.

Before publishing, verify that the agent can explicitly retrieve all seven named
skill entries, rather than relying solely on automatic task-based selection. Check
asset availability through the host's resource inventory without preloading its HTML
at bootstrap. If the host cannot expose all seven entries, do not claim bootstrap
support or publish a simplified variant; configure access or stop affected work.
Missing assets block only tasks that actually need them. This is an instruction
contract, not a technical guarantee that a host follows every load instruction.

## Session Bootstrap and Task Execution

On first Mocketeer work in a new session, read all seven SKILL.md once and establish
the shared product model. Follow the Session Initialization contract in
`mocketeer-discovery`: process, boundaries, terms, artifact handoffs, authorities and
quality gates. Keep revisions/fingerprints and loaded context only in transient agent
context. Do not persist a new business status.

For subsequent tasks, reuse the model, apply the relevant skills and retrieve only
needed additional references/assets. Discovery does not load Golden HTML or all
technical references. Generation loads Golden HTML only if a concrete example,
visual calibration or Golden check is needed. A relevant skill/product update or new
session requires bootstrap again. After Context Compaction, verify retained context;
if insufficient, reread entries or reconstruct the missing baseline before work.

Microsoft Copilot, Claude and Concord use the same seven canonical sources and
identical asset bytes. Run the host-specific manual checks in
`tests/preservation-acceptance.md`; static contract tests alone do not prove actual
host retrieval behavior.

For Claude/Concord consumer repositories, run normal MxAgile setup/update.
`install-core.ps1` copies the seven product-owned skill directories, including assets, into
consumer `.mxagile/skills/`, then `generate-mxagile-platform-skills.ps1` writes:

- Claude: `<project>/.claude/skills/<skill-name>/SKILL.md`
- Microsoft Copilot: `<project>/.github/skills/<skill-name>/SKILL.md`
- Portable/Concord: `<project>/.agents/skills/<skill-name>/SKILL.md`

The normal MxAgile installer/generator is the only consumer-repository delivery
mechanism. Updates refresh the seven consumer copies and regenerate host projections
from the product-owned sources. `docs/mxagile-knowledge-graph.md` remains internal
MxAgile documentation and is not one of the seven skills.

The framework repository keeps only canonical Mocketeer product sources, not local
copies under `.claude`, `.github` or `.agents`. Repository packaging stages those
sources into a disposable consumer `.mxagile/skills/` tree before running the generator.
Fresh Install and unchanged updates reproduce the same host skill and asset bytes.
Foreign host skills fail closed without being overwritten. The general MxAgile host
projections are not covered by this product-source cleanup exception.

Microsoft Copilot session smoke: **NOT_VERIFIED**. No actual Agent Builder session or
observable retrieval trace is available here. Use the short acceptance procedure in
`tests/preservation-acceptance.md`; file/fixture parity is not live-session acceptance.

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
