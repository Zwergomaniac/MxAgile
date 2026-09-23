<#
.SYNOPSIS
    mxcli Stable Installer / Updater for Windows x64.

.DESCRIPTION
    Resolves the latest stable mxcli release from GitHub, checks whether
    the project-local binary is already at an acceptable version, and
    downloads + installs only when necessary.

    Ownership: This script (and its project-distributed copy update-mxcli.ps1)
    is the SOLE canonical path for acquiring or updating the project-local
    mxcli.exe. No agent, migration script, or wrapper may copy an arbitrary
    PATH/global/developer-local mxcli into the project as a substitute.

.PARAMETER TargetDir
    Directory where mxcli.exe will be installed. Defaults to $PSScriptRoot.

.PARAMETER MinimumVersion
    If specified, an existing local binary is accepted (without checking for
    a newer remote version) as long as its version >= MinimumVersion.
    Leave empty (default) to always check for the latest stable release.
    Extension point for future dependency management -- do not use for
    informal version pinning without explicit framework governance.

.PARAMETER DownloadTimeoutSec
    HTTP timeout in seconds for the binary download. Default: 300.

.PARAMETER ApiTimeoutSec
    HTTP timeout in seconds for GitHub API calls. Default: 30.

.PARAMETER RetryCount
    Number of download retry attempts after the first failure. Default: 2.
#>

[CmdletBinding()]
param (
    [string]$TargetDir          = $PSScriptRoot,
    [string]$MinimumVersion     = "",
    [int]$DownloadTimeoutSec    = 300,
    [int]$ApiTimeoutSec         = 30,
    [int]$RetryCount            = 2
)

$ErrorActionPreference = "Stop"

$Repo = "mendixlabs/mxcli"

# Platform detection — works on PS 5.1 (Windows-only) and PS Core (all platforms)
$_isWin = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
    [System.Runtime.InteropServices.OSPlatform]::Windows)
$_isMac = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
    [System.Runtime.InteropServices.OSPlatform]::OSX)

$AssetName  = if ($_isWin)  { 'mxcli-windows-amd64.exe' }
              elseif ($_isMac) { 'mxcli-darwin-amd64' }
              else            { 'mxcli-linux-amd64' }
$BinaryName = if ($_isWin) { 'mxcli.exe' } else { 'mxcli' }

function Format-Bytes {
    param([long]$Bytes)
    if ($Bytes -ge 1GB) { return "{0:F1} GB" -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return "{0:F1} MB" -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return "{0:F1} KB" -f ($Bytes / 1KB) }
    return "$Bytes B"
}

Write-Host ""
Write-Host "=== mxcli Stable Installer ===" -ForegroundColor Cyan
Write-Host "Repository : $Repo"
Write-Host "Platform   : $(if ($_isWin) { 'Windows' } elseif ($_isMac) { 'macOS' } else { 'Linux' })"
Write-Host "Asset      : $AssetName"
Write-Host "Target     : $(Join-Path $TargetDir $BinaryName)"
if ($MinimumVersion) { Write-Host "Minimum    : $MinimumVersion" }
Write-Host ""

$TargetExe = Join-Path $TargetDir $BinaryName

# ------------------------------------------------------------
# 1. Resolve latest stable release via GitHub API
# ------------------------------------------------------------

Write-Host "Resolving latest stable mxcli release..." -ForegroundColor Cyan

$headers = @{
    "Accept"     = "application/vnd.github+json"
    "User-Agent" = "mxcli-powershell-installer"
}

