<#
.SYNOPSIS
    Lifecycle Canonicalization Consistency Tests

.DESCRIPTION
    Validates that .mxagile/lifecycle.yaml is present, structurally sound, and
    consistent with the rest of the MxAgile framework.

    What is tested:
    1. lifecycle.yaml exists and contains required keys
    2. Canonical phase identifiers are unique and all present
    3. initial_phase is a defined phase
    4. All transition targets (next, returns_to) exist as phases or terminal states
    5. terminal_states is non-empty
    6. orchestrator.md references lifecycle.yaml
    7. system-check references lifecycle.yaml for the lifecycle question
    8. README.md lists lifecycle.yaml in the directory structure
    9. architecture.md does not contain stale non-canonical phase names

.NOTES
    Uses pattern matching against file content, not a YAML parser.
    A malformed YAML that contains all required key names will pass structural
    checks here; use a separate YAML linter for schema validation.
#>

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$TestsDir  = $PSScriptRoot
$ScriptDir = Split-Path -Parent $TestsDir
$PassCount   = 0
$FailCount   = 0
$FailDetails = @()

function Assert-True {
    param([string]$TestName, [bool]$Condition, [string]$Message)
    if ($Condition) {
        Write-Host "  PASS: $TestName" -ForegroundColor Green
        $script:PassCount++
    } else {
        Write-Host "  FAIL: $TestName -- $Message" -ForegroundColor Red
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
        Assert-True $TestName ($content -notmatch $Pattern) "Forbidden pattern '$Pattern' found in $FilePath"
    }
}

$lifecyclePath    = Join-Path $ScriptDir ".mxagile/lifecycle.yaml"
$orchestratorPath = Join-Path $ScriptDir ".mxagile/orchestrator.md"
$systemCheckPath  = Join-Path $ScriptDir ".mxagile/skills/system-check.md"
$readmePath       = Join-Path $ScriptDir ".mxagile/README.md"

Write-Host ""
Write-Host "=== Lifecycle Canonicalization Tests ==="
Write-Host "Verifying .mxagile/lifecycle.yaml is the canonical lifecycle source"
Write-Host ""

# =========================================================================
# Section 1: lifecycle.yaml exists and has required top-level keys
# =========================================================================

Write-Host "--- Section 1: lifecycle.yaml structure ---"

Assert-True "lifecycle.yaml exists" (Test-Path -LiteralPath $lifecyclePath) "File not found: $lifecyclePath"

$lcContent = $null
if (Test-Path -LiteralPath $lifecyclePath) {
    $lcContent = Get-Content -LiteralPath $lifecyclePath -Raw

    Assert-True "lifecycle.yaml: schema_version 1"          ($lcContent -match 'schema_version:\s*1')           "Missing 'schema_version: 1'"
    Assert-True "lifecycle.yaml: unit_of_progression"       ($lcContent -match 'unit_of_progression:')          "Missing 'unit_of_progression'"
    Assert-True "lifecycle.yaml: top-level lifecycle block" ($lcContent -match '(?m)^lifecycle:')               "Missing top-level 'lifecycle:' key"
    Assert-True "lifecycle.yaml: initial_phase present"     ($lcContent -match 'initial_phase:')                "Missing 'initial_phase'"
    Assert-True "lifecycle.yaml: initial_phase is discovery" ($lcContent -match 'initial_phase:\s*discovery')   "initial_phase must be 'discovery'"
    Assert-True "lifecycle.yaml: terminal_states present"   ($lcContent -match 'terminal_states:')             "Missing 'terminal_states'"
    Assert-True "lifecycle.yaml: done is terminal state"    ($lcContent -match 'terminal_states:.*done')        "terminal_states must include 'done'"
    Assert-True "lifecycle.yaml: return_routing present"    ($lcContent -match 'return_routing:')               "Missing 'return_routing'"
    Assert-True "lifecycle.yaml: change_propagation present" ($lcContent -match 'change_propagation:')          "Missing 'change_propagation'"
}

