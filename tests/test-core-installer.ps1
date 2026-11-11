# tests/test-core-installer.ps1

param([string[]]$SelectedTests = @())

# Main execution block
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot 'helpers/Remove-TestTempDirectory.ps1')

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
        $installerPath = Join-Path (Join-Path (Join-Path $PSScriptRoot "..") "scripts") "install-core.ps1"
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
        Remove-TestTempDirectory -Path $projectRoot -ExpectedPrefix 'Test-GenericInstallation-'
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
        $layerJson = '{"id": "test-layer", "name": "Test Layer", "version": "1.0.0", "schemaVersion": "1", "artifacts": {"main": "test-file.txt"}}'
        Set-Content -Path (Join-Path $layerSource "layer.json") -Value $layerJson
        New-Item -ItemType File -Path (Join-Path $layerSource "test-file.txt") | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $layerSource ".git") | Out-Null

        # 3. Execute install-core.ps1 with -CompanyLayerSource
        $installerPath = Join-Path (Join-Path (Join-Path $PSScriptRoot "..") "scripts") "install-core.ps1"
        pwsh -File $installerPath -ProjectRoot $projectRoot -CompanyLayerSource $layerSource

        # 4. Assert exit code 0
        Assert-Condition ($LASTEXITCODE -eq 0) "Installer should exit with code 0."

        # 5. Assert that the layer was installed
        $installedLayerPath = Join-Path (Join-Path (Join-Path $projectRoot ".mxagile") "layers") "test-layer"
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
        Remove-TestTempDirectory -Path $projectRoot -ExpectedPrefix 'Test-LocalLayerInstallation-'
    }
}

function Test-UpdateBlocksBeforeMxcliInitWhenForeignMcpConfigExists {
    Write-Host "Running Test-UpdateBlocksBeforeMxcliInitWhenForeignMcpConfigExists..."
    $projectRoot = Join-Path $env:TEMP "Test-Host-Mcp-Ownership-$([guid]::NewGuid())"
    New-Item -ItemType Directory -Path $projectRoot -Force | Out-Null
    New-Item -ItemType File -Path (Join-Path $projectRoot "project.mpr") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $projectRoot ".mxagile") -Force | Out-Null
    New-Item -ItemType File -Path (Join-Path $projectRoot ".mxagile\lifecycle.yaml") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $projectRoot ".agents") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $projectRoot ".cortex") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $projectRoot ".vscode") -Force | Out-Null
    $stateDir = Join-Path $projectRoot ".mxagile\state"
    New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $stateDir "update-transaction.json"), '{"schema_version":1,"state":"UPDATE_IN_PROGRESS","current_stage":"PREFLIGHT"}', [System.Text.UTF8Encoding]::new($false))
    $configs = @{
        (Join-Path $projectRoot ".mcp.json") = '{"mcpServers":{"host":{"command":"preserve-root-config"}}}'
        (Join-Path $projectRoot ".vscode\mcp.json") = '{"servers":{"host":{"command":"preserve-vscode-config"}}}'
        (Join-Path $projectRoot ".agents\mcp_config.json") = '{"servers":{"host":"preserve-agent-config"}}'
        (Join-Path $projectRoot ".cortex\mcp.json") = '{"servers":{"host":"preserve-cortex-config"}}'
    }
    foreach ($path in $configs.Keys) { [System.IO.File]::WriteAllText($path, $configs[$path], [System.Text.UTF8Encoding]::new($false)) }
    $gitignore = Join-Path $projectRoot ".gitignore"
    [System.IO.File]::WriteAllText($gitignore, "# user owned`n", [System.Text.UTF8Encoding]::new($false))
    $beforeGitignore = [System.IO.File]::ReadAllBytes($gitignore)
    $beforeConfigHashes = @{}
    foreach ($path in $configs.Keys) { $beforeConfigHashes[$path] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash }
    $installerPath = Join-Path (Join-Path $PSScriptRoot "..") "scripts\install-core.ps1"

    try {
        $output = & pwsh -NoProfile -NonInteractive -File $installerPath -ProjectRoot $projectRoot -IsUpdate:True 2>&1
        Assert-Condition ($LASTEXITCODE -ne 0) "Update requiring mxcli init must stop before touching unknown MCP configuration."
        Assert-Condition (($output -join "`n") -match "HOST_CONFIG_CONFLICT") "Conflict diagnostic must identify host configuration ownership; output: $($output -join ' ')"
        Assert-Condition ([System.Linq.Enumerable]::SequenceEqual([byte[]][System.IO.File]::ReadAllBytes($gitignore), [byte[]]$beforeGitignore)) "Project .gitignore must remain unchanged before the blocked update."
        foreach ($path in $configs.Keys) {
            Assert-Condition ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -eq $beforeConfigHashes[$path]) "Host config must remain byte-identical: $path"
        }
        $transaction = Get-Content -LiteralPath (Join-Path $stateDir "update-transaction.json") -Raw | ConvertFrom-Json
        Assert-Condition ($transaction.state -eq 'BLOCKED_BEFORE_MUTATION') "Pre-mutation conflict must remain BLOCKED_BEFORE_MUTATION."
        Assert-Condition (-not (Test-Path -LiteralPath (Join-Path $projectRoot ".mxagile\state\mxcli-init.txt"))) "Blocked setup must not create mxcli-init provenance."
        Write-Host "Test-UpdateBlocksBeforeMxcliInitWhenForeignMcpConfigExists PASSED."
    }
    finally {
        Remove-TestTempDirectory -Path $projectRoot -ExpectedPrefix 'Test-Host-Mcp-Ownership-'
    }
}


try {
    $knownTests = @('Test-GenericInstallation', 'Test-LocalLayerInstallation', 'Test-UpdateBlocksBeforeMxcliInitWhenForeignMcpConfigExists')
    $unknownTests = @($SelectedTests | Where-Object { $_ -notin $knownTests })
    if ($unknownTests.Count -gt 0) { throw "Unknown selected tests: $($unknownTests -join ', ')" }
    if ($SelectedTests.Count -eq 0 -or 'Test-GenericInstallation' -in $SelectedTests) { Test-GenericInstallation }
    if ($SelectedTests.Count -eq 0 -or 'Test-LocalLayerInstallation' -in $SelectedTests) { Test-LocalLayerInstallation }
    if ($SelectedTests.Count -eq 0 -or 'Test-UpdateBlocksBeforeMxcliInitWhenForeignMcpConfigExists' -in $SelectedTests) {
        Test-UpdateBlocksBeforeMxcliInitWhenForeignMcpConfigExists
    }

    Write-Host "All tests passed successfully."
    exit 0
}
catch {
    Write-Host "A test failed: $_" -ForegroundColor Red
    exit 1
}
