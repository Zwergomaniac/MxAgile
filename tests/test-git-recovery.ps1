$ErrorActionPreference = 'Stop'
& python -m unittest discover -s $PSScriptRoot -p test_git_recovery.py
exit $LASTEXITCODE