<#
.SYNOPSIS
Initializes the local MxAgile project structure and mxcli tooling.

.DESCRIPTION
Creates required project-local MxAgile directories and ensures mxcli.exe
is available in the target Mendix project.

Framework-owned source content is expected to be provided by the bootstrap
installation process. This script does not resolve Company Layers.
#>

[CmdletBinding()]
param (
    [string]$ProjectRoot = (Get-Location).Path
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

if (-not (Test-Path -LiteralPath $ProjectRoot -PathType Container)) {
    throw "Project root does not exist: $ProjectRoot"
}

$ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)

# ---------------------------------------------------------------------
# Python
# ---------------------------------------------------------------------

Write-Host "Checking for Python and pip..."

$PythonCommand = Get-Command python -ErrorAction SilentlyContinue

if (-not $PythonCommand) {
    throw "Python is not installed or not available in PATH."
}

$PipCommand = Get-Command pip -ErrorAction SilentlyContinue

$RequirementsFile = Join-Path $ProjectRoot "requirements.txt"

if ($PipCommand -and
    (Test-Path -LiteralPath $RequirementsFile -PathType Leaf)) {

    Write-Host "Found requirements.txt. Installing dependencies..."

    & $PipCommand.Source install -r $RequirementsFile

    if ($LASTEXITCODE -ne 0) {
        throw "pip dependency installation failed with exit code $LASTEXITCODE."
    }
}
elseif (-not $PipCommand) {
    Write-Warning "pip is not available; dependency installation skipped."
}
else {
    Write-Host "No requirements.txt found, skipping dependency installation."
}

# ---------------------------------------------------------------------
# mxcli
# ---------------------------------------------------------------------

Write-Host "Checking for mxcli.exe..."

$MxcliPath = Join-Path $ProjectRoot "mxcli.exe"

if (-not (Test-Path -LiteralPath $MxcliPath -PathType Leaf)) {

    Write-Host "mxcli.exe not found in project root. Running installer..."

    $MxcliInstaller = Join-Path $PSScriptRoot "install-mxcli.ps1"

    if (-not (Test-Path -LiteralPath $MxcliInstaller -PathType Leaf)) {
        throw "mxcli installer not found: $MxcliInstaller"
    }

    & $MxcliInstaller -TargetDir $ProjectRoot

    if (-not $?) {
        throw "mxcli installer failed."
    }
}

if (-not (Test-Path -LiteralPath $MxcliPath -PathType Leaf)) {
    throw "mxcli.exe is still missing after installation: $MxcliPath"
}

Write-Host "mxcli ready:"
Write-Host "  $MxcliPath"

# ---------------------------------------------------------------------
# Core directories
# ---------------------------------------------------------------------

Write-Host ""
Write-Host "Starting MxAgile initialization in:"
Write-Host "  $ProjectRoot"

$MxAgileDir = Join-Path $ProjectRoot ".mxagile"

$Directories = @(
    $MxAgileDir
    (Join-Path $ProjectRoot "specs")
    (Join-Path $ProjectRoot "requirements")
    (Join-Path $ProjectRoot "planning\tasks")
    (Join-Path $MxAgileDir "state")
    (Join-Path $MxAgileDir "schemas")
    (Join-Path $MxAgileDir "templates")
    (Join-Path $MxAgileDir "layers")
)

foreach ($Directory in $Directories) {

    if (-not (Test-Path -LiteralPath $Directory -PathType Container)) {

        Write-Host "Creating directory: $Directory"

        New-Item `
            -ItemType Directory `
            -Path $Directory `
            -Force |
            Out-Null
    }
    else {

        Write-Host "Directory exists, skipping: $Directory"
    }
}

Write-Host ""
Write-Host "MxAgile initialization complete." -ForegroundColor Green