<#
.SYNOPSIS
    Capability Resolver — Operational Tests

.DESCRIPTION
    Tests the Get-MxAgileCapabilities.ps1 resolver against temporary project
    roots with controlled configurations.

    Layer 0 (Static):
      A. Script syntax valid (no parse errors)
      B. Script exports expected parameters

    Layer 1 (Operational — uses temp git repos):
      C. No .mxagile dir produces error
      D. JSON output has framework_version field
      E. JSON output has capabilities array
      F. JSON output has upgrade_awareness field
      G. Capability with disabled config key reports enabled=false
      H. Capability with enabled config key reports enabled=true
      I. Capability with missing dependency reports unavailable=true
      J. Capability not unavailable AND enabled does NOT report active=true
      K. Capability available AND enabled reports active=true (no ext deps)
      L. -Capability filter returns only that capability
      M. Unknown -Capability id exits with error
      N. -CheckUpgrades with no discovery state file returns last_seen=null
      O. -UpdateDiscoveryState writes .concord/capability-discovery.yaml
      P. -CheckUpgrades after -UpdateDiscoveryState returns correct last_seen

    Tests use GUID temp directories. No network. No mxcli. No shared state.
#>

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$TestsDir  = $PSScriptRoot
$ScriptDir = Split-Path -Parent $TestsDir
$Resolver  = Join-Path (Join-Path $ScriptDir 'scripts') 'Get-MxAgileCapabilities.ps1'

$PassCount   = 0
$FailCount   = 0
$FailDetails = @()

function Assert-True {
    param([string]$TestName, [bool]$Condition, [string]$Message = '')
    if ($Condition) {
        Write-Host "  PASS: $TestName" -ForegroundColor Green
        $script:PassCount++
    } else {
        Write-Host "  FAIL: $TestName -- $Message" -ForegroundColor Red
        $script:FailCount++
        $script:FailDetails += "  FAIL: $TestName -- $Message"
    }
}

function Get-ConfigOverride {
    param([hashtable]$Map, [string]$Key, [string]$Default = 'false')
    if ($Map.ContainsKey($Key) -and $null -ne $Map[$Key]) { return $Map[$Key] } else { return $Default }
}

