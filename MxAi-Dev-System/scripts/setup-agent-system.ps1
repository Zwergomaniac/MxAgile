<#
.SYNOPSIS
Sets up all MxAgile agent instructions and platform projections.

.DESCRIPTION
Runs:
1. apply-project-agent-instructions.ps1
2. generate-mxagile-platform-skills.ps1

All project output is written relative to the explicitly supplied ProjectRoot.
#>

[CmdletBinding()]
param (
    [string]$ProjectRoot = (Get-Location).Path,

    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

if (-not (Test-Path -LiteralPath $ProjectRoot -PathType Container)) {
    throw "Project root does not exist: $ProjectRoot"
}

$ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)

$ApplyScript = Join-Path $PSScriptRoot "apply-project-agent-instructions.ps1"
$GenerateScript = Join-Path $PSScriptRoot "generate-mxagile-platform-skills.ps1"

Write-Host "=== Agent System Setup ==="
Write-Host "Project: $ProjectRoot"
Write-Host ""

# ---------------------------------------------------------------------
# Step 1
# ---------------------------------------------------------------------

if (-not (Test-Path -LiteralPath $ApplyScript -PathType Leaf)) {
    throw "apply-project-agent-instructions.ps1 not found: $ApplyScript"
}

Write-Host "--- Step 1: Distributing AGENT.md ---"

try {
    & $ApplyScript -ProjectRoot $ProjectRoot

    if (-not $?) {
        throw "apply-project-agent-instructions.ps1 returned unsuccessful status."
    }
}
catch {
    throw "Step 1 failed: $($_.Exception.Message)"
}

Write-Host ""

# ---------------------------------------------------------------------
# Step 2
# ---------------------------------------------------------------------

if (-not (Test-Path -LiteralPath $GenerateScript -PathType Leaf)) {
    throw "generate-mxagile-platform-skills.ps1 not found: $GenerateScript"
}

Write-Host "--- Step 2: Generating MxAgile platform skills ---"

try {
    if ($DryRun) {
        & $GenerateScript `
            -ProjectRoot $ProjectRoot `
            -DryRun
    }
    else {
        & $GenerateScript `
            -ProjectRoot $ProjectRoot
    }

    if (-not $?) {
        throw "generate-mxagile-platform-skills.ps1 returned unsuccessful status."
    }
}
catch {
    throw "Step 2 failed: $($_.Exception.Message)"
}

Write-Host ""
Write-Host "=== Agent System Setup complete ===" -ForegroundColor Green