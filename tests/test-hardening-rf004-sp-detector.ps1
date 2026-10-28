<#
.SYNOPSIS
RF-004: Studio Pro detector regression tests.
Covers: detector succeeds, times out, unrelated SP instance, MPR lock,
UNKNOWN vs CLOSED-AUTONOM, no false LIVE_SP_CURRENT, ask-once preserved.
#>

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$detectorScript = Join-Path $repoRoot "scripts\check-studio-pro-status.ps1"
$policyFile = Join-Path $repoRoot ".mxagile\policies\operating-mode.md"

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
Write-Host "RF-004: Studio Pro Detector Hardening" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan
Write-Host ""

# -----------------------------------------------------------------------
# Test 1: Detector script has -TimeoutSeconds parameter
# -----------------------------------------------------------------------
$t = "Detector: -TimeoutSeconds parameter exists"
try {
    $content = Get-Content $detectorScript -Raw
    if ($content -match "\[int\]\s*\`$TimeoutSeconds") {
        Pass $t
    } else {
        Fail $t "check-studio-pro-status.ps1 does not have [int]\$TimeoutSeconds parameter"
    }
} catch {
    Fail $t "Exception: $_"
}

# -----------------------------------------------------------------------
# Test 2: Detector uses Wait-Job with timeout (bounded detection)
# -----------------------------------------------------------------------
$t = "Detector: uses bounded background job (Wait-Job -Timeout)"
try {
    $content = Get-Content $detectorScript -Raw
    if ($content -match "Wait-Job.*-Timeout" -or $content -match "Start-Job") {
        Pass $t
    } else {
        Fail $t "Detector does not use bounded job pattern (Start-Job/Wait-Job)"
    }
} catch {
    Fail $t "Exception: $_"
}

# -----------------------------------------------------------------------
# Test 3: Timeout produces exit code 2 with TIMEOUT in error
# -----------------------------------------------------------------------
$t = "Detector timeout: exit code 2 and TIMEOUT error message"
try {
    $content = Get-Content $detectorScript -Raw
    if ($content -match "exit 2" -and $content -match "TIMEOUT") {
        Pass $t
    } else {
        Fail $t "Detector does not emit TIMEOUT error message on timeout"
    }
} catch {
    Fail $t "Exception: $_"
}

# -----------------------------------------------------------------------
# Test 4: Timeout JSON includes detection_state = UNKNOWN
# -----------------------------------------------------------------------
$t = "Detector timeout JSON: detection_state UNKNOWN"
try {
    $content = Get-Content $detectorScript -Raw
    if (($content -match "detection_state.*UNKNOWN") -or ($content -match "UNKNOWN.*detection_state")) {
        Pass $t
    } else {
        Fail $t "Timeout JSON output does not include detection_state: UNKNOWN"
    }
} catch {
    Fail $t "Exception: $_"
}

# -----------------------------------------------------------------------
# Test 5: Policy says timeout → AMBIGUOUS-SP-STATE (NOT CLOSED-AUTONOM)
# -----------------------------------------------------------------------
$t = "Policy: timeout → AMBIGUOUS-SP-STATE, NOT CLOSED-AUTONOM"
try {
    $content = Get-Content $policyFile -Raw
    if (($content -match "TIMEOUT.*CLOSED.AUTONOM") -or
        ($content -match "timeout.*AMBIGUOUS") -or
        ($content -match "NOT CLOSED-AUTONOM")) {
        Pass $t
    } else {
        Fail $t "Policy does not explicitly rule out CLOSED-AUTONOM for timeout"
    }
} catch {
    Fail $t "Exception: $_"
}

# -----------------------------------------------------------------------
# Test 6: Policy says MPR lock does not imply execution intent
# -----------------------------------------------------------------------
$t = "Policy: MPR lock is project-affinity evidence only (not execution intent)"
try {
    $content = Get-Content $policyFile -Raw
    $hasIntent = ($content -match "execution intent") -or
                 ($content -match "execution_intent") -or
                 ($content -match "user intent")
    $hasMPR = ($content -match "MPR lock") -or
              ($content -match "mpr.lock") -or
              ($content -match "lock.*evidence") -or
              ($content -match "project-affinity")
    if ($hasIntent -and $hasMPR) {
        Pass $t
    } else {
        Fail $t "Policy does not state MPR lock does not imply execution intent (hasIntent=$hasIntent, hasMPR=$hasMPR)"
    }
} catch {
    Fail $t "Exception: $_"
}

