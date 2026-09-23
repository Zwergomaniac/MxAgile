<#
.SYNOPSIS
    Platform Portability Tests

.DESCRIPTION
    Validates that MxAgile setup/install scripts comply with the cross-platform
    portability contract in policies/platform-portability.md.

    Covers: shell shim existence, PS script Windows-specific pattern elimination,
    mxcli platform detection, temp dir handling, path construction, python3 fallback.
#>

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$TestsDir  = $PSScriptRoot
$ScriptDir = Split-Path -Parent $TestsDir
$PassCount   = 0
$FailCount   = 0
$FailDetails = @()

function Assert-True {
    param([string]$TestName, [bool]$Condition, [string]$Message)
    if ($Condition) {
        Write-Host "  PASS: $TestName" -ForegroundColor Green
        $script:PassCount++
    } else {
        Write-Host "  FAIL: $TestName -- $Message" -ForegroundColor Red
        $script:FailCount++
        $script:FailDetails += "[$TestName] $Message"
    }
}
function Assert-FileContains {
    param([string]$TestName, [string]$FilePath, [string]$Pattern)
    $content = Get-Content -LiteralPath $FilePath -Raw -ErrorAction SilentlyContinue
    if ($null -eq $content) { Assert-True $TestName $false "File not found: $FilePath" }
    else { Assert-True $TestName ($content -match $Pattern) "Pattern '$Pattern' not found in $FilePath" }
}
function Assert-FileNotContains {
    param([string]$TestName, [string]$FilePath, [string]$Pattern)
    $content = Get-Content -LiteralPath $FilePath -Raw -ErrorAction SilentlyContinue
    if ($null -eq $content) { Assert-True $TestName $false "File not found: $FilePath" }
    else { Assert-True $TestName ($content -notmatch $Pattern) "Forbidden pattern '$Pattern' found in $FilePath" }
}

$PortabilityPol  = Join-Path $ScriptDir ".mxagile/policies/platform-portability.md"
$SetupPs         = Join-Path $ScriptDir "mxagile-setup.ps1"
$SetupMercedesPs = Join-Path $ScriptDir "mxagile-setup-mercedes.ps1"
$InstallCore     = Join-Path $ScriptDir "scripts/install-core.ps1"
$InstallMxcli    = Join-Path $ScriptDir "scripts/install-mxcli.ps1"
$MxagileInit     = Join-Path $ScriptDir "scripts/mxagile-init.ps1"
$ShellShim       = Join-Path $ScriptDir "install-mxagile.sh"

# ---------------------------------------------------------------------------
# TEST A: Policy document and architecture decision
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST A: Platform portability policy" -ForegroundColor Cyan

Assert-FileContains "A.1 platform-portability.md exists" $PortabilityPol 'Platform Portability'
Assert-FileContains "A.2 policy names PowerShell Core as canonical implementation" $PortabilityPol 'PowerShell Core.*pwsh.*canonical'
Assert-FileContains "A.3 policy prohibits parallel bash/python semantic implementation" $PortabilityPol 'NOT.*parallel.*Bash|Do NOT create a parallel'
Assert-FileContains "A.4 policy documents platform support matrix" $PortabilityPol 'Platform Support Matrix'
Assert-FileContains "A.5 policy documents shell shim contract" $PortabilityPol 'Shell Shim Contract'
Assert-FileContains "A.6 policy documents mxcli binary name pattern" $PortabilityPol 'mxcliName|BinaryName'
Assert-FileContains "A.7 policy documents GetTempPath() for cross-platform temp" $PortabilityPol 'GetTempPath'
Assert-FileContains "A.8 policy identifies multi-level backslash as portability bug" $PortabilityPol 'WRONG on Linux.*Join-Path.*\\\\|backslash in a Join-Path child'

# ---------------------------------------------------------------------------
# TEST B: Shell shim (install-mxagile.sh)
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST B: Shell shim (install-mxagile.sh)" -ForegroundColor Cyan

Assert-True "B.1 install-mxagile.sh exists" (Test-Path -LiteralPath $ShellShim -PathType Leaf) "File missing: $ShellShim"
Assert-FileContains "B.2 shim has bash shebang" $ShellShim '^#!/usr/bin/env bash'
Assert-FileContains "B.3 shim detects pwsh on PATH" $ShellShim 'for candidate in pwsh|command -v'
Assert-FileContains "B.4 shim prints install instructions when pwsh absent" $ShellShim 'snap install powershell|brew install.*powershell'
Assert-FileContains "B.5 shim delegates to mxagile-setup.ps1" $ShellShim 'mxagile-setup\.ps1'
Assert-FileContains "B.6 shim forwards all arguments unchanged" $ShellShim '"?\$@"?'
Assert-FileContains "B.7 shim uses exec for clean process replacement" $ShellShim 'exec.*PS_SETUP|exec.*mxagile-setup'
Assert-FileNotContains "B.8 shim has no MxAgile install logic (no DFC detection)" $ShellShim 'LEGACY_DFC|MXAGILE_PROJECT|lifecycle\.yaml'

# ---------------------------------------------------------------------------
# TEST C: install-mxcli.ps1 — platform detection (CRITICAL)
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST C: install-mxcli.ps1 platform detection" -ForegroundColor Cyan

