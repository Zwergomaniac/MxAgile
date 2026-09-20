# tests/test-core-installer.ps1

# Main execution block
$ErrorActionPreference = "Stop"

# Helper function for assertions
function Assert-Condition {
    param(
        [bool]$Condition,
        [string]$Message
    )
    if (-not $Condition) {
        throw "Assertion failed: $Message"
    }
}

function Test-GenericInstallation {
    Write-Host "Running Test-GenericInstallation..."
    $testName = "GenericInstallation"
    $tempDir = New-Item -ItemType Directory -Path (Join-Path $env:TEMP "Test-$testName-$([guid]::NewGuid())")
    $projectRoot = $tempDir.FullName

    try {
        # 1. Create a temporary project directory with a dummy .mpr file.
        New-Item -ItemType File -Path (Join-Path $projectRoot "project.mpr") | Out-Null

        # 2. Execute scripts/install-core.ps1
        $installerPath = Join-Path $PSScriptRoot ".." "scripts" "install-core.ps1"
        pwsh -File $installerPath -ProjectRoot $projectRoot

        # 3. Assert that the script exits with code 0.
        Assert-Condition ($LASTEXITCODE -eq 0) "Installer should exit with code 0."

        # 4. Assert that the .mxagile directory is created.
        $mxagilePath = Join-Path $projectRoot ".mxagile"
        Assert-Condition (Test-Path $mxagilePath -PathType Container) ".mxagile directory should be created."

        # 5. Assert that the .mxagile/layers directory either does not exist or is empty.
        $layersPath = Join-Path $mxagilePath "layers"
        $layersExist = Test-Path $layersPath -PathType Container
        $layersEmpty = $true
        if ($layersExist) {
            $layersEmpty = @(Get-ChildItem $layersPath).Count -eq 0
        }
        Assert-Condition ($layersEmpty) ".mxagile/layers should not contain any layers."

        Write-Host "Test-GenericInstallation PASSED."
    }
    finally {
        # Cleanup
        if (Test-Path $projectRoot) {
            Remove-Item -Recurse -Force $projectRoot
        }
    }
}

function Test-LocalLayerInstallation {
    Write-Host "Running Test-LocalLayerInstallation..."
    $testName = "LocalLayerInstallation"
    $tempDir = New-Item -ItemType Directory -Path (Join-Path $env:TEMP "Test-$testName-$([guid]::NewGuid())")
    $projectRoot = $tempDir.FullName
    $layerSource = Join-Path $projectRoot "local-layer-src"

    try {
        # 1. Create temp project and layer source directories
        
        New-Item -ItemType File -Path (Join-Path $projectRoot "project.mpr") | Out-Null
        New-Item -ItemType Directory -Path $layerSource | Out-Null

        # 2. In the layer source directory, create layer files
        $layerJson = '{"id": "test-layer", "name": "Test Layer"}'
        Set-Content -Path (Join-Path $layerSource "layer.json") -Value $layerJson
        New-Item -ItemType File -Path (Join-Path $layerSource "test-file.txt") | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $layerSource ".git") | Out-Null

        # 3. Execute install-core.ps1 with -CompanyLayerSource
        $installerPath = Join-Path $PSScriptRoot ".." "scripts" "install-core.ps1"
        pwsh -File $installerPath -ProjectRoot $projectRoot -CompanyLayerSource $layerSource

        # 4. Assert exit code 0
        Assert-Condition ($LASTEXITCODE -eq 0) "Installer should exit with code 0."

        # 5. Assert that the layer was installed
        $installedLayerPath = Join-Path $projectRoot ".mxagile" "layers" "test-layer"
        Assert-Condition (Test-Path $installedLayerPath -PathType Container) "Layer should be installed at .mxagile/layers/test-layer."

        # 6. Assert that test-file.txt exists
        Assert-Condition (Test-Path (Join-Path $installedLayerPath "test-file.txt")) "test-file.txt should exist in the installed layer."

        # 7. Assert that the .git directory does not exist
        Assert-Condition (-not (Test-Path (Join-Path $installedLayerPath ".git"))) ".git directory should not exist in the installed layer."

        # 8. Assert provenance.json
        $provenancePath = Join-Path $installedLayerPath "provenance.json"
        Assert-Condition (Test-Path $provenancePath) "provenance.json should exist."
        $provenance = Get-Content $provenancePath | ConvertFrom-Json
        Assert-Condition ($provenance.source_type -eq "Local") "provenance.json should have source_type 'Local'."

        Write-Host "Test-LocalLayerInstallation PASSED."
    }
    finally {
        # Cleanup
        if (Test-Path $projectRoot) {
            Remove-Item -Recurse -Force $projectRoot
        }
    }
}


try {
    Test-GenericInstallation
    Test-LocalLayerInstallation

    Write-Host "All tests passed successfully."
    exit 0
}
catch {
    Write-Host "A test failed: $_" -ForegroundColor Red
    exit 1
}
