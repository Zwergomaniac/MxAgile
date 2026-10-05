#Requires -Version 7
# MxAgile Materialization Contract — Tier 1 functional tests
#
# Verifies:
# - Explicit project name in mxagile-project.yaml is preserved (MPR stem does not overwrite)
# - Name is stable across repeated apply-script runs
# - Legacy .dfc-ai/policies/ references in skillssource/AGENTS.md are auto-migrated
# - .dfc-ai/modules/ references in project-authored files are NOT auto-migrated (detected-only)
#
# Uses GUID temp directories. No network, no mxcli.
# Run from repository root:  pwsh tests/test-materialization-contract.ps1

param(
    [string]$RepoRoot = (Get-Location).Path
)

$RepoRoot    = (Resolve-Path $RepoRoot).Path
$ApplyScript = Join-Path $RepoRoot 'scripts\apply-project-agent-instructions.ps1'
$ErrorActionPreference = 'Stop'
$pass = 0; $fail = 0
$tempDirs = @()

function Assert {
    param([bool]$Condition, [string]$Label, [string]$Detail = '')
    if ($Condition) {
        Write-Host "  PASS  $Label" -ForegroundColor Green
        $script:pass++
    } else {
        $msg = if ($Detail) { "  FAIL  $Label — $Detail" } else { "  FAIL  $Label" }
        Write-Host $msg -ForegroundColor Red
        $script:fail++
    }
}

$utf8 = [System.Text.UTF8Encoding]::new($false)

function New-MinimalProject {
    param(
        [string]$MprStem,
        [string]$ProjectYamlContent,
        [string]$SkillsAgentsMd,
        [string]$ProjektMd
    )
    $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ("mxagile-matcon-" + [System.Guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
    $script:tempDirs += $tmpDir

    [System.IO.File]::WriteAllText((Join-Path $tmpDir "$MprStem.mpr"), "DUMMY", $utf8)
    [System.IO.File]::WriteAllText((Join-Path $tmpDir "mxagile-project.yaml"), $ProjectYamlContent, $utf8)
    [System.IO.File]::WriteAllText((Join-Path $tmpDir "AGENT.md"),  "# Agent`nContent.", $utf8)
    [System.IO.File]::WriteAllText((Join-Path $tmpDir "AGENTS.md"), "# Agents`n", $utf8)
    [System.IO.File]::WriteAllText((Join-Path $tmpDir "CLAUDE.md"), "# Claude`n", $utf8)

    $skillsDir = Join-Path $tmpDir "skillssource"
    New-Item -ItemType Directory -Path $skillsDir -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $skillsDir "AGENTS.md"), $SkillsAgentsMd, $utf8)
    [System.IO.File]::WriteAllText((Join-Path $tmpDir "projekt.md"), $ProjektMd, $utf8)

    return $tmpDir
}

function Run-Apply {
    param([string]$ProjectDir)
    & pwsh -File $ApplyScript -ProjectRoot $ProjectDir 2>&1 | Out-Null
    return $LASTEXITCODE
}

function Read-File {
    param([string]$Path)
    return [System.IO.File]::ReadAllText($Path, $utf8)
}

Write-Host "`nMaterialization Contract — $RepoRoot" -ForegroundColor Cyan

# ──────────────────────────────────────────────────────────────
# A  Explicit project name preserved (MPR stem does not overwrite)
# ──────────────────────────────────────────────────────────────
Write-Host "`n[A] Explicit project name preserved; MPR stem does not overwrite"

$projA = New-MinimalProject `
    -MprStem "TechnicalAppStem" `
    -ProjectYamlContent "name: `"Custom Display Name`"`n" `
    -SkillsAgentsMd "# Custom Display Name — Coding Instructions`n`nContent here.`n" `
    -ProjektMd "# Custom Display Name — Projekt`n`nKontext hier.`n"

$_ = Run-Apply -ProjectDir $projA

$skillsA  = Read-File (Join-Path $projA "skillssource\AGENTS.md")
$projektA = Read-File (Join-Path $projA "projekt.md")

Assert ($skillsA  -match 'Custom Display Name') 'A1: skillssource/AGENTS.md retains explicit project name after apply-script'
Assert ($skillsA  -notmatch 'TechnicalAppStem')  'A2: MPR stem not written into skillssource/AGENTS.md when explicit name present'
Assert ($projektA -match 'Custom Display Name') 'A3: projekt.md retains explicit project name after apply-script'
Assert ($projektA -notmatch 'TechnicalAppStem')  'A4: MPR stem not written into projekt.md when explicit name present'

