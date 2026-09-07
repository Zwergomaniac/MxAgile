<#
.SYNOPSIS
    Generates platform-specific skills and agents from .dfc-ai/ neutral sources.

.DESCRIPTION
    Reads neutral skill/agent bodies from .dfc-ai/skills/ and .dfc-ai/agents/,
    prepends platform-specific frontmatter, and writes the result into platform
    directories (.claude/, .github/, .agents/, .grok/).

    All generated files carry a "# GENERATED" header and the dfc- prefix.
    Adapter YAML files under .dfc-ai/adapters/ document the frontmatter per
    platform but are not parsed at runtime — the configuration is inline below.

.PARAMETER ProjectRoot
    Root directory of the Mendix project. Defaults to current directory.

.PARAMETER DryRun
    Show what would be generated without writing files.
#>
[CmdletBinding()]
param(
    [string]$ProjectRoot = $PWD.Path,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$dfcRoot = Join-Path $ProjectRoot '.dfc-ai'
$generatedHeader = "# GENERATED - DO NOT EDIT - Source: .dfc-ai/"

if (-not (Test-Path $dfcRoot)) {
    Write-Error ".dfc-ai/ directory not found at $dfcRoot"
    exit 1
}

function Get-FirstContentLine {
    param([string]$Body)
    foreach ($line in ($Body -split '\n')) {
        $trimmed = $line.Trim()
        if ($trimmed -and -not $trimmed.StartsWith('#')) {
            return $trimmed
        }
    }
    return "DFC process skill"
}

function Write-Generated {
    param([string]$OutputPath, [string]$Content)
    if ($DryRun) {
        Write-Host "  [DRY RUN] $OutputPath"
    } else {
        $dir = Split-Path $OutputPath -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        [System.IO.File]::WriteAllText($OutputPath, $Content, [System.Text.UTF8Encoding]::new($false))
        Write-Host "  Generated: $OutputPath"
    }
}

# --- Skill descriptions (overrides; fallback = first content line) ---
$skillDescriptions = @{
    'discovery'          = 'Systematische Analyse aller Quellen vor Refinement/Implementierung'
    'refinement'         = 'Klaerung offener Punkte und Widersprueche vor Implementierung'
    'quality-gate'       = 'Mehrstufige Validierung nach Implementierung'
    'gate-to-refinement' = 'Gate-Pruefung: Discovery vollstaendig?'
    'gate-to-ready'      = 'Gate-Pruefung: Refinement vollstaendig, bereit fuer Implementierung?'
}

# --- Agent descriptions ---
$agentDescriptions = @{
    'discovery-agent'      = 'Read-only Discovery-Agent: analysiert Quellen, erstellt Story-Spezifikationen'
    'refinement-agent'     = 'Refinement-Agent: klaert offene Punkte, aktualisiert Planungsartefakte'
    'ui-agent'             = 'UI-Agent: Mockup-Analyse (Discovery) und Soll-Ist-Vergleich (Verifying) per Playwright'
    'implementation-agent' = 'Implementation-Agent: arbeitet implementation-checklist.yaml ab, fuehrt MDL aus'
    'acceptance-agent'     = 'Acceptance-Agent: Modell-Inspektion + Playwright User Journeys fuer fachliche Pruefung'
}

$agentTools = @{
    'discovery-agent'      = @('Read', 'Grep', 'Glob', 'Bash')
    'refinement-agent'     = @('Read', 'Grep', 'Glob', 'Bash', 'Edit', 'Write')
    'ui-agent'             = @('Read', 'Grep', 'Glob', 'Bash', 'Write')
    'implementation-agent' = @('Read', 'Grep', 'Glob', 'Bash', 'Edit', 'Write')
    'acceptance-agent'     = @('Read', 'Grep', 'Glob', 'Bash', 'Write')
}

# ============================================================
# Platform configurations
# ============================================================

function Generate-ClaudeSkills {
    $skillsDir = Join-Path $dfcRoot 'skills'
    foreach ($f in (Get-ChildItem $skillsDir -Filter '*.md')) {
        $name = $f.BaseName
        $body = Get-Content $f.FullName -Raw -Encoding UTF8
        $desc = if ($skillDescriptions.ContainsKey($name)) { $skillDescriptions[$name] } else { Get-FirstContentLine $body }

        $frontmatter = "---`ndescription: `"$desc`"`n---"
        $outDir = Join-Path $ProjectRoot ".claude/skills/dfc/$name"
        $outPath = Join-Path $outDir "SKILL.md"
        Write-Generated -OutputPath $outPath -Content "$generatedHeader`n$frontmatter`n`n$body"
    }
}

function Generate-ClaudeAgents {
    $agentsDir = Join-Path $dfcRoot 'agents'
    if (-not (Test-Path $agentsDir)) { return }
    foreach ($f in (Get-ChildItem $agentsDir -Filter '*.md')) {
        $name = $f.BaseName
        $body = Get-Content $f.FullName -Raw -Encoding UTF8
        $desc = if ($agentDescriptions.ContainsKey($name)) { $agentDescriptions[$name] } else { Get-FirstContentLine $body }
        $tools = if ($agentTools.ContainsKey($name)) { $agentTools[$name] } else { @('Read', 'Grep', 'Glob', 'Bash') }
        $toolsYaml = ($tools | ForEach-Object { "  - $_" }) -join "`n"

        $frontmatter = "---`nmodel: sonnet`ndescription: `"$desc`"`ntools:`n$toolsYaml`n---"
        $outPath = Join-Path $ProjectRoot ".claude/agents/dfc-$name.md"
        Write-Generated -OutputPath $outPath -Content "$generatedHeader`n$frontmatter`n`n$body"
    }
}

function Generate-CopilotSkills {
    $skillsDir = Join-Path $dfcRoot 'skills'
    foreach ($f in (Get-ChildItem $skillsDir -Filter '*.md')) {
        $name = $f.BaseName
        $body = Get-Content $f.FullName -Raw -Encoding UTF8
        $desc = if ($skillDescriptions.ContainsKey($name)) { $skillDescriptions[$name] } else { Get-FirstContentLine $body }

        $frontmatter = "---`nname: `"dfc-$name`"`ndescription: `"$desc`"`n---"
        $outDir = Join-Path $ProjectRoot ".github/skills/dfc-$name"
        $outPath = Join-Path $outDir "SKILL.md"
        Write-Generated -OutputPath $outPath -Content "$generatedHeader`n$frontmatter`n`n$body"
    }
}

function Generate-CodexSkills {
    $skillsDir = Join-Path $dfcRoot 'skills'
    $outDir = Join-Path $ProjectRoot ".agents/skills/dfc"
    foreach ($f in (Get-ChildItem $skillsDir -Filter '*.md')) {
        $name = $f.BaseName
        $body = Get-Content $f.FullName -Raw -Encoding UTF8
        $outPath = Join-Path $outDir "$name.md"
        Write-Generated -OutputPath $outPath -Content "$generatedHeader`n`n$body"
    }
}

function Generate-GrokSkills {
    $skillsDir = Join-Path $dfcRoot 'skills'
    $outDir = Join-Path $ProjectRoot ".grok/skills/dfc"
    foreach ($f in (Get-ChildItem $skillsDir -Filter '*.md')) {
        $name = $f.BaseName
        $body = Get-Content $f.FullName -Raw -Encoding UTF8
        $outPath = Join-Path $outDir "$name.md"
        Write-Generated -OutputPath $outPath -Content "$generatedHeader`n`n$body"
    }
}

function Generate-OpenCodeSkills {
    $skillsDir = Join-Path $dfcRoot 'skills'
    $outDir = Join-Path $ProjectRoot ".opencode/skills/dfc"
    foreach ($f in (Get-ChildItem $skillsDir -Filter '*.md')) {
        $name = $f.BaseName
        $body = Get-Content $f.FullName -Raw -Encoding UTF8
        $outPath = Join-Path $outDir "$name.md"
        Write-Generated -OutputPath $outPath -Content "$generatedHeader`n`n$body"
    }
}

function Generate-HermesSkills {
    $skillsDir = Join-Path $dfcRoot 'skills'
    $outDir = Join-Path $ProjectRoot ".hermes/skills/dfc"
    foreach ($f in (Get-ChildItem $skillsDir -Filter '*.md')) {
        $name = $f.BaseName
        $body = Get-Content $f.FullName -Raw -Encoding UTF8
        $outPath = Join-Path $outDir "$name.md"
        Write-Generated -OutputPath $outPath -Content "$generatedHeader`n`n$body"
    }
}

# --- Main ---
Write-Host "DFC-AI Platform Skill Generator"
Write-Host "================================"
Write-Host "Source: $dfcRoot"
Write-Host ""

Write-Host "--- Claude ---"
Generate-ClaudeSkills
Generate-ClaudeAgents

Write-Host "`n--- Copilot ---"
Generate-CopilotSkills

Write-Host "`n--- Codex ---"
Generate-CodexSkills

Write-Host "`n--- Grok ---"
Generate-GrokSkills

Write-Host "`n--- OpenCode ---"
Generate-OpenCodeSkills

Write-Host "`n--- Hermes ---"
Generate-HermesSkills

Write-Host "`nDone."
