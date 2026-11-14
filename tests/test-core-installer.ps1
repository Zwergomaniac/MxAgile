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
        & git -C $projectRoot init -q
        & git -C $projectRoot config user.name "MxAgile Test"
        & git -C $projectRoot config user.email "test@mxagile.invalid"
        & git -C $projectRoot add project.mpr
        & git -C $projectRoot commit -qm "fixture project"
        Assert-Condition ($LASTEXITCODE -eq 0) "Fresh-install fixture Git repository should initialize."

        foreach ($hostFamily in @('.claude', '.github', '.agents')) {
            foreach ($relative in @('assets/images', 'empty-sibling/nested')) {
                New-Item -ItemType Directory -Path (Join-Path $projectRoot "$hostFamily/skills/mocketeer-mockup-generation/$relative") -Force | Out-Null
            }
        }

        # 2. Execute scripts/install-core.ps1
        $installerPath = Join-Path (Join-Path (Join-Path $PSScriptRoot "..") "scripts") "install-core.ps1"
        pwsh -File $installerPath -ProjectRoot $projectRoot

        # 3. Assert that the script exits with code 0.
        Assert-Condition ($LASTEXITCODE -eq 0) "Installer should exit with code 0."

        # 4. Assert that the .mxagile directory is created.
        $mxagilePath = Join-Path $projectRoot ".mxagile"
        Assert-Condition (Test-Path $mxagilePath -PathType Container) ".mxagile directory should be created."
        $projectionIo = Join-Path $mxagilePath 'tools/projection_io.py'
        Assert-Condition (Test-Path $projectionIo -PathType Leaf) "Bound recovery must receive its canonical projection_io dependency."
        Assert-Condition ((Get-FileHash $projectionIo).Hash -eq (Get-FileHash (Join-Path $PSScriptRoot '../scripts/projection_io.py')).Hash) "Installed projection_io must match the canonical payload."

        $waveReader = 'import sys,json; sys.path.insert(0,sys.argv[1]); from wave_ids import planned_wave_ids; print(json.dumps(sorted(planned_wave_ids("## Wave W18a - Fixture\n## Wave W18b - Fixture"))))'
        $waveIds = @(& python -B -c $waveReader (Join-Path $mxagilePath 'tools'))
        Assert-Condition ($LASTEXITCODE -eq 0) 'Installed Wave reader must load its canonical Task schema.'
        Assert-Condition (($waveIds -join '') -eq '["W18a", "W18b"]') 'Installed Wave reader must preserve both suffix identities.'

        # 4a. Mocketeer skills are part of the canonical installer payload and generator output.
        $mocketeerSkillNames = @(
            'mocketeer-discovery',
            'mocketeer-design-contract',
            'mocketeer-refinement',
            'mocketeer-preservation',
            'mocketeer-business-flows',
            'mocketeer-mockup-generation',
            'mocketeer-handoff'
        )
        foreach ($skillName in $mocketeerSkillNames) {
            $sourceSkill = Join-Path $mxagilePath "skills/$skillName/SKILL.md"
            Assert-Condition (Test-Path $sourceSkill -PathType Leaf) "Installer must deliver canonical skill $skillName."
            $projectedSkill = Join-Path $projectRoot ".claude/skills/$skillName/SKILL.md"
            Assert-Condition (Test-Path $projectedSkill -PathType Leaf) "Fresh install must project Claude skill $skillName."
            if (Test-Path $projectedSkill -PathType Leaf) {
                $projectedContent = Get-Content -LiteralPath $projectedSkill -Raw -Encoding UTF8
                Assert-Condition ($projectedContent -match '# GENERATED - DO NOT EDIT - Source: \.mxagile/') "Claude projection must be generated from canonical source: $skillName."
                Assert-Condition ($projectedContent -match "(?s)^---\s*`r?`nname: $skillName`r?`n") "Claude projection frontmatter must identify $skillName."
            }
        }
        $businessFlowSkill = Join-Path $mxagilePath 'skills/mocketeer-business-flows/SKILL.md'
        $goldenSource = Join-Path $mxagilePath 'skills/mocketeer-mockup-generation/assets/golden-mockup.txt'
        Assert-Condition (Test-Path $goldenSource -PathType Leaf) "Installer must deliver the separate Golden HTML asset."
        foreach ($platformRoot in @('.claude/skills', '.github/skills', '.agents/skills')) {
            $goldenProjection = Join-Path $projectRoot "$platformRoot/mocketeer-mockup-generation/assets/golden-mockup.txt"
            Assert-Condition (Test-Path $goldenProjection -PathType Leaf) "Fresh install must project Golden asset to $platformRoot."
            Assert-Condition ((Get-FileHash -LiteralPath $goldenProjection).Hash -eq (Get-FileHash -LiteralPath $goldenSource).Hash) "Fresh-install Golden bytes must match for $platformRoot."
            foreach ($skillName in $mocketeerSkillNames) {
                Assert-Condition (Test-Path (Join-Path $projectRoot "$platformRoot/$skillName/SKILL.md") -PathType Leaf) "Fresh install must expose every session entry on $platformRoot ($skillName)."
            }
        }
        $businessFlowContent = Get-Content -LiteralPath $businessFlowSkill -Raw -Encoding UTF8
        Assert-Condition ($businessFlowContent -match 'FLOWSTEP-001' -and $businessFlowContent -match 'Mermaid is generated from structured steps') "Fresh install must deliver full Business Flow guidance inside its SKILL.md."
        Assert-Condition (-not (Test-Path (Join-Path $mxagilePath 'skills/mocketeer/references'))) "Fresh install must not require a separate Mocketeer references directory."

        # 5. Assert that the .mxagile/layers directory either does not exist or is empty.
        $layersPath = Join-Path $mxagilePath "layers"
        $layersExist = Test-Path $layersPath -PathType Container
        $layersEmpty = $true
        if ($layersExist) {
            $layersEmpty = @(Get-ChildItem $layersPath).Count -eq 0
        }
        Assert-Condition ($layersEmpty) ".mxagile/layers should not contain any layers."

        & git -C $projectRoot add -A
        & git -C $projectRoot commit -qm "installed core baseline"
        Assert-Condition ($LASTEXITCODE -eq 0) "Fresh-install fixture should commit its baseline before event writes."
        $beforeEventStatus = @(& git -C $projectRoot status --porcelain --untracked-files=all)
        $appendEvents = 'import sys; from pathlib import Path; root = Path(sys.argv[1]); sys.path.insert(0, str(root / ".mxagile" / "tools" / "control-plane")); import run_events; run_events.append_event(root, "delivery_blocked", run_id="RUN-IGNORE-TEST"); run_events.append_event(root, "lifecycle_resync_completed", run_id="RUN-IGNORE-TEST")'
        $eventOutput = @(& python -B -c $appendEvents $projectRoot 2>&1)
        Assert-Condition ($LASTEXITCODE -eq 0) "Fresh install should write both event classes: $($eventOutput -join ' ')"
        $runtimeFiles = @(Get-ChildItem -LiteralPath (Join-Path $projectRoot ".mxagile/state/runs") -File | ForEach-Object { ".mxagile/state/runs/$($_.Name)" })
        Assert-Condition ($runtimeFiles.Count -ge 5) "Expected audit/history streams and their lock files plus append.lock."
        foreach ($relative in $runtimeFiles) {
            & git -C $projectRoot check-ignore --quiet -- $relative 2>$null
            Assert-Condition ($LASTEXITCODE -eq 0) "Fresh-install runtime file must be ignored: $relative"
        }
        $afterEventStatus = @(& git -C $projectRoot status --porcelain --untracked-files=all)
        Assert-Condition ((($afterEventStatus -join "`n") -eq ($beforeEventStatus -join "`n"))) "Writing run events or locks must not dirty the consumer working tree. before=[$($beforeEventStatus -join '; ')] after=[$($afterEventStatus -join '; ')]"

        $mocketeerHashes = @{}
        foreach ($root in @('.mxagile/skills', '.claude/skills', '.github/skills', '.agents/skills')) {
            foreach ($skillName in $mocketeerSkillNames) {
                foreach ($file in (Get-ChildItem -LiteralPath (Join-Path $projectRoot "$root/$skillName") -Recurse -File)) {
                    $mocketeerHashes[$file.FullName] = (Get-FileHash -LiteralPath $file.FullName).Hash
                }
            }
        }
        $protectedBefore = @{}
        foreach ($relative in @('.mxagile/state/core-provenance.json', '.mxagile/state/projections-manifest.json', '.mxagile/migration/state.yaml', '.mxagile/state/last-update-result.json', '.mxagile/state/update-transaction.json')) {
            $path = Join-Path $projectRoot $relative
            $protectedBefore[$relative] = if (Test-Path -LiteralPath $path) { (Get-FileHash -LiteralPath $path).Hash } else { $null }
        }
        $foreignProjection = Join-Path $projectRoot '.hermes/skills/mxagile/.hidden-owner'
        [IO.File]::WriteAllText($foreignProjection, 'foreign content')
        $blockedUpdate = @(& pwsh -NoProfile -File $installerPath -ProjectRoot $projectRoot -IsUpdate:True 2>&1)
        Assert-Condition ($LASTEXITCODE -ne 0 -and ($blockedUpdate -join "`n") -match 'SKILL_PROJECTION_CONFLICT') "Foreign content must stop in projection preflight. $($blockedUpdate | Select-Object -Last 5 | Out-String)"
        foreach ($relative in $protectedBefore.Keys) {
            $path = Join-Path $projectRoot $relative
            $after = if (Test-Path -LiteralPath $path) { (Get-FileHash -LiteralPath $path).Hash } else { $null }
            Assert-Condition ($after -eq $protectedBefore[$relative]) "Preflight conflict must preserve $relative (including absence)."
        }
        Assert-Condition (-not (Test-Path -LiteralPath (Join-Path $projectRoot '.mxagile/state/update-transaction.json'))) "No partial transaction is needed before Core mutation."
        Assert-Condition ([IO.File]::ReadAllText($foreignProjection) -eq 'foreign content') "Foreign projection content must remain untouched."
        Remove-Item -LiteralPath $foreignProjection
        Write-Host 'Projection pre-mutation guarantee PASSED.'

        & pwsh -NoProfile -File $installerPath -ProjectRoot $projectRoot -IsUpdate:True
        Assert-Condition ($LASTEXITCODE -eq 0) "Core update must reproduce the Fresh Install Mocketeer payload."
        foreach ($path in $mocketeerHashes.Keys) {
            Assert-Condition ((Get-FileHash -LiteralPath $path).Hash -eq $mocketeerHashes[$path]) "Fresh Install and Core update must reproduce identical Mocketeer bytes: $path"
        }
        Write-Host "Mocketeer Fresh Install / Core update parity PASSED."

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
