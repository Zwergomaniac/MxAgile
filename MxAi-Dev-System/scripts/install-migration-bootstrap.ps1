<#
.SYNOPSIS
    Installs the minimal MxAgile migration bootstrap into a legacy DFC-AI project.

.DESCRIPTION
    When a DFC-AI project is detected, this script installs ONLY the minimum capability
    needed to safely run the DFC-AI -> MxAgile migration:

        .mxagile/migration/README.md   -- migration state marker + instructions
        .mxagile/migration/policy.md   -- migration policy (canonical copy)
        .claude/agents/mxagile-migration-agent.md  -- migration agent (Claude platform)

    Does NOT install:
        - .mxagile/lifecycle.yaml (the sentinel for "MxAgile fully installed")
        - .mxagile/orchestrator.md or any full lifecycle files
        - Any mxagile-* skill files
        - Any managed block injections (apply-project-agent-instructions.ps1)

    Idempotent: safe to run multiple times. Existing bootstrap files are refreshed
    (updated) on rerun. DFC-AI artifacts are never touched.

.PARAMETER ProjectRoot
    Root directory of the target Mendix project.

.PARAMETER CanonicalSource
    Path to the MxAgile framework .mxagile/ directory.
    Defaults to <script-dir>/../.mxagile
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ProjectRoot,

    [string]$CanonicalSource,

    [string]$ProvenanceFlavor         = "",
    [string]$ProvenanceCoreSource     = "",
    [string]$ProvenanceCoreSourceType = "",
    [string]$ProvenanceCoreRef        = "",
    [string]$ProvenanceCoreSubdir     = "",
    [string]$CompanyLayerSource       = "",
    [string]$CompanyLayerSourceType   = "",
    [string]$CompanyLayerRef          = ""
)

$ErrorActionPreference = 'Stop'

$ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)

if (-not (Test-Path -LiteralPath $ProjectRoot -PathType Container)) {
    throw "ProjectRoot not found: $ProjectRoot"
}

if (-not $CanonicalSource) {
    $CanonicalSource = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.mxagile"))
}

if (-not (Test-Path -LiteralPath $CanonicalSource -PathType Container)) {
    throw "Canonical .mxagile/ source not found at: $CanonicalSource"
}

$Utf8WithoutBom = [System.Text.UTF8Encoding]::new($false)

# ---------------------------------------------------------------------------
# 1. Create .mxagile/migration/ with policy and README
# ---------------------------------------------------------------------------
$migrationDir = Join-Path $ProjectRoot ".mxagile\migration"
if (-not (Test-Path -LiteralPath $migrationDir -PathType Container)) {
    New-Item -ItemType Directory -Path $migrationDir -Force | Out-Null
}

# Copy migration policy from canonical source
$sourcePolicyPath = Join-Path $CanonicalSource "policies\migration-dfc-to-mxagile.md"
if (-not (Test-Path -LiteralPath $sourcePolicyPath -PathType Leaf)) {
    throw "Migration policy not found in canonical source: $sourcePolicyPath"
}
$destPolicyPath = Join-Path $migrationDir "policy.md"
Copy-Item -LiteralPath $sourcePolicyPath -Destination $destPolicyPath -Force
Write-Host "  Installed: .mxagile/migration/policy.md"

# Write bootstrap README / state marker
$readmeContent = @"
# MxAgile Migration Bootstrap

This directory marks a DFC-AI project that has received the MxAgile migration bootstrap.

## State

- **Status**: MIGRATION_BOOTSTRAPPED — migration not yet complete
- **Sentinel**: `.mxagile/lifecycle.yaml` is absent until migration completes successfully

## To migrate

Start a new agent session in this project directory and instruct:

    Migrate this existing DFC-AI project to MxAgile according to
    the migration instructions in .mxagile/migration/

The migration agent (`mxagile-migration-agent`) will guide the process.

## What is safe before migration completes

Only this `migration/` directory and `.claude/agents/mxagile-migration-agent.md`
have been written. No other MxAgile files have been installed.

DFC-AI artifacts are untouched.
"@

