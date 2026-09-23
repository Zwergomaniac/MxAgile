<#
.SYNOPSIS
    Bootstrap Rename and State Detection Tests

.DESCRIPTION
    Validates the mxagile-setup.ps1 / mxagile-setup-mercedes.ps1 public entry points:
    - Architecture: canonical setup scripts exist, wrappers delegate correctly
    - State detection: fresh project -> INSTALL, existing -> UPDATE
    - Mercedes independent detection: Core and Layer states detected separately
    - Backward compatibility: old install-mxagile.ps1 wrappers delegate to new scripts
    - Deprecation messaging: wrappers emit deprecation notice
    - One canonical path: no duplicate installation logic in wrappers
    - Documentation: setup scripts referenced in docs
    - Idempotency: re-running setup on an already-installed project uses UPDATE path
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

function Assert-FileContains {
    param([string]$TestName, [string]$FilePath, [string]$Pattern)
    $content = Get-Content -LiteralPath $FilePath -Raw -ErrorAction SilentlyContinue
    if ($null -eq $content) {
        Assert-True $TestName $false "File not found: $FilePath"
    } else {
        Assert-True $TestName ($content -match $Pattern) "Pattern '$Pattern' not found in $FilePath"
    }
}

function Assert-FileNotContains {
    param([string]$TestName, [string]$FilePath, [string]$Pattern)
    $content = Get-Content -LiteralPath $FilePath -Raw -ErrorAction SilentlyContinue
    if ($null -eq $content) {
        Assert-True $TestName $false "File not found: $FilePath"
    } else {
        Assert-True $TestName ($content -notmatch $Pattern) "Forbidden pattern '$Pattern' found in $FilePath"
    }
}

function New-FixtureDirectory {
    param([string]$Name)
    $dir = Join-Path $env:TEMP "mxagile-setup-test-$Name-$([System.Guid]::NewGuid().ToString('N').Substring(0,8))"
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    return $dir
}

