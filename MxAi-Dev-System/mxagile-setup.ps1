<#
.SYNOPSIS
    MxAgile setup — install or update MxAgile in a Mendix project.

.DESCRIPTION
    Detects the current project state and performs the correct operation:

        FRESH PROJECT
            -> INSTALL: bootstrap MxAgile from scratch

        EXISTING MXAGILE PROJECT
            -> UPDATE: synchronize Core, retire stale framework-owned artifacts,
               regenerate projections, reconcile state

    The user does not need to decide whether to run an install or update script.
    This entry point detects project state and selects the correct operation.

    Acquires the MxAgile distribution (from a local filesystem path or a Git URL),
    then invokes the canonical installer (scripts/install-core.ps1) from that
    distribution against the target Mendix project.

    This script may be placed anywhere — it does NOT need to live inside the
    MxAgile distribution directory.

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

.PARAMETER NonInteractive
    Skip the pre-mutation confirmation prompt. Use in CI, scripted invocations,
    and automated regression tests. Interactive direct-launch mode shows a summary
    and waits for keypress before making any changes.

.PARAMETER Wait
    Pause for a keypress before exiting. Intended for interactive/direct-launch
    scenarios (e.g. right-click "Run with PowerShell") where the window would
    otherwise close before the developer can read the result.

    Direct-launch is also detected automatically (parent process = explorer.exe).
    Do NOT pass -Wait in automation, CI, or scripted invocations.

.EXAMPLE
    # Standalone use — acquire distribution from GitHub
    .\mxagile-setup.ps1 -DistributionSource "https://github.com/your-org/mxagile.git"

.EXAMPLE
    # Standalone use — acquire distribution from a local directory
    .\mxagile-setup.ps1 -DistributionSource "C:\tools\MxAi-Dev-System"

.EXAMPLE
    # Development use — run from within the MxAgile distribution tree
    .\mxagile-setup.ps1 -ProjectRoot "C:\projects\MyApp"

.EXAMPLE
    # Interactive/direct-launch use — keep window open after completion
    .\mxagile-setup.ps1 -Wait
#>

[CmdletBinding()]
param (
    [string]$ProjectRoot = (Get-Location).Path,
    [string]$DistributionSource = "",
    [string]$DistributionRef = "main",
    [switch]$NonInteractive,
    [switch]$Wait
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# Canonical MxAgile distribution — used automatically when -DistributionSource is not provided
# and the bootstrap is not running from inside an existing distribution tree.
$CanonicalDistributionUrl    = "https://github.com/Zwergomaniac/MxAgile.git"
$CanonicalDistributionSubdir = "MxAi-Dev-System"   # distribution root lives here within the repo

# ---------------------------------------------------------------------------
# Direct-launch detection
# ---------------------------------------------------------------------------
$isDirectLaunch = $false
try {
    $parentName    = (Get-Process -Id $PID -ErrorAction Stop).Parent.ProcessName
    $isDirectLaunch = $parentName -in @('explorer', 'OpenWith')
} catch { }
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
    # 2. Detect project state and select operation
    # =========================================================================
    Write-Host ""
    Write-Host "=======================================" -ForegroundColor Cyan
    Write-Host "MxAgile Setup" -ForegroundColor Cyan
    Write-Host "=======================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Target project  : $ProjectRoot"
    Write-Host ""
    Write-Host "Detecting project state..."

    $coreMarker    = Join-Path $ProjectRoot ".mxagile\lifecycle.yaml"
    $coreInstalled = Test-Path -LiteralPath $coreMarker -PathType Leaf
    $coreState     = if ($coreInstalled) { "EXISTING_MXAGILE_PROJECT" } else { "FRESH_PROJECT" }
    $coreOperation = if ($coreInstalled) { "UPDATE" } else { "INSTALL" }

    Write-Host ""
    Write-Host "  MxAgile Core       : $coreState -> $coreOperation" -ForegroundColor $(if ($coreInstalled) { "Yellow" } else { "Green" })
    Write-Host ""

    # =========================================================================
    # Interactive pre-mutation summary (before ANY changes are made)
    # =========================================================================
    $isInteractive = (-not $NonInteractive) -and ($shouldWait -or $isDirectLaunch)

    Write-Host "=======================================" -ForegroundColor Cyan
    if ($coreInstalled) {
        Write-Host "This setup will:" -ForegroundColor White
        Write-Host "  - synchronize MxAgile Core framework files" -ForegroundColor White
        Write-Host "  - regenerate required MxAgile agent integrations" -ForegroundColor White
        Write-Host "  - preserve all project-owned knowledge and lifecycle state" -ForegroundColor White
    } else {
        Write-Host "This setup will:" -ForegroundColor White
        Write-Host "  - install MxAgile Core framework" -ForegroundColor White
        Write-Host "  - initialize mxcli tool integration" -ForegroundColor White
        Write-Host "  - generate required MxAgile agent integrations" -ForegroundColor White
    }
    Write-Host ""
    Write-Host "  The Mendix application itself will not intentionally be modified by setup." -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Protected (never overwritten by setup):" -ForegroundColor DarkGray
    Write-Host "    .mxagile/layers/                   Company Layers" -ForegroundColor DarkGray
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
        $devInstaller = Join-Path $PSScriptRoot "scripts\install-core.ps1"
        if (Test-Path -LiteralPath $devInstaller -PathType Leaf) {
            Write-Host "Distribution    : $PSScriptRoot (running from within distribution)"
            $distributionRoot         = $PSScriptRoot
            $provenanceCoreSource     = $PSScriptRoot
            $provenanceCoreSourceType = "local"
            $provenanceCoreRef        = ""
            $provenanceCoreSubdir     = ""
        } else {
            $tempDistDir = Join-Path $env:TEMP "mxagile-setup-$([System.Guid]::NewGuid().ToString('N').Substring(0,8))"
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
            $distributionRoot = if (Test-Path -LiteralPath (Join-Path $subDirPath "scripts\install-core.ps1") -PathType Leaf) {
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
        $tempDistDir = Join-Path $env:TEMP "mxagile-setup-$([System.Guid]::NewGuid().ToString('N').Substring(0,8))"
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
    $canonicalInstaller = Join-Path $distributionRoot "scripts\install-core.ps1"
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
        -ProvenanceFlavor         "core" `
        -ProvenanceCoreSource     $provenanceCoreSource `
        -ProvenanceCoreSourceType $provenanceCoreSourceType `
        -ProvenanceCoreRef        $provenanceCoreRef `
        -ProvenanceCoreSubdir     $provenanceCoreSubdir `
        -IsUpdate                 $coreInstalled
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
