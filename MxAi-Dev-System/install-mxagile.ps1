<#
.SYNOPSIS
    DEPRECATED — use mxagile-setup.ps1 instead.

.DESCRIPTION
    Compatibility wrapper. Delegates to mxagile-setup.ps1.

    This script is retained for backward compatibility with existing automation,
    documentation links, and developer muscle memory.

    The canonical public entry point is now:

        mxagile-setup.ps1

    Semantics: SETUP = stable entry point that detects project state and performs
    the correct operation automatically (INSTALL for fresh projects, UPDATE for
    existing ones). You do not need to choose between install and update scripts.

    No installation logic lives here. There is exactly one canonical implementation
    path: mxagile-setup.ps1 -> scripts/install-core.ps1.
#>

[CmdletBinding()]
param (
    [string]$ProjectRoot = (Get-Location).Path,
    [string]$DistributionSource = "",
    [string]$DistributionRef = "main",
    [switch]$Wait
)

Write-Host ""
Write-Host "NOTE: install-mxagile.ps1 is deprecated." -ForegroundColor Yellow
Write-Host "      Use mxagile-setup.ps1 for all new and existing project setup." -ForegroundColor Yellow
Write-Host "      This wrapper delegates to mxagile-setup.ps1." -ForegroundColor DarkGray
Write-Host ""

$setupScript = Join-Path $PSScriptRoot "mxagile-setup.ps1"

if (-not (Test-Path -LiteralPath $setupScript -PathType Leaf)) {
    Write-Host "ERROR: mxagile-setup.ps1 not found at: $setupScript" -ForegroundColor Red
    exit 1
}

& $setupScript `
    -ProjectRoot        $ProjectRoot `
    -DistributionSource $DistributionSource `
    -DistributionRef    $DistributionRef `
    -Wait:$Wait

exit $LASTEXITCODE
