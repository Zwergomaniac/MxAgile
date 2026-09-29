<#
.SYNOPSIS
    Full MxAgile framework regression suite. Runs Tier 0 + Tier 1 + Tier 2.
.DESCRIPTION
    Authoritative complete regression run. Includes real mxcli integration tests.

    For a fast developer/agent feedback loop that skips Tier 2, use run-fast-tests.ps1.

    Environment variables:
      MXCLI_TEST_BINARY   Pre-cached mxcli binary path. Set externally to skip per-run
                          download. When unset the runner pre-downloads mxcli once before
                          Tier 2 begins. Tier 0 and Tier 1 never trigger a download.
      MXAGILE_SKIP_TIER2  Set to any non-empty value to skip Tier 2. Its use is reported
                          prominently in the summary. Not for normal regression runs.

    See tests/test-inventory.json for tier assignments and resource isolation metadata.
#>

$ScriptDir = Split-Path -Path $MyInvocation.MyCommand.Path -Parent

# ---------------------------------------------------------------------------
# Tier inventory
# ---------------------------------------------------------------------------
$inventoryPath = Join-Path $ScriptDir 'test-inventory.json'
if (-not (Test-Path -LiteralPath $inventoryPath)) {
    Write-Error "test-inventory.json not found. Expected: $inventoryPath"
    exit 1
}
$inventoryList = Get-Content -LiteralPath $inventoryPath -Raw | ConvertFrom-Json
$inventory = @{}
foreach ($entry in $inventoryList) { $inventory[$entry.File] = $entry }

# ---------------------------------------------------------------------------
# Discover test files
# ---------------------------------------------------------------------------
$testFiles  = Get-ChildItem -Path $ScriptDir -Filter 'test-*.ps1'
$smokeFile  = Get-ChildItem -Path $ScriptDir -Filter 'smoke-test.ps1' -ErrorAction SilentlyContinue
$allFiles   = @($testFiles) + @($smokeFile | Where-Object { $_ })

if ($allFiles.Count -eq 0) {
    Write-Error 'No test files found in tests/ directory.'
    exit 1
}

$skipTier2 = ($env:MXAGILE_SKIP_TIER2 -and $env:MXAGILE_SKIP_TIER2 -ne '')

# Split by tier
$tier0Tests   = [System.Collections.Generic.List[object]]::new()
$tier1Tests   = [System.Collections.Generic.List[object]]::new()
$tier2Tests   = [System.Collections.Generic.List[object]]::new()
$unknownTests = [System.Collections.Generic.List[string]]::new()

foreach ($f in $allFiles) {
    $meta = $inventory[$f.Name]
    if (-not $meta) {
        $unknownTests.Add($f.Name)
        $tier2Tests.Add($f)   # conservative default for unclassified tests
        continue
    }
    switch ([int]$meta.Tier) {
        0 { $tier0Tests.Add($f) }
        1 { $tier1Tests.Add($f) }
        2 { $tier2Tests.Add($f) }
        default { $unknownTests.Add($f.Name); $tier2Tests.Add($f) }
    }
}

# ---------------------------------------------------------------------------
# Header
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '======================================================================'
if ($skipTier2) {
    Write-Host 'FULL REGRESSION   [WARNING: Tier 2 SKIPPED via MXAGILE_SKIP_TIER2]'
} else {
    Write-Host 'FULL REGRESSION   [Tier 0 + Tier 1 + Tier 2]'
}
Write-Host '======================================================================'
Write-Host ("  Tier 0 (static/contract):    {0,3} tests" -f $tier0Tests.Count)
Write-Host ("  Tier 1 (component/fixture):  {0,3} tests" -f $tier1Tests.Count)
if ($skipTier2) {
    Write-Host ("  Tier 2 (integration):            SKIPPED ({0} tests) [MXAGILE_SKIP_TIER2 is set]" -f $tier2Tests.Count) -ForegroundColor Yellow
} else {
    Write-Host ("  Tier 2 (integration):        {0,3} tests" -f $tier2Tests.Count)
}
if ($unknownTests.Count -gt 0) {
    Write-Host ("  WARNING: {0} unclassified test(s) treated as Tier 2:" -f $unknownTests.Count) -ForegroundColor Yellow
    foreach ($u in $unknownTests) { Write-Host ('    - ' + $u) -ForegroundColor Yellow }
}
Write-Host '======================================================================'
Write-Host ''

