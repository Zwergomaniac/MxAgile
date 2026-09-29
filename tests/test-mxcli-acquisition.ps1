<#
.SYNOPSIS
    mxcli Dependency Acquisition Safety Tests

.DESCRIPTION
    Validates that the canonical mxcli acquisition path is correct, that
    the migration policy prohibits agent improvisation during acquisition
    failures/timeouts, and that migration state is not advanced when
    acquisition fails.

    Architecture under test:
    - install-mxcli.ps1 is the sole canonical acquisition path
    - mxagile-init.ps1 calls install-mxcli.ps1; uses LASTEXITCODE (not $?)
    - Migration agent must NOT copy PATH/global/developer-local mxcli
    - Tool timeout != installer failure; state MIGRATION_IN_PROGRESS preserved
    - Existing project-local mxcli reuse is installer-owned, not agent-owned

    Test groups:
    A  - project-local mxcli absent -> installer is invoked (canonical path)
    B  - policy prohibits competing install during still-running acquisition
    C  - policy/agent distinguishes tool timeout from installer failure
    D  - failed acquisition -> MIGRATION_IN_PROGRESS preserved, no mxagile_installed
    E  - arbitrary PATH mxcli is NOT silently copied into project (policy)
    F  - arbitrary developer-local mxcli is NOT silently substituted (policy/agent)
    G  - existing binary reuse checks version compatibility
    H  - existing binary: incompatible version triggers download (not accepted silently)
    I  - successful acquisition continues installation normally (exit 0 flow)
    J  - acquisition failure cannot produce mxagile_installed in policy
    K  - acquisition failure cannot produce validation_passed in policy
    L  - regression suites
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

$installMxcli   = Join-Path $ScriptDir "scripts\install-mxcli.ps1"
$mxagileInit    = Join-Path $ScriptDir "scripts\mxagile-init.ps1"
$policyFile     = Join-Path $ScriptDir ".mxagile\policies\migration-dfc-to-mxagile.md"
$agentFile      = Join-Path $ScriptDir ".mxagile\agents\migration-agent.md"

Write-Host ""
Write-Host "=== mxcli Dependency Acquisition Safety Tests ==="
Write-Host ""

Assert-True "install-mxcli.ps1 exists"  (Test-Path -LiteralPath $installMxcli)  "Not found: $installMxcli"
Assert-True "mxagile-init.ps1 exists"   (Test-Path -LiteralPath $mxagileInit)   "Not found: $mxagileInit"
Assert-True "policy file exists"        (Test-Path -LiteralPath $policyFile)    "Not found: $policyFile"
Assert-True "agent file exists"         (Test-Path -LiteralPath $agentFile)     "Not found: $agentFile"
Write-Host ""

# ===========================================================================
# GROUP A: project-local mxcli absent -> canonical installer is invoked
# ===========================================================================
Write-Host "--- A: Absent project-local mxcli triggers canonical installer ---"

Assert-Contains "A1: mxagile-init.ps1 checks for project-local mxcli before running installer" `
    $mxagileInit 'Test-Path.*MxcliPath|MxcliPath.*Test-Path'

Assert-Contains "A2: mxagile-init.ps1 calls install-mxcli.ps1 when binary absent" `
    $mxagileInit 'MxcliInstaller.*install-mxcli|install-mxcli.*MxcliInstaller'

Assert-Contains "A3: mxagile-init.ps1 uses LASTEXITCODE to detect installer failure" `
    $mxagileInit 'LASTEXITCODE'

Assert-NotContains "A4: mxagile-init.ps1 does NOT rely solely on dollar-question-mark for installer failure" `
    $mxagileInit 'if.*-not \$\?.*\).*throw|if \(\s*-not \$\?'

Assert-Contains "A5: install-mxcli.ps1 accepts TargetDir parameter" `
    $installMxcli '\$TargetDir'

Write-Host ""

# ===========================================================================
# GROUP B: Policy prohibits competing install during still-running acquisition
# ===========================================================================
Write-Host "--- B: No competing installer while acquisition is running ---"

Assert-Contains "B1: policy explicitly prohibits starting a second installer invocation" `
    $policyFile 'Starting a second.*install-mxcli|second.*install-mxcli.*running|Zweiten.*install-mxcli'

