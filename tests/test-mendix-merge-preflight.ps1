$ErrorActionPreference = 'Stop'
& python -m unittest discover -s $PSScriptRoot -p test_mendix_merge_preflight.py
exit $LASTEXITCODE
