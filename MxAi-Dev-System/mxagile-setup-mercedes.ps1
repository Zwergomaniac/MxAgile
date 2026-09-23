<#
.SYNOPSIS
    MxAgile setup with Mercedes-Benz Company Layer — install or update independently.

.DESCRIPTION
    Independently detects the state of MxAgile Core and the Mercedes Company Layer,
    then performs the correct operation for each:

        Core absent + Layer absent     -> INSTALL Core + INSTALL Layer
        Core existing + Layer existing -> UPDATE Core + UPDATE Layer
        Core existing + Layer absent   -> UPDATE Core + INSTALL Layer
        Core absent + Layer existing   -> INSTALL Core + (Layer already present)

    Neither component is assumed to share the same installed state as the other.
    The user does not need to decide which script to run or what to pass.

    Acquires the MxAgile distribution (from a local filesystem path or a Git URL),
    then invokes the canonical installer (scripts/install-core.ps1) from that
    distribution against the target Mendix project, including the Mercedes-Benz
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

.PARAMETER MercedesGitUrl
    Git URL for the Mercedes-Benz Company Layer repository.

.PARAMETER MercedesRef
    Git branch / tag / commit ref for the Company Layer. Defaults to "main".

.PARAMETER NonInteractive
    Skip the pre-mutation confirmation prompt. Use in CI, scripted invocations,
    and automated regression tests.

.PARAMETER Wait
    Pause for a keypress before exiting. Intended for interactive/direct-launch
    scenarios (e.g. right-click "Run with PowerShell") where the window would
    otherwise close before the developer can read the result.

    Direct-launch is also detected automatically (parent process = explorer.exe).
    Do NOT pass -Wait in automation, CI, or scripted invocations.

.EXAMPLE
    # Interactive/direct-launch use — keep window open after completion
    .\mxagile-setup-mercedes.ps1 -Wait
#>

[CmdletBinding()]
param (
    [string]$ProjectRoot = (Get-Location).Path,
    [string]$DistributionSource = "",
    [string]$DistributionRef = "main",
    [string]$MercedesGitUrl = "https://mercedes-benz.ghe.com/DFC-Applikationsentwicklung/MxAgile-CompanyLayer.git",
    [string]$MercedesRef = "main",
    [switch]$NonInteractive,
    [switch]$Wait
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$CanonicalDistributionUrl    = "https://github.com/Zwergomaniac/MxAgile.git"
$CanonicalDistributionSubdir = "MxAi-Dev-System"

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
    Write-Host "MxAgile Setup (Mercedes)" -ForegroundColor Cyan
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

    # Layer detection: any subdirectory under .mxagile/layers/ indicates a layer is installed
    $layersDir = Join-Path $ProjectRoot ".mxagile\layers"
    $layerInstalled = $false
    $layerIds = @()
    if (Test-Path -LiteralPath $layersDir -PathType Container) {
        $layerDirs = @(Get-ChildItem -LiteralPath $layersDir -Directory -ErrorAction SilentlyContinue)
        if ($layerDirs.Count -gt 0) {
            $layerInstalled = $true
            $layerIds = $layerDirs | ForEach-Object { $_.Name }
        }
    }
    $layerState     = if ($layerInstalled) { "MERCEDES_LAYER_INSTALLED ($($layerIds -join ', '))" } else { "LAYER_NOT_INSTALLED" }
    $layerOperation = if ($layerInstalled) { "UPDATE" } else { "INSTALL" }

    Write-Host ""
    Write-Host "  MxAgile Core       : $coreState -> $coreOperation" -ForegroundColor $(if ($coreInstalled) { "Yellow" } else { "Green" })
    Write-Host "  Mercedes Layer     : $layerState -> $layerOperation" -ForegroundColor $(if ($layerInstalled) { "Yellow" } else { "Green" })
    Write-Host ""

    # =========================================================================
    # Interactive pre-mutation summary (before ANY changes are made)
    # =========================================================================
    $isInteractive = (-not $NonInteractive) -and ($shouldWait -or $isDirectLaunch)

    Write-Host "=======================================" -ForegroundColor Cyan
    Write-Host "This setup will:" -ForegroundColor White
    if ($coreInstalled) {
        Write-Host "  - update MxAgile Core" -ForegroundColor White
    } else {
        Write-Host "  - install MxAgile Core" -ForegroundColor White
    }
    if ($layerInstalled) {
        Write-Host "  - update the Mercedes-Benz Company Layer" -ForegroundColor White
    } else {
        Write-Host "  - install the Mercedes-Benz Company Layer" -ForegroundColor White
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
    # 6. Invoke canonical installer against the target project
    # =========================================================================
    & $canonicalInstaller `
        -ProjectRoot              $ProjectRoot `
        -CompanyLayerSource       $MercedesGitUrl `
        -CompanyLayerSourceType   Git `
        -CompanyLayerRef          $MercedesRef `
        -IsUpdate                 $coreInstalled `
        -ProvenanceFlavor         "mercedes" `
        -ProvenanceCoreSource     $provenanceCoreSource `
        -ProvenanceCoreSourceType $provenanceCoreSourceType `
        -ProvenanceCoreRef        $provenanceCoreRef `
        -ProvenanceCoreSubdir     $provenanceCoreSubdir
    $exitCode = $LASTEXITCODE

} catch {
    Write-Host ""
    Write-Host "Setup failed!" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
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
