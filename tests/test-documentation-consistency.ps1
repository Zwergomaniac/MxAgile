<#
.SYNOPSIS
    Documentation Consistency Tests: A through L

.DESCRIPTION
    Validates that framework documentation accurately represents current contracts.
    Checks for stale references, missing reconciliation concepts, and documentation
    consistency across README, installation guide, and agent instructions.

    Tests A through L.
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

$ReadMe      = Join-Path $ScriptDir "README.md"
$InstallDoc  = Join-Path $ScriptDir "docs/installation.md"
$ReconPol    = Join-Path $ScriptDir ".mxagile/policies/reconciliation.md"
$KnowPol     = Join-Path $ScriptDir ".mxagile/policies/project-knowledge.md"
$UiParityPol = Join-Path $ScriptDir ".mxagile/policies/ui-parity.md"
$MockupLife  = Join-Path $ScriptDir ".mxagile/policies/mockup-lifecycle.md"
$EvPol       = Join-Path $ScriptDir ".mxagile/policies/evidence-contract.md"

# A: Current public setup/update entrypoints documented
Write-Host ""
Write-Host "TEST A: Current public setup/update entrypoints documented" -ForegroundColor Cyan
Assert-FileContains "A.1 README documents mxagile-setup.ps1 as canonical" $ReadMe 'mxagile-setup\.ps1'
Assert-FileContains "A.2 README documents mxagile-setup-mercedes.ps1 as canonical" $ReadMe 'mxagile-setup-mercedes\.ps1'
Assert-FileContains "A.3 installation.md documents mxagile-setup.ps1" $InstallDoc 'mxagile-setup\.ps1'

# B: Removed active installer names are not taught as current entrypoints
Write-Host ""
Write-Host "TEST B: Deprecated installers not taught as current entrypoints" -ForegroundColor Cyan
Assert-FileNotContains "B.1 README does not list install-mxagile.ps1 as canonical" $ReadMe 'install-mxagile\.ps1.*canonical|canonical.*install-mxagile'
Assert-FileContains "B.2 README marks install-mxagile.ps1 as deprecated" $ReadMe 'deprecated.*install-mxagile|install-mxagile.*deprecated'
Assert-FileContains "B.3 installation.md marks install-mxagile.ps1 as Deprecated" $InstallDoc '(?i)deprecated.*install-mxagile|install-mxagile.*deprecated'

# C: Discovery Reconciliation documented for existing projects
Write-Host ""
Write-Host "TEST C: Discovery Reconciliation documented" -ForegroundColor Cyan
Assert-FileContains "C.1 reconciliation.md defines Discovery Reconciliation" $ReconPol 'Discovery Reconciliation Contract'
Assert-FileContains "C.2 Discovery Reconciliation does NOT restart from scratch" $ReconPol 'Does existing Discovery rerun.*NO'
Assert-FileContains "C.3 README explains Discovery Reconciliation" $ReadMe 'Discovery Reconciliation'

# D: Refinement Reconciliation documented for existing projects
Write-Host ""
Write-Host "TEST D: Refinement Reconciliation documented" -ForegroundColor Cyan
Assert-FileContains "D.1 reconciliation.md defines Refinement Reconciliation" $ReconPol 'Refinement Reconciliation Contract'
Assert-FileContains "D.2 Refinement Reconciliation does NOT restart from scratch" $ReconPol 'Does existing Refinement rerun.*NO'
Assert-FileContains "D.3 README explains Refinement Reconciliation" $ReadMe 'Refinement Reconciliation'

# E: Full Reconciliation uses conservative evidence reuse
Write-Host ""
Write-Host "TEST E: Full Reconciliation defined as conservative evidence reuse" -ForegroundColor Cyan
Assert-FileContains "E.1 ui-parity.md defines full reconciliation as full scope accounting" $UiParityPol 'FULL SCOPE ACCOUNTING'
Assert-FileContains "E.2 ui-parity.md lists REUSABLE classification" $UiParityPol 'REUSABLE'
Assert-FileContains "E.3 reconciliation.md preserves full reconciliation semantics" $ReconPol 'CONSERVATIVE EVIDENCE REUSE'
Assert-FileContains "E.4 README explains full reconciliation as conservative" $ReadMe 'conservative evidence reuse'

