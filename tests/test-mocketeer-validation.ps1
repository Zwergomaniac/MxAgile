#Requires -Version 7
# MxMocketeer static validation — Tier 0 wrapper
# Delegates to products/MxMocketeer/tests/test-mocketeer-validation.ps1

$productTest = Join-Path $PSScriptRoot '..' 'products' 'MxMocketeer' 'tests' 'test-mocketeer-validation.ps1'
if (-not (Test-Path $productTest)) {
    Write-Error "MxMocketeer validation script not found: $productTest"
    exit 1
}
& $productTest
exit $LASTEXITCODE
