<#
.SYNOPSIS
    MxAgile Brownfield Artifact Canonicalization Orchestrator.

.DESCRIPTION
    Converts legacy planning/stories/*.md requirements and planning/checklists/*.yaml
    tasks into canonical requirements/*.yml and planning/tasks/*.yml.

    This is a semantic conversion, not a file relocation.

    The canonicalize_artifacts.py engine does the actual parsing and writing.
    This script manages the lifecycle: state transitions, pre/post checks, and
    the confirmation gate before source retirement.

    Safety contract:
    - Source files are NEVER deleted or modified by this script.
    - Source retirement requires explicit -RetireSource switch AND user confirmation.
    - Canonicalization state is persisted in .mxagile/migration/canonicalization-state.yaml.
    - Re-running is safe: already-converted files are skipped.

.PARAMETER ProjectRoot
    Path to the project to canonicalize. Defaults to current directory.

.PARAMETER Phase
    Which artifact type to convert: requirements, tasks, or all (default).

.PARAMETER DryRun
    Print what would be done without writing any files.

.PARAMETER ValidateOnly
    Validate existing canonical artifacts without converting anything.

.PARAMETER RetireSource
    After successful conversion and validation, mark source files as archived.
    Requires explicit confirmation prompt.

.EXAMPLE
    # Dry run — see what will be converted
    .\migrate-stories.ps1 -DryRun

.EXAMPLE
    # Convert requirements in the current project
    .\migrate-stories.ps1 -Phase requirements

.EXAMPLE
    # Convert all artifacts and validate
    .\migrate-stories.ps1

.EXAMPLE
    # Validate existing canonical artifacts
    .\migrate-stories.ps1 -ValidateOnly
#>

[CmdletBinding()]
param(
    [string]$ProjectRoot = $PWD.Path,
    [ValidateSet("requirements", "tasks", "all")]
    [string]$Phase = "all",
    [switch]$DryRun,
    [switch]$ValidateOnly,
    [switch]$RetireSource
)

$ErrorActionPreference = "Stop"

$ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
$EngineScript = Join-Path (Split-Path -Parent $PSScriptRoot) "scripts\canonicalize_artifacts.py"
# If running from scripts/ directly, adjust path
if (-not (Test-Path -LiteralPath $EngineScript)) {
    $EngineScript = Join-Path $PSScriptRoot "canonicalize_artifacts.py"
}

$StateFile = Join-Path $ProjectRoot ".mxagile\migration\canonicalization-state.yaml"
$StatesDir = Join-Path $ProjectRoot ".mxagile\migration"

function Write-Step {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Cyan
}

function Write-Ok {
    param([string]$Message)
    Write-Host "  OK: $Message" -ForegroundColor Green
}

function Write-Fail {
    param([string]$Message)
    Write-Host "  FAIL: $Message" -ForegroundColor Red
}

function Write-Warn {
    param([string]$Message)
    Write-Host "  WARN: $Message" -ForegroundColor Yellow
}

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------

Write-Step "=== MxAgile Artifact Canonicalization ==="
Write-Host "  Project root: $ProjectRoot"
Write-Host "  Phase:        $Phase"
Write-Host "  Dry-run:      $DryRun"
Write-Host ""

if (-not (Test-Path -LiteralPath $ProjectRoot)) {
    Write-Fail "Project root not found: $ProjectRoot"
    exit 1
}

if (-not (Test-Path -LiteralPath $EngineScript)) {
    Write-Fail "Conversion engine not found: $EngineScript"
    Write-Host "  Expected: scripts/canonicalize_artifacts.py" -ForegroundColor Red
    exit 1
}

# Check Python is available
$pythonCmd = $null
foreach ($cmd in @("python", "python3", "py")) {
    try {
        $ver = & $cmd --version 2>&1
        if ($LASTEXITCODE -eq 0 -and $ver -match "Python 3") {
            $pythonCmd = $cmd
            break
        }
    } catch {}
}
if (-not $pythonCmd) {
    Write-Fail "Python 3 is required. Install Python 3 and ensure it is on PATH."
    exit 1
}

Write-Ok "Python found: $pythonCmd"

# Check migration framework state — canonicalization only runs after framework migration
$MxAgileStateFile = Join-Path $ProjectRoot ".mxagile\migration\state.yaml"
if (Test-Path -LiteralPath $MxAgileStateFile) {
    $stateContent = Get-Content -LiteralPath $MxAgileStateFile -Raw
    if ($stateContent -match "status:\s*in_progress") {
        Write-Warn "Framework migration is still in_progress."
        Write-Host "  Artifact canonicalization should run AFTER framework migration is complete." -ForegroundColor Yellow
        Write-Host "  Proceed only if you are running canonicalization in parallel with a completed migration." -ForegroundColor Yellow
        Write-Host ""
    }
} else {
    Write-Warn "No .mxagile/migration/state.yaml found. Verify this project has MxAgile installed."
}

# ---------------------------------------------------------------------------
# Validate-only mode
# ---------------------------------------------------------------------------

if ($ValidateOnly) {
    Write-Step "--- Validating canonical artifacts ---"
    & $pythonCmd $EngineScript --project-root $ProjectRoot --validate-output
    if ($LASTEXITCODE -ne 0) {
        Write-Fail "Validation found errors."
        exit 1
    }
    Write-Ok "Validation passed."
    exit 0
}

# ---------------------------------------------------------------------------
# Pre-conversion inventory
# ---------------------------------------------------------------------------

$StoriesDir = Join-Path $ProjectRoot "planning\stories"
$ChecklistsDir = Join-Path $ProjectRoot "planning\checklists"
$RequirementsDir = Join-Path $ProjectRoot "requirements"
$TasksDir = Join-Path $ProjectRoot "planning\tasks"

Write-Step "--- Pre-conversion inventory ---"

$storyCount = 0
$checklistCount = 0
if (Test-Path -LiteralPath $StoriesDir) {
    $storyCount = @(Get-ChildItem -Path $StoriesDir -Filter "*.md" -File).Count
    Write-Host "  planning/stories/*.md:              $storyCount files"
}
if (Test-Path -LiteralPath $ChecklistsDir) {
    $checklistCount = @(Get-ChildItem -Path $ChecklistsDir -Filter "*.yaml" -File |
        Where-Object { $_.Name -notmatch "template" }).Count
    Write-Host "  planning/checklists/*.yaml:         $checklistCount files"
}

$existingReqCount = 0
if (Test-Path -LiteralPath $RequirementsDir) {
    $existingReqCount = @(Get-ChildItem -Path $RequirementsDir -Filter "REQ-*.yml" -File).Count
    Write-Host "  requirements/REQ-*.yml (existing):  $existingReqCount files"
}
$existingTaskCount = 0
if (Test-Path -LiteralPath $TasksDir) {
    $existingTaskCount = @(Get-ChildItem -Path $TasksDir -Filter "TASK-*.yml" -File).Count
    Write-Host "  planning/tasks/TASK-*.yml (existing): $existingTaskCount files"
}

Write-Host ""

if ($storyCount -eq 0 -and $checklistCount -eq 0) {
    Write-Ok "No legacy artifacts to convert."
    exit 0
}

# ---------------------------------------------------------------------------
# Dry-run mode
# ---------------------------------------------------------------------------

if ($DryRun) {
    Write-Step "--- Dry-run conversion preview ---"
    & $pythonCmd $EngineScript --project-root $ProjectRoot --phase $Phase --dry-run
    if ($LASTEXITCODE -ne 0) {
        Write-Fail "Dry-run failed."
        exit 1
    }
    Write-Host ""
    Write-Ok "Dry-run complete. No files were written."
    Write-Host "  Run without -DryRun to perform the actual conversion." -ForegroundColor Cyan
    exit 0
}

# ---------------------------------------------------------------------------
# Conversion
# ---------------------------------------------------------------------------

Write-Step "--- Running semantic conversion ---"
& $pythonCmd $EngineScript --project-root $ProjectRoot --phase $Phase
if ($LASTEXITCODE -ne 0) {
    Write-Fail "Conversion engine reported errors. See output above."
    exit 1
}

Write-Host ""
Write-Step "--- Post-conversion validation ---"
& $pythonCmd $EngineScript --project-root $ProjectRoot --validate-output
if ($LASTEXITCODE -ne 0) {
    Write-Fail "Post-conversion validation failed. Canonical artifacts have errors."
    Write-Host "  Source files have NOT been modified. Fix errors and retry." -ForegroundColor Yellow
    exit 1
}

# ---------------------------------------------------------------------------
# Update artifact_canonicalization in state.yaml
# ---------------------------------------------------------------------------

if (Test-Path -LiteralPath $MxAgileStateFile) {
    $stateContent = Get-Content -LiteralPath $MxAgileStateFile -Raw
    if ($stateContent -match "artifact_canonicalization:\s*pending") {
        if (-not $DryRun) {
            $updated = $stateContent -replace "artifact_canonicalization:\s*pending", "artifact_canonicalization: complete"
            Set-Content -LiteralPath $MxAgileStateFile -Value $updated -Encoding UTF8
            Write-Ok "Updated artifact_canonicalization: complete in state.yaml"
        }
    } elseif ($stateContent -match "artifact_canonicalization:\s*in_progress") {
        if (-not $DryRun) {
            $updated = $stateContent -replace "artifact_canonicalization:\s*in_progress", "artifact_canonicalization: complete"
            Set-Content -LiteralPath $MxAgileStateFile -Value $updated -Encoding UTF8
            Write-Ok "Updated artifact_canonicalization: complete in state.yaml"
        }
    }
}

# ---------------------------------------------------------------------------
# Source retirement (optional, requires explicit confirmation)
# ---------------------------------------------------------------------------

if ($RetireSource) {
    Write-Host ""
    Write-Step "--- Source retirement ---"
    Write-Host "  Source files are preserved as authoritative audit trail." -ForegroundColor Yellow
    Write-Host "  Source retirement adds an 'archived: true' marker to the frontmatter." -ForegroundColor Yellow
    Write-Host "  This is reversible — files are NOT deleted." -ForegroundColor Yellow
    Write-Host ""
    $confirm = Read-Host "  Type 'RETIRE' to proceed with source retirement"
    if ($confirm -ne "RETIRE") {
        Write-Warn "Source retirement cancelled."
    } else {
        Write-Step "  Marking source files as archived..."
        if (Test-Path -LiteralPath $StoriesDir) {
            Get-ChildItem -Path $StoriesDir -Filter "REQ-*.md" -File | ForEach-Object {
                $content = Get-Content -LiteralPath $_.FullName -Raw
                if ($content -notmatch "archived:\s*true") {
                    if ($content.StartsWith("---")) {
                        $updated = $content -replace "^---", "---`narchived: true"
                    } else {
                        $updated = "---`narchived: true`n---`n" + $content
                    }
                    Set-Content -LiteralPath $_.FullName -Value $updated -Encoding UTF8
                    Write-Ok "Archived: $($_.Name)"
                }
            }
        }
        Write-Ok "Source retirement complete."
    }
}

Write-Host ""
Write-Step "=== Canonicalization complete ==="
Write-Host "  Canonical artifacts are in requirements/ and planning/tasks/"
Write-Host "  Run: python scripts/build_artifact_index.py <project-root>"
Write-Host "  to rebuild the artifact index with the new canonical data."
Write-Host ""
exit 0
