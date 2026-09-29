<#
.SYNOPSIS
    FAST developer/agent test entry point.
.DESCRIPTION
    Runs the normal developer feedback loop:
      - All Tier 0 tests (static/contract)
      - Tier 1 tests explicitly marked FastGate=true

    Tier 1 tests with FastGate=false (test-layer-update, test-mxagile-dev-cli,
    test-workcopy-hygiene, test-mxcli-binary-cache) are excluded because they are
    too slow or require exclusive resources that make them unsuitable for the fast
    feedback loop. They remain part of FULL regression (run-all-tests.ps1).

    Tier 2 (integration) tests require real mxcli and network and are always
    excluded from FAST.

    On PowerShell 7+, all ParallelSafe tests run concurrently via
    ForEach-Object -Parallel. Non-parallel-safe tests run sequentially after
    the parallel batch. On PowerShell 5.1 every test runs sequentially.

    A FAST PASS is NOT equivalent to a FULL regression PASS.

    See tests/test-inventory.json for tier, FastGate, and ParallelSafe assignments.
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
$testFiles = Get-ChildItem -Path $ScriptDir -Filter 'test-*.ps1'
$smokeFile = Get-ChildItem -Path $ScriptDir -Filter 'smoke-test.ps1' -ErrorAction SilentlyContinue
$allFiles  = @($testFiles) + @($smokeFile | Where-Object { $_ })

# ---------------------------------------------------------------------------
# Partition: FAST = Tier 0 + Tier 1 FastGate=true
#            EXCLUDED = Tier 1 FastGate=false  (FULL only, too slow/exclusive)
#            SKIPPED  = Tier 2 (requires mxcli/network)
# ---------------------------------------------------------------------------
$fastTests     = [System.Collections.Generic.List[object]]::new()
$excludedTier1 = [System.Collections.Generic.List[string]]::new()
$skippedTier2  = [System.Collections.Generic.List[string]]::new()

foreach ($f in $allFiles) {
    $meta = $inventory[$f.Name]
    $tier = if ($meta) { [int]$meta.Tier } else { 2 }

    if ($tier -eq 0) {
        $fastTests.Add($f)
    } elseif ($tier -eq 1) {
        $gate = if ($meta) { [bool]$meta.FastGate } else { $false }
        if ($gate) { $fastTests.Add($f) }
        else        { $excludedTier1.Add($f.Name) }
    } else {
        $skippedTier2.Add($f.Name)
    }
}

$tier0Count     = ($fastTests | Where-Object { $m = $inventory[$_.Name]; $m -and [int]$m.Tier -eq 0 }).Count
$tier1FastCount = $fastTests.Count - $tier0Count

# ---------------------------------------------------------------------------
# Header
# ---------------------------------------------------------------------------
$isPS7   = $PSVersionTable.PSVersion.Major -ge 7
$modeTag = if ($isPS7) { '[parallel-safe batch + sequential]' } else { '[sequential -- upgrade to pwsh 7+ for parallel mode]' }

Write-Host ''
Write-Host '======================================================================'
Write-Host 'FAST REGRESSION   [NOT equivalent to FULL regression]'
Write-Host '======================================================================'
Write-Host ("  Tier 0 (static/contract):       {0,3} tests  -- executed" -f $tier0Count)
Write-Host ("  Tier 1 FastGate=true:           {0,3} tests  -- executed" -f $tier1FastCount)
Write-Host ("  Tier 1 FastGate=false:          {0,3} tests  -- NOT EXECUTED (FULL only)" -f $excludedTier1.Count)
Write-Host ("  Tier 2 (integration/network):   {0,3} tests  -- NOT EXECUTED (FULL only)" -f $skippedTier2.Count)
Write-Host ("  Execution mode:                 $modeTag")
Write-Host '======================================================================'
Write-Host ''

if ($excludedTier1.Count -gt 0) {
    Write-Host '  Tier 1 FastGate=false (not executed):'
    foreach ($s in $excludedTier1) { Write-Host ('    - ' + $s) }
    Write-Host ''
}

if ($fastTests.Count -eq 0) {
    Write-Error 'No FAST tests found.'
    exit 1
}

# ---------------------------------------------------------------------------
# Split by parallel safety
# ---------------------------------------------------------------------------
$parallelTests   = [System.Collections.Generic.List[object]]::new()
$sequentialTests = [System.Collections.Generic.List[object]]::new()

foreach ($f in $fastTests) {
    $meta = $inventory[$f.Name]
    if ($isPS7 -and $meta -and $meta.ParallelSafe) {
        $parallelTests.Add($f)
    } else {
        $sequentialTests.Add($f)
    }
}

$results     = [System.Collections.Generic.List[object]]::new()
$failedCount = 0
$suiteStart  = Get-Date

