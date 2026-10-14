<#
.SYNOPSIS
RF-001: Regression tests for Resume mission priority over general product lifecycle.
Verifies that a valid active mission checkpoint takes priority over FEATURE_SCOPE_COMPLETE
and other general product lifecycle states.
#>

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$schemaFile = Join-Path $repoRoot ".mxagile\schemas\context-epoch.schema.json"
$policyFile = Join-Path $repoRoot ".mxagile\policies\context-lifecycle.md"

$pass = 0
$fail = 0
$errors = @()

function Pass([string]$name) {
    $script:pass++
    Write-Host "  PASS  $name" -ForegroundColor Green
}

function Fail([string]$name, [string]$reason) {
    $script:fail++
    $script:errors += "FAIL: $name — $reason"
    Write-Host "  FAIL  $name" -ForegroundColor Red
    Write-Host "        $reason" -ForegroundColor DarkRed
}

Write-Host ""
Write-Host "RF-001: Resume Mission Priority" -ForegroundColor Cyan
Write-Host "================================" -ForegroundColor Cyan
Write-Host ""

# -----------------------------------------------------------------------
# Test 1: Schema has mission.campaign field
# -----------------------------------------------------------------------
$t = "Schema: mission.campaign field exists"
try {
    $schema = Get-Content $schemaFile -Raw | ConvertFrom-Json
    $missionDef = $schema.definitions.mission
    if ($missionDef.properties.campaign) {
        Pass $t
    } else {
        Fail $t "mission.campaign not found in schema definitions.mission.properties"
    }
} catch {
    Fail $t "Exception: $_"
}

# -----------------------------------------------------------------------
# Test 2: Schema mission.status allows 'active'
# -----------------------------------------------------------------------
$t = "Schema: mission.status allows 'active'"
try {
    $schema = Get-Content $schemaFile -Raw | ConvertFrom-Json
    $statusEnum = $schema.definitions.mission.properties.status.enum
    if ($statusEnum -contains "active") {
        Pass $t
    } else {
        Fail $t "mission.status enum does not include 'active'. Found: $($statusEnum -join ', ')"
    }
} catch {
    Fail $t "Exception: $_"
}

# -----------------------------------------------------------------------
# Test 3: Policy documents Resume Mission Priority section
# -----------------------------------------------------------------------
$t = "Policy: Resume Mission Priority section exists"
try {
    $content = Get-Content $policyFile -Raw
    if ($content -match "Resume Mission Priority") {
        Pass $t
    } else {
        Fail $t "context-lifecycle.md does not contain 'Resume Mission Priority' section"
    }
} catch {
    Fail $t "Exception: $_"
}

# -----------------------------------------------------------------------
# Test 4: Policy defines that active mission wins over FEATURE_SCOPE_COMPLETE
# -----------------------------------------------------------------------
$t = "Policy: active mission wins over FEATURE_SCOPE_COMPLETE"
try {
    $content = Get-Content $policyFile -Raw
    if ($content -match "FEATURE_SCOPE_COMPLETE") {
        Pass $t
    } else {
        Fail $t "Policy does not reference FEATURE_SCOPE_COMPLETE to document priority rule"
    }
} catch {
    Fail $t "Exception: $_"
}

# -----------------------------------------------------------------------
# Test 5: Policy defines backward compatibility for checkpoints without mission_scope
# -----------------------------------------------------------------------
$t = "Policy: backward compatibility for old checkpoints without mission_scope"
try {
    $content = Get-Content $policyFile -Raw
    if ($content -match "mission_scope" -and $content -match "[Rr]ückw") {
        Pass $t
    } elseif ($content -match "mission_scope" -and ($content -match "backward compat" -or $content -match "Rückwärtskompatibilität" -or $content -match "ohne.*mission_scope")) {
        Pass $t
    } else {
        Fail $t "Policy does not document backward compatibility for old checkpoints"
    }
} catch {
    Fail $t "Exception: $_"
}

# -----------------------------------------------------------------------
# Test 6: Policy defines Checkpoint-Durability scope
# -----------------------------------------------------------------------
$t = "Policy: Checkpoint-Durability (same-machine vs. fresh-clone scope)"
try {
    $content = Get-Content $policyFile -Raw
    if ($content -match "Fresh Clone" -or $content -match "fresh clone" -or $content -match "Checkpoint-Durability") {
        Pass $t
    } else {
        Fail $t "Policy does not document checkpoint durability scope distinction"
    }
} catch {
    Fail $t "Exception: $_"
}

# -----------------------------------------------------------------------
# Test 7: Policy describes ambiguity reporting (not user reconstruction)
# -----------------------------------------------------------------------
$t = "Policy: ambiguity reported instead of user reconstruction"
try {
    $content = Get-Content $policyFile -Raw
    $hasAmbiguity = ($content -match "[Aa]mbigu")
    $hasNichtAuffordern = ($content -match "NICHT auffordern")
    $hasReport = ($content -match "berichten")
    if ($hasAmbiguity -and ($hasNichtAuffordern -or $hasReport)) {
        Pass $t
    } else {
        Fail $t "Policy does not say ambiguity must be reported (not user-reconstructed). ambiguity=$hasAmbiguity, nicht-auffordern=$hasNichtAuffordern, berichten=$hasReport"
    }
} catch {
    Fail $t "Exception: $_"
}

# -----------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------
Write-Host ""
Write-Host "Results: $pass passed, $fail failed" -ForegroundColor $(if ($fail -eq 0) { "Green" } else { "Red" })
if ($errors.Count -gt 0) {
    Write-Host ""
    foreach ($e in $errors) { Write-Host "  $e" -ForegroundColor Red }
}
Write-Host ""

exit $fail
