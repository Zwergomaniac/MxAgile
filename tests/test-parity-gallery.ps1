$ErrorActionPreference = 'Stop'
& python -m unittest discover -s $PSScriptRoot -p test_parity_gallery.py
exit $LASTEXITCODE