function Remove-FixtureDirectory {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path) {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$setupScript         = Join-Path $ScriptDir "mxagile-setup.ps1"
$setupMercedesScript = Join-Path $ScriptDir "mxagile-setup-mercedes.ps1"
$installScript       = Join-Path $ScriptDir "install-mxagile.ps1"
$installMercedesScript = Join-Path $ScriptDir "install-mxagile-mercedes.ps1"
$installationDoc     = Join-Path $ScriptDir "docs\installation.md"
$readmeDoc           = Join-Path $ScriptDir "README.md"
$distributionRoot    = $ScriptDir

Write-Host ""
Write-Host "=== Bootstrap Rename and State Detection Tests ==="
Write-Host "Distribution: $distributionRoot"
Write-Host ""

# =========================================================================
# 1. New canonical setup scripts exist
# =========================================================================
Write-Host "--- 1: Canonical setup scripts exist ---"

Assert-True "mxagile-setup.ps1 exists" `
    (Test-Path -LiteralPath $setupScript -PathType Leaf) `
    "mxagile-setup.ps1 not found at: $setupScript"

Assert-True "mxagile-setup-mercedes.ps1 exists" `
    (Test-Path -LiteralPath $setupMercedesScript -PathType Leaf) `
    "mxagile-setup-mercedes.ps1 not found at: $setupMercedesScript"

Assert-True "install-mxagile.ps1 still exists (compatibility)" `
    (Test-Path -LiteralPath $installScript -PathType Leaf) `
    "install-mxagile.ps1 not found (needed for backward compat)"

Assert-True "install-mxagile-mercedes.ps1 still exists (compatibility)" `
    (Test-Path -LiteralPath $installMercedesScript -PathType Leaf) `
    "install-mxagile-mercedes.ps1 not found (needed for backward compat)"

Write-Host ""

# =========================================================================
# 2. Setup scripts have full acquisition logic
# =========================================================================
Write-Host "--- 2: Setup scripts have full acquisition architecture ---"

Assert-FileContains "setup: has DistributionSource parameter" `
    $setupScript 'DistributionSource'

Assert-FileContains "setup: has acquisition/git clone logic" `
    $setupScript 'git clone'

Assert-FileContains "setup: has finally cleanup block" `
    $setupScript 'finally\s*\{'

Assert-FileContains "setup: has safety check (dist not inside target)" `
    $setupScript 'distNorm.*targetNorm|distribution.*must not.*inside'

Assert-FileContains "setup: calls scripts/install-core.ps1" `
    $setupScript 'install-core\.ps1'

Assert-FileContains "setup: has CanonicalDistributionUrl" `
    $setupScript 'CanonicalDistributionUrl'

Assert-FileContains "mercedes-setup: has DistributionSource parameter" `
    $setupMercedesScript 'DistributionSource'

Assert-FileContains "mercedes-setup: has MercedesGitUrl parameter" `
    $setupMercedesScript 'MercedesGitUrl'

Assert-FileContains "mercedes-setup: calls scripts/install-core.ps1" `
    $setupMercedesScript 'install-core\.ps1'

Write-Host ""

# =========================================================================
# 3. Setup scripts detect and report project state
# =========================================================================
Write-Host "--- 3: Setup scripts detect and report project state ---"

Assert-FileContains "setup: detects .mxagile/lifecycle.yaml as Core marker" `
    $setupScript 'lifecycle\.yaml'

Assert-FileContains "setup: defines INSTALL operation" `
    $setupScript '(?i)INSTALL'

Assert-FileContains "setup: defines UPDATE operation" `
    $setupScript '(?i)UPDATE'

Assert-FileContains "setup: reports FRESH_PROJECT state" `
    $setupScript 'FRESH_PROJECT'

Assert-FileContains "setup: reports EXISTING_MXAGILE_PROJECT state" `
    $setupScript 'EXISTING_MXAGILE_PROJECT'

Assert-FileContains "setup: reports protected project state" `
    $setupScript '(?i)protected.*project.*state|never overwritten'

Write-Host ""

# =========================================================================
# 4. Mercedes setup independently detects Core and Layer states
# =========================================================================
Write-Host "--- 4: Mercedes setup independently detects Core + Layer ---"

Assert-FileContains "mercedes-setup: detects Core via .mxagile/lifecycle.yaml" `
    $setupMercedesScript 'lifecycle\.yaml'

Assert-FileContains "mercedes-setup: detects Layer via .mxagile/layers/" `
    $setupMercedesScript '\.mxagile\\layers|mxagile.layers'

Assert-FileContains "mercedes-setup: reports Core state independently" `
    $setupMercedesScript 'coreState'

Assert-FileContains "mercedes-setup: reports Layer state independently" `
    $setupMercedesScript 'layerState'

Assert-FileContains "mercedes-setup: reports Core operation separately" `
    $setupMercedesScript 'coreOperation'

Assert-FileContains "mercedes-setup: reports Layer operation separately" `
    $setupMercedesScript 'layerOperation'

Assert-FileContains "mercedes-setup: LAYER_NOT_INSTALLED state defined" `
    $setupMercedesScript 'LAYER_NOT_INSTALLED'

Assert-FileContains "mercedes-setup: MERCEDES_LAYER_INSTALLED state defined" `
    $setupMercedesScript 'MERCEDES_LAYER_INSTALLED'

Write-Host ""

# =========================================================================
# 5. Compatibility wrappers delegate to setup scripts (not duplicate logic)
# =========================================================================
Write-Host "--- 5: Compatibility wrappers delegate, no duplicate logic ---"

Assert-FileContains "install-wrapper: delegates to mxagile-setup.ps1" `
    $installScript 'mxagile-setup\.ps1'

Assert-FileContains "install-wrapper: has deprecation notice" `
    $installScript '(?i)deprecated|DEPRECATED'

Assert-FileContains "install-mercedes-wrapper: delegates to mxagile-setup-mercedes.ps1" `
    $installMercedesScript 'mxagile-setup-mercedes\.ps1'

Assert-FileContains "install-mercedes-wrapper: has deprecation notice" `
    $installMercedesScript '(?i)deprecated|DEPRECATED'

# Wrappers must NOT contain installation logic (no git clone, no Remove-Item for cleanup)
Assert-FileNotContains "install-wrapper: no git clone in wrapper" `
    $installScript 'git clone'

Assert-FileNotContains "install-wrapper: no Remove-Item tempDistDir in wrapper" `
    $installScript 'Remove-Item.*tempDistDir'

Assert-FileNotContains "install-mercedes-wrapper: no git clone in wrapper" `
    $installMercedesScript 'git clone'

Assert-FileNotContains "install-mercedes-wrapper: no Remove-Item tempDistDir in wrapper" `
    $installMercedesScript 'Remove-Item.*tempDistDir'

Write-Host ""

# =========================================================================
# 6. E2E: Fresh project (no .mxagile/) detects INSTALL
# =========================================================================
Write-Host "--- 6: E2E fresh project -> INSTALL detection ---"

$fixtureFresh = New-FixtureDirectory "fresh"
try {
    New-Item -Path (Join-Path $fixtureFresh "App.mpr") -ItemType File -Force | Out-Null

    # Use *>&1 to capture all streams including Write-Host (stream 6/Information in PS7)
    $output = & $setupScript `
        -DistributionSource $distributionRoot `
        -ProjectRoot $fixtureFresh *>&1
    $outputStr = ($output | Out-String)
    # We don't check exit code here (mxcli may not be available) - just verify output messaging

    Assert-True "6: fresh project shows INSTALL operation in output" `
        ($outputStr -match 'FRESH_PROJECT|INSTALL') `
        "Expected FRESH_PROJECT or INSTALL in output. First 200 chars: $($outputStr.Substring(0, [Math]::Min(200, $outputStr.Length)))"

    Assert-True "6: setup detects project state" `
        ($outputStr -match 'Detecting project state') `
        "Expected 'Detecting project state' in output"

    Assert-True "6: setup reports protected state" `
        ($outputStr -match 'Protected|never overwritten') `
        "Expected protected state notice in output"

} finally {
    Remove-FixtureDirectory $fixtureFresh
}

Write-Host ""

# =========================================================================
# 7. E2E: Existing MxAgile project detects UPDATE
# =========================================================================
Write-Host "--- 7: E2E existing project -> UPDATE detection ---"

$fixtureExisting = New-FixtureDirectory "existing"
try {
    New-Item -Path (Join-Path $fixtureExisting "App.mpr") -ItemType File -Force | Out-Null
    # Plant the canonical Core marker to simulate an existing MxAgile installation
    $mxagileDir = Join-Path $fixtureExisting ".mxagile"
    New-Item -Path $mxagileDir -ItemType Directory -Force | Out-Null
    Set-Content -Path (Join-Path $mxagileDir "lifecycle.yaml") -Value "schema_version: 1" -Encoding UTF8

    $output = & $setupScript `
        -DistributionSource $distributionRoot `
        -ProjectRoot $fixtureExisting *>&1
    $outputStr = ($output | Out-String)

    Assert-True "7: existing project shows UPDATE operation in output" `
        ($outputStr -match 'EXISTING_MXAGILE_PROJECT|UPDATE') `
        "Expected EXISTING_MXAGILE_PROJECT or UPDATE in output. First 200 chars: $($outputStr.Substring(0, [Math]::Min(200, $outputStr.Length)))"

    Assert-True "7: existing project does NOT show FRESH_PROJECT" `
        ($outputStr -notmatch 'FRESH_PROJECT') `
        "Unexpected FRESH_PROJECT in output for existing project"

} finally {
    Remove-FixtureDirectory $fixtureExisting
}

Write-Host ""

# =========================================================================
# 8. E2E Mercedes: fresh -> Core INSTALL + Layer INSTALL
# =========================================================================
Write-Host "--- 8: Mercedes fresh project -> Core INSTALL + Layer INSTALL ---"

$fixtureMercedesFresh = New-FixtureDirectory "mercedes-fresh"
try {
    New-Item -Path (Join-Path $fixtureMercedesFresh "App.mpr") -ItemType File -Force | Out-Null

    $output = & $setupMercedesScript `
        -DistributionSource $distributionRoot `
        -ProjectRoot $fixtureMercedesFresh `
        -MercedesGitUrl "https://example.com/fake-layer.git" *>&1
    $outputStr = ($output | Out-String)

    Assert-True "8: Mercedes fresh project shows FRESH_PROJECT for Core" `
        ($outputStr -match 'FRESH_PROJECT') `
        "Expected FRESH_PROJECT for Core. First 300 chars: $($outputStr.Substring(0, [Math]::Min(300, $outputStr.Length)))"

    Assert-True "8: Mercedes fresh project shows LAYER_NOT_INSTALLED" `
        ($outputStr -match 'LAYER_NOT_INSTALLED') `
        "Expected LAYER_NOT_INSTALLED. First 300 chars: $($outputStr.Substring(0, [Math]::Min(300, $outputStr.Length)))"

    Assert-True "8: Mercedes fresh reports Core action INSTALL" `
        ($outputStr -match 'Core action.*INSTALL|INSTALL.*Core') `
        "Expected Core action INSTALL. First 300 chars: $($outputStr.Substring(0, [Math]::Min(300, $outputStr.Length)))"

} finally {
    Remove-FixtureDirectory $fixtureMercedesFresh
}

