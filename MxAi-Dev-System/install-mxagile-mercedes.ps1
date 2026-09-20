# install-mxagile-mercedes.ps1
param (
    [string]$ProjectRoot = (Get-Location).Path,
    [string]$MercedesGitUrl = "https://mercedes-benz.ghe.com/DFC-Applikationsentwicklung/MxAgile-CompanyLayer.git"
)

# 1. Safety Preflight: .mpr check
$mprFiles = Get-ChildItem -Path $ProjectRoot -Filter *.mpr
if ($mprFiles.Count -eq 0) {
    Write-Error "No .mpr file found in project root."
    exit 1
}
if ($mprFiles.Count -gt 1) {
    Write-Error "Multiple .mpr files found."
    exit 1
}

# 2. Invoke core installer (the one in the root)
& "$PSScriptRoot\install-mxagile.ps1" -ProjectRoot $ProjectRoot

# 3. Resolve/Install Mercedes Layer
& "$PSScriptRoot\scripts\fetch-layer.ps1" -LayerUrl $MercedesGitUrl -TargetDir (Join-Path $ProjectRoot ".mxagile/layers/mercedes-benz")

Write-Host "Mercedes-Benz installation complete."
