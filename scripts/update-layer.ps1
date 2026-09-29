#Requires -Version 7.0
<#
.SYNOPSIS
    Updates an installed MxAgile Company Layer independently of MxAgile Core.

.DESCRIPTION
    Implements the full Company Layer update lifecycle:

        DETECT installed state (provenance.json)
            -> UNTRACKED  : layer dir exists but no provenance — stop with diagnostic
            -> NOT_INSTALLED : layer absent — stop, redirect to setup
            -> UPDATE_CHECK : compare versions
        RESOLVE TARGET version from repository
        COMPARE installed vs target version
            -> NO_UPDATE_AVAILABLE : installed >= target
            -> UPDATE_AVAILABLE    : proceed
        COMPATIBILITY: verify layer.json → compatibility.mxagileCore
            -> BLOCKED_INCOMPATIBLE : stop with diagnostic
        PLAN: identify Layer-owned artifacts
        BACKUP: copy existing layer dir to temp backup
        APPLY: replace Layer-owned artifacts only (ownership boundary enforced)
        VALIDATE: verify installed state
        WRITE PROVENANCE: write all UPDATE-CONTRACT.md required fields
        REPORT: lifecycle impact notice
        CLEANUP: remove backup on success
        ROLLBACK: restore backup on failure

    Company Layer updates are independent of MxAgile Core updates.
    No project-owned artifacts (requirements/, specs/, planning/, Mendix files)
    are ever modified by this script.

.PARAMETER RepositoryUrl
    Git URL of the Company Layer repository.

.PARAMETER Ref
    Git branch, tag, or commit ref to check for updates. Defaults to "main".

.PARAMETER ProjectRoot
    Root directory of the target Mendix project. Defaults to current directory.

.PARAMETER CheckOnly
    Detect and report update availability without applying any changes.

.PARAMETER NonInteractive
    Skip developer confirmation prompt for schema version changes.
    Use in CI and automated invocations.
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$RepositoryUrl,

    [ValidateNotNullOrEmpty()]
    [string]$Ref = "main",

    [string]$ProjectRoot = (Get-Location).Path,

    [switch]$CheckOnly,

    [switch]$NonInteractive
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# =============================================================================
# Semver helpers
# =============================================================================

function Get-SemVerParts {
    param([string]$v)
    $v = $v.Trim().TrimStart('v')
    $parts = ($v -split '\.', 3)
    @(
        [int]($parts[0] -replace '[^\d].*$', ''),
        [int]($(if ($parts.Count -gt 1) { $parts[1] -replace '[^\d].*$', '' } else { 0 })),
        [int]($(if ($parts.Count -gt 2) { $parts[2] -replace '[^\d].*$', '' } else { 0 }))
    )
}

function Compare-SemVer {
    param([string]$a, [string]$b)
    # Returns -1 (a < b), 0 (a == b), 1 (a > b)
    $ap = Get-SemVerParts $a
    $bp = Get-SemVerParts $b
    for ($i = 0; $i -lt 3; $i++) {
        if ($ap[$i] -lt $bp[$i]) { return -1 }
        if ($ap[$i] -gt $bp[$i]) { return 1 }
    }
    return 0
}

function Test-CoreCompatibility {
    # Returns $true when $coreVersion satisfies $constraint (e.g. ">=1.0.0")
    param([string]$coreVersion, [string]$constraint)
    $c = $constraint.Trim()
    if     ($c -match '^>=(.+)$') { return (Compare-SemVer $coreVersion $Matches[1]) -ge 0 }
    elseif ($c -match '^>(.+)$')  { return (Compare-SemVer $coreVersion $Matches[1]) -gt 0 }
    elseif ($c -match '^<=(.+)$') { return (Compare-SemVer $coreVersion $Matches[1]) -le 0 }
    elseif ($c -match '^<(.+)$')  { return (Compare-SemVer $coreVersion $Matches[1]) -lt 0 }
    elseif ($c -match '^=?(.+)$') { return (Compare-SemVer $coreVersion $Matches[1]) -eq 0 }
    return $false
}

# =============================================================================
# Helpers
# =============================================================================

