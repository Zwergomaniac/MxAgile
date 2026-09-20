$ErrorActionPreference = 'Stop'
$mockDir = Join-Path $PSScriptRoot "mock-mendix-project"
$projectFile = Join-Path $mockDir "project.mpr"
$mxagileDir = Join-Path $mockDir ".mxagile"
$script = Join-Path (Split-Path $PSScriptRoot -Parent) "scripts\mxagile-adopt.ps1"

# 1. Setup
if (Test-Path $mockDir) { Remove-Item -LiteralPath $mockDir -Recurse -Force }
New-Item -ItemType Directory -Path $mockDir -Force
New-Item -ItemType File -Path $projectFile -Force
Set-Content -Path $projectFile -Value "dummy"

# 2. Run
Write-Host "Running adoption script first time..."
& $script -TargetDir $mockDir

# 3 & 4. Verify
if (-not (Test-Path $mxagileDir)) { Write-Host "FAIL: .mxagile not created"; exit 1 }
if (-not (Test-Path $projectFile)) { Write-Host "FAIL: project.mpr deleted"; exit 1 }

# 5. Idempotency
Write-Host "Running adoption script second time..."
$output = & $script -TargetDir $mockDir *>&1
# Strip ANSI escape codes before matching
$plainOutput = ($output | Out-String) -replace "\e\[[0-9;]*m", ""
if (-not ($plainOutput -match "Skipping .mxagile")) { Write-Host "FAIL: Did not skip existing .mxagile directory"; exit 1 }

# 6. Clean
Remove-Item -LiteralPath $mockDir -Recurse -Force

# 7. PASS
Write-Host "PASS"
