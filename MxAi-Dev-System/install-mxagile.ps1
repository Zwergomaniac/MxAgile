<#
.SYNOPSIS
    Standalone MxAgile bootstrap installer.

.DESCRIPTION
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
    Target Mendix project to install MxAgile into.
    Defaults to the current working directory.

.PARAMETER DistributionSource
    Path to the MxAgile distribution directory (local filesystem), or a Git URL
    to clone. When not provided, the script checks if it is already being run
    from within a MxAgile distribution (development use case only).

.PARAMETER DistributionRef
    Git branch / tag / commit ref to use when -DistributionSource is a Git URL.
    Defaults to "main".

.EXAMPLE
    # Standalone use — acquire distribution from GitHub
    .\install-mxagile.ps1 -DistributionSource "https://github.com/your-org/mxagile.git"

.EXAMPLE
    # Standalone use — acquire distribution from a local directory
    .\install-mxagile.ps1 -DistributionSource "C:\tools\MxAi-Dev-System"

.EXAMPLE
    # Development use — run from within the MxAgile distribution tree
    .\install-mxagile.ps1 -ProjectRoot "C:\projects\MyApp"
#>

[CmdletBinding()]
param (
    [string]$ProjectRoot = (Get-Location).Path,
    [string]$DistributionSource = "",
    [string]$DistributionRef = "main"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$tempDistDir = $null

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
    # =========================================================================
    $distributionRoot = $null

    if ([string]::IsNullOrWhiteSpace($DistributionSource)) {
        # Development use case: check if this bootstrap lives inside the distribution
        $devInstaller = Join-Path $PSScriptRoot "scripts\install-core.ps1"
        if (Test-Path -LiteralPath $devInstaller -PathType Leaf) {
            Write-Host "Distribution    : $PSScriptRoot (running from within distribution)"
            $distributionRoot = $PSScriptRoot
        } else {
            throw @"

MxAgile distribution not found.

This script is not running from within a MxAgile distribution directory,
and no -DistributionSource was provided.

Usage examples:
  .\install-mxagile.ps1 -DistributionSource "https://github.com/your-org/mxagile.git"
  .\install-mxagile.ps1 -DistributionSource "C:\path\to\MxAi-Dev-System"
"@
        }
    } elseif (Test-Path -LiteralPath $DistributionSource -PathType Container) {
        # Local filesystem path
        $distributionRoot = [System.IO.Path]::GetFullPath($DistributionSource)
        Write-Host "Distribution    : $distributionRoot (local path)"
    } else {
        # Treat as a Git URL — clone to a temporary directory
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
        $distributionRoot = $tempDistDir
        Write-Host "  -> Cloned successfully."
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
    & $canonicalInstaller -ProjectRoot $ProjectRoot
    $exitCode = $LASTEXITCODE
    exit $exitCode

} catch {
    Write-Host ""
    Write-Host "Bootstrap failed!" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
} finally {
    # Always clean up temporary distribution clone, regardless of outcome
    if ($null -ne $tempDistDir -and (Test-Path -LiteralPath $tempDistDir -PathType Container)) {
        Write-Host ""
        Write-Host "Cleaning up temporary distribution at: $tempDistDir"
        Remove-Item -LiteralPath $tempDistDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
