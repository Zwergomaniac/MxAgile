$ErrorActionPreference = 'Stop'
& python -B -m unittest discover -s $PSScriptRoot -p test_board_smoke.py -v
exit $LASTEXITCODE