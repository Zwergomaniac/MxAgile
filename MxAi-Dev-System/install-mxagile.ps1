<#
.SYNOPSIS
    DEPRECATED compatibility wrapper. Use mxagile-setup.ps1 instead.

.DESCRIPTION
    This script is DEPRECATED. The canonical public entry point was renamed to
    mxagile-setup.ps1 in the MxAgile bootstrap-rename release.

    This wrapper delegates to mxagile-setup.ps1 to preserve backward compatibility
    for existing CI/CD pipelines or documentation that still references install-mxagile.ps1.

    Update your scripts to call mxagile-setup.ps1 directly.
#>

param(
    [string]$ProjectRoot    = "",
    [string]$DistributionSource = "",
    [switch]$Force
)

Write-Warning "DEPRECATED: install-mxagile.ps1 is deprecated. Use mxagile-setup.ps1 instead."
Write-Host "Delegating to mxagile-setup.ps1 ..." -ForegroundColor Yellow

$setupScript = Join-Path $PSScriptRoot "mxagile-setup.ps1"

if (-not (Test-Path -LiteralPath $setupScript)) {
    Write-Error "mxagile-setup.ps1 not found at: $setupScript"
    exit 1
}

$passArgs = @{}
if ($ProjectRoot)        { $passArgs['ProjectRoot']        = $ProjectRoot }
if ($DistributionSource) { $passArgs['DistributionSource'] = $DistributionSource }
if ($Force)              { $passArgs['Force']              = $true }

& $setupScript @passArgs
exit $LASTEXITCODE
