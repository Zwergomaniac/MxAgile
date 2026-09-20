<#
.SYNOPSIS
Installs MxAgile and the Mercedes-Benz Company Layer.

.DESCRIPTION
Runs the canonical generic MxAgile installer first and installs the
Mercedes-Benz Company Layer only after generic installation succeeds.

The target Mendix project defaults to the current working directory.
#>

[CmdletBinding()]
param (
    [string]$ProjectRoot = (Get-Location).Path,

    [string]$MercedesGitUrl =
        "https://mercedes-benz.ghe.com/DFC-Applikationsentwicklung/MxAgile-CompanyLayer.git",

    [string]$MercedesRef = "main"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

try {
    # -----------------------------------------------------------------
    # Resolve target project
    # -----------------------------------------------------------------

    if (-not (Test-Path -LiteralPath $ProjectRoot -PathType Container)) {
        throw "Project root does not exist: $ProjectRoot"
    }

    $ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)

    # -----------------------------------------------------------------
    # Safety preflight
    # -----------------------------------------------------------------

    $mprFiles = @(
        Get-ChildItem `
            -LiteralPath $ProjectRoot `
            -File `
            -Filter "*.mpr"
    )

    if ($mprFiles.Count -eq 0) {
        throw "No root-level .mpr file found in project root: $ProjectRoot"
    }

    if ($mprFiles.Count -gt 1) {
        $names = ($mprFiles | ForEach-Object { $_.Name }) -join ", "
        throw "Multiple root-level .mpr files found in '$ProjectRoot': $names"
    }

    Write-Host "Safety Preflight passed: Single .mpr file detected."

    # -----------------------------------------------------------------
    # Generic MxAgile
    # -----------------------------------------------------------------

    $GenericInstaller = Join-Path $PSScriptRoot "install-mxagile.ps1"

    if (-not (Test-Path -LiteralPath $GenericInstaller -PathType Leaf)) {
        throw "Generic MxAgile installer not found: $GenericInstaller"
    }

    Write-Host ""
    Write-Host "Installing Generic MxAgile..."

    & $GenericInstaller -ProjectRoot $ProjectRoot

    if ($LASTEXITCODE -ne 0) {
        throw "Generic MxAgile installation failed with exit code $LASTEXITCODE."
    }

    # -----------------------------------------------------------------
    # Mercedes Layer
    # -----------------------------------------------------------------

    $LayerResolver = Join-Path $PSScriptRoot "scripts\fetch-layer.ps1"

    if (-not (Test-Path -LiteralPath $LayerResolver -PathType Leaf)) {
        throw "Layer resolver not found: $LayerResolver"
    }

    Write-Host ""
    Write-Host "Installing Mercedes-Benz Company Layer..."

    & $LayerResolver `
        -RepositoryUrl $MercedesGitUrl `
        -Ref $MercedesRef `
        -ProjectRoot $ProjectRoot

    if (-not $?) {
        throw "Mercedes-Benz Company Layer resolver failed."
    }

    # -----------------------------------------------------------------
    # Final validation
    # -----------------------------------------------------------------

    $LayerPath = Join-Path $ProjectRoot ".mxagile\layers\mercedes-benz"

    if (-not (Test-Path -LiteralPath $LayerPath -PathType Container)) {
        throw "Mercedes-Benz Layer was not installed at expected location: $LayerPath"
    }

    $ProvenancePath = Join-Path $LayerPath "provenance.json"

    if (-not (Test-Path -LiteralPath $ProvenancePath -PathType Leaf)) {
        throw "Mercedes-Benz Layer provenance is missing: $ProvenancePath"
    }

    $NestedGit = Join-Path $LayerPath ".git"

    if (Test-Path -LiteralPath $NestedGit) {
        throw "Installed Mercedes-Benz Layer incorrectly contains nested Git metadata: $NestedGit"
    }

    Write-Host ""
    Write-Host "Mercedes-Benz installation complete." -ForegroundColor Green
    exit 0
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}