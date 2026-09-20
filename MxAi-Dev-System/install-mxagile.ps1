[CmdletBinding()]
param (
    [string]$ProjectRoot = (Get-Location).Path
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

try {
    $CanonicalInstaller = Join-Path $PSScriptRoot "scripts\install-core.ps1"

    if (-not (Test-Path -LiteralPath $CanonicalInstaller -PathType Leaf)) {
        throw "Canonical installer not found: $CanonicalInstaller"
    }

    & $CanonicalInstaller -ProjectRoot $ProjectRoot
    $exitCode = $LASTEXITCODE
    exit $exitCode
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
