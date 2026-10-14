<#
.SYNOPSIS
RF-010: Verification-before-completion hardening regression tests.
Covers the Mode-A pattern: clean check → test harness mutates → agent must NOT
claim clean completion without re-checking.
Also covers RF-009 test-script vs application-defect distinction.
#>

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$completionPolicyFile = Join-Path $repoRoot ".mxagile\policies\mission-completion.md"
$harnessPolicyFile = Join-Path $repoRoot ".mxagile\policies\test-harness-cleanup.md"

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
Write-Host "RF-010: Verification-Before-Completion Hardening" -ForegroundColor Cyan
Write-Host "=================================================" -ForegroundColor Cyan
Write-Host ""

# -----------------------------------------------------------------------
# Test 1: Completion policy has Final Completion Cleanliness Gate section
# -----------------------------------------------------------------------
$t = "Completion policy: Final Completion Cleanliness Gate section exists"
try {
    $content = Get-Content $completionPolicyFile -Raw
    if ($content -match "Final Completion Cleanliness Gate") {
        Pass $t
    } else {
        Fail $t "mission-completion.md does not have 'Final Completion Cleanliness Gate' section"
    }
} catch {
    Fail $t "Exception: $_"
}

# -----------------------------------------------------------------------
# Test 2: Rule: git status AFTER last harness action
# -----------------------------------------------------------------------
$t = "Completion policy: git status required AFTER last harness action"
try {
    $content = Get-Content $completionPolicyFile -Raw
    if (($content -match "AFTER.*harness") -or
        ($content -match "last.*test-harness") -or
        ($content -match "git status.*AFTER")) {
        Pass $t
    } else {
        Fail $t "Policy does not state git status must run AFTER last harness/runtime action"
    }
} catch {
    Fail $t "Exception: $_"
}

# -----------------------------------------------------------------------
# Test 3: Mode-A regression pattern explicitly documented
# -----------------------------------------------------------------------
$t = "Completion policy: Mode-A regression pattern documented"
try {
    $content = Get-Content $completionPolicyFile -Raw
    if (($content -match "Mode.A") -or ($content -match "mode.a") -or ($content -match "Mode A")) {
        Pass $t
    } else {
        Fail $t "Policy does not document the Mode-A regression pattern"
    }
} catch {
    Fail $t "Exception: $_"
}

# -----------------------------------------------------------------------
# Test 4: UNEXPECTED_OR_UNKNOWN blocks clean completion
# -----------------------------------------------------------------------
$t = "Completion policy: UNEXPECTED_OR_UNKNOWN changes block clean completion"
try {
    $content = Get-Content $completionPolicyFile -Raw
    if (($content -match "UNEXPECTED_OR_UNKNOWN.*NOT claim") -or
        ($content -match "NOT claim.*UNEXPECTED_OR_UNKNOWN") -or
        ($content -match "do NOT claim clean") -or
        ($content -match "UNEXPECTED_OR_UNKNOWN.*block")) {
        Pass $t
    } else {
        Fail $t "Policy does not block completion on UNEXPECTED_OR_UNKNOWN changes"
    }
} catch {
    Fail $t "Exception: $_"
}

# -----------------------------------------------------------------------
# Test 5: TEMPORARY_TEST_HARNESS_ARTIFACT → clean → re-verify
# -----------------------------------------------------------------------
$t = "Completion policy: TEMPORARY artifacts cleaned then re-verified"
try {
    $content = Get-Content $completionPolicyFile -Raw
    if (($content -match "TEMPORARY_TEST_HARNESS_ARTIFACT.*clean") -or
        ($content -match "clean.*re.verify") -or
        ($content -match "re-run git status") -or
        ($content -match "clean deterministically")) {
        Pass $t
    } else {
        Fail $t "Policy does not require re-verification after cleaning harness artifacts"
    }
} catch {
    Fail $t "Exception: $_"
}

# -----------------------------------------------------------------------
# Test 6: test-harness-cleanup.md exists (RF-007)
# -----------------------------------------------------------------------
$t = "Test-harness cleanup policy file exists"
if (Test-Path $harnessPolicyFile) {
    Pass $t
} else {
    Fail $t "policies/test-harness-cleanup.md does not exist"
}

# -----------------------------------------------------------------------
# Test 7: Harness cleanup policy defines artifact classification
# -----------------------------------------------------------------------
$t = "Harness cleanup policy: artifact classification defined"
try {
    $content = Get-Content $harnessPolicyFile -Raw
    $classes = @("REQUIRED_APPLICATION_CHANGE", "REQUIRED_ACCEPTANCE_EVIDENCE",
                 "TEMPORARY_TEST_HARNESS_ARTIFACT", "UNEXPECTED_OR_UNKNOWN")
    $missingClasses = @($classes | Where-Object { $content -notmatch $_ })
    if ($missingClasses.Count -eq 0) {
        Pass $t
    } else {
        Fail $t "Missing artifact classes: $($missingClasses -join ', ')"
    }
} catch {
    Fail $t "Exception: $_"
}

# -----------------------------------------------------------------------
# RF-009 Tests: Test-Script vs Application-Defect distinction
# -----------------------------------------------------------------------

# Test 8: Completion policy has TEST_SCRIPT_FAILURE classification
$t = "RF-009: TEST_SCRIPT_FAILURE classification defined"
try {
    $content = Get-Content $completionPolicyFile -Raw
    if ($content -match "TEST_SCRIPT_FAILURE") {
        Pass $t
    } else {
        Fail $t "mission-completion.md does not define TEST_SCRIPT_FAILURE classification"
    }
} catch {
    Fail $t "Exception: $_"
}

# Test 9: APPLICATION_DEFECT is distinct from TEST_SCRIPT_FAILURE
$t = "RF-009: APPLICATION_DEFECT vs TEST_SCRIPT_FAILURE are distinct"
try {
    $content = Get-Content $completionPolicyFile -Raw
    if ($content -match "TEST_SCRIPT_FAILURE" -and $content -match "APPLICATION_DEFECT") {
        Pass $t
    } else {
        Fail $t "Policy does not distinguish TEST_SCRIPT_FAILURE from APPLICATION_DEFECT"
    }
} catch {
    Fail $t "Exception: $_"
}

# Test 10: No CapTrack-specific navigation names in Core
$t = "RF-009: No CapTrack-specific test names/routes in Core policies"
try {
    $policyDir = Join-Path $repoRoot ".mxagile\policies"
    $suspiciousTerms = @("user-switcher", "UserSwitcher", "captrack_nav", "CapTrackNav")
    $found = @()
    $files = Get-ChildItem -Path $policyDir -Filter "*.md" -Recurse -File
    foreach ($file in $files) {
        $fc = Get-Content $file.FullName -Raw -ErrorAction SilentlyContinue
        foreach ($term in $suspiciousTerms) {
            if ($fc -match [regex]::Escape($term)) {
                $found += "$($file.Name): $term"
            }
        }
    }
    if ($found.Count -eq 0) {
        Pass $t
    } else {
        Fail $t "CapTrack-specific terms found in Core policies: $($found -join ', ')"
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