try {
    $releases = Invoke-RestMethod `
        -Uri         "https://api.github.com/repos/$Repo/releases" `
        -Headers     $headers `
        -TimeoutSec  $ApiTimeoutSec
} catch {
    throw "GitHub API call failed (timeout=${ApiTimeoutSec}s): $($_.Exception.Message)"
}

$release = $releases |
    Where-Object {
        -not $_.draft -and
        -not $_.prerelease -and
        $_.tag_name -notmatch "(?i)nightly"
    } |
    Select-Object -First 1

if (-not $release) {
    throw "No stable mxcli release found. Check network access and GitHub API availability."
}

$asset = $release.assets |
    Where-Object { $_.name -eq $AssetName } |
    Select-Object -First 1

if (-not $asset) {
    $available = ($release.assets | ForEach-Object { $_.name }) -join ", "
    throw "Asset '$AssetName' not found in release $($release.tag_name). Available: $available"
}

$remoteVersionMatch = [regex]::Match($release.tag_name, '(\d+\.\d+\.\d+)')
$remoteVersionStr   = if ($remoteVersionMatch.Success) { $remoteVersionMatch.Groups[1].Value } else { $release.tag_name }
$assetSizeHuman     = Format-Bytes -Bytes $asset.size

Write-Host "  Latest  : $($release.tag_name)  ($assetSizeHuman)" -ForegroundColor Green
Write-Host ""

# ------------------------------------------------------------
# 2. Check local version
# ------------------------------------------------------------

Write-Host "Checking local version..." -ForegroundColor Cyan

if (Test-Path -LiteralPath $TargetExe -PathType Leaf) {
    $localVersionStr = ""
    try {
        $localVersionOutput = & $TargetExe --version 2>$null
        $localMatch         = [regex]::Match($localVersionOutput, '(\d+\.\d+\.\d+)')
        if ($localMatch.Success) { $localVersionStr = $localMatch.Groups[1].Value }
    } catch {
        Write-Warning "  Could not read local mxcli version -- will reinstall."
    }

    if ($localVersionStr) {
        $localSemVer  = [System.Version]$localVersionStr
        $remoteSemVer = if ($remoteVersionMatch.Success) { [System.Version]$remoteVersionStr } else { $null }

        # MinimumVersion shortcut: if caller specified a floor and local >= floor, accept it
        if ($MinimumVersion) {
            $minSemVer = [System.Version]$MinimumVersion
            if ($localSemVer -ge $minSemVer) {
                Write-Host "  Local $localVersionStr >= minimum $MinimumVersion -- requirement satisfied." -ForegroundColor Green
                Write-Host ""
                Write-Host "[OK] mxcli $localVersionStr meets the minimum version requirement." -ForegroundColor Green
                exit 0
            }
            Write-Host "  Local $localVersionStr < minimum $MinimumVersion -- upgrade required." -ForegroundColor Yellow
        } elseif ($remoteSemVer -and $localSemVer -ge $remoteSemVer) {
            Write-Host "  Local $localVersionStr >= remote $remoteVersionStr -- already up-to-date." -ForegroundColor Green
            Write-Host ""
            Write-Host "[OK] mxcli is already up-to-date (v$localVersionStr)." -ForegroundColor Green
            exit 0
        } else {
            Write-Host "  Local $localVersionStr < remote $remoteVersionStr -- update required." -ForegroundColor Yellow
        }
    } else {
        Write-Host "  Local mxcli version unreadable -- reinstalling." -ForegroundColor Yellow
    }
} else {
    Write-Host "  No local mxcli.exe found -- fresh install." -ForegroundColor Yellow
}

Write-Host ""

# ------------------------------------------------------------
# 3. Download with retry
# ------------------------------------------------------------

$tempBase   = [System.IO.Path]::GetTempPath()
$tempFile   = Join-Path $tempBase "mxcli-$($release.tag_name)-$AssetName"
$maxAttempts = 1 + [Math]::Max(0, $RetryCount)

for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
    if ($attempt -gt 1) {
        $delay = 5 * ($attempt - 1)
        Write-Host "  Retrying (attempt $attempt/$maxAttempts, waiting ${delay}s)..." -ForegroundColor Yellow
        Start-Sleep -Seconds $delay
    }

    Write-Host "Downloading mxcli $($release.tag_name) ($assetSizeHuman)..." -ForegroundColor Cyan
    Write-Host "  Timeout : ${DownloadTimeoutSec}s  |  Attempt $attempt/$maxAttempts"

    $downloadOk = $false
    try {
        Invoke-WebRequest `
            -Uri             $asset.browser_download_url `
            -OutFile         $tempFile `
            -UseBasicParsing `
            -TimeoutSec      $DownloadTimeoutSec
        $downloadOk = $true
    } catch {
        if ($attempt -lt $maxAttempts) {
            Write-Warning "  Download attempt $attempt failed: $($_.Exception.Message)"
            continue
        }
        throw "Download failed after $maxAttempts attempt(s): $($_.Exception.Message)"
    }

    if ($downloadOk) { break }
}

# ------------------------------------------------------------
# 4. Verify download
# ------------------------------------------------------------

Write-Host ""
Write-Host "Verifying download..." -ForegroundColor Cyan

if (-not (Test-Path -LiteralPath $tempFile -PathType Leaf)) {
    throw "Download verification failed: file not found at $tempFile"
}

$actualSize   = (Get-Item -LiteralPath $tempFile).Length
$expectedSize = $asset.size
$actualHuman  = Format-Bytes -Bytes $actualSize
$expectedHuman = Format-Bytes -Bytes $expectedSize

if ($actualSize -ne $expectedSize) {
    Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
    throw "Download size mismatch: got $actualSize bytes ($actualHuman), expected $expectedSize bytes ($expectedHuman). The download may be truncated or corrupt."
}

Write-Host "  Size    : $actualHuman ($actualSize bytes) -- matches release asset" -ForegroundColor Green
Write-Host ""

# ------------------------------------------------------------
# 5. Install
# ------------------------------------------------------------

Write-Host "Installing mxcli..." -ForegroundColor Cyan

Copy-Item -Path $tempFile -Destination $TargetExe -Force
Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue

# Make executable on Linux / macOS (chmod is a no-op on Windows)
if (-not $_isWin) {
    $chmodResult = & chmod +x $TargetExe 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "chmod +x failed on $TargetExe ($chmodResult) -- binary may not be directly executable."
    } else {
        Write-Host "  chmod +x: OK"
    }
}

# ------------------------------------------------------------
# 6. Post-install verification
# ------------------------------------------------------------

if (-not (Test-Path -LiteralPath $TargetExe -PathType Leaf)) {
    throw "Post-install verification failed: mxcli.exe not found at $TargetExe"
}

try {
    $installedOutput  = & $TargetExe --version 2>$null
    $installedMatch   = [regex]::Match($installedOutput, '(\d+\.\d+\.\d+)')
    $installedVersion = if ($installedMatch.Success) { $installedMatch.Groups[1].Value } else { "(version unreadable)" }
    Write-Host "  Installed : $TargetExe"
    Write-Host "  Version   : $installedVersion"
    Write-Host ""
    Write-Host "[OK] mxcli $installedVersion installed successfully." -ForegroundColor Green
} catch {
    Write-Warning "mxcli.exe installed but could not be started: $($_.Exception.Message)"
    Write-Host "[OK] mxcli installed (post-install version check failed -- binary may still be usable)." -ForegroundColor Yellow
}

Write-Host ""
