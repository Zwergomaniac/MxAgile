#Requires -Version 7
# MxAgile Core — Test Adapter Policy Regression
# Proves that Core forbids legacy/internal Mendix browser adapters in generated tests,
# mandates Playwright user journeys for FRONTEND verification, preserves authorization
# proof strength, and correctly classifies adapter failures as TEST_ADAPTER_GAP (not
# TEST_INFRASTRUCTURE_GAP).
#
# Run from repository root:  pwsh tests/test-test-adapter-policy.ps1

param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
)

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

function FileContent { param([string]$Path)
    if (Test-Path $Path) { return Get-Content $Path -Raw -Encoding UTF8 }
    return ''
}

Write-Host "`nMxAgile Core — Test Adapter Policy Regression — $RepoRoot" -ForegroundColor Cyan

$TG  = Join-Path $RepoRoot '.mxagile/skills/test-generate.md'
$TDP = Join-Path $RepoRoot '.mxagile/policies/test-defect-protection.md'
$AA  = Join-Path $RepoRoot '.mxagile/agents/acceptance-agent.md'
$VL  = Join-Path $RepoRoot '.mxagile/policies/verification-layers.md'

$tg  = FileContent $TG
$tdp = FileContent $TDP
$aa  = FileContent $AA
$vl  = FileContent $VL

# ──────────────────────────────────────────────────────────────
# [A] test-generate.md: Forbidden Adapters section present
# ──────────────────────────────────────────────────────────────
Write-Host "`n[A] test-generate.md — Forbidden Adapters section"
Assert ($tg -match 'Forbidden Adapter') 'Forbidden Adapters section exists in test-generate.md'

# ──────────────────────────────────────────────────────────────
# [B] test-generate.md: Specific forbidden patterns listed
# ──────────────────────────────────────────────────────────────
Write-Host "`n[B] test-generate.md — Specific forbidden patterns"
Assert ($tg -match 'window\.mx\.data|window\.mx\.ui|window\\.mx') `
    'forbids window.mx.data.* and window.mx.ui.* Mendix bridge APIs'
Assert ($tg -match 'mx\.ui\.openForm|mx\.ui\.\*') `
    'forbids mx.ui.openForm and mx.ui.* calls'
Assert ($tg -match 'runtimeOperation') `
    'forbids runtimeOperation ID usage'
Assert ($tg -match 'XAS|xas|executeAction') `
    'forbids direct XAS/executeAction internal calls'
Assert ($tg -match 'page\.evaluate.*window\.mx|window\.mx.*page\.evaluate') `
    'forbids page.evaluate injecting Mendix JS SDK calls'

# ──────────────────────────────────────────────────────────────
# [C] test-generate.md: Playwright user journey mandated for FRONTEND
# ──────────────────────────────────────────────────────────────
Write-Host "`n[C] test-generate.md — Playwright user journey mandatory for FRONTEND"
Assert ($tg -match 'navigate|click|fill') `
    'mandates real Playwright user journey steps (navigate/click/fill)'
Assert ($tg -match 'getByRole|getByLabel|getByTestId|getByText') `
    'requires accessible locator preference order'
Assert ($tg -match 'locator preference order') `
    'references locator preference order'

# ──────────────────────────────────────────────────────────────
# [D] test-generate.md: Authorization proof goes to RUNTIME, not FRONTEND
# ──────────────────────────────────────────────────────────────
Write-Host "`n[D] test-generate.md — Authorization proofs use RUNTIME layer"
Assert ($tg -match 'RUNTIME.*runtime_check|runtime_check.*RUNTIME|Authorization.*RUNTIME') `
    'directs authorization server-side enforcement to RUNTIME runtime_check blocks'
Assert ($tg -match 'VISIBILITY.*NOT.*AUTHORIZATION|VISIBILITY alone.*NOT|NOT.*VISIBILITY alone') `
    'states VISIBILITY alone does not satisfy AUTHORIZATION proof'

