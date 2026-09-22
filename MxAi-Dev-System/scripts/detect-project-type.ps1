<#
.SYNOPSIS
    Detects the AI framework installation type of a Mendix project.

.DESCRIPTION
    Classifies the target project as one of:
        CLEAN_PROJECT           - No AI framework installed
        EXISTING_MXAGILE_PROJECT - MxAgile already installed
        LEGACY_DFC_PROJECT      - DFC-AI installation detected
        AMBIGUOUS               - Both DFC-AI and MxAgile markers found

    Primary detection markers:
        MxAgile:  .mxagile/lifecycle.yaml
        DFC-AI:   .dfc-ai/version.yaml  (primary)
                  scripts/generate-dfc-platform-skills.ps1  (secondary)
                  .claude/agents/dfc-*.md  (secondary)

    Outputs a JSON object with Classification and Evidence fields.
    Exit code: 0 = detection succeeded; 1 = ProjectRoot not found.

.PARAMETER ProjectRoot
    Root directory of the Mendix project. Defaults to current directory.
#>

[CmdletBinding()]
param(
    [string]$ProjectRoot = (Get-Location).Path
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $ProjectRoot -PathType Container)) {
    Write-Error "ProjectRoot not found: $ProjectRoot"
    exit 1
}

$ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)

# ---------------------------------------------------------------------------
# MxAgile markers
# ---------------------------------------------------------------------------
$mxAgileEvidence = @()

if (Test-Path -LiteralPath (Join-Path $ProjectRoot ".mxagile\lifecycle.yaml") -PathType Leaf) {
    $mxAgileEvidence += ".mxagile/lifecycle.yaml"
}

if (Test-Path -LiteralPath (Join-Path $ProjectRoot ".mxagile") -PathType Container) {
    $managedAgentsDir = Join-Path $ProjectRoot ".claude\agents"
    if (Test-Path -LiteralPath $managedAgentsDir -PathType Container) {
        $mxagileAgents = @(Get-ChildItem -LiteralPath $managedAgentsDir -Filter "mxagile-*.md" -File -ErrorAction SilentlyContinue)
        if ($mxagileAgents.Count -gt 0) {
            $mxAgileEvidence += ".claude/agents/mxagile-*.md ($($mxagileAgents.Count) files)"
        }
    }
}

# ---------------------------------------------------------------------------
# DFC-AI markers
# ---------------------------------------------------------------------------
$dfcEvidence = @()

# Primary: .dfc-ai/version.yaml
$dfcVersionPath = Join-Path $ProjectRoot ".dfc-ai\version.yaml"
if (Test-Path -LiteralPath $dfcVersionPath -PathType Leaf) {
    $dfcEvidence += ".dfc-ai/version.yaml (primary)"
} elseif (Test-Path -LiteralPath (Join-Path $ProjectRoot ".dfc-ai") -PathType Container) {
    $dfcEvidence += ".dfc-ai/ directory (primary)"
}

# Secondary: DFC generation script
$dfcGenScript = Join-Path $ProjectRoot "scripts\generate-dfc-platform-skills.ps1"
if (Test-Path -LiteralPath $dfcGenScript -PathType Leaf) {
    $dfcEvidence += "scripts/generate-dfc-platform-skills.ps1"
}

# Secondary: dfc- prefixed agent files
$claudeAgentsDir = Join-Path $ProjectRoot ".claude\agents"
if (Test-Path -LiteralPath $claudeAgentsDir -PathType Container) {
    $dfcAgents = @(Get-ChildItem -LiteralPath $claudeAgentsDir -Filter "dfc-*.md" -File -ErrorAction SilentlyContinue)
    if ($dfcAgents.Count -gt 0) {
        $dfcEvidence += ".claude/agents/dfc-*.md ($($dfcAgents.Count) files)"
    }
}

# Secondary: old injection markers in AGENTS.md
$agentsMdPath = Join-Path $ProjectRoot "AGENTS.md"
if (Test-Path -LiteralPath $agentsMdPath -PathType Leaf) {
    $agentsMdContent = Get-Content -LiteralPath $agentsMdPath -Raw -ErrorAction SilentlyContinue
    if ($agentsMdContent -match '<!-- BEGIN PROJECT AGENT INSTRUCTIONS -->') {
        $dfcEvidence += "AGENTS.md contains legacy DFC-AI injection markers"
    }
}

# ---------------------------------------------------------------------------
# Classification
# ---------------------------------------------------------------------------
$hasMxAgile = $mxAgileEvidence.Count -gt 0 -and (@($mxAgileEvidence | Where-Object { $_ -match 'lifecycle\.yaml' })).Count -gt 0
$hasDfc     = $dfcEvidence.Count -gt 0 -and (@($dfcEvidence | Where-Object { $_ -match '\.dfc-ai' })).Count -gt 0

$classification = if ($hasMxAgile -and $hasDfc) {
    "AMBIGUOUS"
} elseif ($hasMxAgile) {
    "EXISTING_MXAGILE_PROJECT"
} elseif ($hasDfc) {
    "LEGACY_DFC_PROJECT"
} else {
    "CLEAN_PROJECT"
}

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------
$result = [ordered]@{
    Classification  = $classification
    DfcEvidence     = $dfcEvidence
    MxAgileEvidence = $mxAgileEvidence
    ProjectRoot     = $ProjectRoot
}

$result | ConvertTo-Json -Depth 4

exit 0