Assert-Contains "B2: agent prohibits competing installer start" `
    $agentFile 'zweiten.*install-mxcli.*Aufruf|second.*install-mxcli|Zweiten.*install-mxcli'

Write-Host ""

# ===========================================================================
# GROUP C: Policy/agent distinguishes tool timeout from installer failure
# ===========================================================================
Write-Host "--- C: Tool timeout is not equated to installer failure ---"

Assert-Contains "C1: policy has explicit table distinguishing RUNNING/SUCCEEDED/FAILED" `
    $policyFile 'RUNNING|SUCCEEDED|FAILED.*Determination'

Assert-Contains "C2: policy states tool timeout does NOT mean installer failed" `
    $policyFile 'timeout.*does NOT mean|Timeout.*not.*failed|tool.*timeout.*installer'

Assert-Contains "C3: agent states tool-timeout != installer-failure semantics" `
    $agentFile 'Tool-Timeout.*Installer-Fehler|Timeout.*KEIN.*Installer|timeout.*not.*failure'

Write-Host ""

# ===========================================================================
# GROUP D: Failed acquisition preserves MIGRATION_IN_PROGRESS
# ===========================================================================
Write-Host "--- D: Failed acquisition preserves MIGRATION_IN_PROGRESS ---"

Assert-Contains "D1: policy states last_completed_step remains dfc_artifacts_removed on acquisition failure" `
    $policyFile 'last_completed_step.*dfc_artifacts_removed'

Assert-Contains "D2: policy states state remains MIGRATION_IN_PROGRESS on acquisition failure" `
    $policyFile 'MIGRATION_IN_PROGRESS.*acquisition.*fail|State remains.*MIGRATION_IN_PROGRESS'

Assert-Contains "D3: policy instructs to report exact error to developer" `
    $policyFile 'exact error.*installer|instruct developer.*retry Phase'

Write-Host ""

# ===========================================================================
# GROUP E: PATH mxcli must NOT be silently copied into project
# ===========================================================================
Write-Host "--- E: Arbitrary PATH mxcli not copied into project ---"

Assert-Contains "E1: policy prohibits copying mxcli from PATH into project" `
    $policyFile 'Copying.*mxcli.*from PATH|PATH.*mxcli.*project|path.*mxcli.*prohibited'

Assert-Contains "E2: agent prohibits copying mxcli from PATH" `
    $agentFile 'mxcli.*aus PATH.*kopieren|PATH.*mxcli.*NICHT|PATH.*copy.*mxcli'

Write-Host ""

# ===========================================================================
# GROUP F: Developer-local mxcli must NOT be silently substituted
# ===========================================================================
Write-Host "--- F: Developer-local mxcli not silently substituted ---"

Assert-Contains "F1: policy prohibits copying global mxcli from developer paths" `
    $policyFile '\.local.*bin|global mxcli|developer-local mxcli|arbitrary path'

Assert-Contains "F2: agent prohibits copying global mxcli from developer paths" `
    $agentFile 'local.bin|globale mxcli|entwickler-lokale|beliebige.*mxcli'

Assert-Contains "F3: policy states install-mxcli.ps1 is the only canonical acquisition path" `
    $policyFile 'canonical path for acquiring|SOLE canonical path|install-mxcli.*only.*canonical'

Write-Host ""

# ===========================================================================
# GROUP G: Existing binary reuse checks version compatibility
# ===========================================================================
Write-Host "--- G: Existing binary reuse validates version ---"

Assert-Contains "G1: install-mxcli.ps1 checks local version before accepting existing binary" `
    $installMxcli 'Test-Path.*TargetExe|TargetExe.*--version|localVersion'

Assert-Contains "G2: install-mxcli.ps1 compares local vs remote semver" `
    $installMxcli 'localSemVer|remoteSemVer|remoteVersionStr'

Assert-Contains "G3: install-mxcli.ps1 accepts MinimumVersion parameter for explicit floor" `
    $installMxcli 'MinimumVersion'

Write-Host ""

# ===========================================================================
# GROUP H: Incompatible version triggers download (not silently accepted)
# ===========================================================================
Write-Host "--- H: Incompatible local version triggers download ---"

Assert-Contains "H1: install-mxcli.ps1 proceeds with download when local < remote" `
    $installMxcli 'localSemVer.*-lt.*remoteSemVer|localSemVer.*remoteSemVer.*update|update.*required'