# ──────────────────────────────────────────────────────────────
# [E] test-generate.md: TEST_ADAPTER_GAP classification referenced
# ──────────────────────────────────────────────────────────────
Write-Host "`n[E] test-generate.md — TEST_ADAPTER_GAP classification"
Assert ($tg -match 'TEST_ADAPTER_GAP') `
    'references TEST_ADAPTER_GAP as the correct classification for forbidden-adapter failures'
Assert ($tg -notmatch 'TEST_INFRASTRUCTURE_GAP.*forbidden|forbidden.*TEST_INFRASTRUCTURE_GAP') `
    'does not conflate forbidden adapter failures with TEST_INFRASTRUCTURE_GAP'

# ──────────────────────────────────────────────────────────────
# [F] test-defect-protection.md: TEST_ADAPTER_GAP defined
# ──────────────────────────────────────────────────────────────
Write-Host "`n[F] test-defect-protection.md — TEST_ADAPTER_GAP defined"
Assert ($tdp -match 'TEST_ADAPTER_GAP') `
    'defines TEST_ADAPTER_GAP defect class'
Assert ($tdp -match 'forbidden.*adapter|Forbidden.*adapter|forbidden or unsupported execution adapter') `
    'describes TEST_ADAPTER_GAP as caused by a forbidden/unsupported adapter'
Assert ($tdp -match 'window\.mx|mx\.ui\.openForm|runtimeOperation|XAS') `
    'TEST_ADAPTER_GAP examples include Mendix-internal browser API patterns'

# ──────────────────────────────────────────────────────────────
# [G] test-defect-protection.md: TEST_ADAPTER_GAP ≠ TEST_INFRASTRUCTURE_GAP
# ──────────────────────────────────────────────────────────────
Write-Host "`n[G] test-defect-protection.md — adapter failure must not auto-promote to TEST_INFRASTRUCTURE_GAP"
Assert ($tdp -match 'TEST_ADAPTER_GAP.*NOT.*TEST_INFRASTRUCTURE_GAP|NOT.*TEST_INFRASTRUCTURE_GAP.*TEST_ADAPTER_GAP') `
    'explicitly states TEST_ADAPTER_GAP is NOT TEST_INFRASTRUCTURE_GAP'
Assert ($tdp -match 'do NOT classify.*TEST_INFRASTRUCTURE_GAP|Do NOT.*TEST_INFRASTRUCTURE_GAP|not.*classify.*TEST_INFRASTRUCTURE_GAP') `
    'instructs agent NOT to classify forbidden-adapter failure as TEST_INFRASTRUCTURE_GAP'

# ──────────────────────────────────────────────────────────────
# [H] test-defect-protection.md: Classification protocol includes forbidden adapter step
# ──────────────────────────────────────────────────────────────
Write-Host "`n[H] test-defect-protection.md — classification protocol includes adapter check"
Assert ($tdp -match 'forbidden adapter|forbidden.*adapter') `
    'classification protocol checks for forbidden adapter usage'
Assert ($tdp -match 'TEST_ADAPTER_GAP.*regenerate|regenerate.*TEST_ADAPTER_GAP') `
    'TEST_ADAPTER_GAP action is to regenerate with approved adapters'
Assert ($tdp -match 'DECISION_REQUIRED is NOT required|no DECISION_REQUIRED') `
    'TEST_ADAPTER_GAP does not require DECISION_REQUIRED'

# ──────────────────────────────────────────────────────────────
# [I] test-defect-protection.md: TEST_INFRASTRUCTURE_GAP guard added
# ──────────────────────────────────────────────────────────────
Write-Host "`n[I] test-defect-protection.md — TEST_INFRASTRUCTURE_GAP guard"
Assert ($tdp -match 'Guard|guard') `
    'TEST_INFRASTRUCTURE_GAP section contains the adapter guard note'
Assert ($tdp -match 'assess.*alternatives|alternatives.*assessed|Playwright.*RUNTIME.*alternatives|RUNTIME.*Playwright.*alternatives') `
    'requires assessing Playwright/RUNTIME alternatives before concluding infrastructure blocker'

