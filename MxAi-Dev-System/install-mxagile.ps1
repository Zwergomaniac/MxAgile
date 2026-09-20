<#
.SYNOPSIS
Installs the generic MxAgile framework into a Mendix project.

.DESCRIPTION
The target project defaults to the current working directory.
Installer-owned scripts are always resolved relative to this bootstrap file.

The target project must contain exactly one root-level .mpr file.
#>

[CmdletBinding()]
param (
    [string]$ProjectRoot = (Get-Location).Path
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

try {
    # -----------------------------------------------------------------
    # Resolve target project
    # -----------------------------------------------------------------

    if (-not (Test-Path -LiteralPath $ProjectRoot -PathType Container)) {
        throw "Project root does not exist: $ProjectRoot"
    }

    $ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)

    # -----------------------------------------------------------------
    # Safety preflight
    # -----------------------------------------------------------------

    $mprFiles = @(
        Get-ChildItem `
            -LiteralPath $ProjectRoot `
            -File `
            -Filter "*.mpr"
    )

    if ($mprFiles.Count -eq 0) {
        throw "No root-level .mpr file found in project root: $ProjectRoot"
    }

    if ($mprFiles.Count -gt 1) {
        $names = ($mprFiles | ForEach-Object { $_.Name }) -join ", "
        throw "Multiple root-level .mpr files found in '$ProjectRoot': $names"
    }

    Write-Host "Safety Preflight passed: Single .mpr file detected."

    # -----------------------------------------------------------------
    # Resolve installer-owned scripts
    # -----------------------------------------------------------------

    $InitScript = Join-Path $PSScriptRoot "scripts\mxagile-init.ps1"
    $AgentSetupScript = Join-Path $PSScriptRoot "scripts\setup-agent-system.ps1"

    foreach ($script in @($InitScript, $AgentSetupScript)) {
        if (-not (Test-Path -LiteralPath $script -PathType Leaf)) {
            throw "Required installer script not found: $script"
        }
    }

    # -----------------------------------------------------------------
    # Initialize MxAgile
    # -----------------------------------------------------------------

    Write-Host "Initializing MxAgile framework..."

    try {
        & $InitScript -ProjectRoot $ProjectRoot

        if (-not $?) {
            throw "mxagile-init.ps1 returned an unsuccessful PowerShell status."
        }
    }
    catch {
        throw "MxAgile framework initialization failed: $($_.Exception.Message)"
    }

    # -----------------------------------------------------------------
    # Setup agent system
    # -----------------------------------------------------------------

    Write-Host "Setting up Agent System..."

    try {
        & $AgentSetupScript -ProjectRoot $ProjectRoot

        if (-not $?) {
            throw "setup-agent-system.ps1 returned an unsuccessful PowerShell status."
        }
    }
    catch {
        throw "Agent system setup failed: $($_.Exception.Message)"
    }

    # -----------------------------------------------------------------
    # Final validation
    # -----------------------------------------------------------------

    $MxAgilePath = Join-Path $ProjectRoot ".mxagile"

    if (-not (Test-Path -LiteralPath $MxAgilePath -PathType Container)) {
        throw "MxAgile initialization completed without creating '$MxAgilePath'."
    }

    Write-Host ""
    Write-Host "Generic MxAgile installation complete." -ForegroundColor Green
    exit 0
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}