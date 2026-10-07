#Requires -Version 7
# Static validation for scripts/install-graphify.ps1 — Tier 0 / no-execute.
# Validates installer structure, parameters, safety exits, and package name
# without invoking uv, graphify, or any network operation.

try {

    $ScriptDir     = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path $MyInvocation.MyCommand.Path -Parent }
    $InstallerPath = Join-Path $ScriptDir '..' 'scripts' 'install-graphify.ps1'

    function Assert-Condition {
        param ($Condition, $Message)
        if (-not $Condition) { throw "Assertion Failed: $Message" }
    }

    # ── Test 1: Installer exists at scripts/install-graphify.ps1 ──────────────
    Write-Host "[TEST] Installer exists at scripts/install-graphify.ps1"
    Assert-Condition (Test-Path $InstallerPath) "install-graphify.ps1 not found at: $InstallerPath"
    Write-Host "[PASS] Installer exists"

    $content = Get-Content -Path $InstallerPath -Raw

    # ── Test 2: #Requires -Version 7 ──────────────────────────────────────────
    Write-Host "[TEST] Installer declares #Requires -Version 7"
    Assert-Condition ($content -match '#Requires -Version 7') "#Requires -Version 7 not found in installer"
    Write-Host "[PASS] #Requires -Version 7 present"

    # ── Test 3: VersionConstraint parameter defaults to 0.9.28 ────────────────
    Write-Host "[TEST] VersionConstraint parameter defaults to 0.9.28"
    Assert-Condition ($content -match 'VersionConstraint') "VersionConstraint parameter not declared"
    Assert-Condition ($content -match "VersionConstraint\s*=\s*['""]?0\.9\.28") "VersionConstraint default 0.9.28 not found"
    Write-Host "[PASS] VersionConstraint defaults to 0.9.28"

    # ── Test 4: Checks uv before proceeding (uv --version) ────────────────────
    Write-Host "[TEST] Installer checks 'uv --version' before proceeding"
    Assert-Condition ($content -match 'uv --version') "uv --version check not found in installer"
    Write-Host "[PASS] uv --version check present"

    # ── Test 5: Write-State function declared ─────────────────────────────────
    Write-Host "[TEST] Installer has Write-State function"
    Assert-Condition ($content -match 'function Write-State') "Write-State function declaration not found"
    Write-Host "[PASS] Write-State function present"

    # ── Test 6: Write-State called on both success and failure paths ───────────
    Write-Host "[TEST] Write-State is called on success and failure paths (>= 3 call sites)"
    $writeStateCalls = ([regex]::Matches($content, 'Write-State')).Count
    # Expect: uv-not-found path, install-failure path, success path → >= 3
    Assert-Condition ($writeStateCalls -ge 3) "Expected >= 3 Write-State calls, got $writeStateCalls"
    Write-Host "[PASS] Write-State called on $writeStateCalls paths"

    # ── Test 7: Uses graphifyy (double-y) package name ────────────────────────
    Write-Host "[TEST] Installer installs 'graphifyy' (double-y PyPI package name)"
    Assert-Condition ($content -match 'graphifyy') "Package name 'graphifyy' (double-y) not found"
    Assert-Condition ($content -match 'uv tool install') "'uv tool install' command not found"
    Write-Host "[PASS] 'uv tool install graphifyy' pattern present"

    # ── Test 8: Non-fatal on uv-not-found — exits 0, never exit 1 ────────────
    Write-Host "[TEST] Installer exits 0 (non-fatal) when uv is not found — never exit 1"
    # Must have 'exit 0' for the optional-provider safety exits
    Assert-Condition ($content -match 'exit 0') "exit 0 not found — installer must exit 0 for optional provider failures"
    # Installer must NEVER use exit 1: Graphify is optional, all failures are non-fatal
    Assert-Condition (-not ($content -match 'exit 1')) "exit 1 found — installer must not hard-fail; Graphify is optional"
    Write-Host "[PASS] Non-fatal exit 0 on uv-not-found confirmed (no exit 1 anywhere)"

    # ── Test 9: Non-fatal on install failure — exits 0, does not throw ────────
    Write-Host "[TEST] Installer exits 0 (non-fatal) on install failure"
    # Multiple exit 0 sites required: uv-not-found, install-failure, and clean-success
    $exitZeroCount = ([regex]::Matches($content, 'exit 0')).Count
    Assert-Condition ($exitZeroCount -ge 2) "Expected >= 2 'exit 0' occurrences for non-fatal paths, got $exitZeroCount"
    Write-Host "[PASS] Multiple non-fatal exit 0 paths confirmed ($exitZeroCount total)"

    # ── Test 10: State file path is .mxagile/state/graphify-state.yaml ────────
    Write-Host "[TEST] State file path uses .mxagile/state/graphify-state.yaml"
    Assert-Condition ($content -match '\.mxagile') ".mxagile directory not referenced in installer"
    Assert-Condition ($content -match 'graphify-state\.yaml') "graphify-state.yaml not referenced in installer"
    Assert-Condition ($content -match 'state') "'state' subdirectory not referenced in installer"
    Write-Host "[PASS] .mxagile/state/graphify-state.yaml path present"

    # ── Test 11: -Force switch declared ───────────────────────────────────────
    Write-Host "[TEST] Installer has -Force switch parameter"
    Assert-Condition ($content -match '\[switch\]') "[switch] type annotation not found"
    Assert-Condition ($content -match '\$Force') "`$Force parameter not found"
    Write-Host "[PASS] -Force switch parameter present"

    # ── Test 12: Smoke test step (graphify --version after install) ────────────
    Write-Host "[TEST] Installer performs a smoke test (graphify --version after install)"
    $graphifyVersionCount = ([regex]::Matches($content, 'graphify --version')).Count
    Assert-Condition ($graphifyVersionCount -ge 1) "graphify --version smoke test not found"
    Write-Host "[PASS] graphify --version smoke test present"

    # ── Test 13: Version constraint 0.9.28 as minimum in install command ───────
    Write-Host "[TEST] Version constraint 0.9.28 appears as minimum in uv install spec"
    Assert-Condition ($content -match 'graphifyy>=') "graphifyy>= version spec not found in install command"
    # The constraint should be tied to the VersionConstraint variable
    Assert-Condition ($content -match 'graphifyy>=.*VersionConstraint' -or
                      $content -match 'graphifyy>=\$VersionConstraint') `
        "graphifyy>= must use VersionConstraint variable, not a hardcoded string"
    Write-Host "[PASS] graphifyy>=`$VersionConstraint install spec confirmed"

} catch {
    Write-Error "A test failed: $_"
    exit 1
} finally {
    # Static analysis only — no temp directories created
}

Write-Host ""
Write-Host "[OK] All tests in test-graphify-install.ps1 passed."
exit 0
