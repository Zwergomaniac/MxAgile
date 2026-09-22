<#
.SYNOPSIS
    Migration Lifecycle Re-Sync and False-Completion Prevention Tests

.DESCRIPTION
    Validates the lifecycle re-sync contract, MIGRATION_IN_PROGRESS routing gate,
    completion authority, interrupt/resume semantics, hybrid-state preservation,
    framework migration boundary, and durable step model.

    Architecture under test (OPTION A -- Hybrid Preservation):
    - Framework migration PRESERVES legacy project artifacts at original locations.
    - planning/stories/REQ-*.md and planning/checklists/ are NOT moved during migration.
    - Artifact canonicalization (legacy .md -> canonical .yml) is a SEPARATE lifecycle.
    - Stale-reference rewrites do NOT occur during framework migration.
    - build_artifact_index.py scans requirements/*.yml -- relocating .md files without
      format conversion would create an unindexable half-state (rejected).

    Test groups:
    A  - MIGRATION_IN_PROGRESS + "continue" -> migration resumes, normal lifecycle blocked
    B  - MIGRATION_IN_PROGRESS + "what is the current state" -> migration state authoritative
    C  - MIGRATION_IN_PROGRESS + "what to work on" -> remaining migration steps identified first
    D  - Prior message says "complete" + repo says in_progress -> repository wins
    E  - Sub-step completion wording is scoped (no overall-complete claim on sub-step)
    F  - DFC cleanup / MxAgile install sub-step wording is explicitly scoped
    G  - Successful final validation -> overall migration may be reported complete
    H  - MIGRATION_IN_PROGRESS blocks normal requirement implementation
    I  - Durable step: baseline_written -> resume at Phase 4 DFC Cleanup (no Phase 3.5)
    J  - Durable step: dfc_artifacts_removed -> resume at Phase 5
    K  - Durable step: mxagile_installed -> resume at Phase 6 (validation)
    L  - Mercedes provenance -> resumed migration remains Mercedes
    M  - Framework migration does NOT perform stale-reference path rewrites
    N  - Legacy artifacts preserved at original locations (not relocated during migration)
    O  - Artifact canonicalization is a separate lifecycle
    P  - Brownfield baseline records original artifact locations
    Q  - Brownfield baseline and planning content remain intact
    R  - No historical MxAgile lifecycle gates fabricated
    S  - Regression: test-migration-crash-safety.ps1 passes
    T  - Regression: test-migration-provenance.ps1 passes
    U  - Regression: test-dfc-migration-preflight.ps1 passes
    V  - Regression: test-startup-priority.ps1 passes
    W  - Regression: test-install-bootstrap-regression.ps1 passes
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

$policyFile = Join-Path $ScriptDir ".mxagile\policies\migration-dfc-to-mxagile.md"
$agentFile  = Join-Path $ScriptDir ".mxagile\agents\migration-agent.md"

Write-Host ""
Write-Host "=== Migration Lifecycle Re-Sync Tests ==="
Write-Host ""

Assert-True "policy file exists" (Test-Path -LiteralPath $policyFile) "Not found: $policyFile"
Assert-True "agent file exists"  (Test-Path -LiteralPath $agentFile)  "Not found: $agentFile"
Write-Host ""

# ===========================================================================
# GROUP A: MIGRATION_IN_PROGRESS + "continue" -> migration resumes, normal lifecycle blocked
# ===========================================================================
Write-Host "--- A: MIGRATION_IN_PROGRESS blocks normal lifecycle on continue ---"

Assert-Contains "A1: agent defines global re-sync as first action" `
    $agentFile 'GLOBALE LIFECYCLE RE-SYNC|Global.*Lifecycle.*Re-Sync'

Assert-Contains "A2: agent re-sync runs on 'continue'" `
    $agentFile 'continue|weiter'

Assert-Contains "A3: policy defines MIGRATION_IN_PROGRESS hard gate" `
    $policyFile 'MIGRATION_IN_PROGRESS.*Hard.*Routing.*Gate|Hard Routing Gate'

Assert-Contains "A4: policy states normal project lifecycle must not begin during migration" `
    $policyFile 'enter normal MxAgile project lifecycle|Do NOT.*normal project work|DO NOT enter normal project lifecycle'

Assert-Contains "A5: policy explicitly blocks wave/task/requirement implementation" `
    $policyFile 'wave.*task.*requirement.*implementation|requirement.*implementation.*MUST NOT|start.*wave.*task'

Write-Host ""

# ===========================================================================
# GROUP B: MIGRATION_IN_PROGRESS + "current state" -> migration state authoritative
# ===========================================================================
Write-Host "--- B: Migration state is authoritative on state inquiry ---"

Assert-Contains "B1: policy defines handling of 'current state' question" `
    $policyFile 'current.*state|What.*current.*state|current project state'

Assert-Contains "B2: policy response includes last completed step and next step" `
    $policyFile 'last.*completed.*step|last_completed_step'

Assert-Contains "B3: agent handles state query via re-sync first" `
    $agentFile 'Was ist der aktuelle Stand|current.*state|Resume.*Verhalten'

Write-Host ""

# ===========================================================================
# GROUP C: MIGRATION_IN_PROGRESS + "what to work on" -> migration steps before project tasks
# ===========================================================================
Write-Host "--- C: 'What to work on' identifies migration steps first ---"

Assert-Contains "C1: policy routing table covers 'what to work on next'" `
    $policyFile 'What should.*work.*on|work.*on.*next|remaining migration step'

Assert-Contains "C2: agent blocks normal project work during migration" `
    $agentFile 'normale Projektarbeit.*nicht|normalen.*MxAgile.*Lifecycle.*beginnt nicht'

Assert-Contains "C3: policy instruction table maps 'work on next' to remaining migration steps" `
    $policyFile 'remaining migration step|next migration step'

Write-Host ""

# ===========================================================================
# GROUP D: Prior "migration complete" claim + in_progress repo state -> repository wins
# ===========================================================================
Write-Host "--- D: Repository state overrides conversational claims ---"

Assert-Contains "D1: policy states conversational history is not authoritative" `
    $policyFile 'Conversational History Is Not Authoritative|conversational.*not.*authoritative'

Assert-Contains "D2: policy says to correct prior statement and resume" `
    $policyFile 'Acknowledge.*incorrect|incorrect.*prior.*statement|Korrigiere.*falsche|correct.*false'

Assert-Contains "D3: agent states repo truth overrides conversational assumptions" `
    $agentFile 'Repository-Wahrheit.*ueberschreibt|Repository.*wins|nicht autoritativ'

Assert-Contains "D4: agent explicitly handles prior 'Migration complete' with in_progress state" `
    $agentFile 'Migration complete.*in_progress|in_progress.*Migration complete|Korrigiere die falsche Aussage'

Write-Host ""

# ===========================================================================
# GROUP E: Sub-step completion is not overall completion
# ===========================================================================
Write-Host "--- E: Sub-step completion is not overall completion ---"

Assert-Contains "E1: policy sub-step wording rule: scoped language required" `
    $policyFile 'Sub-step.*completion.*MUST|sub-step.*scoped|scoped.*language'

Assert-Contains "E2: policy states overall complete requires validation_passed" `
    $policyFile 'validation_passed'

Assert-Contains "E3: policy states 'Migration complete' only after Phase 6 validation" `
    $policyFile '"Migration complete".*Phase 6|only.*after.*validation|Only.*after.*ALL'

Write-Host ""

# ===========================================================================
# GROUP F: DFC cleanup / MxAgile install sub-step wording is scoped
# ===========================================================================
Write-Host "--- F: Sub-step completion wording is scoped ---"

Assert-Contains "F1: policy shows DFC cleanup scoped wording CORRECT example" `
    $policyFile 'CORRECT.*DFC artifacts removed|DFC.*removed.*Next.*MxAgile installation'

Assert-Contains "F2: policy marks sub-step wording WRONG example for overall completion" `
    $policyFile 'WRONG.*Migration complete'

Assert-Contains "F3: agent prohibits 'Migration abgeschlossen' after sub-step" `
    $agentFile 'Migration abgeschlossen.*wenn nur.*Sub-Schritt|sub-step.*not.*Migration.*complete|Sub-Schritt.*nicht.*gesamt'

Write-Host ""

# ===========================================================================
# GROUP G: Completion requires validation_passed
# ===========================================================================
Write-Host "--- G: Completion requires validation_passed ---"

Assert-Contains "G1: policy defines completion authority with required conditions" `
    $policyFile 'Completion Authority|completion.*authority'

Assert-Contains "G2: policy requires detect-project-type to return EXISTING_MXAGILE_PROJECT" `
    $policyFile 'EXISTING_MXAGILE_PROJECT'

Assert-Contains "G3: policy requires validation_passed before status: complete" `
    $policyFile 'validation_passed.*status.*complete|after.*validation_passed'

Assert-Contains "G4: agent defers 'Migration complete' to step 14 (after validation)" `
    $agentFile 'Melde Migration.*abgeschlossen.*erst jetzt|erst jetzt.*nach Schritt|Only now.*after'

Write-Host ""

# ===========================================================================
# GROUP H: MIGRATION_IN_PROGRESS blocks normal requirement implementation
# ===========================================================================
Write-Host "--- H: MIGRATION_IN_PROGRESS blocks REQ implementation ---"

Assert-Contains "H1: policy routing table explicitly handles 'Implement REQ-xxx'" `
    $policyFile 'Implement REQ|REQ.*Refuse|refuse.*MIGRATION_IN_PROGRESS'

Assert-Contains "H2: policy states gate applies even when requirements are readable" `
    $policyFile 'project requirements are readable|requirements.*readable'

Assert-Contains "H3: agent safety rule 8 blocks normal work" `
    $agentFile 'MIGRATION_IN_PROGRESS blockiert normale Projektarbeit|Sicherheitsregel.*8|Regel 8'

Write-Host ""

# ===========================================================================
# GROUP I: Durable step: baseline_written -> resume at Phase 4 (no Phase 3.5 intermediary)
# ===========================================================================
Write-Host "--- I: Durable step: baseline_written resumes at Phase 4 DFC Cleanup ---"

Assert-Contains "I1: agent resume table maps baseline_written to Phase 4 DFC Cleanup" `
    $agentFile 'baseline_written.*Phase 4|baseline_written.*DFC'

Assert-NotContains "I2: agent resume table does NOT map baseline_written to Phase 3.5" `
    $agentFile 'baseline_written.*Phase 3\.5|baseline_written.*Artifact Relocation'

Assert-NotContains "I3: milestone table does NOT contain planning_artifacts_relocated" `
    $agentFile 'planning_artifacts_relocated'

Write-Host ""

# ===========================================================================
# GROUP J: Durable step: dfc_artifacts_removed -> resume at Phase 5
# ===========================================================================
Write-Host "--- J: Durable step: dfc_artifacts_removed ---"

Assert-Contains "J1: policy defines dfc_artifacts_removed as step milestone" `
    $policyFile 'dfc_artifacts_removed'

Assert-Contains "J2: agent resume table maps dfc_artifacts_removed to Phase 5" `
    $agentFile 'dfc_artifacts_removed.*Phase 5|dfc_artifacts_removed.*MxAgile Installation'

Write-Host ""

# ===========================================================================
# GROUP K: Durable step: mxagile_installed -> resume at Phase 6 (validation)
# ===========================================================================
Write-Host "--- K: Durable step: mxagile_installed ---"

Assert-Contains "K1: policy defines mxagile_installed as step milestone" `
    $policyFile 'mxagile_installed'

Assert-Contains "K2: agent resume table maps mxagile_installed to Phase 6 (validation)" `
    $agentFile 'mxagile_installed.*Phase 6|mxagile_installed.*Validierung'

Write-Host ""

# ===========================================================================
# GROUP L: Mercedes provenance -> resumed migration remains Mercedes
# ===========================================================================
Write-Host "--- L: Mercedes provenance preserved through resume ---"

Assert-Contains "L1: policy requires flavor integrity check in completion authority" `
    $policyFile 'Flavor integrity|flavor.*mercedes.*Company Layer'

Assert-Contains "L2: policy completion authority blocks downgrade from Mercedes to core-only" `
    $policyFile '[Dd]owngrade.*[Cc]ore|[Mm]ercedes.*[Cc]ore.*only|[Cc]ore-only'

Assert-Contains "L3: policy Phase 7 validation checks Mercedes Company Layer is installed" `
    $policyFile 'flavor.*mercedes.*Company Layer.*installed|Mercedes.*Company Layer'

Write-Host ""

# ===========================================================================
# GROUP M: Framework migration does NOT rewrite stale path references
# ===========================================================================
Write-Host "--- M: No stale path reference rewrites during framework migration ---"

Assert-Contains "M1: policy explicitly states stale-ref rewrites are NOT performed during framework migration" `
    $policyFile 'Stale-reference rewrites.*NOT performed|stale.*path.*reference.*NOT|not.*rewrite.*path.*reference'

Assert-Contains "M2: policy states path references remain valid because files have not moved" `
    $policyFile 'reference.*paths remain valid|remain valid because.*files have not moved|paths.*remain valid'

Assert-Contains "M3: policy states stale-ref rewrites belong to canonicalization lifecycle not framework migration" `
    $policyFile 'Reference rewriting.*canonicalization|reference.*rewriting.*separate'

Write-Host ""

# ===========================================================================
# GROUP N: Legacy artifacts preserved at original locations (not relocated)
# ===========================================================================
Write-Host "--- N: Legacy artifacts preserved at original locations ---"

Assert-Contains "N1: policy explicitly states legacy artifacts remain at original DFC-AI locations" `
    $policyFile 'remain at their original locations|Preserved in place|original.*DFC-AI locations'

Assert-Contains "N2: policy explicitly names planning/stories/ as preserved in place" `
    $policyFile 'planning/stories/.*Preserved in place|Preserved in place.*planning/stories/'

Assert-Contains "N3: policy explicitly names planning/checklists/ as preserved in place" `
    $policyFile 'planning/checklists/.*Preserved in place|Preserved in place.*planning/checklists/'

Assert-NotContains "N4: policy does NOT contain Phase 3.5 artifact relocation instruction" `
    $policyFile '5\.1.*Relocate requirements stories|Relocate requirements stories|Copy each.*planning/stories.*to requirements'

Assert-NotContains "N5: agent does NOT instruct to move planning/stories/ files" `
    $agentFile 'planning/stories.*->.*requirements/|Relocate.*planning/stories'

Write-Host ""

# ===========================================================================
# GROUP O: Artifact canonicalization is a separate lifecycle
# ===========================================================================
Write-Host "--- O: Artifact canonicalization is a separate lifecycle ---"

Assert-Contains "O1: policy explicitly states canonicalization is a separate lifecycle" `
    $policyFile 'separate.*lifecycle|canonicalization.*separate|Artifact canonicalization is a separate'

Assert-Contains "O2: policy names migrate-stories.ps1 as canonicalization tool (not migration tool)" `
    $policyFile 'migrate-stories\.ps1'

Assert-Contains "O3: agent confirms artifact canonicalization is a separate lifecycle" `
    $agentFile 'Artefakt-Kanonisierung ist ein SEPARATER Lifecycle|separater.*Lifecycle|separate.*Lifecycle'

Write-Host ""

# ===========================================================================
# GROUP P: Brownfield baseline records original artifact locations
# ===========================================================================
Write-Host "--- P: Brownfield baseline records original artifact locations ---"

Assert-Contains "P1: policy brownfield baseline template records stories_location field" `
    $policyFile 'stories_location.*planning/stories/'

Assert-Contains "P2: policy brownfield baseline template records checklists_location field" `
    $policyFile 'checklists_location.*planning/checklists/'

Assert-Contains "P3: policy brownfield baseline template records artifact_canonicalization pending" `
    $policyFile 'artifact_canonicalization.*pending'

Write-Host ""

# ===========================================================================
# GROUP Q: Brownfield baseline preserved; planning artifacts intact after validation
# ===========================================================================
Write-Host "--- Q: Brownfield baseline and original artifact content preserved ---"

Assert-Contains "Q1: policy Phase 6 validation verifies planning/stories/ still exists (not relocated)" `
    $policyFile 'planning/stories/.*still exists|planning/stories.*NOT relocated|planning/stories.*hybrid state'

Assert-Contains "Q2: policy Phase 6 validation verifies planning/checklists/ still exists (not relocated)" `
    $policyFile 'planning/checklists/.*still exists|planning/checklists.*NOT relocated|planning/checklists.*hybrid state'

Assert-Contains "Q3: policy validation Phase 6 verifies brownfield-baseline exists" `
    $policyFile 'brownfield-baseline\.yaml.*exists.*intact|brownfield.*baseline.*intact'

Write-Host ""

# ===========================================================================
# GROUP R: No historical MxAgile lifecycle gates fabricated
# ===========================================================================
Write-Host "--- R: No fabricated MxAgile lifecycle history ---"

Assert-Contains "R1: policy states do not claim MxAgile phase history" `
    $policyFile 'Do NOT claim MxAgile phase history|not.*claim.*MxAgile.*phase'

Assert-Contains "R2: agent rule 3 prohibits fabricated lifecycle" `
    $agentFile 'Kein fabrizierter Lifecycle|fabrizierter|fabricated.*Lifecycle'

Assert-Contains "R3: policy brownfield note is starting point, not history" `
    $policyFile 'No MxAgile lifecycle phases were performed historically|starting point'

Write-Host ""

# ===========================================================================
# GROUPS S-W: Regression suites
# ===========================================================================
Write-Host "--- S,T,U,V,W: Regression suites ---"

Invoke-RegressionSuite "S: test-migration-crash-safety.ps1 passes" `
    (Join-Path $TestsDir "test-migration-crash-safety.ps1")

Invoke-RegressionSuite "T: test-migration-provenance.ps1 passes" `
    (Join-Path $TestsDir "test-migration-provenance.ps1")

Invoke-RegressionSuite "U: test-dfc-migration-preflight.ps1 passes" `
    (Join-Path $TestsDir "test-dfc-migration-preflight.ps1")

Invoke-RegressionSuite "V: test-startup-priority.ps1 passes" `
    (Join-Path $TestsDir "test-startup-priority.ps1")

Invoke-RegressionSuite "W: test-install-bootstrap-regression.ps1 passes" `
    (Join-Path $TestsDir "test-install-bootstrap-regression.ps1")

Write-Host ""

# ===========================================================================
# Summary
# ===========================================================================
Write-Host "=== Migration Lifecycle Re-Sync Test Results ==="
Write-Host "  PASS: $PassCount" -ForegroundColor Green
if ($FailCount -gt 0) {
    Write-Host "  FAIL: $FailCount" -ForegroundColor Red
    foreach ($detail in $FailDetails) {
        Write-Host "    $detail" -ForegroundColor Red
    }
    Write-Host ""
    Write-Host "TEST FAILED: Migration lifecycle re-sync contract violated." -ForegroundColor Red
    exit 1
} else {
    Write-Host ""
    Write-Host "TEST PASSED: Migration lifecycle re-sync contract met." -ForegroundColor Green
    exit 0
}
