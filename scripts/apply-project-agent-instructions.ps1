<#
.SYNOPSIS
Applies project-specific agent instructions to platform entry points.

.DESCRIPTION
Uses AGENT.md from the target project as the project instruction source.

Existing AGENTS.md, CLAUDE.md, and Copilot instruction content outside the
managed MxAgile block is preserved. The managed block is appended at the end
of existing user content on first insertion, and replaced in-place on reruns.

Managed block markers:
  <!-- MXAGILE:MANAGED:START --> / <!-- MXAGILE:MANAGED:END -->

Old markers (backward-compatible, migrated on first run):
  <!-- BEGIN PROJECT AGENT INSTRUCTIONS --> / <!-- END PROJECT AGENT INSTRUCTIONS -->

Error conditions (script exits with non-zero):
  - DUPLICATE: more than one managed block found in a file
  - MALFORMED: START marker count does not match END marker count
#>

[CmdletBinding()]
param (
    [string]$ProjectRoot = (Get-Location).Path
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

if (-not (Test-Path -LiteralPath $ProjectRoot -PathType Container)) {
    throw "Project root does not exist: $ProjectRoot"
}

$ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)

$SourcePath  = Join-Path $ProjectRoot "AGENT.md"
$AgentsPath  = Join-Path $ProjectRoot "AGENTS.md"
$ClaudePath  = Join-Path $ProjectRoot "CLAUDE.md"

$GitHubDirectory = Join-Path $ProjectRoot ".github"
$CopilotPath     = Join-Path $GitHubDirectory "copilot-instructions.md"

$SkillsSourceDir   = Join-Path $ProjectRoot "skillssource"
$SkillsAgentsPath  = Join-Path $SkillsSourceDir "AGENTS.md"

$GitIgnorePath = Join-Path $ProjectRoot ".gitignore"

# Current canonical markers
$NewStartMarker = "<!-- MXAGILE:MANAGED:START -->"
$NewEndMarker   = "<!-- MXAGILE:MANAGED:END -->"

# Legacy markers (detected for migration; do not write these)
$OldStartMarker = "<!-- BEGIN PROJECT AGENT INSTRUCTIONS -->"
$OldEndMarker   = "<!-- END PROJECT AGENT INSTRUCTIONS -->"

$Utf8WithoutBom = [System.Text.UTF8Encoding]::new($false)

# ---------------------------------------------------------------------
# Remove-LegacyBlock
# Strips the old-marker managed block from content (used internally).
# Retained for backward-compat reference; Apply-ManagedBlock handles
# migration automatically.
# ---------------------------------------------------------------------
function Remove-LegacyBlock {
    param(
        [AllowEmptyString()]
        [string]$Content
    )

    if ([string]::IsNullOrEmpty($Content)) {
        return ""
    }

    $pattern = '(?s)<!-- BEGIN PROJECT AGENT INSTRUCTIONS -->.*?<!-- END PROJECT AGENT INSTRUCTIONS -->\s*'
    return [regex]::Replace($Content, $pattern, "")
}

