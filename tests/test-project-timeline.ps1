$ErrorActionPreference = 'Stop'
& python -B -m unittest discover -s $PSScriptRoot -p test_project_timeline.py -v
exit $LASTEXITCODE
