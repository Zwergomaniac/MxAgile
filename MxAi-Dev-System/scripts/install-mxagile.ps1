# scripts/install-mxagile.ps1

param (
    [string]$ProjectRoot = (Get-Location).Path
)

# 1. Safety Preflight: .mpr check
$mprFiles = Get-ChildItem -Path $ProjectRoot -Filter *.mpr
if ($mprFiles.Count -eq 0) {
    Write-Error "No .mpr file found in project root."
    exit 1
}
if ($mprFiles.Count -gt 1) {
    Write-Error "Multiple .mpr files found. Please ensure only one .mpr file exists."
    exit 1
}
Write-Host "Safety Preflight passed: Single .mpr file detected."

# 2. Call existing workflows
Write-Host "Initializing MxAgile framework..."
& (Join-Path $PSScriptRoot "mxagile-init.ps1") -ProjectRoot $ProjectRoot

Write-Host "Setting up Agent System..."
& (Join-Path $PSScriptRoot "setup-agent-system.ps1") -ProjectRoot $ProjectRoot

Write-Host "Generic MxAgile installation complete."