# ---------------------------------------------------------------------
# Apply-ManagedBlock
# Idempotent injection of a managed block into a file.
#
# Behavior:
#   MISSING (no block)       -> Append block at end of existing content.
#   VALID (one block)        -> Replace block in-place; migrate old markers.
#   DUPLICATE (>1 block)     -> Throw diagnostic error. Script exits non-zero.
#   MALFORMED (count != END) -> Throw diagnostic error. Script exits non-zero.
# ---------------------------------------------------------------------
function Apply-ManagedBlock {
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [Parameter(Mandatory)]
        [string]$BlockContent,

        [Parameter(Mandatory)]
        [string]$FileDescription
    )

    # Read current file content (empty string if file does not exist yet)
    $currentContent = ""
    if (Test-Path -LiteralPath $FilePath -PathType Leaf) {
        $currentContent = Get-Content -LiteralPath $FilePath -Raw
        if ($null -eq $currentContent) { $currentContent = "" }
    }

    # Count occurrences of each marker variant
    $newStartCount = ([regex]::Matches($currentContent, [regex]::Escape($NewStartMarker))).Count
    $newEndCount   = ([regex]::Matches($currentContent, [regex]::Escape($NewEndMarker))).Count
    $oldStartCount = ([regex]::Matches($currentContent, [regex]::Escape($OldStartMarker))).Count
    $oldEndCount   = ([regex]::Matches($currentContent, [regex]::Escape($OldEndMarker))).Count

    $totalStart = $newStartCount + $oldStartCount
    $totalEnd   = $newEndCount   + $oldEndCount

    # --- DUPLICATE ---
    if ($totalStart -gt 1 -or $totalEnd -gt 1) {
        throw @"
MXAGILE INJECTION ERROR: Multiple managed blocks detected in ${FileDescription}.
  File   : $FilePath
  START markers (new): $newStartCount  (old): $oldStartCount  (total): $totalStart
  END   markers (new): $newEndCount  (old): $oldEndCount  (total): $totalEnd

Manual intervention required. Remove the duplicate managed blocks before rerunning.
"@
    }

    # --- MALFORMED ---
    if ($totalStart -ne $totalEnd) {
        throw @"
MXAGILE INJECTION ERROR: Malformed managed block in ${FileDescription}.
  File   : $FilePath
  START markers found: $totalStart
  END   markers found: $totalEnd

Manual intervention required. Fix the managed block before rerunning.
"@
    }

    # Build the replacement managed block
    $newBlock = "${NewStartMarker}`n${BlockContent}`n${NewEndMarker}"

    if ($totalStart -eq 0) {
        # --- MISSING: no block — append at end ---
        if ([string]::IsNullOrEmpty($currentContent.Trim())) {
            $newContent = $newBlock + "`n"
        } else {
            $trimmed = $currentContent.TrimEnd("`r", "`n")
            $newContent = $trimmed + "`n`n" + $newBlock + "`n"
        }
    } else {
        # --- VALID: one block — replace in-place, migrating old markers if needed ---
        $useStart = if ($oldStartCount -gt 0) { $OldStartMarker } else { $NewStartMarker }
        $useEnd   = if ($oldEndCount   -gt 0) { $OldEndMarker   } else { $NewEndMarker   }

        $startIdx = $currentContent.IndexOf($useStart)
        $endIdx   = $currentContent.IndexOf($useEnd)
        $endPos   = $endIdx + $useEnd.Length

        # Content before the block (trim trailing whitespace/newlines)
        $before = $currentContent.Substring(0, $startIdx).TrimEnd("`r", "`n")

        # Content after the block (trim leading whitespace/newlines)
        $after = if ($endPos -lt $currentContent.Length) {
            $currentContent.Substring($endPos).TrimStart("`r", "`n")
        } else {
            ""
        }

        # Reconstruct: before + blank line + block + blank line + after
        $parts = @()
        if ($before.Length -gt 0) {
            $parts += $before
            $parts += ""  # blank line separator
        }
        $parts += $newBlock

        if ($after.Length -gt 0) {
            $parts += ""  # blank line separator
            $parts += $after
        }

        $newContent = ($parts -join "`n") + "`n"
    }

    [System.IO.File]::WriteAllText($FilePath, $newContent, $Utf8WithoutBom)
}

