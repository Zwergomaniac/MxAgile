<#
.SYNOPSIS
    Checks a single .yml file against the project's quality checklist.
.PARAMETER FilePath
    The path to the .yml file to check.
#>
param (
    [Parameter(Mandatory=$true)]
    [string]$FilePath
)

Write-Host "🚀 Handing off to Python-based Quality Gate Engine..."

$PSScriptRoot = Split-Path -Path $MyInvocation.MyCommand.Path -Parent
$PythonScriptPath = Join-Path $PSScriptRoot "check-quality.py"

# The Python script accepts the file to check and an optional root path.
# The Python script accepts the file to check and the absolute project root path.
$ProjectRoot = Join-Path $PSScriptRoot ".."
python $PythonScriptPath $FilePath --path $ProjectRoot

if ($LASTEXITCODE -ne 0) {
    Write-Error "Quality check failed."
    exit 1
} else {
    Write-Host "Quality check passed."
}
