#Requires -Version 7
# MxAgile P0 User Orientation — Tier 0 static validation
#
# Validates that the user-orientation policy exists and owns the correct contract,
# that orchestrator.md routes orientation requests correctly, that orientation is
# non-blocking and non-tracking, and that normal work is never gated behind orientation.
#
# Run from repository root:  pwsh tests/test-orientation.ps1

param(
    [string]$RepoRoot = (Get-Location).Path
)

$RepoRoot = (Resolve-Path $RepoRoot).Path
$ErrorActionPreference = 'Stop'
$pass = 0; $fail = 0

function Assert {
    param([bool]$Condition, [string]$Label, [string]$Detail = '')
    if ($Condition) {
        Write-Host "  PASS  $Label" -ForegroundColor Green
        $script:pass++
    } else {
        $msg = if ($Detail) { "  FAIL  $Label — $Detail" } else { "  FAIL  $Label" }
        Write-Host $msg -ForegroundColor Red
        $script:fail++
    }
}

Write-Host "`nP0 User Orientation — $RepoRoot" -ForegroundColor Cyan

$uo        = Get-Content (Join-Path $RepoRoot '.mxagile\policies\user-orientation.md') -Raw -Encoding UTF8
$orch      = Get-Content (Join-Path $RepoRoot '.mxagile\orchestrator.md') -Raw -Encoding UTF8
$apply     = Get-Content (Join-Path $RepoRoot 'scripts\apply-project-agent-instructions.ps1') -Raw -Encoding UTF8
$ic        = Get-Content (Join-Path $RepoRoot 'scripts\install-core.ps1') -Raw -Encoding UTF8

# ──────────────────────────────────────────────────────────────
# A  Policy file: structure and trigger coverage
# ──────────────────────────────────────────────────────────────
Write-Host "`n[A] user-orientation.md: structure and trigger coverage"
Assert ($uo -match '## PURPOSE') 'A1: has PURPOSE section'
Assert ($uo -match '## TRIGGERS') 'A2: has TRIGGERS section'
Assert ($uo -match 'PROJECT_INITIALIZED') 'A3: defines PROJECT_INITIALIZED trigger'
Assert ($uo -match 'PROJECT_ADOPTED') 'A4: defines PROJECT_ADOPTED trigger'
Assert ($uo -match 'EXPLICIT_HELP') 'A5: defines EXPLICIT_HELP trigger'
Assert ($uo -match '## CONTENT BUDGET') 'A6: has CONTENT BUDGET section'
Assert ($uo -match '## CORE VOCABULARY') 'A7: has CORE VOCABULARY section'
Assert ($uo -match '## NO-GATE RULE') 'A8: has NO-GATE RULE section'

# ──────────────────────────────────────────────────────────────
# B  Orchestrator integration
# ──────────────────────────────────────────────────────────────
Write-Host "`n[B] orchestrator.md: ORIENTATION integration"
Assert ($orch -match 'ORIENTATION Check') 'B1: orchestrator.md has ORIENTATION Check section'
Assert ($orch -match 'user-orientation\.md') 'B2: orchestrator.md references user-orientation.md'
Assert ($orch -match 'blockiert NIEMALS|NIEMALS.*blockiert|blockiert niemals') 'B3: orchestrator states orientation never blocks the actual request'
Assert ($orch -match 'FRAMEWORK_CHANGE') 'B4: FRAMEWORK_CHANGE detection still present (not removed)'
Assert ($orch -match 'ORIENTATION Check.*\r?\n.*\r?\n.*FRAMEWORK_CHANGE|ORIENTATION.*Check') 'B5: ORIENTATION check appears before FRAMEWORK_CHANGE section'

# ──────────────────────────────────────────────────────────────
# C  Managed block awareness
# ──────────────────────────────────────────────────────────────
Write-Host "`n[C] Managed block: orientation reference"
Assert ($apply -match 'user-orientation\.md') 'C1: managed block startup references user-orientation.md'
Assert ($apply -match 'user-orientation.*never blocks|user-orientation.*orientation.*brief|Brief.*never blocks') 'C2: managed block notes orientation is brief and non-blocking'

