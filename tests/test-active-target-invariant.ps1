#Requires -Version 7
# Active Target Invariant Tests — Tier 0
# Verifies: exactly ONE revision per mockup bundle may have active_target: true.
# Tests VALID (1 active), INVALID (0 active), INVALID (2+ active), TRANSITION cases.
# Also verifies schema and policy enforce the invariant.
#
# Run from repository root:  pwsh tests/test-active-target-invariant.ps1

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

function ReadFile { param([string]$Path)
    if (Test-Path -LiteralPath $Path) { [string](Get-Content -LiteralPath $Path -Raw -Encoding UTF8) }
    else { '' }
}

function ReadYAML { param([string]$Path)
    if (Test-Path -LiteralPath $Path) { [string](Get-Content -LiteralPath $Path -Raw -Encoding UTF8) }
    else { '' }
}

function ParseJSON { param([string]$Content)
    try { $Content | ConvertFrom-Json -Depth 20 } catch { $null }
}

# Helper: count active_target: true in a YAML/JSON string
# Uses = not ": " to avoid matching inside comments
function CountActiveTrueYAML { param([string]$Content)
    ([regex]::Matches($Content, 'active_target: true')).Count
}

function CountActiveFalseYAML { param([string]$Content)
    ([regex]::Matches($Content, 'active_target: false')).Count
}

Write-Host "`nActive Target Invariant Tests — $RepoRoot" -ForegroundColor Cyan

# ──────────────────────────────────────────────────────────────
# [1] Invariant rule documented in canonical sources
# ──────────────────────────────────────────────────────────────
Write-Host "`n[1] Active-target invariant in canonical sources"
$revSchema = ReadFile (Join-Path $RepoRoot '.mxagile/schemas/revision.schema.json')
Assert ($revSchema -match 'active_target') 'revision schema defines active_target field'
Assert ($revSchema -match 'exactly one|ONE.*active_target|active_target.*ONE') 'revision schema documents one-active-target invariant'

$policyMockupLifecycle = ReadFile (Join-Path $RepoRoot '.mxagile/policies/mockup-lifecycle.md')
Assert ($policyMockupLifecycle -match 'active_target') 'mockup-lifecycle policy references active_target'

$gateRefinement = ReadFile (Join-Path $RepoRoot '.mxagile/skills/gate-to-refinement.md')
Assert ($gateRefinement -match 'active_target') 'gate-to-refinement skill enforces active_target check'
Assert ($gateRefinement -match 'active_target.*true|true.*active_target') 'gate-to-refinement checks for active_target: true'

$gateReady = ReadFile (Join-Path $RepoRoot '.mxagile/skills/gate-to-ready.md')
Assert ($gateReady -match 'active_target') 'gate-to-ready skill enforces active_target check'

# ──────────────────────────────────────────────────────────────
# [2] VALID case: core-regression fixture has exactly one active_target: true
# ──────────────────────────────────────────────────────────────
Write-Host "`n[2] VALID case: core-regression fixture — exactly one active_target"
$rl = ReadYAML (Join-Path $RepoRoot 'tests/fixtures/core-regression/revision-lifecycle.yaml')
$activeTrue = CountActiveTrueYAML $rl
$activeFalse = CountActiveFalseYAML $rl
Assert ($activeTrue -eq 1) "core-regression fixture: exactly 1 active_target: true ($activeTrue found)"
Assert ($activeFalse -ge 1) "core-regression fixture: at least 1 active_target: false ($activeFalse found)"
Assert ($rl -match 'lifecycle_status: SOURCE') 'VALID: SOURCE revision exists'
Assert ($rl -match 'lifecycle_status: REFINED_TARGET') 'VALID: REFINED_TARGET revision exists'

# ──────────────────────────────────────────────────────────────
# [3] INVALID (0 active): detect when no active_target: true
# ──────────────────────────────────────────────────────────────
Write-Host "`n[3] INVALID case detection: zero active_target:true"
# Simulate detection of the invalid state
$invalidZero = @"
bundle_id: MOCKUP-TEST
revisions:
  - revision_id: REV-001
    lifecycle_status: SOURCE
    active_target: false
  - revision_id: REV-002
    lifecycle_status: REFINED_TARGET
    active_target: false
"@
$zeroActiveTrue = CountActiveTrueYAML $invalidZero
Assert ($zeroActiveTrue -eq 0) 'Zero-active fixture: 0 active_target: true detected'
Assert ($zeroActiveTrue -ne 1) 'Zero-active fixture: violates one-active-target invariant'

# Policy must document the WORKING_TARGET_UNACCEPTED_DEVIATION state
Assert ($gateRefinement -match 'WORKING_TARGET_UNACCEPTED|create_revision') 'gate-to-refinement documents resolution for missing active target'

