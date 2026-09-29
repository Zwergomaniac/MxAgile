[CmdletBinding(SupportsShouldProcess = $true)]
param (
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string]$TemplateName,

    [Parameter(Position = 1)]
    [string]$TestDirName,

    [switch]$Force,

    # Robocopy thread count. 8 is a safe default on most developer machines.
    # Increase only if I/O is the bottleneck and the machine has fast storage.
    [ValidateRange(1, 128)]
    [int]$Threads = 8,

    # Show full Robocopy file/directory listings instead of the compact summary.
    [switch]$VerboseCopy
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrEmpty($TestDirName)) {
    $TestDirName = $TemplateName
}

$WorkspaceRoot = Split-Path -Parent $PSScriptRoot
$SourcePath    = Join-Path $WorkspaceRoot "project-templates\$TemplateName"
$DestPath      = Join-Path $WorkspaceRoot ".testing-$TestDirName"

# ---------------------------------------------------------------------------
# Helper
# ---------------------------------------------------------------------------
function Format-Bytes {
    param([long]$Bytes)
    if ($Bytes -ge 1GB) { return "{0:F1} GB" -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return "{0:F1} MB" -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return "{0:F1} KB" -f ($Bytes / 1KB) }
    return "$Bytes B"
}

# ---------------------------------------------------------------------------
# Source validation
# ---------------------------------------------------------------------------
if (-not (Test-Path -LiteralPath $SourcePath -PathType Container)) {
    Write-Error "Source template not found: $SourcePath"
    exit 1
}

# ---------------------------------------------------------------------------
# Copy policy
# ---------------------------------------------------------------------------
#
# By-name exclusions: match any directory with this exact name at any depth.
#   node_modules     - REGENERATABLE: npm packages (any tool, any depth)
#   .mendix-cache    - CACHE: Mendix Studio extension/module/backup cache
#   .playwright-mcp  - TRANSIENT: Playwright MCP server console logs
#   .playwright-cli  - TRANSIENT: Playwright CLI console logs
#
# By-path exclusions: match only the specific absolute path.
#   .docker\build    - CACHE: Docker build layer blobs (app + lib, ~494 MB)
#   .concord\scratch\pw - TRANSIENT: Playwright screenshot/trace artifacts in Concord scratch
#
# NOT excluded (preserved):
#   .dfc-ai/            Required for brownfield migration tests (legacy DFC markers)
#   .concord/           Project memory, journal, plans, scratch scripts preserved
#   mprcontents/        Required Mendix application content
#   modules/            Required Mendix application modules
#   planning/           Project knowledge
#   .docker/.env        Preserved as-is (flagged with credential warning below)
#   vendorlib/          Required Mendix Java dependencies
#   .claude/            Brownfield agent history
#   .ai-context/        AI context state

$ExcludeByName = @(
    'node_modules',
    '.mendix-cache',
    '.playwright-mcp',
    '.playwright-cli'
)

$ExcludeByPath = @(
    (Join-Path $SourcePath '.docker\build'),
    (Join-Path $SourcePath '.concord\scratch\pw')
)

# Optional fixture-specific override: place a .test-workcopy-policy.json at the fixture root
$policyFile = Join-Path $SourcePath '.test-workcopy-policy.json'
if (Test-Path -LiteralPath $policyFile -PathType Leaf) {
    try {
        $policy = Get-Content -LiteralPath $policyFile -Raw | ConvertFrom-Json
        if ($policy.additionalExcludeByName) {
            $ExcludeByName += @($policy.additionalExcludeByName)
        }
        if ($policy.additionalExcludeByPath) {
            foreach ($rel in @($policy.additionalExcludeByPath)) {
                $ExcludeByPath += (Join-Path $SourcePath $rel)
            }
        }
    } catch {
        Write-Warning "Could not parse .test-workcopy-policy.json: $_"
    }
}

# ---------------------------------------------------------------------------
# Credential notice (high-visibility — always shown regardless of other flags)
# ---------------------------------------------------------------------------
$envFile = Join-Path $SourcePath '.docker\.env'
if (Test-Path -LiteralPath $envFile -PathType Leaf) {
    Write-Host ""
    Write-Host "  NOTICE: .docker/.env contains environment variables including credentials." -ForegroundColor Yellow
    Write-Host "          File is included in the workcopy. Do not commit the workcopy." -ForegroundColor Yellow
}

# ---------------------------------------------------------------------------
# Destination handling
# ---------------------------------------------------------------------------
if (Test-Path -LiteralPath $DestPath) {
    if (-not $Force) {
        Write-Error "Destination '$DestPath' already exists. Use -Force to overwrite."
        exit 1
    }

    $resolvedDest = (Resolve-Path -LiteralPath $DestPath).Path
    $resolvedRoot = (Resolve-Path -LiteralPath $WorkspaceRoot).Path
    if (-not $resolvedDest.StartsWith($resolvedRoot)) {
        Write-Error "CRITICAL: Destination '$DestPath' is outside workspace root. Aborting."
        exit 1
    }
    if (-not (Split-Path -Leaf $resolvedDest).StartsWith('.testing-')) {
        Write-Error "CRITICAL: Destination leaf does not start with '.testing-'. Aborting."
        exit 1
    }

    if ($PSCmdlet.ShouldProcess($DestPath, 'Remove existing directory')) {
        try {
            Remove-Item -LiteralPath $DestPath -Recurse -Force
        } catch [System.IO.IOException] {
            Write-Host ""
            Write-Error "Workspace may still be in use by another terminal, agent, or application and could not be reset.`nPath: $DestPath`nClose all processes accessing this path, then retry."
            exit 1
        }
    }
}