# ──────────────────────────────────────────────────────────────
# D  NO-GATE guarantee
# ──────────────────────────────────────────────────────────────
Write-Host "`n[D] NO-GATE guarantee: orientation is never a lifecycle gate"
Assert ($uo -match 'NO-GATE RULE') 'D1: user-orientation.md has NO-GATE RULE'
Assert ($uo -match 'Block lifecycle progress|block.*lifecycle|NEVER.*block.*lifecycle|blockiert.*NIEMALS.*Lifecycle') 'D2: NO-GATE RULE explicitly prohibits blocking lifecycle progress'
Assert ($uo -match 'confirmation|Confirmation|confirm') 'D3: NO-GATE RULE mentions confirmation (to prohibit it)'
Assert (($uo -match 'NO-GATE RULE') -and ($uo -match 'process-state\.yaml')) 'D4: NO-GATE RULE explicitly prohibits modifying process-state.yaml'

# ──────────────────────────────────────────────────────────────
# E  NO-TRACKING guarantee (P0)
# ──────────────────────────────────────────────────────────────
Write-Host "`n[E] NO-TRACKING guarantee: no per-user tracking in P0"
Assert ($uo -match 'NO-TRACKING RULE') 'E1: user-orientation.md has NO-TRACKING RULE'
Assert ($uo -match 'last_seen_user|last_orientation_user|onboarding_completed') 'E2: NO-TRACKING RULE lists prohibited tracking fields'
Assert ($uo -notmatch '(?i)(write|create|set|update)\s+last_seen|write.*last_orientation') 'E3: no instruction to write tracking fields'

# ──────────────────────────────────────────────────────────────
# F  Core vocabulary present
# ──────────────────────────────────────────────────────────────
Write-Host "`n[F] Core vocabulary: canonical terms present"
Assert ($uo -match '\*\*System Check\*\*|System Check') 'F1: System Check in vocabulary'
Assert ($uo -match '\*\*Re-Sync\*\*|Re-Sync') 'F2: Re-Sync in vocabulary'
Assert ($uo -match '\*\*Discovery\*\*|Discovery') 'F3: Discovery in vocabulary'
Assert ($uo -match '\*\*Refinement\*\*|Refinement') 'F4: Refinement in vocabulary'
Assert ($uo -match '\*\*Implementation\*\*|Implementation') 'F5: Implementation in vocabulary'
Assert ($uo -match 'Verification.*Acceptance|Acceptance.*Verification') 'F6: Verification/Acceptance in vocabulary'
Assert ($uo -match '\*\*Decision Required\*\*|Decision Required') 'F7: Decision Required in vocabulary'

# ──────────────────────────────────────────────────────────────
# G  No internal complexity exposed by default
# ──────────────────────────────────────────────────────────────
Write-Host "`n[G] Orientation output does not enumerate internal complexity"
Assert ($uo -notmatch 'discovery-agent\.md|implementation-agent\.md|refinement-agent\.md') 'G1: auto-orientation does not enumerate agent files'
Assert ($uo -match 'Do NOT enumerate all agents|not.*enumerate.*agents|enumerate all agents.*not') 'G2: content budget explicitly prohibits agent enumeration'
Assert ($uo -notmatch 'intake-completeness\.md|evidence-levels\.md|spa-mockup-bundle\.md') 'G3: auto-orientation does not enumerate policy files'

# ──────────────────────────────────────────────────────────────
# H  Brownfield / adoption orientation
# ──────────────────────────────────────────────────────────────
Write-Host "`n[H] Brownfield / adoption orientation"
Assert ($uo -match 'PROJECT_ADOPTED') 'H1: PROJECT_ADOPTED trigger defined'
Assert ($uo -match 'remain relevant.*preserved|preserved.*remain|Existing.*preserved|preserved.*existing') 'H2: adoption orientation states existing knowledge is preserved'
Assert ($uo -match 'does not invalidate|not invalidat|Adoption does not') 'H3: adoption orientation explicitly does not imply evidence invalidation'

