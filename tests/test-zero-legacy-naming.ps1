<#
.SYNOPSIS
    Tier 0: Zero-Legacy Naming Static Guard

.DESCRIPTION
    Verifies that ACTIVE current MxAgile code and configuration never produces
    or references legacy DFC / DFC-AI naming.

    This guard checks that:
    - Adapter YAML configs use canonical mxagile/ paths (not dfc/)
    - .mxagile/README.md uses current paths (not dfc/ in active sections)
    - Generator script does not contain dfc/ output paths
    - project-templates do not contain dfc/ platform skill directories
    - .mxagile/agents/maintainer.md correctly marks DFC as LEGACY

    ALLOWED OCCURRENCES (excluded from guard):
    - tests/fixtures/legacy-dfc/** (intentional legacy fixture)
    - docs/migrations/** (migration documentation)
    - docs/architecture.md (CURRENT vs TARGET gap table)
    - docs/injection-contract.md (migration explanation section)
    - .mxagile/skills/system-check.md (stale detection knowledge for old installs)
    - tests/test-injection-contract.ps1 (tests that dfc/ does NOT exist)
    - tests/test-zero-legacy-naming.ps1 (this file)
    - tests/test-legacy-migration.ps1 (migration test)
    - install-mxagile-mercedes.ps1 (external GitHub org URL)
    - tests/run-installer-tests.ps1 (validates external GitHub org URL)
    - .mxagile/agents/maintainer.md (intentional legacy knowledge)

.NOTES
    Do NOT make this a simple grep-for-dfc guard  -- that would break legitimate
    migration knowledge. This guard is SEMANTIC, not syntactic.
#>

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ScriptDir   = Split-Path -Parent $PSScriptRoot
$PassCount   = 0
$FailCount   = 0
$FailDetails = @()

function Assert-True {
    param([string]$TestName, [bool]$Condition, [string]$Message)
    if ($Condition) {
        Write-Host "  PASS: $TestName" -ForegroundColor Green
        $script:PassCount++
    } else {
        Write-Host "  FAIL: $TestName  -- $Message" -ForegroundColor Red
        $script:FailCount++
        $script:FailDetails += "[$TestName] $Message"
    }
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

function Assert-FileNotContains {
    param([string]$TestName, [string]$FilePath, [string]$Pattern)
    $content = Get-Content -LiteralPath $FilePath -Raw -ErrorAction SilentlyContinue
    if ($null -eq $content) {
        Assert-True $TestName $false "File not found: $FilePath"
    } else {
        Assert-True $TestName ($content -notmatch $Pattern) "FORBIDDEN pattern '$Pattern' found in $FilePath  -- legacy naming must not appear in active code"
    }
}

Write-Host ""
Write-Host "=== Zero-Legacy Naming Guard ==="
Write-Host "Verifying active MxAgile code does not produce legacy DFC naming"
Write-Host ""

# =========================================================================
# Section 1: Adapter YAML configs must use mxagile/ paths
# =========================================================================

Write-Host "--- Section 1: Adapter YAML configs ---"

$adapters = @(
    @{ Platform = "claude";    File = ".mxagile/adapters/claude/skills.yaml";    ForbiddenPattern = 'output_dir:\s*"\.claude/skills/dfc' }
    @{ Platform = "codex";     File = ".mxagile/adapters/codex/skills.yaml";     ForbiddenPattern = 'output_dir:\s*"\.agents/skills/dfc' }
    @{ Platform = "grok";      File = ".mxagile/adapters/grok/skills.yaml";      ForbiddenPattern = 'output_dir:\s*"\.grok/skills/dfc' }
    @{ Platform = "opencode";  File = ".mxagile/adapters/opencode/skills.yaml";  ForbiddenPattern = 'output_dir:\s*"\.opencode/skills/dfc' }
    @{ Platform = "hermes";    File = ".mxagile/adapters/hermes/skills.yaml";    ForbiddenPattern = 'output_dir:\s*"\.hermes/skills/dfc' }
)

foreach ($adapter in $adapters) {
    $fullPath = Join-Path $ScriptDir $adapter.File
    Assert-FileNotContains "Adapter $($adapter.Platform): no legacy dfc/ output_dir" $fullPath $adapter.ForbiddenPattern
}

# Verify canonical paths are used instead
Assert-FileContains "Adapter codex: uses mxagile/ output_dir" (Join-Path $ScriptDir ".mxagile/adapters/codex/skills.yaml") 'output_dir:\s*"\.agents/skills/mxagile'
Assert-FileContains "Adapter grok: uses mxagile/ output_dir" (Join-Path $ScriptDir ".mxagile/adapters/grok/skills.yaml") 'output_dir:\s*"\.grok/skills/mxagile'
Assert-FileContains "Adapter opencode: uses mxagile/ output_dir" (Join-Path $ScriptDir ".mxagile/adapters/opencode/skills.yaml") 'output_dir:\s*"\.opencode/skills/mxagile'

Write-Host ""

# =========================================================================
# Section 2: Generator script must not produce dfc/ paths
# =========================================================================

Write-Host "--- Section 2: Generator script ---"

$generatorPath = Join-Path $ScriptDir "scripts/generate-mxagile-platform-skills.ps1"

# Forbidden: hardcoded dfc/ directory paths in output functions
Assert-FileNotContains "Generator: no .agents/skills/dfc/ output" $generatorPath '\.agents\\\\skills\\\\dfc'
Assert-FileNotContains "Generator: no .grok/skills/dfc/ output" $generatorPath '\.grok\\\\skills\\\\dfc'
Assert-FileNotContains "Generator: no .opencode/skills/dfc/ output" $generatorPath '\.opencode\\\\skills\\\\dfc'
Assert-FileNotContains "Generator: no .hermes/skills/dfc/ output" $generatorPath '\.hermes\\\\skills\\\\dfc'

# Allowed: comment explaining the migration (not an output path)
# The .DESCRIPTION comment referencing "dfc/" is documentation, not an output  -- intentionally not checked

Write-Host ""

# =========================================================================
# Section 3: .mxagile/README.md platform table uses current paths
# =========================================================================

Write-Host "--- Section 3: .mxagile/README.md ---"

$readmePath = Join-Path $ScriptDir ".mxagile/README.md"

# In the platform support table, check for legacy paths  -- if they appear as current, that's wrong
# We check for the specific table row patterns that would indicate stale current-labeling
Assert-FileNotContains "README: no Claude dfc/ in platform table" $readmePath '`\.claude/skills/dfc/`'
Assert-FileNotContains "README: no Codex dfc/ in platform table" $readmePath '`\.agents/skills/dfc/`'
Assert-FileNotContains "README: no Grok dfc/ in platform table" $readmePath '`\.grok/skills/dfc/`'
Assert-FileNotContains "README: no OpenCode dfc/ in platform table" $readmePath '`\.opencode/skills/dfc/`'
Assert-FileNotContains "README: no Hermes dfc/ in platform table" $readmePath '`\.hermes/skills/dfc/`'

# Verify current paths appear
Assert-FileContains "README: Claude uses mxagile-* path" $readmePath '`\.claude/skills/mxagile-\*'
Assert-FileContains "README: Codex uses mxagile/ path" $readmePath '`\.agents/skills/mxagile/`'

Write-Host ""

# =========================================================================
# Section 4: project-templates do not contain dfc/ platform skill dirs
# =========================================================================

Write-Host "--- Section 4: project-templates legacy directories ---"

$templateBase = Join-Path $ScriptDir "project-templates"

# Check that dfc/ skill directories do not exist in templates
$legacyTemplateDirs = @(
    "brownfield_spec/.opencode/skills/dfc"
    "brownfield_spec/.agents/skills/dfc"
    "brownfield_spec/.grok/skills/dfc"
    "brownfield_spec/.hermes/skills/dfc"
    "brownfield_spec/.claude/skills/dfc"
)

foreach ($legacyDir in $legacyTemplateDirs) {
    $fullPath = Join-Path $templateBase $legacyDir
    Assert-True "project-templates: $legacyDir does NOT exist" (-not (Test-Path -LiteralPath $fullPath -PathType Container)) "Legacy dfc/ directory found in project-templates: $fullPath"
}

Write-Host ""

# =========================================================================
# Section 5: Maintainer Agent marks DFC as LEGACY
# =========================================================================

Write-Host "--- Section 5: Maintainer Agent legacy labeling ---"

$maintainerPath = Join-Path $ScriptDir ".mxagile/agents/maintainer.md"

Assert-True "Maintainer Agent exists" (Test-Path -LiteralPath $maintainerPath -PathType Leaf) "maintainer.md not found"
Assert-FileContains "Maintainer: marks DFC as legacy" $maintainerPath '(?i)(legacy|historical|predecessor)'
Assert-FileContains "Maintainer: describes current canonical path" $maintainerPath '\.mxagile/'
Assert-FileContains "Maintainer: explicitly prohibits creating dfc/ dirs" $maintainerPath '(?i)do not create.*\.claude/skills/dfc'

Write-Host ""

# =========================================================================
# Section 6: Legacy fixture exists (guard must NOT fail because of it)
# =========================================================================

Write-Host "--- Section 6: Legacy fixture integrity ---"

$fixturePath = Join-Path $ScriptDir "tests/fixtures/legacy-dfc"

Assert-True "Legacy fixture directory exists" (Test-Path -LiteralPath $fixturePath -PathType Container) "tests/fixtures/legacy-dfc/ not found  -- required for migration tests"
Assert-True "Legacy fixture has .MxAgile dir" (Test-Path (Join-Path $fixturePath ".MxAgile") -PathType Container) "Legacy fixture missing .MxAgile/ directory"
Assert-True "Legacy fixture has dfc/ Claude skills" (Test-Path (Join-Path $fixturePath ".claude/skills/dfc") -PathType Container) "Legacy fixture missing .claude/skills/dfc/"
Assert-True "Legacy fixture README exists" (Test-Path (Join-Path $fixturePath "README.md")) "Legacy fixture missing README.md"

Write-Host ""

# =========================================================================
# Final summary
# =========================================================================

Write-Host "=== Zero-Legacy Guard Results ==="
Write-Host "  PASS: $PassCount" -ForegroundColor Green
if ($FailCount -gt 0) {
    Write-Host "  FAIL: $FailCount" -ForegroundColor Red
    foreach ($detail in $FailDetails) {
        Write-Host "    $detail" -ForegroundColor Red
    }
    Write-Host ""
    Write-Host "GUARD FAILED: Active MxAgile code contains unexpected legacy DFC naming." -ForegroundColor Red
    exit 1
} else {
    Write-Host ""
    Write-Host "GUARD PASSED: No unexpected legacy DFC naming in active code." -ForegroundColor Green
    exit 0
}
