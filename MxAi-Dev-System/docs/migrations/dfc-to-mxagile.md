# Migration Guide: DFC / DFC-AI → MxAgile

This document describes how to migrate a project that was installed with the
historical DFC / DFC-AI framework to the current MxAgile framework.

DFC and DFC-AI are the **legacy predecessor names** for what is now called MxAgile.
No new projects should use DFC naming. This guide exists to support upgrading
installations from the legacy product.

---

## Terminology Mapping

| LEGACY (DFC / DFC-AI) | CURRENT (MxAgile) |
|----------------------|-------------------|
| DFC | MxAgile |
| DFC-AI | MxAgile |
| `.MxAgile/` (capital M) | `.mxagile/` (lowercase) |
| `dfc-discovery` | `mxagile-discovery` |
| `dfc-refinement` | `mxagile-refinement` |
| `dfc-quality-gate` | `mxagile-quality-gate` |
| `dfc-gate-to-refinement` | `mxagile-gate-to-refinement` |
| `dfc-gate-to-ready` | `mxagile-gate-to-ready` |
| `.claude/skills/dfc/` | `.claude/skills/mxagile-{name}/SKILL.md` |
| `.agents/skills/dfc/` | `.agents/skills/mxagile/` |
| `.grok/skills/dfc/` | `.grok/skills/mxagile/` |
| `.opencode/skills/dfc/` | `.opencode/skills/mxagile/` |
| `.hermes/skills/dfc/` | `.hermes/skills/mxagile/` |
| `.github/skills/dfc-*/` | `.github/skills/mxagile-{name}/SKILL.md` |
| `Source: .MxAgile/` (generated header) | `Source: .mxagile/` |

---

## Identifying a Legacy DFC Installation

A project has a LEGACY DFC installation if any of the following exist:

1. `.MxAgile/` directory at the project root (capital M in Mx)
2. Generated files in `.claude/skills/dfc/` with `# GENERATED` header
3. Generated files in `.agents/skills/dfc/`
4. Generated files in `.grok/skills/dfc/`
5. Generated files in `.opencode/skills/dfc/`
6. Generated files in `.hermes/skills/dfc/`
7. Generated files containing `Source: .MxAgile/` in their header

Note: The presence of `dfc` in a directory name alone is not sufficient proof of
MxAgile ownership. Always verify `# GENERATED` headers before removing content.

---

## Migration Steps

### Prerequisites

- Current MxAgile installer: `install-mxagile.ps1` (or `install-mxagile-mercedes.ps1`)
- PowerShell 7+ (pwsh)
- The target Mendix project directory

### Step 1: Inventory legacy artifacts

```powershell
# Check for legacy canonical source
Test-Path ".MxAgile"

# Check for legacy platform projections
Test-Path ".claude\skills\dfc"
Test-Path ".agents\skills\dfc"
Test-Path ".grok\skills\dfc"
Test-Path ".opencode\skills\dfc"
Test-Path ".hermes\skills\dfc"
```

### Step 2: Run current MxAgile installer

Running the current installer will generate canonical MxAgile projections:

```powershell
pwsh -File path\to\MxAi-Dev-System\install-mxagile.ps1 -ProjectRoot <ProjectRoot>
```

This generates (among other things):
- `.claude/skills/mxagile-{name}/SKILL.md`
- `.agents/skills/mxagile/{name}.md`
- `.github/skills/mxagile-{name}/SKILL.md`
- etc.

### Step 3: Remove proven legacy projections

After verifying the new projections exist, remove legacy DFC directories that
are confirmed MxAgile-generated (contain `# GENERATED` header):

```powershell
# Verify ownership before removal
foreach ($legacyPath in @(".claude\skills\dfc", ".agents\skills\dfc", ".grok\skills\dfc", ".opencode\skills\dfc", ".hermes\skills\dfc")) {
    if (Test-Path $legacyPath) {
        $files = Get-ChildItem $legacyPath -Filter "*.md"
        $isOwned = $files | Where-Object { (Get-Content $_.FullName -Raw) -match '# GENERATED' }
        if ($isOwned) {
            Write-Host "Removing owned legacy path: $legacyPath"
            Remove-Item $legacyPath -Recurse -Force
        } else {
            Write-Warning "SKIPPED: $legacyPath contains unowned files — manual review required"
        }
    }
}
```

### Step 4: Handle legacy canonical source `.MxAgile/`

If `.MxAgile/` (capital M) exists:

```powershell
if (Test-Path ".MxAgile") {
    if (Test-Path ".mxagile") {
        Write-Warning ".mxagile/ already exists. Review .MxAgile/ manually before removing."
    } else {
        Write-Warning ".MxAgile/ found but no .mxagile/ exists. This project may be on a very old version."
        Write-Warning "Run install-mxagile.ps1 first, then remove .MxAgile/ after verifying .mxagile/ is correct."
    }
}
```

### Step 5: Verify migration

Run the `mxagile-system-check` skill in a new agent session:

```
Run the MxAgile system check and output the complete diagnostic report.
```

The report should show:
- No legacy `dfc/` directories under `.claude/skills/`, `.agents/skills/`, etc.
- Current `mxagile-*` skills present
- No `.MxAgile/` (capital M) directory

---

## Managed Instruction Blocks

If the project's `AGENTS.md`, `CLAUDE.md`, or `.github/copilot-instructions.md` contain
old instruction block markers:

```
<!-- BEGIN PROJECT AGENT INSTRUCTIONS -->
...
<!-- END PROJECT AGENT INSTRUCTIONS -->
```

Running `scripts/apply-project-agent-instructions.ps1` will automatically detect
these legacy markers and migrate them to the current format:

```
<!-- MXAGILE:MANAGED:START -->
...
<!-- MXAGILE:MANAGED:END -->
```

User content surrounding the block is preserved.

---

## What Is Safe to Remove

| Artifact | Safe to Remove | Condition |
|----------|---------------|-----------|
| `.claude/skills/dfc/*.md` | YES | Only if files contain `# GENERATED` header |
| `.agents/skills/dfc/*.md` | YES | Only if files contain `# GENERATED` header |
| `.grok/skills/dfc/*.md` | YES | Only if files contain `# GENERATED` header |
| `.opencode/skills/dfc/*.md` | YES | Only if files contain `# GENERATED` header |
| `.hermes/skills/dfc/*.md` | YES | Only if files contain `# GENERATED` header |
| `.MxAgile/` directory | YES (after migration) | Only after `.mxagile/` is confirmed correct |

| Artifact | NOT Safe to Remove |
|----------|-------------------|
| Any `dfc/` file WITHOUT `# GENERATED` header | User-owned content |
| `AGENT.md` | User/project owned |
| Content outside managed blocks | User-owned content |

---

## For the Maintainer Agent

The `mxagile-maintainer` agent handles migration tasks. Use the skill:

```
/mxagile-maintainer
```

or:

```
Run the MxAgile Maintainer Agent to migrate this project from legacy DFC to MxAgile.
```
