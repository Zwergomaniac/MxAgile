<#
.SYNOPSIS
    Migration Crash-Safety and Correctness Tests

.DESCRIPTION
    Validates crash-safety, state-machine correctness, and PS5.1 copy-promotion
    fixes for the DFC-AI -> MxAgile migration workflow.

    Test groups:
    A  - Static: policy mentions state.yaml
    B  - Classifier: DFC + bootstrap, no state.yaml -> LEGACY_DFC_PROJECT
    C  - Classifier: state.yaml in_progress + DFC still present -> MIGRATION_IN_PROGRESS
    D  - Classifier: state.yaml in_progress + DFC removed, no lifecycle -> MIGRATION_IN_PROGRESS
    E  - Classifier: fresh detection of above state -> MIGRATION_IN_PROGRESS (never CLEAN)
    F  - Classifier: state.yaml + partial .mxagile -> MIGRATION_IN_PROGRESS
    G  - Static: agent mentions writing state.yaml before destructive cleanup
    H  - Copy promotion: skills land at skills/*.md not skills/skills/*.md
    I  - Copy promotion: state/ and migration/ preserved through copy
    J  - State machine: all 5 classifications function correctly
    K  - Classifier: lifecycle.yaml + state.yaml -> EXISTING_MXAGILE_PROJECT
    L  - Classifier: state.yaml removed, lifecycle.yaml present -> EXISTING_MXAGILE_PROJECT
    M  - Static: policy references install-core.ps1, not setup-agent-system directly
    N  - Static: policy requires same enumeration for plan and baseline counts
    O  - Static: state.yaml step-tracking structure is defined in policy
    P  - Output: MigrationEvidence field present in detector output
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

function Assert-FileNotContains {
    param([string]$TestName, [string]$FilePath, [string]$Pattern)
    $content = Get-Content -LiteralPath $FilePath -Raw -ErrorAction SilentlyContinue
    if ($null -eq $content) {
        Assert-True $TestName $false "File not found: $FilePath"
    } else {
        Assert-True $TestName (-not ($content -match $Pattern)) "Pattern '$Pattern' should NOT appear in $FilePath"
    }
}

function Assert-FileAbsent {
    param([string]$TestName, [string]$FilePath)
    Assert-True $TestName (-not (Test-Path -LiteralPath $FilePath)) "Expected absent: $FilePath"
}

function New-FixtureDirectory {
    param([string]$Name)
    $dir = Join-Path $env:TEMP "mxagile-crash-safety-$Name-$([System.Guid]::NewGuid().ToString('N').Substring(0,8))"
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    return $dir
}

function Remove-FixtureDirectory {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path) {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Script / canonical paths
$detectScript    = Join-Path $ScriptDir "scripts\detect-project-type.ps1"
$installScript   = Join-Path $ScriptDir "scripts\install-core.ps1"
$canonicalMxAgile = Join-Path $ScriptDir ".mxagile"
$policyFile      = Join-Path $canonicalMxAgile "policies\migration-dfc-to-mxagile.md"
$agentFile       = Join-Path $canonicalMxAgile "agents\migration-agent.md"

Write-Host ""
Write-Host "=== Migration Crash-Safety and Correctness Tests ==="
Write-Host ""

# =========================================================================
# Infrastructure check
# =========================================================================
Write-Host "--- Infrastructure ---"
Assert-True "detect-project-type.ps1 exists" (Test-Path -LiteralPath $detectScript) "Not found: $detectScript"
Assert-True "install-core.ps1 exists" (Test-Path -LiteralPath $installScript) "Not found: $installScript"
Assert-True "canonical .mxagile/ exists" (Test-Path -LiteralPath $canonicalMxAgile -PathType Container) "Not found: $canonicalMxAgile"
Assert-True "migration policy exists" (Test-Path -LiteralPath $policyFile) "Not found: $policyFile"
Assert-True "migration agent exists" (Test-Path -LiteralPath $agentFile) "Not found: $agentFile"
Write-Host ""

# =========================================================================
# GROUP A: Static policy checks
# =========================================================================
Write-Host "--- A: Static - policy mentions state.yaml ---"

Assert-FileContains "A1: policy mentions state.yaml" `
    $policyFile 'state\.yaml'

Assert-FileContains "A2: policy mentions status: in_progress" `
    $policyFile 'status:.*in_progress|in_progress'

Assert-FileContains "A3: policy mentions MIGRATION_IN_PROGRESS" `
    $policyFile 'MIGRATION_IN_PROGRESS'

Assert-FileContains "A4: policy defines last_completed_step" `
    $policyFile 'last_completed_step'

Assert-FileContains "A5: policy defines steps_completed structure" `
    $policyFile 'steps_completed'

Write-Host ""

# =========================================================================
# GROUP G: Static agent checks
# =========================================================================
Write-Host "--- G: Static - agent mentions state.yaml before destructive cleanup ---"

Assert-FileContains "G1: agent mentions state.yaml" `
    $agentFile 'state\.yaml'

Assert-FileContains "G2: agent mentions writing state.yaml before DFC removal" `
    $agentFile 'state\.yaml.*VOR.*Loeschen|VOR.*Loeschen.*DFC|state\.yaml.*bevor.*loeschen|status: in_progress.*VOR'

Assert-FileContains "G3: agent mentions MIGRATION_IN_PROGRESS" `
    $agentFile 'MIGRATION_IN_PROGRESS'

Assert-FileContains "G4: agent mentions resume semantics" `
    $agentFile 'Resume|resume|Fortsetzen|fortsetzen|letzten.*Schritt|last_completed_step'

Write-Host ""

# =========================================================================
# GROUP M: Static install ordering checks
# =========================================================================
Write-Host "--- M: Static - policy uses install-core.ps1, not setup-agent-system alone ---"

Assert-FileContains "M1: policy references install-core.ps1" `
    $policyFile 'install-core\.ps1'

Assert-FileNotContains "M2: policy does NOT instruct calling setup-agent-system.ps1 as Phase 5 install step" `
    $policyFile "setup-agent-system\.ps1.*-ProjectRoot|& .*setup-agent-system\.ps1.*-ProjectRoot"

Assert-FileContains "M3: policy explains why not to call setup-agent-system directly" `
    $policyFile 'setup-agent-system.*requires|requires.*skills.*exist|internal|internally'

Assert-FileContains "M4: agent references install-core.ps1" `
    $agentFile 'install-core\.ps1'

Assert-FileNotContains "M5: agent does NOT call setup-agent-system directly as install step" `
    $agentFile 'setup-agent-system\.ps1.*-ProjectRoot.*install|Schritt.*setup-agent-system.*direkt'

Write-Host ""

# =========================================================================
# GROUP N: Static count consistency checks
# =========================================================================
Write-Host "--- N: Static - policy requires same enumeration for plan and baseline ---"

Assert-FileContains "N1: policy requires Phase 1 enumeration to be used in Phase 3" `
    $policyFile 'Phase 1.*enumeration|Phase 1.*Zaehlung|same.*enumeration|EXACT.*list|Zaehlung.*Phase'

Assert-FileContains "N2: policy warns against re-enumerating in Phase 3" `
    $policyFile 'NOT.*re-enumerate|NOT.*re-run.*glob|nicht.*neu.*zaehlen|nicht neu zaehlen|KEINE neue Enumeration'

Assert-FileContains "N3: agent requires exact count from Phase 1 inventory" `
    $agentFile 'EXAKT.*Zaehlung|exakt.*zaehlung|Phase 1.*Zaehlung|Ergebnisliste'

Write-Host ""

# =========================================================================
# GROUP O: Static state machine definition check
# =========================================================================
Write-Host "--- O: Static - policy defines state.yaml step-tracking structure ---"

Assert-FileContains "O1: policy defines started_at field" `
    $policyFile 'started_at'

Assert-FileContains "O2: policy defines last_completed_step field" `
    $policyFile 'last_completed_step'

Assert-FileContains "O3: policy includes a YAML template for state.yaml" `
    $policyFile 'status: in_progress'

Assert-FileContains "O4: policy defines status: complete transition" `
    $policyFile 'status: complete'

Write-Host ""

# =========================================================================
# GROUP B: Classifier  -  DFC + bootstrap, no state.yaml -> LEGACY_DFC_PROJECT
# =========================================================================
Write-Host "--- B: Classifier - DFC + bootstrap, no state.yaml -> LEGACY_DFC_PROJECT ---"
$fixtureB = New-FixtureDirectory "B-dfc-no-state"
try {
    New-Item -Path (Join-Path $fixtureB "App.mpr") -ItemType File -Force | Out-Null
    $dfcDir = Join-Path $fixtureB ".dfc-ai"
    New-Item -Path $dfcDir -ItemType Directory -Force | Out-Null
    Set-Content -Path (Join-Path $dfcDir "version.yaml") -Value 'version: "1.0"' -Encoding UTF8
    # Migration bootstrap installed but NO state.yaml
    $migDir = Join-Path $fixtureB ".mxagile\migration"
    New-Item -Path $migDir -ItemType Directory -Force | Out-Null
    Set-Content -Path (Join-Path $migDir "README.md") -Value "# MIGRATION_BOOTSTRAPPED" -Encoding UTF8

    $resultJson = & $detectScript -ProjectRoot $fixtureB
    $result = $resultJson | ConvertFrom-Json

    Assert-True "B1: DFC+bootstrap with no state.yaml -> LEGACY_DFC_PROJECT (not CLEAN)" `
        ($result.Classification -eq "LEGACY_DFC_PROJECT") `
        "Expected LEGACY_DFC_PROJECT, got: $($result.Classification)"

    Assert-True "B2: not misclassified as CLEAN_PROJECT" `
        ($result.Classification -ne "CLEAN_PROJECT") `
        "Was misclassified as CLEAN_PROJECT"
} finally {
    Remove-FixtureDirectory $fixtureB
}
Write-Host ""

# =========================================================================
# GROUP C: Classifier  -  state.yaml in_progress + DFC still present -> MIGRATION_IN_PROGRESS
# =========================================================================
Write-Host "--- C: Classifier - state.yaml in_progress + DFC still present -> MIGRATION_IN_PROGRESS ---"
$fixtureC = New-FixtureDirectory "C-state-dfc"
try {
    New-Item -Path (Join-Path $fixtureC "App.mpr") -ItemType File -Force | Out-Null
    # DFC still present
    $dfcDir = Join-Path $fixtureC ".dfc-ai"
    New-Item -Path $dfcDir -ItemType Directory -Force | Out-Null
    Set-Content -Path (Join-Path $dfcDir "version.yaml") -Value 'version: "1.0"' -Encoding UTF8
    # state.yaml written
    $migDir = Join-Path $fixtureC ".mxagile\migration"
    New-Item -Path $migDir -ItemType Directory -Force | Out-Null
    Set-Content -Path (Join-Path $migDir "state.yaml") -Value "status: in_progress`nstarted_at: 2026-09-22T10:00:00Z`nlast_completed_step: baseline_written" -Encoding UTF8

    $resultJson = & $detectScript -ProjectRoot $fixtureC
    $result = $resultJson | ConvertFrom-Json

    Assert-True "C1: state.yaml in_progress + DFC present -> MIGRATION_IN_PROGRESS" `
        ($result.Classification -eq "MIGRATION_IN_PROGRESS") `
        "Expected MIGRATION_IN_PROGRESS, got: $($result.Classification)"

    Assert-True "C2: not misclassified as LEGACY_DFC_PROJECT" `
        ($result.Classification -ne "LEGACY_DFC_PROJECT") `
        "Was misclassified as LEGACY_DFC_PROJECT"
} finally {
    Remove-FixtureDirectory $fixtureC
}
Write-Host ""

# =========================================================================
# GROUP D: Classifier  -  state.yaml in_progress + DFC removed, no lifecycle.yaml -> MIGRATION_IN_PROGRESS
# =========================================================================
Write-Host "--- D: Classifier - state.yaml in_progress + DFC removed, no lifecycle -> MIGRATION_IN_PROGRESS ---"
$fixtureD = New-FixtureDirectory "D-state-nodfc"
try {
    New-Item -Path (Join-Path $fixtureD "App.mpr") -ItemType File -Force | Out-Null
    # DFC removed (not present)
    # No lifecycle.yaml (installation not complete)
    $migDir = Join-Path $fixtureD ".mxagile\migration"
    New-Item -Path $migDir -ItemType Directory -Force | Out-Null
    Set-Content -Path (Join-Path $migDir "state.yaml") -Value "status: in_progress`nstarted_at: 2026-09-22T10:00:00Z`nlast_completed_step: dfc_artifacts_removed" -Encoding UTF8

    $resultJson = & $detectScript -ProjectRoot $fixtureD
    $result = $resultJson | ConvertFrom-Json

    Assert-True "D1: state.yaml in_progress + DFC gone + no lifecycle -> MIGRATION_IN_PROGRESS" `
        ($result.Classification -eq "MIGRATION_IN_PROGRESS") `
        "Expected MIGRATION_IN_PROGRESS, got: $($result.Classification)"

    Assert-True "D2: never misclassified as CLEAN_PROJECT (crash window)" `
        ($result.Classification -ne "CLEAN_PROJECT") `
        "Was misclassified as CLEAN_PROJECT  -  crash-safety invariant violated"

    Assert-True "D3: never misclassified as LEGACY_DFC_PROJECT" `
        ($result.Classification -ne "LEGACY_DFC_PROJECT") `
        "Was misclassified as LEGACY_DFC_PROJECT"
} finally {
    Remove-FixtureDirectory $fixtureD
}
Write-Host ""

# =========================================================================
# GROUP E: Classifier  -  fresh detection of MIGRATION_IN_PROGRESS state
# =========================================================================
Write-Host "--- E: Classifier - fresh detection of state.yaml -> MIGRATION_IN_PROGRESS ---"
$fixtureE = New-FixtureDirectory "E-fresh-mip"
try {
    New-Item -Path (Join-Path $fixtureE "App.mpr") -ItemType File -Force | Out-Null
    New-Item -Path (Join-Path $fixtureE ".mxagile\migration") -ItemType Directory -Force | Out-Null
    Set-Content -Path (Join-Path $fixtureE ".mxagile\migration\state.yaml") -Value "status: in_progress`nlast_completed_step: baseline_written" -Encoding UTF8

    $resultJson = & $detectScript -ProjectRoot $fixtureE
    $result = $resultJson | ConvertFrom-Json

    Assert-True "E1: fresh detection with state.yaml -> MIGRATION_IN_PROGRESS" `
        ($result.Classification -eq "MIGRATION_IN_PROGRESS") `
        "Expected MIGRATION_IN_PROGRESS, got: $($result.Classification)"
} finally {
    Remove-FixtureDirectory $fixtureE
}
Write-Host ""

# =========================================================================
# GROUP F: Classifier  -  state.yaml + partial .mxagile (no lifecycle.yaml) -> MIGRATION_IN_PROGRESS
# =========================================================================
Write-Host "--- F: Classifier - state.yaml + partial .mxagile -> MIGRATION_IN_PROGRESS ---"
$fixtureF = New-FixtureDirectory "F-partial-mxagile"
try {
    New-Item -Path (Join-Path $fixtureF "App.mpr") -ItemType File -Force | Out-Null
    # .mxagile exists but no lifecycle.yaml
    New-Item -Path (Join-Path $fixtureF ".mxagile\skills") -ItemType Directory -Force | Out-Null
    New-Item -Path (Join-Path $fixtureF ".mxagile\agents") -ItemType Directory -Force | Out-Null
    New-Item -Path (Join-Path $fixtureF ".mxagile\migration") -ItemType Directory -Force | Out-Null
    Set-Content -Path (Join-Path $fixtureF ".mxagile\migration\state.yaml") -Value "status: in_progress`nlast_completed_step: mxagile_payload_copying" -Encoding UTF8

    $resultJson = & $detectScript -ProjectRoot $fixtureF
    $result = $resultJson | ConvertFrom-Json

    Assert-True "F1: partial .mxagile + state.yaml -> MIGRATION_IN_PROGRESS (not CLEAN)" `
        ($result.Classification -eq "MIGRATION_IN_PROGRESS") `
        "Expected MIGRATION_IN_PROGRESS, got: $($result.Classification)"
} finally {
    Remove-FixtureDirectory $fixtureF
}
Write-Host ""

# =========================================================================
# GROUP K: Classifier  -  lifecycle.yaml + state.yaml -> EXISTING_MXAGILE_PROJECT
# =========================================================================
Write-Host "--- K: Classifier - lifecycle.yaml + state.yaml -> EXISTING_MXAGILE_PROJECT ---"
$fixtureK = New-FixtureDirectory "K-lifecycle-state"
try {
    New-Item -Path (Join-Path $fixtureK "App.mpr") -ItemType File -Force | Out-Null
    New-Item -Path (Join-Path $fixtureK ".mxagile") -ItemType Directory -Force | Out-Null
    Set-Content -Path (Join-Path $fixtureK ".mxagile\lifecycle.yaml") -Value "version: 1" -Encoding UTF8
    New-Item -Path (Join-Path $fixtureK ".mxagile\migration") -ItemType Directory -Force | Out-Null
    Set-Content -Path (Join-Path $fixtureK ".mxagile\migration\state.yaml") -Value "status: in_progress`nlast_completed_step: mxagile_installed" -Encoding UTF8

    $resultJson = & $detectScript -ProjectRoot $fixtureK
    $result = $resultJson | ConvertFrom-Json

    Assert-True "K1: lifecycle.yaml + state.yaml -> EXISTING_MXAGILE_PROJECT (lifecycle wins)" `
        ($result.Classification -eq "EXISTING_MXAGILE_PROJECT") `
        "Expected EXISTING_MXAGILE_PROJECT, got: $($result.Classification)"
} finally {
    Remove-FixtureDirectory $fixtureK
}
Write-Host ""

# =========================================================================
# GROUP L: Classifier  -  state.yaml removed, lifecycle.yaml present -> EXISTING_MXAGILE_PROJECT
# =========================================================================
Write-Host "--- L: Classifier - no state.yaml, lifecycle.yaml present -> EXISTING_MXAGILE_PROJECT ---"
$fixtureL = New-FixtureDirectory "L-no-state-lifecycle"
try {
    New-Item -Path (Join-Path $fixtureL "App.mpr") -ItemType File -Force | Out-Null
    New-Item -Path (Join-Path $fixtureL ".mxagile") -ItemType Directory -Force | Out-Null
    Set-Content -Path (Join-Path $fixtureL ".mxagile\lifecycle.yaml") -Value "version: 1" -Encoding UTF8
    # No state.yaml

    $resultJson = & $detectScript -ProjectRoot $fixtureL
    $result = $resultJson | ConvertFrom-Json

    Assert-True "L1: lifecycle.yaml only -> EXISTING_MXAGILE_PROJECT" `
        ($result.Classification -eq "EXISTING_MXAGILE_PROJECT") `
        "Expected EXISTING_MXAGILE_PROJECT, got: $($result.Classification)"
} finally {
    Remove-FixtureDirectory $fixtureL
}
Write-Host ""

# =========================================================================
# GROUP J: All 5 classifications work correctly
# =========================================================================
Write-Host "--- J: State machine - all 5 classifications ---"

# J1: CLEAN_PROJECT (already tested implicitly in other test suites; quick re-check)
$fixtureJ1 = New-FixtureDirectory "J1-clean"
try {
    New-Item -Path (Join-Path $fixtureJ1 "App.mpr") -ItemType File -Force | Out-Null
    $r = (& $detectScript -ProjectRoot $fixtureJ1 | ConvertFrom-Json)
    Assert-True "J1: no markers -> CLEAN_PROJECT" ($r.Classification -eq "CLEAN_PROJECT") "Got: $($r.Classification)"
} finally {
    Remove-FixtureDirectory $fixtureJ1
}

# J2: LEGACY_DFC_PROJECT
$fixtureJ2 = New-FixtureDirectory "J2-legacy"
try {
    New-Item -Path (Join-Path $fixtureJ2 "App.mpr") -ItemType File -Force | Out-Null
    New-Item -Path (Join-Path $fixtureJ2 ".dfc-ai") -ItemType Directory -Force | Out-Null
    Set-Content -Path (Join-Path $fixtureJ2 ".dfc-ai\version.yaml") -Value 'version: "1.0"' -Encoding UTF8
    $r = (& $detectScript -ProjectRoot $fixtureJ2 | ConvertFrom-Json)
    Assert-True "J2: .dfc-ai only -> LEGACY_DFC_PROJECT" ($r.Classification -eq "LEGACY_DFC_PROJECT") "Got: $($r.Classification)"
} finally {
    Remove-FixtureDirectory $fixtureJ2
}

# J3: MIGRATION_IN_PROGRESS
$fixtureJ3 = New-FixtureDirectory "J3-mip"
try {
    New-Item -Path (Join-Path $fixtureJ3 "App.mpr") -ItemType File -Force | Out-Null
    New-Item -Path (Join-Path $fixtureJ3 ".mxagile\migration") -ItemType Directory -Force | Out-Null
    Set-Content -Path (Join-Path $fixtureJ3 ".mxagile\migration\state.yaml") -Value "status: in_progress" -Encoding UTF8
    $r = (& $detectScript -ProjectRoot $fixtureJ3 | ConvertFrom-Json)
    Assert-True "J3: state.yaml in_progress -> MIGRATION_IN_PROGRESS" ($r.Classification -eq "MIGRATION_IN_PROGRESS") "Got: $($r.Classification)"
} finally {
    Remove-FixtureDirectory $fixtureJ3
}

# J4: EXISTING_MXAGILE_PROJECT
$fixtureJ4 = New-FixtureDirectory "J4-existing"
try {
    New-Item -Path (Join-Path $fixtureJ4 "App.mpr") -ItemType File -Force | Out-Null
    New-Item -Path (Join-Path $fixtureJ4 ".mxagile") -ItemType Directory -Force | Out-Null
    Set-Content -Path (Join-Path $fixtureJ4 ".mxagile\lifecycle.yaml") -Value "version: 1" -Encoding UTF8
    $r = (& $detectScript -ProjectRoot $fixtureJ4 | ConvertFrom-Json)
    Assert-True "J4: lifecycle.yaml -> EXISTING_MXAGILE_PROJECT" ($r.Classification -eq "EXISTING_MXAGILE_PROJECT") "Got: $($r.Classification)"
} finally {
    Remove-FixtureDirectory $fixtureJ4
}

# J5: AMBIGUOUS
$fixtureJ5 = New-FixtureDirectory "J5-ambiguous"
try {
    New-Item -Path (Join-Path $fixtureJ5 "App.mpr") -ItemType File -Force | Out-Null
    New-Item -Path (Join-Path $fixtureJ5 ".dfc-ai") -ItemType Directory -Force | Out-Null
    Set-Content -Path (Join-Path $fixtureJ5 ".dfc-ai\version.yaml") -Value 'version: "1.0"' -Encoding UTF8
    New-Item -Path (Join-Path $fixtureJ5 ".mxagile") -ItemType Directory -Force | Out-Null
    Set-Content -Path (Join-Path $fixtureJ5 ".mxagile\lifecycle.yaml") -Value "version: 1" -Encoding UTF8
    $r = (& $detectScript -ProjectRoot $fixtureJ5 | ConvertFrom-Json)
    Assert-True "J5: DFC + lifecycle.yaml -> AMBIGUOUS" ($r.Classification -eq "AMBIGUOUS") "Got: $($r.Classification)"
} finally {
    Remove-FixtureDirectory $fixtureJ5
}
Write-Host ""

# =========================================================================
# GROUP P: MigrationEvidence field in detector output
# =========================================================================
Write-Host "--- P: MigrationEvidence field in output ---"
$fixtureP = New-FixtureDirectory "P-evidence"
try {
    New-Item -Path (Join-Path $fixtureP "App.mpr") -ItemType File -Force | Out-Null
    New-Item -Path (Join-Path $fixtureP ".mxagile\migration") -ItemType Directory -Force | Out-Null
    Set-Content -Path (Join-Path $fixtureP ".mxagile\migration\state.yaml") -Value "status: in_progress" -Encoding UTF8

    $resultJson = & $detectScript -ProjectRoot $fixtureP
    $result = $resultJson | ConvertFrom-Json

    Assert-True "P1: MigrationEvidence field exists in JSON output" `
        ($null -ne $result.MigrationEvidence) `
        "MigrationEvidence field missing from JSON output"

    $migEv = @($result.MigrationEvidence)
    Assert-True "P2: MigrationEvidence is non-empty when state.yaml present" `
        ($migEv.Count -gt 0) `
        "MigrationEvidence should be non-empty when state.yaml has status: in_progress"

    Assert-True "P3: MigrationEvidence references state.yaml" `
        (($migEv | Where-Object { $_ -match 'state\.yaml' }) -ne $null) `
        "MigrationEvidence does not mention state.yaml: $($migEv -join ', ')"
} finally {
    Remove-FixtureDirectory $fixtureP
}
Write-Host ""

# =========================================================================
# GROUP H: Copy promotion - PS5.1 nesting bug fix
# =========================================================================
Write-Host "--- H: Copy promotion - skills land at skills/*.md not skills/skills/*.md ---"
$fixtureH = New-FixtureDirectory "H-copy-promotion"
try {
    # Simulate canonical source
    $fakeCanonical = Join-Path $fixtureH "canonical-mxagile"
    New-Item -Path (Join-Path $fakeCanonical "skills") -ItemType Directory -Force | Out-Null
    New-Item -Path (Join-Path $fakeCanonical "agents") -ItemType Directory -Force | Out-Null
    Set-Content -Path (Join-Path $fakeCanonical "skills\discovery.md") -Value "# Discovery skill" -Encoding UTF8
    Set-Content -Path (Join-Path $fakeCanonical "skills\refinement.md") -Value "# Refinement skill" -Encoding UTF8
    Set-Content -Path (Join-Path $fakeCanonical "agents\discovery-agent.md") -Value "# Agent" -Encoding UTF8
    Set-Content -Path (Join-Path $fakeCanonical "lifecycle.yaml") -Value "version: 1" -Encoding UTF8

    # Simulate project dest with pre-existing empty skills/ (as mxagile-init.ps1 creates it)
    $destMxAgile = Join-Path $fixtureH "dest-mxagile"
    New-Item -Path (Join-Path $destMxAgile "skills") -ItemType Directory -Force | Out-Null   # pre-existing empty dir
    New-Item -Path (Join-Path $destMxAgile "migration") -ItemType Directory -Force | Out-Null
    Set-Content -Path (Join-Path $destMxAgile "migration\state.yaml") -Value "status: in_progress" -Encoding UTF8

    # Execute the content-merge copy logic (matches the fix in install-core.ps1)
    Get-ChildItem -LiteralPath $fakeCanonical -Exclude "layers", "state" | ForEach-Object {
        if ($_.PSIsContainer) {
            $destSubDir = Join-Path $destMxAgile $_.Name
            if (-not (Test-Path -LiteralPath $destSubDir -PathType Container)) {
                New-Item -ItemType Directory -Path $destSubDir -Force | Out-Null
            }
            Copy-Item -Path "$($_.FullName)\*" -Destination $destSubDir -Recurse -Force
        } else {
            Copy-Item -LiteralPath $_.FullName -Destination $destMxAgile -Force
        }
    }

    # H: Skills must land directly under skills/, not nested skills/skills/
    Assert-True "H1: skills/discovery.md at correct path (not nested)" `
        (Test-Path -LiteralPath (Join-Path $destMxAgile "skills\discovery.md")) `
        "skills/discovery.md not found at correct path"

    Assert-True "H2: skills/refinement.md at correct path (not nested)" `
        (Test-Path -LiteralPath (Join-Path $destMxAgile "skills\refinement.md")) `
        "skills/refinement.md not found at correct path"

    Assert-FileAbsent "H3: NO skills/skills/ double-nesting (PS5.1 bug absent)" `
        (Join-Path $destMxAgile "skills\skills")

    Assert-True "H4: lifecycle.yaml installed at root of dest" `
        (Test-Path -LiteralPath (Join-Path $destMxAgile "lifecycle.yaml")) `
        "lifecycle.yaml not installed"

    Assert-True "H5: agents/discovery-agent.md installed" `
        (Test-Path -LiteralPath (Join-Path $destMxAgile "agents\discovery-agent.md")) `
        "agents/discovery-agent.md not installed"

} finally {
    Remove-FixtureDirectory $fixtureH
}
Write-Host ""

# =========================================================================
# GROUP I: Copy promotion - state/ and migration/ preserved
# =========================================================================
Write-Host "--- I: Copy promotion - state/ and migration/ preserved through copy ---"
$fixtureI = New-FixtureDirectory "I-preservation"
try {
    # Canonical source with skills and agents but NO state/ or migration/
    $fakeCanonical = Join-Path $fixtureI "canonical-mxagile"
    New-Item -Path (Join-Path $fakeCanonical "skills") -ItemType Directory -Force | Out-Null
    Set-Content -Path (Join-Path $fakeCanonical "skills\skill.md") -Value "# Skill" -Encoding UTF8
    Set-Content -Path (Join-Path $fakeCanonical "lifecycle.yaml") -Value "version: 1" -Encoding UTF8

    # Project dest with brownfield-baseline.yaml and migration/state.yaml pre-existing
    $destMxAgile = Join-Path $fixtureI "dest-mxagile"
    New-Item -Path (Join-Path $destMxAgile "state") -ItemType Directory -Force | Out-Null
    Set-Content -Path (Join-Path $destMxAgile "state\brownfield-baseline.yaml") -Value "brownfield_baseline: true`nstories_count: 42" -Encoding UTF8
    New-Item -Path (Join-Path $destMxAgile "migration") -ItemType Directory -Force | Out-Null
    Set-Content -Path (Join-Path $destMxAgile "migration\state.yaml") -Value "status: in_progress`nlast_completed_step: dfc_artifacts_removed" -Encoding UTF8
    Set-Content -Path (Join-Path $destMxAgile "migration\policy.md") -Value "# Policy copy" -Encoding UTF8

    # Execute copy (matches the fix; 'state' excluded)
    Get-ChildItem -LiteralPath $fakeCanonical -Exclude "layers", "state" | ForEach-Object {
        if ($_.PSIsContainer) {
            $destSubDir = Join-Path $destMxAgile $_.Name
            if (-not (Test-Path -LiteralPath $destSubDir -PathType Container)) {
                New-Item -ItemType Directory -Path $destSubDir -Force | Out-Null
            }
            Copy-Item -Path "$($_.FullName)\*" -Destination $destSubDir -Recurse -Force
        } else {
            Copy-Item -LiteralPath $_.FullName -Destination $destMxAgile -Force
        }
    }

    # I: state/ preserved (state is excluded from canonical copy)
    Assert-True "I1: state/brownfield-baseline.yaml preserved after copy" `
        (Test-Path -LiteralPath (Join-Path $destMxAgile "state\brownfield-baseline.yaml")) `
        "brownfield-baseline.yaml was removed during copy"

    $baselineContent = Get-Content -LiteralPath (Join-Path $destMxAgile "state\brownfield-baseline.yaml") -Raw
    Assert-True "I2: brownfield-baseline.yaml content intact (stories_count preserved)" `
        ($baselineContent -match 'stories_count: 42') `
        "brownfield-baseline.yaml content was modified"

    # I: migration/ preserved (migration/ does not exist in canonical source)
    Assert-True "I3: migration/state.yaml preserved after copy" `
        (Test-Path -LiteralPath (Join-Path $destMxAgile "migration\state.yaml")) `
        "migration/state.yaml was removed during copy"

    $stateContent = Get-Content -LiteralPath (Join-Path $destMxAgile "migration\state.yaml") -Raw
    Assert-True "I4: migration/state.yaml content intact (last_completed_step preserved)" `
        ($stateContent -match 'dfc_artifacts_removed') `
        "migration/state.yaml content was modified"

    Assert-True "I5: migration/policy.md preserved after copy" `
        (Test-Path -LiteralPath (Join-Path $destMxAgile "migration\policy.md")) `
        "migration/policy.md was removed during copy"

    # Also verify canonical skills DID land correctly
    Assert-True "I6: skills/skill.md was installed (canonical copy worked)" `
        (Test-Path -LiteralPath (Join-Path $destMxAgile "skills\skill.md")) `
        "skills/skill.md was not installed"

} finally {
    Remove-FixtureDirectory $fixtureI
}
Write-Host ""

# =========================================================================
# install-core.ps1 static checks  -  MIGRATION_IN_PROGRESS handling
# =========================================================================
Write-Host "--- install-core.ps1 static checks ---"

Assert-FileContains "install-core: handles MIGRATION_IN_PROGRESS classification" `
    $installScript 'MIGRATION_IN_PROGRESS'

Assert-FileContains "install-core: prints resuming-migration message" `
    $installScript 'Resuming migration|resuming migration'

Assert-FileContains "install-core: uses content-merge copy (PSIsContainer check)" `
    $installScript 'PSIsContainer'

Assert-FileContains "install-core: creates destSubDir before copy" `
    $installScript 'destSubDir'

Assert-FileContains "install-core: uses wildcard copy to avoid PS5.1 nesting" `
    $installScript 'Copy-Item.*-Path.*\\\*.*-Destination.*destSubDir'

Write-Host ""

# =========================================================================
# Summary
# =========================================================================
Write-Host "=== Migration Crash-Safety Test Results ==="
Write-Host "  PASS: $PassCount" -ForegroundColor Green
if ($FailCount -gt 0) {
    Write-Host "  FAIL: $FailCount" -ForegroundColor Red
    foreach ($detail in $FailDetails) {
        Write-Host "    $detail" -ForegroundColor Red
    }
    Write-Host ""
    Write-Host "TEST FAILED: Migration crash-safety contract violated." -ForegroundColor Red
    exit 1
} else {
    Write-Host ""
    Write-Host "TEST PASSED: Migration crash-safety and correctness contract met." -ForegroundColor Green
    exit 0
}
