<#
.SYNOPSIS
    Tier 1: Legacy DFC Migration Knowledge Test

.DESCRIPTION
    Verifies that MxAgile retains complete, correct knowledge of legacy DFC
    structures — and knows how to detect and migrate them. Exercises the
    tests/fixtures/legacy-dfc/ directory as a representative BEFORE state.

    Three invariants this test enforces:
    1. The legacy fixture represents a valid real-world BEFORE state
    2. The Maintainer Agent carries full migration knowledge
    3. The migration documentation is complete and self-consistent

    This test does NOT run the migration. It verifies that MxAgile has all
    the knowledge required to run it successfully when needed.

.NOTES
    Do not rename or restructure tests/fixtures/legacy-dfc/ without updating
    both this test and mxagile-maintainer.md.
#>

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$TestsDir    = $PSScriptRoot
$ScriptDir   = Split-Path -Parent $TestsDir
$PassCount   = 0
$FailCount   = 0
$FailDetails = @()

function Assert-True {
    param([string]$TestName, [bool]$Condition, [string]$Message)
    if ($Condition) {
        Write-Host "  PASS: $TestName" -ForegroundColor Green
        $script:PassCount++
    } else {
        Write-Host "  FAIL: $TestName — $Message" -ForegroundColor Red
        $script:FailCount++
        $script:FailDetails += "[$TestName] $Message"
    }
}

function Assert-FileExists {
    param([string]$TestName, [string]$Path)
    Assert-True $TestName (Test-Path -LiteralPath $Path) "File not found: $Path"
}

function Assert-DirExists {
    param([string]$TestName, [string]$Path)
    Assert-True $TestName (Test-Path -LiteralPath $Path -PathType Container) "Directory not found: $Path"
}

function Assert-FileContains {
    param([string]$TestName, [string]$FilePath, [string]$Pattern)
    $content = Get-Content -LiteralPath $FilePath -Raw -ErrorAction SilentlyContinue
    if ($null -eq $content) {
        Assert-True $TestName $false "File not found: $FilePath"
    } else {
        Assert-True $TestName ($content -match $Pattern) "Expected pattern '$Pattern' not found in $FilePath"
    }
}

Write-Host ""
Write-Host "=== Legacy DFC Migration Knowledge Test ==="
Write-Host "Verifying MxAgile understands, detects, and can migrate legacy DFC structures"
Write-Host ""

# =========================================================================
# Section 1: Legacy fixture — BEFORE state structure
# =========================================================================

Write-Host "--- Section 1: Legacy fixture BEFORE state ---"

$fixturePath = Join-Path $TestsDir "fixtures/legacy-dfc"

Assert-DirExists  "Fixture: root exists"               $fixturePath
Assert-FileExists "Fixture: project.mpr present"       (Join-Path $fixturePath "project.mpr")
Assert-FileExists "Fixture: README.md present"         (Join-Path $fixturePath "README.md")

# Legacy canonical source directory (uppercase .MxAgile)
Assert-DirExists  "Fixture: .MxAgile/ exists (capital M)"              (Join-Path $fixturePath ".MxAgile")
Assert-DirExists  "Fixture: .MxAgile/skills/ exists"                   (Join-Path $fixturePath ".MxAgile/skills")
Assert-FileExists "Fixture: .MxAgile/skills/discovery.md exists"       (Join-Path $fixturePath ".MxAgile/skills/discovery.md")
Assert-FileExists "Fixture: .MxAgile/skills/refinement.md exists"      (Join-Path $fixturePath ".MxAgile/skills/refinement.md")

# Legacy Claude projections: .claude/skills/dfc/
Assert-DirExists  "Fixture: .claude/skills/dfc/ exists"                (Join-Path $fixturePath ".claude/skills/dfc")
Assert-FileExists "Fixture: .claude/skills/dfc/discovery.md"           (Join-Path $fixturePath ".claude/skills/dfc/discovery.md")
Assert-FileExists "Fixture: .claude/skills/dfc/refinement.md"          (Join-Path $fixturePath ".claude/skills/dfc/refinement.md")