$readmePath = Join-Path $migrationDir "README.md"
[System.IO.File]::WriteAllText($readmePath, $readmeContent, $Utf8WithoutBom)
Write-Host "  Installed: .mxagile/migration/README.md"

# ---------------------------------------------------------------------------
# 2. Install migration agent platform file for Claude
# ---------------------------------------------------------------------------
$claudeAgentsDir = Join-Path $ProjectRoot ".claude\agents"
if (-not (Test-Path -LiteralPath $claudeAgentsDir -PathType Container)) {
    New-Item -ItemType Directory -Path $claudeAgentsDir -Force | Out-Null
}

$sourceAgentPath = Join-Path $CanonicalSource "agents\migration-agent.md"
if (-not (Test-Path -LiteralPath $sourceAgentPath -PathType Leaf)) {
    throw "Migration agent source not found: $sourceAgentPath"
}
$agentBody = Get-Content -LiteralPath $sourceAgentPath -Raw -Encoding UTF8

$agentFrontmatter = @"
---
model: sonnet
description: "DFC-AI -> MxAgile Migration Agent: inventories legacy DFC artifacts, preserves project knowledge, establishes MxAgile brownfield baseline"
tools:
  - Read
  - Grep
  - Glob
  - Bash
  - Edit
  - Write
---
"@

$migrationAgentPath = Join-Path $claudeAgentsDir "mxagile-migration-agent.md"
[System.IO.File]::WriteAllText(
    $migrationAgentPath,
    "$agentFrontmatter`n`n$agentBody",
    $Utf8WithoutBom
)
Write-Host "  Installed: .claude/agents/mxagile-migration-agent.md"

# ---------------------------------------------------------------------------
# 3. Write .mxagile/migration/provenance.yaml
# ---------------------------------------------------------------------------
$provFlavor     = if ([string]::IsNullOrWhiteSpace($ProvenanceFlavor))         { "core" }  else { $ProvenanceFlavor }
$provSourceType = if ([string]::IsNullOrWhiteSpace($ProvenanceCoreSourceType)) { "local" } else { $ProvenanceCoreSourceType }
$recordedAt     = [System.DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")

$yamlLines = [System.Collections.Generic.List[string]]::new()
$yamlLines.Add("# MxAgile installation provenance")
$yamlLines.Add("# Written by the migration bootstrap. Read by the migration agent to reacquire")
$yamlLines.Add("# the correct MxAgile distribution during Phase 5 (MxAgile installation).")
$yamlLines.Add("# Do NOT edit manually.")
$yamlLines.Add("")
$yamlLines.Add("installation:")
$yamlLines.Add("  flavor: " + $provFlavor)
$yamlLines.Add("  recorded_at: `"" + $recordedAt + "`"")
$yamlLines.Add("")
$yamlLines.Add("  core:")
$yamlLines.Add("    source: `"" + $ProvenanceCoreSource + "`"")
$yamlLines.Add("    source_type: " + $provSourceType)
if (-not [string]::IsNullOrWhiteSpace($ProvenanceCoreRef)) {
    $yamlLines.Add("    ref: " + $ProvenanceCoreRef)
}
if (-not [string]::IsNullOrWhiteSpace($ProvenanceCoreSubdir)) {
    $yamlLines.Add("    subdirectory: " + $ProvenanceCoreSubdir)
}
if ($provFlavor -eq "mercedes" -and -not [string]::IsNullOrWhiteSpace($CompanyLayerSource)) {
    $yamlLines.Add("")
    $yamlLines.Add("  company_layer:")
    $yamlLines.Add("    source: `"" + $CompanyLayerSource + "`"")
    $yamlLines.Add("    source_type: " + $CompanyLayerSourceType)
    if (-not [string]::IsNullOrWhiteSpace($CompanyLayerRef)) {
        $yamlLines.Add("    ref: " + $CompanyLayerRef)
    }
}

$provenanceContent = ($yamlLines -join "`n") + "`n"
$provenancePath = Join-Path $migrationDir "provenance.yaml"
[System.IO.File]::WriteAllText($provenancePath, $provenanceContent, $Utf8WithoutBom)
Write-Host "  Installed: .mxagile/migration/provenance.yaml"

Write-Host ""
Write-Host "Migration bootstrap installed."