# ──────────────────────────────────────────────────────────────
# B  Name stable across repeated apply-script runs
# ──────────────────────────────────────────────────────────────
Write-Host "`n[B] Name stable across repeated apply-script runs"

$projB = New-MinimalProject `
    -MprStem "AppB" `
    -ProjectYamlContent "name: `"Stable Name Project`"`n" `
    -SkillsAgentsMd "# Stable Name Project — Coding Instructions`n`nContent here.`n" `
    -ProjektMd "# Stable Name Project — Projekt`n`n"

$_ = Run-Apply -ProjectDir $projB
$run1 = Read-File (Join-Path $projB "skillssource\AGENTS.md")
$_ = Run-Apply -ProjectDir $projB
$run2 = Read-File (Join-Path $projB "skillssource\AGENTS.md")
$_ = Run-Apply -ProjectDir $projB
$run3 = Read-File (Join-Path $projB "skillssource\AGENTS.md")

Assert ($run1 -eq $run2)                       'B1: skillssource/AGENTS.md: run 1 == run 2 (name stable)'
Assert ($run2 -eq $run3)                       'B2: skillssource/AGENTS.md: run 2 == run 3 (name stable across 3 runs)'
Assert ($run1 -match 'Stable Name Project')    'B3: project name present after all runs'

# ──────────────────────────────────────────────────────────────
# C  Legacy .dfc-ai/policies/ path auto-migrated in skillssource/AGENTS.md
# ──────────────────────────────────────────────────────────────
Write-Host "`n[C] Legacy .dfc-ai/policies/ auto-migrated in skillssource/AGENTS.md"

$projC = New-MinimalProject `
    -MprStem "LegacyApp" `
    -ProjectYamlContent "name: `"Legacy Test Project`"`n" `
    -SkillsAgentsMd "# [PROJEKTNAME] — Coding Instructions`n`nSee .dfc-ai/policies/test-workflow.md for test rules.`n" `
    -ProjektMd "# Projekt`n`nSomething about .dfc-ai/modules/ here.`n"

$_ = Run-Apply -ProjectDir $projC
$skillsC = Read-File (Join-Path $projC "skillssource\AGENTS.md")

Assert ($skillsC -notmatch '\.dfc-ai/policies/')          'C1: .dfc-ai/policies/ reference removed from skillssource/AGENTS.md'
Assert ($skillsC -match '\.mxagile/policies/test-workflow') 'C2: .mxagile/policies/test-workflow.md present after migration'

# ──────────────────────────────────────────────────────────────
# D  .dfc-ai/modules/ NOT auto-migrated in project-authored files (detected-only)
# ──────────────────────────────────────────────────────────────
Write-Host "`n[D] .dfc-ai/modules/ NOT auto-migrated (ambiguous — detected-only)"

$projD = New-MinimalProject `
    -MprStem "LegacyApp2" `
    -ProjectYamlContent "name: `"Legacy Test Project 2`"`n" `
    -SkillsAgentsMd "# [PROJEKTNAME] — Coding Instructions`n`nContent here.`n" `
    -ProjektMd "# Projekt`n`nSomething about .dfc-ai/modules/ here.`n"

$_ = Run-Apply -ProjectDir $projD
$projektD = Read-File (Join-Path $projD "projekt.md")

Assert ($projektD -match '\.dfc-ai/modules/') 'D1: .dfc-ai/modules/ retained in projekt.md (not auto-migrated — detected-only)'

# ──────────────────────────────────────────────────────────────
# Cleanup
# ──────────────────────────────────────────────────────────────
foreach ($td in $tempDirs) {
    Remove-Item -LiteralPath $td -Recurse -Force -ErrorAction SilentlyContinue
}

# ──────────────────────────────────────────────────────────────
# Summary
# ──────────────────────────────────────────────────────────────
Write-Host "`n========================================"
if ($fail -eq 0) {
    Write-Host "  PASS: $pass   FAIL: $fail — all checks passed" -ForegroundColor Green
} else {
    Write-Host "  PASS: $pass   FAIL: $fail — validation failed" -ForegroundColor Red
}
Write-Host "========================================`n"

exit ($fail -gt 0 ? 1 : 0)
