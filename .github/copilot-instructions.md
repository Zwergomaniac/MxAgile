# Mendix AI Framework Workspace

This workspace maintains reusable AI-assisted delivery assets for Mendix projects in the Mercedes-Benz environment. It is a framework source workspace, not a runnable Mendix application and not a customer project.

## Workspace purpose

- `extract to root project vx.x/` is the canonical template copied into a new Mendix project.
- `MxMocketeer/` contains shared Copilot prompts for requirements discovery and interactive HTML mockups.
- `MxScrumMaster/` contains shared Copilot prompts for product, backlog, and delivery preparation.
- `.github/agents/` contains Copilot agents used to maintain and review this framework source.
- `extract to root project vx.x/.dfc-ai/GLOSSARY.yaml` defines the internal terminology copied into Mendix projects.

## Working rules

- Start with the concrete artifact named by the requester. Read the smallest relevant neighbouring documentation before changing it.
- Preserve the responsibility boundaries: Mocketeer discovers and prototypes; ScrumMaster creates and maintains Board-led planning; the copied project template governs discovery through verification inside a Mendix project.
- Treat `extract to root project vx.x/` as a distributable product. Do not add framework-maintenance tools, machine-specific paths, credentials, or private workspace assumptions to it.
- In a copied project, the Mendix Epics Board is the operational source of truth when configured. Local files are derived planning or technical artifacts and must not replace Board status, sprints, tasks, or acceptance criteria.
- Reuse existing DFC-AI agents, skills, policies, and scripts before introducing new parallel processes or terminology.
- Keep instructions role-specific. Shared project facts belong in `projekt.md`; tool-specific behavior belongs in the corresponding agent or instruction file.
- Before work involving Mendix modeling, roles, user access, UI, feedback, or reuse, read `extract to root project vx.x/.dfc-ai/GLOSSARY.yaml`, then `extract to root project vx.x/.dfc-ai/modules/platform-modules.md`, and the relevant module detail. Module references take precedence when they conflict with this summary.
- Do not modify Mercedes-Benz platform modules. Prefer documented platform modules and Marketplace components before proposing custom solutions.
- Never read, expose, add, or version credentials. `.env.mendix` is local configuration only.
- Do not use manual Git commit or push steps as part of a Mendix project workflow; Mendix Team Server owns version control.
- Preserve existing language and ASCII conventions. Write German by default unless a request specifies another language.

## Change quality

- Make focused, minimal changes; avoid unrelated formatting and prompt rewrites.
- Update directly coupled documentation when a workflow, path, artifact contract, or ownership changes.
- Validate modified Markdown/frontmatter, referenced paths, and changed scripts with the narrowest available check.
- Mark unresolved evidence as `ASSUMPTION` or `DECISION REQUIRED`; do not encode unsupported rules as mandatory behavior.

## Specialized agents

- Use **Mendix AI Framework Maintainer** for changes to template architecture, prompts, agents, skills, policies, scripts, and cross-version consolidation.
- Use **Mendix AI Framework Reviewer** for read-only release and consistency reviews across the template, shared prompts, and automation.