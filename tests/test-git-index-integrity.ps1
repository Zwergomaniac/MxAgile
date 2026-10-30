$ErrorActionPreference = 'Stop'
& python -m unittest discover -s $PSScriptRoot -p test_git_index_integrity.py
exit $LASTEXITCODE