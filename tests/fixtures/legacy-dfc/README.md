# Legacy DFC Fixture

This directory simulates a project installed with the LEGACY DFC / DFC-AI framework
(the historical predecessor to MxAgile).

**Purpose:** Migration tests and zero-legacy guard validation use this fixture to
verify that:
1. The MxAgile Maintainer Agent can detect legacy DFC structures
2. The migration path correctly produces canonical MxAgile output
3. The zero-legacy guard correctly ALLOWS these occurrences (they are intentional)

**This fixture intentionally contains legacy DFC naming.**

Legacy names here are CORRECT for a fixture — do not rename them to mxagile.

## Simulated Legacy Structure

```
.MxAgile/                    <- legacy canonical source (capital M — intentional)
  skills/
    discovery.md             <- legacy neutral skill (no frontmatter)
    refinement.md
  agents/
    discovery-agent.md

.claude/skills/dfc/          <- legacy Claude projections (dfc/ dir — intentional)
  discovery.md               <- GENERATED file with legacy header
  refinement.md

.agents/skills/dfc/          <- legacy Codex projections (dfc/ dir — intentional)
  discovery.md

.opencode/skills/dfc/        <- legacy OpenCode projections (dfc/ dir — intentional)
  discovery.md

project.mpr                  <- dummy Mendix project file
```

## Expected Migration Result

After running the migration / current MxAgile installer:

- `.mxagile/` exists (or `.MxAgile/` renamed to `.mxagile/`)
- `.claude/skills/mxagile-*/SKILL.md` exists (new naming)
- `.agents/skills/mxagile/` exists (new naming)
- `.opencode/skills/mxagile/` exists (new naming)
- Legacy `dfc/` directories removed (proven GENERATED ownership)
- User content preserved
