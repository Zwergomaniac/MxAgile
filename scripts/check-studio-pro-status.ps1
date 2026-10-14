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
Exit code 2  — the check itself failed (e.g. project file not found, timeout, permission error).

Exit code 2 with error containing "TIMEOUT" means detection did not complete within
-TimeoutSeconds. The agent MUST treat this as AMBIGUOUS-SP-STATE (= UNKNOWN), NOT as
CLOSED-AUTONOM. Absence of a detection result is not proof that Studio Pro is absent.
#>

[CmdletBinding()]
param(
    [string]$ProjectPath,
    [switch]$Json,
    [int]$TimeoutSeconds = 10
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
        [PSCustomObject]@{
            isOpen             = $null
            pid                = $null
            projectPath        = $ProjectPath
            anyStudioProRunning = $null
            otherProjectPids   = @()
            error              = $_.Exception.Message
        } | ConvertTo-Json -Compress
    } else {
        Write-Error $_.Exception.Message
    }
    exit 2
}

$projectArgument = $ProjectPath.ToLowerInvariant()

# Bounded detection: run CIM query in a background job so we can enforce a timeout.
# A slow WMI/CIM subsystem must not hang the agent indefinitely.
$detectionJob = Start-Job -ScriptBlock {
    param($filter)
    @(Get-CimInstance Win32_Process -Filter $filter -ErrorAction SilentlyContinue)
} -ArgumentList "Name='studiopro.exe'"

$completed = Wait-Job -Job $detectionJob -Timeout $TimeoutSeconds
if (-not $completed) {
    Remove-Job -Job $detectionJob -Force -ErrorAction SilentlyContinue
    $timeoutMsg = "Studio Pro detection timed out after ${TimeoutSeconds}s. Result is UNKNOWN (AMBIGUOUS-SP-STATE), NOT CLOSED-AUTONOM."
    if ($Json) {
        [PSCustomObject]@{
            isOpen              = $null
            pid                 = $null
            projectPath         = $ProjectPath
            anyStudioProRunning = $null
            otherProjectPids    = @()
            error               = "TIMEOUT: $timeoutMsg"
            detection_state     = "UNKNOWN"
        } | ConvertTo-Json -Compress
    } else {
        Write-Error $timeoutMsg
    }
    exit 2
}

$allStudioProProcesses = @(Receive-Job -Job $detectionJob -ErrorAction SilentlyContinue)
Remove-Job -Job $detectionJob -Force -ErrorAction SilentlyContinue

$existingProjectProcess = $allStudioProProcesses |
    Where-Object { $_.CommandLine -and $_.CommandLine.ToLowerInvariant().Contains($projectArgument) } |
    Select-Object -First 1
$otherProcesses = @($allStudioProProcesses |
    Where-Object { $_ -ne $existingProjectProcess })

if ($existingProjectProcess) {
    if ($Json) {
        [PSCustomObject]@{
            isOpen             = $true
            pid                = $existingProjectProcess.ProcessId
            projectPath        = $ProjectPath
            anyStudioProRunning = $true
            otherProjectPids   = @($otherProcesses | ForEach-Object { $_.ProcessId })
        } | ConvertTo-Json -Compress
    } else {
        Write-Host "Studio Pro has this project open (PID $($existingProjectProcess.ProcessId)): '$ProjectPath'."
    }
    exit 0
}

if ($Json) {
    [PSCustomObject]@{
        isOpen             = $false
        pid                = $null
        projectPath        = $ProjectPath
        anyStudioProRunning = ($allStudioProProcesses.Count -gt 0)
        otherProjectPids   = @($allStudioProProcesses | ForEach-Object { $_.ProcessId })
    } | ConvertTo-Json -Compress
} else {
    if ($allStudioProProcesses.Count -gt 0) {
        Write-Host "Studio Pro does not have this project open, but is running for another project: '$ProjectPath'."
    } else {
        Write-Host "Studio Pro does not have this project open: '$ProjectPath'."
    }
}
exit 1
