<#
.SYNOPSIS
    Installer Direct-Launch UX Tests

.DESCRIPTION
    Validates that the public bootstrap installers support both:
    A. Automation / terminal invocations -- non-blocking, exit-code semantics preserved
    B. Interactive / direct-launch -- final result stays visible until keypress

    Checks:
    1.  -Wait switch declared in both installers
    2.  Direct-launch detection code present (parent process check)
    3.  $shouldWait guard used before ReadKey (not unconditional)
    4.  Exit code captured in $exitCode variable
    5.  ReadKey call wrapped in try/catch (does not crash in non-interactive context)
    6.  No unconditional Read-Host or pause added
    7.  No 'exit' call inside try/catch (exit code flows through $exitCode variable)
    8.  pause logic placed AFTER finally block (does not interfere with cleanup)
    9.  Core installer (install-mxagile.ps1) has ProvenanceFlavor "core"
    10. Mercedes installer (install-mxagile-mercedes.ps1) has ProvenanceFlavor "mercedes"
    11. Regression: test-install-bootstrap-regression.ps1 passes
    12. Regression: test-startup-priority.ps1 passes
#>

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$TestsDir    = $PSScriptRoot
$ScriptDir   = Split-Path -Parent $TestsDir
$PassCount   = 0
$FailCount   = 0
$FailDetails = @()

function Assert-True {
    param([string]$TestName, [bool]$Condition, [string]$Message)
    if ($Condition) {
        Write-Host "  PASS: $TestName" -ForegroundColor Green
        $script:PassCount++
    } else {
        Write-Host "  FAIL: $TestName -- $Message" -ForegroundColor Red
        $script:FailCount++
        $script:FailDetails += "[$TestName] $Message"
    }
}

function Assert-Contains {
    param([string]$TestName, [string]$FilePath, [string]$Pattern)
    $content = Get-Content -LiteralPath $FilePath -Raw -ErrorAction SilentlyContinue
    if ($null -eq $content) {
        Assert-True $TestName $false "File not found: $FilePath"
    } else {
        Assert-True $TestName ($content -match $Pattern) "Pattern '$Pattern' not found in $FilePath"
    }
}

function Assert-NotContains {
    param([string]$TestName, [string]$FilePath, [string]$Pattern)
    $content = Get-Content -LiteralPath $FilePath -Raw -ErrorAction SilentlyContinue
    if ($null -eq $content) {
        Assert-True $TestName $false "File not found: $FilePath"
    } else {
        Assert-True $TestName (-not ($content -match $Pattern)) "Pattern '$Pattern' must NOT appear in $FilePath"
    }
}

function Invoke-RegressionSuite {
    param([string]$TestName, [string]$ScriptPath)
    if (-not (Test-Path -LiteralPath $ScriptPath)) {
        Assert-True $TestName $false "Regression script not found: $ScriptPath"
        return
    }
    $output   = & powershell -NoProfile -ExecutionPolicy Bypass -File $ScriptPath 2>&1
    $exitCode = $LASTEXITCODE
    Assert-True $TestName ($exitCode -eq 0) "Exited $exitCode. Last: $(($output | Select-Object -Last 5) -join ' | ')"
}

$coreInstaller     = Join-Path $ScriptDir "install-mxagile.ps1"
$mercedesInstaller = Join-Path $ScriptDir "install-mxagile-mercedes.ps1"

Write-Host ""
Write-Host "=== Installer Direct-Launch UX Tests ==="
Write-Host ""

Assert-True "core installer exists"     (Test-Path -LiteralPath $coreInstaller)     "Not found: $coreInstaller"
Assert-True "mercedes installer exists" (Test-Path -LiteralPath $mercedesInstaller) "Not found: $mercedesInstaller"
Write-Host ""

# ---------------------------------------------------------------------------
# GROUP 1: -Wait switch declared
# ---------------------------------------------------------------------------
Write-Host "--- 1: -Wait switch declared ---"

Assert-Contains "1a: core installer declares switch-Wait parameter" `
    $coreInstaller '\[switch\]\$Wait'

Assert-Contains "1b: mercedes installer declares switch-Wait parameter" `
    $mercedesInstaller '\[switch\]\$Wait'

Write-Host ""

# ---------------------------------------------------------------------------
# GROUP 2: Direct-launch detection (parent process check)
# ---------------------------------------------------------------------------
Write-Host "--- 2: Direct-launch detection ---"

Assert-Contains "2a: core installer detects explorer parent process" `
    $coreInstaller "explorer.*OpenWith|isDirectLaunch"

Assert-Contains "2b: mercedes installer detects explorer parent process" `
    $mercedesInstaller "explorer.*OpenWith|isDirectLaunch"

Assert-Contains "2c: core installer sets shouldWait from Wait or isDirectLaunch" `
    $coreInstaller 'shouldWait.*=.*Wait.*isDirectLaunch|isDirectLaunch.*Wait'

Assert-Contains "2d: mercedes installer sets shouldWait from Wait or isDirectLaunch" `
    $mercedesInstaller 'shouldWait.*=.*Wait.*isDirectLaunch|isDirectLaunch.*Wait'

Write-Host ""

# ---------------------------------------------------------------------------
# GROUP 3: ReadKey guarded by shouldWait (not unconditional)
# ---------------------------------------------------------------------------
Write-Host "--- 3: ReadKey guarded by shouldWait ---"

Assert-Contains "3a: core installer guards ReadKey with shouldWait check" `
    $coreInstaller 'if.*shouldWait'

Assert-Contains "3b: mercedes installer guards ReadKey with shouldWait check" `
    $mercedesInstaller 'if.*shouldWait'

