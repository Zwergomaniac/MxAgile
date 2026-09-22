<#
.SYNOPSIS
    Install Bootstrap Regression Tests

.DESCRIPTION
    Validates that install-mxagile.ps1 correctly separates:
        - bootstrap location ($PSScriptRoot of the bootstrap)
        - distribution root  (acquired via -DistributionSource)
        - target project     (-ProjectRoot)

    These tests use target directories that contain NO MxAgile internal
    installer scripts, which is the real-world standalone use case.

    Root cause reproduced: running install-mxagile.ps1 from a standalone
    location (e.g. copied into target project) caused $PSScriptRoot to
    resolve inside the target directory, where scripts/install-core.ps1
    does not exist. Normal init or DFC detection never ran.

    Scenarios:
    1.  Bootstrap script contains -DistributionSource parameter
    2.  Bootstrap script contains acquisition logic (not just $PSScriptRoot)
    3.  Bootstrap script contains temp-dir cleanup (finally block)
    4.  Bootstrap script separates bootstrap / distribution / target paths
    5.  Legacy DFC external project: exit 2, migration bootstrap files installed
    6.  Legacy DFC external project: DFC artifacts unchanged
    7.  Legacy DFC external project: no installer scripts in target
    8.  Legacy DFC external project: no complete MxAgile projections in target
    9.  Invalid DistributionSource: exit 1, target unchanged
    10. Distribution inside target: blocked (safety check)
    11. Clean external project: does not fail with "Canonical installer not found"
    12. Mercedes variant: also has acquisition logic
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

function Assert-FileContains {
    param([string]$TestName, [string]$FilePath, [string]$Pattern)
    $content = Get-Content -LiteralPath $FilePath -Raw -ErrorAction SilentlyContinue
    if ($null -eq $content) {
        Assert-True $TestName $false "File not found: $FilePath"
    } else {
        Assert-True $TestName ($content -match $Pattern) "Pattern '$Pattern' not found in $FilePath"
    }
}

function Assert-FileAbsent {
    param([string]$TestName, [string]$FilePath)
    Assert-True $TestName (-not (Test-Path -LiteralPath $FilePath)) "Expected absent: $FilePath"
}

function New-FixtureDirectory {
    param([string]$Name)
    $dir = Join-Path $env:TEMP "mxagile-bootstrap-test-$Name-$([System.Guid]::NewGuid().ToString('N').Substring(0,8))"
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    return $dir
}