# ---------------------------------------------------------------------------
# Phase A: Parallel batch (PS7 only, ParallelSafe tests)
# ---------------------------------------------------------------------------
if ($parallelTests.Count -gt 0) {
    Write-Host ('======================================================================')
    Write-Host ('PARALLEL BATCH  [{0} tests -- all ParallelSafe]' -f $parallelTests.Count)
    Write-Host ('======================================================================')
    Write-Host ''

    $batchStart = Get-Date

    $batchResults = $parallelTests | ForEach-Object -Parallel {
        $file    = $_
        $invCopy = $using:inventory
        $meta    = $invCopy[$file.Name]
        $tier    = if ($meta) { $meta.Tier } else { '?' }

        $startTime = Get-Date
        $rawOutput = & powershell -NoProfile -File $file.FullName 2>&1
        $exitCode  = $LASTEXITCODE
        $duration  = (Get-Date) - $startTime

        [PSCustomObject]@{
            Tier      = $tier
            FastGate  = if ($meta) { $meta.FastGate } else { $false }
            TestFile  = $file.Name
            Status    = if ($exitCode -eq 0) { 'PASS' } else { 'FAIL' }
            Duration  = '{0:N2}s' -f $duration.TotalSeconds
            ExitCode  = $exitCode
            Output    = ($rawOutput | ForEach-Object { $_.ToString() }) -join "`n"
        }
    } -ThrottleLimit 8

    $batchDuration = (Get-Date) - $batchStart

    foreach ($r in ($batchResults | Sort-Object Tier, TestFile)) {
        if ($r.Status -eq 'PASS') {
            Write-Host ('  PASS  ' + $r.TestFile + '  (' + $r.Duration + ')') -ForegroundColor Green
        } else {
            Write-Host ''
            Write-Host ('======================================================================')
            Write-Host ('FAILED: ' + $r.TestFile) -ForegroundColor Red
            Write-Host ('======================================================================')
            Write-Host $r.Output
            Write-Host ''
            $failedCount++
        }
        $results.Add($r)
    }

    Write-Host ''
    Write-Host ('Parallel batch completed in {0:N2}s' -f $batchDuration.TotalSeconds) -ForegroundColor DarkGray
    Write-Host ''
}

# ---------------------------------------------------------------------------
# Phase B: Sequential tests (non-parallel-safe, or all when PS5.1)
# ---------------------------------------------------------------------------
foreach ($testFile in $sequentialTests) {
    $meta = $inventory[$testFile.Name]
    $tier = if ($meta) { $meta.Tier } else { '?' }

    Write-Host '======================================================================'
    Write-Host ('EXECUTING [Tier {0}]: {1}' -f $tier, $testFile.Name)
    Write-Host '======================================================================'

    $startTime = Get-Date
    try {
        powershell -NoProfile -File $testFile.FullName
        $exitCode = $LASTEXITCODE
    } catch {
        Write-Error ('Terminating error in {0}: {1}' -f $testFile.Name, ($_ | Out-String))
        $exitCode = -1
    }
    $duration = (Get-Date) - $startTime
    $status   = if ($exitCode -eq 0) { 'PASS' } else { 'FAIL' }
    if ($status -eq 'FAIL') { $failedCount++ }

    $results.Add([PSCustomObject]@{
        Tier     = $tier
        FastGate = if ($meta) { $meta.FastGate } else { $false }
        TestFile = $testFile.Name
        Status   = $status
        Duration = '{0:N2}s' -f $duration.TotalSeconds
        ExitCode = $exitCode
    })
    Write-Host ''
}

$totalDuration = (Get-Date) - $suiteStart

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
Write-Host '======================================================================'
Write-Host 'FAST REGRESSION SUMMARY'
Write-Host '======================================================================'
$results | Sort-Object Tier, TestFile | Format-Table Tier, FastGate, TestFile, Status, Duration -AutoSize

Write-Host ''
Write-Host '  Tier 1 FastGate=false -- NOT EXECUTED in fast mode:'
foreach ($s in $excludedTier1) { Write-Host ('    - ' + $s) }
Write-Host ''
Write-Host '  Tier 2 (integration) -- NOT EXECUTED in fast mode:'
foreach ($s in $skippedTier2) { Write-Host ('    - ' + $s) }
Write-Host ''

$t0Fail = ($results | Where-Object { $_.Tier -eq 0 -and $_.Status -eq 'FAIL' }).Count
$t1Fail = ($results | Where-Object { $_.Tier -eq 1 -and $_.Status -eq 'FAIL' }).Count

Write-Host ('Tier 0 (static/contract):          ') -NoNewline
if ($t0Fail -gt 0) { Write-Host ('FAIL (' + $t0Fail + ')') -ForegroundColor Red }
else               { Write-Host 'PASS' -ForegroundColor Green }

Write-Host ('Tier 1 FastGate=true:              ') -NoNewline
if ($t1Fail -gt 0) { Write-Host ('FAIL (' + $t1Fail + ')') -ForegroundColor Red }
else               { Write-Host 'PASS' -ForegroundColor Green }

Write-Host 'Tier 1 FastGate=false:             NOT EXECUTED' -ForegroundColor Yellow
Write-Host 'Tier 2 (integration):              NOT EXECUTED' -ForegroundColor Yellow
Write-Host ''
Write-Host ('Wall-clock: {0:N2}s' -f $totalDuration.TotalSeconds)
Write-Host ''

if ($failedCount -gt 0) {
    Write-Host ('FAST REGRESSION: FAIL  (' + $failedCount + ' test(s) failed)') -ForegroundColor Red
    Write-Host ''
    Write-Host 'NOTE: This is NOT a full regression result. Run run-all-tests.ps1 for complete coverage.' -ForegroundColor Yellow
    exit 1
} else {
    Write-Host 'FAST REGRESSION: PASS' -ForegroundColor Green
    Write-Host ''
    Write-Host 'NOTE: This is NOT a full regression result. Run run-all-tests.ps1 for complete coverage.' -ForegroundColor Yellow
    exit 0
}
