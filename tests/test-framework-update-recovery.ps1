$ErrorActionPreference = 'Stop'
$previous = $env:PYTHONDONTWRITEBYTECODE
try {
    $env:PYTHONDONTWRITEBYTECODE = '1'
    & python -B -m unittest discover -s $PSScriptRoot -p test_framework_update_recovery.py
    exit $LASTEXITCODE
} finally {
    $env:PYTHONDONTWRITEBYTECODE = $previous
}
