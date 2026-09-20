[CmdletBinding()]
param (
    [string]$ProjectRoot = (Get-Location).Path,
    [string]$MercedesGitUrl = "https://mercedes-benz.ghe.com/DFC-Applikationsentwicklung/MxAgile-CompanyLayer.git",
    [string]$MercedesRef = "main"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

try {
    $CanonicalInstaller = Join-Path $PSScriptRoot "scripts\install-core.ps1"

    if (-not (Test-Path -LiteralPath $CanonicalInstaller -PathType Leaf)) {
        throw "Canonical installer not found: $CanonicalInstaller"
    }

    & $CanonicalInstaller `
        -ProjectRoot $ProjectRoot `
        -CompanyLayerSource $MercedesGitUrl `
        -CompanyLayerSourceType Git `
        -CompanyLayerRef $MercedesRef

    $exitCode = $LASTEXITCODE
    exit $exitCode
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
