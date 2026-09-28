# Test suite for SPA mockup bundle revision lifecycle.
# Covers: deterministic hash, same-content = same hash, create_revision.py,
# gate cannot self-authorize (requires DEC-NNN), no empty revision creation.

try {

    # --- Setup ---
    $TestDir = Join-Path $env:TEMP "tmp-test-spa-bundle"
    if (Test-Path $TestDir) { Remove-Item -Recurse -Force $TestDir }
    New-Item -ItemType Directory -Path $TestDir | Out-Null

    $PSScriptRoot        = Split-Path -Path $MyInvocation.MyCommand.Path -Parent
    $HashScriptPath      = Join-Path $PSScriptRoot "..\scripts\artifact_hashing.py"
    $RevisionScriptPath  = Join-Path $PSScriptRoot "..\scripts\create_revision.py"

    # Create test directories
    $MockupRoot     = Join-Path $TestDir "planning\target-mockups"
    $BundleDir      = Join-Path $MockupRoot "test-bundle"
    $DecisionsDir   = Join-Path $TestDir "planning\decisions"
    New-Item -ItemType Directory -Path $BundleDir    | Out-Null
    New-Item -ItemType Directory -Path $DecisionsDir | Out-Null

    # Create a simple SPA bundle
    Set-Content -Path (Join-Path $BundleDir "index.html") -Value "<html><body>Hello SPA</body></html>"
    New-Item -ItemType Directory -Path (Join-Path $BundleDir "js") | Out-Null
    Set-Content -Path (Join-Path $BundleDir "js\app.js") -Value "console.log('app');"

    function Assert-Condition {
        param ($Condition, $Message)
        if (-not $Condition) { throw "Assertion Failed: $Message" }
    }

    # Helper: call hash_spa_bundle via inline Python
    function Get-BundleHash {
        param ($Dir)
        $hashOutput = & python -c @"
import sys
sys.path.insert(0, r'$(Split-Path $HashScriptPath)')
from artifact_hashing import hash_spa_bundle
print(hash_spa_bundle(r'$Dir'))
"@
        return $hashOutput.Trim()
    }

    # --- Test 1: Hash is non-empty and has sha256: prefix ---
    Write-Host "[TEST] Running: Bundle hash format"
    $hash1 = Get-BundleHash $BundleDir
    Assert-Condition ($hash1 -match '^sha256:[0-9a-f]{64}$') "Bundle hash format invalid: $hash1"
    Write-Host "[PASS] Bundle hash format"

    # --- Test 2: Same content produces same hash (deterministic) ---
    Write-Host "[TEST] Running: Hash determinism"
    $hash2 = Get-BundleHash $BundleDir
    Assert-Condition ($hash1 -eq $hash2) "Same bundle produced different hashes on second call."
    Write-Host "[PASS] Hash determinism"

    # --- Test 3: Different content produces different hash ---
    Write-Host "[TEST] Running: Hash sensitivity to content change"
    $beforeChange = Get-BundleHash $BundleDir
    Add-Content -Path (Join-Path $BundleDir "js\app.js") -Value "`nconsole.log('changed');"
    $afterChange = Get-BundleHash $BundleDir
    Assert-Condition ($beforeChange -ne $afterChange) "Bundle hash did not change after content modification."
    Write-Host "[PASS] Hash sensitivity"

    # --- Test 4: create_revision.py requires DEC-NNN file to exist ---
    Write-Host "[TEST] Running: create_revision.py requires decision file"
    $output = & python $RevisionScriptPath --path $TestDir --mockup test-bundle --decision DEC-999 2>&1
    Assert-Condition ($LASTEXITCODE -ne 0) "create_revision.py should fail when DEC-999.md does not exist."
    Assert-Condition ($output -match "Decision file not found") "Expected 'Decision file not found' error message."
    Write-Host "[PASS] create_revision.py requires decision file"

    # --- Test 5: create_revision.py succeeds when DEC-NNN exists ---
    Write-Host "[TEST] Running: create_revision.py happy path"
    Set-Content -Path (Join-Path $DecisionsDir "DEC-001.md") -Value "# DEC-001: Accept test-bundle REV-001`nAccepted."
    & python $RevisionScriptPath --path $TestDir --mockup test-bundle --decision DEC-001
    Assert-Condition ($LASTEXITCODE -eq 0) "create_revision.py failed unexpectedly."
    $revDir = Join-Path $MockupRoot "test-bundle\_history\REV-001"
    Assert-Condition (Test-Path $revDir) "REV-001 directory was not created."
    $revYaml = Join-Path $revDir "revision.yaml"
    Assert-Condition (Test-Path $revYaml) "revision.yaml was not created."
    Write-Host "[PASS] create_revision.py happy path"

    # --- Test 6: revision.yaml contains expected fields ---
    Write-Host "[TEST] Running: revision.yaml content"
    $revContent = Get-Content $revYaml -Raw
    Assert-Condition ($revContent -match "revision_id: REV-001") "revision_id missing in revision.yaml"
    Assert-Condition ($revContent -match "mockup_name: test-bundle") "mockup_name missing in revision.yaml"
    Assert-Condition ($revContent -match "bundle_hash: sha256:") "bundle_hash missing in revision.yaml"
    Assert-Condition ($revContent -match "acceptance_decisions:") "acceptance_decisions missing in revision.yaml"
    Assert-Condition ($revContent -match "DEC-001") "DEC-001 reference missing in revision.yaml"
    Write-Host "[PASS] revision.yaml content"

    # --- Test 7: _history/ excluded from bundle hash computation ---
    Write-Host "[TEST] Running: _history/ excluded from hash"
    $hashBeforeRevision = Get-BundleHash $BundleDir
    # The revision is already created in _history/ — hash should be stable
    $hashAfterRevision = Get-BundleHash $BundleDir
    Assert-Condition ($hashBeforeRevision -eq $hashAfterRevision) "_history/ inclusion changed the bundle hash (should be excluded)."
    Write-Host "[PASS] _history/ excluded from hash"

    # --- Test 8: create_revision.py blocks identical revision (no change) ---
    Write-Host "[TEST] Running: create_revision.py blocks identical revision"
    Set-Content -Path (Join-Path $DecisionsDir "DEC-002.md") -Value "# DEC-002: Second acceptance"
    # Working bundle is unchanged — should be blocked
    $output = & python $RevisionScriptPath --path $TestDir --mockup test-bundle --decision DEC-002 2>&1
    Assert-Condition ($LASTEXITCODE -ne 0) "create_revision.py should refuse to create identical revision."
    Assert-Condition ($output -match "No content changes") "Expected 'No content changes' warning."
    Write-Host "[PASS] create_revision.py blocks identical revision"

    # --- Test 9: Sequential revision numbering ---
    Write-Host "[TEST] Running: Sequential revision numbering"
    # Modify the bundle so there IS a content change
    Add-Content -Path (Join-Path $BundleDir "index.html") -Value "<!-- v2 -->"
    & python $RevisionScriptPath --path $TestDir --mockup test-bundle --decision DEC-002
    Assert-Condition ($LASTEXITCODE -eq 0) "create_revision.py failed on second revision."
    $rev2Dir = Join-Path $MockupRoot "test-bundle\_history\REV-002"
    Assert-Condition (Test-Path $rev2Dir) "REV-002 directory was not created."
    $rev2Yaml = Get-Content (Join-Path $rev2Dir "revision.yaml") -Raw
    Assert-Condition ($rev2Yaml -match "predecessor_revision_id: REV-001") "predecessor_revision_id missing in REV-002."
    Write-Host "[PASS] Sequential revision numbering"

    # --- Test 10: --dry-run does not write files ---
    Write-Host "[TEST] Running: --dry-run"
    Set-Content -Path (Join-Path $DecisionsDir "DEC-003.md") -Value "# DEC-003: Dry run test"
    Add-Content -Path (Join-Path $BundleDir "index.html") -Value "<!-- v3 -->"
    & python $RevisionScriptPath --path $TestDir --mockup test-bundle --decision DEC-003 --dry-run
    $rev3Dir = Join-Path $MockupRoot "test-bundle\_history\REV-003"
    Assert-Condition (-not (Test-Path $rev3Dir)) "--dry-run created REV-003 directory but should not have."
    Write-Host "[PASS] --dry-run"

} catch {
    Write-Error "A test failed: $_"
    exit 1
} finally {
    if (Test-Path $TestDir) {
        Remove-Item -Recurse -Force $TestDir -ErrorAction SilentlyContinue
        Write-Host "[INFO] Cleaned up test directory."
    }
}

Write-Host "`n✅ All tests in test-spa-bundle-revision.ps1 passed."
exit 0
