<#
.SYNOPSIS
Reports whether Studio Pro currently has THIS project open — read-only, no side effects.

.DESCRIPTION
Detects a running `studiopro.exe` process whose command line references the given
.mpr file. Does not start, stop, or touch Studio Pro or the project in any way.

Use this before deciding whether to run `open-studio-pro.ps1` (which fails if the
project is already open) — an agent can check autonomously instead of asking the
developer whether Studio Pro is open.

.PARAMETER ProjectPath
Path to the .mpr file. Defaults to the sole .mpr file in the repository root.

.PARAMETER Json
Emit a single-line JSON object instead of human-readable text.

.OUTPUTS
Exit code 0  — the project IS open in Studio Pro.
Exit code 1  — the project is NOT open in Studio Pro.
Exit code 2  — the check itself failed (e.g. project file not found).
#>

[CmdletBinding()]
param(
    [string]$ProjectPath,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot

try {
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
} catch {
    if ($Json) {
        [PSCustomObject]@{ isOpen = $null; pid = $null; projectPath = $ProjectPath; error = $_.Exception.Message } |
            ConvertTo-Json -Compress
    } else {
        Write-Error $_.Exception.Message
    }
    exit 2
}

$projectArgument = $ProjectPath.ToLowerInvariant()
$existingProjectProcess = Get-CimInstance Win32_Process -Filter "Name='studiopro.exe'" |
    Where-Object { $_.CommandLine -and $_.CommandLine.ToLowerInvariant().Contains($projectArgument) } |
    Select-Object -First 1

if ($existingProjectProcess) {
    if ($Json) {
        [PSCustomObject]@{
            isOpen      = $true
            pid         = $existingProjectProcess.ProcessId
            projectPath = $ProjectPath
        } | ConvertTo-Json -Compress
    } else {
        Write-Host "Studio Pro has this project open (PID $($existingProjectProcess.ProcessId)): '$ProjectPath'."
    }
    exit 0
}

if ($Json) {
    [PSCustomObject]@{
        isOpen      = $false
        pid         = $null
        projectPath = $ProjectPath
    } | ConvertTo-Json -Compress
} else {
    Write-Host "Studio Pro does not have this project open: '$ProjectPath'."
}
exit 1
