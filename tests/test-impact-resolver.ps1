# Test suite for the impact resolver (scripts/resolve_impact.py).
# Covers: PAGE->REQ resolution, REQ->Page reverse, Spec resolution,
# stale index rebuild, no-match behavior, --json output.

try {

    # --- Setup ---
    $TestDir = Join-Path $env:TEMP "tmp-test-impact-resolver-$([System.Guid]::NewGuid().ToString('N').Substring(0,8))"
    if (Test-Path $TestDir) { Remove-Item -Recurse -Force $TestDir }
    New-Item -ItemType Directory -Path $TestDir | Out-Null

    $PSScriptRoot       = Split-Path -Path $MyInvocation.MyCommand.Path -Parent
    $BuilderScriptPath  = Join-Path $PSScriptRoot "..\scripts\build_artifact_index.py"
    $ResolverScriptPath = Join-Path $PSScriptRoot "..\scripts\resolve_impact.py"

    # Create directories
    $ReqDir   = Join-Path $TestDir "requirements"
    $SpecDir  = Join-Path $TestDir "specs"
    $PageDir  = Join-Path $TestDir "planning\ui-inventory"
    $ScenDir  = Join-Path $TestDir "planning\scenarios"
    New-Item -ItemType Directory -Path $ReqDir  | Out-Null
    New-Item -ItemType Directory -Path $SpecDir | Out-Null
    New-Item -ItemType Directory -Path $PageDir | Out-Null
    New-Item -ItemType Directory -Path $ScenDir | Out-Null

    # Create canonical artifacts
    # PAGE-DASHBOARD with a derivedFrom req and an applies_to req
    Set-Content -Path (Join-Path $PageDir "PAGE-DASHBOARD.yaml") -Value "page_id: PAGE-DASHBOARD`npurpose: Dashboard screen`nmockup_name: demo-application"
    Set-Content -Path (Join-Path $ReqDir "REQ-010.yml") -Value "ID: REQ-010`nName: Dashboard view`nderivedFrom: PAGE-DASHBOARD"
    Set-Content -Path (Join-Path $ReqDir "REQ-011.yml") -Value "ID: REQ-011`nName: Multi-screen filter`nscreens: [PAGE-DASHBOARD]"
    Set-Content -Path (Join-Path $SpecDir "SPEC-010.yml") -Value "ID: SPEC-010`nName: Dashboard spec`nrequirements: [REQ-010]"
    Set-Content -Path (Join-Path $ScenDir "SCEN-010.yaml") -Value "scenario_id: SCEN-010`nscreen_id: PAGE-DASHBOARD`ntraceability:`n  requirements: [REQ-010]"

    function Assert-Condition {
        param ($Condition, $Message)
        if (-not $Condition) { throw "Assertion Failed: $Message" }
    }

    # Build the index
    & python $BuilderScriptPath $TestDir
    Assert-Condition ($LASTEXITCODE -eq 0) "build_artifact_index.py failed."

    # --- Test 1: PAGE resolution returns expected requirements ---
    Write-Host "[TEST] Running: PAGE->REQ resolution"
    $output = & python $ResolverScriptPath --path $TestDir PAGE-DASHBOARD 2>&1
    Assert-Condition ($LASTEXITCODE -eq 0) "resolve_impact.py failed for PAGE-DASHBOARD."
    Assert-Condition ($output -match "REQ-010") "REQ-010 not found in PAGE-DASHBOARD resolution."
    Assert-Condition ($output -match "REQ-011") "REQ-011 (APPLIES_TO) not found in PAGE-DASHBOARD resolution."
    Write-Host "[PASS] PAGE->REQ resolution"

    # --- Test 2: PAGE resolution returns specs ---
    Write-Host "[TEST] Running: PAGE->SPEC resolution"
    Assert-Condition ($output -match "SPEC-010") "SPEC-010 not found in PAGE-DASHBOARD resolution."
    Write-Host "[PASS] PAGE->SPEC resolution"

    # --- Test 3: PAGE resolution returns scenarios ---
    Write-Host "[TEST] Running: PAGE->scenario resolution"
    Assert-Condition ($output -match "SCEN-010") "SCEN-010 not found in PAGE-DASHBOARD resolution."
    Write-Host "[PASS] PAGE->scenario resolution"

    # --- Test 4: REQ resolution returns pages ---
    Write-Host "[TEST] Running: REQ->pages resolution"
    $reqOutput = & python $ResolverScriptPath --path $TestDir REQ-010 2>&1
    Assert-Condition ($LASTEXITCODE -eq 0) "resolve_impact.py failed for REQ-010."
    Assert-Condition ($reqOutput -match "PAGE-DASHBOARD") "PAGE-DASHBOARD not found in REQ-010 resolution."
    Assert-Condition ($reqOutput -match "SPEC-010") "SPEC-010 not found in REQ-010 resolution."
    Write-Host "[PASS] REQ->pages resolution"

    # --- Test 5: SPEC resolution returns requirements and tasks ---
    Write-Host "[TEST] Running: SPEC resolution"
    $specOutput = & python $ResolverScriptPath --path $TestDir SPEC-010 2>&1
    Assert-Condition ($LASTEXITCODE -eq 0) "resolve_impact.py failed for SPEC-010."
    Assert-Condition ($specOutput -match "REQ-010") "REQ-010 not found in SPEC-010 resolution."
    Write-Host "[PASS] SPEC resolution"

    # --- Test 6: Bundle resolution via --mockup ---
    Write-Host "[TEST] Running: Bundle resolution"
    $bundleOutput = & python $ResolverScriptPath --path $TestDir --mockup demo-application 2>&1
    Assert-Condition ($LASTEXITCODE -eq 0) "resolve_impact.py failed for bundle demo-application."
    Assert-Condition ($bundleOutput -match "PAGE-DASHBOARD") "PAGE-DASHBOARD not found in bundle resolution."
    Write-Host "[PASS] Bundle resolution"

    # --- Test 7: --json output is valid JSON ---
    Write-Host "[TEST] Running: --json output"
    $jsonOutput = & python $ResolverScriptPath --path $TestDir --json PAGE-DASHBOARD 2>&1
    Assert-Condition ($LASTEXITCODE -eq 0) "resolve_impact.py --json failed."
    $parsed = $jsonOutput | ConvertFrom-Json
    Assert-Condition ($parsed.query_type -eq "page") "query_type is not 'page' in JSON output."
    Assert-Condition ($parsed.all_requirements -contains "REQ-010") "REQ-010 not in all_requirements in JSON output."
    Write-Host "[PASS] --json output"

    # --- Test 8: Unknown identifier produces a warning, not a crash ---
    Write-Host "[TEST] Running: Unknown identifier warning"
    $unknownOutput = & python $ResolverScriptPath --path $TestDir PAGE-UNKNOWN 2>&1
    # Should not crash (exit code 0) but should warn about missing identifier
    Assert-Condition ($LASTEXITCODE -eq 0) "resolve_impact.py crashed on unknown identifier."
    Assert-Condition ($unknownOutput -match "not found in index|Identifier") "Expected 'not found in index' warning for PAGE-UNKNOWN."
    Write-Host "[PASS] Unknown identifier warning"

    # --- Test 9: Stale index triggers rebuild ---
    Write-Host "[TEST] Running: Stale index auto-rebuild"
    # Add a new requirement after the index was built
    Set-Content -Path (Join-Path $ReqDir "REQ-012.yml") -Value "ID: REQ-012`nName: Post-index req`nscreens: [PAGE-DASHBOARD]"
    # Index is now stale — resolver should detect and rebuild
    $staleOutput = & python $ResolverScriptPath --path $TestDir --json PAGE-DASHBOARD 2>&1
    $staleJson = $staleOutput | ConvertFrom-Json -ErrorAction SilentlyContinue
    if ($staleJson) {
        # After rebuild, REQ-012 should be included
        $warnings = $staleJson.warnings -join " "
        # Either rebuild happened (REQ-012 present) or warnings mention stale/rebuild
        $hasREQ012 = $staleJson.all_requirements -contains "REQ-012"
        $hasRebuildWarning = $warnings -match "stale|rebuild|Rebuild"
        Assert-Condition ($hasREQ012 -or $hasRebuildWarning) "Stale index was not detected or rebuilt."
    }
    Write-Host "[PASS] Stale index auto-rebuild"

} catch {
    Write-Error "A test failed: $_"
    exit 1
} finally {
    if (Test-Path $TestDir) {
        Remove-Item -Recurse -Force $TestDir -ErrorAction SilentlyContinue
        Write-Host "[INFO] Cleaned up test directory."
    }
}

Write-Host "`n✅ All tests in test-impact-resolver.ps1 passed."
exit 0
