<#
.SYNOPSIS
Opens the current Mendix project in Studio Pro for required manual model actions.

.DESCRIPTION
Use after a validation result that requires a Studio Pro action, such as CE0066
(Update security). This script only opens the project; it does not modify the model.

Run `scripts/check-studio-pro-status.ps1` first (an agent does this automatically,
without asking the developer) to find out whether the project is already open —
this script refuses to start a second instance for the same project.
#>

[CmdletBinding()]
param(
    [string]$ProjectPath,
    [string]$StudioProPath,
    [switch]$WaitForClose
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot

if ([string]::IsNullOrWhiteSpace($ProjectPath)) {
    $projects = @(Get-ChildItem -Path $projectRoot -File -Filter '*.mpr')
    if ($projects.Count -ne 1) {
        throw "Expected exactly one .mpr file in '$projectRoot'. Pass -ProjectPath explicitly."
    }
    $ProjectPath = $projects[0].FullName
}

if (-not (Test-Path -Path $ProjectPath -PathType Leaf)) {
    throw "Mendix project '$ProjectPath' does not exist."
}
$ProjectPath = [IO.Path]::GetFullPath((Resolve-Path -Path $ProjectPath).Path)
$projectArgument = $ProjectPath.ToLowerInvariant()
$existingProjectProcess = Get-CimInstance Win32_Process -Filter "Name='studiopro.exe'" |
    Where-Object { $_.CommandLine -and $_.CommandLine.ToLowerInvariant().Contains($projectArgument) } |
    Select-Object -First 1
if ($existingProjectProcess) {
    throw "Studio Pro already has this project open (PID $($existingProjectProcess.ProcessId)): '$ProjectPath'. Run scripts/check-studio-pro-status.ps1 first to detect this without starting a second instance."
}

if ([string]::IsNullOrWhiteSpace($StudioProPath)) {
    $installRoot = Join-Path $env:ProgramFiles 'Mendix'
    $settingsPath = Join-Path $projectRoot 'project-settings.user.json'
    $versionMatch = if (Test-Path -Path $settingsPath -PathType Leaf) {
        Select-String -Path $settingsPath -Pattern 'Version=(\d+\.\d+\.\d+)\.0' | Select-Object -First 1
    }

    if ($versionMatch -and $versionMatch.Matches.Count -gt 0) {
        $projectVersion = $versionMatch.Matches[0].Groups[1].Value
        $StudioProPath = Join-Path $installRoot "$projectVersion\modeler\studiopro.exe"
    } else {
        $studioCandidates = @(Get-ChildItem -Path $installRoot -Directory -ErrorAction SilentlyContinue |
            Where-Object { Test-Path (Join-Path $_.FullName 'modeler\studiopro.exe') })
        if ($studioCandidates.Count -ne 1) {
            throw "Could not select the Mendix Studio Pro version for '$ProjectPath'. Pass -StudioProPath explicitly."
        }

        $StudioProPath = Join-Path $studioCandidates[0].FullName 'modeler\studiopro.exe'
    }
}

if (-not (Test-Path -Path $StudioProPath -PathType Leaf)) {
    throw "Studio Pro executable '$StudioProPath' does not exist."
}

$studioProcess = Start-Process -FilePath $StudioProPath -ArgumentList "`"$ProjectPath`"" -PassThru
Write-Host "Opened '$ProjectPath' in Studio Pro (PID $($studioProcess.Id))."

if ($WaitForClose) {
    Write-Host "Waiting for Studio Pro PID $($studioProcess.Id) to close. Other Studio Pro instances are ignored."
    Wait-Process -Id $studioProcess.Id
    Write-Host "Studio Pro PID $($studioProcess.Id) has closed."
}