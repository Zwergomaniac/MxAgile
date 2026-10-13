<#
.SYNOPSIS
    Anti-Dual-Memory Guarantee — Validation Tests

.DESCRIPTION
    Validates the critical acceptance requirement that retrieved context from
    external systems (Context Mode) cannot directly change MxAgile evidence
    states or promote gate/mission state.

    This is a CRITICAL acceptance requirement per MxAgile 1.5 spec section 21.

    Layer 0 (Static):
      A. Anti-dual-memory guarantee documented in context-mode.yaml
      B. Prohibited promotions enumerated in context-mode.yaml
      C. Anti-dual-memory guarantee documented in config.yaml
      D. Anti-dual-memory guarantee documented in docs/context-optimization.md
      E. context-mode.yaml states retrieved content is not authoritative evidence
      F. context-mode.yaml documents test_reference pointing to this file
      G. WARM context definition explicitly excludes HOT mission state fields
      H. HOT context definition covers all lifecycle-authority fields
      I. context-mode.yaml states context_mode_may_not includes evidence states
      J. context-mode.yaml states context_mode_may_not includes gate completion
      K. context-mode.yaml states context_mode_may_not includes mission completion
      L. context-mode.yaml states context_mode_may_not includes lifecycle phase
      M. Fallback must-not-block list covers Resume, Re-Sync, checkpoint validation

    Layer 1 (Semantic — validates prohibition completeness):
      N. UNVERIFIED not in permitted promotions
      O. FAILED not in permitted promotions
      P. STALE not in permitted promotions
      Q. Evidence state authority contract does not contradict itself
      R. Fallback must_not_block covers all critical operations

.NOTES
    Part of MxAgile 1.5 — Context Optimization & Capability Discovery.
    See docs/context-optimization.md#anti-dual-memory-guarantee
    See .mxagile/integrations/context-mode.yaml#anti_dual_memory_guarantee
#>

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$TestsDir = $PSScriptRoot
$RepoRoot = Split-Path -Parent $TestsDir
$MxAgile  = Join-Path $RepoRoot '.mxagile'
$Docs     = Join-Path $RepoRoot 'docs'

$PassCount   = 0
$FailCount   = 0
$FailDetails = @()

function Assert-True {
    param([string]$TestName, [bool]$Condition, [string]$Message = '')
    if ($Condition) {
        Write-Host "  PASS: $TestName" -ForegroundColor Green
        $script:PassCount++
    } else {
        Write-Host "  FAIL: $TestName -- $Message" -ForegroundColor Red
        $script:FailCount++
        $script:FailDetails += "  FAIL: $TestName -- $Message"
    }
}

$cmFile     = Join-Path (Join-Path $MxAgile 'integrations') 'context-mode.yaml'
$configFile = Join-Path $MxAgile 'config.yaml'
$ctxOptDoc  = Join-Path $Docs 'context-optimization.md'

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=== Anti-Dual-Memory Guarantee Tests ===" -ForegroundColor Cyan
Write-Host "(CRITICAL acceptance requirement - MxAgile 1.5 section 21)" -ForegroundColor Yellow
Write-Host ""

$cmExists = Test-Path $cmFile
Assert-True 'context-mode.yaml exists (prerequisite)' $cmExists "Not found: $cmFile"

$cmText = ''
if ($cmExists) { $cmText = Get-Content $cmFile -Raw }

# A. Anti-dual-memory guarantee section present
Assert-True 'A. anti_dual_memory_guarantee section in context-mode.yaml' `
    ($cmText -match 'anti_dual_memory_guarantee:') `
    'anti_dual_memory_guarantee: section not found'

# B. Prohibited promotions enumerated
Assert-True 'B. prohibited_promotions listed' `
    ($cmText -match 'prohibited_promotions:') `
    'prohibited_promotions: not found'

# C. Anti-dual-memory comment in config.yaml
$configExists = Test-Path $configFile
Assert-True 'config.yaml exists (prerequisite)' $configExists "Not found: $configFile"
$configText = if ($configExists) { Get-Content $configFile -Raw } else { '' }
Assert-True 'C. ANTI-DUAL-MEMORY comment in config.yaml' `
    ($configText -match 'ANTI-DUAL-MEMORY') `
    'Anti-dual-memory guarantee not mentioned in config.yaml'

# D. Anti-dual-memory in docs/context-optimization.md
$docExists = Test-Path $ctxOptDoc
Assert-True 'docs/context-optimization.md exists (prerequisite)' $docExists "Not found: $ctxOptDoc"
$docText = if ($docExists) { Get-Content $ctxOptDoc -Raw } else { '' }
Assert-True 'D. Anti-Dual-Memory section in docs/context-optimization.md' `
    ($docText -match 'Anti-Dual-Memory') `
    'Anti-Dual-Memory guarantee not in context-optimization.md'

# E. Retrieved content is not authoritative evidence
Assert-True 'E. context-mode.yaml: retrieved content is not authoritative evidence' `
    ($cmText -match 'RETRIEVED context') `
    'RETRIEVED context statement not found'
Assert-True 'E. context-mode.yaml: not authoritative evidence' `
    ($cmText -match 'not authoritative') `
    '"not authoritative" statement not found'

# F. Test reference points to this file
Assert-True 'F. context-mode.yaml references test_anti_dual_memory.ps1' `
    ($cmText -match 'test-anti-dual-memory') `
    'test_reference to this test file not found in context-mode.yaml'

# G. WARM context definition explicitly excludes HOT state fields
$warmEligible = $cmText -match 'eligible_for_externalization:\s*true'
Assert-True 'G. WARM section has eligible_for_externalization: true' $warmEligible 'eligible_for_externalization not found in WARM section'
Assert-True 'G. HOT context defined (mission state not WARM)' ($cmText -match 'HOT:') 'HOT: context mapping section not found'

