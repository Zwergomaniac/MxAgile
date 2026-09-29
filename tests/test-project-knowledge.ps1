<#
.SYNOPSIS
    Project Knowledge Contract Tests: A through K

.DESCRIPTION
    Validates canonical artifact locations, Git-tracking contract, screenshot lifecycle,
    evidence manifest, gitignore contract, and fresh clone collaboration guarantee.

    Tests A through K.
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
    if ($null -eq $content) { Assert-True $TestName $false "File not found: $FilePath" }
    else { Assert-True $TestName ($content -match $Pattern) "Pattern '$Pattern' not found in $FilePath" }
}
function Assert-FileNotContains {
    param([string]$TestName, [string]$FilePath, [string]$Pattern)
    $content = Get-Content -LiteralPath $FilePath -Raw -ErrorAction SilentlyContinue
    if ($null -eq $content) { Assert-True $TestName $false "File not found: $FilePath" }
    else { Assert-True $TestName ($content -notmatch $Pattern) "Forbidden pattern '$Pattern' found in $FilePath" }
}

$KnowPol   = Join-Path $ScriptDir ".mxagile/policies/project-knowledge.md"
$EvPol     = Join-Path $ScriptDir ".mxagile/policies/evidence-contract.md"
$ParityPol = Join-Path $ScriptDir ".mxagile/policies/ui-parity.md"
$EvSchema  = Join-Path $ScriptDir ".mxagile/schemas/evidence-manifest.schema.json"
$GitIgnore = Join-Path $ScriptDir ".gitignore"

# A: Source mockup is Git-trackable canonical project knowledge
Write-Host ""
Write-Host "TEST A: Source mockup is Git-trackable canonical project knowledge" -ForegroundColor Cyan
Assert-FileContains "A.1 project-knowledge.md defines source mockups as CANONICAL" $KnowPol 'Source mockups'
Assert-FileContains "A.2 source mockups path is input-resources/ui-ux" $KnowPol 'input-resources/ui-ux'
Assert-FileContains "A.3 project-knowledge.md states source mockups are git-tracked" $KnowPol 'YES.*IMMUTABLE.*Discovery'
Assert-FileNotContains "A.4 .gitignore does not ignore input-resources" $GitIgnore 'input-resources'

# B: Refined target mockup is Git-trackable canonical project knowledge
Write-Host ""
Write-Host "TEST B: Refined target mockup is Git-trackable canonical project knowledge" -ForegroundColor Cyan
Assert-FileContains "B.1 project-knowledge.md defines target mockups as CANONICAL" $KnowPol 'planning/target-mockups'
Assert-FileContains "B.2 target mockups are git-tracked" $KnowPol 'Refined target mockups'
Assert-FileNotContains "B.3 .gitignore does not ignore planning" $GitIgnore '^planning/'

# C: Requirements/Specs/Tasks remain Git-trackable
Write-Host ""
Write-Host "TEST C: Requirements/Specs/Tasks remain Git-trackable" -ForegroundColor Cyan
Assert-FileContains "C.1 project-knowledge.md defines Requirements location" $KnowPol 'requirements/'
Assert-FileContains "C.2 project-knowledge.md defines Specs location" $KnowPol 'specs/'
Assert-FileContains "C.3 project-knowledge.md defines Tasks location" $KnowPol 'planning/tasks'
Assert-FileContains "C.4 project-knowledge.md states artifacts must be versioned project state" $KnowPol 'versioned project state'

# D: Canonical parity report is Git-trackable
Write-Host ""
Write-Host "TEST D: Canonical parity report is Git-trackable" -ForegroundColor Cyan
Assert-FileContains "D.1 project-knowledge.md defines parity reports in planning/parity" $KnowPol 'planning/parity'
Assert-FileContains "D.2 ui-parity.md outputs parity to planning/parity" $ParityPol 'planning/parity'
Assert-FileNotContains "D.3 .gitignore does not ignore planning/parity" $GitIgnore 'planning/parity'

# E: Promoted screenshot evidence is Git-trackable
Write-Host ""
Write-Host "TEST E: Promoted screenshot evidence is Git-trackable" -ForegroundColor Cyan
Assert-FileContains "E.1 project-knowledge.md defines promoted screenshots path" $KnowPol 'planning/evidence/screenshots'
Assert-FileContains "E.2 evidence-contract.md defines promotion to planning/evidence" $EvPol 'planning/evidence/screenshots'
Assert-FileNotContains "E.3 .gitignore does not ignore planning/evidence" $GitIgnore 'planning/evidence'