# ──────────────────────────────────────────────────────────────
# [J] acceptance-agent.md: defect classification includes TEST_ADAPTER_GAP
# ──────────────────────────────────────────────────────────────
Write-Host "`n[J] acceptance-agent.md — defect classification includes TEST_ADAPTER_GAP"
Assert ($aa -match 'TEST_ADAPTER_GAP') `
    'acceptance-agent defect protocol references TEST_ADAPTER_GAP'
Assert ($aa -match 'forbidden adapter|Forbidden Adapter|forbidden.*adapter') `
    'acceptance-agent checks for forbidden adapter in classification protocol'
Assert ($aa -match 'do NOT reclassify.*TEST_INFRASTRUCTURE_GAP|NOT.*TEST_INFRASTRUCTURE_GAP') `
    'acceptance-agent explicitly forbids reclassifying TEST_ADAPTER_GAP as TEST_INFRASTRUCTURE_GAP'

# ──────────────────────────────────────────────────────────────
# [K] acceptance-agent.md: campaign execution references TEST_ADAPTER_GAP classification
# ──────────────────────────────────────────────────────────────
Write-Host "`n[K] acceptance-agent.md — campaign execution references TEST_ADAPTER_GAP"
Assert ($aa -match 'TEST_ADAPTER_GAP.*TEST_INFRASTRUCTURE_GAP') `
    'Phase 1 failure classification line lists TEST_ADAPTER_GAP alongside TEST_INFRASTRUCTURE_GAP'

# ──────────────────────────────────────────────────────────────
# [L] verification-layers.md: VISIBILITY ≠ AUTHORIZATION
# ──────────────────────────────────────────────────────────────
Write-Host "`n[L] verification-layers.md — VISIBILITY does not imply AUTHORIZATION"
Assert ($vl -match 'VISIBILITY') `
    'defines VISIBILITY dimension'
Assert ($vl -match 'AUTHORIZATION') `
    'defines AUTHORIZATION dimension'
Assert ($vl -match 'Not the same as.*Authorization|hidden button.*security gap|VISIBILITY.*not.*AUTHORIZATION') `
    'explicitly states VISIBILITY is not the same as AUTHORIZATION'
Assert ($vl -match 'server.*enforce|server-side.*enforce') `
    'AUTHORIZATION requires server-side enforcement'

# ──────────────────────────────────────────────────────────────
# [M] test-generate.md: FRONTEND layer still produces real Playwright steps (not hollow)
# ──────────────────────────────────────────────────────────────
Write-Host "`n[M] test-generate.md — FRONTEND layer produces real Playwright steps"
Assert ($tg -match 'playwright:') `
    'FRONTEND layer template produces playwright: blocks'
Assert ($tg -match 'role_session') `
    'Playwright steps include role_session context'
Assert ($tg -match 'assert_accessible|assert_not_accessible|assert_text|assert_labeled') `
    'Playwright steps include visible-state assertions'

# ──────────────────────────────────────────────────────────────
# [N] test-generate.md: MODEL layer complementary (not replaced)
# ──────────────────────────────────────────────────────────────
Write-Host "`n[N] test-generate.md — MODEL layer still complementary"
Assert ($tg -match '### MODEL layer') `
    'MODEL layer section still present in test-generate.md'
Assert ($tg -match 'inspect:') `
    'MODEL layer still produces inspect: blocks for model-level assertions'

# ──────────────────────────────────────────────────────────────
# Summary
# ──────────────────────────────────────────────────────────────
Write-Host ''
Write-Host ('────────────────────────────────────────')
Write-Host ('Test Adapter Policy Regression: {0} PASS  {1} FAIL' -f $pass, $fail)
Write-Host ('────────────────────────────────────────')

if ($fail -gt 0) {
    Write-Host 'FAIL' -ForegroundColor Red
    exit 1
} else {
    Write-Host 'PASS' -ForegroundColor Green
    exit 0
}
