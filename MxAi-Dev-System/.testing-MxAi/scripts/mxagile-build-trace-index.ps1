<#
.SYNOPSIS
    A wrapper to execute the Python-based trace indexer.
#>

Write-Host "🚀 Handing off to Python-based Trace Indexer..."

$PSScriptRoot = Split-Path -Path $MyInvocation.MyCommand.Path -Parent
$PythonScriptPath = Join-Path $PSScriptRoot "build_trace_index.py"

# Execute the python script
python $PythonScriptPath .

if ($LASTEXITCODE -ne 0) {
    Write-Error "Python script execution failed."
}