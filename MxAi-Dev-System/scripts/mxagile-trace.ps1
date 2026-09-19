<#
.SYNOPSIS
    A wrapper to execute the Python-based traceability query engine.
.PARAMETER Id
    The ID of the artifact to trace (e.g., 'SP-001').
#>
param (
    [Parameter(Mandatory=$true)]
    [string]$Id
)

Write-Host "🚀 Handing off to Python-based Traceability Engine..."

$PSScriptRoot = Split-Path -Path $MyInvocation.MyCommand.Path -Parent
$PythonScriptPath = Join-Path $PSScriptRoot "trace.py"

# The Python script accepts the ID and a path argument.
python $PythonScriptPath $Id --path "."

if ($LASTEXITCODE -ne 0) {
    Write-Error "Python script execution failed."
}
