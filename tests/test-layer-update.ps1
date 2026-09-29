# tests/test-layer-update.ps1
#
# Full safety regression suite for scripts/update-layer.ps1.
# All tests use synthetic Layer/project fixtures -- no real Git remote required.
# Tests invoke update-layer.ps1 via pwsh (PowerShell Core) as a child process.
#
# SCHEMAVERSION SEMANTICS (documented per contract):
#   schemaVersion describes the Layer package/contract FORMAT that MxAgile Core
#   must understand. A version difference may warrant developer confirmation and
#   Core compatibility gating, but it does NOT trigger a stateful N->N+1 migration
#   of the previously installed Layer projection.  If Core understands the target
#   schema the normal backup -> replace owned projection -> validate -> provenance
#   flow is sufficient unless the Layer contract explicitly requires otherwise.
#   Tests Test-SchemaVersionChangeProceedsWithoutMigration and
#   Test-SchemaVersionSameNoPromptRequired verify this behaviour directly.

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ScriptsDir   = Join-Path (Join-Path $PSScriptRoot "..") "scripts"
$UpdateScript = Join-Path $ScriptsDir "update-layer.ps1"

# =============================================================================
# Assertion helpers
# =============================================================================

function Assert-Equal {
    param($Actual, $Expected, [string]$Label)
    if ($Actual -ne $Expected) {
        throw "ASSERT FAILED [$Label]: expected '$Expected', got '$Actual'"
    }
}
function Assert-True  { param([bool]$Condition, [string]$Label)
    if (-not $Condition) { throw "ASSERT FAILED [$Label]: condition was false" } }
function Assert-False { param([bool]$Condition, [string]$Label)
    if ($Condition) { throw "ASSERT FAILED [$Label]: condition was true" } }
function Assert-FileExists    { param([string]$Path, [string]$Label)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf))      { throw "ASSERT FAILED [$Label]: file not found: $Path" } }
function Assert-DirExists     { param([string]$Path, [string]$Label)
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { throw "ASSERT FAILED [$Label]: dir not found: $Path" } }
function Assert-FileNotExists { param([string]$Path, [string]$Label)
    if (Test-Path -LiteralPath $Path)                            { throw "ASSERT FAILED [$Label]: path should not exist: $Path" } }

# =============================================================================
# Fixture factories
# =============================================================================

function New-TempProject {
    $dir = Join-Path $env:TEMP "mxagile-prj-$([System.Guid]::NewGuid().ToString('N').Substring(0,8))"
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    New-Item -ItemType File -Path (Join-Path $dir "project.mpr") | Out-Null
    $mxagile = Join-Path $dir ".mxagile"
    New-Item -ItemType Directory -Path $mxagile      -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $mxagile "layers") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $mxagile "state")  -Force | Out-Null
    [System.IO.File]::WriteAllText(
        (Join-Path $mxagile "version.yaml"),
        "version: `"1.1`"`nmin_compatible: `"1.0`"`n",
        [System.Text.Encoding]::UTF8)
    return $dir
}