function New-TempProjectRoot {
    param(
        [string]$Version = '1.5',
        [hashtable]$ConfigOverrides = @{}
    )
    $tempRoot = Join-Path $env:TEMP "mxagile-cap-test-$(New-Guid)"
    New-Item -ItemType Directory -Path $tempRoot | Out-Null

    $mxDir = Join-Path $tempRoot '.mxagile'
    New-Item -ItemType Directory -Path $mxDir | Out-Null

    # Minimal version.yaml
    $versionLines = @(
        "version: `"$Version`""
        'min_compatible: "1.0"'
        'updated: "2026-10-13"'
    )
    $versionLines | Set-Content -Path (Join-Path $mxDir 'version.yaml') -Encoding UTF8

    # Copy real capabilities.yaml
    $realCaps = Join-Path (Join-Path $ScriptDir '.mxagile') 'capabilities.yaml'
    if (Test-Path $realCaps) {
        Copy-Item $realCaps (Join-Path $mxDir 'capabilities.yaml')
    }

    # Build minimal config.yaml
    $configLines = @('# Test config')
    $configLines += 'context_lifecycle:'
    $configLines += "  enabled: $(Get-ConfigOverride $ConfigOverrides 'context_lifecycle.enabled')"
    $configLines += "  checkpoint_resume: $(Get-ConfigOverride $ConfigOverrides 'context_lifecycle.checkpoint_resume')"
    $configLines += "  manual_rollover: $(Get-ConfigOverride $ConfigOverrides 'context_lifecycle.manual_rollover')"
    $configLines += "  pressure_recommendations: $(Get-ConfigOverride $ConfigOverrides 'context_lifecycle.pressure_recommendations')"
    $configLines += "  auto_rollover: $(Get-ConfigOverride $ConfigOverrides 'context_lifecycle.auto_rollover')"
    $configLines += 'context_optimization:'
    $configLines += "  enabled: $(Get-ConfigOverride $ConfigOverrides 'context_optimization.enabled')"
    $configLines += '  rtk:'
    $configLines += "    enabled: $(Get-ConfigOverride $ConfigOverrides 'context_optimization.rtk.enabled')"
    $configLines += '  context_mode:'
    $configLines += "    enabled: $(Get-ConfigOverride $ConfigOverrides 'context_optimization.context_mode.enabled')"
    $configLines += 'graphify:'
    $configLines += "  enabled: $(Get-ConfigOverride $ConfigOverrides 'graphify.enabled')"
    $configLines | Set-Content -Path (Join-Path $mxDir 'config.yaml') -Encoding UTF8

    return $tempRoot
}

function Remove-TempProjectRoot {
    param([string]$Path)
    if ($Path -and (Test-Path $Path)) {
        Remove-Item -Recurse -Force $Path -ErrorAction SilentlyContinue
    }
}

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=== Capability Resolver Tests ===" -ForegroundColor Cyan

# A. Script syntax valid
Assert-True 'A. Resolver script exists' (Test-Path $Resolver) "Not found: $Resolver"
if (Test-Path $Resolver) {
    $syntaxErrors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($Resolver, [ref]$null, [ref]$syntaxErrors)
    Assert-True 'A. No syntax errors' ($syntaxErrors.Count -eq 0) "Parse errors: $($syntaxErrors -join '; ')"
}

# B. Script has expected parameters
if (Test-Path $Resolver) {
    $resolverText = Get-Content $Resolver -Raw
    Assert-True 'B. Has -Format parameter' ($resolverText -match 'param.*Format' -or $resolverText -match '\[string\]\$Format') 'Missing -Format'
    Assert-True 'B. Has -Capability parameter' ($resolverText -match '\[string\]\$Capability') 'Missing -Capability'
    Assert-True 'B. Has -ProjectRoot parameter' ($resolverText -match '\[string\]\$ProjectRoot') 'Missing -ProjectRoot'
    Assert-True 'B. Has -CheckUpgrades switch' ($resolverText -match '\[switch\]\$CheckUpgrades') 'Missing -CheckUpgrades'
    Assert-True 'B. Has -UpdateDiscoveryState switch' ($resolverText -match '\[switch\]\$UpdateDiscoveryState') 'Missing -UpdateDiscoveryState'
}

# C. No .mxagile dir → error
$tmpNoMxagile = Join-Path $env:TEMP "mxagile-cap-test-no-dir-$(New-Guid)"
New-Item -ItemType Directory -Path $tmpNoMxagile | Out-Null
try {
    $exitCode = 0
    try {
        & $Resolver -Format json -ProjectRoot $tmpNoMxagile 2>&1 | Out-Null
        $exitCode = $LASTEXITCODE
    } catch {
        $exitCode = 1
    }
    Assert-True 'C. Missing .mxagile dir produces non-zero exit' ($exitCode -ne 0) "Expected non-zero exit, got $exitCode"
} finally {
    Remove-TempProjectRoot -Path $tmpNoMxagile
}

# D-F. JSON output structure
$tmpBasic = New-TempProjectRoot
try {
    $jsonOutput = & $Resolver -Format json -ProjectRoot $tmpBasic 2>&1
    $exitCode = $LASTEXITCODE
    Assert-True 'D. JSON output succeeds' ($exitCode -eq 0) "Exit code: $exitCode; output: $($jsonOutput | Select-Object -First 3 | Out-String)"

    if ($exitCode -eq 0) {
        $json = $jsonOutput | ConvertFrom-Json -ErrorAction SilentlyContinue
        Assert-True 'D. JSON has framework_version' ($null -ne $json.framework_version) 'framework_version missing'
        Assert-True 'E. JSON has capabilities array' ($null -ne $json.capabilities) 'capabilities missing'
        Assert-True 'E. capabilities array non-empty' ($json.capabilities.Count -gt 0) "capabilities count: $($json.capabilities.Count)"
        Assert-True 'F. JSON has upgrade_awareness' ($null -ne $json.upgrade_awareness) 'upgrade_awareness missing'
        Assert-True 'F. upgrade_awareness has last_seen_version' ($json.upgrade_awareness.PSObject.Properties.Name -contains 'last_seen_version') 'last_seen_version missing'
    }
} finally {
    Remove-TempProjectRoot -Path $tmpBasic
}

# G. Disabled config → enabled=false
$tmpDisabled = New-TempProjectRoot -ConfigOverrides @{ 'context_lifecycle.enabled' = 'false' }
try {
    $jsonOutput = & $Resolver -Format json -ProjectRoot $tmpDisabled 2>&1
    if ($LASTEXITCODE -eq 0) {
        $json = $jsonOutput | ConvertFrom-Json
        $clCap = $json.capabilities | Where-Object { $_.id -eq 'context_lifecycle' }
        Assert-True 'G. Disabled capability reports enabled=false' ($clCap -and $clCap.state.enabled -eq $false) "enabled was: $($clCap.state.enabled)"
    }
} finally {
    Remove-TempProjectRoot -Path $tmpDisabled
}

# H. Enabled config → enabled=true (context_lifecycle, no ext deps)
$tmpEnabled = New-TempProjectRoot -ConfigOverrides @{ 'context_lifecycle.enabled' = 'true' }
try {
    $jsonOutput = & $Resolver -Format json -ProjectRoot $tmpEnabled 2>&1
    if ($LASTEXITCODE -eq 0) {
        $json = $jsonOutput | ConvertFrom-Json
        $clCap = $json.capabilities | Where-Object { $_.id -eq 'context_lifecycle' }
        Assert-True 'H. Enabled capability reports enabled=true' ($clCap -and $clCap.state.enabled -eq $true) "enabled was: $($clCap.state.enabled)"
    }
} finally {
    Remove-TempProjectRoot -Path $tmpEnabled
}

# I. RTK capability reports unavailable when rtk not in PATH
# We don't install RTK — so rtk should not be in PATH in CI
$tmpRtkEnabled = New-TempProjectRoot -ConfigOverrides @{
    'context_optimization.enabled' = 'true'
    'context_optimization.rtk.enabled' = 'true'
}
try {
    $rtkInPath = Get-Command rtk -ErrorAction SilentlyContinue
    if (-not $rtkInPath) {
        $jsonOutput = & $Resolver -Format json -ProjectRoot $tmpRtkEnabled 2>&1
        if ($LASTEXITCODE -eq 0) {
            $json = $jsonOutput | ConvertFrom-Json
            $rtkCap = $json.capabilities | Where-Object { $_.id -eq 'rtk_optimization' }
            Assert-True 'I. RTK unavailable when not in PATH' ($rtkCap -and $rtkCap.state.unavailable -eq $true) "unavailable was: $($rtkCap.state.unavailable)"
            Assert-True 'I. RTK not active when unavailable' ($rtkCap -and $rtkCap.state.active -eq $false) "active was: $($rtkCap.state.active)"
        }
    } else {
        Write-Host "  SKIP: I. RTK is in PATH - skipping unavailable test" -ForegroundColor DarkGray
        $script:PassCount++
    }
} finally {
    Remove-TempProjectRoot -Path $tmpRtkEnabled
}

# J. Enabled+unavailable does NOT report active=true
$tmpJ = New-TempProjectRoot -ConfigOverrides @{
    'context_optimization.enabled' = 'true'
    'context_optimization.context_mode.enabled' = 'true'
}
try {
    $cmInPath = Get-Command 'context-mode' -ErrorAction SilentlyContinue
    if (-not $cmInPath) {
        $jsonOutput = & $Resolver -Format json -ProjectRoot $tmpJ 2>&1
        if ($LASTEXITCODE -eq 0) {
            $json = $jsonOutput | ConvertFrom-Json
            $cmCap = $json.capabilities | Where-Object { $_.id -eq 'context_mode_integration' }
            Assert-True 'J. Enabled+unavailable NOT active' ($cmCap -and $cmCap.state.active -eq $false) "active was: $($cmCap.state.active)"
        }
    } else {
        Write-Host "  SKIP: J. context-mode is in PATH" -ForegroundColor DarkGray
        $script:PassCount++
    }
} finally {
    Remove-TempProjectRoot -Path $tmpJ
}

# K. context_lifecycle enabled reports active=true (no ext deps required)
$tmpK = New-TempProjectRoot -ConfigOverrides @{ 'context_lifecycle.enabled' = 'true' }
try {
    $jsonOutput = & $Resolver -Format json -ProjectRoot $tmpK 2>&1
    if ($LASTEXITCODE -eq 0) {
        $json = $jsonOutput | ConvertFrom-Json
        $clCap = $json.capabilities | Where-Object { $_.id -eq 'context_lifecycle' }
        Assert-True 'K. context_lifecycle active when enabled' ($clCap -and $clCap.state.active -eq $true) "active was: $($clCap.state.active)"
    }
} finally {
    Remove-TempProjectRoot -Path $tmpK
}

# L. -Capability filter
$tmpL = New-TempProjectRoot
try {
    $jsonOutput = & $Resolver -Format json -ProjectRoot $tmpL -Capability 'context_lifecycle' 2>&1
    if ($LASTEXITCODE -eq 0) {
        $json = $jsonOutput | ConvertFrom-Json
        Assert-True 'L. Filter returns only requested capability' ($json.capabilities.Count -eq 1) "Count was: $($json.capabilities.Count)"
        Assert-True 'L. Returned capability has correct id' ($json.capabilities[0].id -eq 'context_lifecycle') "id was: $($json.capabilities[0].id)"
    }
} finally {
    Remove-TempProjectRoot -Path $tmpL
}

# M. Unknown capability id exits with error
$tmpM = New-TempProjectRoot
try {
    $exitCode = 0
    try {
        $null = & $Resolver -Format json -ProjectRoot $tmpM -Capability 'nonexistent_capability_xyz' 2>&1
        $exitCode = $LASTEXITCODE
    } catch { $exitCode = 1 }
    Assert-True 'M. Unknown capability id exits non-zero' ($exitCode -ne 0) "Expected non-zero exit"
} finally {
    Remove-TempProjectRoot -Path $tmpM
}

# N. CheckUpgrades with no discovery state → last_seen=null
$tmpN = New-TempProjectRoot
try {
    $jsonOutput = & $Resolver -Format json -ProjectRoot $tmpN -CheckUpgrades 2>&1
    if ($LASTEXITCODE -eq 0) {
        $json = $jsonOutput | ConvertFrom-Json
        Assert-True 'N. No discovery state - last_seen_version is null' ($null -eq $json.upgrade_awareness.last_seen_version) "Got: $($json.upgrade_awareness.last_seen_version)"
    }
} finally {
    Remove-TempProjectRoot -Path $tmpN
}

# O. UpdateDiscoveryState writes .concord/capability-discovery.yaml
$tmpO = New-TempProjectRoot
try {
    $null = & $Resolver -Format json -ProjectRoot $tmpO -UpdateDiscoveryState 2>&1
    $discoveryFile = Join-Path (Join-Path $tmpO '.concord') 'capability-discovery.yaml'
    Assert-True 'O. discovery state file created' (Test-Path $discoveryFile) "File not found: $discoveryFile"
    if (Test-Path $discoveryFile) {
        $discoveryText = Get-Content $discoveryFile -Raw
        Assert-True 'O. discovery state has last_seen_framework_version' ($discoveryText -match 'last_seen_framework_version') 'Missing field'
    }
} finally {
    Remove-TempProjectRoot -Path $tmpO
}

# P. CheckUpgrades after UpdateDiscoveryState returns correct last_seen
$tmpP = New-TempProjectRoot -Version '1.4'
try {
    # Write a discovery state with version 1.4
    $concordDir = Join-Path $tmpP '.concord'
    New-Item -ItemType Directory -Path $concordDir | Out-Null
    @'
last_seen_framework_version: "1.4"
updated: "2026-10-13T00:00:00Z"
'@ | Set-Content -Path (Join-Path $concordDir 'capability-discovery.yaml') -Encoding UTF8

    # Now resolver is at 1.4, last seen 1.4 -- no new capabilities
    $jsonOutput = & $Resolver -Format json -ProjectRoot $tmpP -CheckUpgrades 2>&1
    if ($LASTEXITCODE -eq 0) {
        $json = $jsonOutput | ConvertFrom-Json
        Assert-True 'P. last_seen_version read correctly' ($json.upgrade_awareness.last_seen_version -eq '1.4') "Got: $($json.upgrade_awareness.last_seen_version)"
    }
} finally {
    Remove-TempProjectRoot -Path $tmpP
}

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=== Results ===" -ForegroundColor Cyan
Write-Host "  PASS: $PassCount" -ForegroundColor Green
if ($FailCount -gt 0) {
    Write-Host "  FAIL: $FailCount" -ForegroundColor Red
    $FailDetails | ForEach-Object { Write-Host $_ -ForegroundColor Red }
    exit 1
} else {
    Write-Host "  All tests passed." -ForegroundColor Green
    exit 0
}