# Legacy Codex projections: .agents/skills/dfc/
Assert-DirExists  "Fixture: .agents/skills/dfc/ exists"                (Join-Path $fixturePath ".agents/skills/dfc")
Assert-FileExists "Fixture: .agents/skills/dfc/discovery.md"           (Join-Path $fixturePath ".agents/skills/dfc/discovery.md")

# Legacy OpenCode projections: .opencode/skills/dfc/
Assert-DirExists  "Fixture: .opencode/skills/dfc/ exists"              (Join-Path $fixturePath ".opencode/skills/dfc")
Assert-FileExists "Fixture: .opencode/skills/dfc/discovery.md"         (Join-Path $fixturePath ".opencode/skills/dfc/discovery.md")

Write-Host ""

# =========================================================================
# Section 2: Legacy fixture file headers prove ownership
# =========================================================================

Write-Host "--- Section 2: Legacy fixture headers (ownership proof) ---"

# Generated projections must carry Source header so safe-to-remove is provable
Assert-FileContains "Claude dfc/discovery.md: has GENERATED header" `
    (Join-Path $fixturePath ".claude/skills/dfc/discovery.md") '# GENERATED'
Assert-FileContains "Claude dfc/discovery.md: has Source: .MxAgile/" `
    (Join-Path $fixturePath ".claude/skills/dfc/discovery.md") 'Source: \.MxAgile/'

Assert-FileContains "Claude dfc/refinement.md: has GENERATED header" `
    (Join-Path $fixturePath ".claude/skills/dfc/refinement.md") '# GENERATED'
Assert-FileContains "Claude dfc/refinement.md: has Source: .MxAgile/" `
    (Join-Path $fixturePath ".claude/skills/dfc/refinement.md") 'Source: \.MxAgile/'

Assert-FileContains "Agents dfc/discovery.md: has GENERATED header" `
    (Join-Path $fixturePath ".agents/skills/dfc/discovery.md") '# GENERATED'
Assert-FileContains "Agents dfc/discovery.md: has Source: .MxAgile/" `
    (Join-Path $fixturePath ".agents/skills/dfc/discovery.md") 'Source: \.MxAgile/'

# Canonical source (.MxAgile/skills/) must NOT have GENERATED header
$dfcSkillContent = Get-Content -LiteralPath (Join-Path $fixturePath ".MxAgile/skills/discovery.md") -Raw
Assert-True "Canonical .MxAgile/skills/discovery.md: no GENERATED header" `
    ($dfcSkillContent -notmatch '# GENERATED') `
    ".MxAgile canonical skills should not have GENERATED headers — they are the source"

Write-Host ""

# =========================================================================
# Section 3: Maintainer Agent carries full legacy knowledge
# =========================================================================

Write-Host "--- Section 3: Maintainer Agent knowledge ---"

$maintainerPath = Join-Path $ScriptDir ".mxagile/agents/mxagile-maintainer.md"

Assert-FileExists "Maintainer Agent exists" $maintainerPath

# Must know the capital-M directory
Assert-FileContains "Maintainer: knows .MxAgile/ (capital M)"     $maintainerPath '\.MxAgile'

# Must know the dfc/ platform path pattern
Assert-FileContains "Maintainer: knows .claude/skills/dfc/"       $maintainerPath '\.claude/skills/dfc'
Assert-FileContains "Maintainer: knows .agents/skills/dfc/"       $maintainerPath '\.agents/skills/dfc'

# Must carry the canonical-current paths
Assert-FileContains "Maintainer: knows .mxagile/ (canonical)"     $maintainerPath '\.mxagile/'
Assert-FileContains "Maintainer: knows .claude/skills/mxagile-*"  $maintainerPath 'mxagile-'

# Must explicitly state it never creates DFC output
Assert-FileContains "Maintainer: has INVARIANT/NEVER creates DFC"   $maintainerPath '(?i)(INVARIANT|NEVER|must not.*creat)'

