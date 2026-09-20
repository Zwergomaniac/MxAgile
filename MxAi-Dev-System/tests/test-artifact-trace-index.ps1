# Test suite for artifact-trace-index.json builder

# Setup
$TestDir = Join-Path $env:TEMP "tmp-test-artifact-trace"
if (Test-Path $TestDir) {
    Remove-Item -Recurse -Force $TestDir
}
New-Item -ItemType Directory -Path $TestDir | Out-Null

# Create directories that the script will scan
New-Item -ItemType Directory -Path (Join-Path $TestDir "specs") | Out-Null
New-Item -ItemType Directory -Path (Join-Path $TestDir "requirements") | Out-Null


$BuilderScriptPath = "$PSScriptRoot/../scripts/build_trace_index.py"
$IndexPath = Join-Path $TestDir ".mxagile/state/trace-index.json"

function Get-FileSha256 {
    param ([string]$FilePath)
    $stream = [System.IO.File]::OpenRead($FilePath)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $hashBytes = $sha.ComputeHash($stream)
    $stream.Close()
    return [System.BitConverter]::ToString($hashBytes).Replace("-", "").ToLower()
}

# --- Test 1: Deletion and Regeneration ---
try {
    # 1. Run the builder script
    python $BuilderScriptPath --project-root $TestDir
    
    # 2. Verify the index file is created
    if (-not (Test-Path $IndexPath)) {
        throw "Index file was not created on the first run."
    }
    
    # 3. Delete the index file
    Remove-Item -Path $IndexPath
    
    # 4. Rerun the builder script
    python $BuilderScriptPath --project-root $TestDir
    
    # 5. Verify the index file is recreated
    if (Test-Path $IndexPath) {
        Write-Host "[PASS] Deletion and Regeneration"
    } else {
        throw "Index file was not recreated after deletion."
    }
} catch {
    Write-Host "[FAIL] Deletion and Regeneration: $_"
}

# --- Test 2: Idempotency ---
try {
    # 1. Run the builder script
    python $BuilderScriptPath --project-root $TestDir
    
    # 2. Calculate the hash
    $hash1 = Get-FileSha256 -FilePath $IndexPath
    
    # 3. Run the builder script a second time
    python $BuilderScriptPath --project-root $TestDir
    
    # 4. Recalculate the hash
    $hash2 = Get-FileSha256 -FilePath $IndexPath
    
    # 5. Verify that the two hashes are identical
    if ($hash1 -eq $hash2) {
        Write-Host "[PASS] Idempotency"
    } else {
        throw "Hashes do not match. Expected $hash1, got $hash2."
    }
} catch {
    Write-Host "[FAIL] Idempotency: $_"
}

# --- Test 3: Change Propagation ---
try {
    # 1. Create a dummy spec file
    $specFilePath = Join-Path $TestDir "specs/SPEC-01.yml"
    Set-Content -Path $specFilePath -Value "ID: SPEC-01`nName: My First Spec"

    # 2. Run the builder script to create a baseline
    python $BuilderScriptPath --project-root $TestDir
    
    # 3. Read the index and store the hash of a specific artifact
    $indexContent = Get-Content $IndexPath | ConvertFrom-Json
    $originalHash = $indexContent.specs."SPEC-01".hash
    
    # 4. Modify the content of the corresponding source artifact file
    Add-Content -Path $specFilePath -Value "`nDescription: A change"
    
    # 5. Rerun the builder script
    python $BuilderScriptPath --project-root $TestDir
    
    # 6. Read the new index and verify the hash has changed
    $newIndexContent = Get-Content $IndexPath | ConvertFrom-Json
    $newHash = $newIndexContent.specs."SPEC-01".hash
    
    if ($originalHash -ne $newHash) {
        Write-Host "[PASS] Change Propagation"
    } else {
        throw "Hash for modified file did not change."
    }
} catch {
    Write-Host "[FAIL] Change Propagation: $_"
}

# --- Test 4: Ghost Node Detection ---
try {
    # 1. We already have a file from the previous test. Rerun the builder.
    python $BuilderScriptPath --project-root $TestDir
    
    # 2. Delete a source artifact file
    $fileToDelete = Join-Path $TestDir "specs/SPEC-01.yml"
    Remove-Item -Path $fileToDelete
    
    # 3. Rerun the builder script
    python $BuilderScriptPath --project-root $TestDir
    
    # 4. Read the new index and verify the node is gone
    $indexContent = Get-Content $IndexPath | ConvertFrom-Json
    
    if (-not $indexContent.specs.'SPEC-01') {
        Write-Host "[PASS] Ghost Node Detection"
    } else {
        throw "Node for deleted file still exists in the index."
    }
} catch {
    Write-Host "[FAIL] Ghost Node Detection: $_"
}

# --- Cleanup ---
finally {
    Remove-Item -Recurse -Force $TestDir -ErrorAction SilentlyContinue
}
