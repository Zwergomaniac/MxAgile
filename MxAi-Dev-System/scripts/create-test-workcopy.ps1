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
    [int]$Threads = 8
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrEmpty($TestDirName)) {
    $TestDirName = $TemplateName
}

$WorkspaceRoot = Split-Path -Parent $PSScriptRoot
$SourcePath    = Join-Path $WorkspaceRoot "project-templates\$TemplateName"
$DestPath      = Join-Path $WorkspaceRoot ".testing-$TestDirName"

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
# Credential notice
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
        Remove-Item -LiteralPath $DestPath -Recurse -Force
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
    $robocopyArgs.Add('/BYTES')       # report sizes in bytes

    foreach ($name in $ExcludeByName) {
        $robocopyArgs.Add('/XD')
        $robocopyArgs.Add($name)
    }
    foreach ($path in $ExcludeByPath) {
        $robocopyArgs.Add('/XD')
        $robocopyArgs.Add($path)
    }

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    & robocopy @robocopyArgs
    $robocopyExitCode = $LASTEXITCODE
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
        Write-Host ""
        Write-Host "[FAILED] Robocopy exited with code $robocopyExitCode - destination may be incomplete." -ForegroundColor Red
        exit 1
    }

    Write-Host ""
    Write-Host "  Elapsed : $($stopwatch.Elapsed.ToString('mm\:ss\.fff'))" -ForegroundColor Green

    # ---------------------------------------------------------------------------
    # Fixture fidelity validation
    # ---------------------------------------------------------------------------
    Write-Host "  Validating fixture fidelity..."
    $fidelityErrors = [System.Collections.Generic.List[string]]::new()

    # .mpr must survive
    $destMpr = @(Get-ChildItem -LiteralPath $DestPath -Filter '*.mpr' -File -ErrorAction SilentlyContinue)
    if ($destMpr.Count -eq 0) {
        $fidelityErrors.Add("No .mpr file found in destination")
    }

    # .dfc-ai must survive (brownfield migration marker)
    $srcDfc = Join-Path $SourcePath '.dfc-ai'
    $dstDfc = Join-Path $DestPath '.dfc-ai'
    if ((Test-Path -LiteralPath $srcDfc -PathType Container) -and
        -not (Test-Path -LiteralPath $dstDfc -PathType Container)) {
        $fidelityErrors.Add(".dfc-ai/ missing in destination (required for brownfield migration tests)")
    }

    # planning/ must survive
    $srcPlan = Join-Path $SourcePath 'planning'
    $dstPlan = Join-Path $DestPath 'planning'
    if ((Test-Path -LiteralPath $srcPlan -PathType Container) -and
        -not (Test-Path -LiteralPath $dstPlan -PathType Container)) {
        $fidelityErrors.Add("planning/ missing in destination")
    }

    # mprcontents/ must survive
    $srcMprc = Join-Path $SourcePath 'mprcontents'
    $dstMprc = Join-Path $DestPath 'mprcontents'
    if ((Test-Path -LiteralPath $srcMprc -PathType Container) -and
        -not (Test-Path -LiteralPath $dstMprc -PathType Container)) {
        $fidelityErrors.Add("mprcontents/ missing in destination")
    }

    # No .mxagile/lifecycle.yaml introduced if source did not have one
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
    Write-Host "  Fidelity: OK" -ForegroundColor Green

    # ---------------------------------------------------------------------------
    # Source immutability check
    # ---------------------------------------------------------------------------
    Write-Host "  Checking source immutability..."
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
    Write-Host "  Source immutability: OK" -ForegroundColor Green

    Write-Host ""
    Write-Host "[OK] Test workcopy created: $DestPath" -ForegroundColor Green
}