# Must contain the word "migration" or "migrate"
Assert-FileContains "Maintainer: mentions migration"               $maintainerPath '(?i)migrat'

Write-Host ""

# =========================================================================
# Section 4: Migration documentation completeness
# =========================================================================

Write-Host "--- Section 4: Migration documentation ---"

$migrationDoc = Join-Path $ScriptDir "docs/migrations/dfc-to-mxagile.md"

Assert-FileExists "Migration doc exists: docs/migrations/dfc-to-mxagile.md" $migrationDoc

# Must map old paths to new paths
Assert-FileContains "Migration doc: maps .MxAgile -> .mxagile"    $migrationDoc '\.MxAgile'
Assert-FileContains "Migration doc: maps dfc/ -> mxagile/"        $migrationDoc 'dfc/'
Assert-FileContains "Migration doc: shows target mxagile/ path"   $migrationDoc 'mxagile/'

# Must contain detection criteria
Assert-FileContains "Migration doc: has detection section"         $migrationDoc '(?i)(detect|recogni|identif)'

# Must have migration steps
Assert-FileContains "Migration doc: has steps/procedure"           $migrationDoc '(?i)(step|procedure|how to|migrate)'

Write-Host ""

# =========================================================================
# Section 5: Fixture README explains the context
# =========================================================================

Write-Host "--- Section 5: Fixture README context ---"

$fixtureReadme = Join-Path $fixturePath "README.md"

Assert-FileContains "Fixture README: explains BEFORE state"       $fixtureReadme '(?i)(before|legacy|simulate|represent)'
Assert-FileContains "Fixture README: references .MxAgile"         $fixtureReadme '\.MxAgile'
Assert-FileContains "Fixture README: explains dfc/ directories"   $fixtureReadme 'dfc/'
Assert-FileContains "Fixture README: explains GENERATED header"   $fixtureReadme '(?i)(GENERATED|safe.to.remove|ownership)'

Write-Host ""

# =========================================================================
# Section 6: Detection logic self-consistency
# =========================================================================

Write-Host "--- Section 6: Detection logic cross-check ---"

# Detection criteria in maintainer agent and migration doc should be consistent.
# Both should reference .MxAgile/ (capital M) as the primary legacy indicator.
$maintainerContent = Get-Content -LiteralPath $maintainerPath -Raw
$migrationContent  = Get-Content -LiteralPath $migrationDoc -Raw

Assert-True "Both docs agree: .MxAgile is legacy indicator" `
    ($maintainerContent -match '\.MxAgile' -and $migrationContent -match '\.MxAgile') `
    "Inconsistency: both maintainer.md and migration doc must reference .MxAgile as legacy indicator"

Assert-True "Both docs agree: dfc/ is legacy path" `
    ($maintainerContent -match 'dfc/' -and $migrationContent -match 'dfc/') `
    "Inconsistency: both maintainer.md and migration doc must reference dfc/ as legacy path"

# The GENERATED header format must match between fixture and maintainer knowledge
Assert-True "Maintainer: knows GENERATED header pattern" `
    ($maintainerContent -match '(?i)GENERATED') `
    "Maintainer must know about the '# GENERATED - Source: .MxAgile/' header for safe removal"

Write-Host ""

# =========================================================================
# Final summary
# =========================================================================

Write-Host "=== Legacy Migration Knowledge Test Results ==="
Write-Host "  PASS: $PassCount" -ForegroundColor Green
if ($FailCount -gt 0) {
    Write-Host "  FAIL: $FailCount" -ForegroundColor Red
    foreach ($detail in $FailDetails) {
        Write-Host "    $detail" -ForegroundColor Red
    }
    Write-Host ""
    Write-Host "TEST FAILED: Legacy migration knowledge is incomplete or inconsistent." -ForegroundColor Red
    Write-Host "MxAgile cannot safely migrate legacy DFC projects without complete knowledge." -ForegroundColor Red
    exit 1
} else {
    Write-Host ""
    Write-Host "TEST PASSED: MxAgile has complete knowledge to detect and migrate legacy DFC." -ForegroundColor Green
    exit 0
}
