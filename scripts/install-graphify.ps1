#Requires -Version 7
<#
.SYNOPSIS
    Graphify Optional Enrichment Provider Installer for MxAgile.

.DESCRIPTION
    Installs or verifies the Graphify CLI via 'uv tool install graphifyy'.
    Graphify is an OPTIONAL enrichment overlay — it MUST NOT be a required
    dependency. Installation failure never blocks MxAgile core operations.

    Ownership: MxAgile Core (scripts/install-graphify.ps1)

    This installer:
      1. Verifies that uv is available (required to install graphify tools)
      2. Checks whether graphify is already installed at an acceptable version
      3. Installs/upgrades via 'uv tool install graphifyy>=<constraint>'
      4. Runs a smoke test (graphify --version)
      5. Writes scripts/graphify-state.yaml with installation status

    The installer writes state to .mxagile/state/graphify-state.yaml so that
    graph_capability.py and graphify_provider.py can detect installation status
    without invoking the CLI on every call.

.PARAMETER VersionConstraint
    Minimum acceptable version. Defaults to the MxAgile-validated floor: 0.9.28.

.PARAMETER Force
    Force reinstall even if an acceptable version is already installed.

.PARAMETER StateDir
    Directory for graphify-state.yaml. Defaults to .mxagile/state relative to
    the project root (parent of this script's directory).
#>

[CmdletBinding()]
param(
    [string]$VersionConstraint = '0.9.28',
    [switch]$Force,
    [string]$StateDir = ''
)

$ErrorActionPreference = 'Continue'

# ─── Resolve paths ────────────────────────────────────────────────────────────

$ScriptDir  = $PSScriptRoot
$ProjectDir = Split-Path $ScriptDir -Parent

if ([string]::IsNullOrWhiteSpace($StateDir)) {
    $StateDir = Join-Path $ProjectDir '.mxagile' 'state'
}

$StateFile = Join-Path $StateDir 'graphify-state.yaml'

function Write-State {
    param([hashtable]$State)
    $null = New-Item -ItemType Directory -Path $StateDir -Force
    $lines = @()
    foreach ($key in $State.Keys) {
        $val = $State[$key]
        if ($null -eq $val)        { $lines += "${key}: null"   }
        elseif ($val -is [bool])   { $lines += "${key}: $(if ($val) { 'true' } else { 'false' })" }
        elseif ($val -is [string]) { $lines += "${key}: `"$val`"" }
        else                       { $lines += "${key}: $val"   }
    }
    $lines | Set-Content -Path $StateFile -Encoding UTF8
}

# ─── Header ───────────────────────────────────────────────────────────────────

Write-Host ''
Write-Host '=== Graphify Optional Enrichment Provider Installer ===' -ForegroundColor Cyan
Write-Host "Project  : $ProjectDir"
Write-Host "Minimum  : $VersionConstraint"
Write-Host "State    : $StateFile"
Write-Host ''

# ─── 1. Check uv availability ────────────────────────────────────────────────

Write-Host 'Checking uv availability...' -ForegroundColor Cyan

$uvPath = $null
try {
    $uvOut  = & uv --version 2>&1
    $uvPath = (Get-Command uv -ErrorAction SilentlyContinue)?.Source
    Write-Host "  uv     : $uvOut" -ForegroundColor Green
} catch {
    Write-Host "  uv not found in PATH." -ForegroundColor Red
    Write-Host ''
    Write-Host '[WARN] Graphify installation requires uv.' -ForegroundColor Yellow
    Write-Host '  Install uv: https://docs.astral.sh/uv/getting-started/installation/'
    Write-Host '  Graphify will remain MISSING. MxAgile core operations are unaffected.'
    Write-State @{
        status             = 'MISSING'
        installed_version  = $null
        version_constraint = $VersionConstraint
        install_path       = $null
        install_date       = $null
        graph_path         = $null
        node_count         = $null
        link_count         = $null
        last_built         = $null
        build_duration_s   = $null
        source_fingerprint = $null
        local_only         = $true
        error              = 'uv not found — required for Graphify installation'
    }
    exit 0   # Non-fatal: optional provider
}

Write-Host ''

# ─── 2. Check existing graphify installation ──────────────────────────────────

Write-Host 'Checking existing graphify installation...' -ForegroundColor Cyan

$graphifyPath     = (Get-Command graphify -ErrorAction SilentlyContinue)?.Source
$installedVersion = $null

if ($graphifyPath) {
    try {
        $verOut = & graphify --version 2>&1
        $match  = [regex]::Match($verOut, '(\d+\.\d+\.\d+)')
        if ($match.Success) {
            $installedVersion = $match.Groups[1].Value
        }
    } catch { }
}

if ($installedVersion) {
    Write-Host "  Found  : $graphifyPath ($installedVersion)" -ForegroundColor Green
    if (-not $Force) {
        $installed = [System.Version]$installedVersion
        $minimum   = [System.Version]$VersionConstraint
        if ($installed -ge $minimum) {
            Write-Host "  Version $installedVersion >= minimum $VersionConstraint — already satisfied." -ForegroundColor Green
            Write-Host ''
            Write-Host "[OK] Graphify $installedVersion meets the version requirement." -ForegroundColor Green
            Write-State @{
                status             = 'MISSING'
                installed_version  = $installedVersion
                version_constraint = $VersionConstraint
                install_path       = $graphifyPath
                install_date       = (Get-Date -Format 'o')
                graph_path         = $null
                node_count         = $null
                link_count         = $null
                last_built         = $null
                build_duration_s   = $null
                source_fingerprint = $null
                local_only         = $true
                error              = $null
            }
            exit 0
        }
        Write-Host "  Version $installedVersion < minimum $VersionConstraint — upgrade required." -ForegroundColor Yellow
    } else {
        Write-Host '  --Force specified — reinstalling.' -ForegroundColor Yellow
    }
} else {
    Write-Host '  graphify not found in PATH — fresh install.' -ForegroundColor Yellow
}

Write-Host ''

# ─── 3. Install via uv ───────────────────────────────────────────────────────

$packageSpec = "graphifyy>=$VersionConstraint"
Write-Host "Installing $packageSpec via uv..." -ForegroundColor Cyan
Write-Host "  Command: uv tool install $packageSpec"
Write-Host ''

try {
    & uv tool install $packageSpec 2>&1 | ForEach-Object { Write-Host "  $_" }
    if ($LASTEXITCODE -ne 0) {
        throw "uv tool install exited with code $LASTEXITCODE"
    }
} catch {
    $errMsg = $_.Exception.Message
    Write-Host ''
    Write-Host "[WARN] Graphify installation failed: $errMsg" -ForegroundColor Yellow
    Write-Host '  Graphify enrichment will remain unavailable.'
    Write-Host '  MxAgile core operations are unaffected.'
    Write-State @{
        status             = 'MISSING'
        installed_version  = $null
        version_constraint = $VersionConstraint
        install_path       = $null
        install_date       = $null
        graph_path         = $null
        node_count         = $null
        link_count         = $null
        last_built         = $null
        build_duration_s   = $null
        source_fingerprint = $null
        local_only         = $true
        error              = $errMsg
    }
    exit 0   # Non-fatal: optional provider
}

Write-Host ''

# ─── 4. Smoke test ───────────────────────────────────────────────────────────

Write-Host 'Smoke test...' -ForegroundColor Cyan

$newPath    = (Get-Command graphify -ErrorAction SilentlyContinue)?.Source
$newVersion = $null

if ($newPath) {
    try {
        $verOut = & graphify --version 2>&1
        $match  = [regex]::Match($verOut, '(\d+\.\d+\.\d+)')
        if ($match.Success) {
            $newVersion = $match.Groups[1].Value
        }
        Write-Host "  Path   : $newPath"
        Write-Host "  Version: $newVersion" -ForegroundColor Green
    } catch {
        Write-Host "  graphify installed but could not be started: $($_.Exception.Message)" -ForegroundColor Yellow
    }
} else {
    Write-Host '  graphify not found in PATH after install — uv tool path may not be in PATH.' -ForegroundColor Yellow
    Write-Host '  Run: uv tool update-shell   (then reopen your terminal)'
}

Write-Host ''

# ─── 5. Write state file ─────────────────────────────────────────────────────

$state = @{
    status             = if ($newVersion) { 'MISSING' } else { 'FAILED' }
    installed_version  = $newVersion
    version_constraint = $VersionConstraint
    install_path       = $newPath
    install_date       = (Get-Date -Format 'o')
    graph_path         = $null
    node_count         = $null
    link_count         = $null
    last_built         = $null
    build_duration_s   = $null
    source_fingerprint = $null
    local_only         = $true
    error              = if ($newVersion) { $null } else { 'graphify not in PATH after install' }
}

Write-State $state

if ($newVersion) {
    Write-Host "[OK] Graphify $newVersion installed." -ForegroundColor Green
    Write-Host "     State written to: $StateFile"
    Write-Host ''
    Write-Host 'Next: enable graphify enrichment in .mxagile/config.yaml:' -ForegroundColor Cyan
    Write-Host '  enrichment_provider: graphify'
    Write-Host '  graphify:'
    Write-Host '    enabled: true'
    Write-Host ''
    Write-Host "Then run: python scripts/graphify_provider.py build  (to build the initial graph)"
    exit 0
} else {
    Write-Host "[WARN] Graphify installed but could not be verified. Check PATH for uv tools." -ForegroundColor Yellow
    Write-Host '  Run: uv tool update-shell   (then reopen terminal)'
    exit 0   # Non-fatal: optional provider
}