# ---------------------------------------------------------------------------
# mxcli binary cache — acquire ONLY when Tier 2 tests will run
# Tier 0 and Tier 1 must never trigger a network download.
# ---------------------------------------------------------------------------
if (-not $skipTier2 -and $tier2Tests.Count -gt 0) {
    if (-not $env:MXCLI_TEST_BINARY) {
        $mxcliCacheDir = Join-Path $env:TEMP 'mxagile-mxcli-test-cache'
        $isWin = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
            [System.Runtime.InteropServices.OSPlatform]::Windows)
        $mxcliCacheName = if ($isWin) { 'mxcli.exe' } else { 'mxcli' }
        $mxcliCacheBin  = Join-Path $mxcliCacheDir $mxcliCacheName

        if (-not (Test-Path -LiteralPath $mxcliCacheBin -PathType Leaf)) {
            Write-Host 'Tier 2 tests require mxcli. Pre-downloading binary cache (one-time, ~91 MB)...' -ForegroundColor Cyan
            New-Item -ItemType Directory -Path $mxcliCacheDir -Force | Out-Null
            $installerScript = Join-Path $ScriptDir '..\scripts\install-mxcli.ps1'
            & powershell -NoProfile -File $installerScript -TargetDir $mxcliCacheDir
            if ($LASTEXITCODE -ne 0) {
                Write-Warning ("mxcli pre-download failed (exit $LASTEXITCODE). Tier 2 tests will fall back to per-test downloads.")
            }
        }

        if (Test-Path -LiteralPath $mxcliCacheBin -PathType Leaf) {
            $env:MXCLI_TEST_BINARY = $mxcliCacheBin
            Write-Host ('mxcli test cache ready: ' + $mxcliCacheBin) -ForegroundColor DarkGray
            Write-Host ''
        }
    } else {
        Write-Host ('mxcli: using externally set MXCLI_TEST_BINARY=' + $env:MXCLI_TEST_BINARY) -ForegroundColor DarkGray
        Write-Host ''
    }
}

# ---------------------------------------------------------------------------
# Execute in tier order: Tier 0, Tier 1, Tier 2
# ---------------------------------------------------------------------------
$testsToRun = [System.Collections.Generic.List[object]]::new()
foreach ($t in $tier0Tests) { $testsToRun.Add($t) }
foreach ($t in $tier1Tests) { $testsToRun.Add($t) }
if (-not $skipTier2) {
    foreach ($t in $tier2Tests) { $testsToRun.Add($t) }
}

$results     = [System.Collections.Generic.List[object]]::new()
$failedCount = 0

foreach ($testFile in $testsToRun) {
    $meta = $inventory[$testFile.Name]
    $tier = if ($meta) { $meta.Tier } else { '?' }
    $net  = if ($meta -and $meta.NetworkRequired)   { 'net' }   else { '' }
    $mx   = if ($meta -and $meta.RealMxcliRequired) { 'mxcli' } else { '' }
    $tags = (@($net, $mx) | Where-Object { $_ }) -join '+'
    $label = if ($tags) { ' [' + $tags + ']' } else { '' }

    Write-Host '======================================================================'
    Write-Host ('EXECUTING [Tier ' + $tier + $label + ']: ' + $testFile.Name)
    Write-Host '======================================================================'

    $startTime = Get-Date
    try {
        powershell -NoProfile -File $testFile.FullName
        $exitCode = $LASTEXITCODE
    } catch {
        Write-Error ('Terminating error in ' + $testFile.Name + ': ' + ($_ | Out-String))
        $exitCode = -1
    }
    $duration = (Get-Date) - $startTime
    $status   = if ($exitCode -eq 0) { 'PASS' } else { 'FAIL' }
    if ($status -eq 'FAIL') { $failedCount++ }

    $results.Add([PSCustomObject]@{
        Tier     = $tier
        TestFile = $testFile.Name
        Status   = $status
        Duration = '{0:N2}s' -f $duration.TotalSeconds
        Network  = $net
        Mxcli    = $mx
        ExitCode = $exitCode
    })
    Write-Host ''
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
Write-Host '======================================================================'
Write-Host 'FULL REGRESSION SUMMARY'
Write-Host '======================================================================'
$results | Format-Table Tier, TestFile, Status, Duration, Network, Mxcli -AutoSize

Write-Host ''
$t0Fail = ($results | Where-Object { $_.Tier -eq 0 -and $_.Status -eq 'FAIL' }).Count
$t1Fail = ($results | Where-Object { $_.Tier -eq 1 -and $_.Status -eq 'FAIL' }).Count
$t2Fail = ($results | Where-Object { $_.Tier -eq 2 -and $_.Status -eq 'FAIL' }).Count

Write-Host 'Tier 0 (static/contract):   ' -NoNewline
if ($t0Fail -gt 0) { Write-Host ('FAIL (' + $t0Fail + ')') -ForegroundColor Red }
else               { Write-Host 'PASS' -ForegroundColor Green }

Write-Host 'Tier 1 (component/fixture): ' -NoNewline
if ($t1Fail -gt 0) { Write-Host ('FAIL (' + $t1Fail + ')') -ForegroundColor Red }
else               { Write-Host 'PASS' -ForegroundColor Green }

Write-Host 'Tier 2 (integration):       ' -NoNewline
if ($skipTier2) {
    Write-Host 'NOT EXECUTED  [MXAGILE_SKIP_TIER2 was set]' -ForegroundColor Yellow
} elseif ($t2Fail -gt 0) {
    Write-Host ('FAIL (' + $t2Fail + ')') -ForegroundColor Red
} else {
    Write-Host 'PASS' -ForegroundColor Green
}

Write-Host ''
if ($failedCount -gt 0) {
    Write-Host ('FULL REGRESSION: FAIL  (' + $failedCount + ' test(s) failed)') -ForegroundColor Red
    exit 1
} elseif ($skipTier2) {
    Write-Host 'FULL REGRESSION: INCOMPLETE  (Tier 2 skipped -- MXAGILE_SKIP_TIER2 was set)' -ForegroundColor Yellow
    exit 0
} else {
    Write-Host 'FULL REGRESSION: PASS' -ForegroundColor Green
    exit 0
}
