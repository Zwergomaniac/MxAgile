<#
.SYNOPSIS
    DEPRECATED compatibility wrapper. Use mxagile-setup-mercedes.ps1 instead.

.DESCRIPTION
    This script is DEPRECATED. The canonical public entry point was renamed to
    mxagile-setup-mercedes.ps1 in the MxAgile bootstrap-rename release.

    This wrapper delegates to mxagile-setup-mercedes.ps1 to preserve backward compatibility
    for existing CI/CD pipelines or documentation that still references
    install-mxagile-mercedes.ps1.

    Update your scripts to call mxagile-setup-mercedes.ps1 directly.
#>

param(
    [string]$ProjectRoot        = "",
    [string]$DistributionSource = "",
    [string]$MercedesGitUrl     = "",
    [switch]$Force
)

Write-Warning "DEPRECATED: install-mxagile-mercedes.ps1 is deprecated. Use mxagile-setup-mercedes.ps1 instead."
Write-Host "Delegating to mxagile-setup-mercedes.ps1 ..." -ForegroundColor Yellow

$setupScript = Join-Path $PSScriptRoot "mxagile-setup-mercedes.ps1"

if (-not (Test-Path -LiteralPath $setupScript)) {
    Write-Error "mxagile-setup-mercedes.ps1 not found at: $setupScript"
    exit 1
}

$passArgs = @{}
if ($ProjectRoot)        { $passArgs['ProjectRoot']        = $ProjectRoot }
if ($DistributionSource) { $passArgs['DistributionSource'] = $DistributionSource }
if ($MercedesGitUrl)     { $passArgs['MercedesGitUrl']     = $MercedesGitUrl }
if ($Force)              { $passArgs['Force']              = $true }

& $setupScript @passArgs
exit $LASTEXITCODE
