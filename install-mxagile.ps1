<#
.SYNOPSIS
    DEPRECATED compatibility wrapper. Use mxagile-setup.ps1 directly.

.DESCRIPTION
    This script is a deprecated public bootstrap entry point that delegates to
    mxagile-setup.ps1. New invocations should call mxagile-setup.ps1 directly.

    ProvenanceFlavor "core"

.PARAMETER ProjectRoot
    Target Mendix project root. Passed through to mxagile-setup.ps1.

.PARAMETER DistributionSource
    Optional distribution source (directory or git URL). Passed through to
    mxagile-setup.ps1.

.PARAMETER DistributionRef
    Optional git ref when DistributionSource is a git URL. Passed through.

.PARAMETER Wait
    Pause for a keypress before exiting. Useful when launched via Windows Explorer
    (right-click > Run with PowerShell) so the console window stays visible.
    Direct-launch from explorer.exe is also detected automatically.
    Do NOT pass -Wait in automation or CI.
#>
[CmdletBinding()]
param(
    [string]$ProjectRoot        = "",
    [string]$DistributionSource = "",
    [string]$DistributionRef    = "main",
    [switch]$Wait
)

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Direct-launch detection (Windows only: explorer.exe or OpenWith parent)
# ---------------------------------------------------------------------------
$isDirectLaunch = $false
$_isWin = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
    [System.Runtime.InteropServices.OSPlatform]::Windows)
if ($_isWin) {
    try {
        $parentName     = (Get-Process -Id $PID -ErrorAction Stop).Parent.ProcessName
        $isDirectLaunch = $parentName -in @('explorer', 'OpenWith')
    } catch { }
}

$shouldWait = $Wait -or $isDirectLaunch

# ---------------------------------------------------------------------------
# Deprecation notice
# ---------------------------------------------------------------------------
Write-Host "[DEPRECATED] install-mxagile.ps1: use mxagile-setup.ps1 directly." -ForegroundColor Yellow

# ---------------------------------------------------------------------------
# Delegate to canonical setup script
# ---------------------------------------------------------------------------
$exitCode = 0
try {
    $setupScript = Join-Path $PSScriptRoot "mxagile-setup.ps1"
    $setupArgs   = @{}
    if ($ProjectRoot)             { $setupArgs['ProjectRoot']        = $ProjectRoot }
    if ($DistributionSource)      { $setupArgs['DistributionSource'] = $DistributionSource }
    if ($DistributionRef -ne 'main') { $setupArgs['DistributionRef'] = $DistributionRef }

    & $setupScript @setupArgs
    if ($LASTEXITCODE -ne $null) { $exitCode = $LASTEXITCODE }
} catch {
    Write-Host "install-mxagile.ps1: $($_.Exception.Message)" -ForegroundColor Red
    $exitCode = 1
}

# ---------------------------------------------------------------------------
# Interactive pause (direct-launch or explicit -Wait only)
# ---------------------------------------------------------------------------
if ($shouldWait) {
    Write-Host ""
    Write-Host "Press any key to close this window..."
    try { $null = [System.Console]::ReadKey($true) } catch { }
}

exit $exitCode