# ---------------------------------------------------------------------------
# Source immutability baseline (hash .mpr files before copy)
# ---------------------------------------------------------------------------
$preCopyHashes = @{}
Get-ChildItem -LiteralPath $SourcePath -Filter '*.mpr' -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
    $preCopyHashes[$_.FullName] = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
}

# ---------------------------------------------------------------------------
# Progress header
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=== Test Workcopy: $TemplateName ===" -ForegroundColor Cyan
Write-Host "  Source  : $SourcePath"
Write-Host "  Dest    : $DestPath"
Write-Host "  Threads : $Threads"
Write-Host ""
Write-Host "  Excluded by name (any depth):"
foreach ($ex in $ExcludeByName) { Write-Host "    - $ex" -ForegroundColor DarkGray }
Write-Host "  Excluded by path:"
foreach ($ex in $ExcludeByPath) { Write-Host "    - $ex" -ForegroundColor DarkGray }
Write-Host ""

# ---------------------------------------------------------------------------
# Robocopy
# ---------------------------------------------------------------------------
if ($PSCmdlet.ShouldProcess($DestPath, "Create test workcopy from '$TemplateName'")) {

    $robocopyArgs = [System.Collections.Generic.List[string]]::new()
    $robocopyArgs.Add($SourcePath)
    $robocopyArgs.Add($DestPath)
    $robocopyArgs.Add('/E')           # include subdirectories and empty ones
    $robocopyArgs.Add('/COPY:DAT')    # copy Data, Attributes, Timestamps
    $robocopyArgs.Add("/MT:$Threads") # multithreaded copy
    $robocopyArgs.Add('/R:2')         # 2 retries on file-copy failure
    $robocopyArgs.Add('/W:1')         # 1 second between retries
    $robocopyArgs.Add('/NP')          # suppress per-file progress percentage
    $robocopyArgs.Add('/BYTES')       # byte-precision summary (enables parsing below)

    foreach ($name in $ExcludeByName) {
        $robocopyArgs.Add('/XD')
        $robocopyArgs.Add($name)
    }
    foreach ($path in $ExcludeByPath) {
        $robocopyArgs.Add('/XD')
        $robocopyArgs.Add($path)
    }

    if (-not $VerboseCopy) {
        $robocopyArgs.Add('/NFL')   # suppress per-file listing
        $robocopyArgs.Add('/NDL')   # suppress per-directory listing
    }

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    if ($VerboseCopy) {
        & robocopy @robocopyArgs
        $robocopyExitCode = $LASTEXITCODE
        $roboCaptured     = $null
    } else {
        Write-Host "  Copying..." -NoNewline
        $roboCaptured     = @(& robocopy @robocopyArgs 2>&1 | ForEach-Object { "$_" })
        $robocopyExitCode = $LASTEXITCODE
    }

    $stopwatch.Stop()

    # Robocopy exit codes:
    #   0   No files copied (source and dest identical).
    #   1   Files copied successfully.
    #   2   Extra files in dest (not our case - fresh dest).
    #   3   1+2.
    #   4   Mismatched files.
    #   5   1+4.
    #   6   2+4.
    #   7   1+2+4.
    #   8+  At least one failure (file/dir could not be copied).
    #  16   Fatal error.
    if ($robocopyExitCode -ge 8) {
        Write-Host ""   # end the "Copying..." line on failure
        if ($null -ne $roboCaptured) {
            $roboCaptured | Where-Object { $_ -match 'ERROR|FAILED' } | ForEach-Object {
                Write-Host "  $_" -ForegroundColor Red
            }
        }
        Write-Host ""
        Write-Host "  [FAILED] Robocopy exited with code $robocopyExitCode - destination may be incomplete." -ForegroundColor Red
        exit 1
    }

    if (-not $VerboseCopy) {
        Write-Host " done." -ForegroundColor Green
    }

    # Parse Robocopy summary from captured output (locale-agnostic, Total column).
    # Strategy: collect lines whose tokens after the first colon are all pure integers
    # and number exactly 6 (the Dirs/Files/Bytes summary rows). The Times row is excluded
    # because its tokens contain colons (0:00:11 format).
    # Row order is always Dirs, Files, Bytes regardless of locale.
    $rbFiles = 0L
    $rbDirs  = 0L
    $rbBytes = 0L
    if ($null -ne $roboCaptured) {
        $summaryDataRows = [System.Collections.Generic.List[string]]::new()
        foreach ($line in $roboCaptured) {
            $colonIdx = $line.IndexOf(':')
            if ($colonIdx -lt 0) { continue }
            $afterColon = $line.Substring($colonIdx + 1).Trim()
            $tokens = @($afterColon -split '\s+' | Where-Object { $_ -ne '' })
            if ($tokens.Count -eq 6 -and
                -not @($tokens | Where-Object { $_ -notmatch '^\d+$' })) {
                $summaryDataRows.Add($line)
            }
        }
        if ($summaryDataRows.Count -ge 3) {
            if ($summaryDataRows[0] -match ':\s*(\d+)') { $rbDirs  = [long]$Matches[1] }
            if ($summaryDataRows[1] -match ':\s*(\d+)') { $rbFiles = [long]$Matches[1] }
            if ($summaryDataRows[2] -match ':\s*(\d+)') { $rbBytes = [long]$Matches[1] }
        }
    }

    # ---------------------------------------------------------------------------
    # Fixture fidelity validation
    # ---------------------------------------------------------------------------
    $fidelityErrors = [System.Collections.Generic.List[string]]::new()

    $destMpr = @(Get-ChildItem -LiteralPath $DestPath -Filter '*.mpr' -File -ErrorAction SilentlyContinue)
    if ($destMpr.Count -eq 0) {
        $fidelityErrors.Add("No .mpr file found in destination")
    }

    $srcDfc = Join-Path $SourcePath '.dfc-ai'
    $dstDfc = Join-Path $DestPath '.dfc-ai'
    if ((Test-Path -LiteralPath $srcDfc -PathType Container) -and
        -not (Test-Path -LiteralPath $dstDfc -PathType Container)) {
        $fidelityErrors.Add(".dfc-ai/ missing in destination (required for brownfield migration tests)")
    }

    $srcPlan = Join-Path $SourcePath 'planning'
    $dstPlan = Join-Path $DestPath 'planning'
    if ((Test-Path -LiteralPath $srcPlan -PathType Container) -and
        -not (Test-Path -LiteralPath $dstPlan -PathType Container)) {
        $fidelityErrors.Add("planning/ missing in destination")
    }

    $srcMprc = Join-Path $SourcePath 'mprcontents'
    $dstMprc = Join-Path $DestPath 'mprcontents'
    if ((Test-Path -LiteralPath $srcMprc -PathType Container) -and
        -not (Test-Path -LiteralPath $dstMprc -PathType Container)) {
        $fidelityErrors.Add("mprcontents/ missing in destination")
    }

    $srcLifecycle = Join-Path $SourcePath '.mxagile\lifecycle.yaml'
    $dstLifecycle = Join-Path $DestPath '.mxagile\lifecycle.yaml'
    if (-not (Test-Path -LiteralPath $srcLifecycle -PathType Leaf) -and
         (Test-Path -LiteralPath $dstLifecycle -PathType Leaf)) {
        $fidelityErrors.Add("FATAL: .mxagile/lifecycle.yaml introduced into destination - migration start condition corrupted")
    }

    if ($fidelityErrors.Count -gt 0) {
        Write-Host ""
        Write-Host "  FIDELITY ERRORS:" -ForegroundColor Red
        foreach ($err in $fidelityErrors) { Write-Host "    - $err" -ForegroundColor Red }
        exit 1
    }

    # ---------------------------------------------------------------------------
    # Source immutability check
    # ---------------------------------------------------------------------------
    $mutated = @()
    foreach ($path in $preCopyHashes.Keys) {
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $currentHash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
            if ($currentHash -ne $preCopyHashes[$path]) {
                $mutated += $path
            }
        }
    }
    if ($mutated.Count -gt 0) {
        Write-Host ""
        Write-Host "  CRITICAL: Source files were modified during copy:" -ForegroundColor Red
        foreach ($f in $mutated) { Write-Host "    $f" -ForegroundColor Red }
        exit 1
    }

    # ---------------------------------------------------------------------------
    # Compact completion summary
    # ---------------------------------------------------------------------------
    $elapsed   = $stopwatch.Elapsed.ToString('mm\:ss\.fff')
    $resultStr = if ($robocopyExitCode -eq 0) { "OK (exit 0 - source and dest identical)" }
                 else { "OK (exit $robocopyExitCode)" }

    Write-Host ""
    Write-Host "[OK] Test workcopy created: $DestPath" -ForegroundColor Green

    if (-not $VerboseCopy -and ($rbFiles -gt 0 -or $rbDirs -gt 0)) {
        $humanBytes = Format-Bytes -Bytes $rbBytes
        Write-Host ""
        Write-Host ("  Files    : {0:N0}" -f $rbFiles)
        Write-Host ("  Dirs     : {0:N0}" -f $rbDirs)
        Write-Host ("  Bytes    : {0:N0} ({1})" -f $rbBytes, $humanBytes)
    }
    Write-Host "  Elapsed  : $elapsed"
    Write-Host "  Result   : $resultStr"
    Write-Host "  Fidelity : OK" -ForegroundColor Green
    Write-Host "  Immutable: OK" -ForegroundColor Green
}