Write-Host ""

# =========================================================================
# Section 2: Canonical phase identifiers all present and unique
# =========================================================================

Write-Host "--- Section 2: Canonical phase identifiers ---"

$canonicalPhases = @('discovery', 'refinement', 'ready', 'implementing', 'verifying')

if ($null -ne $lcContent) {
    foreach ($phaseName in $canonicalPhases) {
        # Phase must appear as a YAML key (indented line followed by colon)
        $phasePattern = "(?m)^\s+" + [regex]::Escape($phaseName) + ":"
        Assert-True ("lifecycle.yaml: phase '" + $phaseName + "' defined") `
            ([regex]::IsMatch($lcContent, $phasePattern)) `
            ("Phase '" + $phaseName + "' not found as YAML key")
    }

    # Each phase key must appear exactly once (no duplicates)
    foreach ($phaseName in $canonicalPhases) {
        $phasePattern = "(?m)^\s+" + [regex]::Escape($phaseName) + ":"
        $count = ([regex]::Matches($lcContent, $phasePattern)).Count
        Assert-True ("lifecycle.yaml: phase '" + $phaseName + "' not duplicated") `
            ($count -eq 1) `
            ("Phase '" + $phaseName + "' appears $count times (expected 1)")
    }
}

Write-Host ""

# =========================================================================
# Section 3: Transition targets reference valid phases or terminal states
# =========================================================================

Write-Host "--- Section 3: Transition target validity ---"

if ($null -ne $lcContent) {
    $validTargets = $canonicalPhases + @('done')

    # Find all next: [...] and returns_to: [...] list values
    $transPattern = '(?m)^\s+(next|returns_to):\s*\[([^\]]*)\]'
    $transMatches = [regex]::Matches($lcContent, $transPattern)

    foreach ($tm in $transMatches) {
        $rawTargets = $tm.Groups[2].Value
        $parts = $rawTargets.Split(',')
        foreach ($part in $parts) {
            $target = $part.Trim()
            if ($target.Length -gt 0) {
                Assert-True ("Transition target '" + $target + "' is a known phase or terminal state") `
                    ($validTargets -contains $target) `
                    ("Unknown target '" + $target + "' -- must be a canonical phase or terminal state")
            }
        }
    }
}

Write-Host ""

# =========================================================================
# Section 4: Return routing covers all three return directions
# =========================================================================

Write-Host "--- Section 4: Return routing semantics ---"

if ($null -ne $lcContent) {
    Assert-True "return_routing: has principle" `
        ($lcContent -match 'return_routing:') `
        "return_routing block must exist"

    Assert-True "return_routing: routes to implementing" `
        ($lcContent -match 'return_to:\s*implementing') `
        "return_routing must include a rule returning to 'implementing'"

    Assert-True "return_routing: routes to refinement" `
        ($lcContent -match 'return_to:\s*refinement') `
        "return_routing must include a rule returning to 'refinement'"

    Assert-True "return_routing: routes to discovery" `
        ($lcContent -match 'return_to:\s*discovery') `
        "return_routing must include a rule returning to 'discovery'"
}

Write-Host ""

# =========================================================================
# Section 5: Change propagation status vocabulary
# =========================================================================

Write-Host "--- Section 5: Change propagation vocabulary ---"

if ($null -ne $lcContent) {
    $requiredStatuses = @('CURRENT', 'CHANGED', 'IMPACT_REVIEW_REQUIRED', 'STALE', 'REOPENED', 'VERIFIED')
    foreach ($status in $requiredStatuses) {
        Assert-True ("change_propagation: status '" + $status + "' defined") `
            ($lcContent -match $status) `
            ("Status vocabulary missing '" + $status + "'")
    }

    Assert-True "change_propagation: mockup_changed example present" `
        ($lcContent -match 'mockup_changed:') `
        "Missing mockup_changed example in change_propagation"

    Assert-True "change_propagation: spec change example present" `
        ($lcContent -match 'spec_changed') `
        "Missing spec_changed example in change_propagation"
}

