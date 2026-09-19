<#
.SYNOPSIS
    Single entry point for setting up the complete agent system.

.DESCRIPTION
    Runs both agent setup scripts in the correct order:
    1. apply-project-agent-instructions.ps1 — distributes AGENT.md to platform entry points
    2. generate-dfc-platform-skills.ps1 — generates platform skills/agents from .MxAgile/

    Each script can also be run independently.

.PARAMETER ProjectRoot
    Root directory of the Mendix project. Defaults to the script's parent's parent.

.PARAMETER DryRun
    Pass through to generate-dfc-platform-skills.ps1 — show what would be generated.
#>
[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path -Parent (Split-Path -Parent $PSCommandPath)),
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$scriptsDir = Split-Path -Parent $PSCommandPath

Write-Host "=== Agent System Setup ==="
Write-Host "Project: $ProjectRoot"
Write-Host ""

# Step 1: Distribute AGENT.md to platform entry points
$applyScript = Join-Path $scriptsDir 'apply-project-agent-instructions.ps1'
if (Test-Path $applyScript) {
    Write-Host "--- Step 1: Distributing AGENT.md ---"
    & $applyScript
    Write-Host ""
} else {
    Write-Warning "apply-project-agent-instructions.ps1 not found — skipping"
}

# Step 2: Generate DFC platform skills and agents
$generateScript = Join-Path $scriptsDir 'generate-dfc-platform-skills.ps1'
if (Test-Path $generateScript) {
    Write-Host "--- Step 2: Generating DFC platform skills ---"
    $params = @{ ProjectRoot = $ProjectRoot }
    if ($DryRun) { $params.DryRun = $true }
    & $generateScript @params
    Write-Host ""
} else {
    Write-Warning "generate-dfc-platform-skills.ps1 not found — skipping"
}

Write-Host "=== Setup complete ==="

