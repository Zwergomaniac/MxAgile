<#
.SYNOPSIS
    MxAgile setup with Company Layer — install or update independently.

.DESCRIPTION
    Independently detects the state of MxAgile Core and the Company Layer,
    then performs the correct operation for each:

        Core absent + Layer absent     -> INSTALL Core + INSTALL Layer
        Core existing + Layer existing -> UPDATE Core + UPDATE Layer
        Core existing + Layer absent   -> UPDATE Core + INSTALL Layer
        Core absent + Layer existing   -> INSTALL Core + (Layer already present)

    Neither component is assumed to share the same installed state as the other.
    The user does not need to decide which script to run or what to pass.

    Acquires the MxAgile distribution (from a local filesystem path or a Git URL),
    then invokes the canonical installer (scripts/install-core.ps1) from that
    distribution against the target Mendix project, including the Company Layer
    Company Layer.

    Path model:
        bootstrap    = this file ($PSScriptRoot, wherever it was placed)
        distribution = acquired from -DistributionSource, OR $PSScriptRoot when
                       already running from within the distribution (dev use)
        target       = -ProjectRoot (defaults to current working directory)

    These three paths are independent and must not be conflated.

.PARAMETER ProjectRoot
    Target Mendix project. Defaults to the current working directory.

.PARAMETER DistributionSource
    Path to the MxAgile distribution directory (local filesystem), or a Git URL
    to clone. When not provided, the script checks if it is already being run
    from within a MxAgile distribution (development use case only).

.PARAMETER DistributionRef
    Git branch / tag / commit ref to use when -DistributionSource is a Git URL.
    Defaults to "main".

.PARAMETER CompanyLayerGitUrl
    Git URL for the Company Layer repository. Required: pass it explicitly or set the
    MXAGILE_COMPANY_LAYER_URL environment variable. There is no built-in default.

.PARAMETER CompanyLayerRef
    Git branch / tag / commit ref for the Company Layer. Defaults to "main".

.PARAMETER NonInteractive
    Skip the pre-mutation confirmation prompt. Use in CI, scripted invocations,
    and automated regression tests.

.PARAMETER ResumeUpdate
    Resume an existing UPDATE_IN_PROGRESS or PARTIAL_UPDATE only when Core and
    Company Layer source/ref targets match the persisted transaction.

.PARAMETER Wait
    Pause for a keypress before exiting. Intended for interactive/direct-launch
    scenarios (e.g. right-click "Run with PowerShell") where the window would
    otherwise close before the developer can read the result.

    Direct-launch is also detected automatically (parent process = explorer.exe).
    Do NOT pass -Wait in automation, CI, or scripted invocations.

.EXAMPLE
    # Interactive/direct-launch use — keep window open after completion
    .\mxagile-setup-company-layer.ps1 -Wait
#>

[CmdletBinding()]
param (
    [string]$ProjectRoot = (Get-Location).Path,
    [string]$DistributionSource = "",
    [string]$DistributionRef = "main",
    [string]$CompanyLayerGitUrl = $env:MXAGILE_COMPANY_LAYER_URL,
    [string]$CompanyLayerRef = "main",
    [switch]$NonInteractive,
    [switch]$Wait,
    [switch]$ResumeUpdate
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# =========================================================================
# PowerShell Version Preflight (RF-005)
# MxAgile installation requires PowerShell 7+ (pwsh).
# =========================================================================
if ($PSVersionTable.PSVersion.Major -lt 7) {
    $installedVersion = $PSVersionTable.PSVersion.ToString()
    Write-Host ""
    Write-Host "ERROR: PowerShell 7 or later is required." -ForegroundColor Red
    Write-Host ""
    Write-Host "  Detected: Windows PowerShell $installedVersion"
    Write-Host "  Required: PowerShell 7+ (pwsh)"
    Write-Host ""
    Write-Host "Install PowerShell 7:"
    Write-Host "  winget install Microsoft.PowerShell"
    Write-Host "  https://aka.ms/powershell"
    Write-Host ""
    Write-Host "Then run this script with:"
    Write-Host "  pwsh -File mxagile-setup-company-layer.ps1"
    Write-Host ""
    exit 1
}

$CanonicalDistributionUrl    = "https://github.com/Zwergomaniac/MxAgile.git"
$CanonicalDistributionSubdir = ""   # framework files live at repository root

# ---------------------------------------------------------------------------
# Direct-launch detection (Windows only — explorer.exe parent process)
# ---------------------------------------------------------------------------
$isDirectLaunch = $false
$_isWindowsPlatform = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
    [System.Runtime.InteropServices.OSPlatform]::Windows)
if ($_isWindowsPlatform) {
    try {
        $parentName     = (Get-Process -Id $PID -ErrorAction Stop).Parent.ProcessName
        $isDirectLaunch = $parentName -in @('explorer', 'OpenWith')
    } catch { }
}
$shouldWait = $Wait -or $isDirectLaunch