# F: Temporary Playwright screenshot remains ephemeral
Write-Host ""
Write-Host "TEST F: Temporary Playwright screenshot remains ephemeral (gitignored)" -ForegroundColor Cyan
Assert-FileContains "F.1 .gitignore ignores .concord directory" $GitIgnore '\.concord'
Assert-FileContains "F.2 evidence-contract.md states .concord is gitignored" $EvPol '\.concord.*gitignored'
Assert-FileContains "F.3 project-knowledge.md classifies .concord as TEMPORARY/ephemeral" $KnowPol '\.concord.*NO.*Ephemeral'

# G: Promoted evidence remains discoverable after fresh lifecycle re-sync
Write-Host ""
Write-Host "TEST G: Promoted evidence remains discoverable after fresh lifecycle re-sync" -ForegroundColor Cyan
Assert-FileContains "G.1 project-knowledge.md defines fresh clone collaboration test" $KnowPol 'Fresh Clone Collaboration Test'
Assert-FileContains "G.2 promoted screenshots in planning/ survive re-sync" $KnowPol 'planning/evidence'
Assert-FileContains "G.3 parity reports in planning/ survive re-sync" $KnowPol 'planning/parity'

# H: Evidence manifest resolves screenshot to scenario
Write-Host ""
Write-Host "TEST H: Evidence manifest resolves screenshot to scenario" -ForegroundColor Cyan
Assert-FileContains "H.1 evidence-manifest schema has scenario_id per entry" $EvSchema 'scenario_id'
Assert-FileContains "H.2 evidence-manifest schema has artifact path per entry" $EvSchema '"path"'
Assert-FileContains "H.3 evidence-contract.md defines manifest as canonical index" $EvPol 'Evidence Manifest'
Assert-FileContains "H.4 manifest maps requirement to scenario to evidence" $EvPol 'Requirement.*acceptance clause|Traceability Chain'

# I: Ignored scratch cannot become the only storage location for accepted findings
Write-Host ""
Write-Host "TEST I: Ignored scratch cannot become the only storage for accepted findings" -ForegroundColor Cyan
Assert-FileContains "I.1 project-knowledge.md prohibits scratch-only accepted findings" $KnowPol 'only in agent scratch|Scratch must not'
Assert-FileContains "I.2 evidence-contract.md states unpromoted evidence is not collaboration-ready" $EvPol 'no collaboration value'

# J: Secrets remain excluded from Git
Write-Host ""
Write-Host "TEST J: Secrets remain excluded from Git" -ForegroundColor Cyan
Assert-FileContains "J.1 .gitignore comment references secrets/credentials" $GitIgnore 'secrets|credential'
Assert-FileContains "J.2 project-knowledge.md classifies secrets as NEVER git-tracked" $KnowPol 'SECRET.*NEVER|\.env\.mendix.*NEVER'

# K: Fresh clone retains all non-secret evidence needed to understand current UI state
Write-Host ""
Write-Host "TEST K: Fresh clone retains all non-secret evidence to understand current UI state" -ForegroundColor Cyan
Assert-FileContains "K.1 project-knowledge.md defines what fresh clone can reconstruct" $KnowPol 'reconstruct'
Assert-FileContains "K.2 source mockups reconstructable from fresh clone" $KnowPol 'Find source mockups'
Assert-FileContains "K.3 parity reports reconstructable from fresh clone" $KnowPol 'Understand current parity state'
Assert-FileContains "K.4 evidence manifest reconstructable from fresh clone" $KnowPol 'Trace a parity finding'

# ---------------------------------------------------------------------------
$total = $PassCount + $FailCount
Write-Host ""
Write-Host "=" * 60
Write-Host "RESULTS: $PassCount passed, $FailCount failed out of $total tests"
if ($FailCount -gt 0) {
    Write-Host ""
    Write-Host "FAILURES:" -ForegroundColor Red
    $FailDetails | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    exit 1
} else {
    Write-Host "All tests PASSED" -ForegroundColor Green
    exit 0
}
