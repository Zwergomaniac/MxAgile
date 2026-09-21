<#
.SYNOPSIS
    Tier 1: Managed Block Fixture Tests

.DESCRIPTION
    Tests the Apply-ManagedBlock semantics of apply-project-agent-instructions.ps1.

    Each fixture creates a temp directory with a dummy .mpr file, creates the
    relevant instruction files with fixture content, runs the script, and validates
    the result.

    Fixtures:
      A - No existing block: block appended at end
      B - User content before block (new file): block appended, user content preserved
      C - User content before and after existing block: block replaced, both preserved
      D - Second installation (idempotency): exactly one block, no duplicates
      E - Malformed marker (START without END): script must fail with non-zero exit
      F - Old marker migration: old markers replaced with new, user content preserved
#>

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ScriptDir = Split-Path -Parent $PSScriptRoot
$ApplyScript = Join-Path $ScriptDir "scripts\apply-project-agent-instructions.ps1"

if (-not (Test-Path -LiteralPath $ApplyScript)) {
    Write-Error "apply-project-agent-instructions.ps1 not found at: $ApplyScript"
    exit 1
}

$PassCount = 0
$FailCount = 0
$FailDetails = @()

function New-TestProject {
    $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ("mxagile-test-" + [System.IO.Path]::GetRandomFileName())
    New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null

    # Dummy .mpr file (satisfies preflight check)
    [System.IO.File]::WriteAllText((Join-Path $tmpDir "TestProject.mpr"), "DUMMY_MPR")

    # Minimal AGENT.md
    [System.IO.File]::WriteAllText(
        (Join-Path $tmpDir "AGENT.md"),
        "# Test Agent`r`nAgent instructions for testing.",
        [System.Text.UTF8Encoding]::new($false)
    )

    # Required empty placeholders (as mxagile-init.ps1 would create)
    [System.IO.File]::WriteAllText((Join-Path $tmpDir "AGENTS.md"), "", [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::WriteAllText((Join-Path $tmpDir "CLAUDE.md"), "", [System.Text.UTF8Encoding]::new($false))

    return $tmpDir
}

function Remove-TestProject {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path) {
        Remove-Item -LiteralPath $Path -Recurse -Force
    }
}

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

function Count-Occurrences {
    param([string]$Text, [string]$Pattern)
    return ([regex]::Matches($Text, [regex]::Escape($Pattern))).Count
}

$NewStart = "<!-- MXAGILE:MANAGED:START -->"
$NewEnd   = "<!-- MXAGILE:MANAGED:END -->"
$OldStart = "<!-- BEGIN PROJECT AGENT INSTRUCTIONS -->"
$OldEnd   = "<!-- END PROJECT AGENT INSTRUCTIONS -->"

# =============================================================================
# Fixture A  -- No existing instruction file content (empty placeholders)
# =============================================================================
Write-Host "`nFixture A  -- Empty placeholder files (no existing block)" -ForegroundColor Cyan

$tmpA = New-TestProject
try {
    & powershell.exe -NonInteractive -NoProfile -File $ApplyScript -ProjectRoot $tmpA
    if ($LASTEXITCODE -ne 0) {
        Assert-True "A: script succeeds" $false "Script exited with code $LASTEXITCODE"
    }

    $agentsContent = Get-Content -LiteralPath (Join-Path $tmpA "AGENTS.md") -Raw
    $claudeContent = Get-Content -LiteralPath (Join-Path $tmpA "CLAUDE.md") -Raw

    Assert-True "A: AGENTS.md contains START marker"   ($agentsContent -match [regex]::Escape($NewStart)) "START marker not found"
    Assert-True "A: AGENTS.md contains END marker"     ($agentsContent -match [regex]::Escape($NewEnd))   "END marker not found"
    Assert-True "A: AGENTS.md exactly 1 START marker"  ((Count-Occurrences $agentsContent $NewStart) -eq 1) "Expected 1 START, found $(Count-Occurrences $agentsContent $NewStart)"
    Assert-True "A: AGENTS.md exactly 1 END marker"    ((Count-Occurrences $agentsContent $NewEnd)   -eq 1) "Expected 1 END, found $(Count-Occurrences $agentsContent $NewEnd)"
    Assert-True "A: CLAUDE.md contains START marker"   ($claudeContent  -match [regex]::Escape($NewStart)) "CLAUDE.md START marker not found"
    Assert-True "A: CLAUDE.md contains END marker"     ($claudeContent  -match [regex]::Escape($NewEnd))   "CLAUDE.md END marker not found"
} finally {
    Remove-TestProject $tmpA
}

# =============================================================================
# Fixture B  -- User content BEFORE block (pre-existing user content, no block)
# =============================================================================
Write-Host "`nFixture B  -- User content before block (no existing block)" -ForegroundColor Cyan

$tmpB = New-TestProject
try {
    [System.IO.File]::WriteAllText(
        (Join-Path $tmpB "AGENTS.md"),
        "USER_CONTENT_BEFORE_93817`n",
        [System.Text.UTF8Encoding]::new($false)
    )

    & powershell.exe -NonInteractive -NoProfile -File $ApplyScript -ProjectRoot $tmpB
    if ($LASTEXITCODE -ne 0) {
        Assert-True "B: script succeeds" $false "Script exited with code $LASTEXITCODE"
    }

    $agentsContent = Get-Content -LiteralPath (Join-Path $tmpB "AGENTS.md") -Raw

    Assert-True "B: user content preserved"           ($agentsContent -match "USER_CONTENT_BEFORE_93817") "User content missing"
    Assert-True "B: managed block present"            ($agentsContent -match [regex]::Escape($NewStart))  "START marker missing"
    Assert-True "B: exactly 1 START marker"           ((Count-Occurrences $agentsContent $NewStart) -eq 1) "Expected 1 START"
    Assert-True "B: user content appears before block" ($agentsContent.IndexOf("USER_CONTENT_BEFORE_93817") -lt $agentsContent.IndexOf($NewStart)) "User content should be before managed block"
} finally {
    Remove-TestProject $tmpB
}

# =============================================================================
# Fixture C  -- User content BEFORE and AFTER existing block (replace block)
# =============================================================================
Write-Host "`nFixture C  -- User content before and after existing block (replace)" -ForegroundColor Cyan

$tmpC = New-TestProject
try {
    $fixtureC = @"
USER_CONTENT_BEFORE_93817

<!-- MXAGILE:MANAGED:START -->
Old content here.
<!-- MXAGILE:MANAGED:END -->

USER_CONTENT_AFTER_48321
"@
    [System.IO.File]::WriteAllText(
        (Join-Path $tmpC "AGENTS.md"),
        $fixtureC,
        [System.Text.UTF8Encoding]::new($false)
    )

    & powershell.exe -NonInteractive -NoProfile -File $ApplyScript -ProjectRoot $tmpC
    if ($LASTEXITCODE -ne 0) {
        Assert-True "C: script succeeds" $false "Script exited with code $LASTEXITCODE"
    }

    $agentsContent = Get-Content -LiteralPath (Join-Path $tmpC "AGENTS.md") -Raw

    Assert-True "C: content-before preserved"   ($agentsContent -match "USER_CONTENT_BEFORE_93817") "Before content missing"
    Assert-True "C: content-after preserved"    ($agentsContent -match "USER_CONTENT_AFTER_48321")  "After content missing"
    Assert-True "C: exactly 1 START marker"     ((Count-Occurrences $agentsContent $NewStart) -eq 1) "Expected 1 START"
    Assert-True "C: exactly 1 END marker"       ((Count-Occurrences $agentsContent $NewEnd)   -eq 1) "Expected 1 END"
    Assert-True "C: old block content removed"  (-not ($agentsContent -match "Old content here\."))  "Old block content still present"
    Assert-True "C: AGENT.md content in block"  ($agentsContent -match "Agent instructions for testing") "AGENT.md content not in block"
} finally {
    Remove-TestProject $tmpC
}

# =============================================================================
# Fixture D  -- Idempotency (second run produces exactly one block)
# =============================================================================
Write-Host "`nFixture D  -- Idempotency (second run)" -ForegroundColor Cyan

$tmpD = New-TestProject
try {
    [System.IO.File]::WriteAllText(
        (Join-Path $tmpD "AGENTS.md"),
        "User content before.`n",
        [System.Text.UTF8Encoding]::new($false)
    )

    # First run
    & powershell.exe -NonInteractive -NoProfile -File $ApplyScript -ProjectRoot $tmpD
    # Second run
    & powershell.exe -NonInteractive -NoProfile -File $ApplyScript -ProjectRoot $tmpD
    if ($LASTEXITCODE -ne 0) {
        Assert-True "D: second run succeeds" $false "Script exited with code $LASTEXITCODE"
    }

    $agentsContent = Get-Content -LiteralPath (Join-Path $tmpD "AGENTS.md") -Raw

    Assert-True "D: exactly 1 START after 2 runs" ((Count-Occurrences $agentsContent $NewStart) -eq 1) "Expected 1 START, got $(Count-Occurrences $agentsContent $NewStart)"
    Assert-True "D: exactly 1 END after 2 runs"   ((Count-Occurrences $agentsContent $NewEnd)   -eq 1) "Expected 1 END, got $(Count-Occurrences $agentsContent $NewEnd)"
    Assert-True "D: user content preserved"        ($agentsContent -match "User content before\.") "User content missing"
} finally {
    Remove-TestProject $tmpD
}

# =============================================================================
# Fixture E  -- Malformed marker (START without END)  -- must FAIL
# =============================================================================
Write-Host "`nFixture E  -- Malformed block (START without END, must fail)" -ForegroundColor Cyan

$tmpE = New-TestProject
try {
    [System.IO.File]::WriteAllText(
        (Join-Path $tmpE "AGENTS.md"),
        "User content.`n`n<!-- MXAGILE:MANAGED:START -->`nOrphaned start.",
        [System.Text.UTF8Encoding]::new($false)
    )

    $output = & powershell.exe -NonInteractive -NoProfile -File $ApplyScript -ProjectRoot $tmpE 2>&1
    $exitCode = $LASTEXITCODE

    Assert-True "E: script exits non-zero"          ($exitCode -ne 0)                                        "Expected non-zero exit, got $exitCode"
    Assert-True "E: output contains diagnostic msg"  (($output | Out-String) -match "MXAGILE INJECTION ERROR") "Expected diagnostic message in output"
} finally {
    Remove-TestProject $tmpE
}

# =============================================================================
# Fixture F  -- Old marker migration
# =============================================================================
Write-Host "`nFixture F  -- Old marker migration" -ForegroundColor Cyan

$tmpF = New-TestProject
try {
    $fixtureF = @"
User content before.

<!-- BEGIN PROJECT AGENT INSTRUCTIONS -->
Old managed content.
<!-- END PROJECT AGENT INSTRUCTIONS -->

User content after.
"@
    [System.IO.File]::WriteAllText(
        (Join-Path $tmpF "AGENTS.md"),
        $fixtureF,
        [System.Text.UTF8Encoding]::new($false)
    )

    & powershell.exe -NonInteractive -NoProfile -File $ApplyScript -ProjectRoot $tmpF
    if ($LASTEXITCODE -ne 0) {
        Assert-True "F: script succeeds" $false "Script exited with code $LASTEXITCODE"
    }

    $agentsContent = Get-Content -LiteralPath (Join-Path $tmpF "AGENTS.md") -Raw

    Assert-True "F: new START marker present"       ($agentsContent -match [regex]::Escape($NewStart))  "New START marker not found"
    Assert-True "F: new END marker present"         ($agentsContent -match [regex]::Escape($NewEnd))    "New END marker not found"
    Assert-True "F: old START marker absent"        (-not ($agentsContent -match [regex]::Escape($OldStart))) "Old START still present"
    Assert-True "F: old END marker absent"          (-not ($agentsContent -match [regex]::Escape($OldEnd)))   "Old END still present"
    Assert-True "F: before-content preserved"       ($agentsContent -match "User content before\.")  "Before content missing"
    Assert-True "F: after-content preserved"        ($agentsContent -match "User content after\.")   "After content missing"
    Assert-True "F: old managed content replaced"   (-not ($agentsContent -match "Old managed content\.")) "Old content still present"
} finally {
    Remove-TestProject $tmpF
}

# =============================================================================
# Summary
# =============================================================================
Write-Host ""
Write-Host "═══════════════════════════════════════════" -ForegroundColor DarkGray
Write-Host "Test Results: $PassCount passed, $FailCount failed" -ForegroundColor $(if ($FailCount -eq 0) { 'Green' } else { 'Red' })

if ($FailCount -gt 0) {
    Write-Host "`nFailed assertions:" -ForegroundColor Red
    foreach ($detail in $FailDetails) {
        Write-Host "  $detail" -ForegroundColor Red
    }
    exit 1
} else {
    Write-Host "All managed block tests passed." -ForegroundColor Green
    exit 0
}