Assert-FileContains "C.1 install-mxcli.ps1 has platform detection" $InstallMxcli 'RuntimeInformation.*IsOSPlatform|IsOSPlatform.*Windows'
Assert-FileContains "C.2 linux asset name defined" $InstallMxcli 'mxcli-linux-amd64'
Assert-FileContains "C.3 darwin asset name defined" $InstallMxcli 'mxcli-darwin-amd64'
Assert-FileContains "C.4 windows asset name still defined" $InstallMxcli 'mxcli-windows-amd64.exe'
Assert-FileNotContains "C.5 asset name is not hardcoded as Windows-only" $InstallMxcli '^\$AssetName\s*=\s*"mxcli-windows-amd64\.exe"'
Assert-FileContains "C.6 binary name is platform-aware" $InstallMxcli "BinaryName.*mxcli\.exe.*mxcli|mxcli\.exe.*BinaryName"
Assert-FileContains "C.7 target exe uses BinaryName variable" $InstallMxcli '\$TargetExe\s*=\s*Join-Path.*\$BinaryName'
Assert-FileContains "C.8 temp dir uses GetTempPath not env:TEMP" $InstallMxcli 'GetTempPath'
Assert-FileNotContains "C.9 env:TEMP not used directly in install-mxcli.ps1" $InstallMxcli '\$env:TEMP'
Assert-FileContains "C.10 chmod +x applied on non-Windows" $InstallMxcli 'chmod \+x'

# ---------------------------------------------------------------------------
# TEST D: mxagile-setup.ps1 — Windows-specific pattern fixes
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST D: mxagile-setup.ps1 Windows-specific patterns" -ForegroundColor Cyan

Assert-FileContains "D.1 explorer.exe detection guarded by isWindowsPlatform" $SetupPs 'isWindowsPlatform[\s\S]{1,200}explorer'
Assert-FileContains "D.2 RuntimeInformation used for Windows detection" $SetupPs 'RuntimeInformation.*IsOSPlatform'
Assert-FileNotContains "D.3 env:TEMP not used directly in setup script" $SetupPs '\$env:TEMP'
Assert-FileContains "D.4 GetTempPath used for temp dir" $SetupPs 'GetTempPath'
Assert-FileContains "D.5 scripts/install-core.ps1 path uses nested Join-Path" $SetupPs 'Join-Path.*scripts.*install-core|Join-Path \(Join-Path.*scripts\)'

# ---------------------------------------------------------------------------
# TEST G: mxagile-setup-mercedes.ps1 — same portability contract as D
# (was missed in original portability pass — regression coverage for Mercedes entry point)
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST G: mxagile-setup-mercedes.ps1 Windows-specific patterns" -ForegroundColor Cyan

Assert-FileContains "G.1 explorer.exe detection guarded by isWindowsPlatform" $SetupMercedesPs 'isWindowsPlatform[\s\S]{1,200}explorer'
Assert-FileContains "G.2 RuntimeInformation used for Windows detection" $SetupMercedesPs 'RuntimeInformation.*IsOSPlatform'
Assert-FileNotContains "G.3 env:TEMP not used directly in mercedes setup script" $SetupMercedesPs '\$env:TEMP'
Assert-FileContains "G.4 GetTempPath used for temp dir" $SetupMercedesPs 'GetTempPath'
Assert-FileContains "G.5 scripts/install-core.ps1 path uses nested Join-Path" $SetupMercedesPs 'Join-Path.*scripts.*install-core|Join-Path \(Join-Path.*scripts\)'

# ---------------------------------------------------------------------------
# TEST E: install-core.ps1 — mxcli name + path fixes
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST E: install-core.ps1 cross-platform fixes" -ForegroundColor Cyan

Assert-FileContains "E.1 install-core.ps1 has platform detection" $InstallCore 'RuntimeInformation.*IsOSPlatform|isWindowsPlatform'
Assert-FileContains "E.2 mxcli binary name is platform-aware" $InstallCore 'mxcliName.*mxcli\.exe.*mxcli|isWindowsPlatform.*mxcli'
Assert-FileNotContains "E.3 mxcli.exe not hardcoded as join target" $InstallCore 'Join-Path \$ProjectRoot "mxcli\.exe"'
Assert-FileContains "E.4 provenance path uses Path.Combine for cross-platform" $InstallCore 'Path\]::Combine.*mxcli-init'
Assert-FileNotContains "E.5 backslash glob pattern removed from canonical payload copy" $InstallCore '\$\(.*FullName\)\\\\?\*'
Assert-FileContains "E.6 canonical payload copy uses Join-Path glob" $InstallCore 'Join-Path.*FullName.*\*'

# ---------------------------------------------------------------------------
# TEST F: mxagile-init.ps1 — mxcli name + python3 + path fixes
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST F: mxagile-init.ps1 cross-platform fixes" -ForegroundColor Cyan

Assert-FileContains "F.1 mxagile-init.ps1 has platform detection" $MxagileInit 'RuntimeInformation.*IsOSPlatform|isWindowsPlatform'
Assert-FileContains "F.2 mxcliName variable defined for platform-aware binary" $MxagileInit 'mxcliName'
Assert-FileNotContains "F.3 mxcli.exe not hardcoded in path construction" $MxagileInit 'Join-Path \$ProjectRoot "mxcli\.exe"'
Assert-FileContains "F.4 python3 checked before python" $MxagileInit 'python3'
Assert-FileContains "F.5 planning/tasks uses nested Join-Path (not backslash)" $MxagileInit 'Join-Path.*planning.*tasks|Join-Path \(Join-Path.*planning\)'

# ---------------------------------------------------------------------------
$total = $PassCount + $FailCount
Write-Host ""
Write-Host "=" * 60
Write-Host "RESULTS: $PassCount passed, $FailCount failed out of $total tests"
if ($FailCount -gt 0) {
    Write-Host ""
    Write-Host "FAILURES:" -ForegroundColor Red
    $FailDetails | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    exit 1
} else {
    Write-Host "All tests PASSED" -ForegroundColor Green
    exit 0
}
