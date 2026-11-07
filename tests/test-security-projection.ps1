$ErrorActionPreference = 'Stop'
& python -m unittest discover -s $PSScriptRoot -p test_security_projection.py
exit $LASTEXITCODE