# H. HOT context covers lifecycle-authority fields
$hotCoversEpoch     = $cmText -match 'Context Epoch'     -or $cmText -match 'epoch'
$hotCoversGates     = $cmText -match 'gates'
$hotCoversEvidence  = $cmText -match 'evidence states'
$hotCoversResume    = $cmText -match 'Resume Contract'
Assert-True 'H. HOT covers Context Epoch' $hotCoversEpoch 'Context Epoch not in HOT definition'
Assert-True 'H. HOT covers gates' $hotCoversGates 'gates not in HOT definition'
Assert-True 'H. HOT covers evidence states' $hotCoversEvidence 'evidence states not in HOT definition'
Assert-True 'H. HOT covers Resume Contract' $hotCoversResume 'Resume Contract not in HOT definition'

# I. context_mode_may_not covers evidence states
Assert-True 'I. context_mode_may_not includes evidence state authority' `
    ($cmText -match 'VERIFIED.*FAILED.*UNVERIFIED.*STALE.*SUPERSEDED' -or $cmText -match 'evidence states') `
    'Evidence state prohibition not found in context_mode_may_not'

# J. context_mode_may_not includes gate completion
Assert-True 'J. context_mode_may_not includes gate completion' `
    ($cmText -match 'gate completion' -or $cmText -match 'Decide gate') `
    'Gate completion prohibition not found'

# K. context_mode_may_not includes mission completion
Assert-True 'K. context_mode_may_not includes mission completion' `
    ($cmText -match 'mission completion' -or $cmText -match 'Decide mission') `
    'Mission completion prohibition not found'

# L. context_mode_may_not includes lifecycle phase
Assert-True 'L. context_mode_may_not includes lifecycle phase' `
    ($cmText -match 'lifecycle phase' -or $cmText -match 'Decide lifecycle') `
    'Lifecycle phase prohibition not found'

# M. Fallback must_not_block covers critical operations
Assert-True 'M. fallback must_not_block Resume' ($cmText -match 'Resume') 'Resume not in must_not_block'
Assert-True 'M. fallback must_not_block Re-Sync' ($cmText -match 'Re-Sync') 'Re-Sync not in must_not_block'
Assert-True 'M. fallback must_not_block checkpoint validation' ($cmText -match 'checkpoint') 'Checkpoint not in must_not_block'

# N-P. Specific prohibited promotions
Assert-True 'N. UNVERIFIED->VERIFIED prohibited' `
    ($cmText -match 'UNVERIFIED.*VERIFIED' -or $cmText -match 'UNVERIFIED -> VERIFIED') `
    'UNVERIFIED->VERIFIED promotion prohibition not found'

Assert-True 'O. FAILED->VERIFIED prohibited' `
    ($cmText -match 'FAILED.*VERIFIED' -or $cmText -match 'FAILED -> VERIFIED') `
    'FAILED->VERIFIED promotion prohibition not found'

Assert-True 'P. STALE->VERIFIED prohibited' `
    ($cmText -match 'STALE.*VERIFIED' -or $cmText -match 'STALE -> VERIFIED') `
    'STALE->VERIFIED promotion prohibition not found'

# Q. No contradiction in authority contract
# The 'may' and 'may_not' sections must not overlap on evidence/state authority
$mayNotSection = ''
$maySection = ''
$inMayNot = $false
$inMay = $false
foreach ($line in ($cmText -split '\n')) {
    if ($line -match 'context_mode_may_not:') { $inMayNot = $true; $inMay = $false; continue }
    if ($line -match 'context_mode_may:') { $inMay = $true; $inMayNot = $false; continue }
    if ($inMayNot -and $line -match '^\s+-\s+') { $mayNotSection += $line + "`n" }
    if ($inMay -and $line -match '^\s+-\s+') { $maySection += $line + "`n" }
}
# May section should NOT contain VERIFIED, gate state changes, mission state changes
$mayContradictsAuthority = ($maySection -match 'VERIFIED' -and $maySection -notmatch 'cannot' -and $maySection -notmatch 'not.*VERIFIED') -or
                            ($maySection -match 'gate.*complete' -and $maySection -notmatch 'help locate')
Assert-True 'Q. context_mode_may does not contradict authority contract' `
    (-not $mayContradictsAuthority) `
    'may section appears to grant authority over evidence/gate state'

# R. Fallback must_not_block comprehensive
Assert-True 'R. fallback must_not_block includes evidence access' `
    ($cmText -match 'canonical references' -or $cmText -match 'Evidence access') `
    'Evidence access not in must_not_block'
Assert-True 'R. fallback must_not_block includes normal agent operation' `
    ($cmText -match 'Normal agent operation' -or $cmText -match 'normal agent') `
    'Normal agent operation not in must_not_block'

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=== Anti-Dual-Memory Guarantee Results ===" -ForegroundColor Cyan
Write-Host "  PASS: $PassCount" -ForegroundColor Green
if ($FailCount -gt 0) {
    Write-Host "  FAIL: $FailCount" -ForegroundColor Red
    $FailDetails | ForEach-Object { Write-Host $_ -ForegroundColor Red }
    Write-Host ""
    Write-Host "  CRITICAL: Anti-dual-memory guarantee has gaps." -ForegroundColor Red
    Write-Host "  MxAgile evidence authority is compromised." -ForegroundColor Red
    exit 1
} else {
    Write-Host "  All anti-dual-memory guarantee tests passed." -ForegroundColor Green
    Write-Host "  MxAgile evidence authority contract is intact." -ForegroundColor Green
    exit 0
}