$tempDistDir = $null
$exitCode    = 0
$updateTransactionPath = $null
$updateTransaction = $null
$coreMutationStarted = $false

function Save-UpdateTransaction {
    param([System.Collections.IDictionary]$Transaction)
    Save-MxAgileUpdateTransaction -Root $ProjectRoot -Transaction $Transaction
}

function Get-PostUpdateDoctor {
    param([string]$Root, [bool]$ApplySafe = $true)
    $doctor = [ordered]@{
        executed = $false; exit_code = $null; compatibility = 'NOT_VERIFIED'; reason = 'PYTHON_UNAVAILABLE'
        migration = [ordered]@{ status = 'NOT_VERIFIED' }
        repair_status = $null; blocking_diagnostic_count = $null; safe_deterministic_count = $null
        agent_repairable_count = $null; decision_required_count = $null; unsupported_count = $null; report = $null
    }
    $python = Get-Command python -ErrorAction SilentlyContinue
    if (-not $python) { $python = Get-Command python3 -ErrorAction SilentlyContinue }
    $doctorPath = Join-Path $Root '.mxagile/tools/project_compatibility.py'
    if (-not $python) { return $doctor }
    if (-not (Test-Path -LiteralPath $doctorPath -PathType Leaf)) { $doctor.reason = 'DOCTOR_SCRIPT_UNAVAILABLE'; return $doctor }
    try {
        $PSNativeCommandUseErrorActionPreference = $false
        $provenance = Get-Content -LiteralPath (Join-Path $Root '.mxagile/state/core-provenance.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $contractAware = $provenance.PSObject.Properties.Name -contains 'artifact_contract'
        $arguments = @('-B', $doctorPath, $(if ($contractAware) { 'migrate' } else { 'doctor' }), '--project-root', $Root, '--format', 'json')
        if ($contractAware -and $ApplySafe) { $arguments += '--apply-safe' }
        $output = & $python.Source @arguments 2>$null
        $doctor.exit_code = $LASTEXITCODE
        if ($doctor.exit_code -notin @(0, 1, 2)) { $doctor.reason = "DOCTOR_EXIT_$($doctor.exit_code)"; return $doctor }
        $report = ($output -join "`n") | ConvertFrom-Json -ErrorAction Stop
        if ($contractAware) {
            if ($report.stage -ne 'CONTRACT_MIGRATION_CHECKED') { throw 'Invalid migration contract' }
            $doctor.migration = $report.migration
            $report = $report.doctor
        }
        $doctor.executed = $true
        if ($report.stage -ne 'PROJECT_COMPATIBILITY_CHECKED' -or $report.read_only -ne $true -or
            $report.compatibility -notin @('COMPATIBLE', 'PARTIAL', 'BLOCKED')) {
            $doctor.reason = 'DOCTOR_OUTPUT_INVALID'
            return $doctor
        }
        $doctor.compatibility = $report.compatibility
        $doctor.reason = $null
        $doctor.repair_status = $report.repair_status
        $doctor.blocking_diagnostic_count = @($report.diagnostics | Where-Object { $_.blocking }).Count
        $doctor.safe_deterministic_count = @($report.diagnostics | Where-Object { $_.repairability -eq 'SAFE_DETERMINISTIC' }).Count
        $doctor.agent_repairable_count = @($report.diagnostics | Where-Object { $_.repairability -eq 'AGENT_REPAIRABLE' }).Count
        $doctor.decision_required_count = @($report.diagnostics | Where-Object { $_.repairability -eq 'DECISION_REQUIRED' }).Count
        $doctor.unsupported_count = @($report.diagnostics | Where-Object { $_.repairability -eq 'UNSUPPORTED' }).Count
        $doctor.report = $report
    } catch { $doctor.reason = 'DOCTOR_EXECUTION_FAILED' }
    return $doctor
}

function Save-UpdateHandoff {
    param([System.Collections.IDictionary]$Transaction, [System.Collections.IDictionary]$Doctor)
    $handoffPath = Join-Path $ProjectRoot '.mxagile/state/last-update-result.json'
    $handoff = if (Test-Path -LiteralPath $handoffPath -PathType Leaf) {
        Get-Content -LiteralPath $handoffPath -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable
    } else { [ordered]@{ schema_version = 1 } }
    $handoff.update_state = $Transaction.state
    $handoff.update_transaction = $Transaction
    $handoff.doctor = $Doctor
    $handoff.compatibility_status = $Doctor.compatibility
    $handoff.session_contract = [ordered]@{ state = 'RE_SYNC_REQUIRED'; policy = '.mxagile/policies/update-contract.md' }
    $tempPath = "$handoffPath.$([Guid]::NewGuid().ToString('N')).tmp"
    [System.IO.File]::WriteAllText($tempPath, (($handoff | ConvertTo-Json -Depth 40) + "`n"), [System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $tempPath -Destination $handoffPath -Force
}

try {
    # =========================================================================
    # 1. Validate target project path
    # =========================================================================
    if (-not (Test-Path -LiteralPath $ProjectRoot -PathType Container)) {
        throw "Target project root does not exist: $ProjectRoot"
    }
    $ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)

    # =========================================================================
    # 2. Independently detect Core state and Layer state
    # =========================================================================
    Write-Host ""
    Write-Host "=======================================" -ForegroundColor Cyan
    Write-Host "MxAgile Setup (Company Layer)" -ForegroundColor Cyan
    Write-Host "=======================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Target project  : $ProjectRoot"
    Write-Host ""
    Write-Host "Detecting project state..."

    # Core detection: canonical marker is .mxagile/lifecycle.yaml
    $coreMarker    = Join-Path $ProjectRoot ".mxagile\lifecycle.yaml"
    $coreInstalled = Test-Path -LiteralPath $coreMarker -PathType Leaf
    $coreState     = if ($coreInstalled) { "EXISTING_MXAGILE_PROJECT" } else { "FRESH_PROJECT" }
    $coreOperation = if ($coreInstalled) { "UPDATE" } else { "INSTALL" }

    # Layer detection: any subdirectory under .mxagile/layers/ indicates a layer is installed.
    # Also check for provenance.json to distinguish TRACKED vs UNTRACKED installations.
    $layersDir = Join-Path $ProjectRoot ".mxagile\layers"
    $layerInstalled  = $false
    $layerHasProvenance = $false
    $layerIds = @()
    if (Test-Path -LiteralPath $layersDir -PathType Container) {
        $layerDirs = @(Get-ChildItem -LiteralPath $layersDir -Directory -ErrorAction SilentlyContinue)
        if ($layerDirs.Count -gt 0) {
            $layerInstalled = $true
            $layerIds = $layerDirs | ForEach-Object { $_.Name }
            # Check provenance in each installed layer dir
            $layerHasProvenance = ($layerDirs | ForEach-Object {
                Test-Path -LiteralPath (Join-Path $_.FullName "provenance.json") -PathType Leaf
            } | Where-Object { $_ -eq $true } | Measure-Object).Count -gt 0
        }
    }
    $layerProvenanceNote = if ($layerInstalled) {
        if ($layerHasProvenance) { " [provenance: OK]" } else { " [provenance: MISSING - will report UNTRACKED]" }
    } else { "" }
    $layerState     = if ($layerInstalled) { "LAYER_INSTALLED ($($layerIds -join ', '))$layerProvenanceNote" } else { "LAYER_NOT_INSTALLED" }
    $layerOperation = if ($layerInstalled) { "UPDATE" } else { "INSTALL" }

    Write-Host ""
    Write-Host "  MxAgile Core       : $coreState -> $coreOperation" -ForegroundColor $(if ($coreInstalled) { "Yellow" } else { "Green" })
    Write-Host "  Company Layer     : $layerState -> $layerOperation" -ForegroundColor $(if ($layerInstalled) { "Yellow" } else { "Green" })
    Write-Host ""

    # =========================================================================
    # Interactive pre-mutation summary (before ANY changes are made)
    # =========================================================================
    $isInteractive = (-not $NonInteractive) -and ($shouldWait -or $isDirectLaunch)

    Write-Host "=======================================" -ForegroundColor Cyan
    Write-Host "This setup will:" -ForegroundColor White
    if ($coreInstalled -or $layerInstalled) {
        Write-Host "  - update MxAgile Core" -ForegroundColor White
    } else {
        Write-Host "  - install MxAgile Core" -ForegroundColor White
    }
    if ($layerInstalled) {
        Write-Host "  - update the Company Layer" -ForegroundColor White
    } else {
        Write-Host "  - install the Company Layer" -ForegroundColor White
    }
    Write-Host "  - update required MxAgile agent integrations" -ForegroundColor White
    Write-Host "  - preserve project-owned knowledge and lifecycle state" -ForegroundColor White
    Write-Host ""
    Write-Host "  The Mendix application itself will not intentionally be modified by setup." -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Protected (never overwritten by setup):" -ForegroundColor DarkGray
    Write-Host "    .mxagile/layers/                   Company Layer content" -ForegroundColor DarkGray
    Write-Host "    .mxagile/migration/                Migration history" -ForegroundColor DarkGray
    Write-Host "    planning/lifecycle/process-state.yaml  Durable project lifecycle state" -ForegroundColor DarkGray
    Write-Host "    requirements/ specs/ planning/     Project Requirements, Specs, Tasks" -ForegroundColor DarkGray
    Write-Host "    input-resources/                   Source mockups and input artifacts" -ForegroundColor DarkGray
    Write-Host "    .env.mendix                        Local secrets (never touched)" -ForegroundColor DarkGray
    Write-Host "    .mxagile/state/                    Framework-internal state" -ForegroundColor DarkGray
    Write-Host "=======================================" -ForegroundColor Cyan
    Write-Host ""

    if ($isInteractive) {
        Write-Host "Press any key to continue, or close this window to cancel." -ForegroundColor Yellow
        try { [void][System.Console]::ReadKey($true) } catch { }
        Write-Host ""
    }

    # =========================================================================
    # 3. Acquire MxAgile distribution
    # =========================================================================
    $distributionRoot = $null

    $provenanceCoreSource     = ""
    $provenanceCoreSourceType = ""
    $provenanceCoreRef        = $DistributionRef
    $provenanceCoreSubdir     = ""

    if ([string]::IsNullOrWhiteSpace($DistributionSource)) {
        $devInstaller = Join-Path (Join-Path $PSScriptRoot "scripts") "install-core.ps1"
        if (Test-Path -LiteralPath $devInstaller -PathType Leaf) {
            Write-Host "Distribution    : $PSScriptRoot (running from within distribution)"
            $distributionRoot         = $PSScriptRoot
            $provenanceCoreSource     = $PSScriptRoot
            $provenanceCoreSourceType = "local"
            $provenanceCoreRef        = ""
            $provenanceCoreSubdir     = ""
        } else {
            $tempDistDir = Join-Path ([System.IO.Path]::GetTempPath()) "mxagile-setup-$([System.Guid]::NewGuid().ToString('N').Substring(0,8))"
            Write-Host "Distribution    : $CanonicalDistributionUrl (canonical, ref: $DistributionRef)"
            Write-Host "  -> Cloning to : $tempDistDir (temporary)"

            $gitCmd = Get-Command git -ErrorAction SilentlyContinue
            if (-not $gitCmd) {
                throw "git is not available on PATH. It is required to acquire the MxAgile distribution."
            }

            git clone --depth 1 --branch $DistributionRef $CanonicalDistributionUrl $tempDistDir
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to acquire MxAgile distribution from canonical source: $CanonicalDistributionUrl"
            }

            $subDirPath = Join-Path $tempDistDir $CanonicalDistributionSubdir
            $distributionRoot = if (Test-Path -LiteralPath (Join-Path (Join-Path $subDirPath "scripts") "install-core.ps1") -PathType Leaf) {
                $subDirPath
            } else {
                $tempDistDir
            }
            Write-Host "  -> Acquired: $distributionRoot"

            $provenanceCoreSource     = $CanonicalDistributionUrl
            $provenanceCoreSourceType = "git"
            $provenanceCoreRef        = $DistributionRef
            if ($null -ne $tempDistDir -and $distributionRoot -ne $tempDistDir) {
                $provenanceCoreSubdir = $distributionRoot.Substring($tempDistDir.Length).TrimStart('\', '/')
            }
        }
    } elseif (Test-Path -LiteralPath $DistributionSource -PathType Container) {
        $distributionRoot             = [System.IO.Path]::GetFullPath($DistributionSource)
        Write-Host "Distribution    : $distributionRoot (local path)"
        $provenanceCoreSource         = $distributionRoot
        $provenanceCoreSourceType     = "local"
        $provenanceCoreRef            = ""
        $provenanceCoreSubdir         = ""
    } else {
        $tempDistDir = Join-Path ([System.IO.Path]::GetTempPath()) "mxagile-setup-$([System.Guid]::NewGuid().ToString('N').Substring(0,8))"
        Write-Host "Distribution    : $DistributionSource"
        Write-Host "  -> Cloning to : $tempDistDir (temporary)"

        $gitCmd = Get-Command git -ErrorAction SilentlyContinue
        if (-not $gitCmd) {
            throw "git is not available on PATH. It is required to clone the MxAgile distribution."
        }

        git clone --depth 1 --branch $DistributionRef $DistributionSource $tempDistDir
        if ($LASTEXITCODE -ne 0) {
            throw "git clone failed with exit code $LASTEXITCODE. Check the URL and network access."
        }
        $distributionRoot             = $tempDistDir
        Write-Host "  -> Cloned successfully."
        $provenanceCoreSource         = $DistributionSource
        $provenanceCoreSourceType     = "git"
        $provenanceCoreRef            = $DistributionRef
        $provenanceCoreSubdir         = ""
    }

    # =========================================================================
    # Resolve exact Core commit SHA from distribution (best-effort)
    # Commit hash is the primary currency signal — version string alone is not sufficient.
    # =========================================================================
    $provenanceCoreCommit = ""
    try {
        $resolvedSha = (& git -C $distributionRoot rev-parse HEAD 2>&1 |
            Select-Object -First 1).ToString().Trim()
        if ($resolvedSha -match '^[a-f0-9]{40}$') {
            $provenanceCoreCommit = $resolvedSha
            Write-Host "  -> Core commit   : $provenanceCoreCommit"
        }
    } catch { }

    # =========================================================================
    # 4. Safety: distribution must not be inside the target project
    # =========================================================================
    $targetNorm = $ProjectRoot.TrimEnd('\', '/')
    $distNorm   = $distributionRoot.TrimEnd('\', '/')
    if ($distNorm -eq $targetNorm -or
        $distNorm.StartsWith($targetNorm + '\') -or
        $distNorm.StartsWith($targetNorm + '/')) {
        throw "Distribution root ($distributionRoot) must not be inside the target project ($ProjectRoot)."
    }

    # =========================================================================
    # 5. Verify canonical installer exists in distribution
    # =========================================================================
    $canonicalInstaller = Join-Path (Join-Path $distributionRoot "scripts") "install-core.ps1"
    if (-not (Test-Path -LiteralPath $canonicalInstaller -PathType Leaf)) {
        throw "Canonical installer not found in MxAgile distribution: $canonicalInstaller"
    }
    Write-Host "Canonical installer: $canonicalInstaller"
    Write-Host ""

    # =========================================================================
    # 6. Invoke canonical Core installer (without Company Layer when already installed)
    #
    # Company Layer install vs update are independent operations:
    #   Layer NOT installed → pass -CompanyLayerSource to install-core.ps1 (initial install)
    #   Layer INSTALLED     → call update-layer.ps1 separately (CR-10: independent update domains)
    # =========================================================================

    # Company Layer source is explicit: no implicit/default source (fail before any mutation).
    if ([string]::IsNullOrWhiteSpace($CompanyLayerGitUrl)) {
        throw "No Company Layer source configured. Pass -CompanyLayerGitUrl <git-url> or set MXAGILE_COMPANY_LAYER_URL."
    }

    . (Join-Path $distributionRoot 'scripts/update-transaction.ps1')
    if ($ResumeUpdate -and $tempDistDir -and $coreInstalled) {
        $installedIdentity=Get-Content -LiteralPath (Join-Path $ProjectRoot '.mxagile/state/core-provenance.json') -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable
        $pinnedCommit=[string]$installedIdentity['commit']
        if ($pinnedCommit -notmatch '^[a-f0-9]{40}$') { throw 'Installed Core commit is not observable for source verification.' }
        & git -C $distributionRoot cat-file -e "$pinnedCommit`^{commit}" 2>$null
        if ($LASTEXITCODE -ne 0) {
            & git -C $distributionRoot fetch --depth 1 origin $pinnedCommit 2>&1 | Out-Host
            if ($LASTEXITCODE -ne 0) { throw 'Pinned Core source objects could not be acquired; no consumer mutation performed.' }
        }
    }
    $resumeAppliedCore=$false
    if ($coreInstalled) {
        $updateTransactionPath = Join-Path $ProjectRoot '.mxagile/state/update-transaction.json'
        $existingTransaction = $null
        if (Test-Path -LiteralPath $updateTransactionPath -PathType Leaf) {
            try { $existingTransaction = Get-Content -LiteralPath $updateTransactionPath -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable }
            catch { throw "Existing update-transaction.json is invalid; recovery is blocked before mutation: $($_.Exception.Message)" }
        }
        $pendingStates = @('UPDATE_IN_PROGRESS', 'PARTIAL_UPDATE')
        if ($existingTransaction -and $existingTransaction.state -in $pendingStates) {
            if (-not $ResumeUpdate) {
                throw "A prior update is $($existingTransaction.state). Inspect .mxagile/state/update-transaction.json and rerun the same target with -ResumeUpdate after recovery review."
            }
            $resumeCoreCommit = if ($provenanceCoreCommit) { $provenanceCoreCommit } else { 'UNKNOWN' }
            $installedCoreForResume=Get-Content -LiteralPath (Join-Path $ProjectRoot '.mxagile/state/core-provenance.json') -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable
            $resumeAppliedCore=$installedCoreForResume.commit -eq $existingTransaction.target_core.commit
            if ((-not $resumeAppliedCore -and $existingTransaction.target_core.commit -ne $resumeCoreCommit) -or
                $existingTransaction.target_company_layer.repository -ne $CompanyLayerGitUrl -or
                $existingTransaction.target_company_layer.ref -ne $CompanyLayerRef) {
                throw "Resume target differs from the persisted update transaction; no mutation performed."
            }
            $updateTransaction = $existingTransaction
            $updateTransaction.state = 'UPDATE_IN_PROGRESS'
            $updateTransaction.current_stage = 'RESUME_PRECHECK'
            $updateTransaction.failed_stage = $null
            $updateTransaction.failure = $null
            $updateTransaction.resumed_at = (Get-Date).ToUniversalTime().ToString('o')
            if (-not $resumeAppliedCore) { $updateTransaction.resume_count = [int]$updateTransaction.resume_count + 1 }
        } elseif ($ResumeUpdate) {
            & $canonicalInstaller -ProjectRoot $ProjectRoot -IsUpdate $true -ResumeUpdate
            if ($LASTEXITCODE -ne 0) { throw 'Installed-Core projection resume failed; no Company Layer update was inferred.' }
            exit 0
        } else {
            $previousCore = $null
            $coreProvenancePath = Join-Path $ProjectRoot '.mxagile/state/core-provenance.json'
            if (Test-Path -LiteralPath $coreProvenancePath -PathType Leaf) {
                try { $previousCore = Get-Content -LiteralPath $coreProvenancePath -Raw -Encoding UTF8 | ConvertFrom-Json }
                catch { throw "Installed Core provenance is invalid; update is blocked: $($_.Exception.Message)" }
            }
            $targetCoreVersion = 'UNKNOWN'
            $versionPath = Join-Path $distributionRoot '.mxagile/version.yaml'
            if (Test-Path -LiteralPath $versionPath -PathType Leaf) {
                $versionText = Get-Content -LiteralPath $versionPath -Raw -Encoding UTF8
                if ($versionText -match '(?m)^version:\s+"?([^"\s]+)') { $targetCoreVersion = $Matches[1] }
            }
            $previousLayers = @()
            foreach ($layerId in $layerIds) {
                $layerProvenancePath = Join-Path (Join-Path $layersDir $layerId) 'provenance.json'
                if (Test-Path -LiteralPath $layerProvenancePath -PathType Leaf) {
                    try {
                        $layerProvenance = Get-Content -LiteralPath $layerProvenancePath -Raw -Encoding UTF8 | ConvertFrom-Json
                        $previousLayers += [ordered]@{
                            id = [string]$layerId
                            version = [string]$layerProvenance.installedVersion
                            commit = [string]$layerProvenance.sourceCommit
                        }
                    } catch { $previousLayers += [ordered]@{ id = [string]$layerId; version = 'UNKNOWN'; commit = 'UNKNOWN' } }
                } else { $previousLayers += [ordered]@{ id = [string]$layerId; version = 'UNKNOWN'; commit = 'UNKNOWN' } }
            }
            $updateTransaction = [ordered]@{
                schema_version = 1
                update_attempt_id = "UPDATE-$([Guid]::NewGuid().ToString('N'))"
                state = 'UPDATE_IN_PROGRESS'
                started_at = (Get-Date).ToUniversalTime().ToString('o')
                updated_at = (Get-Date).ToUniversalTime().ToString('o')
                current_stage = 'PRECHECK_COMPLETE'
                previous_core = [ordered]@{
                    version = if ($previousCore) { $previousCore.version } else { 'UNKNOWN' }
                    commit = if ($previousCore) { $previousCore.commit } else { 'UNKNOWN' }
                    installed_at = if ($previousCore) { $previousCore.installed_at } else { $null }
                }
                target_core = [ordered]@{
                    source = $provenanceCoreSource
                    source_type = $provenanceCoreSourceType
                    ref = $provenanceCoreRef
                    version = $targetCoreVersion
                    commit = if ($provenanceCoreCommit) { $provenanceCoreCommit } else { 'UNKNOWN' }
                }
                previous_company_layers = @($previousLayers)
                target_company_layer = [ordered]@{ repository = $CompanyLayerGitUrl; ref = $CompanyLayerRef; id = $null; version = 'NOT_RESOLVED'; commit = 'NOT_RESOLVED' }
                completed_stages = @()
                failed_stage = $null
                failure = $null
                affected_generated_artifacts = @('.mxagile/', 'CLAUDE.md', 'AGENTS.md', 'AGENT.md', '.github/', '.agents/', '.claude/', '.opencode/', '.grok/', '.hermes/')
                migrations_performed = @()
                rollback = [ordered]@{ available = $false; core = $false; company_layer = $false; backup_path = $null; performed = $false }
                compatibility_status = 'NOT_VERIFIED'
                context_state = 'STALE'
                restart_required = $false
                resync_required = $true
                resume_available = $true
                resume_count = 0
            }
        }
        Save-UpdateTransaction -Transaction $updateTransaction
        $coreMutationStarted = $false
    }

    # Step 6a: Core installation / update
    if ($resumeAppliedCore) {
        $coreMutationStarted=$true
        & $canonicalInstaller -ProjectRoot $ProjectRoot -IsUpdate $true -ResumeUpdate -DeferPostUpdateCompatibility
        if ($LASTEXITCODE -ne 0) { throw 'Installed-Core projection resume failed.' }
    }
    if (-not $layerInstalled -and -not $resumeAppliedCore) {
        # First-time setup: install Core AND Layer together
        $coreMutationStarted = $true
        & $canonicalInstaller `
            -ProjectRoot              $ProjectRoot `
            -CompanyLayerSource       $CompanyLayerGitUrl `
            -CompanyLayerSourceType   Git `
            -CompanyLayerRef          $CompanyLayerRef `
            -IsUpdate                 $coreInstalled `
            -ProvenanceFlavor         "company-layer" `
            -ProvenanceCoreSource     $provenanceCoreSource `
            -ProvenanceCoreSourceType $provenanceCoreSourceType `
            -ProvenanceCoreRef        $provenanceCoreRef `
            -ProvenanceCoreSubdir     $provenanceCoreSubdir `
            -ProvenanceCoreCommit     $provenanceCoreCommit `
            -DeferPostUpdateCompatibility:([bool]($null -ne $updateTransaction))
        $exitCode = $LASTEXITCODE
        if ($exitCode -ne 0) { throw "MxAgile Core/Layer installation failed with exit code $exitCode." }
    } else {
        # Layer already installed: update Core only (no -CompanyLayerSource)
        $coreMutationStarted = $true
        if (-not $resumeAppliedCore) {
        & $canonicalInstaller `
            -ProjectRoot              $ProjectRoot `
            -IsUpdate                 $coreInstalled `
            -ProvenanceFlavor         "company-layer" `
            -ProvenanceCoreSource     $provenanceCoreSource `
            -ProvenanceCoreSourceType $provenanceCoreSourceType `
            -ProvenanceCoreRef        $provenanceCoreRef `
            -ProvenanceCoreSubdir     $provenanceCoreSubdir `
            -ProvenanceCoreCommit     $provenanceCoreCommit `
            -DeferPostUpdateCompatibility
        $exitCode = $LASTEXITCODE

        if ($exitCode -ne 0) {
            throw "MxAgile Core update failed with exit code $exitCode."
        }
        }

        if ($null -ne $updateTransaction) {
            $updateTransaction=Get-Content -LiteralPath $updateTransactionPath -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable
            if ($updateTransaction.completed_stages -notcontains 'CORE_UPDATE') {
                $updateTransaction.completed_stages = @($updateTransaction.completed_stages + 'CORE_UPDATE')
            }
            $updateTransaction.current_stage = 'COMPANY_LAYER_UPDATE'
            $coreProvenancePath = Join-Path $ProjectRoot '.mxagile/state/core-provenance.json'
            if (Test-Path -LiteralPath $coreProvenancePath -PathType Leaf) {
                $installedCore = Get-Content -LiteralPath $coreProvenancePath -Raw -Encoding UTF8 | ConvertFrom-Json
                $updateTransaction.target_core.version = $installedCore.version
                $updateTransaction.target_core.commit = $installedCore.commit
            }
            Save-UpdateTransaction -Transaction $updateTransaction
        }

        if (-not $layerInstalled) {
            & (Join-Path $distributionRoot 'scripts/fetch-layer.ps1') -RepositoryUrl $CompanyLayerGitUrl -Ref $CompanyLayerRef -ProjectRoot $ProjectRoot
            if ($LASTEXITCODE -ne 0) { throw 'Pending first Company Layer installation failed.' }
            $layerIds=@(Get-ChildItem -LiteralPath $layersDir -Directory | Select-Object -ExpandProperty Name)
        }
        # Step 6b: Independent Company Layer update
        $updateLayerScript = Join-Path (Join-Path $distributionRoot "scripts") "update-layer.ps1"
        if (-not (Test-Path -LiteralPath $updateLayerScript -PathType Leaf)) {
            throw "update-layer.ps1 not found in MxAgile distribution: $updateLayerScript"
        }

        Write-Host ""
        Write-Host "---"
        Write-Host "Company Layer Update (independent)" -ForegroundColor Cyan
        Write-Host "---"
        Write-Host ""

        $updateLayerParams = @{
            RepositoryUrl = $CompanyLayerGitUrl
            Ref           = $CompanyLayerRef
            ProjectRoot   = $ProjectRoot
            ExpectedInstalledLayerIds = @($layerIds)
            TransactionPath = $updateTransactionPath
        }
        if ($NonInteractive) { $updateLayerParams.NonInteractive = $true }
        if ($ResumeUpdate) { $updateLayerParams.ResumeUpdate = $true }

        & $updateLayerScript @updateLayerParams
        $layerExitCode = $LASTEXITCODE

        # Exit codes from update-layer.ps1:
        #   0 = SUCCESS / NO_UPDATE_AVAILABLE / NOT_INSTALLED
        #   1 = UPDATE_FAILED
        #   2 = BLOCKED_INCOMPATIBLE
        #   3 = UNTRACKED_INSTALLATION
        if ($layerExitCode -ne 0) {
            throw "Company Layer update failed (exit code $layerExitCode)."
        }
        $exitCode = 0
    }

    if ($null -ne $updateTransaction) {
        if (Test-Path -LiteralPath $updateTransactionPath -PathType Leaf) {
            $updateTransaction = Get-Content -LiteralPath $updateTransactionPath -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable
        }
        if ($updateTransaction.completed_stages -notcontains 'CORE_UPDATE') {
            $updateTransaction.completed_stages = @($updateTransaction.completed_stages + 'CORE_UPDATE')
        }
        if ($updateTransaction.completed_stages -notcontains 'COMPANY_LAYER_UPDATE') {
            $updateTransaction.completed_stages = @($updateTransaction.completed_stages + 'COMPANY_LAYER_UPDATE')
        }
        $updateTransaction.current_stage = 'POST_UPDATE_DOCTOR'
        $updateTransaction.state = 'UPDATE_IN_PROGRESS'
        Save-UpdateTransaction -Transaction $updateTransaction

        $doctor = Get-PostUpdateDoctor -Root $ProjectRoot
        $updateTransaction.doctor_status = $doctor.compatibility
        $updateTransaction.compatibility_status = $doctor.compatibility
        if ($doctor.migration.status -ne 'NOT_VERIFIED') { $updateTransaction.completed_stages = @($updateTransaction.completed_stages + 'CONTRACT_MIGRATION') }
        if ($doctor.executed) { $updateTransaction.completed_stages = @($updateTransaction.completed_stages + 'DOCTOR' | Select-Object -Unique) }
        if ($updateTransaction.Contains('projection')) { $updateTransaction.projection.contract_migration_started=$true; $updateTransaction.projection.doctor_executed=[bool]$doctor.executed }
        $updateTransaction.current_stage = 'CONTEXT_RESYNC'
        $updateTransaction.state = 'UPDATE_INSTALLED_RESTART_REQUIRED'
        $updateTransaction.context_state = 'STALE'
        $updateTransaction.resync_required = $true
        $updateTransaction.restart_required = $false
        $updateTransaction.resume_available = $false
        Save-UpdateTransaction -Transaction $updateTransaction
        Save-UpdateHandoff -Transaction $updateTransaction -Doctor $doctor
        Remove-Item -LiteralPath $updateTransactionPath -Force -ErrorAction SilentlyContinue
    }

} catch {
    Write-Host ""
    Write-Host "Setup failed!" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    if ($null -ne $updateTransaction -and -not [string]::IsNullOrWhiteSpace($updateTransactionPath)) {
        if (Test-Path -LiteralPath $updateTransactionPath -PathType Leaf) {
            try { $updateTransaction = Get-Content -LiteralPath $updateTransactionPath -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable } catch { }
        }
        $blockedBeforeMutation = $updateTransaction.state -eq 'BLOCKED_BEFORE_MUTATION'
        $updateTransaction.failure = $_.Exception.Message
        $updateTransaction.failed_stage = if ($updateTransaction.current_stage) { $updateTransaction.current_stage } else { 'UNKNOWN' }
        $updateTransaction.state = if ($blockedBeforeMutation) { 'BLOCKED_BEFORE_MUTATION' } elseif ($coreMutationStarted) { 'PARTIAL_UPDATE' } else { 'BLOCKED_BEFORE_MUTATION' }
        $updateTransaction.context_state = if ($updateTransaction.state -eq 'PARTIAL_UPDATE') { 'STALE' } else { 'UNCHANGED' }
        $updateTransaction.compatibility_status = 'NOT_VERIFIED'
        $updateTransaction.resync_required = $updateTransaction.state -eq 'PARTIAL_UPDATE'
        $updateTransaction.resume_available = $updateTransaction.state -eq 'PARTIAL_UPDATE'
        $projectionIncomplete=$updateTransaction.Contains('projection') -and $updateTransaction.projection.status -ne 'COMPLETE'
        $doctor = [ordered]@{
            executed = $false; exit_code = $null; compatibility = 'NOT_VERIFIED'
            reason = if ($projectionIncomplete) { 'PROJECTIONS_INCOMPLETE' } elseif ($blockedBeforeMutation) { 'BLOCKED_BEFORE_MUTATION' } else { 'UPDATE_INCOMPLETE' }
            repair_status = $null; blocking_diagnostic_count = $null; safe_deterministic_count = $null
            agent_repairable_count = $null; decision_required_count = $null; unsupported_count = $null; report = $null
        }
        $updateTransaction.compatibility_status = $doctor.compatibility
        try {
            Save-UpdateTransaction -Transaction $updateTransaction
            Save-UpdateHandoff -Transaction $updateTransaction -Doctor $doctor
            if ($updateTransaction.state -eq 'BLOCKED_BEFORE_MUTATION') {
                Remove-Item -LiteralPath $updateTransactionPath -Force -ErrorAction SilentlyContinue
            }
        } catch { Write-Host "Update recovery state could not be persisted: $($_.Exception.Message)" -ForegroundColor Red }
    }
    $exitCode = 1
} finally {
    if ($null -ne $tempDistDir -and (Test-Path -LiteralPath $tempDistDir -PathType Container)) {
        Write-Host ""
        Write-Host "Cleaning up temporary distribution at: $tempDistDir"
        Remove-Item -LiteralPath $tempDistDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ($shouldWait) {
    Write-Host ""
    Write-Host "Press any key to continue..." -ForegroundColor DarkGray
    try { [void][System.Console]::ReadKey($true) } catch { }
}

exit $exitCode