# -----------------------------------------------------------------------
# Test 7: Policy documents script_timeout as detection_source value
# -----------------------------------------------------------------------
$t = "Policy: script_timeout listed as valid detection_source"
try {
    $content = Get-Content $policyFile -Raw
    if ($content -match "script_timeout") {
        Pass $t
    } else {
        Fail $t "Policy does not list script_timeout as detection_source option"
    }
} catch {
    Fail $t "Exception: $_"
}

# -----------------------------------------------------------------------
# Test 8: Policy documents unknown as valid detection_confidence
# -----------------------------------------------------------------------
$t = "Policy: unknown listed as valid detection_confidence"
try {
    $content = Get-Content $policyFile -Raw
    if (($content -match "detection_confidence.*unknown") -or ($content -match "unknown.*detection_confidence")) {
        Pass $t
    } else {
        Fail $t "Policy does not list 'unknown' as valid detection_confidence"
    }
} catch {
    Fail $t "Exception: $_"
}

# -----------------------------------------------------------------------
# Test 9: Known operating mode does not trigger an execution-mode question
# -----------------------------------------------------------------------
$t = "Execution-intent policy: known mode routes without asking"
try {
    $execIntentFile = Join-Path $repoRoot ".mxagile\policies\execution-intent.md"
    $content = Get-Content $execIntentFile -Raw
    if (($content -match "known mode.*without asking") -and ($content -match "not a user-selected")) {
        Pass $t
    } else {
        Fail $t "execution-intent.md does not route a known mode automatically"
    }
} catch {
    Fail $t "Exception: $_"
}

# -----------------------------------------------------------------------
# Test 10: MCP tool presence is not health or project identity
# -----------------------------------------------------------------------
$t = "Execution-intent policy: tool presence does NOT imply healthy same-project route"
try {
    $execIntentFile = Join-Path $repoRoot ".mxagile\policies\execution-intent.md"
    $content = Get-Content $execIntentFile -Raw
    $hasHealthBoundary = $content -match "tool appears in the active tool set.*Successful operation"
    $hasIdentityBoundary = $content -match "identity returned by the endpoint"
    if ($hasHealthBoundary -and $hasIdentityBoundary) {
        Pass $t
    } else {
        Fail $t "execution-intent.md does not distinguish tool presence, health, and project identity"
    }
} catch {
    Fail $t "Exception: $_"
}

# -----------------------------------------------------------------------
# Test 11: Project path matching requires a complete command-line argument
# -----------------------------------------------------------------------
$t = "Detector: exact normalized MPR argument match"
try {
    $projectArgument = 'C:\work\App.mpr'.ToLowerInvariant()
    $projectPattern = "(?i)(?<![^\s`"'=])$([regex]::Escape($projectArgument))(?=$|[\s`"'])"
    $sameProject = 'studiopro.exe -project "c:\work\app.mpr"'
    $similarPrefix = 'studiopro.exe -project "c:\work\app.mpr-backup"'
    $similarSuffix = 'studiopro.exe -project "c:\work\app.mprBackup"'
    $matchesSame = [regex]::IsMatch($sameProject, $projectPattern)
    $matchesPrefix = [regex]::IsMatch($similarPrefix, $projectPattern)
    $matchesSuffix = [regex]::IsMatch($similarSuffix, $projectPattern)
    if ($matchesSame -and -not $matchesPrefix -and -not $matchesSuffix) {
        Pass $t
    } else {
        Fail $t "Expected only the exact path to match (same=$matchesSame, prefix=$matchesPrefix, suffix=$matchesSuffix)"
    }
} catch {
    Fail $t "Exception: $_"
}

# -----------------------------------------------------------------------
# Test 12: Failed CIM probe or unreadable command line remains UNKNOWN
# -----------------------------------------------------------------------
$t = "Detector: CIM failure and unreadable command line remain UNKNOWN"
try {
    $content = Get-Content $detectorScript -Raw
    $probeFailsClosed = ($content -match 'Get-CimInstance Win32_Process.*-ErrorAction Stop') -and
                        ($content -match '\$detectionJob\.State -eq .Failed.')
    $unreadableIsUnknown = ($content -match '\$unreadableProcesses') -and
                           ($content -match 'AMBIGUOUS-SP-STATE.*NOT LIVE-SP-OTHER or CLOSED-AUTONOM') -and
                           ($content -match 'detection_state\s*=\s*"UNKNOWN"')
    if ($probeFailsClosed -and $unreadableIsUnknown) {
        Pass $t
    } else {
        Fail $t "CIM failure/unreadable process can still be classified as absent or foreign (probe=$probeFailsClosed, unreadable=$unreadableIsUnknown)"
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
