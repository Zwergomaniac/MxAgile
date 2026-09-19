<#
.SYNOPSIS
    A wrapper to execute the Python-based analysis engine.
#>

Write-Host "🚀 Handing off to Python-based Analysis Engine..."

$PSScriptRoot = Split-Path -Path $MyInvocation.MyCommand.Path -Parent
$PythonScriptPath = Join-Path $PSScriptRoot "analyze.py"

# The Python script accepts a path argument. We pass the current directory.
python $PythonScriptPath --path "."

if ($LASTEXITCODE -ne 0) {
    Write-Error "Python script execution failed."
}
