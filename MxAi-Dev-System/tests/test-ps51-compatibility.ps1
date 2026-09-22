<#
.SYNOPSIS
    PS5.1 Compatibility and Phase-5 Safety Tests

.DESCRIPTION
    Validates that production PowerShell scripts are compatible with Windows
    PowerShell 5.1, that install-core.ps1 Phase-5 failure remains safe, and that
    the migration agent cannot manually reconstruct a failed canonical installation.

    Architecture under test:
    - Production scripts in scripts/ must execute under powershell.exe (PS5.1)
    - Join-Path with 3+ positional args fails in PS5.1; must use nested form
    - install-core.ps1 failure -> MIGRATION_IN_PROGRESS -> fix -> retry Phase 5
    - Phase-5 retry is idempotent; no manual cleanup required
    - Agent must not infer Phase 5 complete from mxcli.exe presence alone

    Test groups:
    A - No 3+-segment positional Join-Path in production scripts
    B - install-core.ps1 path construction is PS5.1 compatible
    C - Core installation path PS5.1 compatible
    D - Mercedes (Company Layer) installation path PS5.1 compatible
    E - Migration Phase 5 resume path PS5.1 compatible
    F - Canonical .mxagile payload resolution PS5.1 compatible
    G - Company Layer path handling PS5.1 compatible
    H - Partial Phase-5 failure remains MIGRATION_IN_PROGRESS
    I - Phase-5 retry idempotency documented
    J - Agent prohibits manual reconstruction after installer failure
    K-P - Regression suites
#>

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$TestsDir  = $PSScriptRoot
$ScriptDir = Split-Path -Parent $TestsDir
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
        Assert-True $TestName (-not ($content -match $Pattern)) "Prohibited pattern '$Pattern' found in $FilePath"
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

# Assert that a script has no 3+-positional-arg Join-Path calls.
# Line-by-line matching avoids false positives from raw multiline content.
# Pattern matches: Join-Path $variable "string1" "string2" (the PS5.1-failing form)
# Does NOT match: Join-Path (Join-Path ...) "string" (correctly nested form)
function Assert-NoMultiSegJoinPath {
    param([string]$TestName, [string]$FilePath)
    if (-not (Test-Path -LiteralPath $FilePath)) {
        Assert-True $TestName $false "File not found: $FilePath"
        return
    }
    $precisePattern = 'Join-Path\s+\$\w+\s+"[^"]*"\s+"[^"]*"'
    $hits = @(Get-Content -LiteralPath $FilePath | Where-Object { $_ -match $precisePattern })
    if ($hits.Count -gt 0) {
        Assert-True $TestName $false "Found $($hits.Count) 3+-arg Join-Path line(s): $($hits[0].Trim())"
    } else {
        Assert-True $TestName $true ""
    }
}

# Production scripts to audit for PS5.1 compatibility
$productionScripts = @(
    "install-core.ps1"
    "mxagile-init.ps1"
    "install-mxcli.ps1"
    "install-migration-bootstrap.ps1"
    "setup-agent-system.ps1"
    "detect-project-type.ps1"
    "fetch-layer.ps1"
    "apply-project-agent-instructions.ps1"
    "generate-mxagile-platform-skills.ps1"
)

$installCore      = Join-Path $ScriptDir "scripts\install-core.ps1"
$policyFile       = Join-Path $ScriptDir ".mxagile\policies\migration-dfc-to-mxagile.md"
$agentFile        = Join-Path $ScriptDir ".mxagile\agents\migration-agent.md"

Write-Host ""
Write-Host "=== PS5.1 Compatibility and Phase-5 Safety Tests ==="
Write-Host ""

Assert-True "install-core.ps1 exists"  (Test-Path -LiteralPath $installCore)  "Not found: $installCore"
Assert-True "policy file exists"       (Test-Path -LiteralPath $policyFile)   "Not found: $policyFile"
Assert-True "agent file exists"        (Test-Path -LiteralPath $agentFile)    "Not found: $agentFile"
Write-Host ""

