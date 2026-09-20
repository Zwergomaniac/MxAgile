# Test suite for the consolidated artifact index builder.

# Overall error handling to ensure script exits with non-zero on failure
try {

    # --- Setup ---
    $TestDir = Join-Path $env:TEMP "tmp-test-artifact-trace"
    if (Test-Path $TestDir) {
        Remove-Item -Recurse -Force $TestDir
    }
    New-Item -ItemType Directory -Path $TestDir | Out-Null

    # Create directories that the script will scan
    $SpecDir = Join-Path $TestDir "specs"
    $ReqDir = Join-Path $TestDir "requirements"
    New-Item -ItemType Directory -Path $SpecDir | Out-Null
    New-Item -ItemType Directory -Path $ReqDir | Out-Null

    $PSScriptRoot = Split-Path -Path $MyInvocation.MyCommand.Path -Parent
    $BuilderScriptPath = Join-Path $PSScriptRoot "..\scripts\build_artifact_index.py"
    $IndexPath = Join-Path $TestDir ".mxagile\state\artifact-index.json"

    function Assert-Condition {
        param ($Condition, $Message)
        if (-not $Condition) {
            throw "Assertion Failed: $Message"
        }
    }

    # --- Test 1: Deletion and Regeneration ---
    Write-Host "[TEST] Running: Deletion and Regeneration"
    & python $BuilderScriptPath $TestDir
    Assert-Condition (Test-Path $IndexPath) "Index file was not created on the first run."
    $firstRunContent = Get-Content $IndexPath
    Remove-Item -Path $IndexPath
    & python $BuilderScriptPath $TestDir
    Assert-Condition (Test-Path $IndexPath) "Index file was not recreated after deletion."
    Write-Host "[PASS] Deletion and Regeneration"

    # --- Test 2: Idempotency ---
    Write-Host "[TEST] Running: Idempotency"
    $hash1 = (Get-FileHash -Path $IndexPath -Algorithm SHA256).Hash
    & python $BuilderScriptPath $TestDir # Rerun
    $hash2 = (Get-FileHash -Path $IndexPath -Algorithm SHA256).Hash
    Assert-Condition ($hash1 -eq $hash2) "Index file hash changed on second run, expected it to be idempotent."
    Write-Host "[PASS] Idempotency"

    # --- Test 3: Change Propagation ---
    Write-Host "[TEST] Running: Change Propagation"
    $specFilePath = Join-Path $SpecDir "SPEC-01.yml"
    Set-Content -Path $specFilePath -Value "ID: SPEC-01`nName: My First Spec"
    & python $BuilderScriptPath $TestDir
    $indexJson = Get-Content $IndexPath | ConvertFrom-Json
    $originalHash = ($indexJson.nodes | Where-Object { $_.id -eq 'SPEC-01' }).hash
    Assert-Condition ($originalHash -ne $null) "Could not find SPEC-01 in index before change."
    
    # Modify the file and re-run
    Add-Content -Path $specFilePath -Value "`nDescription: A change"
    & python $BuilderScriptPath $TestDir
    $indexJson = Get-Content $IndexPath | ConvertFrom-Json
    $newHash = ($indexJson.nodes | Where-Object { $_.id -eq 'SPEC-01' }).hash
    Assert-Condition ($originalHash -ne $newHash) "Hash for modified file SPEC-01 did not change."
    Write-Host "[PASS] Change Propagation"

    # --- Test 4: Ghost Node Detection ---
    Write-Host "[TEST] Running: Ghost Node Detection"
    Remove-Item -Path $specFilePath
    & python $BuilderScriptPath $TestDir
    $indexJson = Get-Content $IndexPath | ConvertFrom-Json
    $ghostNode = $indexJson.nodes | Where-Object { $_.id -eq 'SPEC-01' }
    Assert-Condition (-not $ghostNode) "Node for deleted file SPEC-01 still exists in the index."
    Write-Host "[PASS] Ghost Node Detection"

    # --- Test 5: Edge Creation ---
    Write-Host "[TEST] Running: Edge Creation"
    $reqFilePath = Join-Path $ReqDir "REQ-01.yml"
    Set-Content -Path $reqFilePath -Value "ID: REQ-01`nName: A requirement"
    $specFilePath = Join-Path $SpecDir "SPEC-02.yml"
    Set-Content -Path $specFilePath -Value "ID: SPEC-02`nName: Another spec`nrequirements: [REQ-01]"
    & python $BuilderScriptPath $TestDir
    $indexJson = Get-Content $IndexPath | ConvertFrom-Json
    $edge = $indexJson.edges | Where-Object { $_.from -eq 'REQ-01' -and $_.to -eq 'SPEC-02' }
    Assert-Condition ($edge) "Edge from REQ-01 to SPEC-02 was not created."
    Write-Host "[PASS] Edge Creation"

} catch {
    Write-Error "A test failed: $_"
    exit 1
} finally {
    # --- Cleanup ---
    if (Test-Path $TestDir) {
        Remove-Item -Recurse -Force $TestDir -ErrorAction SilentlyContinue
        Write-Host "[INFO] Cleaned up test directory."
    }
}

# If we get here, all tests passed.
Write-Host "
✅ All tests in test-artifact-trace-index.ps1 passed."
exit 0