Write-Host ""

# =========================================================================
# 9. E2E Mercedes: existing Core + no Layer -> Core UPDATE + Layer INSTALL
# =========================================================================
Write-Host "--- 9: Mercedes existing Core, no Layer -> Core UPDATE + Layer INSTALL ---"

$fixtureMercedesCore = New-FixtureDirectory "mercedes-core-only"
try {
    New-Item -Path (Join-Path $fixtureMercedesCore "App.mpr") -ItemType File -Force | Out-Null
    # Plant Core marker only (no layer)
    $mxDir = Join-Path $fixtureMercedesCore ".mxagile"
    New-Item -Path $mxDir -ItemType Directory -Force | Out-Null
    Set-Content -Path (Join-Path $mxDir "lifecycle.yaml") -Value "schema_version: 1" -Encoding UTF8

    $output = & $setupMercedesScript `
        -DistributionSource $distributionRoot `
        -ProjectRoot $fixtureMercedesCore `
        -MercedesGitUrl "https://example.com/fake-layer.git" *>&1
    $outputStr = ($output | Out-String)

    Assert-True "9: Core existing detected correctly" `
        ($outputStr -match 'EXISTING_MXAGILE_PROJECT') `
        "Expected EXISTING_MXAGILE_PROJECT. First 300 chars: $($outputStr.Substring(0, [Math]::Min(300, $outputStr.Length)))"

    Assert-True "9: Layer absence detected correctly" `
        ($outputStr -match 'LAYER_NOT_INSTALLED') `
        "Expected LAYER_NOT_INSTALLED. First 300 chars: $($outputStr.Substring(0, [Math]::Min(300, $outputStr.Length)))"

    Assert-True "9: Core operation is UPDATE" `
        ($outputStr -match 'Core action.*UPDATE|UPDATE.*Core') `
        "Expected Core action UPDATE. First 300 chars: $($outputStr.Substring(0, [Math]::Min(300, $outputStr.Length)))"

    Assert-True "9: Layer operation is INSTALL" `
        ($outputStr -match 'Company Layer action.*INSTALL|Layer action.*INSTALL') `
        "Expected Layer action INSTALL. First 300 chars: $($outputStr.Substring(0, [Math]::Min(300, $outputStr.Length)))"

} finally {
    Remove-FixtureDirectory $fixtureMercedesCore
}

Write-Host ""

# =========================================================================
# 10. E2E: Old compatibility wrapper delegates to new setup script
# =========================================================================
Write-Host "--- 10: Old wrapper delegates to new setup script ---"

$fixtureWrapper = New-FixtureDirectory "wrapper-compat"
try {
    New-Item -Path (Join-Path $fixtureWrapper "App.mpr") -ItemType File -Force | Out-Null

    $output = & $installScript `
        -DistributionSource $distributionRoot `
        -ProjectRoot $fixtureWrapper *>&1
    $outputStr = ($output | Out-String)

    Assert-True "10: old wrapper shows deprecation notice" `
        ($outputStr -match '(?i)deprecated|DEPRECATED') `
        "Expected deprecation notice in wrapper output"

    Assert-True "10: old wrapper output references mxagile-setup.ps1" `
        ($outputStr -match 'mxagile-setup\.ps1') `
        "Expected reference to mxagile-setup.ps1 in wrapper output"

    # The actual setup runs (delegation worked)
    Assert-True "10: delegation to setup script executed (detection output present)" `
        ($outputStr -match 'Detecting project state|MxAgile Setup') `
        "Expected setup script output. Wrapper may not have delegated. First 300 chars: $($outputStr.Substring(0, [Math]::Min(300, $outputStr.Length)))"

} finally {
    Remove-FixtureDirectory $fixtureWrapper
}

Write-Host ""

# =========================================================================
# 11. Documentation references setup scripts
# =========================================================================
Write-Host "--- 11: Documentation references mxagile-setup.ps1 ---"

Assert-FileContains "installation.md: references mxagile-setup.ps1" `
    $installationDoc 'mxagile-setup\.ps1'

Assert-FileContains "installation.md: references mxagile-setup-mercedes.ps1" `
    $installationDoc 'mxagile-setup-mercedes\.ps1'

Assert-FileContains "installation.md: describes INSTALL/UPDATE detection" `
    $installationDoc '(?i)INSTALL.*UPDATE|detects.*state'

Assert-FileContains "installation.md: marks old scripts as deprecated" `
    $installationDoc '(?i)[Dd]eprecated'

Assert-FileContains "README.md: references mxagile-setup.ps1" `
    $readmeDoc 'mxagile-setup\.ps1'

Write-Host ""

# =========================================================================
# 12. Idempotency: re-running setup on existing project uses UPDATE
# =========================================================================
Write-Host "--- 12: Idempotency — re-run on existing project uses UPDATE path ---"

$fixtureIdemp = New-FixtureDirectory "idempotent"
try {
    New-Item -Path (Join-Path $fixtureIdemp "App.mpr") -ItemType File -Force | Out-Null
    # Simulate already-installed Core
    $mxDir2 = Join-Path $fixtureIdemp ".mxagile"
    New-Item -Path $mxDir2 -ItemType Directory -Force | Out-Null
    Set-Content -Path (Join-Path $mxDir2 "lifecycle.yaml") -Value "schema_version: 1" -Encoding UTF8
    # Simulate project-owned state that must survive
    $layersDir2 = Join-Path $mxDir2 "layers"
    New-Item -Path $layersDir2 -ItemType Directory -Force | Out-Null
    Set-Content -Path (Join-Path $layersDir2 "marker.txt") -Value "layer content" -Encoding UTF8

    $output = & $setupScript `
        -DistributionSource $distributionRoot `
        -ProjectRoot $fixtureIdemp *>&1
    $outputStr = ($output | Out-String)

    Assert-True "12: re-run on existing project selects UPDATE" `
        ($outputStr -match 'UPDATE') `
        "Expected UPDATE in output when re-running on existing project"

    # Protected layers directory must survive the re-run (as far as the bootstrap goes)
    Assert-True "12: .mxagile/layers/ still exists after re-run" `
        (Test-Path -LiteralPath $layersDir2 -PathType Container) `
        ".mxagile/layers/ was removed during idempotent re-run"

} finally {
    Remove-FixtureDirectory $fixtureIdemp
}

Write-Host ""

# =========================================================================
# Summary
# =========================================================================
Write-Host "=== Setup Detection Test Results ==="
Write-Host "  PASS: $PassCount" -ForegroundColor Green
if ($FailCount -gt 0) {
    Write-Host "  FAIL: $FailCount" -ForegroundColor Red
    foreach ($detail in $FailDetails) {
        Write-Host "    $detail" -ForegroundColor Red
    }
    Write-Host ""
    Write-Host "TEST FAILED: Bootstrap rename or state detection contract violated." -ForegroundColor Red
    exit 1
} else {
    Write-Host ""
    Write-Host "TEST PASSED: Bootstrap rename, state detection, and compatibility wrappers are correct." -ForegroundColor Green
    exit 0
}
