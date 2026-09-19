<#
.SYNOPSIS
    A wrapper to execute the Python-based refinement engine.
#>

Write-Host "🚀 Handing off to Python-based Refinement Engine..."

$PSScriptRoot = Split-Path -Path $MyInvocation.MyCommand.Path -Parent
$PythonScriptPath = Join-Path $PSScriptRoot "refine.py"

# Execute the python script
python $PythonScriptPath .

if ($LASTEXITCODE -ne 0) {
    Write-Error "Python script execution failed."
}
