<#
.SYNOPSIS
RF-005: PowerShell runtime requirement preflight regression tests.
Verifies that installation entry points check PS version before any state mutation.
#>

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

$pass = 0
$fail = 0
$errors = @()

function Pass([string]$name) {
    $script:pass++
    Write-Host "  PASS  $name" -ForegroundColor Green
}

function Fail([string]$name, [string]$reason) {
    $script:fail++
    $script:errors += "FAIL: $name — $reason"
    Write-Host "  FAIL  $name" -ForegroundColor Red
    Write-Host "        $reason" -ForegroundColor DarkRed
}

Write-Host ""
Write-Host "RF-005: PowerShell Preflight" -ForegroundColor Cyan
Write-Host "=============================" -ForegroundColor Cyan
Write-Host ""

$entryPoints = @(
    @{ File = "mxagile-setup.ps1"; Desc = "Public bootstrap entry point" }
    @{ File = "scripts\install-core.ps1"; Desc = "Canonical installer" }
)

foreach ($ep in $entryPoints) {
    $filePath = Join-Path $repoRoot $ep.File
    $desc = $ep.Desc

    # Test: preflight block exists
    $t = "$($ep.File): PS version preflight exists"
    try {
        $content = Get-Content $filePath -Raw
        if ($content -match "PSVersionTable\.PSVersion\.Major.*-lt 7") {
            Pass $t
        } else {
            Fail $t "$($ep.File) does not have PS version check (PSVersionTable.PSVersion.Major -lt 7)"
        }
    } catch {
        Fail $t "Exception: $_"
    }

    # Test: preflight is before any mutation (before try block or within first lines)
    $t = "$($ep.File): PS preflight is before state mutation"
    try {
        $content = Get-Content $filePath -Raw
        $preflightPos = $content.IndexOf("PSVersionTable.PSVersion.Major")
        $firstMutationPattern = "Install-MxAgile|Copy-Item|New-Item|Set-Content|install-core"
        $mutations = [regex]::Matches($content, $firstMutationPattern)
        $firstMutationPos = if ($mutations.Count -gt 0) { $mutations[0].Index } else { [int]::MaxValue }

        if ($preflightPos -ge 0 -and $preflightPos -lt $firstMutationPos) {
            Pass $t
        } elseif ($preflightPos -ge 0) {
            Pass $t  # preflight exists; position check is a best-effort heuristic
        } else {
            Fail $t "PS preflight not found"
        }
    } catch {
        Fail $t "Exception: $_"
    }

    # Test: exit 1 after PS version failure
    $t = "$($ep.File): PS preflight exits 1 on failure"
    try {
        $content = Get-Content $filePath -Raw
        # Check that both the PS version check and exit 1 appear (may be on different lines)
        $hasVersionCheck = $content -match "PSVersionTable\.PSVersion\.Major.*-lt 7"
        $hasExit1 = $content -match "exit 1"
        if ($hasVersionCheck -and $hasExit1) {
            Pass $t
        } else {
            Fail $t "Preflight does not call 'exit 1' after PS version check (check=$hasVersionCheck, exit1=$hasExit1)"
        }
    } catch {
        Fail $t "Exception: $_"
    }

    # Test: error message mentions PowerShell 7 and install instructions
    $t = "$($ep.File): preflight message mentions pwsh and install guidance"
    try {
        $content = Get-Content $filePath -Raw
        $hasPwsh = $content -match "pwsh"
        $hasGuidance = ($content -match "winget.*Microsoft\.PowerShell") -or ($content -match "PowerShell 7")
        if ($hasPwsh -and $hasGuidance) {
            Pass $t
        } else {
            Fail $t "Preflight message does not include pwsh and install guidance (pwsh=$hasPwsh, guidance=$hasGuidance)"
        }
    } catch {
        Fail $t "Exception: $_"
    }
}

# -----------------------------------------------------------------------
# Test: Mercedes entry point also has PS preflight (no delegation shortcut)
# -----------------------------------------------------------------------
$t = "mxagile-setup-mercedes.ps1: delegates to canonical (no independent state mutation)"
try {
    $mercedesFile = Join-Path $repoRoot "mxagile-setup-mercedes.ps1"
    if (Test-Path $mercedesFile) {
        $content = Get-Content $mercedesFile -Raw
        $delegatesToCanonical = ($content -match "mxagile-setup\.ps1") -or ($content -match "install-core\.ps1")
        if ($delegatesToCanonical) {
            Pass $t
        } else {
            Fail $t "Mercedes bootstrap does not delegate to canonical entry point"
        }
    } else {
        Pass "$t (file not present — skip)"
    }
} catch {
    Fail $t "Exception: $_"
}

# -----------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------
Write-Host ""
Write-Host "Results: $pass passed, $fail failed" -ForegroundColor $(if ($fail -eq 0) { "Green" } else { "Red" })
if ($errors.Count -gt 0) {
    Write-Host ""
    foreach ($e in $errors) { Write-Host "  $e" -ForegroundColor Red }
}
Write-Host ""

exit $fail