# F: README points to current canonical project locations
Write-Host ""
Write-Host "TEST F: README documents canonical project locations" -ForegroundColor Cyan
Assert-FileContains "F.1 README documents requirements location" $ReadMe 'requirements/'
Assert-FileContains "F.2 README documents specs location" $ReadMe 'specs/'
Assert-FileContains "F.3 README documents planning/tasks location" $ReadMe 'planning/'
Assert-FileContains "F.4 README documents planning/parity as parity reports location" $ReadMe 'planning/parity'
Assert-FileContains "F.5 README documents planning/evidence as promoted screenshots location" $ReadMe 'planning/evidence'

# G: Source vs refined target mockup distinction is documented
Write-Host ""
Write-Host "TEST G: Source vs refined target mockup distinction documented" -ForegroundColor Cyan
Assert-FileContains "G.1 mockup-lifecycle.md defines source mockup as immutable" $MockupLife 'IMMUTABLE'
Assert-FileContains "G.2 mockup-lifecycle.md defines refined target mockup" $MockupLife 'active acceptance target'
Assert-FileContains "G.3 README references source and target mockups" $ReadMe 'source mockups|target mockup'

# H: Promoted screenshot/evidence location is documented as Git tracked
Write-Host ""
Write-Host "TEST H: Promoted screenshot/evidence location documented as Git tracked" -ForegroundColor Cyan
Assert-FileContains "H.1 evidence-contract.md states planning/evidence is canonical" $EvPol 'planning/evidence/screenshots.*canonical|canonical.*planning/evidence'
Assert-FileContains "H.2 project-knowledge.md lists planning/evidence as YES git tracked" $KnowPol 'planning/evidence.*YES'
Assert-FileContains "H.3 README states promoted screenshots are in planning/evidence" $ReadMe 'planning/evidence/screenshots'

# I: Temporary artifacts are documented as non-canonical
Write-Host ""
Write-Host "TEST I: Temporary artifacts documented as non-canonical" -ForegroundColor Cyan
Assert-FileContains "I.1 project-knowledge.md classifies .concord as TEMPORARY" $KnowPol '\.concord.*Ephemeral'
Assert-FileContains "I.2 README states .concord is gitignored/temporary" $ReadMe '\.concord.*gitignored|gitignored.*concord'
Assert-FileContains "I.3 evidence-contract.md states .concord screenshots are temporary" $EvPol '\.concord.*gitignored'

# J: Secrets documented as non-versioned
Write-Host ""
Write-Host "TEST J: Secrets documented as non-versioned" -ForegroundColor Cyan
Assert-FileContains "J.1 project-knowledge.md classifies secrets as NEVER git tracked" $KnowPol 'SECRET.*NEVER'
Assert-FileContains "J.2 README warns about .env.mendix not to be committed" $ReadMe '\.env\.mendix.*secret|secret.*\.env\.mendix|never.*committed'

# K: Generated agent projections derive from canonical sources
Write-Host ""
Write-Host "TEST K: Generated projections derive from canonical sources" -ForegroundColor Cyan
Assert-FileContains "K.1 README instructs to regenerate after changing .mxagile sources" $ReadMe 'generate-mxagile-platform-skills'
Assert-FileContains "K.2 project-knowledge.md classifies projections as GENERATED" $KnowPol 'GENERATED.*projections|projections.*GENERATED'

# L: Obsolete DFC-AI paths not described as active MxAgile paths
Write-Host ""
Write-Host "TEST L: Obsolete DFC-AI paths not described as active MxAgile paths" -ForegroundColor Cyan
Assert-FileNotContains "L.1 README does not recommend mxagile-refine.ps1 as active command" $ReadMe 'mxagile-refine\.ps1'
Assert-FileNotContains "L.2 README does not recommend mxagile-init.ps1 as active command" $ReadMe 'mxagile-init\.ps1'
Assert-FileNotContains "L.3 README does not recommend mxagile-check-quality.ps1 as active command" $ReadMe 'mxagile-check-quality\.ps1'
Assert-FileNotContains "L.4 installation.md does not recommend mxagile-refine.ps1 as active command" $InstallDoc 'mxagile-refine\.ps1'

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