# ===========================================================================
# GROUP A: No 3+-segment positional Join-Path in production scripts
# ===========================================================================
Write-Host "--- A: No PS5.1-incompatible Join-Path in production scripts ---"

foreach ($scriptName in $productionScripts) {
    $scriptPath = Join-Path $ScriptDir "scripts\$scriptName"
    if (-not (Test-Path -LiteralPath $scriptPath)) {
        Write-Host "  SKIP: A: $scriptName (not found)" -ForegroundColor DarkGray
        continue
    }
    Assert-NoMultiSegJoinPath "A: $scriptName has no 3+-positional Join-Path" $scriptPath
}

Write-Host ""

# ===========================================================================
# GROUP B: install-core.ps1 canonical source path uses nested Join-Path
# ===========================================================================
Write-Host "--- B: install-core.ps1 PS5.1-compatible path construction ---"

Assert-Contains "B1: canonicalSource uses nested Join-Path (not 3-arg form)" `
    $installCore 'Join-Path\s*\(Join-Path\s+\$PSScriptRoot\s+"\.\."\)\s+"\.mxagile"'

Assert-NotContains "B2: canonicalSource does NOT use 3-arg Join-Path" `
    $installCore 'Join-Path\s+\$PSScriptRoot\s+"\.\."\s+"\.mxagile"'