function Remove-FixtureDirectory {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path) {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$bootstrapScript = Join-Path $ScriptDir "install-mxagile.ps1"
$mercedesScript  = Join-Path $ScriptDir "install-mxagile-mercedes.ps1"
$distributionRoot = $ScriptDir   # MxAi-Dev-System/ IS the distribution root for local tests

Write-Host ""
Write-Host "=== Install Bootstrap Regression Tests ==="
Write-Host "Distribution: $distributionRoot"
Write-Host ""

# =========================================================================
# 1-4: Static verification of bootstrap script content
# =========================================================================
Write-Host "--- 1-4: Bootstrap script architecture ---"

Assert-FileContains "1: bootstrap has -DistributionSource parameter" `
    $bootstrapScript 'DistributionSource'

Assert-FileContains "2: bootstrap does NOT assume PSScriptRoot is always distribution" `
    $bootstrapScript 'DistributionSource.*not.*provided|IsNullOrWhiteSpace.*DistributionSource|not.*DistributionSource'

Assert-FileContains "2: bootstrap acquires from local path when DistributionSource is a directory" `
    $bootstrapScript 'Test-Path.*DistributionSource.*PathType Container|PathType Container.*DistributionSource'

Assert-FileContains "2: bootstrap supports git clone acquisition" `
    $bootstrapScript 'git clone'

Assert-FileContains "3: bootstrap has finally block for cleanup" `
    $bootstrapScript 'finally\s*\{'

Assert-FileContains "3: cleanup removes tempDistDir" `
    $bootstrapScript 'Remove-Item.*tempDistDir|tempDistDir.*Remove-Item'

Assert-FileContains "4: bootstrap validates distribution != target (safety check)" `
    $bootstrapScript 'distribution.*must not.*inside.*target|distNorm.*targetNorm|targetNorm.*distNorm'

Assert-FileContains "4: bootstrap resolves canonical installer from distribution root" `
    $bootstrapScript 'distributionRoot.*scripts.*install-core|canonicalInstaller.*distributionRoot'

# Zero-config assertions: canonical source embedded in bootstrapper
Assert-FileContains "4b: bootstrap defines canonical distribution URL (zero-config)" `
    $bootstrapScript 'CanonicalDistributionUrl'

Assert-FileContains "4b: bootstrap defines canonical distribution subdirectory" `
    $bootstrapScript 'CanonicalDistributionSubdir'

Assert-FileContains "4b: bootstrap falls through to canonical clone when not in distribution tree" `
    $bootstrapScript 'CanonicalDistributionUrl.*canonical|canonical.*CanonicalDistributionUrl'

Assert-FileContains "4b: mercedes defines canonical distribution URL (zero-config)" `
    $mercedesScript 'CanonicalDistributionUrl'

Write-Host ""

# =========================================================================
# 5-8: E2E regression - legacy DFC external project
# =========================================================================
Write-Host "--- 5-8: E2E regression - legacy DFC external project ---"
$fixtureDfc = New-FixtureDirectory "dfc-external"
try {
    # Minimal DFC project (no MxAgile internal scripts present)
    New-Item -Path (Join-Path $fixtureDfc "CapTrack.mpr") -ItemType File -Force | Out-Null
    $dfcDir = Join-Path $fixtureDfc ".dfc-ai"
    New-Item -Path $dfcDir -ItemType Directory -Force | Out-Null
    Set-Content -Path (Join-Path $dfcDir "version.yaml") -Value 'version: "1.0"' -Encoding UTF8
    $planningDir = Join-Path $fixtureDfc "planning\stories"
    New-Item -Path $planningDir -ItemType Directory -Force | Out-Null
    Set-Content -Path (Join-Path $planningDir "REQ-001.md") -Value "# REQ-001 original" -Encoding UTF8
    Set-Content -Path (Join-Path $fixtureDfc "projekt.md") -Value "# Original project" -Encoding UTF8

    # Verify target has NO MxAgile installer scripts before running
    Assert-FileAbsent "5: target has no detect-project-type.ps1 before bootstrap" `
        (Join-Path $fixtureDfc "scripts\detect-project-type.ps1")

    # Run bootstrap with explicit DistributionSource (external use case)
    $output = & $bootstrapScript `
        -DistributionSource $distributionRoot `
        -ProjectRoot $fixtureDfc 2>&1
    $exitCode = $LASTEXITCODE

    Assert-True "5: exit code is 2 (MIGRATION_REQUIRED) for DFC project" `
        ($exitCode -eq 2) `
        "Expected exit code 2, got: $exitCode. Output: $($output -join ' ')"

    Assert-True "5: output mentions MIGRATION REQUIRED" `
        (($output | Where-Object { $_ -match 'MIGRATION REQUIRED|MIGRATION_REQUIRED' }) -ne $null) `
        "Expected MIGRATION REQUIRED in output"

    Assert-True "5: migration bootstrap files installed" `
        (Test-Path -LiteralPath (Join-Path $fixtureDfc ".mxagile\migration\README.md")) `
        ".mxagile/migration/README.md not installed"

    Assert-True "5: migration agent installed" `
        (Test-Path -LiteralPath (Join-Path $fixtureDfc ".claude\agents\mxagile-migration-agent.md")) `
        ".claude/agents/mxagile-migration-agent.md not installed"

    # 6: DFC artifacts unchanged
    Assert-True "6: .dfc-ai/version.yaml unchanged" `
        (Test-Path -LiteralPath (Join-Path $dfcDir "version.yaml")) `
        ".dfc-ai/version.yaml was removed"

    $req001 = Get-Content -LiteralPath (Join-Path $planningDir "REQ-001.md") -Raw
    Assert-True "6: planning/stories/REQ-001.md content unchanged" `
        ($req001 -match "REQ-001 original") `
        "REQ-001.md was modified"

    $projekt = Get-Content -LiteralPath (Join-Path $fixtureDfc "projekt.md") -Raw
    Assert-True "6: projekt.md unchanged" `
        ($projekt -match "Original project") `
        "projekt.md was modified"

    # 7: No installer scripts in target
    Assert-FileAbsent "7: detect-project-type.ps1 NOT in target" `
        (Join-Path $fixtureDfc "scripts\detect-project-type.ps1")

    Assert-FileAbsent "7: install-core.ps1 NOT in target" `
        (Join-Path $fixtureDfc "scripts\install-core.ps1")

    Assert-FileAbsent "7: install-migration-bootstrap.ps1 NOT in target" `
        (Join-Path $fixtureDfc "scripts\install-migration-bootstrap.ps1")

    Assert-FileAbsent "7: generate-mxagile-platform-skills.ps1 NOT in target" `
        (Join-Path $fixtureDfc "scripts\generate-mxagile-platform-skills.ps1")

    # 8: No complete MxAgile projections in target
    Assert-FileAbsent "8: .mxagile/lifecycle.yaml NOT installed before migration" `
        (Join-Path $fixtureDfc ".mxagile\lifecycle.yaml")

    Assert-FileAbsent "8: .mxagile/orchestrator.md NOT installed before migration" `
        (Join-Path $fixtureDfc ".mxagile\orchestrator.md")

    $claudeSkillsDir8 = Join-Path $fixtureDfc ".claude\skills"
    $mxagileSkillCount8 = 0
    if (Test-Path -LiteralPath $claudeSkillsDir8 -PathType Container) {
        $mxagileSkillCount8 = @(Get-ChildItem -LiteralPath $claudeSkillsDir8 -Recurse -Filter "*.md" -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'mxagile-' }).Count
    }
    Assert-True "8: no mxagile-* lifecycle skills in target" `
        ($mxagileSkillCount8 -eq 0) `
        "Found $mxagileSkillCount8 unexpected mxagile-* skills in target"

} finally {
    Remove-FixtureDirectory $fixtureDfc
}
Write-Host ""

# =========================================================================
# 9: Invalid DistributionSource — target unchanged
# =========================================================================
Write-Host "--- 9: Invalid DistributionSource ---"
$fixtureInvalid = New-FixtureDirectory "invalid-dist"
try {
    New-Item -Path (Join-Path $fixtureInvalid "App.mpr") -ItemType File -Force | Out-Null
    Set-Content -Path (Join-Path $fixtureInvalid "projekt.md") -Value "# Original" -Encoding UTF8

    & $bootstrapScript `
        -DistributionSource "C:\this\path\does\not\exist\mxagile" `
        -ProjectRoot $fixtureInvalid 2>&1 | Out-Null
    $exitCode = $LASTEXITCODE

    Assert-True "9: non-zero exit on invalid distribution" `
        ($exitCode -ne 0) `
        "Expected non-zero exit, got: $exitCode"

    $projektAfter = Get-Content -LiteralPath (Join-Path $fixtureInvalid "projekt.md") -Raw
    Assert-True "9: target project unchanged after acquisition failure" `
        ($projektAfter -match "# Original") `
        "projekt.md was modified"

    Assert-FileAbsent "9: .mxagile/ not created on acquisition failure" `
        (Join-Path $fixtureInvalid ".mxagile\lifecycle.yaml")
} finally {
    Remove-FixtureDirectory $fixtureInvalid
}
Write-Host ""

# =========================================================================
# 10: Distribution inside target — safety check blocks it
# =========================================================================
Write-Host "--- 10: Distribution inside target safety check ---"
$fixtureNested = New-FixtureDirectory "nested"
try {
    New-Item -Path (Join-Path $fixtureNested "App.mpr") -ItemType File -Force | Out-Null
    # Try to use a path INSIDE the target as the distribution
    $nestedDistSource = Join-Path $fixtureNested "mxagile-dist"
    New-Item -Path $nestedDistSource -ItemType Directory -Force | Out-Null
    New-Item -Path (Join-Path $nestedDistSource "scripts") -ItemType Directory -Force | Out-Null
    New-Item -Path (Join-Path $nestedDistSource "scripts\install-core.ps1") -ItemType File -Force | Out-Null

    & $bootstrapScript `
        -DistributionSource $nestedDistSource `
        -ProjectRoot $fixtureNested 2>&1 | Out-Null
    $exitCode = $LASTEXITCODE

    Assert-True "10: blocked when distribution is inside target" `
        ($exitCode -ne 0) `
        "Expected non-zero exit when distribution is inside target, got: $exitCode"
} finally {
    Remove-FixtureDirectory $fixtureNested
}
Write-Host ""

# =========================================================================
# 11: Clean external project — fails at later step, not bootstrap acquisition
# =========================================================================
Write-Host "--- 11: Clean external project bootstrap routing ---"
$fixtureClean = New-FixtureDirectory "clean-external"
try {
    New-Item -Path (Join-Path $fixtureClean "App.mpr") -ItemType File -Force | Out-Null

    $output = & $bootstrapScript `
        -DistributionSource $distributionRoot `
        -ProjectRoot $fixtureClean 2>&1
    $exitCode = $LASTEXITCODE

    # Exit code is non-zero (mxcli missing, etc.) but NOT because of bootstrap acquisition failure
    $hasAcquisitionError = ($output | Where-Object { $_ -match 'Canonical installer not found|Distribution not found|PSScriptRoot' }) -ne $null
    Assert-True "11: bootstrap acquisition succeeded (no 'Canonical installer not found' error)" `
        (-not $hasAcquisitionError) `
        "Bootstrap acquisition failed: $($output -join ' | ')"

    # No installer scripts in clean target
    Assert-FileAbsent "11: detect-project-type.ps1 NOT in clean target" `
        (Join-Path $fixtureClean "scripts\detect-project-type.ps1")

    Assert-FileAbsent "11: install-core.ps1 NOT in clean target" `
        (Join-Path $fixtureClean "scripts\install-core.ps1")

} finally {
    Remove-FixtureDirectory $fixtureClean
}
Write-Host ""

# =========================================================================
# 12: Mercedes variant also has acquisition logic
# =========================================================================
Write-Host "--- 12: Mercedes variant architecture ---"

Assert-FileContains "12: mercedes has -DistributionSource parameter" `
    $mercedesScript 'DistributionSource'

Assert-FileContains "12: mercedes has finally cleanup block" `
    $mercedesScript 'finally\s*\{'

Assert-FileContains "12: mercedes supports git clone acquisition" `
    $mercedesScript 'git clone'

Assert-FileContains "12: mercedes safety check: distribution != target" `
    $mercedesScript 'distNorm.*targetNorm|distribution.*must not.*inside'

Assert-FileContains "12: mercedes resolves canonical installer from distribution" `
    $mercedesScript 'distributionRoot.*scripts.*install-core|canonicalInstaller.*distributionRoot'

Write-Host ""

# =========================================================================
# Summary
# =========================================================================
Write-Host "=== Install Bootstrap Regression Test Results ==="
Write-Host "  PASS: $PassCount" -ForegroundColor Green
if ($FailCount -gt 0) {
    Write-Host "  FAIL: $FailCount" -ForegroundColor Red
    foreach ($detail in $FailDetails) {
        Write-Host "    $detail" -ForegroundColor Red
    }
    Write-Host ""
    Write-Host "TEST FAILED: Bootstrap architecture contract violated." -ForegroundColor Red
    exit 1
} else {
    Write-Host ""
    Write-Host "TEST PASSED: Bootstrap correctly separates bootstrapper / distribution / target." -ForegroundColor Green
    exit 0
}
