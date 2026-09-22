<#
.SYNOPSIS
    Migration Provenance Persistence Tests

.DESCRIPTION
    Validates that installation provenance is correctly persisted to
    .mxagile/migration/provenance.yaml by the migration bootstrap, and that
    the policy and agent documents correctly describe provenance-based Phase 5.

    Test groups:
    A  - Runtime: flavor=core persisted correctly
    B  - Runtime: flavor=mercedes persisted correctly
    C  - Runtime: core source and ref persisted
    D  - Runtime: mercedes company_layer block persisted
    E  - Runtime: provenance.yaml written before bootstrap exits (ordering)
    F  - Static: policy describes provenance-based Phase 5 acquisition
    G  - Static: policy requires validation of provenance fields
    H  - Static: policy forbids guessing/substituting distribution
    I  - Static: policy includes flavor-specific install-core.ps1 invocation
    J  - Static: agent references provenance.yaml in step 9
    K  - Runtime: ref value is reused from passed param
    L  - Static: policy stops on missing provenance fields
    M  - Static: policy instructs re-running bootstrap to restore provenance
    N  - Static: policy states MIGRATION_IN_PROGRESS survives install failure
    O  - Static: policy references lifecycle.yaml as success signal
    P  - Static: policy instructs temp dir cleanup
    Q  - Runtime: provenance.yaml does not overwrite state.yaml or brownfield-baseline
    R  - Regression: test-migration-crash-safety.ps1 passes
    S  - Regression: test-dfc-migration-preflight.ps1 passes
    T  - Regression: test-install-bootstrap-regression.ps1 passes
    U  - Regression: test-startup-priority.ps1 passes
#>

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$TestsDir     = $PSScriptRoot
$ScriptDir    = Split-Path -Parent $TestsDir
$PassCount    = 0
$FailCount    = 0
$FailDetails  = @()

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
        Assert-True $TestName (-not ($content -match $Pattern)) "Pattern '$Pattern' should NOT appear in $FilePath"
    }
}

function New-FixtureDirectory {
    param([string]$Name)
    $dir = Join-Path $env:TEMP "mxagile-provenance-$Name-$([System.Guid]::NewGuid().ToString('N').Substring(0,8))"
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    return $dir
}

