<#
.SYNOPSIS
RF-002: Context Mode setup/discovery state regression tests.
Verifies that INSTALLED / REGISTERED / LOADED / ACTIVE states are clearly distinguished.
#>

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$integrationFile = Join-Path $repoRoot ".mxagile\integrations\context-mode.yaml"

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
Write-Host "RF-002: Context Mode Setup/Discovery States" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

$content = Get-Content $integrationFile -Raw

# -----------------------------------------------------------------------
# Test 1: integration file defines setup_states section
# -----------------------------------------------------------------------
$t = "Integration file: setup_states section exists"
if ($content -match "setup_states:") {
    Pass $t
} else {
    Fail $t "context-mode.yaml does not have setup_states: section"
}

# -----------------------------------------------------------------------
# Test 2: All four states defined
# -----------------------------------------------------------------------
foreach ($state in @("INSTALLED", "REGISTERED", "LOADED", "ACTIVE")) {
    $t = "State '$state' defined in setup_states"
    if ($content -match "\b$state\b:") {
        Pass $t
    } else {
        Fail $t "setup_states does not define state '$state'"
    }
}

# -----------------------------------------------------------------------
# Test 3: Resolution algorithm documented
# -----------------------------------------------------------------------
$t = "Setup state resolution algorithm documented"
if ($content -match "resolution_algorithm") {
    Pass $t
} else {
    Fail $t "context-mode.yaml does not have resolution_algorithm section"
}

# -----------------------------------------------------------------------
# Test 4: Authoring tool is ctx_index, not ctx_store
# -----------------------------------------------------------------------
$t = "Authoring tool is ctx_index"
if ($content -match "authoring_tool" -and $content -match "ctx_index") {
    Pass $t
} else {
    Fail $t "authoring_tool section missing or does not specify ctx_index"
}

# -----------------------------------------------------------------------
# Test 5: ctx_store explicitly NOT the authoring tool
# -----------------------------------------------------------------------
$t = "ctx_store explicitly excluded as authoring tool"
if ($content -match "ctx_store") {
    Pass $t
} else {
    Fail $t "authoring_tool section does not mention that ctx_store is incorrect"
}

# -----------------------------------------------------------------------
# Test 6: Detection section notes executable != ACTIVE
# -----------------------------------------------------------------------
$t = "Detection section: executable alone does not imply ACTIVE"
$detectionNote = ($content -match "PATH.*does NOT imply") -or
                 ($content -match "executable.*NOT.*ACTIVE") -or
                 ($content -match "Executable in PATH alone")
if ($detectionNote) {
    Pass $t
} else {
    Fail $t "Detection section does not clarify that executable in PATH != LOADED/ACTIVE"
}

# -----------------------------------------------------------------------
# Test 7: LOADED state requires tool namespace presence
# -----------------------------------------------------------------------
$t = "LOADED state requires tool namespace (ctx_doctor visible)"
if ($content -match "ctx_doctor.*tool" -or $content -match "tool namespace") {
    Pass $t
} else {
    Fail $t "LOADED state does not specify tool-namespace evidence requirement"
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