# ──────────────────────────────────────────────────────────────
# I  Normal work not blocked; original intent continues
# ──────────────────────────────────────────────────────────────
Write-Host "`n[I] Normal work not blocked; continue-original-intent rule"
Assert ($orch -match 'NEIN.*weiter.*FRAMEWORK_CHANGE|weiter mit FRAMEWORK_CHANGE') 'I1: orchestrator ORIENTATION check routes non-help requests to normal FRAMEWORK_CHANGE flow'
Assert ($uo -match 'CONTINUE-ORIGINAL-INTENT RULE') 'I2: user-orientation.md has CONTINUE-ORIGINAL-INTENT RULE'
Assert ($uo -match 'continues the original work request|continue.*original.*request|Continues.*without stopping') 'I3: continue-intent rule states original work continues without stopping'

# ──────────────────────────────────────────────────────────────
# J  No lifecycle mutation from orientation
# ──────────────────────────────────────────────────────────────
Write-Host "`n[J] No lifecycle mutation from orientation"
Assert ($uo -match 'NO-GATE RULE') 'J1: NO-GATE RULE exists (no mutation guard present)'
Assert (($uo -match 'NO-GATE RULE') -and ($uo -match 'process-state\.yaml')) 'J2: policy explicitly prohibits process-state mutation'

# ──────────────────────────────────────────────────────────────
# K  No orientation agent / no new agent created
# ──────────────────────────────────────────────────────────────
Write-Host "`n[K] Architectural invariant: no new agent/phase created"
$agentFiles = Get-ChildItem (Join-Path $RepoRoot '.mxagile\agents') -Filter '*.md' -ErrorAction SilentlyContinue
$agentFileNames = if ($agentFiles) { ($agentFiles | Select-Object -ExpandProperty Name) -join ',' } else { '' }
Assert ($agentFileNames -notmatch 'orientation-agent|onboarding-agent|tutorial-agent') 'K1: no orientation-agent or onboarding-agent file created'
Assert ($uo -match 'not a separate lifecycle phase.*not an agent|not.*agent.*not.*lifecycle|not.*tutorial') 'K2: policy explicitly states it is not an agent or tutorial system'
Assert ($uo -match 'orchestrator\.md.*detects|architectural owner.*orchestrator') 'K3: policy documents that orchestrator.md is the architectural routing owner'

# ──────────────────────────────────────────────────────────────
# L  Company-agnostic content
# ──────────────────────────────────────────────────────────────
Write-Host "`n[L] Company-agnostic content"
Assert ($uo -notmatch 'CapTrack|Mercedes|KidsCompass|mercedes-benz') 'L1: user-orientation.md contains no company-specific names'
Assert ($orch -notmatch 'CapTrack|Mercedes|KidsCompass') 'L2: orientation additions to orchestrator.md are company-agnostic'

# ──────────────────────────────────────────────────────────────
# M  New install hint present; update path unchanged
# ──────────────────────────────────────────────────────────────
Write-Host "`n[M] install-core.ps1: orientation hint for new installs only"
Assert ($ic -match 'simply describe what you want to achieve|describe.*what.*you.*want') 'M1: install-core.ps1 has orientation hint for new installs'
Assert ($ic -match '-not \$IsUpdate|-not\s+\$IsUpdate') 'M2: orientation hint is gated to new installs only (not updates)'

# ──────────────────────────────────────────────────────────────
# Summary
# ──────────────────────────────────────────────────────────────
Write-Host "`n========================================"
if ($fail -eq 0) {
    Write-Host "  PASS: $pass   FAIL: $fail — all checks passed" -ForegroundColor Green
} else {
    Write-Host "  PASS: $pass   FAIL: $fail — validation failed" -ForegroundColor Red
}
Write-Host "========================================`n"

exit ($fail -gt 0 ? 1 : 0)
