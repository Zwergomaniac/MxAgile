$ErrorActionPreference = 'Stop'
& python -m unittest discover -s $PSScriptRoot -p test_test_impact.py
exit $LASTEXITCODE