function Remove-TempDir {
    param([string]$Path)
    if (-not [string]::IsNullOrWhiteSpace($Path) -and (Test-Path -LiteralPath $Path)) {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Get-JsonProp {
    # Safe property accessor for PSCustomObject under Set-StrictMode -Version Latest.
    # Returns [string]$prop.Value if the property exists, otherwise "".
    # Avoids the strict-mode error thrown when accessing a non-existent property directly.
    param([psobject]$Obj, [string]$Name)
    $prop = $Obj.PSObject.Properties[$Name]
    if ($null -ne $prop) { return [string]$prop.Value }
    return ""
}

function Assert-LayerBoundary {
    # Throws if $DestPath would escape the Layer's owned directory.
    param([string]$DestPath, [string]$LayerRoot)
    $allowedBase = [System.IO.Path]::GetFullPath($LayerRoot).TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
    $normalized  = [System.IO.Path]::GetFullPath($DestPath).TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
    if (-not $normalized.StartsWith($allowedBase)) {
        throw "SECURITY: attempted write outside Layer boundary. Path: $DestPath  Boundary: $LayerRoot"
    }
}

function Confirm-ArtifactManifestSafety {
    # Validates every artifact path declared in the target Layer manifest BEFORE
    # backup creation — i.e., before any mutation to the installed projection.
    # Rejects:
    #   - absolute paths  (Unix: starts with /,  Windows: drive letter or leading \)
    #   - path-traversal  (any component equal to '..')
    #   - paths that normalize outside the Layer boundary after Join-Path
    #
    # schemaVersion semantics note:
    #   schemaVersion describes the Layer package/contract format that Core must
    #   understand. A schemaVersion difference warrants developer confirmation and
    #   may require Core compatibility gating, but it does NOT trigger a stateful
    #   N->N+1 migration of the previously installed Layer projection. If Core
    #   understands the target schema, the normal backup->replace->validate->
    #   provenance flow is sufficient unless the Layer contract explicitly states
    #   otherwise. This function is not schema-version-sensitive; it applies the
    #   same path-safety rules regardless of schema version.
    param([psobject]$Artifacts, [string]$LayerRoot)
    if ($null -eq $Artifacts) { return }
    foreach ($prop in $Artifacts.PSObject.Properties) {
        $relPath = ([string]$prop.Value).Trim()
        if ([string]::IsNullOrWhiteSpace($relPath)) { continue }

        # Reject absolute Unix paths (start with /) and Windows paths (drive:\ or leading \)
        if ($relPath -match '^[/\\]' -or $relPath -match '^[A-Za-z]:') {
            throw "SECURITY: artifact '$($prop.Name)' declares an absolute path: '$relPath'"
        }

        # Reject any path component equal to '..' (traversal)
        $components = $relPath -split '[/\\]'
        foreach ($component in $components) {
            if ($component -eq '..') {
                throw "SECURITY: artifact '$($prop.Name)' contains a path traversal component '..': '$relPath'"
            }
        }

        # Final normalized boundary check (defence-in-depth)
        try {
            $fullPath = [System.IO.Path]::GetFullPath((Join-Path $LayerRoot $relPath))
        } catch {
            throw "SECURITY: artifact '$($prop.Name)' produced an invalid path: '$relPath'"
        }
        $boundary = [System.IO.Path]::GetFullPath($LayerRoot).TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
        if (-not $fullPath.StartsWith($boundary)) {
            throw "SECURITY: artifact '$($prop.Name)' resolves outside the Layer boundary: '$relPath'"
        }
    }
}

function Copy-LayerArtifacts {
    # Copies Layer-owned artifacts from $SourceDir to $DestDir.
    # Excludes: .git, provenance.json, and all paths not declared in layer.json → artifacts.
    param(
        [string]$SourceDir,
        [string]$DestDir,
        [psobject]$Artifacts   # layer.json → artifacts (may be $null for full replace)
    )

    # Build whitelist of top-level names to copy from the declared artifact paths.
    # We always include layer.json itself.
    $allowed = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $allowed.Add("layer.json") | Out-Null

    if ($null -ne $Artifacts) {
        foreach ($prop in $Artifacts.PSObject.Properties) {
            $relPath = [string]$prop.Value
            # The top-level name is everything up to the first / or \
            $topLevel = ($relPath -split '[/\\]', 2)[0].Trim()
            if (-not [string]::IsNullOrWhiteSpace($topLevel)) {
                $allowed.Add($topLevel) | Out-Null
            }
        }
    }

    Get-ChildItem -LiteralPath $SourceDir -Force |
        Where-Object { $_.Name -ne ".git" -and $_.Name -ne "provenance.json" -and $allowed.Contains($_.Name) } |
        ForEach-Object {
            $dest = Join-Path $DestDir $_.Name
            Assert-LayerBoundary $dest $DestDir
            if ($_.PSIsContainer) {
                Copy-Item -LiteralPath $_.FullName -Destination $dest -Recurse -Force
            } else {
                Copy-Item -LiteralPath $_.FullName -Destination $dest -Force
            }
        }
}

# =============================================================================
# Paths
# =============================================================================

$ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
if (-not (Test-Path -LiteralPath $ProjectRoot -PathType Container)) {
    throw "Project root does not exist: $ProjectRoot"
}

$MxAgileDir   = Join-Path $ProjectRoot ".mxagile"
$LayersDir    = Join-Path $MxAgileDir "layers"
$StateDir     = Join-Path $MxAgileDir "state"
$TempCloneDir = Join-Path $MxAgileDir "tmp_layer_update"
$BackupBase   = Join-Path $MxAgileDir "tmp_layer_backup"

# Variables accessible across try/catch
$tempClonePath   = $null
$backupPath      = $null
$layerDir        = $null
$installedVersion = $null
$installedCommit  = $null

Write-Host ""
Write-Host "=======================================" -ForegroundColor Cyan
Write-Host "MxAgile Company Layer Update" -ForegroundColor Cyan
Write-Host "=======================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Repository : $RepositoryUrl"
Write-Host "Ref        : $Ref"
Write-Host "Project    : $ProjectRoot"
if ($CheckOnly) { Write-Host "Mode       : CHECK ONLY (no changes will be applied)" -ForegroundColor Yellow }
Write-Host ""

try {
    # =========================================================================
    # CR-03: Read installed Core version (required before any mutation)
    # =========================================================================

    $coreVersionFile = Join-Path $MxAgileDir "version.yaml"
    $coreVersion = "0.0.0"
    if (Test-Path -LiteralPath $coreVersionFile -PathType Leaf) {
        $coreVersionRaw = Get-Content -LiteralPath $coreVersionFile -Raw
        if ($coreVersionRaw -match '(?m)^version:\s*"?([0-9][^"\s]*)"?') {
            $coreVersion = $Matches[1]
        }
    }
    Write-Host "Installed Core version : $coreVersion"

    # =========================================================================
    # Git availability
    # =========================================================================

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw "Git is not available in PATH."
    }

    # =========================================================================
    # Clone target Layer to temp dir
    # =========================================================================

    Remove-TempDir $TempCloneDir

    Write-Host "Acquiring target Layer from repository (sparse)..."

    # Phase 1: shallow clone without materializing any files.
    # --no-checkout avoids writing deeply-nested reference-app content (e.g.
    # SampleApp/node_modules/) that would exceed the Windows MAX_PATH limit.
    & git clone --depth 1 --no-checkout --branch $Ref -- $RepositoryUrl $TempCloneDir 2>&1 |
        ForEach-Object { Write-Host "  git: $_" }

    if ($LASTEXITCODE -ne 0) {
        throw "git clone failed with exit code $LASTEXITCODE."
    }

    # Scope core.longpaths to this acquisition repo only — never modifies global config.
    & git -C $TempCloneDir config core.longpaths true 2>&1 | Out-Null

    # Phase 2: read layer.json from the object store (no disk write) to determine
    # which paths are declared as installation artifacts.
    $preSparseManifestLines = & git -C $TempCloneDir show "HEAD:layer.json" 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "Target repository does not contain layer.json."
    }

    $preSparseManifest = $null
    try {
        $preSparseManifest = ($preSparseManifestLines -join "`n") | ConvertFrom-Json
    } catch {
        throw "Unable to parse target layer.json: $($_.Exception.Message)"
    }

    # Derive sparse-checkout patterns: layer.json + top-level declared artifact paths.
    [string[]]$sparsePatterns = @("layer.json")
    if ($null -ne $preSparseManifest.artifacts) {
        foreach ($artifactPath in $preSparseManifest.artifacts.PSObject.Properties.Value) {
            $topLevel = ([string]$artifactPath).TrimEnd('/\') -split '[/\\]' | Select-Object -First 1
            if (-not [string]::IsNullOrWhiteSpace($topLevel) -and $sparsePatterns -notcontains $topLevel) {
                $sparsePatterns += $topLevel
            }
        }
    }

    # Phase 3: materialize only declared artifact paths.
    # Falls back to a full checkout on git < 2.25 (sparse-checkout not available);
    # repo-scoped core.longpaths is still applied in the fallback path.
    & git -C $TempCloneDir sparse-checkout init --no-cone 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        $sparseArgs = @('-C', $TempCloneDir, 'sparse-checkout', 'set') + $sparsePatterns
        & git @sparseArgs 2>&1 | Out-Null
    }
    & git -C $TempCloneDir checkout 2>&1 | ForEach-Object { Write-Host "  git: $_" }

    if ($LASTEXITCODE -ne 0) {
        throw "git checkout failed with exit code $LASTEXITCODE."
    }

    # =========================================================================
    # Read and validate target layer.json
    # =========================================================================

    $targetManifestPath = Join-Path $TempCloneDir "layer.json"
    if (-not (Test-Path -LiteralPath $targetManifestPath -PathType Leaf)) {
        throw "Target repository does not contain layer.json."
    }

    try {
        $targetManifest = Get-Content -LiteralPath $targetManifestPath -Raw | ConvertFrom-Json
    } catch {
        throw "Unable to parse target layer.json: $($_.Exception.Message)"
    }

    $targetLayerId       = [string]$targetManifest.id
    $targetVersion       = [string]$targetManifest.version
    $targetSchemaVersion = [string]$targetManifest.schemaVersion
    $targetName          = [string]$targetManifest.name

    foreach ($field in @(@{n='id';v=$targetLayerId}, @{n='version';v=$targetVersion})) {
        if ([string]::IsNullOrWhiteSpace($field.v)) {
            throw "target layer.json is missing required field '$($field.n)'."
        }
    }

    # Resolve exact immutable commit SHA (CR-02: must not rely on mutable ref)
    Push-Location $TempCloneDir
    try {
        $targetCommit = (& git rev-parse HEAD 2>&1).Trim()
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($targetCommit)) {
            throw "Unable to resolve target Git commit SHA."
        }
    } finally {
        Pop-Location
    }

    Write-Host "Target Layer    : $targetName ($targetLayerId)"
    Write-Host "Target version  : $targetVersion"
    Write-Host "Target commit   : $targetCommit"
    Write-Host ""

    # =========================================================================
    # CR-01: Detect installed Layer state
    # =========================================================================

    $layerDir       = Join-Path $LayersDir $targetLayerId
    $provenancePath = Join-Path $layerDir "provenance.json"

    $layerDirExists   = Test-Path -LiteralPath $layerDir -PathType Container
    $provenanceExists = Test-Path -LiteralPath $provenancePath -PathType Leaf

    if (-not $layerDirExists) {
        Write-Host "  Result: LAYER_NOT_INSTALLED" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  Layer '$targetLayerId' is not installed in this project." -ForegroundColor White
        Write-Host "  To install: run mxagile-setup-mercedes.ps1 (or the appropriate setup script)." -ForegroundColor DarkGray
        exit 0
    }

    if (-not $provenanceExists) {
        Write-Host ""
        Write-Host "=======================================" -ForegroundColor Red
        Write-Host "BLOCKED: Untracked Installation" -ForegroundColor Red
        Write-Host "=======================================" -ForegroundColor Red
        Write-Host ""
        Write-Host "  Layer '$targetLayerId' directory exists but provenance.json is missing." -ForegroundColor White
        Write-Host ""
        Write-Host "  This indicates the layer was installed before provenance tracking" -ForegroundColor White
        Write-Host "  was introduced, or was installed manually without provenance." -ForegroundColor White
        Write-Host ""
        Write-Host "  This updater cannot safely determine the installed version or commit." -ForegroundColor White
        Write-Host "  Automatic update is BLOCKED to prevent unintended data loss." -ForegroundColor White
        Write-Host ""
        Write-Host "  Resolution options:" -ForegroundColor Cyan
        Write-Host "    1. Verify the installed content matches a known Layer version." -ForegroundColor White
        Write-Host "       Then write provenance.json manually to identify the installed state." -ForegroundColor White
        Write-Host "    2. Remove .mxagile\layers\$targetLayerId\ and run the setup script" -ForegroundColor White
        Write-Host "       to perform a clean installation with correct provenance." -ForegroundColor White
        Write-Host ""
        Write-Host "  Result: UNTRACKED_INSTALLATION" -ForegroundColor Red
        exit 3
    }

    # Read installed provenance
    try {
        $installedProvenance = Get-Content -LiteralPath $provenancePath -Raw | ConvertFrom-Json
    } catch {
        throw "Unable to parse installed provenance.json: $($_.Exception.Message)"
    }

    # Read installed version — support both current schema (installedVersion)
    # and legacy schema (no installedVersion field; fall back to installed layer.json)
    $installedVersion = Get-JsonProp $installedProvenance 'installedVersion'
    if ([string]::IsNullOrWhiteSpace($installedVersion)) {
        $installedLayerJsonPath = Join-Path $layerDir "layer.json"
        if (Test-Path -LiteralPath $installedLayerJsonPath -PathType Leaf) {
            try {
                $ilm = Get-Content -LiteralPath $installedLayerJsonPath -Raw | ConvertFrom-Json
                $installedVersion = [string]$ilm.version
            } catch { }
        }
    }
    if ([string]::IsNullOrWhiteSpace($installedVersion)) {
        $installedVersion = "0.0.0"
    }

    # Read installed commit — support both current and legacy provenance field names
    $installedCommit = Get-JsonProp $installedProvenance 'sourceCommit'
    if ([string]::IsNullOrWhiteSpace($installedCommit)) {
        $installedCommit = Get-JsonProp $installedProvenance 'resolved_revision'
    }

    Write-Host "Installed version : $installedVersion"
    Write-Host "Installed commit  : $(if ($installedCommit) { $installedCommit } else { '(unknown)' })"
    Write-Host ""

    # =========================================================================
    # CR-02: Version comparison
    # =========================================================================

    $versionCmp = Compare-SemVer $targetVersion $installedVersion

    if ($versionCmp -lt 0) {
        Write-Host "[INFO] Installed version ($installedVersion) is NEWER than target ($targetVersion)." -ForegroundColor Yellow
        Write-Host "       No update applied — downgrade requires explicit action." -ForegroundColor DarkGray
        Write-Host "       Result: NO_UPDATE_AVAILABLE"
        exit 0
    }

    if ($versionCmp -eq 0) {
        Write-Host "[OK] Layer is already at the latest version ($installedVersion)." -ForegroundColor Green
        Write-Host "     Result: NO_UPDATE_AVAILABLE"
        exit 0
    }

    Write-Host "[INFO] Update available: $installedVersion -> $targetVersion" -ForegroundColor Cyan
    Write-Host ""

    if ($CheckOnly) {
        Write-Host "  Check-only mode — no changes applied." -ForegroundColor DarkGray
        Write-Host "  Result: UPDATE_AVAILABLE"
        exit 0
    }

    # =========================================================================
    # CR-03: Compatibility gating — BEFORE any project mutation
    # =========================================================================

    $coreConstraint = $null
    if ($targetManifest.compatibility -and $targetManifest.compatibility.mxagileCore) {
        $coreConstraint = [string]$targetManifest.compatibility.mxagileCore
    }

    if (-not [string]::IsNullOrWhiteSpace($coreConstraint)) {
        $compatible = Test-CoreCompatibility $coreVersion $coreConstraint

        if (-not $compatible) {
            Write-Host ""
            Write-Host "=======================================" -ForegroundColor Red
            Write-Host "BLOCKED: Core version incompatible" -ForegroundColor Red
            Write-Host "=======================================" -ForegroundColor Red
            Write-Host ""
            Write-Host "  Installed MxAgile Core version : $coreVersion" -ForegroundColor White
            Write-Host "  Target Layer version           : $targetVersion ($targetLayerId)" -ForegroundColor White
            Write-Host "  Required Core compatibility    : $coreConstraint" -ForegroundColor White
            Write-Host ""
            Write-Host "  The target Layer version requires MxAgile Core $coreConstraint" -ForegroundColor Yellow
            Write-Host "  but the installed Core ($coreVersion) does not satisfy this." -ForegroundColor Yellow
            Write-Host ""
            Write-Host "  Recommended next action:" -ForegroundColor Cyan
            Write-Host "    1. Update MxAgile Core first (run mxagile-setup-mercedes.ps1)." -ForegroundColor White
            Write-Host "    2. Then re-run this Layer update." -ForegroundColor White
            Write-Host ""
            Write-Host "  No Layer artifacts have been modified." -ForegroundColor DarkGray
            Write-Host "  Result: BLOCKED_INCOMPATIBLE" -ForegroundColor Red
            exit 2
        }

        Write-Host "[OK] Compatibility check passed (Core $coreVersion satisfies $coreConstraint)." -ForegroundColor Green
    }

    # =========================================================================
    # CR-04: Schema version check — developer confirmation if changed
    # =========================================================================

    $installedSchemaVersion = Get-JsonProp $installedProvenance 'schemaVersion'
    $schemaVersionChanged   = (-not [string]::IsNullOrWhiteSpace($targetSchemaVersion)) -and
                              (-not [string]::IsNullOrWhiteSpace($installedSchemaVersion)) -and
                              ($targetSchemaVersion -ne $installedSchemaVersion)

    if ($schemaVersionChanged) {
        Write-Host ""
        Write-Host "=======================================" -ForegroundColor Yellow
        Write-Host "Notice: Schema version changed" -ForegroundColor Yellow
        Write-Host "=======================================" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  Installed schema version : $installedSchemaVersion" -ForegroundColor White
        Write-Host "  Target schema version    : $targetSchemaVersion" -ForegroundColor White
        Write-Host ""
        Write-Host "  A schema version change may indicate the format of Layer artifacts" -ForegroundColor White
        Write-Host "  has changed. The update replaces all Layer-owned content wholesale." -ForegroundColor White
        Write-Host ""

        if (-not $NonInteractive) {
            $confirm = Read-Host "  Continue with update? [y/N]"
            if ($confirm -notmatch '^[Yy]') {
                Write-Host "  Update cancelled." -ForegroundColor Yellow
                exit 0
            }
        } else {
            Write-Host "  NonInteractive mode — proceeding with schema version change." -ForegroundColor DarkGray
        }
    }

    # =========================================================================
    # CR-05 (pre-flight): Validate target artifact manifest paths BEFORE mutation
    # Rejects absolute paths and path-traversal components in the target manifest
    # BEFORE backup creation — no filesystem mutation has occurred if this throws.
    # =========================================================================

    Write-Host "Validating artifact manifest paths (pre-backup safety)..."
    Confirm-ArtifactManifestSafety -Artifacts $targetManifest.artifacts -LayerRoot $layerDir
    Write-Host "[OK] Artifact manifest paths are safe." -ForegroundColor Green

    # =========================================================================
    # CR-06: Backup — copy existing Layer dir before any mutation
    # =========================================================================

    $timestamp  = Get-Date -Format 'yyyyMMddHHmmss'
    $backupPath = "${BackupBase}_${targetLayerId}_${timestamp}"

    Write-Host "Creating backup..."
    Copy-Item -LiteralPath $layerDir -Destination $backupPath -Recurse -Force
    Write-Host "[OK] Backup created at: $backupPath" -ForegroundColor Green

    # =========================================================================
    # CR-05: Ownership-safe apply — replace Layer-owned artifacts only
    # =========================================================================

    Write-Host "Applying update (replacing Layer-owned artifacts)..."

    # Remove currently installed Layer-owned content (never provenance.json — written last)
    # Artifacts declared in the current installed layer.json (fall back to known set)
    $installedLayerJsonPath2 = Join-Path $layerDir "layer.json"
    $currentArtifacts        = $null
    if (Test-Path -LiteralPath $installedLayerJsonPath2 -PathType Leaf) {
        try {
            $ilm2 = Get-Content -LiteralPath $installedLayerJsonPath2 -Raw | ConvertFrom-Json
            $currentArtifacts = $ilm2.artifacts
        } catch { }
    }

    # Build removal list: layer.json + declared artifact paths (top-level names)
    $removeNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $removeNames.Add("layer.json") | Out-Null
    if ($null -ne $currentArtifacts) {
        foreach ($prop in $currentArtifacts.PSObject.Properties) {
            $topLevel = (([string]$prop.Value) -split '[/\\]', 2)[0].Trim()
            if (-not [string]::IsNullOrWhiteSpace($topLevel)) {
                $removeNames.Add($topLevel) | Out-Null
            }
        }
    } else {
        # Fallback: known artifact names per UPDATE-CONTRACT.md
        foreach ($n in @("glossary.yml", "platform-modules.yml", "modules")) {
            $removeNames.Add($n) | Out-Null
        }
    }

    foreach ($name in $removeNames) {
        $existing = Join-Path $layerDir $name
        Assert-LayerBoundary $existing $layerDir
        if (Test-Path -LiteralPath $existing) {
            Remove-Item -LiteralPath $existing -Recurse -Force
        }
    }

    # Copy new artifacts from target clone
    Copy-LayerArtifacts -SourceDir $TempCloneDir -DestDir $layerDir -Artifacts $targetManifest.artifacts

    Write-Host "[OK] Layer-owned artifacts replaced." -ForegroundColor Green

    # =========================================================================
    # CR-08: Update derived projections — state manifest
    # =========================================================================

    if (-not (Test-Path -LiteralPath $StateDir -PathType Container)) {
        New-Item -ItemType Directory -Path $StateDir -Force | Out-Null
    }

    $stateManifestPath = Join-Path $StateDir "manifest.$targetLayerId.md"
    $stateManifestContent = @"