function Remove-FixtureDirectory {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path) {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Key paths
$bootstrapScript  = Join-Path $ScriptDir "scripts\install-migration-bootstrap.ps1"
$canonicalMxAgile = Join-Path $ScriptDir ".mxagile"
$policyFile       = Join-Path $canonicalMxAgile "policies\migration-dfc-to-mxagile.md"
$agentFile        = Join-Path $canonicalMxAgile "agents\migration-agent.md"

Write-Host ""
Write-Host "=== Migration Provenance Persistence Tests ==="
Write-Host ""

# =========================================================================
# Infrastructure check
# =========================================================================
Write-Host "--- Infrastructure ---"
Assert-True "bootstrap script exists" (Test-Path -LiteralPath $bootstrapScript) "Not found: $bootstrapScript"
Assert-True "migration policy exists"  (Test-Path -LiteralPath $policyFile)      "Not found: $policyFile"
Assert-True "migration agent exists"   (Test-Path -LiteralPath $agentFile)       "Not found: $agentFile"
Write-Host ""

# =========================================================================
# GROUP A,B: Flavor persistence
# =========================================================================
Write-Host "--- A,B: Flavor persistence ---"

$fixtureA = New-FixtureDirectory "A-core-flavor"
try {
    # bootstrap needs a .mpr file to satisfy install-core preflight but bootstrap itself
    # only needs ProjectRoot to exist with .mxagile/migration/ or it will create it.
    New-Item -Path (Join-Path $fixtureA "App.mpr") -ItemType File -Force | Out-Null

    & $bootstrapScript `
        -ProjectRoot              $fixtureA `
        -CanonicalSource          $canonicalMxAgile `
        -ProvenanceFlavor         "core" `
        -ProvenanceCoreSource     "https://github.com/Zwergomaniac/MxAgile.git" `
        -ProvenanceCoreSourceType "git" `
        -ProvenanceCoreRef        "main"

    $provenancePath = Join-Path $fixtureA ".mxagile\migration\provenance.yaml"
    Assert-True "A1: provenance.yaml created for core flavor" `
        (Test-Path -LiteralPath $provenancePath) `
        "provenance.yaml not written at $provenancePath"

    $pContent = Get-Content -LiteralPath $provenancePath -Raw -ErrorAction SilentlyContinue
    Assert-True "A2: flavor: core in provenance.yaml" `
        ($pContent -match 'flavor:\s*core') `
        "flavor: core not found in provenance.yaml"

    Assert-FileNotContains "A3: no company_layer block in core provenance" `
        $provenancePath 'company_layer:'

} finally {
    Remove-FixtureDirectory $fixtureA
}

$fixtureB = New-FixtureDirectory "B-mercedes-flavor"
try {
    New-Item -Path (Join-Path $fixtureB "App.mpr") -ItemType File -Force | Out-Null

    & $bootstrapScript `
        -ProjectRoot              $fixtureB `
        -CanonicalSource          $canonicalMxAgile `
        -ProvenanceFlavor         "mercedes" `
        -ProvenanceCoreSource     "https://github.com/Zwergomaniac/MxAgile.git" `
        -ProvenanceCoreSourceType "git" `
        -ProvenanceCoreRef        "main" `
        -CompanyLayerSource       "https://mercedes-benz.ghe.com/DFC-Applikationsentwicklung/MxAgile-CompanyLayer.git" `
        -CompanyLayerSourceType   "git" `
        -CompanyLayerRef          "main"

    $provenancePath = Join-Path $fixtureB ".mxagile\migration\provenance.yaml"
    Assert-True "B1: provenance.yaml created for mercedes flavor" `
        (Test-Path -LiteralPath $provenancePath) `
        "provenance.yaml not written at $provenancePath"

    $pContent = Get-Content -LiteralPath $provenancePath -Raw -ErrorAction SilentlyContinue
    Assert-True "B2: flavor: mercedes in provenance.yaml" `
        ($pContent -match 'flavor:\s*mercedes') `
        "flavor: mercedes not found in provenance.yaml"

    Assert-True "B3: company_layer block present for mercedes" `
        ($pContent -match 'company_layer:') `
        "company_layer: block missing from mercedes provenance.yaml"

} finally {
    Remove-FixtureDirectory $fixtureB
}
Write-Host ""

# =========================================================================
# GROUP C: Core source/ref persisted
# =========================================================================
Write-Host "--- C: Core source and ref persisted ---"

$fixtureC = New-FixtureDirectory "C-source-ref"
try {
    New-Item -Path (Join-Path $fixtureC "App.mpr") -ItemType File -Force | Out-Null

    & $bootstrapScript `
        -ProjectRoot              $fixtureC `
        -CanonicalSource          $canonicalMxAgile `
        -ProvenanceFlavor         "core" `
        -ProvenanceCoreSource     "https://example.com/mxagile-test.git" `
        -ProvenanceCoreSourceType "git" `
        -ProvenanceCoreRef        "v2.3.1"

    $provenancePath = Join-Path $fixtureC ".mxagile\migration\provenance.yaml"
    $pContent = Get-Content -LiteralPath $provenancePath -Raw -ErrorAction SilentlyContinue

    Assert-True "C1: core source URL persisted" `
        ($pContent -match 'source:.*https://example\.com/mxagile-test\.git') `
        "Core source URL not found in provenance.yaml"

    Assert-True "C2: core ref persisted" `
        ($pContent -match 'ref:\s*v2\.3\.1') `
        "Core ref v2.3.1 not found in provenance.yaml"

    Assert-True "C3: source_type: git persisted" `
        ($pContent -match 'source_type:\s*git') `
        "source_type: git not found in provenance.yaml"

} finally {
    Remove-FixtureDirectory $fixtureC
}
Write-Host ""

# =========================================================================
# GROUP D: Mercedes company layer block persisted
# =========================================================================
Write-Host "--- D: Mercedes company layer persisted ---"

$fixtureD = New-FixtureDirectory "D-company-layer"
try {
    New-Item -Path (Join-Path $fixtureD "App.mpr") -ItemType File -Force | Out-Null

    & $bootstrapScript `
        -ProjectRoot              $fixtureD `
        -CanonicalSource          $canonicalMxAgile `
        -ProvenanceFlavor         "mercedes" `
        -ProvenanceCoreSource     "https://github.com/Zwergomaniac/MxAgile.git" `
        -ProvenanceCoreSourceType "git" `
        -ProvenanceCoreRef        "main" `
        -CompanyLayerSource       "https://mercedes-benz.ghe.com/DFC/Layer.git" `
        -CompanyLayerSourceType   "git" `
        -CompanyLayerRef          "release-1.0"

    $provenancePath = Join-Path $fixtureD ".mxagile\migration\provenance.yaml"
    $pContent = Get-Content -LiteralPath $provenancePath -Raw -ErrorAction SilentlyContinue

    Assert-True "D1: company_layer.source persisted" `
        ($pContent -match 'source:.*mercedes-benz\.ghe\.com.*Layer\.git') `
        "Company layer source not found in provenance.yaml"

    Assert-True "D2: company_layer.ref persisted" `
        ($pContent -match 'ref:\s*release-1\.0') `
        "Company layer ref release-1.0 not found in provenance.yaml"

    Assert-True "D3: company_layer.source_type persisted" `
        ($pContent -match 'source_type:\s*git') `
        "Company layer source_type not found in provenance.yaml"

} finally {
    Remove-FixtureDirectory $fixtureD
}
Write-Host ""

# =========================================================================
# GROUP E: Provenance written before bootstrap exits (ordering)
# =========================================================================
Write-Host "--- E: Provenance written before bootstrap exits ---"

# Static check: the bootstrap script writes provenance.yaml before the final message
$bootstrapContent = Get-Content -LiteralPath $bootstrapScript -Raw -ErrorAction SilentlyContinue
Assert-True "E1: bootstrap script contains provenance.yaml write" `
    ($bootstrapContent -match 'provenance\.yaml') `
    "provenance.yaml write not found in bootstrap script"

Assert-True "E2: bootstrap uses File::WriteAllText for provenance (consistent with other files)" `
    ($bootstrapContent -match 'WriteAllText.*provenance|provenance.*WriteAllText') `
    "File::WriteAllText not used for provenance.yaml in bootstrap"

# Runtime check: after calling bootstrap, provenance.yaml exists and is non-empty
$fixtureE = New-FixtureDirectory "E-ordering"
try {
    New-Item -Path (Join-Path $fixtureE "App.mpr") -ItemType File -Force | Out-Null

    & $bootstrapScript `
        -ProjectRoot              $fixtureE `
        -CanonicalSource          $canonicalMxAgile `
        -ProvenanceFlavor         "core" `
        -ProvenanceCoreSource     "https://github.com/Zwergomaniac/MxAgile.git" `
        -ProvenanceCoreSourceType "git" `
        -ProvenanceCoreRef        "main"

    $provenancePath = Join-Path $fixtureE ".mxagile\migration\provenance.yaml"
    Assert-True "E3: provenance.yaml exists after bootstrap returns" `
        (Test-Path -LiteralPath $provenancePath) `
        "provenance.yaml missing after bootstrap completed"

    $pContent = Get-Content -LiteralPath $provenancePath -Raw -ErrorAction SilentlyContinue
    Assert-True "E4: provenance.yaml is non-empty" `
        (-not [string]::IsNullOrWhiteSpace($pContent)) `
        "provenance.yaml is empty"

} finally {
    Remove-FixtureDirectory $fixtureE
}
Write-Host ""

# =========================================================================
# GROUP F,G,H: Reacquisition from provenance only (static policy checks)
# =========================================================================
Write-Host "--- F,G,H: Reacquisition from provenance only (static policy checks) ---"

Assert-FileContains "F1: policy describes provenance.yaml read" `
    $policyFile 'provenance\.yaml'

Assert-FileContains "F2: policy describes git clone for reacquisition" `
    $policyFile 'git clone'

Assert-FileContains "F3: policy references subdirectory resolution" `
    $policyFile 'subdirectory|subdir'

Assert-FileContains "G1: policy requires validation of flavor field" `
    $policyFile 'flavor.*core.*mercedes|core.*mercedes.*flavor|installation\.flavor'

Assert-FileContains "G2: policy requires validation of core.source" `
    $policyFile 'core\.source|installation\.core\.source'

Assert-FileContains "G3: policy requires validation of source_type" `
    $policyFile 'source_type.*git.*local|git.*local.*source_type'

Assert-FileContains "H1: policy forbids guessing repository URLs" `
    $policyFile '[Gg]uess.*[Uu]rl|[Gg]uess.*[Rr]epositor'

Assert-FileContains "H2: policy forbids searching neighboring directories" `
    $policyFile '[Nn]eighbor|[Bb]enachbart'

Assert-FileContains "H3: policy forbids silently substituting distribution" `
    $policyFile '[Ss]ilently|[Ii]mplicit.*[Ff]allback|implizit'

Write-Host ""

# =========================================================================
# GROUP I,J: Migration flavor preserved (static checks)
# =========================================================================
Write-Host "--- I,J: Flavor-specific install paths (static checks) ---"

Assert-FileContains "I1: policy shows core-only install-core.ps1 invocation" `
    $policyFile 'flavor.*core.*install-core|install-core.*flavor.*core|For.*flavor.*core'

Assert-FileContains "I2: policy shows mercedes install-core.ps1 invocation with company layer" `
    $policyFile 'company_layer|CompanyLayer|CompanyLayerSource'

Assert-FileContains "J1: agent references provenance.yaml in step 9" `
    $agentFile 'provenance\.yaml'

Assert-FileContains "J2: agent step 9 validates provenance fields" `
    $agentFile 'Validiere.*Pflichtfelder|Pflichtfelder'

Assert-FileContains "J3: agent step 9 stops on missing/invalid provenance" `
    $agentFile 'STOPP.*nicht raten|STOPP.*substituieren'

Write-Host ""

# =========================================================================
# GROUP K: Ref is reused exactly as passed
# =========================================================================
Write-Host "--- K: Ref is reused from passed param ---"

$fixtureK = New-FixtureDirectory "K-ref-reuse"
try {
    New-Item -Path (Join-Path $fixtureK "App.mpr") -ItemType File -Force | Out-Null

    & $bootstrapScript `
        -ProjectRoot              $fixtureK `
        -CanonicalSource          $canonicalMxAgile `
        -ProvenanceFlavor         "core" `
        -ProvenanceCoreSource     "https://github.com/Zwergomaniac/MxAgile.git" `
        -ProvenanceCoreSourceType "git" `
        -ProvenanceCoreRef        "release-99.0"

    $provenancePath = Join-Path $fixtureK ".mxagile\migration\provenance.yaml"
    $pContent = Get-Content -LiteralPath $provenancePath -Raw -ErrorAction SilentlyContinue

    Assert-True "K1: exact ref value preserved in provenance.yaml" `
        ($pContent -match 'ref:\s*release-99\.0') `
        "ref value release-99.0 not found in provenance.yaml"

} finally {
    Remove-FixtureDirectory $fixtureK
}
Write-Host ""

# =========================================================================
# GROUP L,M: Missing/malformed provenance stops safely (static)
# =========================================================================
Write-Host "--- L,M: Missing/malformed provenance stops safely (static) ---"

Assert-FileContains "L1: policy STOP instruction on missing fields" `
    $policyFile 'STOP|STOPP'

Assert-FileContains "L2: policy says not to downgrade mercedes to core-only" `
    $policyFile '[Dd]owngrade.*[Cc]ore|[Mm]ercedes.*[Cc]ore.*only|[Cc]ore-only'

Assert-FileContains "M1: policy instructs re-running bootstrap to restore provenance" `
    $policyFile 'install-mxagile\.ps1|bootstrap.*restore|re-run.*bootstrap'

Assert-FileContains "M2: policy confirms project stays in MIGRATION_IN_PROGRESS safely" `
    $policyFile 'MIGRATION_IN_PROGRESS.*safely|safely.*MIGRATION_IN_PROGRESS|project remains.*MIGRATION_IN_PROGRESS'

Write-Host ""

# =========================================================================
# GROUP N: Installation failure leaves MIGRATION_IN_PROGRESS (static)
# =========================================================================
Write-Host "--- N: Installation failure leaves MIGRATION_IN_PROGRESS ---"

# The policy's state machine section defines MIGRATION_IN_PROGRESS invariant
Assert-FileContains "N1: policy defines MIGRATION_IN_PROGRESS invariant" `
    $policyFile 'MIGRATION_IN_PROGRESS.*until.*install-core|install-core.*lifecycle\.yaml|lifecycle\.yaml.*signals.*migration'

Write-Host ""

# =========================================================================
# GROUP O: Success reaches EXISTING_MXAGILE_PROJECT (static)
# =========================================================================
Write-Host "--- O: Success reaches EXISTING_MXAGILE_PROJECT ---"

Assert-FileContains "O1: policy shows lifecycle.yaml signals Phase 5 success" `
    $policyFile 'lifecycle\.yaml.*signals|presence.*lifecycle\.yaml'

Write-Host ""

# =========================================================================
# GROUP P: Temp dir cleaned (static)
# =========================================================================
Write-Host "--- P: Temp dir cleaned (static) ---"

Assert-FileContains "P1: policy instructs cleanup of temp dir" `
    $policyFile '[Cc]lean.*temp|[Rr]emove.*tempDir|tempDir.*after'

Assert-FileContains "P2: agent instructs cleanup of temp clone" `
    $agentFile 'Bereinige.*temporaer|temporaer.*[Cc]lone|[Bb]ereinige.*tempor'

Write-Host ""

# =========================================================================
# GROUP Q: provenance.yaml does NOT overwrite state.yaml or brownfield-baseline
# =========================================================================
Write-Host "--- Q: Brownfield baseline survives provenance write ---"

$fixtureQ = New-FixtureDirectory "Q-baseline-survives"
try {
    New-Item -Path (Join-Path $fixtureQ "App.mpr") -ItemType File -Force | Out-Null

    # Pre-create migration dir with state.yaml
    $migDir = Join-Path $fixtureQ ".mxagile\migration"
    New-Item -Path $migDir -ItemType Directory -Force | Out-Null
    Set-Content -Path (Join-Path $migDir "state.yaml") -Value "status: in_progress`nlast_completed_step: dfc_artifacts_removed" -Encoding UTF8

    # Pre-create state dir with brownfield-baseline.yaml
    $stateDir = Join-Path $fixtureQ ".mxagile\state"
    New-Item -Path $stateDir -ItemType Directory -Force | Out-Null
    Set-Content -Path (Join-Path $stateDir "brownfield-baseline.yaml") -Value "brownfield_baseline: true`nstories_count: 17" -Encoding UTF8

    & $bootstrapScript `
        -ProjectRoot              $fixtureQ `
        -CanonicalSource          $canonicalMxAgile `
        -ProvenanceFlavor         "core" `
        -ProvenanceCoreSource     "https://github.com/Zwergomaniac/MxAgile.git" `
        -ProvenanceCoreSourceType "git" `
        -ProvenanceCoreRef        "main"

    $stateContent = Get-Content -LiteralPath (Join-Path $migDir "state.yaml") -Raw -ErrorAction SilentlyContinue
    Assert-True "Q1: state.yaml preserved (not overwritten by provenance write)" `
        ($stateContent -match 'dfc_artifacts_removed') `
        "state.yaml was overwritten during bootstrap rerun"

    $baselineContent = Get-Content -LiteralPath (Join-Path $stateDir "brownfield-baseline.yaml") -Raw -ErrorAction SilentlyContinue
    Assert-True "Q2: brownfield-baseline.yaml preserved" `
        ($baselineContent -match 'stories_count: 17') `
        "brownfield-baseline.yaml was modified"

    $provenancePath = Join-Path $migDir "provenance.yaml"
    Assert-True "Q3: provenance.yaml was still written" `
        (Test-Path -LiteralPath $provenancePath) `
        "provenance.yaml missing after Q fixture run"

} finally {
    Remove-FixtureDirectory $fixtureQ
}
Write-Host ""

# =========================================================================
# GROUP R,S,T,U: Regression suites
# =========================================================================
Write-Host "--- R,S,T,U: Regression suites ---"

function Invoke-RegressionSuite {
    param([string]$TestName, [string]$ScriptPath)
    if (-not (Test-Path -LiteralPath $ScriptPath)) {
        Assert-True $TestName $false "Regression script not found: $ScriptPath"
        return
    }
    $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $ScriptPath 2>&1
    $exitCode = $LASTEXITCODE
    Assert-True $TestName ($exitCode -eq 0) "Exited with code $exitCode. Last output: $(($output | Select-Object -Last 5) -join ' | ')"
}

Invoke-RegressionSuite "R: test-migration-crash-safety.ps1 passes" `
    (Join-Path $TestsDir "test-migration-crash-safety.ps1")

Invoke-RegressionSuite "S: test-dfc-migration-preflight.ps1 passes" `
    (Join-Path $TestsDir "test-dfc-migration-preflight.ps1")

Invoke-RegressionSuite "T: test-install-bootstrap-regression.ps1 passes" `
    (Join-Path $TestsDir "test-install-bootstrap-regression.ps1")

Invoke-RegressionSuite "U: test-startup-priority.ps1 passes" `
    (Join-Path $TestsDir "test-startup-priority.ps1")

Write-Host ""

# =========================================================================
# Summary
# =========================================================================
Write-Host "=== Migration Provenance Persistence Test Results ==="
Write-Host "  PASS: $PassCount" -ForegroundColor Green
if ($FailCount -gt 0) {
    Write-Host "  FAIL: $FailCount" -ForegroundColor Red
    foreach ($detail in $FailDetails) {
        Write-Host "    $detail" -ForegroundColor Red
    }
    Write-Host ""
    Write-Host "TEST FAILED: Migration provenance persistence contract violated." -ForegroundColor Red
    exit 1
} else {
    Write-Host ""
    Write-Host "TEST PASSED: Migration provenance persistence contract met." -ForegroundColor Green
    exit 0
}