Assert-Contains "H2: install-mxcli.ps1 proceeds with download when local version unreadable" `
    $installMxcli 'unreadable.*reinstall|reinstalling|version unreadable'

Assert-Contains "H3: install-mxcli.ps1 applies MinimumVersion check before accepting local binary" `
    $installMxcli 'localSemVer.*-ge.*minSemVer|minSemVer.*localSemVer'

Write-Host ""

# ===========================================================================
# GROUP I: Successful canonical acquisition continues installation
# ===========================================================================
Write-Host "--- I: Successful acquisition continues installation normally ---"

Assert-Contains "I1: install-mxcli.ps1 verifies downloaded file size matches API-reported size" `
    $installMxcli 'actualSize.*expectedSize|expectedSize.*actualSize|size.*mismatch'

Assert-Contains "I2: install-mxcli.ps1 copies binary to target and verifies post-install" `
    $installMxcli 'Copy-Item.*TargetExe|TargetExe.*Copy-Item'

Assert-Contains "I3: install-mxcli.ps1 runs post-install version check" `
    $installMxcli 'installedVersion|post-install.*version|installed.*--version'

Assert-Contains "I4: install-mxcli.ps1 has timeout parameters for both API and download" `
    $installMxcli 'DownloadTimeoutSec|ApiTimeoutSec'

Assert-Contains "I5: install-mxcli.ps1 has retry logic for download failures" `
    $installMxcli 'RetryCount|attempt.*maxAttempts|Retry'

Write-Host ""

# ===========================================================================
# GROUP J: Acquisition failure cannot produce mxagile_installed
# ===========================================================================
Write-Host "--- J: Acquisition failure cannot produce mxagile_installed ---"

Assert-Contains "J1: policy prohibits writing mxagile_installed on acquisition failure" `
    $policyFile 'mxagile_installed.*NICHT schreiben|Do NOT write.*mxagile_installed|not.*mxagile_installed.*fail'

Assert-Contains "J2: policy states lifecycle.yaml must exist as signal of Phase 5 success" `
    $policyFile 'lifecycle\.yaml.*signals.*Phase 5|lifecycle\.yaml.*Phase 5.*succeeded'

Write-Host ""

# ===========================================================================
# GROUP K: Acquisition failure cannot produce validation_passed
# ===========================================================================
Write-Host "--- K: Acquisition failure cannot produce validation_passed ---"

Assert-Contains "K1: policy prohibits writing validation_passed on acquisition failure" `
    $policyFile 'validation_passed.*NICHT schreiben|Do NOT write.*validation_passed|not.*validation_passed.*fail'

Assert-Contains "K2: policy prohibits writing status: complete on acquisition failure" `
    $policyFile 'status.*complete.*NICHT|Do NOT.*status.*complete|not.*complete.*fail'

Write-Host ""

# ===========================================================================
# GROUP L: Regression suites
# ===========================================================================
Write-Host "--- L: Regression suites ---"

Invoke-RegressionSuite "L1: test-migration-lifecycle-resync.ps1 passes" `
    (Join-Path $TestsDir "test-migration-lifecycle-resync.ps1")

Invoke-RegressionSuite "L2: test-migration-provenance.ps1 passes" `
    (Join-Path $TestsDir "test-migration-provenance.ps1")

Invoke-RegressionSuite "L3: test-startup-priority.ps1 passes" `
    (Join-Path $TestsDir "test-startup-priority.ps1")

Write-Host ""

# ===========================================================================
# Summary
# ===========================================================================
Write-Host "=== mxcli Acquisition Safety Test Results ==="
Write-Host "  PASS: $PassCount" -ForegroundColor Green
if ($FailCount -gt 0) {
    Write-Host "  FAIL: $FailCount" -ForegroundColor Red
    foreach ($detail in $FailDetails) {
        Write-Host "    $detail" -ForegroundColor Red
    }
    Write-Host ""
    Write-Host "TEST FAILED: mxcli acquisition safety contract violated." -ForegroundColor Red
    exit 1
} else {
    Write-Host ""
    Write-Host "TEST PASSED: mxcli acquisition safety contract met." -ForegroundColor Green
    exit 0
}
