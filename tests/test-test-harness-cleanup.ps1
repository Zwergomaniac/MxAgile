$ErrorActionPreference = 'Stop'
& python -m unittest discover -s $PSScriptRoot -p test_test_harness_cleanup.py
exit $LASTEXITCODE