# Runtime: confirm powershell.exe (PS5.1) can evaluate the path expression without error
$ps51PathTest = powershell -NoProfile -ExecutionPolicy Bypass -Command @"
`$result = try {
    `$PSScriptRoot = '$ScriptDir\scripts'
    Join-Path (Join-Path `$PSScriptRoot '..') '.mxagile'
    'OK'
} catch { "ERROR: `$_" }
Write-Output `$result
"@ 2>&1
$ps51PathTestExit = $LASTEXITCODE
Assert-True "B3: PS5.1 can evaluate nested Join-Path for canonicalSource" `
    ($ps51PathTestExit -eq 0 -and ($ps51PathTest -join '') -notmatch '^ERROR') `
    "PS5.1 evaluation failed: $($ps51PathTest -join ' ')"

Write-Host ""

# ===========================================================================
# GROUP C: Core installation path PS5.1 compatible
# ===========================================================================
Write-Host "--- C: Core installation path PS5.1 compatible ---"

Assert-NotContains "C1: install-core.ps1 step-1a path (mxagile-init) uses 2-arg Join-Path" `
    $installCore 'Join-Path\s+\$PSScriptRoot\s+"mxagile-init\.ps1"\s+[\$"]'

Assert-NotContains "C2: install-core.ps1 step-1b path (mxcli) uses 2-arg Join-Path" `
    $installCore 'Join-Path\s+\$ProjectRoot\s+"mxcli\.exe"\s+[\$"]'

Assert-Contains "C3: install-core.ps1 PS5.1 nesting-bug comment present" `
    $installCore 'PS5\.1 nesting-bug'

Write-Host ""

# ===========================================================================
# GROUP D: Mercedes (Company Layer) installation path PS5.1 compatible
# ===========================================================================
Write-Host "--- D: Mercedes Company Layer installation path PS5.1 compatible ---"

Assert-NoMultiSegJoinPath "D1: install-core.ps1 Company Layer section has no 3+-arg Join-Path" `
    $installCore

Assert-Contains "D2: install-core.ps1 Company Layer destination uses 2-arg Join-Path" `
    $installCore 'Join-Path\s+\$ProjectRoot\s+"\.mxagile.layers'

Write-Host ""

# ===========================================================================
# GROUP E: Migration Phase-5 resume path PS5.1 compatible
# ===========================================================================
Write-Host "--- E: Migration Phase-5 resume path PS5.1 compatible ---"

$installMigration = Join-Path $ScriptDir "scripts\install-migration-bootstrap.ps1"
if (Test-Path -LiteralPath $installMigration) {
    Assert-NoMultiSegJoinPath "E1: install-migration-bootstrap.ps1 has no 3+-arg Join-Path" `
        $installMigration
} else {
    Write-Host "  SKIP: E1: install-migration-bootstrap.ps1 not found" -ForegroundColor DarkGray
}

Assert-Contains "E2: policy documents Phase-5 retry is idempotent after partial failure" `
    $policyFile 'Phase 5 retry is safe|retry.*idempotent|idempotent.*retry'

Assert-Contains "E3: policy states last_completed_step remains dfc_artifacts_removed after install-core failure" `
    $policyFile 'last_completed_step.*dfc_artifacts_removed'

Write-Host ""

# ===========================================================================
# GROUP F: Canonical .mxagile payload resolution PS5.1 compatible
# ===========================================================================
Write-Host "--- F: Canonical .mxagile payload resolution PS5.1 compatible ---"

Assert-Contains "F1: install-core.ps1 resolves canonicalSource with GetFullPath + nested Join-Path" `
    $installCore 'GetFullPath.*Join-Path.*Join-Path'

Assert-NotContains "F2: install-core.ps1 does not use 3-arg Join-Path for canonicalSource" `
    $installCore 'Join-Path\s+\$PSScriptRoot\s+"\.\."\s+"\.mxagile"'

Assert-Contains "F3: policy documents PS5.1 runtime contract" `
    $policyFile 'Windows PowerShell 5\.1|PS5\.1.*minimum|minimum.*PS5\.1'

Assert-Contains "F4: policy documents nested Join-Path as canonical PS5.1 alternative" `
    $policyFile 'nested.*Join-Path|Join-Path.*nested'

Write-Host ""

# ===========================================================================
# GROUP G: Company Layer path handling PS5.1 compatible
# ===========================================================================
Write-Host "--- G: Company Layer path handling PS5.1 compatible ---"

$fetchLayer = Join-Path $ScriptDir "scripts\fetch-layer.ps1"
if (Test-Path -LiteralPath $fetchLayer) {
    Assert-NoMultiSegJoinPath "G1: fetch-layer.ps1 has no 3+-arg Join-Path" $fetchLayer
} else {
    Write-Host "  SKIP: G1: fetch-layer.ps1 not found" -ForegroundColor DarkGray
}

Assert-NoMultiSegJoinPath "G2: install-core.ps1 Company Layer validation paths use <=2-arg Join-Path" `
    $installCore

Write-Host ""

# ===========================================================================
# GROUP H: Partial Phase-5 failure remains MIGRATION_IN_PROGRESS
# ===========================================================================
Write-Host "--- H: Partial Phase-5 failure stays MIGRATION_IN_PROGRESS ---"

Assert-Contains "H1: policy prohibits inferring Phase-5 complete from mxcli.exe presence" `
    $policyFile 'mxcli\.exe.*presence.*Phase 5|Phase 5.*mxcli\.exe.*alone|Inferring Phase 5.*mxcli'

Assert-Contains "H2: policy prohibits inferring Phase-5 complete from tool projections" `
    $policyFile 'tool projections.*Phase 5|generated.*projections.*Phase 5|Inferring Phase 5.*projections'

Assert-Contains "H3: policy prohibits inferring Phase-5 complete from scaffold directories" `
    $policyFile 'scaffold.*Phase 5|mxagile-init.*scaffold.*Phase 5|Inferring Phase 5.*scaffold'

Assert-Contains "H4: policy states Phase 5 complete only when install-core exits 0 AND lifecycle.yaml exists" `
    $policyFile 'install-core.*exits 0.*lifecycle\.yaml|lifecycle\.yaml.*install-core.*exits 0'

Assert-Contains "H5: agent prohibits inferring Phase 5 complete from mxcli.exe alone" `
    $agentFile 'Phase 5.*mxcli\.exe.*vorhanden|mxcli\.exe.*Phase 5.*abgeschlossen|mxcli\.exe.*vorhanden.*Phase 5'

Write-Host ""

# ===========================================================================
# GROUP I: Phase-5 retry idempotency documented
# ===========================================================================
Write-Host "--- I: Phase-5 retry idempotency ---"

Assert-Contains "I1: policy documents mxagile-init.ps1 as idempotent on retry" `
    $policyFile 'mxagile-init.*idempoten|idempoten.*mxagile-init|scaffold.*already exist'

Assert-Contains "I2: policy documents mxcli.exe install-mxcli.ps1 already-up-to-date on retry" `
    $policyFile 'already up-to-date|already-up-to-date'

Assert-Contains "I3: policy documents canonical payload copy as safe overwrite on retry" `
    $policyFile '-Force.*safe|safe.*-Force|Overwritten.*-Force|-Force.*idempoten'

Assert-Contains "I4: policy documents that retry requires no manual cleanup" `
    $policyFile 'without requiring manual cleanup|no manual cleanup|NOT require.*manual cleanup'

Write-Host ""

# ===========================================================================
# GROUP J: Agent prohibits manual reconstruction after installer failure
# ===========================================================================
Write-Host "--- J: Agent prohibits manual reconstruction ---"

Assert-Contains "J1: agent prohibits manually copying .mxagile payload" `
    $agentFile '\.mxagile.*Payload.*manuell|manuell.*\.mxagile.*kopieren|manuell.*Distribution.*kopieren'

Assert-Contains "J2: agent prohibits manual Company Layer installation" `
    $agentFile 'Company Layer.*manuell.*installieren|manuell.*Company Layer'

Assert-Contains "J3: agent prohibits hand-reimplementing install-core.ps1" `
    $agentFile 'hand-reimplementieren|reimplementieren|install-core.*hand'

Assert-Contains "J4: policy prohibits manual .mxagile payload copy" `
    $policyFile 'Manually copying.*\.mxagile.*payload|manual.*\.mxagile.*payload.*PROHIBITED'

Assert-Contains "J5: policy prohibits manual Company Layer installation after failure" `
    $policyFile 'Manually running Company Layer|manual.*Company Layer.*PROHIBITED'

Assert-Contains "J6: policy prohibits hand-reimplementing install-core.ps1" `
    $policyFile 'Hand-reimplementing.*install-core|reimplementing.*install-core.*PROHIBITED'

Assert-Contains "J7: policy instructs developer to fix canonical installer and retry Phase 5" `
    $policyFile 'fix the canonical installer.*retry Phase 5|fix.*installer.*retry|retry Phase 5'

Write-Host ""

# ===========================================================================
# GROUPS K-P: Regression suites
# ===========================================================================
Write-Host "--- K-P: Regression suites ---"

Invoke-RegressionSuite "K: test-mxcli-acquisition.ps1 passes" `
    (Join-Path $TestsDir "test-mxcli-acquisition.ps1")

Invoke-RegressionSuite "L: test-migration-lifecycle-resync.ps1 passes" `
    (Join-Path $TestsDir "test-migration-lifecycle-resync.ps1")

Invoke-RegressionSuite "M: test-migration-provenance.ps1 passes" `
    (Join-Path $TestsDir "test-migration-provenance.ps1")

Invoke-RegressionSuite "N: test-migration-crash-safety.ps1 passes" `
    (Join-Path $TestsDir "test-migration-crash-safety.ps1")

Invoke-RegressionSuite "O: test-install-bootstrap-regression.ps1 passes" `
    (Join-Path $TestsDir "test-install-bootstrap-regression.ps1")

Invoke-RegressionSuite "P: test-startup-priority.ps1 passes" `
    (Join-Path $TestsDir "test-startup-priority.ps1")

Write-Host ""

# ===========================================================================
# Summary
# ===========================================================================
Write-Host "=== PS5.1 Compatibility and Phase-5 Safety Test Results ==="
Write-Host "  PASS: $PassCount" -ForegroundColor Green
if ($FailCount -gt 0) {
    Write-Host "  FAIL: $FailCount" -ForegroundColor Red
    foreach ($detail in $FailDetails) {
        Write-Host "    $detail" -ForegroundColor Red
    }
    Write-Host ""
    Write-Host "TEST FAILED: PS5.1 compatibility or Phase-5 safety contract violated." -ForegroundColor Red
    exit 1
} else {
    Write-Host ""
    Write-Host "TEST PASSED: PS5.1 compatibility and Phase-5 safety contracts met." -ForegroundColor Green
    exit 0
}
