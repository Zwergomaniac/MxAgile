<#
.SYNOPSIS
    Checks if all requirements have corresponding validation evidence.
#>
param ()

Write-Host "🚀 Handing off to Python-based Convergence Engine..."

$PSScriptRoot = Split-Path -Path $MyInvocation.MyCommand.Path -Parent
$PythonScriptPath = Join-Path $PSScriptRoot "converge.py"

# The Python script accepts a path argument.
python $PythonScriptPath --path "."

if ($LASTEXITCODE -ne 0) {
    Write-Error "Python script execution failed."
}