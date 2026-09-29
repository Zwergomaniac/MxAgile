<#
.SYNOPSIS
    Regression tests for the MXCLI_TEST_BINARY shared binary cache mechanism.

    Tier: 1  NetworkRequired: false  RealMxcliRequired: false  ParallelSafe: true
#>

$ScriptDir   = Split-Path -Path $MyInvocation.MyCommand.Path -Parent
$RepoRoot    = Split-Path -Path $ScriptDir -Parent
$ScriptsDir  = Join-Path $RepoRoot 'scripts'
$InitScript  = Join-Path $ScriptsDir 'mxagile-init.ps1'
$RunAll      = Join-Path $ScriptDir 'run-all-tests.ps1'
$RunFast     = Join-Path $ScriptDir 'run-fast-tests.ps1'

$Passed = 0
$Failed = 0

function Assert-True {
    param([bool]$Condition, [string]$Name)
    if ($Condition) {
        Write-Host ('  PASS: ' + $Name)
        $script:Passed++
    } else {
        Write-Host ('  FAIL: ' + $Name) -ForegroundColor Red
        $script:Failed++
    }
}

function Assert-Contains {
    param([string]$File, [string]$Pattern, [string]$Name)
    if (-not (Test-Path -LiteralPath $File)) {
        Write-Host ('  FAIL: ' + $Name + ' (file not found: ' + $File + ')') -ForegroundColor Red
        $script:Failed++
        return
    }
    $content = Get-Content -LiteralPath $File -Raw
    Assert-True -Condition ($content -match $Pattern) -Name $Name
}

function Assert-NotContains {
    param([string]$File, [string]$Pattern, [string]$Name)
    if (-not (Test-Path -LiteralPath $File)) {
        Write-Host ('  FAIL: ' + $Name + ' (file not found: ' + $File + ')') -ForegroundColor Red
        $script:Failed++
        return
    }
    $content = Get-Content -LiteralPath $File -Raw
    Assert-True -Condition ($content -notmatch $Pattern) -Name $Name
}

# ---------------------------------------------------------------------------
# Group A: mxagile-init.ps1 — MXCLI_TEST_BINARY shortcut is present
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host 'Group A: mxagile-init.ps1 binary cache shortcut'

Assert-Contains -File $InitScript -Pattern 'MXCLI_TEST_BINARY' `
    -Name 'A.1 mxagile-init.ps1 reads MXCLI_TEST_BINARY env var'

Assert-Contains -File $InitScript -Pattern 'Copy-Item.*MXCLI_TEST_BINARY|MXCLI_TEST_BINARY.*Copy-Item|cachedBinary.*Copy-Item|Copy-Item.*cachedBinary' `
    -Name 'A.2 mxagile-init.ps1 copies cached binary when env var is set'

Assert-Contains -File $InitScript -Pattern 'install-mxcli\.ps1' `
    -Name 'A.3 mxagile-init.ps1 still falls back to installer when cache not set'

Assert-Contains -File $InitScript -Pattern 'Test-Path.*cachedBinary|cachedBinary.*Test-Path' `
    -Name 'A.4 mxagile-init.ps1 verifies cached binary exists before using it'

# ---------------------------------------------------------------------------
# Group B: run-all-tests.ps1 — cache acquired only for Tier 2
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host 'Group B: run-all-tests.ps1 cache acquisition strategy'

Assert-Contains -File $RunAll -Pattern 'MXCLI_TEST_BINARY' `
    -Name 'B.1 run-all-tests.ps1 uses MXCLI_TEST_BINARY'

Assert-Contains -File $RunAll -Pattern 'Tier 2.*tests.*run|tier2Tests.*Count|SkipTier2' `
    -Name 'B.2 run-all-tests.ps1 guards cache on Tier 2 presence'

Assert-Contains -File $RunAll -Pattern 'Tier 0.*Tier 1.*never.*download|Tier 0 and Tier 1 must never' `
    -Name 'B.3 run-all-tests.ps1 documents that Tier 0/1 never trigger download'

Assert-Contains -File $RunAll -Pattern 'mxagile-mxcli-test-cache' `
    -Name 'B.4 run-all-tests.ps1 uses named persistent cache directory'

# ---------------------------------------------------------------------------
# Group C: run-fast-tests.ps1 — never triggers binary download
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host 'Group C: run-fast-tests.ps1 must never trigger a download'

Assert-NotContains -File $RunFast -Pattern 'install-mxcli' `
    -Name 'C.1 run-fast-tests.ps1 does not reference install-mxcli.ps1'

Assert-NotContains -File $RunFast -Pattern 'MXCLI_TEST_BINARY' `
    -Name 'C.2 run-fast-tests.ps1 does not set or read MXCLI_TEST_BINARY'

Assert-NotContains -File $RunFast -Pattern 'mxcli-test-cache|mxcliCache' `
    -Name 'C.3 run-fast-tests.ps1 has no cache acquisition block'

Assert-NotContains -File $RunFast -Pattern 'NetworkRequired|RealMxcliRequired' `
    -Name 'C.4 run-fast-tests.ps1 does not execute network-dependent tests'