function New-FakeLayerRepo {
    param(
        [string]$Id              = "test-layer",
        [string]$Version         = "1.0.0",
        [string]$SchemaVersion   = "1",
        [string]$CoreConstraint  = ">=1.0.0",
        [bool]$InitGit           = $true,
        # Artifact control
        [bool]$IncludeGlossary      = $true,   # false -> omit glossary.yml from source
        [bool]$BadDetailFileRef     = $false,  # true  -> dangling detailFile in platform-modules.yml
        [string]$MaliciousArtifact  = "",      # non-empty -> inject this artifact path in layer.json
        [bool]$AddDeepNestedContent = $false   # true  -> add SampleApp/node_modules deep path to repo
    )
    $dir = Join-Path $env:TEMP "mxagile-repo-$([System.Guid]::NewGuid().ToString('N').Substring(0,8))"
    New-Item -ItemType Directory -Path $dir -Force | Out-Null

    # Build artifacts object
    $artifacts = [ordered]@{
        glossary        = "glossary.yml"
        platformModules = "platform-modules.yml"
    }
    if (-not [string]::IsNullOrWhiteSpace($MaliciousArtifact)) {
        $artifacts["evil"] = $MaliciousArtifact
    }

    $layerJson = [ordered]@{
        id            = $Id
        name          = "Test Layer"
        version       = $Version
        schemaVersion = $SchemaVersion
        compatibility = @{ mxagileCore = $CoreConstraint }
        artifacts     = $artifacts
        installTarget = ".mxagile/layers/$Id/"
    }
    $layerJson | ConvertTo-Json -Depth 5 |
        Set-Content -Path (Join-Path $dir "layer.json") -Encoding UTF8

    if ($IncludeGlossary) {
        Set-Content -Path (Join-Path $dir "glossary.yml") `
            -Value "terms: [{term: TestTerm, definition: A test term}]`n" -Encoding UTF8
    }

    if ($BadDetailFileRef) {
        Set-Content -Path (Join-Path $dir "platform-modules.yml") `
            -Value "platform-modules-information:`n  modules:`n    - id: TEST`n      detailFile: modules/DOES_NOT_EXIST.md`n" `
            -Encoding UTF8
    } else {
        Set-Content -Path (Join-Path $dir "platform-modules.yml") `
            -Value "platform-modules-information:`n  modules: []`n" -Encoding UTF8
    }

    if ($AddDeepNestedContent) {
        # Simulate deeply-nested reference-app content with paths long enough to
        # exceed the Windows MAX_PATH (260 chars) limit when cloned via plain
        # "git clone --depth 1" without core.longpaths.  The sparse-checkout
        # acquisition introduced in update-layer.ps1 avoids materializing this.
        $deepDir = Join-Path $dir ("SampleApp/javascriptsource/nanoflowcommons/node_modules/" +
            "very-long-package-name-that-makes-the-path-long/node_modules/" +
            "another-very-long-package-name-for-testing-purposes/node_modules/" +
            "yet-another-really-long-package-name-here/dist/submodule/utilities/helpers")
        New-Item -ItemType Directory -Path $deepDir -Force | Out-Null
        Set-Content -Path (Join-Path $deepDir "index.js") -Value "module.exports = {};" -Encoding UTF8
    }

    if ($InitGit) {
        Push-Location $dir
        # Temporarily lower EAP: WPS 5.1 writes native-command stderr to the PS
        # error stream as ErrorRecord objects; with EAP=Stop they terminate.
        $savedEAP = $ErrorActionPreference
        $ErrorActionPreference = "SilentlyContinue"
        try {
            & git init -q  2>&1 | Out-Null
            & git config user.email "test@test.com" 2>&1 | Out-Null
            & git config user.name  "Test"          2>&1 | Out-Null
            # Enable long paths for this fixture repo so deep-nested content can be committed.
            & git config core.longpaths true 2>&1 | Out-Null
            & git add .    2>&1 | Out-Null
            & git commit -m "init" -q 2>&1 | Out-Null
            # Normalize branch name to 'main' for -Ref "main" compatibility
            $ErrorActionPreference = "Stop"
            $branch = (& git rev-parse --abbrev-ref HEAD 2>&1).Trim()
            if ($branch -ne "main") {
                $ErrorActionPreference = "SilentlyContinue"
                & git branch -m main 2>&1 | Out-Null
            }
        } finally {
            $ErrorActionPreference = $savedEAP
            Pop-Location
        }
    }
    return $dir
}

function Install-FakeLayer {
    param(
        [string]$ProjectRoot,
        [string]$LayerId         = "test-layer",
        [string]$InstalledVersion = "1.0.0",
        [string]$InstalledCommit  = "aaa000bbb111",
        [string]$SchemaVersion    = "1",
        [string]$GlossaryContent  = "terms: []`n",
        [bool]$WriteProvenance    = $true
    )
    $layerDir = Join-Path $ProjectRoot ".mxagile\layers\$LayerId"
    New-Item -ItemType Directory -Path $layerDir -Force | Out-Null
    Set-Content -Path (Join-Path $layerDir "layer.json") `
        -Value (@{id=$LayerId; name="Installed Layer"; version=$InstalledVersion; schemaVersion=$SchemaVersion; artifacts=@{glossary="glossary.yml"; platformModules="platform-modules.yml"}} | ConvertTo-Json -Depth 5) `
        -Encoding UTF8
    [System.IO.File]::WriteAllText(
        (Join-Path $layerDir "glossary.yml"),
        $GlossaryContent,
        [System.Text.Encoding]::UTF8)
    Set-Content -Path (Join-Path $layerDir "platform-modules.yml") `
        -Value "platform-modules-information:`n  modules: []`n" -Encoding UTF8

    if ($WriteProvenance) {
        $prov = [ordered]@{
            layerId          = $LayerId
            installedVersion = $InstalledVersion
            schemaVersion    = $SchemaVersion
            sourceRepository = "https://example.com/layer.git"
            sourceRef        = "main"
            sourceCommit     = $InstalledCommit
            installedAt      = "2026-01-01T00:00:00Z"
            installedBy      = "mxagile-core/fetch-layer"
            previousVersion  = $null
            previousCommit   = $null
        }
        $prov | ConvertTo-Json | Set-Content -Path (Join-Path $layerDir "provenance.json") -Encoding UTF8
    }
    return $layerDir
}

function Get-ProvenanceContent {
    param([string]$ProjectRoot, [string]$LayerId = "test-layer")
    $path = Join-Path $ProjectRoot ".mxagile\layers\$LayerId\provenance.json"
    return Get-Content -LiteralPath $path -Raw
}

function Get-BackupCount {
    param([string]$ProjectRoot, [string]$LayerId = "test-layer")
    $pattern = Join-Path (Join-Path $ProjectRoot ".mxagile") "tmp_layer_backup_${LayerId}_*"
    return @(Get-ChildItem -Path $pattern -ErrorAction SilentlyContinue).Count
}

# =============================================================================
# -- EXISTING BASELINE TESTS (8) ----------------------------------------------
# =============================================================================

function Test-LayerNotInstalled {
    Write-Host "Running Test-LayerNotInstalled..."
    $project = New-TempProject
    $repo    = New-FakeLayerRepo -Id "not-here" -Version "1.2.0"
    try {
        pwsh -File $UpdateScript -RepositoryUrl $repo -ProjectRoot $project -NonInteractive
        Assert-Equal $LASTEXITCODE 0 "exit code when layer not installed"
        Write-Host "  PASSED"
    } finally {
        Remove-Item -LiteralPath $project -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $repo    -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Test-UntrackedInstallation {
    Write-Host "Running Test-UntrackedInstallation..."
    $project = New-TempProject
    $repo    = New-FakeLayerRepo -Id "test-layer" -Version "1.2.0"
    Install-FakeLayer -ProjectRoot $project -LayerId "test-layer" -InstalledVersion "1.0.0" -WriteProvenance $false | Out-Null
    try {
        pwsh -File $UpdateScript -RepositoryUrl $repo -ProjectRoot $project -NonInteractive
        Assert-Equal $LASTEXITCODE 3 "exit code for untracked installation"
        Write-Host "  PASSED"
    } finally {
        Remove-Item -LiteralPath $project -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $repo    -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Test-NoUpdateAvailable {
    Write-Host "Running Test-NoUpdateAvailable..."
    $project = New-TempProject
    $repo    = New-FakeLayerRepo -Id "test-layer" -Version "1.0.0"
    Install-FakeLayer -ProjectRoot $project -LayerId "test-layer" -InstalledVersion "1.0.0" | Out-Null
    try {
        pwsh -File $UpdateScript -RepositoryUrl $repo -ProjectRoot $project -NonInteractive
        Assert-Equal $LASTEXITCODE 0 "exit code when no update available"
        Write-Host "  PASSED"
    } finally {
        Remove-Item -LiteralPath $project -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $repo    -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Test-BlockedIncompatible {
    Write-Host "Running Test-BlockedIncompatible..."
    $project = New-TempProject
    $repo    = New-FakeLayerRepo -Id "test-layer" -Version "2.0.0" -CoreConstraint ">=2.0.0"
    Install-FakeLayer -ProjectRoot $project -LayerId "test-layer" -InstalledVersion "1.0.0" | Out-Null
    $provBefore = Get-ProvenanceContent -ProjectRoot $project
    try {
        pwsh -File $UpdateScript -RepositoryUrl $repo -ProjectRoot $project -NonInteractive
        Assert-Equal $LASTEXITCODE 2 "exit code for incompatible Core"
        $prov = Get-ProvenanceContent -ProjectRoot $project | ConvertFrom-Json
        Assert-Equal $prov.installedVersion "1.0.0" "installedVersion must be unchanged after blocked update"
        Assert-Equal (Get-BackupCount $project) 0 "no backup must exist - failure was pre-mutation"
        Write-Host "  PASSED"
    } finally {
        Remove-Item -LiteralPath $project -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $repo    -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Test-SuccessfulUpdate {
    Write-Host "Running Test-SuccessfulUpdate..."
    $project = New-TempProject
    $repo    = New-FakeLayerRepo -Id "test-layer" -Version "1.2.0"
    Install-FakeLayer -ProjectRoot $project -LayerId "test-layer" `
        -InstalledVersion "1.0.0" -InstalledCommit "oldcommitsha" | Out-Null
    try {
        pwsh -File $UpdateScript -RepositoryUrl $repo -ProjectRoot $project -NonInteractive
        Assert-Equal $LASTEXITCODE 0 "exit code for successful update"
        $prov = Get-ProvenanceContent -ProjectRoot $project | ConvertFrom-Json
        Assert-Equal $prov.installedVersion "1.2.0"                  "installedVersion must be new version"
        Assert-Equal $prov.previousVersion  "1.0.0"                  "previousVersion must be old version"
        Assert-Equal $prov.previousCommit   "oldcommitsha"            "previousCommit must be old commit"
        Assert-True  (-not [string]::IsNullOrWhiteSpace($prov.sourceCommit))  "sourceCommit must be set"
        Assert-True  (-not [string]::IsNullOrWhiteSpace($prov.installedAt))   "installedAt must be set"
        Assert-Equal $prov.installedBy "mxagile-core/update-layer"   "installedBy must identify updater"
        Assert-Equal $prov.layerId     "test-layer"                   "layerId must match"
        $lj = Get-Content -LiteralPath (Join-Path $project ".mxagile\layers\test-layer\layer.json") -Raw | ConvertFrom-Json
        Assert-Equal $lj.version "1.2.0" "installed layer.json must have new version"
        $manifest = Get-Content -LiteralPath (Join-Path $project ".mxagile\state\manifest.test-layer.md") -Raw
        Assert-True ($manifest -match "1\.2\.0") "state manifest must mention new version"
        Assert-True ($manifest -match "1\.0\.0") "state manifest must mention previous version"
        Assert-Equal (Get-BackupCount $project) 0 "backup must be removed on success"
        Write-Host "  PASSED"
    } finally {
        Remove-Item -LiteralPath $project -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $repo    -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Test-CheckOnlyMode {
    Write-Host "Running Test-CheckOnlyMode..."
    $project  = New-TempProject
    $repo     = New-FakeLayerRepo -Id "test-layer" -Version "1.5.0"
    Install-FakeLayer -ProjectRoot $project -LayerId "test-layer" -InstalledVersion "1.0.0" | Out-Null
    $before   = Get-ProvenanceContent -ProjectRoot $project
    try {
        pwsh -File $UpdateScript -RepositoryUrl $repo -ProjectRoot $project -CheckOnly -NonInteractive
        Assert-Equal $LASTEXITCODE 0 "exit code for check-only"
        Assert-Equal (Get-ProvenanceContent -ProjectRoot $project) $before "provenance must not change in check-only mode"
        Assert-Equal (Get-BackupCount $project) 0 "no backup in check-only mode"
        Write-Host "  PASSED"
    } finally {
        Remove-Item -LiteralPath $project -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $repo    -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Test-OwnershipBoundary {
    Write-Host "Running Test-OwnershipBoundary..."
    $project     = New-TempProject
    $repo        = New-FakeLayerRepo -Id "test-layer" -Version "1.2.0"
    $canaryPath  = Join-Path $project "requirements\canary.txt"
    New-Item -ItemType Directory -Path (Split-Path $canaryPath) -Force | Out-Null
    Set-Content -Path $canaryPath -Value "must not be touched" -Encoding UTF8
    Install-FakeLayer -ProjectRoot $project -LayerId "test-layer" -InstalledVersion "1.0.0" | Out-Null
    try {
        pwsh -File $UpdateScript -RepositoryUrl $repo -ProjectRoot $project -NonInteractive
        Assert-Equal $LASTEXITCODE 0 "exit code for ownership boundary test"
        Assert-FileExists $canaryPath "requirements/canary.txt must not be deleted"
        Assert-True ((Get-Content -LiteralPath $canaryPath -Raw) -match "must not be touched") "canary must be unmodified"
        Write-Host "  PASSED"
    } finally {
        Remove-Item -LiteralPath $project -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $repo    -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Test-LegacyProvenanceFallback {
    Write-Host "Running Test-LegacyProvenanceFallback..."
    $project  = New-TempProject
    $repo     = New-FakeLayerRepo -Id "test-layer" -Version "1.2.0"
    $layerDir = Install-FakeLayer -ProjectRoot $project -LayerId "test-layer" -InstalledVersion "1.0.0" -WriteProvenance $false
    $oldProv  = @{
        layer_id = "test-layer"; layer_name = "Test Layer"
        source = "https://example.com/layer.git"; requested_ref = "main"
        resolved_revision = "legacycommitabc"
    }
    $oldProv | ConvertTo-Json | Set-Content -Path (Join-Path $layerDir "provenance.json") -Encoding UTF8
    try {
        pwsh -File $UpdateScript -RepositoryUrl $repo -ProjectRoot $project -NonInteractive
        Assert-Equal $LASTEXITCODE 0 "exit code with legacy provenance"
        $prov = Get-ProvenanceContent -ProjectRoot $project | ConvertFrom-Json
        Assert-Equal $prov.installedVersion "1.2.0"         "installedVersion must be new version"
        Assert-Equal $prov.previousCommit   "legacycommitabc" "previousCommit must capture legacy resolved_revision"
        Write-Host "  PASSED"
    } finally {
        Remove-Item -LiteralPath $project -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $repo    -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# =============================================================================
# -- ADDITIONAL SAFETY TESTS ---------------------------------------------------
# =============================================================================

# --- 1. Failure BEFORE apply leaves all state unchanged ----------------------

function Test-FailureBeforeApplyLeavesStateUnchanged {
    # Contract: a failure at clone time (before backup) must not alter any
    # installed state. No backup directory must be created.
    Write-Host "Running Test-FailureBeforeApplyLeavesStateUnchanged..."
    $project       = New-TempProject
    $repo          = New-FakeLayerRepo -Id "test-layer" -Version "1.2.0"
    Install-FakeLayer -ProjectRoot $project -LayerId "test-layer" -InstalledVersion "1.0.0" | Out-Null
    $provBefore    = Get-ProvenanceContent -ProjectRoot $project

    # Delete repo to force git-clone failure
    Remove-Item -LiteralPath $repo -Recurse -Force

    try {
        pwsh -File $UpdateScript -RepositoryUrl $repo -ProjectRoot $project -NonInteractive
        Assert-Equal $LASTEXITCODE 1 "exit code when clone fails"
        # Provenance must be unchanged
        Assert-Equal (Get-ProvenanceContent -ProjectRoot $project) $provBefore "provenance must be unchanged after pre-apply failure"
        # No backup may have been created
        Assert-Equal (Get-BackupCount $project) 0 "no backup must exist when failure is pre-backup"
        Write-Host "  PASSED"
    } finally {
        Remove-Item -LiteralPath $project -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# --- 2. Injected failure during artifact replacement triggers rollback --------

function Test-ApplyFailureTriggersRollback {
    # Injection: target repo declares glossary artifact but omits the file.
    # After remove+copy, validation detects missing glossary -> throws -> rollback.
    # The rollback must restore the previously installed state.
    Write-Host "Running Test-ApplyFailureTriggersRollback..."
    $project  = New-TempProject
    # Target repo: omit glossary.yml from source - declared in artifacts but file absent
    $repo     = New-FakeLayerRepo -Id "test-layer" -Version "1.2.0" -IncludeGlossary $false
    Install-FakeLayer -ProjectRoot $project -LayerId "test-layer" `
        -InstalledVersion "1.0.0" -InstalledCommit "stablecommit" `
        -GlossaryContent "ORIGINAL-CONTENT-FOR-ROLLBACK-VERIFY`n" | Out-Null
    $provBefore = Get-ProvenanceContent -ProjectRoot $project
    try {
        pwsh -File $UpdateScript -RepositoryUrl $repo -ProjectRoot $project -NonInteractive
        Assert-Equal $LASTEXITCODE 1 "exit code when apply/validation fails"

        # Rollback must have restored previous provenance
        $provAfter = Get-ProvenanceContent -ProjectRoot $project | ConvertFrom-Json
        Assert-Equal $provAfter.installedVersion "1.0.0" "installedVersion must still be 1.0.0 after rollback"

        # Rollback must have restored original glossary
        $glossaryPath = Join-Path $project ".mxagile\layers\test-layer\glossary.yml"
        Assert-FileExists $glossaryPath "glossary.yml must be restored by rollback"
        Assert-True ((Get-Content -LiteralPath $glossaryPath -Raw) -match "ORIGINAL-CONTENT-FOR-ROLLBACK-VERIFY") `
            "glossary.yml must contain original content after rollback"

        # Backup must have been consumed by rollback (not left as an orphan)
        Assert-Equal (Get-BackupCount $project) 0 "backup dir must be consumed (moved) during rollback"

        Write-Host "  PASSED"
    } finally {
        Remove-Item -LiteralPath $project -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $repo    -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# --- 3. Injected failure during validation triggers rollback ------------------

function Test-ValidationFailureTriggersRollback {
    # Injection: platform-modules.yml declares a detailFile that does not exist.
    # Validation fires after artifacts are replaced -> throws -> rollback.
    Write-Host "Running Test-ValidationFailureTriggersRollback..."
    $project  = New-TempProject
    $repo     = New-FakeLayerRepo -Id "test-layer" -Version "1.2.0" -BadDetailFileRef $true
    Install-FakeLayer -ProjectRoot $project -LayerId "test-layer" `
        -InstalledVersion "1.0.0" -InstalledCommit "stablecommit2" `
        -GlossaryContent "VALIDATION-ROLLBACK-CANARY`n" | Out-Null
    try {
        pwsh -File $UpdateScript -RepositoryUrl $repo -ProjectRoot $project -NonInteractive
        Assert-Equal $LASTEXITCODE 1 "exit code when validation fails"
        $prov = Get-ProvenanceContent -ProjectRoot $project | ConvertFrom-Json
        Assert-Equal $prov.installedVersion "1.0.0" "installedVersion must still be 1.0.0"
        $glossaryPath = Join-Path $project ".mxagile\layers\test-layer\glossary.yml"
        Assert-FileExists $glossaryPath "glossary.yml must be restored"
        Assert-True ((Get-Content -LiteralPath $glossaryPath -Raw) -match "VALIDATION-ROLLBACK-CANARY") `
            "original glossary content must be restored by rollback"
        Assert-Equal (Get-BackupCount $project) 0 "backup consumed by rollback"
        Write-Host "  PASSED"
    } finally {
        Remove-Item -LiteralPath $project -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $repo    -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# --- 4. Rollback restores previous projection byte-for-byte ------------------

function Test-RollbackRestoresByteForByte {
    # Each Layer-owned file in the installed projection must be bit-identical
    # to its pre-update version after a failed update + rollback.
    Write-Host "Running Test-RollbackRestoresByteForByte..."
    $project = New-TempProject
    $repo    = New-FakeLayerRepo -Id "test-layer" -Version "1.2.0" -IncludeGlossary $false
    $layerDir = Install-FakeLayer -ProjectRoot $project -LayerId "test-layer" `
        -InstalledVersion "1.0.0" -GlossaryContent "BYTE-FOR-BYTE-CANARY-12345`n"

    # Capture exact byte content of all installed files before update
    $beforeGlossaryBytes = [System.IO.File]::ReadAllBytes((Join-Path $layerDir "glossary.yml"))
    $beforeLayerJsonBytes = [System.IO.File]::ReadAllBytes((Join-Path $layerDir "layer.json"))
    $beforeProvBytes      = [System.IO.File]::ReadAllBytes((Join-Path $layerDir "provenance.json"))

    try {
        pwsh -File $UpdateScript -RepositoryUrl $repo -ProjectRoot $project -NonInteractive
        Assert-Equal $LASTEXITCODE 1 "exit code for failing update (byte-for-byte test)"

        $afterGlossaryBytes  = [System.IO.File]::ReadAllBytes((Join-Path $layerDir "glossary.yml"))
        $afterLayerJsonBytes = [System.IO.File]::ReadAllBytes((Join-Path $layerDir "layer.json"))
        $afterProvBytes      = [System.IO.File]::ReadAllBytes((Join-Path $layerDir "provenance.json"))

        Assert-True ([System.Linq.Enumerable]::SequenceEqual($beforeGlossaryBytes, $afterGlossaryBytes))   "glossary.yml must be byte-for-byte identical after rollback"
        Assert-True ([System.Linq.Enumerable]::SequenceEqual($beforeLayerJsonBytes, $afterLayerJsonBytes)) "layer.json must be byte-for-byte identical after rollback"
        Assert-True ([System.Linq.Enumerable]::SequenceEqual($beforeProvBytes, $afterProvBytes))           "provenance.json must be byte-for-byte identical after rollback"

        Write-Host "  PASSED"
    } finally {
        Remove-Item -LiteralPath $project -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $repo    -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# --- 5. Rollback retains/restores previous provenance ------------------------

function Test-RollbackRetainsPreviousProvenance {
    # After rollback the provenance.json in the installed layer dir must
    # be identical to what it was before the failed update attempt.
    Write-Host "Running Test-RollbackRetainsPreviousProvenance..."
    $project = New-TempProject
    $repo    = New-FakeLayerRepo -Id "test-layer" -Version "1.2.0" -IncludeGlossary $false
    Install-FakeLayer -ProjectRoot $project -LayerId "test-layer" `
        -InstalledVersion "1.0.0" -InstalledCommit "provenance-canary-sha" | Out-Null
    $provBefore = Get-ProvenanceContent -ProjectRoot $project
    try {
        pwsh -File $UpdateScript -RepositoryUrl $repo -ProjectRoot $project -NonInteractive
        Assert-Equal $LASTEXITCODE 1 "exit code for failing update"
        $provAfter = Get-ProvenanceContent -ProjectRoot $project
        # Byte-level equality: provenance must be identical
        Assert-Equal $provAfter $provBefore "provenance.json must be identical to pre-update state after rollback"
        # Semantic check: installedVersion must still be 1.0.0
        $prov = $provAfter | ConvertFrom-Json
        Assert-Equal $prov.installedVersion "1.0.0" "installed version must be unchanged"
        Assert-Equal $prov.sourceCommit "provenance-canary-sha" "sourceCommit must be unchanged"
        Write-Host "  PASSED"
    } finally {
        Remove-Item -LiteralPath $project -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $repo    -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# --- 6. Failed update never records the target version as installed ----------

function Test-FailedUpdateNeverRecordsTargetVersion {
    # Even when validation runs after artifacts are applied, provenance must
    # NOT record the target version on failure. The target version is only
    # written after successful validation.
    Write-Host "Running Test-FailedUpdateNeverRecordsTargetVersion..."
    $project = New-TempProject
    # Use bad detailFile reference to trigger post-apply validation failure
    $repo    = New-FakeLayerRepo -Id "test-layer" -Version "9.9.9" -BadDetailFileRef $true
    Install-FakeLayer -ProjectRoot $project -LayerId "test-layer" -InstalledVersion "1.0.0" | Out-Null
    try {
        pwsh -File $UpdateScript -RepositoryUrl $repo -ProjectRoot $project -NonInteractive
        Assert-Equal $LASTEXITCODE 1 "exit code for failing update"
        $prov = Get-ProvenanceContent -ProjectRoot $project | ConvertFrom-Json
        Assert-False ($prov.installedVersion -eq "9.9.9") "target version 9.9.9 must NEVER be recorded as installed after failure"
        Assert-Equal  $prov.installedVersion "1.0.0"      "installed version must remain 1.0.0"
        # Also verify layer.json in installed dir still shows 1.0.0 (from rollback)
        $lj = Get-Content -LiteralPath (Join-Path $project ".mxagile\layers\test-layer\layer.json") -Raw | ConvertFrom-Json
        Assert-False ($lj.version -eq "9.9.9") "layer.json must not record target version after failed update"
        Write-Host "  PASSED"
    } finally {
        Remove-Item -LiteralPath $project -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $repo    -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# =============================================================================
# -- PROJECT-STATE PROTECTION VERIFICATION ------------------------------------
# =============================================================================

# --- 7. Project-owned artifacts unchanged during successful update ------------

function Test-ProjectArtifactsUnchangedDuringSuccessfulUpdate {
    Write-Host "Running Test-ProjectArtifactsUnchangedDuringSuccessfulUpdate..."
    $project = New-TempProject
    $repo    = New-FakeLayerRepo -Id "test-layer" -Version "1.2.0"
    Install-FakeLayer -ProjectRoot $project -LayerId "test-layer" -InstalledVersion "1.0.0" | Out-Null

    # Populate project-owned artifacts with canary content
    $canaries = @{
        "requirements\REQ-001.yml"     = "CANARY-REQ-001"
        "specs\SPEC-001.yml"           = "CANARY-SPEC-001"
        "planning\tasks\TASK-001.yml"  = "CANARY-TASK-001"
        "planning\lifecycle\process-state.yaml" = "CANARY-LIFECYCLE"
        "AGENT.md"                     = "CANARY-AGENT-MD"
    }
    foreach ($rel in $canaries.Keys) {
        $full = Join-Path $project $rel
        New-Item -ItemType Directory -Path (Split-Path $full) -Force | Out-Null
        [System.IO.File]::WriteAllText($full, $canaries[$rel], [System.Text.Encoding]::UTF8)
    }
    $beforeContents = @{}
    foreach ($rel in $canaries.Keys) {
        $beforeContents[$rel] = Get-Content -LiteralPath (Join-Path $project $rel) -Raw
    }

    try {
        pwsh -File $UpdateScript -RepositoryUrl $repo -ProjectRoot $project -NonInteractive
        Assert-Equal $LASTEXITCODE 0 "exit code for successful update"
        foreach ($rel in $canaries.Keys) {
            $after = Get-Content -LiteralPath (Join-Path $project $rel) -Raw
            Assert-Equal $after $beforeContents[$rel] "$rel must be unchanged after successful update"
        }
        Write-Host "  PASSED"
    } finally {
        Remove-Item -LiteralPath $project -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $repo    -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# --- 8. Project-owned artifacts unchanged during failed update / rollback -----

function Test-ProjectArtifactsUnchangedDuringFailedUpdate {
    Write-Host "Running Test-ProjectArtifactsUnchangedDuringFailedUpdate..."
    $project = New-TempProject
    $repo    = New-FakeLayerRepo -Id "test-layer" -Version "1.2.0" -BadDetailFileRef $true
    Install-FakeLayer -ProjectRoot $project -LayerId "test-layer" -InstalledVersion "1.0.0" | Out-Null

    $canaries = @{
        "requirements\REQ-001.yml"     = "CANARY-FAILED-REQ"
        "specs\SPEC-001.yml"           = "CANARY-FAILED-SPEC"
        "planning\tasks\TASK-001.yml"  = "CANARY-FAILED-TASK"
        "planning\evidence\E-001.md"   = "CANARY-FAILED-EVIDENCE"
    }
    foreach ($rel in $canaries.Keys) {
        $full = Join-Path $project $rel
        New-Item -ItemType Directory -Path (Split-Path $full) -Force | Out-Null
        [System.IO.File]::WriteAllText($full, $canaries[$rel], [System.Text.Encoding]::UTF8)
    }

    try {
        pwsh -File $UpdateScript -RepositoryUrl $repo -ProjectRoot $project -NonInteractive
        Assert-Equal $LASTEXITCODE 1 "exit code for failing update with rollback"
        foreach ($rel in $canaries.Keys) {
            $after = Get-Content -LiteralPath (Join-Path $project $rel) -Raw
            Assert-Equal $after $canaries[$rel] "$rel must be unchanged after failed update + rollback"
        }
        Write-Host "  PASSED"
    } finally {
        Remove-Item -LiteralPath $project -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $repo    -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# --- 9. Mendix application content untouched ---------------------------------

function Test-MendixApplicationContentUntouched {
    # Tests both successful update and failed update (two runs).
    Write-Host "Running Test-MendixApplicationContentUntouched..."
    $project = New-TempProject

    # Place Mendix application content as canary files
    $mendixPaths = @(
        "project.mpr",
        "mprcontents\units.json",
        "modules\Administration\module.xml",
        "javasource\com\example\MyAction.java",
        "themesource\atlas_ui_resources\web\main.css"
    )
    foreach ($rel in $mendixPaths) {
        $full = Join-Path $project $rel
        New-Item -ItemType Directory -Path (Split-Path $full) -Force | Out-Null
        [System.IO.File]::WriteAllText($full, "MENDIX-CANARY: $rel", [System.Text.Encoding]::UTF8)
    }

    $beforeContents = @{}
    foreach ($rel in $mendixPaths) {
        $beforeContents[$rel] = Get-Content -LiteralPath (Join-Path $project $rel) -Raw
    }

    Install-FakeLayer -ProjectRoot $project -LayerId "test-layer" -InstalledVersion "1.0.0" | Out-Null

    # Run 1: successful update
    $repo1 = New-FakeLayerRepo -Id "test-layer" -Version "1.2.0"
    try {
        pwsh -File $UpdateScript -RepositoryUrl $repo1 -ProjectRoot $project -NonInteractive
        Assert-Equal $LASTEXITCODE 0 "successful update exit code"
    } finally {
        Remove-Item -LiteralPath $repo1 -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Run 2: failing update (rollback)
    $repo2 = New-FakeLayerRepo -Id "test-layer" -Version "1.3.0" -BadDetailFileRef $true
    try {
        pwsh -File $UpdateScript -RepositoryUrl $repo2 -ProjectRoot $project -NonInteractive
        Assert-Equal $LASTEXITCODE 1 "failing update exit code"
    } finally {
        Remove-Item -LiteralPath $repo2 -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Verify all Mendix paths unchanged
    foreach ($rel in $mendixPaths) {
        $after = Get-Content -LiteralPath (Join-Path $project $rel) -Raw
        Assert-Equal $after $beforeContents[$rel] "Mendix file '$rel' must be untouched"
    }

    try { Write-Host "  PASSED" }
    finally {
        Remove-Item -LiteralPath $project -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# =============================================================================
# -- IDEMPOTENCY ---------------------------------------------------------------
# =============================================================================

# --- 10. Repeated update to already-installed version is idempotent ----------

function Test-RepeatedUpdateIsIdempotent {
    Write-Host "Running Test-RepeatedUpdateIsIdempotent..."
    $project = New-TempProject
    $repo    = New-FakeLayerRepo -Id "test-layer" -Version "1.2.0"
    Install-FakeLayer -ProjectRoot $project -LayerId "test-layer" -InstalledVersion "1.0.0" | Out-Null

    # First update: 1.0.0 -> 1.2.0 (should succeed)
    pwsh -File $UpdateScript -RepositoryUrl $repo -ProjectRoot $project -NonInteractive
    Assert-Equal $LASTEXITCODE 0 "first update exit code"
    $provAfterFirst = Get-ProvenanceContent -ProjectRoot $project

    # Second update with same repo (1.2.0 -> 1.2.0): should be NO_UPDATE_AVAILABLE
    pwsh -File $UpdateScript -RepositoryUrl $repo -ProjectRoot $project -NonInteractive
    Assert-Equal $LASTEXITCODE 0 "second update exit code (no-op)"
    $provAfterSecond = Get-ProvenanceContent -ProjectRoot $project

    try {
        # Provenance must be unchanged between first and second run
        Assert-Equal $provAfterSecond $provAfterFirst "provenance must be unchanged on repeated update to same version"
        $prov = $provAfterSecond | ConvertFrom-Json
        Assert-Equal $prov.installedVersion "1.2.0" "installed version must still be 1.2.0"
        Assert-Equal (Get-BackupCount $project) 0 "no backup must exist after idempotent run"
        Write-Host "  PASSED"
    } finally {
        Remove-Item -LiteralPath $project -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $repo    -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# =============================================================================
# -- SECURITY / PATH TRAVERSAL -------------------------------------------------
# =============================================================================

# --- 11. Malicious ../ path traversal in artifact manifest is rejected BEFORE mutation

function Test-PathTraversalRejectedBeforeMutation {
    # The pre-backup Confirm-ArtifactManifestSafety check must fire before any
    # filesystem mutation. After this test no backup should exist and provenance
    # must be unchanged.
    Write-Host "Running Test-PathTraversalRejectedBeforeMutation..."
    $project = New-TempProject
    # Target repo declares a malicious relative artifact path
    $repo    = New-FakeLayerRepo -Id "test-layer" -Version "1.2.0" -MaliciousArtifact "../requirements/evil.txt"
    Install-FakeLayer -ProjectRoot $project -LayerId "test-layer" -InstalledVersion "1.0.0" | Out-Null
    $provBefore = Get-ProvenanceContent -ProjectRoot $project

    # Canary outside layer boundary
    $evilTarget = Join-Path $project "requirements\evil.txt"
    New-Item -ItemType Directory -Path (Split-Path $evilTarget) -Force | Out-Null
    Set-Content -Path $evilTarget -Value "SHOULD-NOT-BE-OVERWRITTEN" -Encoding UTF8

    try {
        pwsh -File $UpdateScript -RepositoryUrl $repo -ProjectRoot $project -NonInteractive
        Assert-Equal $LASTEXITCODE 1 "exit code when traversal path detected"
        Assert-Equal (Get-BackupCount $project) 0 "no backup must exist - rejection is pre-mutation"
        Assert-Equal (Get-ProvenanceContent -ProjectRoot $project) $provBefore "provenance must be unchanged"
        # The evil target must not have been created/modified
        $evilContent = Get-Content -LiteralPath $evilTarget -Raw
        Assert-True ($evilContent -match "SHOULD-NOT-BE-OVERWRITTEN") "target outside boundary must not be modified"
        Write-Host "  PASSED"
    } finally {
        Remove-Item -LiteralPath $project -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $repo    -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# --- 12. Absolute / out-of-bound install paths are rejected before mutation ---

function Test-AbsolutePathRejectedBeforeMutation {
    Write-Host "Running Test-AbsolutePathRejectedBeforeMutation..."
    $project = New-TempProject
    Install-FakeLayer -ProjectRoot $project -LayerId "test-layer" -InstalledVersion "1.0.0" | Out-Null
    $provBefore = Get-ProvenanceContent -ProjectRoot $project

    # Determine an absolute path valid for the current platform
    $isNonWindows = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows) -eq $false
    $absolutePath = if ($isNonWindows) { "/tmp/mxagile-evil.txt" } else { "C:\Windows\Temp\mxagile-evil.txt" }
    $repo = New-FakeLayerRepo -Id "test-layer" -Version "1.2.0" -MaliciousArtifact $absolutePath

    try {
        pwsh -File $UpdateScript -RepositoryUrl $repo -ProjectRoot $project -NonInteractive
        Assert-Equal $LASTEXITCODE 1 "exit code when absolute path detected"
        Assert-Equal (Get-BackupCount $project) 0 "no backup must exist - rejection is pre-mutation"
        Assert-Equal (Get-ProvenanceContent -ProjectRoot $project) $provBefore "provenance must be unchanged"
        Write-Host "  PASSED"
    } finally {
        Remove-Item -LiteralPath $project -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $repo    -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# =============================================================================
# -- CROSS-PLATFORM VERIFICATION -----------------------------------------------
# =============================================================================

# --- 13. Windows path traversal variants are caught --------------------------

function Test-WindowsPathTraversalVariants {
    # Verifies that Windows-style path traversal with backslash separators is
    # caught by Confirm-ArtifactManifestSafety on all platforms (PowerShell Core
    # normalizes both separators via GetFullPath).
    Write-Host "Running Test-WindowsPathTraversalVariants..."

    $traversalVariants = @(
        "..\requirements\evil.txt",    # Windows backslash relative traversal
        "..\evil",                      # backslash traversal, short
        "subdir\..\..\..\evil.txt"     # multi-level backslash traversal
    )

    foreach ($malicious in $traversalVariants) {
        $project = New-TempProject
        $repo    = New-FakeLayerRepo -Id "test-layer" -Version "1.2.0" -MaliciousArtifact $malicious
        Install-FakeLayer -ProjectRoot $project -LayerId "test-layer" -InstalledVersion "1.0.0" | Out-Null
        $provBefore = Get-ProvenanceContent -ProjectRoot $project
        try {
            pwsh -File $UpdateScript -RepositoryUrl $repo -ProjectRoot $project -NonInteractive
            Assert-Equal $LASTEXITCODE 1 "exit 1 for backslash traversal: '$malicious'"
            Assert-Equal (Get-BackupCount $project) 0 "no backup for: '$malicious'"
            Assert-Equal (Get-ProvenanceContent -ProjectRoot $project) $provBefore "provenance unchanged for: '$malicious'"
        } finally {
            Remove-Item -LiteralPath $project -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $repo    -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    Write-Host "  PASSED"
}

# --- 14. Linux / headless / PowerShell Core path behavior is covered ----------

function Test-CrossPlatformPathBehavior {
    # Verifies Unix-style absolute paths and forward-slash traversal are caught
    # on the current platform under PowerShell Core (which is the execution host
    # for update-layer.ps1 in all environments).
    Write-Host "Running Test-CrossPlatformPathBehavior..."

    $variants = @(
        "../requirements/evil.txt",    # Unix-style forward-slash traversal
        "subdir/../../evil.txt",       # multi-level forward-slash traversal
        "/etc/evil",                   # Unix absolute path
        "/tmp/evil.txt"                # another Unix absolute
    )

    foreach ($malicious in $variants) {
        $project = New-TempProject
        $repo    = New-FakeLayerRepo -Id "test-layer" -Version "1.2.0" -MaliciousArtifact $malicious
        Install-FakeLayer -ProjectRoot $project -LayerId "test-layer" -InstalledVersion "1.0.0" | Out-Null
        $provBefore = Get-ProvenanceContent -ProjectRoot $project
        try {
            pwsh -File $UpdateScript -RepositoryUrl $repo -ProjectRoot $project -NonInteractive
            Assert-Equal $LASTEXITCODE 1 "exit 1 for path: '$malicious'"
            Assert-Equal (Get-BackupCount $project) 0 "no backup for: '$malicious'"
            Assert-Equal (Get-ProvenanceContent -ProjectRoot $project) $provBefore "provenance unchanged for: '$malicious'"
        } finally {
            Remove-Item -LiteralPath $project -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $repo    -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    Write-Host "  PASSED"
}

# =============================================================================
# -- SCHEMAVERSION SEMANTICS ---------------------------------------------------
# =============================================================================
#
# schemaVersion semantics (see header comment at top of this file):
#   A schema version change does NOT trigger a stateful N->N+1 migration of the
#   installed projection. The updater uses backup->replace->validate->provenance
#   regardless of schema version. With -NonInteractive the developer confirmation
#   is skipped; the replace flow is unchanged.

# --- 15. schemaVersion change proceeds without migration --------------------

function Test-SchemaVersionChangeProceedsWithoutMigration {
    # Target has schemaVersion "2" (was "1"). With -NonInteractive the update
    # must proceed using the normal replace flow - no migration is attempted.
    # The NEW content from the target repo replaces the old content wholesale.
    # The old content is NOT transformed into the new format; it is just replaced.
    Write-Host "Running Test-SchemaVersionChangeProceedsWithoutMigration..."
    $project  = New-TempProject
    $repo     = New-FakeLayerRepo -Id "test-layer" -Version "1.2.0" -SchemaVersion "2"
    Install-FakeLayer -ProjectRoot $project -LayerId "test-layer" `
        -InstalledVersion "1.0.0" -SchemaVersion "1" | Out-Null
    try {
        pwsh -File $UpdateScript -RepositoryUrl $repo -ProjectRoot $project -NonInteractive
        Assert-Equal $LASTEXITCODE 0 "schema version bump must not block update with -NonInteractive"
        $prov = Get-ProvenanceContent -ProjectRoot $project | ConvertFrom-Json
        Assert-Equal $prov.installedVersion "1.2.0" "update must complete and record new version"
        Assert-Equal $prov.schemaVersion    "2"     "new schemaVersion must be recorded in provenance"
        # The installed content must be the TARGET's content (replacement, not migration)
        $installedGlossary = Get-Content -LiteralPath (Join-Path $project ".mxagile\layers\test-layer\glossary.yml") -Raw
        Assert-True ($installedGlossary -match "TestTerm") "installed content must be TARGET content (replacement, not migration of old content)"
        Write-Host "  PASSED"
    } finally {
        Remove-Item -LiteralPath $project -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $repo    -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# --- 16. Same schemaVersion requires no developer confirmation ---------------

function Test-SchemaVersionSameNoPromptRequired {
    # When schemaVersion is unchanged, the updater must never prompt and must
    # proceed to update without any interaction.
    Write-Host "Running Test-SchemaVersionSameNoPromptRequired..."
    $project = New-TempProject
    $repo    = New-FakeLayerRepo -Id "test-layer" -Version "1.2.0" -SchemaVersion "1"
    Install-FakeLayer -ProjectRoot $project -LayerId "test-layer" `
        -InstalledVersion "1.0.0" -SchemaVersion "1" | Out-Null
    try {
        # Run WITHOUT -NonInteractive - if the script tries to Read-Host it would hang/fail
        # in a non-interactive child process. Successful exit proves no prompt was issued.
        $job = Start-Job -ScriptBlock {
            param($script, $repo, $project)
            & pwsh -File $script -RepositoryUrl $repo -ProjectRoot $project | Out-Null
            return $LASTEXITCODE
        } -ArgumentList $UpdateScript, $repo, $project

        # Timeout is 120s: Start-Job+pwsh overhead is ~24s on this machine; the actual
        # update is ~20-30s. 120s still catches an infinite Read-Host hang.
        $completed = Wait-Job $job -Timeout 120
        if ($null -eq $completed) {
            Stop-Job $job
            throw "Update timed out - likely blocked waiting for interactive prompt (schema version unchanged should not prompt)"
        }
        $exitCode = Receive-Job $job
        Remove-Job $job

        Assert-Equal $exitCode 0 "update must succeed without -NonInteractive when schema unchanged"
        $prov = Get-ProvenanceContent -ProjectRoot $project | ConvertFrom-Json
        Assert-Equal $prov.installedVersion "1.2.0" "update must complete"
        Write-Host "  PASSED"
    } finally {
        Remove-Item -LiteralPath $project -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $repo    -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# =============================================================================
# -- SPARSE ACQUISITION / LONG-PATH SAFETY -------------------------------------
# =============================================================================

# --- 17. Deep-nested repo content does not block acquisition -----------------

function Test-SparseAcquisitionExcludesIrrelevantContent {
    # Verifies that update-layer.ps1 succeeds when the Layer repository contains
    # deeply-nested reference-app content (e.g. SampleApp/node_modules/...) whose
    # full path would exceed the Windows 260-char MAX_PATH limit under a naive
    # "git clone --depth 1".  The sparse-checkout acquisition must materialize
    # only declared artifacts and must complete without error.
    Write-Host "Running Test-SparseAcquisitionExcludesIrrelevantContent..."
    $project = New-TempProject
    $repo    = New-FakeLayerRepo -Id "test-layer" -Version "1.2.0" -AddDeepNestedContent $true
    Install-FakeLayer -ProjectRoot $project -LayerId "test-layer" -InstalledVersion "1.0.0" | Out-Null
    try {
        pwsh -File $UpdateScript -RepositoryUrl $repo -ProjectRoot $project -NonInteractive
        Assert-Equal $LASTEXITCODE 0 "update from repo with deep-nested content must succeed"

        $layerDir = Join-Path $project ".mxagile\layers\test-layer"
        Assert-FileExists (Join-Path $layerDir "glossary.yml") "declared artifact must be installed"

        # Undeclared reference-app content must not appear in the installed layer
        Assert-False (Test-Path -LiteralPath (Join-Path $layerDir "SampleApp")) `
            "SampleApp reference-app content must not be installed"
        Write-Host "  PASSED"
    } finally {
        Remove-Item -LiteralPath $project -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $repo    -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# --- 18. Acquisition does not modify global git core.longpaths ---------------

function Test-AcquisitionDoesNotModifyGlobalGitConfig {
    # Verifies that running update-layer.ps1 leaves the developer's global
    # git configuration unchanged.  core.longpaths is scoped to the acquisition
    # temp repo only; the global value (whether set or absent) must be preserved.
    Write-Host "Running Test-AcquisitionDoesNotModifyGlobalGitConfig..."
    $project = New-TempProject
    $repo    = New-FakeLayerRepo -Id "test-layer" -Version "1.2.0"
    Install-FakeLayer -ProjectRoot $project -LayerId "test-layer" -InstalledVersion "1.0.0" | Out-Null

    $longpathsBefore     = & git config --global --get core.longpaths 2>$null
    $longpathsBeforeExit = $LASTEXITCODE   # 0 = key exists, 1 = key absent

    try {
        pwsh -File $UpdateScript -RepositoryUrl $repo -ProjectRoot $project -NonInteractive
        Assert-Equal $LASTEXITCODE 0 "update must succeed"

        $longpathsAfter     = & git config --global --get core.longpaths 2>$null
        $longpathsAfterExit = $LASTEXITCODE

        Assert-Equal $longpathsAfterExit $longpathsBeforeExit `
            "global core.longpaths presence must be unchanged after update"
        if ($longpathsBeforeExit -eq 0) {
            Assert-Equal $longpathsAfter $longpathsBefore `
                "global core.longpaths value must be unchanged after update"
        }
        Write-Host "  PASSED"
    } finally {
        Remove-Item -LiteralPath $project -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $repo    -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# --- 19. PS 5.1 invocation produces a clear version-requirement diagnostic ---

function Test-PS51RuntimeDiagnostic {
    # Verifies that invoking update-layer.ps1 via Windows PowerShell 5.1 exits
    # non-zero and emits a clear "#Requires -Version 7.0" diagnostic rather than
    # a cryptic parser error.  Skipped on platforms where powershell.exe is absent.
    Write-Host "Running Test-PS51RuntimeDiagnostic..."

    if (-not (Get-Command powershell.exe -ErrorAction SilentlyContinue)) {
        Write-Host "  SKIPPED (powershell.exe not available on this platform)"
        return
    }

    $output   = & powershell.exe -NoProfile -NonInteractive -File $UpdateScript `
                    -RepositoryUrl "https://example.com/fake" 2>&1
    $exitCode = $LASTEXITCODE

    Assert-True ($exitCode -ne 0) "PS5.1 invocation must exit non-zero"
    $outputStr = ($output -join " ")
    Assert-True ($outputStr -match "(?i)(version|7\.|requires)") `
        "PS5.1 output must contain a version-requirement diagnostic (got: $outputStr)"
    Write-Host "  PASSED"
}

# =============================================================================
# -- Test runner ---------------------------------------------------------------
# =============================================================================

$passed = 0
$failed = 0

$tests = @(
    # Baseline (8)
    "Test-LayerNotInstalled",
    "Test-UntrackedInstallation",
    "Test-NoUpdateAvailable",
    "Test-BlockedIncompatible",
    "Test-SuccessfulUpdate",
    "Test-CheckOnlyMode",
    "Test-OwnershipBoundary",
    "Test-LegacyProvenanceFallback",
    # Additional safety tests (6)
    "Test-FailureBeforeApplyLeavesStateUnchanged",
    "Test-ApplyFailureTriggersRollback",
    "Test-ValidationFailureTriggersRollback",
    "Test-RollbackRestoresByteForByte",
    "Test-RollbackRetainsPreviousProvenance",
    "Test-FailedUpdateNeverRecordsTargetVersion",
    # Project-state protection (3)
    "Test-ProjectArtifactsUnchangedDuringSuccessfulUpdate",
    "Test-ProjectArtifactsUnchangedDuringFailedUpdate",
    "Test-MendixApplicationContentUntouched",
    # Idempotency (1)
    "Test-RepeatedUpdateIsIdempotent",
    # Security / path traversal (2)
    "Test-PathTraversalRejectedBeforeMutation",
    "Test-AbsolutePathRejectedBeforeMutation",
    # Cross-platform (2)
    "Test-WindowsPathTraversalVariants",
    "Test-CrossPlatformPathBehavior",
    # schemaVersion semantics (2)
    "Test-SchemaVersionChangeProceedsWithoutMigration",
    "Test-SchemaVersionSameNoPromptRequired",
    # Sparse acquisition / long-path safety (3)
    "Test-SparseAcquisitionExcludesIrrelevantContent",
    "Test-AcquisitionDoesNotModifyGlobalGitConfig",
    "Test-PS51RuntimeDiagnostic"
)

Write-Host ""
Write-Host "=======================================" -ForegroundColor Cyan
Write-Host "MxAgile Layer Update - Safety Regression Suite"
Write-Host "=======================================" -ForegroundColor Cyan
Write-Host "Tests: $($tests.Count)"
Write-Host ""

foreach ($test in $tests) {
    try {
        & $test
        $passed++
    } catch {
        Write-Host "  FAILED: $test" -ForegroundColor Red
        Write-Host "    $($_.Exception.Message)" -ForegroundColor Red
        $failed++
    }
}

Write-Host ""
Write-Host "=======================================" -ForegroundColor $(if ($failed -eq 0) { "Green" } else { "Red" })
Write-Host "Layer Update Tests: $passed passed, $failed failed  (total: $($tests.Count))"
Write-Host "=======================================" -ForegroundColor $(if ($failed -eq 0) { "Green" } else { "Red" })

if ($failed -gt 0) { exit 1 } else { exit 0 }
