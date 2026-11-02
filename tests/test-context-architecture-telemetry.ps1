$ErrorActionPreference = 'Stop'

$testFile = Join-Path $PSScriptRoot 'test_context_architecture_telemetry.py'
& python $testFile
exit $LASTEXITCODE