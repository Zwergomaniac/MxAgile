$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

foreach ($pattern in @('test_external_change_reconciliation.py', 'test_board_performance.py', 'test_board_http.py')) {
    & python -m unittest discover -s $PSScriptRoot -p $pattern
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

exit 0