# ---------------------------------------------------------------------
# Ensure-Directory
# ---------------------------------------------------------------------
function Ensure-Directory {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

# ---------------------------------------------------------------------
# Add-GitIgnoreEntry
# ---------------------------------------------------------------------
function Add-GitIgnoreEntry {
    param(
        [Parameter(Mandatory)]
        [string]$Entry
    )

    $content = if (Test-Path -LiteralPath $GitIgnorePath -PathType Leaf) {
        Get-Content -LiteralPath $GitIgnorePath -Raw
    } else {
        ""
    }

    $existing = @(
        $content -split "`r?`n" |
        ForEach-Object { $_.Trim() }
    )

    if ($existing -notcontains $Entry) {
        $prefix = if ($content -and -not $content.EndsWith("`n")) { "`n" } else { "" }
        [System.IO.File]::AppendAllText(
            $GitIgnorePath,
            "$prefix$Entry`n",
            $Utf8WithoutBom
        )
    }
}

# ---------------------------------------------------------------------
# Validate required source file
# ---------------------------------------------------------------------
foreach ($requiredPath in @($SourcePath, $AgentsPath, $ClaudePath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw @"
Required project file does not exist:

  $requiredPath

Ensure mxcli init and the MxAgile project skeleton have been initialized first.
"@
    }
}

# ---------------------------------------------------------------------
# Ensure output directories
# ---------------------------------------------------------------------
Ensure-Directory -Path $GitHubDirectory

# ---------------------------------------------------------------------
# Read project instructions
# ---------------------------------------------------------------------
$ProjectInstructions = Get-Content -LiteralPath $SourcePath -Raw
if ($null -eq $ProjectInstructions) { $ProjectInstructions = "" }

# ---------------------------------------------------------------------
# MxAgile startup routing block
# Injected at the top of every managed block so that Lifecycle Re-Sync
# is the first orientation step in an existing MxAgile project —
# BEFORE Project Brain, Git history, or generic memory.
# ---------------------------------------------------------------------
$MxAgileStartupBlock = @'
## MxAgile Startup — Lifecycle Re-Sync First

**This is a MxAgile-managed Mendix project.**

When starting, resuming, or picking up work, follow this order:

1. **Lifecycle Re-Sync FIRST** — check for `.mxagile/` and `.concord/scratch/process-state.yaml`.
   If present, read `.mxagile/policies/lifecycle-resync.md` and reconstruct the current
   delivery position (wave, phase, completed/remaining checklist items) BEFORE anything else.
   The Startup Re-Sync algorithm is in `policies/lifecycle-resync.md` step 0.

2. **Project Brain after Re-Sync** — consult `./mxcli brain plan` or `docs/brain/` only
   AFTER the lifecycle position is established. Brain is supplementary context, not lifecycle state.

3. **Empty Brain does NOT require Git history** — if Brain has no slices, continue from
   canonical project artifacts. Do NOT inspect parent Git history or sibling repositories.

4. **Git history is not lifecycle state** — use `planning/checklists/` and `sprints/decisions.md`
   as the authoritative resume evidence. Do not run `git log` to reconstruct delivery position.

5. **Scope: this project root only** — do not traverse into parent directories, parent repositories,
   sibling projects, or `project-templates/`. All lifecycle evidence is inside this project.

Detailed policy: `.mxagile/policies/lifecycle-resync.md`
'@

# ---------------------------------------------------------------------
# Compose managed block content
# Each block = [MxAgile startup routing] + [project-specific instructions]
# CLAUDE.md uses @AGENT.md reference (Claude-specific include syntax).
# AGENTS.md and Copilot use the full AGENT.md content inline.
# ---------------------------------------------------------------------
$AgentsBlockContent  = if ([string]::IsNullOrWhiteSpace($ProjectInstructions)) {
    $MxAgileStartupBlock
} else {
    $MxAgileStartupBlock + "`n`n" + $ProjectInstructions.Trim()
}

$ClaudeBlockContent  = $MxAgileStartupBlock + "`n`n@AGENT.md"

$CopilotBlockContent = $AgentsBlockContent

# ---------------------------------------------------------------------
# Apply managed blocks
# ---------------------------------------------------------------------
Apply-ManagedBlock `
    -FilePath        $AgentsPath `
    -BlockContent    $AgentsBlockContent `
    -FileDescription "AGENTS.md"

Apply-ManagedBlock `
    -FilePath        $ClaudePath `
    -BlockContent    $ClaudeBlockContent `
    -FileDescription "CLAUDE.md"

Apply-ManagedBlock `
    -FilePath        $CopilotPath `
    -BlockContent    $CopilotBlockContent `
    -FileDescription ".github/copilot-instructions.md"

# skillssource/AGENTS.md — project knowledge index/router for Maia and skillssource-aware tools.
# mxcli init does not create this file; MxAgile owns the managed block.
# Existing user content (domain conventions, coding rules) is preserved outside the block.
if (Test-Path -LiteralPath $SkillsSourceDir -PathType Container) {
    $skillsAgentsBlock = @'
## MxAgile Startup — Lifecycle Re-Sync First

**This is a MxAgile-managed Mendix project.**

When starting, resuming, or picking up work:
1. Check `.mxagile/` and `.concord/scratch/process-state.yaml` → Lifecycle Re-Sync FIRST.
2. Reconstruct: process-state → checklist → decisions → story specs.
3. Empty Brain → continue from project artifacts. Do NOT inspect Git history.
4. Scope: this project root only. Do not traverse parent or sibling directories.

Policy: `.mxagile/policies/lifecycle-resync.md`

---

## MxAgile Project Knowledge Index

This section routes to canonical project knowledge. Never duplicate content here.

**Project description:** `projekt.md` (goals, tech stack, modules, sprint structure)

**Input resources** (when present):
- UI/UX mockups and requirements: `input-resources/`
- Analysis guidelines: `input-resources/README.md`

**Planning and specifications** (when present):
- Story specifications: `planning/stories/`
- Execution waves: `planning/execution-waves.md`
- Implementation checklists: `planning/checklists/`
- Decisions: `sprints/decisions.md`

**Requirements and specs** (when present):
- `requirements/`, `specs/`

**MxAgile lifecycle:**
- Canonical definition: `.mxagile/lifecycle.yaml`
- Narrative expansion: `.mxagile/orchestrator.md`
- Framework skills and agents: `.mxagile/`

Paths marked "(when present)" may not exist yet in a new project. Discover what exists and proceed per the MxAgile lifecycle.
'@

    Apply-ManagedBlock `
        -FilePath        $SkillsAgentsPath `
        -BlockContent    $skillsAgentsBlock `
        -FileDescription "skillssource/AGENTS.md"

    Write-Host "  $SkillsAgentsPath"
}

# ---------------------------------------------------------------------
# Local-state ignore rules
# ---------------------------------------------------------------------
Add-GitIgnoreEntry -Entry "/.env.mendix"
Add-GitIgnoreEntry -Entry "/.mxcli/catalog.db"
Add-GitIgnoreEntry -Entry "/sprints/generated/"
Add-GitIgnoreEntry -Entry "/planning/generated/"

Write-Host "Applied project instructions:"
Write-Host "  $AgentsPath"
Write-Host "  $ClaudePath"
Write-Host "  $CopilotPath"
