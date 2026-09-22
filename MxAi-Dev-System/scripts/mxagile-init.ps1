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

    if ($LASTEXITCODE -ne 0) {
        throw "mxcli installer failed with exit code $LASTEXITCODE."
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
    (Join-Path $MxAgileDir "skills")
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

# ---------------------------------------------------------------------
# Core agent files
# ---------------------------------------------------------------------

$AgentFiles = @(
    (Join-Path $ProjectRoot "AGENT.md")
    (Join-Path $ProjectRoot "AGENTS.md")
    (Join-Path $ProjectRoot "CLAUDE.md")
)

foreach ($AgentFile in $AgentFiles) {
    if (-not (Test-Path -LiteralPath $AgentFile -PathType Leaf)) {
        Write-Host "Creating placeholder agent file: $AgentFile"
        [System.IO.File]::WriteAllLines($AgentFile, @(""))
    }
}

# ---------------------------------------------------------------------
# input-resources scaffold
# ---------------------------------------------------------------------

Write-Host ""
Write-Host "Initializing input-resources scaffold..."

$InputResourcesDir = Join-Path $ProjectRoot "input-resources"
$UiUxDir           = Join-Path $InputResourcesDir "ui-ux"

foreach ($dir in @($InputResourcesDir, $UiUxDir)) {
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Write-Host "Creating directory: $dir"
    }
    else {
        Write-Host "Directory exists, skipping: $dir"
    }
}

$InputReadme = Join-Path $InputResourcesDir "README.md"
if (-not (Test-Path -LiteralPath $InputReadme -PathType Leaf)) {
    Write-Host "Creating: $InputReadme"
    Set-Content -LiteralPath $InputReadme -Encoding UTF8 -Value @"
# Input Resources

Dieser Ordner enthaelt Eingabeartefakte fuer die Umsetzung des Mendix-Projekts.

## Verbindlichkeit

Relevante Artefakte in diesem Ordner muessen vor Planung und Implementierung
einer Story beruecksichtigt werden.

## Struktur

- ``ui-ux/``       — HTML-Mockups, Wireframes, Screenshots, UX-Ablaeufe
- ``requirements/`` — ergaenzende Anforderungsdokumente, fachliche Regeln
- ``processes/``   — Prozessdarstellungen, Zustandsmodelle

## HTML-Mockups

HTML-Mockups werden von einem AI-Agenten mit Playwright in einem echten Browser ausgefuehrt.

## Was hier NICHT abgelegt wird

Generierte Analysen, Planung und Laufzeit-Evidenz gehoeren NICHT hierher:
- Screenshots der laufenden App  → ``.concord/screenshots/app/``
- UI-Inventar YAML              → ``planning/ui-inventory/``
- Story-Spezifikationen         → ``planning/stories/``

## Schreibschutz

Dateien in diesem Ordner sind Eingabeartefakte und duerfen vom Agenten nicht
veraendert werden, sofern dies nicht ausdruecklich beauftragt wurde.
"@
}
else {
    Write-Host "File exists, preserving: $InputReadme"
}

$UiUxReadme = Join-Path $UiUxDir "README.md"
if (-not (Test-Path -LiteralPath $UiUxReadme -PathType Leaf)) {
    Write-Host "Creating: $UiUxReadme"
    Set-Content -LiteralPath $UiUxReadme -Encoding UTF8 -Value @"
# UI/UX Input Resources

HTML-Mockups, Wireframes, Screenshots und visuelle UX-Referenzen fuer die Mendix-Implementierung.

## Was hier liegt

- ``*.html``        — interaktive HTML-Mockups (werden von UI-Agent mit Playwright analysiert)
- ``*.png / *.jpg`` — Screenshots und statische visuelle Referenzen
- ``_archive/``     — aeltere Mockup-Versionen (werden vom UI-Agent ignoriert)

## Was hier NICHT liegt

- Laufzeit-Screenshots der App  → ``.concord/screenshots/app/``
- Analyse-Screenshots           → ``.concord/screenshots/mockup/``
- UI-Inventar YAML              → ``planning/ui-inventory/``

## Schreibschutz

Dateien in diesem Ordner duerfen vom Agenten nicht veraendert werden,
sofern dies nicht ausdruecklich beauftragt wurde.
"@
}
else {
    Write-Host "File exists, preserving: $UiUxReadme"
}

# ---------------------------------------------------------------------
# mxagile-project.yaml (project config — created with defaults if absent)
# ---------------------------------------------------------------------

$ProjectConfig = Join-Path $ProjectRoot "mxagile-project.yaml"
if (-not (Test-Path -LiteralPath $ProjectConfig -PathType Leaf)) {
    Write-Host "Creating default project configuration: $ProjectConfig"
    Set-Content -LiteralPath $ProjectConfig -Encoding UTF8 -Value @"
# MxAgile Project Configuration
# Schema: .mxagile/schemas/mxagile-project.schema.json
#
# Agents read this file to determine UI-driven mode, source authority, and fidelity.
# If this file is absent all defaults apply and existing MxAgile behavior is preserved.

development:
  # Set to true to enable the Mockup-Driven UI Contract:
  #   - Discovery must find and process all HTML mockups in input-resources/ui-ux/
  #   - Implementation follows UI inventory as a binding contract
  #   - Verification enforces configured fidelity
  ui_driven: false

source_authority:
  # Per-concern source authority. Resolves each concern independently.
  # A source does NOT globally override another source.
  ui_visual: mockup          # visual appearance and layout
  ui_interaction: mockup     # interaction behavior and state transitions
  navigation: mockup         # navigation flows between pages
  business_logic: requirements   # business rules, mandatory fields, calculations
  data_rules: requirements       # data types, constraints, validation rules

ui:
  # standard: structural field/button presence check
  # high:     adds semantic layout, grouping, ordering, navigation, interaction, hierarchy check
  fidelity: standard
"@
}
else {
    Write-Host "File exists, preserving: $ProjectConfig"
}