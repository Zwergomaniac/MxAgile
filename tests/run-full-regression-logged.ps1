param([string]$LogFile = "")

if (-not $LogFile) {
    $LogFile = Join-Path $env:TEMP "mxagile-full-regression.log"
}

$mxcliCache = Join-Path $env:TEMP "mxagile-mxcli-test-cache\mxcli.exe"
if (Test-Path -LiteralPath $mxcliCache) {
    $env:MXCLI_TEST_BINARY = $mxcliCache
    Write-Host "mxcli cache: $mxcliCache"
} else {
    Write-Host "WARNING: mxcli cache not found, Tier 2 will download"
}

Write-Host "Log file: $LogFile"
Write-Host ""

$start = Get-Date
$scriptDir = Split-Path -Path $MyInvocation.MyCommand.Path -Parent
& pwsh -NoProfile -File (Join-Path $scriptDir "run-all-tests.ps1") 2>&1 | Tee-Object -FilePath $LogFile
$duration = (Get-Date) - $start

Write-Host ""
Write-Host ("Total wall-clock: " + [math]::Round($duration.TotalSeconds,1) + "s")
Write-Host "Log saved to: $LogFile"
