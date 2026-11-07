<#
.SYNOPSIS
Generates the read-only MxAgile Security Projection (security-matrix.yaml) from the Mendix model.

.DESCRIPTION
Thin entry point for scripts/security_projection.py (distributed as .mxagile/tools/security_projection.py).
The Mendix model is the authority; the output is generated evidence and must not be edited by hand.
Uses the project-local mxcli.exe (MxAgile Core owned) unless -Mxcli is given. Never falls back silently
to another mxcli. Exit codes: 0 complete, 3 written but INCOMPLETE, 1 schema error, 2 tooling/input error.
Does not start Studio Pro or the runtime; opens the .mpr read-only through mxcli.

.PARAMETER Project   Path to the .mpr (default: the single *.mpr in the current directory).
.PARAMETER Out       Output file (default: <project dir>/.mxagile/state/security/security-matrix.yaml).
.PARAMETER Mxcli     Explicit mxcli executable.
.PARAMETER Force     Rewrite even when the semantic fingerprint is unchanged.
.PARAMETER ReasonType/ReasonRef/ReasonText  Optional explicit change reason (requirement|task|decision|finding). Never inferred.
#>
[CmdletBinding()]
param(
    [string]$Project,
    [string]$Out,
    [string]$Mxcli,
    [switch]$Force,
    [ValidateSet('requirement', 'task', 'decision', 'finding', 'unknown')]
    [string]$ReasonType,
    [string]$ReasonRef,
    [string]$ReasonText
)
$ErrorActionPreference = 'Stop'

$tool = Join-Path $PSScriptRoot 'security_projection.py'
if (-not (Test-Path -LiteralPath $tool)) { $tool = Join-Path $PSScriptRoot '../.mxagile/tools/security_projection.py' }
if (-not (Test-Path -LiteralPath $tool)) { Write-Error 'security_projection.py not found next to this script or in .mxagile/tools.'; exit 2 }

if (-not $Project) {
    $found = @(Get-ChildItem -LiteralPath (Get-Location) -Filter '*.mpr' -File)
    if ($found.Count -ne 1) { Write-Error "Specify -Project: found $($found.Count) .mpr files in the current directory."; exit 2 }
    $Project = $found[0].FullName
}
$Project = (Resolve-Path -LiteralPath $Project).Path
if (-not $Mxcli) {
    $local = Join-Path (Split-Path -Parent $Project) 'mxcli.exe'
    if (Test-Path -LiteralPath $local) { $Mxcli = $local }
    else { Write-Error "Project-local mxcli.exe not found next to $Project. Install it via the MxAgile mxcli installer or pass -Mxcli explicitly."; exit 2 }
}
$python = (Get-Command python -ErrorAction SilentlyContinue)
if (-not $python) { Write-Error 'python not found on PATH.'; exit 2 }

$argsList = @($tool, 'generate', '--project', $Project, '--mxcli', $Mxcli)
if ($Out) { $argsList += @('--out', $Out) }
if ($Force) { $argsList += '--force' }
if ($ReasonType) { $argsList += @('--reason-type', $ReasonType) }
if ($ReasonRef) { $argsList += @('--reason-ref', $ReasonRef) }
if ($ReasonText) { $argsList += @('--reason-text', $ReasonText) }
& $python.Source @argsList
exit $LASTEXITCODE