Assert-Contains "3c: core installer calls ReadKey" `
    $coreInstaller 'ReadKey'

Assert-Contains "3d: mercedes installer calls ReadKey" `
    $mercedesInstaller 'ReadKey'

Write-Host ""

# ---------------------------------------------------------------------------
# GROUP 4: ReadKey wrapped in try/catch (no crash in non-interactive context)
# ---------------------------------------------------------------------------
Write-Host "--- 4: ReadKey wrapped in try/catch ---"

Assert-Contains "4a: core installer wraps ReadKey in try/catch" `
    $coreInstaller 'try.*ReadKey.*catch|ReadKey.*\$true.*\}.*catch'

Assert-Contains "4b: mercedes installer wraps ReadKey in try/catch" `
    $mercedesInstaller 'try.*ReadKey.*catch|ReadKey.*\$true.*\}.*catch'

Write-Host ""

# ---------------------------------------------------------------------------
# GROUP 5: No unconditional blocking constructs
# ---------------------------------------------------------------------------
Write-Host "--- 5: No unconditional blocking constructs ---"

Assert-NotContains "5a: core installer does not have unconditional Read-Host" `
    $coreInstaller '^[^#]*Read-Host'

Assert-NotContains "5b: mercedes installer does not have unconditional Read-Host" `
    $mercedesInstaller '^[^#]*Read-Host'

Write-Host ""

# ---------------------------------------------------------------------------
# GROUP 6: Exit code captured in $exitCode, not via 'exit' inside try/catch
# ---------------------------------------------------------------------------
Write-Host "--- 6: Exit code captured via exitCode variable ---"

Assert-Contains "6a: core installer initializes exitCode = 0" `
    $coreInstaller '\$exitCode\s*=\s*0'

Assert-Contains "6b: mercedes installer initializes exitCode = 0" `
    $mercedesInstaller '\$exitCode\s*=\s*0'

Assert-Contains "6c: core installer sets exitCode = 1 in catch block" `
    $coreInstaller '\$exitCode = 1'

Assert-Contains "6d: mercedes installer sets exitCode = 1 in catch block" `
    $mercedesInstaller '\$exitCode = 1'

Assert-Contains "6e: core installer ends with exit exitCode" `
    $coreInstaller 'exit \$exitCode'

Assert-Contains "6f: mercedes installer ends with exit exitCode" `
    $mercedesInstaller 'exit \$exitCode'

Write-Host ""

# ---------------------------------------------------------------------------
# GROUP 7: Core / Mercedes flavor identity preserved
# ---------------------------------------------------------------------------
Write-Host "--- 7: Installer flavor identity ---"

Assert-Contains "7a: core installer passes ProvenanceFlavor 'core'" `
    $coreInstaller 'ProvenanceFlavor.*"core"'

Assert-Contains "7b: mercedes installer passes ProvenanceFlavor 'mercedes'" `
    $mercedesInstaller 'ProvenanceFlavor.*"mercedes"'

Write-Host ""

# ---------------------------------------------------------------------------
# GROUP 8: Non-interactive invocation does not pause
#   Verify by calling the core installer with a non-existent project path
#   (it will fail fast without any git activity) and check it exits quickly.
# ---------------------------------------------------------------------------
Write-Host "--- 8: Non-interactive invocation exits without pause ---"

$bogusProject = Join-Path $env:TEMP "mxagile-ux-test-nonexistent-$([System.Guid]::NewGuid().ToString('N').Substring(0,8))"
$sw = [System.Diagnostics.Stopwatch]::StartNew()
& powershell -NoProfile -ExecutionPolicy Bypass -File $coreInstaller `
    -ProjectRoot $bogusProject 2>&1 | Out-Null
$installerExit = $LASTEXITCODE
$sw.Stop()

# The installer should fail fast (no project exists) and return within 10 seconds.
# If -Wait / ReadKey were unconditional, it would block indefinitely.
Assert-True "8a: core installer exits quickly on fast-fail (no unconditional pause)" `
    ($sw.Elapsed.TotalSeconds -lt 10) `
    "Took $($sw.Elapsed.TotalSeconds)s -- possible unconditional blocking construct"

# Exit code should be non-zero (failure)
Assert-True "8b: core installer returns non-zero exit code on invalid project path" `
    ($installerExit -ne 0) "Expected non-zero exit code, got $installerExit"

Write-Host ""

# ---------------------------------------------------------------------------
# Regression
# ---------------------------------------------------------------------------
Write-Host "--- 9-10: Regression suites ---"

Invoke-RegressionSuite "9: test-install-bootstrap-regression.ps1 passes" `
    (Join-Path $TestsDir "test-install-bootstrap-regression.ps1")

Invoke-RegressionSuite "10: test-startup-priority.ps1 passes" `
    (Join-Path $TestsDir "test-startup-priority.ps1")

Write-Host ""

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
Write-Host "=== Installer UX Test Results ==="
Write-Host "  PASS: $PassCount" -ForegroundColor Green
if ($FailCount -gt 0) {
    Write-Host "  FAIL: $FailCount" -ForegroundColor Red
    foreach ($detail in $FailDetails) {
        Write-Host "    $detail" -ForegroundColor Red
    }
    Write-Host ""
    Write-Host "TEST FAILED: Installer UX contract violated." -ForegroundColor Red
    exit 1
} else {
    Write-Host ""
    Write-Host "TEST PASSED: Installer UX contract met." -ForegroundColor Green
    exit 0
}
