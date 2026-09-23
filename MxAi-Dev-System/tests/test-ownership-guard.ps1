<#
.SYNOPSIS
    Ownership Guard and Framework Request Routing Tests

.DESCRIPTION
    Validates the FRAMEWORK_CHANGE classification rule, consumer project ownership
    contract, system-check lifecycle guidance, and mxcli init provenance mechanism.
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
    else { Assert-True $TestName ($content -notmatch $Pattern) "Forbidden pattern '$Pattern' in $FilePath" }
}

$OwnerPol    = Join-Path $ScriptDir ".mxagile/policies/ownership-guard.md"
$Orchestrator= Join-Path $ScriptDir ".mxagile/orchestrator.md"
$SysCheck    = Join-Path $ScriptDir ".mxagile/skills/system-check.md"
$InstCore    = Join-Path $ScriptDir "scripts/install-core.ps1"

# TEST A: FRAMEWORK_CHANGE is classified before any action
Write-Host ""
Write-Host "TEST A: FRAMEWORK_CHANGE classification happens before any action" -ForegroundColor Cyan
Assert-FileContains "A.1 ownership-guard.md defines FRAMEWORK_CHANGE classification" $OwnerPol 'FRAMEWORK_CHANGE Classification'
Assert-FileContains "A.2 orchestrator.md has FRAMEWORK_CHANGE as first startup check" $Orchestrator 'FRAMEWORK_CHANGE Detection.*ERSTES'
Assert-FileContains "A.3 orchestrator.md checks workspace type before proceeding" $Orchestrator 'Consumer-Projekt.*NICHT veraendern'

# TEST B: Consumer project agent does not patch installed .mxagile/
Write-Host ""
Write-Host "TEST B: Consumer project agent must not patch installed .mxagile/" -ForegroundColor Cyan
Assert-FileContains "B.1 ownership-guard.md prohibits editing .mxagile/policies/" $OwnerPol 'FRAMEWORK_OWNED.*NO'
Assert-FileContains "B.2 ownership-guard.md prohibits editing .mxagile/agents/" $OwnerPol '\.mxagile/agents'
Assert-FileContains "B.3 installed .mxagile/ is described as framework-owned projection" $OwnerPol 'installed projection'

# TEST C: Framework dev workspace can make framework changes
Write-Host ""
Write-Host "TEST C: Framework dev workspace can make framework changes" -ForegroundColor Cyan
Assert-FileContains "C.1 ownership-guard.md defines framework workspace detection" $OwnerPol 'Framework Workspace Detection'
Assert-FileContains "C.2 framework dev workspace: normal development rules apply" $OwnerPol 'normale Framework-Entwicklungsregeln gelten|normal framework development rules apply'

# TEST D: Project-owned artifacts can still be modified in consumer project
Write-Host ""
Write-Host "TEST D: Project-owned artifacts may still be modified in consumer project" -ForegroundColor Cyan
Assert-FileContains "D.1 requirements/ is PROJECT_OWNED and may be modified" $OwnerPol 'requirements.*PROJECT_OWNED.*YES'
Assert-FileContains "D.2 specs/ is PROJECT_OWNED and may be modified" $OwnerPol 'specs.*PROJECT_OWNED.*YES'
Assert-FileContains "D.3 planning/lifecycle/ is PROJECT_OWNED and may be modified" $OwnerPol 'planning/lifecycle.*PROJECT_OWNED.*YES'

# TEST E: User instruction does not override ownership
Write-Host ""
Write-Host "TEST E: User instruction does not override ownership classification" -ForegroundColor Cyan
Assert-FileContains "E.1 ownership-guard.md states user instruction does not override" $OwnerPol 'User Instruction Does Not Override'
Assert-FileContains "E.2 improve installer example given as prohibited action" $OwnerPol 'installer|reconciliation policy'

# TEST F: Installed .mxagile/ is not treated as editable source
Write-Host ""
Write-Host "TEST F: Installed .mxagile/ is not editable source in consumer project" -ForegroundColor Cyan
Assert-FileContains "F.1 core invariant states installed Core = framework-owned projection" $OwnerPol 'Core Invariant'
Assert-FileContains "F.2 orchestrator.md references ownership-guard.md" $Orchestrator 'ownership-guard.md'

# TEST G: mxcli init provenance marker written after successful init
Write-Host ""
Write-Host "TEST G: mxcli init provenance marker written after successful initialization" -ForegroundColor Cyan
Assert-FileContains "G.1 install-core.ps1 defines provenance file path" $InstCore 'mxcli-init.txt'
Assert-FileContains "G.2 install-core.ps1 writes provenance after successful mxcli init" $InstCore 'provenance.*written|WriteAllText.*mxcli-init'
Assert-FileContains "G.3 provenance file written with mxcli version and date" $InstCore 'mxcli_version'

# TEST H: Provenance marker used for UPDATE skip check (not just arbitrary file existence)
Write-Host ""
Write-Host "TEST H: Provenance marker used for UPDATE skip check" -ForegroundColor Cyan
Assert-FileContains "H.1 install-core.ps1 checks for provenance file" $InstCore 'provenanceExists'
Assert-FileContains "H.2 provenance-based check preferred over file-existence fallback" $InstCore 'prefer provenance marker over bare file existence'
Assert-FileContains "H.3 fallback documented when provenance absent" $InstCore 'Fall back.*provenance file is absent'

# TEST I: System check detects lifecycle re-sync need after Core UPDATE
Write-Host ""
Write-Host "TEST I: System check detects lifecycle re-sync state" -ForegroundColor Cyan
Assert-FileContains "I.1 system-check.md has Lifecycle State section" $SysCheck 'Lifecycle State and Reconciliation Detection'
Assert-FileContains "I.2 system-check reads planning/lifecycle/process-state.yaml" $SysCheck 'planning/lifecycle/process-state.yaml'
Assert-FileContains "I.3 system-check detects legacy .concord/scratch location" $SysCheck 'concord.*scratch.*process-state'
Assert-FileContains "I.4 system-check detects legacy artifacts (planning/stories/, sprints/decisions.md)" $SysCheck 'planning/stories'

# TEST J: System check outputs required next lifecycle actions
Write-Host ""
Write-Host "TEST J: System check outputs required next lifecycle actions" -ForegroundColor Cyan
Assert-FileContains "J.1 system-check Next Steps section derives specific actions" $SysCheck 'required_actions'
Assert-FileContains "J.2 system-check handles lifecycle re-sync resume" $SysCheck 'Lifecycle re-sync.*currently at Wave'
Assert-FileContains "J.3 system-check handles evidence gaps" $SysCheck 'Evidence gaps found'
Assert-FileContains "J.4 machine-readable YAML includes lifecycle_state" $SysCheck 'lifecycle_state:'

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