# ---------------------------------------------------------------------------
# Group D: Functional fixture — MXCLI_TEST_BINARY copy-instead-of-download
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host 'Group D: Functional test — copy-from-cache path in mxagile-init.ps1'

$TempDir   = Join-Path $env:TEMP ('mxcli-cache-test-' + [System.IO.Path]::GetRandomFileName())
$FakeMxcli = Join-Path $TempDir 'fake-mxcli.exe'
$TargetDir = Join-Path $TempDir 'project'

try {
    New-Item -ItemType Directory -Path $TempDir  -Force | Out-Null
    New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null

    # Create a fake mxcli binary (just a text file with a known marker)
    Set-Content -LiteralPath $FakeMxcli -Value 'FAKE-MXCLI-CACHE-BINARY' -Encoding ASCII

    # Save original env and set the cache path
    $origCached = $env:MXCLI_TEST_BINARY
    $env:MXCLI_TEST_BINARY = $FakeMxcli

    try {
        # Run mxagile-init.ps1 (it will fail after mxcli copy since the fake binary
        # is not real, but we only care that the copy step ran correctly)
        $output = & powershell -NoProfile -File $InitScript -ProjectRoot $TargetDir 2>&1
        # mxagile-init.ps1 will fail after copying because the fake binary
        # isn't executable, but the copy should have happened
    } catch {
        # Expected — fake binary causes downstream failures
    } finally {
        $env:MXCLI_TEST_BINARY = $origCached
    }

    $isWin = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
        [System.Runtime.InteropServices.OSPlatform]::Windows)
    $mxcliName = if ($isWin) { 'mxcli.exe' } else { 'mxcli' }
    $copyDest  = Join-Path $TargetDir $mxcliName

    Assert-True -Condition (Test-Path -LiteralPath $copyDest -PathType Leaf) `
        -Name 'D.1 mxcli binary was copied from MXCLI_TEST_BINARY into project dir'

    if (Test-Path -LiteralPath $copyDest -PathType Leaf) {
        $copiedContent = Get-Content -LiteralPath $copyDest -Raw
        Assert-True -Condition ($copiedContent -match 'FAKE-MXCLI-CACHE-BINARY') `
            -Name 'D.2 copied binary is the cached file (not a fresh download)'
    }

    # Verify the output mentions the cache path (not the installer)
    $outputStr = $output -join "`n"
    Assert-True -Condition ($outputStr -match 'MXCLI_TEST_BINARY|pre-cached') `
        -Name 'D.3 mxagile-init.ps1 reports using the cached binary'

} finally {
    if (Test-Path -LiteralPath $TempDir) {
        Remove-Item -LiteralPath $TempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ---------------------------------------------------------------------------
# Group E: Inventory completeness — every discovered test has a tier entry
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host 'Group E: Inventory completeness'

$inventoryPath = Join-Path $ScriptDir 'test-inventory.json'
Assert-True -Condition (Test-Path -LiteralPath $inventoryPath -PathType Leaf) `
    -Name 'E.1 test-inventory.json exists'

if (Test-Path -LiteralPath $inventoryPath -PathType Leaf) {
    $inventoryData = Get-Content -LiteralPath $inventoryPath -Raw | ConvertFrom-Json
    $inventoryFiles = $inventoryData | ForEach-Object { $_.File }

    $discoveredTests = @(Get-ChildItem -Path $ScriptDir -Filter 'test-*.ps1') +
                       @(Get-ChildItem -Path $ScriptDir -Filter 'smoke-test.ps1' -ErrorAction SilentlyContinue)

    $missing = $discoveredTests | Where-Object { $_.Name -notin $inventoryFiles }
    Assert-True -Condition ($missing.Count -eq 0) `
        -Name ('E.2 all discovered tests are in inventory (' + $missing.Count + ' missing)')

    if ($missing.Count -gt 0) {
        $missing | ForEach-Object { Write-Host ('    missing: ' + $_.Name) -ForegroundColor Yellow }
    }

    $t0 = ($inventoryData | Where-Object { $_.Tier -eq 0 }).Count
    $t1 = ($inventoryData | Where-Object { $_.Tier -eq 1 }).Count
    $t2 = ($inventoryData | Where-Object { $_.Tier -eq 2 }).Count
    Assert-True -Condition ($t0 -gt 0 -and $t1 -gt 0 -and $t2 -gt 0) `
        -Name ('E.3 inventory has entries for all three tiers (T0=' + $t0 + ' T1=' + $t1 + ' T2=' + $t2 + ')')

    $noReason = $inventoryData | Where-Object { -not $_.Reason -or $_.Reason -eq '' }
    Assert-True -Condition ($noReason.Count -eq 0) `
        -Name 'E.4 every inventory entry has a Reason'
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
Write-Host ''
$total = $Passed + $Failed
Write-Host ('=' * 60)
if ($Failed -gt 0) {
    Write-Host ('RESULTS: ' + $Passed + ' passed, ' + $Failed + ' FAILED out of ' + $total + ' tests') -ForegroundColor Red
    exit 1
} else {
    Write-Host ('RESULTS: ' + $Passed + ' passed, 0 failed out of ' + $total + ' tests') -ForegroundColor Green
    Write-Host 'All tests PASSED'
    exit 0
}