# Layer: $targetName ($targetLayerId)

Source: $RepositoryUrl

Requested ref: $Ref

Resolved revision: $targetCommit

Installed version: $targetVersion

Previous version: $installedVersion
"@
    [System.IO.File]::WriteAllText($stateManifestPath, $stateManifestContent, [System.Text.Encoding]::UTF8)
    Write-Host "[OK] State manifest updated." -ForegroundColor Green

    # =========================================================================
    # CR-02/UPDATE-CONTRACT: Validate installed state
    # =========================================================================

    Write-Host "Validating installed state..."

    # layer.json must be valid JSON with required fields
    $validatedManifestPath = Join-Path $layerDir "layer.json"
    if (-not (Test-Path -LiteralPath $validatedManifestPath -PathType Leaf)) {
        throw "Validation failed: layer.json not found after update."
    }
    try {
        $validatedManifest = Get-Content -LiteralPath $validatedManifestPath -Raw | ConvertFrom-Json
    } catch {
        throw "Validation failed: layer.json is not valid JSON after update."
    }
    if ([string]::IsNullOrWhiteSpace([string]$validatedManifest.id) -or
        [string]::IsNullOrWhiteSpace([string]$validatedManifest.version)) {
        throw "Validation failed: layer.json is missing required 'id' or 'version' after update."
    }

    # glossary.yml — present and non-empty if declared
    $glossaryPath = Join-Path $layerDir "glossary.yml"
    if ($null -ne $targetManifest.artifacts -and $targetManifest.artifacts.PSObject.Properties['glossary']) {
        if (-not (Test-Path -LiteralPath $glossaryPath -PathType Leaf)) {
            throw "Validation failed: declared glossary '$($targetManifest.artifacts.glossary)' not found after update."
        }
        if ([string]::IsNullOrWhiteSpace((Get-Content -LiteralPath $glossaryPath -Raw))) {
            throw "Validation failed: glossary.yml is empty after update."
        }
    }

    # platform-modules.yml — present, non-empty, and detailFile refs resolve
    $platformModulesPath = Join-Path $layerDir "platform-modules.yml"
    if ($null -ne $targetManifest.artifacts -and $targetManifest.artifacts.PSObject.Properties['platformModules']) {
        if (-not (Test-Path -LiteralPath $platformModulesPath -PathType Leaf)) {
            throw "Validation failed: declared platformModules '$($targetManifest.artifacts.platformModules)' not found after update."
        }
        $pmContent = Get-Content -LiteralPath $platformModulesPath -Raw
        if ([string]::IsNullOrWhiteSpace($pmContent)) {
            throw "Validation failed: platform-modules.yml is empty after update."
        }
        # Verify detailFile references resolve
        [regex]::Matches($pmContent, '(?m)^\s*detailFile:\s*(.+)$') | ForEach-Object {
            $refPath = $_.Groups[1].Value.Trim().Trim('"', "'")
            $refFull = Join-Path $layerDir $refPath
            if (-not (Test-Path -LiteralPath $refFull -PathType Leaf)) {
                throw "Validation failed: platform-modules.yml references missing file: $refPath"
            }
        }
    }

    # No .git metadata should have been installed
    if (Test-Path -LiteralPath (Join-Path $layerDir ".git")) {
        throw "Validation failed: installed Layer contains .git metadata."
    }

    Write-Host "[OK] Validation passed." -ForegroundColor Green

    # =========================================================================
    # CR-07: Write provenance — only after successful validation
    # =========================================================================

    $newProvenance = [ordered]@{
        layerId          = $targetLayerId
        installedVersion = $targetVersion
        schemaVersion    = $targetSchemaVersion
        sourceRepository = $RepositoryUrl
        sourceRef        = $Ref
        sourceCommit     = $targetCommit
        installedAt      = (Get-Date -Format 'o')
        installedBy      = 'mxagile-core/update-layer'
        previousVersion  = $installedVersion
        previousCommit   = $(if ($installedCommit) { $installedCommit } else { $null })
    }

    $newProvenance | ConvertTo-Json | Set-Content -LiteralPath $provenancePath -Encoding utf8

    Write-Host "[OK] Provenance written." -ForegroundColor Green

    # =========================================================================
    # CR-06: Cleanup backup on success
    # =========================================================================

    Remove-TempDir $backupPath
    $backupPath = $null
    Write-Host "[OK] Backup removed." -ForegroundColor Green

    # =========================================================================
    # CR-09: Lifecycle impact report
    # =========================================================================

    Write-Host ""
    Write-Host "=======================================" -ForegroundColor Cyan
    Write-Host "Company Layer Update: SUCCESSFUL" -ForegroundColor Green
    Write-Host "=======================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Layer   : $targetName ($targetLayerId)" -ForegroundColor White
    Write-Host "  Version : $installedVersion -> $targetVersion" -ForegroundColor White
    Write-Host "  Commit  : $(if ($installedCommit) { $installedCommit } else { '(unknown)' }) -> $targetCommit" -ForegroundColor White
    Write-Host ""
    Write-Host "  Result: UPDATE_SUCCESSFUL" -ForegroundColor Green
    Write-Host ""
    Write-Host "--------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "Next step: Lifecycle Impact Assessment" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  The Layer update may have introduced new knowledge or constraints." -ForegroundColor White
    Write-Host "  Project artifacts (requirements/, specs/, planning/) were NOT modified." -ForegroundColor White
    Write-Host ""
    Write-Host "  Start a NEW agent session in this project and enter:" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "    Run the MxAgile system check and output the complete diagnostic report." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Possible outcomes: no impact | reconciliation required |" -ForegroundColor DarkGray
    Write-Host "  Discovery required | Refinement required | verification required" -ForegroundColor DarkGray
    Write-Host "--------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ""

    exit 0

} catch {
    Write-Host ""
    Write-Host "=======================================" -ForegroundColor Red
    Write-Host "Company Layer Update: FAILED" -ForegroundColor Red
    Write-Host "=======================================" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""

    # CR-06: Rollback — restore from backup if one exists
    if (-not [string]::IsNullOrWhiteSpace($backupPath) -and
        (Test-Path -LiteralPath $backupPath -PathType Container)) {
        Write-Host "  Rolling back from backup..." -ForegroundColor Yellow
        try {
            if (-not [string]::IsNullOrWhiteSpace($layerDir) -and
                (Test-Path -LiteralPath $layerDir -PathType Container)) {
                Remove-Item -LiteralPath $layerDir -Recurse -Force
            }
            Move-Item -LiteralPath $backupPath -Destination $layerDir -Force
            $backupPath = $null
            Write-Host "  [OK] Rollback successful — previous Layer state restored." -ForegroundColor Green
            Write-Host "       Provenance unchanged; installed version remains: $installedVersion" -ForegroundColor DarkGray
        } catch {
            Write-Host "  [FAILED] Rollback also failed: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "  Manual recovery required. Backup preserved at:" -ForegroundColor Red
            Write-Host "    $backupPath" -ForegroundColor White
        }
    } else {
        Write-Host "  No backup available (failure occurred before backup was created)." -ForegroundColor DarkGray
    }

    Write-Host ""
    Write-Host "  Result: UPDATE_FAILED" -ForegroundColor Red
    exit 1

} finally {
    Remove-TempDir $TempCloneDir
    # Backup is intentionally NOT cleaned up in finally —
    # success path already removes it; failure path preserves it for manual recovery.
}