Write-Host ""

# =========================================================================
# Section 6: orchestrator.md references lifecycle.yaml
# =========================================================================

Write-Host "--- Section 6: orchestrator.md references lifecycle.yaml ---"

Assert-True "orchestrator.md exists" (Test-Path -LiteralPath $orchestratorPath) "orchestrator.md not found: $orchestratorPath"
Assert-FileContains "orchestrator.md: references lifecycle.yaml" $orchestratorPath 'lifecycle\.yaml'

Write-Host ""

# =========================================================================
# Section 7: system-check references lifecycle.yaml for lifecycle question
# =========================================================================

Write-Host "--- Section 7: system-check lifecycle question references lifecycle.yaml ---"

Assert-True "system-check.md exists" (Test-Path -LiteralPath $systemCheckPath) "system-check.md not found"

if (Test-Path -LiteralPath $systemCheckPath) {
    $scContent = Get-Content -LiteralPath $systemCheckPath -Raw

    Assert-True "system-check: lifecycle question references lifecycle.yaml" `
        ($scContent -match 'lifecycle\.yaml') `
        "system-check Section H lifecycle question must reference lifecycle.yaml"

    # The H.3 block should reference lifecycle.yaml not orchestrator.md for the expected answer
    $h3Block = [regex]::Match($scContent, '(?s)3\.\s+\*\*Canonical lifecycle\*\*.*?PASS / FAIL / UNKNOWN')
    if ($h3Block.Success) {
        Assert-True "system-check: H.3 block references lifecycle.yaml" `
            ($h3Block.Value -match 'lifecycle\.yaml') `
            "The H.3 question block must reference lifecycle.yaml"
    } else {
        Assert-True "system-check: H.3 question block found" $false `
            "Could not locate H.3 lifecycle question block -- question text may have changed"
    }
}

Write-Host ""

# =========================================================================
# Section 8: README.md lists lifecycle.yaml
# =========================================================================

Write-Host "--- Section 8: README.md directory listing ---"

Assert-True ".mxagile/README.md exists" (Test-Path -LiteralPath $readmePath) "README.md not found"
Assert-FileContains ".mxagile/README.md: lists lifecycle.yaml" $readmePath 'lifecycle\.yaml'

Write-Host ""

# =========================================================================
# Section 9: No stale non-canonical phase names in active documentation
# =========================================================================

Write-Host "--- Section 9: No stale phase names in architecture.md ---"

$archPath = Join-Path $ScriptDir "docs/architecture.md"
if (Test-Path -LiteralPath $archPath) {
    # The old TARGET diagram had these non-canonical identifiers
    Assert-FileNotContains "architecture.md: no 'RE[Requirements]' node from old diagram" `
        $archPath 'RE\[Requirements\]'

    Assert-FileNotContains "architecture.md: no 'Discovery through Convergence' phrase" `
        $archPath 'Discovery through Convergence'

    # architecture.md should reference lifecycle.yaml as the canonical source
    Assert-FileContains "architecture.md: references lifecycle.yaml" `
        $archPath 'lifecycle\.yaml'
}

Write-Host ""

# =========================================================================
# Final summary
# =========================================================================

Write-Host "=== Lifecycle Canonicalization Test Results ==="
Write-Host "  PASS: $PassCount" -ForegroundColor Green
if ($FailCount -gt 0) {
    Write-Host "  FAIL: $FailCount" -ForegroundColor Red
    foreach ($detail in $FailDetails) {
        Write-Host "    $detail" -ForegroundColor Red
    }
    Write-Host ""
    Write-Host "TEST FAILED: Lifecycle canonical source is missing or inconsistent." -ForegroundColor Red
    exit 1
} else {
    Write-Host ""
    Write-Host "TEST PASSED: lifecycle.yaml is present, structurally sound, and consistently referenced." -ForegroundColor Green
    exit 0
}
