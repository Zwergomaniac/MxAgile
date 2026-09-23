<#
.SYNOPSIS
    DEPRECATED — use mxagile-setup-mercedes.ps1 instead.

.DESCRIPTION
    Compatibility wrapper. Delegates to mxagile-setup-mercedes.ps1.

    This script is retained for backward compatibility with existing automation,
    documentation links, and developer muscle memory.

    The canonical public entry point is now:

        mxagile-setup-mercedes.ps1

    Semantics: SETUP = stable entry point that independently detects the state of
    MxAgile Core and the Mercedes Company Layer, and performs the correct operation
    for each (INSTALL or UPDATE) without requiring the user to decide.

    No installation logic lives here. There is exactly one canonical implementation
    path: mxagile-setup-mercedes.ps1 -> scripts/install-core.ps1.
#>

[CmdletBinding()]
param (
    [string]$ProjectRoot = (Get-Location).Path,
    [string]$DistributionSource = "",
    [string]$DistributionRef = "main",
    [string]$MercedesGitUrl = "https://mercedes-benz.ghe.com/DFC-Applikationsentwicklung/MxAgile-CompanyLayer.git",
    [string]$MercedesRef = "main",
    [switch]$Wait
)

Write-Host ""
Write-Host "NOTE: install-mxagile-mercedes.ps1 is deprecated." -ForegroundColor Yellow
Write-Host "      Use mxagile-setup-mercedes.ps1 for all new and existing project setup." -ForegroundColor Yellow
Write-Host "      This wrapper delegates to mxagile-setup-mercedes.ps1." -ForegroundColor DarkGray
Write-Host ""

$setupScript = Join-Path $PSScriptRoot "mxagile-setup-mercedes.ps1"

if (-not (Test-Path -LiteralPath $setupScript -PathType Leaf)) {
    Write-Host "ERROR: mxagile-setup-mercedes.ps1 not found at: $setupScript" -ForegroundColor Red
    exit 1
}

& $setupScript `
    -ProjectRoot        $ProjectRoot `
    -DistributionSource $DistributionSource `
    -DistributionRef    $DistributionRef `
    -MercedesGitUrl     $MercedesGitUrl `
    -MercedesRef        $MercedesRef `
    -Wait:$Wait

exit $LASTEXITCODE
