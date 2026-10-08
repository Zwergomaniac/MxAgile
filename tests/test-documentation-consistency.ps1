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

# M: README does not use the legacy project name
Write-Host ""
Write-Host "TEST M: README does not use legacy project name" -ForegroundColor Cyan
Assert-FileNotContains "M.1 README does not use legacy name MxAi-Dev-System" $ReadMe 'MxAi-Dev-System'

# N: README does not expose internal scripts as user commands
Write-Host ""
Write-Host "TEST N: README does not expose internal scripts as user commands" -ForegroundColor Cyan
Assert-FileNotContains "N.1 README does not tell users to call setup-agent-system.ps1" $ReadMe '(?i)run.*setup-agent-system|setup-agent-system.*to initialize'

# O: README mentions all five lifecycle phases from lifecycle.yaml
Write-Host ""
Write-Host "TEST O: README mentions all five lifecycle phases" -ForegroundColor Cyan
Assert-FileContains "O.1 README mentions discovery phase" $ReadMe '(?i)\bdiscovery\b'
Assert-FileContains "O.2 README mentions refinement phase" $ReadMe '(?i)\brefinement\b'
Assert-FileContains "O.3 README mentions ready phase" $ReadMe '(?i)\bready\b'
Assert-FileContains "O.4 README mentions implementing phase" $ReadMe '(?i)\bimplementing\b'
Assert-FileContains "O.5 README mentions verifying phase" $ReadMe '(?i)\bverifying\b'

# P: Canonical setup scripts exist on disk
Write-Host ""
Write-Host "TEST P: Canonical setup scripts exist on disk" -ForegroundColor Cyan
Assert-True "P.1 mxagile-setup.ps1 exists at root" (Test-Path (Join-Path $ScriptDir "mxagile-setup.ps1")) "mxagile-setup.ps1 not found"
Assert-True "P.2 mxagile-setup-mercedes.ps1 exists at root" (Test-Path (Join-Path $ScriptDir "mxagile-setup-mercedes.ps1")) "mxagile-setup-mercedes.ps1 not found"
Assert-True "P.3 scripts/install-core.ps1 exists" (Test-Path (Join-Path $ScriptDir "scripts/install-core.ps1")) "scripts/install-core.ps1 not found"
Assert-True "P.4 scripts/generate-mxagile-platform-skills.ps1 exists" (Test-Path (Join-Path $ScriptDir "scripts/generate-mxagile-platform-skills.ps1")) "scripts/generate-mxagile-platform-skills.ps1 not found"

# Q: CLAUDE.md does not contain dead MxAi-Dev-System/ link prefix
Write-Host ""
Write-Host "TEST Q: CLAUDE.md has no dead MxAi-Dev-System/ link paths" -ForegroundColor Cyan
$ClaudeMd = Join-Path $ScriptDir "CLAUDE.md"
Assert-FileNotContains "Q.1 CLAUDE.md does not reference MxAi-Dev-System/ path prefix" $ClaudeMd 'MxAi-Dev-System/'

# R: README documents the autonomy model accurately
Write-Host ""
Write-Host "TEST R: README documents autonomy model" -ForegroundColor Cyan
Assert-FileContains "R.1 README mentions operating-mode detection" $ReadMe 'CLOSED-AUTONOM|operating.mode'
Assert-FileContains "R.2 README mentions Terminal-State Guard" $ReadMe 'Terminal-State Guard'
Assert-FileContains "R.3 README mentions durable mission state" $ReadMe 'mission-state'
Assert-FileContains "R.4 README distinguishes local commit from push" $ReadMe '(?i)local commit.*push|push.*authority|commit authority'

# S: README documents the Project/Release Completion Checkpoint
Write-Host ""
Write-Host "TEST S: README documents Project/Release Completion Checkpoint" -ForegroundColor Cyan
Assert-FileContains "S.1 README mentions Project/Release Completion Checkpoint" $ReadMe '(?i)(project.*release.*checkpoint|feature.*scope.*complet)'
Assert-FileContains "S.2 README mentions FEATURE_SCOPE_COMPLETE level" $ReadMe 'FEATURE_SCOPE_COMPLETE'
Assert-FileContains "S.3 README mentions review profiles in non-technical language" $ReadMe '(?i)(Quick Health Check|Integrated Product Review|Release Readiness Review)'
Assert-FileContains "S.4 README mentions checkpoint policy file" $ReadMe 'project-release-checkpoint'

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
