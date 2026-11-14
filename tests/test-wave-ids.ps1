$ErrorActionPreference = 'Stop'
$python = Get-Command python -ErrorAction SilentlyContinue
if (-not $python) { $python = Get-Command python3 -ErrorAction Stop }
& $python.Source -B -m unittest discover -s $PSScriptRoot -p test_wave_ids.py
if ($LASTEXITCODE -ne 0) { throw 'Wave identity regression failed.' }
