<#
.SYNOPSIS
    Standalone MxAgile bootstrap installer.

.DESCRIPTION
    Acquires the MxAgile distribution (from a local filesystem path or a Git URL),
    then invokes the canonical installer (scripts/install-core.ps1) from that
    distribution against the target Mendix project.

    This script may be placed anywhere -- it does NOT need to live inside the
    MxAgile distribution directory.

    Path model:
        bootstrap    = this file ($PSScriptRoot, wherever it was placed)
        distribution = acquired from -DistributionSource, OR $PSScriptRoot when
                       already running from within the distribution (dev use)
        target       = -ProjectRoot (defaults to current working directory)

    These three paths are independent and must not be conflated.

.PARAMETER ProjectRoot
    Target Mendix project to install MxAgile into.
    Defaults to the current working directory.

.PARAMETER DistributionSource
    Path to the MxAgile distribution directory (local filesystem), or a Git URL
    to clone. When not provided, the script checks if it is already being run
    from within a MxAgile distribution (development use case only).

.PARAMETER DistributionRef
    Git branch / tag / commit ref to use when -DistributionSource is a Git URL.
    Defaults to "main".

.PARAMETER Wait
    Pause for a keypress before exiting. Intended for interactive/direct-launch
    scenarios (e.g. right-click "Run with PowerShell") where the window would
    otherwise close before the developer can read the result.

    Direct-launch is also detected automatically (parent process = explorer.exe).
    Do NOT pass -Wait in automation, CI, or scripted invocations.

.EXAMPLE
    # Standalone use -- acquire distribution from GitHub
    .\install-mxagile.ps1 -DistributionSource "https://github.com/your-org/mxagile.git"

.EXAMPLE
    # Standalone use -- acquire distribution from a local directory
    .\install-mxagile.ps1 -DistributionSource "C:\tools\MxAi-Dev-System"

.EXAMPLE
    # Development use -- run from within the MxAgile distribution tree
    .\install-mxagile.ps1 -ProjectRoot "C:\projects\MyApp"

.EXAMPLE
    # Interactive/direct-launch use -- keep window open after completion
    .\install-mxagile.ps1 -Wait
#>

[CmdletBinding()]
param (
    [string]$ProjectRoot = (Get-Location).Path,
    [string]$DistributionSource = "",
    [string]$DistributionRef = "main",
    [switch]$Wait
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# Canonical MxAgile distribution -- used automatically when -DistributionSource is not provided
# and the bootstrap is not running from inside an existing distribution tree.
$CanonicalDistributionUrl    = "https://github.com/Zwergomaniac/MxAgile.git"
$CanonicalDistributionSubdir = "MxAi-Dev-System"   # distribution root lives here within the repo

# ---------------------------------------------------------------------------
# Direct-launch detection
# Detects when the script is launched via right-click "Run with PowerShell"
# or similar (parent process = explorer.exe / OpenWith.exe). In that case the
# console window belongs to this script and will close immediately on exit,
# so we must pause to keep the result readable.
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
    Write-Host "Target project  : $ProjectRoot"

    # =========================================================================
    # 2. Acquire MxAgile distribution
    #    Resolution order:
    #      1. Explicit -DistributionSource (override)
    #      2. $PSScriptRoot contains scripts/install-core.ps1 (dev / running from inside distribution)
    #      3. Clone from $CanonicalDistributionUrl (zero-config, normal user path)
    # =========================================================================
    $distributionRoot = $null

    # Provenance variables - populated in each resolution branch below
    $provenanceCoreSource     = ""
    $provenanceCoreSourceType = ""
    $provenanceCoreRef        = $DistributionRef
    $provenanceCoreSubdir     = ""

    if ([string]::IsNullOrWhiteSpace($DistributionSource)) {
        # Priority 2: dev mode -- bootstrap is running from inside the distribution tree
        $devInstaller = Join-Path $PSScriptRoot "scripts\install-core.ps1"
        if (Test-Path -LiteralPath $devInstaller -PathType Leaf) {
            Write-Host "Distribution    : $PSScriptRoot (running from within distribution)"
            $distributionRoot         = $PSScriptRoot
            $provenanceCoreSource     = $PSScriptRoot
            $provenanceCoreSourceType = "local"
            $provenanceCoreRef        = ""
            $provenanceCoreSubdir     = ""
        } else {
            # Priority 3: zero-config -- clone canonical distribution automatically
            $tempDistDir = Join-Path $env:TEMP "mxagile-install-$([System.Guid]::NewGuid().ToString('N').Substring(0,8))"
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

            # Distribution root is MxAi-Dev-System/ within the repo; fall back to clone root if absent
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
        # Local filesystem path
        $distributionRoot             = [System.IO.Path]::GetFullPath($DistributionSource)
        Write-Host "Distribution    : $distributionRoot (local path)"
        $provenanceCoreSource         = $distributionRoot
        $provenanceCoreSourceType     = "local"
        $provenanceCoreRef            = ""
        $provenanceCoreSubdir         = ""
    } else {
        # Treat as a Git URL -- clone to a temporary directory
        $tempDistDir = Join-Path $env:TEMP "mxagile-install-$([System.Guid]::NewGuid().ToString('N').Substring(0,8))"
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
    # 3. Safety: distribution must not be inside the target project
    # =========================================================================
    $targetNorm = $ProjectRoot.TrimEnd('\', '/')
    $distNorm   = $distributionRoot.TrimEnd('\', '/')
    if ($distNorm -eq $targetNorm -or
        $distNorm.StartsWith($targetNorm + '\') -or
        $distNorm.StartsWith($targetNorm + '/')) {
        throw "Distribution root ($distributionRoot) must not be inside the target project ($ProjectRoot)."
    }

    # =========================================================================
    # 4. Verify canonical installer exists in distribution
    # =========================================================================
    $canonicalInstaller = Join-Path $distributionRoot "scripts\install-core.ps1"
    if (-not (Test-Path -LiteralPath $canonicalInstaller -PathType Leaf)) {
        throw "Canonical installer not found in MxAgile distribution: $canonicalInstaller"
    }
    Write-Host "Canonical installer: $canonicalInstaller"
    Write-Host ""

    # =========================================================================
    # 5. Invoke canonical installer against the target project
    # =========================================================================
    & $canonicalInstaller `
        -ProjectRoot              $ProjectRoot `
        -ProvenanceFlavor         "core" `
        -ProvenanceCoreSource     $provenanceCoreSource `
        -ProvenanceCoreSourceType $provenanceCoreSourceType `
        -ProvenanceCoreRef        $provenanceCoreRef `
        -ProvenanceCoreSubdir     $provenanceCoreSubdir
    $exitCode = $LASTEXITCODE

} catch {
    Write-Host ""
    Write-Host "Bootstrap failed!" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    $exitCode = 1
} finally {
    # Always clean up temporary distribution clone, regardless of outcome
    if ($null -ne $tempDistDir -and (Test-Path -LiteralPath $tempDistDir -PathType Container)) {
        Write-Host ""
        Write-Host "Cleaning up temporary distribution at: $tempDistDir"
        Remove-Item -LiteralPath $tempDistDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ---------------------------------------------------------------------------
# Interactive/direct-launch pause
# Only reached when NOT called via "exit" from a sub-call. Keeps the console
# window open after direct-launch or when -Wait is explicitly passed.
# Automation/terminal invocations: $shouldWait is false, no pause.
# ---------------------------------------------------------------------------
if ($shouldWait) {
    Write-Host ""
    Write-Host "Press any key to continue..." -ForegroundColor DarkGray
    try { [void][System.Console]::ReadKey($true) } catch { }
}

exit $exitCode