# ──────────────────────────────────────────────────────────────
# [4] INVALID (2+ active): detect when multiple active_target: true
# ──────────────────────────────────────────────────────────────
Write-Host "`n[4] INVALID case detection: two active_target:true"
$invalidDouble = @"
bundle_id: MOCKUP-TEST-DOUBLE
revisions:
  - revision_id: REV-001
    lifecycle_status: SOURCE
    active_target: true
  - revision_id: REV-002
    lifecycle_status: REFINED_TARGET
    active_target: true
"@
$doubleActiveTrue = CountActiveTrueYAML $invalidDouble
Assert ($doubleActiveTrue -eq 2) 'Double-active fixture: 2 active_target: true detected'
Assert ($doubleActiveTrue -ne 1) 'Double-active fixture: violates one-active-target invariant'

# Agent policy must block on this condition
Assert ($gateRefinement -match 'double.*active|two.*active|doppeltes.*active_target') 'gate-to-refinement explicitly rejects double active_target'

# ──────────────────────────────────────────────────────────────
# [5] TRANSITION: active_target transition documented in policy
# ──────────────────────────────────────────────────────────────
Write-Host "`n[5] TRANSITION: active_target transition documented"
# The transition: old active = false, new = true (atomic)
# Must be done by create_revision.py only
$revSchemaContent = ReadFile (Join-Path $RepoRoot '.mxagile/schemas/revision.schema.json')
Assert ($revSchemaContent -match 'create_revision') 'revision schema references create_revision.py for atomic transition'

# Template: revision template must say DO NOT CREATE MANUALLY
$revTemplate = ReadFile (Join-Path $RepoRoot '.mxagile/templates/generic/revisions/template.yaml')
Assert ($revTemplate -ne '') 'revision template exists'
Assert ($revTemplate -match 'create_revision|DO NOT CREATE MANUALLY') 'revision template warns against manual creation'

# ──────────────────────────────────────────────────────────────
# [6] SOURCE revision defaults: active_target true, lifecycle SOURCE
# ──────────────────────────────────────────────────────────────
Write-Host "`n[6] SOURCE revision defaults"
$revTemplate = ReadFile (Join-Path $RepoRoot '.mxagile/templates/generic/revisions/template.yaml')
Assert ($revTemplate -match 'lifecycle_status:.*SOURCE') 'revision template default lifecycle_status is SOURCE'

# Migration defaults: active_target true for SOURCE
$kf = ReadFile (Join-Path $RepoRoot 'products/MxMocketeer/knowledge/design-contract.txt')
Assert ($kf -match 'active_target.*true.*Only revision|Only revision.*active_target.*true|active_target.*true.*SOURCE') 'knowledge file: SOURCE default active_target is true'

# ──────────────────────────────────────────────────────────────
# [7] Acceptance agent must check active_target before campaign
# ──────────────────────────────────────────────────────────────
Write-Host "`n[7] Acceptance agent: pre-campaign active_target check"
$acceptAgent = ReadFile (Join-Path $RepoRoot '.mxagile/agents/acceptance-agent.md')
Assert ($acceptAgent -match 'active_target') 'acceptance agent references active_target check'
Assert ($acceptAgent -match 'pre.campaign|before.*campaign|vor.*Campaign') 'acceptance agent runs active_target check before campaign'

# ──────────────────────────────────────────────────────────────
# [8] UI agent must not set active_target: true
# ──────────────────────────────────────────────────────────────
Write-Host "`n[8] UI agent: active_target set by MxAgile, not MxMocketeer"
$uiAgent = ReadFile (Join-Path $RepoRoot '.mxagile/agents/ui-agent.md')
$mocketeerSysPrompt = ReadFile (Join-Path $RepoRoot 'products/MxMocketeer/system-prompt.md')

# MxMocketeer must set active_target: false on new revisions
Assert ($mocketeerSysPrompt -match 'active_target: false') 'system-prompt: MxMocketeer sets active_target: false on new revision'
# MxAgile sets active_target: true upon acceptance
Assert ($mocketeerSysPrompt -match 'MxAgile.*active_target.*true|active_target.*true.*developer acceptance') 'system-prompt: MxAgile sets active_target: true upon acceptance'

# ──────────────────────────────────────────────────────────────
# Summary
# ──────────────────────────────────────────────────────────────
Write-Host "`n========================================"
if ($fail -eq 0) {
    Write-Host "  PASS: $pass   FAIL: $fail — all active-target invariant checks passed" -ForegroundColor Green
} else {
    Write-Host "  PASS: $pass   FAIL: $fail — active-target invariant checks failed" -ForegroundColor Red
}
Write-Host "========================================`n"

exit ($fail -gt 0 ? 1 : 0)
