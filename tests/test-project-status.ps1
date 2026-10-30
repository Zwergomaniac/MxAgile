$ErrorActionPreference = 'Stop'

$testFile = Join-Path $PSScriptRoot 'test_project_status.py'
& python $testFile
exit $LASTEXITCODE