#Requires -Version 7
# MxAgile UTF-8 Idempotency + Project Name Materialization — Tier 1 functional tests
#
# Verifies:
# - Apply-ManagedBlock preserves German Unicode across 3 consecutive runs (A == B == C)
# - [PROJEKTNAME] is replaced from mxagile-project.yaml.name on each run
# - Two distinct project names produce distinct results with no cross-contamination
# - [PROJEKTNAME] is never left in materialized output when name is available
#
# Uses GUID temp directories. No network, no mxcli. Fast (inline script calls).
# Run from repository root:  pwsh tests/test-utf8-idempotency.ps1

param(
    [string]$RepoRoot = (Get-Location).Path
)

$RepoRoot   = (Resolve-Path $RepoRoot).Path
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

function New-TestProject {
    param(
        [string]$ProjectName,
        [string]$ProjektMdContent = $null,
        [string]$SkillsAgentsMdContent = $null,
        [string]$AgentsMdContent = $null
    )
    $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ("mxagile-utf8-test-" + [System.Guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
    $script:tempDirs += $tmpDir
    $utf8 = [System.Text.UTF8Encoding]::new($false)

    # Dummy .mpr file
    [System.IO.File]::WriteAllText((Join-Path $tmpDir "$ProjectName.mpr"), "DUMMY_MPR", $utf8)

    # mxagile-project.yaml with the given project name
    [System.IO.File]::WriteAllText(
        (Join-Path $tmpDir "mxagile-project.yaml"),
        "name: `"$ProjectName`"`n",
        $utf8
    )

    # AGENT.md (required by apply script)
    [System.IO.File]::WriteAllText(
        (Join-Path $tmpDir "AGENT.md"),
        "# Agent Instructions`nInstructions here.",
        $utf8
    )

    # AGENTS.md with German Unicode content
    $agentsMd = if ($AgentsMdContent) { $AgentsMdContent } else {
        "# Agent Rules`n`nÜberprüfung der Größe — Straße, Änderungen, ß`n`nProjectübersicht: em dash — here"
    }
    [System.IO.File]::WriteAllText((Join-Path $tmpDir "AGENTS.md"), $agentsMd, $utf8)

    # CLAUDE.md
    [System.IO.File]::WriteAllText((Join-Path $tmpDir "CLAUDE.md"), "# Claude Rules`n", $utf8)

    # skillssource/AGENTS.md — German Unicode + [PROJEKTNAME] placeholder
    $skillsDir = Join-Path $tmpDir "skillssource"
    New-Item -ItemType Directory -Path $skillsDir -Force | Out-Null
    $skillsAgents = if ($SkillsAgentsMdContent) { $SkillsAgentsMdContent } else {
        "# [PROJEKTNAME] — Maia Coding Instructions`n`nÄnderungen, Größe, Straße, Überprüfung`n"
    }
    [System.IO.File]::WriteAllText((Join-Path $skillsDir "AGENTS.md"), $skillsAgents, $utf8)

    # projekt.md — German Unicode + [PROJEKTNAME] placeholder
    $projektMd = if ($ProjektMdContent) { $ProjektMdContent } else {
        "# [PROJEKTNAME] — Projekt-Kontext`n`n**[PROJEKTNAME]** ist ein Beispiel.`nÜberprüfung, Größe, Straße, ß`n"
    }
    [System.IO.File]::WriteAllText((Join-Path $tmpDir "projekt.md"), $projektMd, $utf8)

    return $tmpDir
}

function Run-Apply {
    param([string]$ProjectDir)
    & pwsh -File $ApplyScript -ProjectRoot $ProjectDir 2>&1 | Out-Null
    return $LASTEXITCODE
}

function Read-Utf8 {
    param([string]$Path)
    return [System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false))
}

Write-Host "`nUTF-8 Idempotency + Project Name Materialization — $RepoRoot" -ForegroundColor Cyan

# ──────────────────────────────────────────────────────────────
# A  UTF-8 encoding idempotency: German Unicode preserved across 3 runs
# ──────────────────────────────────────────────────────────────
Write-Host "`n[A] UTF-8 encoding idempotency (3 runs, A == B == C)"

$proj = New-TestProject -ProjectName "Encoding Test Projekt"
$agentsPath  = Join-Path $proj "AGENTS.md"
$skillsPath  = Join-Path $proj "skillssource\AGENTS.md"

# Run 1
$_ = Run-Apply -ProjectDir $proj
$contentA_agents  = Read-Utf8 $agentsPath
$contentA_skills  = Read-Utf8 $skillsPath

# Run 2
$_ = Run-Apply -ProjectDir $proj
$contentB_agents  = Read-Utf8 $agentsPath
$contentB_skills  = Read-Utf8 $skillsPath

# Run 3
$_ = Run-Apply -ProjectDir $proj
$contentC_agents  = Read-Utf8 $agentsPath
$contentC_skills  = Read-Utf8 $skillsPath

Assert ($contentA_agents -match 'Ü|ß|ä|Ö|ö|ü|Ä') 'A1: AGENTS.md: German Unicode present after run 1'
Assert ($contentA_agents -eq $contentB_agents)    'A2: AGENTS.md: run 1 == run 2 (byte-stable)'
Assert ($contentB_agents -eq $contentC_agents)    'A3: AGENTS.md: run 2 == run 3 (byte-stable)'
Assert ($contentA_agents -notmatch 'Ã¤|Ã¶|Ã¼|ÃŸ|â€"') 'A4: AGENTS.md: no mojibake (Ã¤/ÃŸ/â€" patterns absent)'

Assert ($contentA_skills -match 'Ä|ü|Ö|ä|ß') 'A5: skillssource/AGENTS.md: German Unicode present after run 1'
Assert ($contentA_skills -eq $contentB_skills)  'A6: skillssource/AGENTS.md: run 1 == run 2 (byte-stable)'
Assert ($contentB_skills -eq $contentC_skills)  'A7: skillssource/AGENTS.md: run 2 == run 3 (byte-stable)'
Assert ($contentA_skills -notmatch 'Ã¤|Ã¶|Ã¼|ÃŸ|â€"') 'A8: skillssource/AGENTS.md: no mojibake after 3 runs'

# ──────────────────────────────────────────────────────────────
# B  Project name materialization: [PROJEKTNAME] replaced on first run
# ──────────────────────────────────────────────────────────────
Write-Host "`n[B] Project name materialization from mxagile-project.yaml"

$proj2 = New-TestProject -ProjectName "Example Alpha"
$_ = Run-Apply -ProjectDir $proj2

$skills2  = Read-Utf8 (Join-Path $proj2 "skillssource\AGENTS.md")
$projekt2 = Read-Utf8 (Join-Path $proj2 "projekt.md")

Assert ($skills2 -match 'Example Alpha')       'B1: skillssource/AGENTS.md: [PROJEKTNAME] replaced with project name'
Assert ($skills2 -notmatch '\[PROJEKTNAME\]')  'B2: skillssource/AGENTS.md: no [PROJEKTNAME] remaining'
Assert ($projekt2 -match 'Example Alpha')      'B3: projekt.md: [PROJEKTNAME] replaced with project name'
Assert ($projekt2 -notmatch '\[PROJEKTNAME\]') 'B4: projekt.md: no [PROJEKTNAME] remaining'
Assert ($skills2 -match 'Ä|ü|Ö|ä|ß')          'B5: skillssource/AGENTS.md: German Unicode preserved during materialization'

# ──────────────────────────────────────────────────────────────
# C  Project identity isolation: Alpha != Beta, no cross-contamination
# ──────────────────────────────────────────────────────────────
Write-Host "`n[C] Project identity isolation"

$projAlpha = New-TestProject -ProjectName "Example Alpha"
$projBeta  = New-TestProject -ProjectName "Example Beta"

$_ = Run-Apply -ProjectDir $projAlpha
$_ = Run-Apply -ProjectDir $projBeta

$alphaSkills  = Read-Utf8 (Join-Path $projAlpha "skillssource\AGENTS.md")
$betaSkills   = Read-Utf8 (Join-Path $projBeta  "skillssource\AGENTS.md")
$alphaProjekt = Read-Utf8 (Join-Path $projAlpha "projekt.md")
$betaProjekt  = Read-Utf8 (Join-Path $projBeta  "projekt.md")

Assert ($alphaSkills -match 'Example Alpha')          'C1: Alpha project: skillssource/AGENTS.md contains Alpha name'
Assert ($alphaSkills -notmatch 'Example Beta')        'C2: Alpha project: no Beta name leaked'
Assert ($betaSkills -match 'Example Beta')            'C3: Beta project: skillssource/AGENTS.md contains Beta name'
Assert ($betaSkills -notmatch 'Example Alpha')        'C4: Beta project: no Alpha name leaked'
Assert ($alphaProjekt -notmatch '\[PROJEKTNAME\]')    'C5: Alpha projekt.md: no unresolved placeholder'
Assert ($betaProjekt -notmatch '\[PROJEKTNAME\]')     'C6: Beta projekt.md: no unresolved placeholder'

# ──────────────────────────────────────────────────────────────
# D  Idempotency of materialization: second run does not double-replace
# ──────────────────────────────────────────────────────────────
Write-Host "`n[D] Materialization idempotency: second run does not corrupt"

$proj3 = New-TestProject -ProjectName "Idempotency Check"
$_ = Run-Apply -ProjectDir $proj3
$afterRun1 = Read-Utf8 (Join-Path $proj3 "skillssource\AGENTS.md")

$_ = Run-Apply -ProjectDir $proj3
$afterRun2 = Read-Utf8 (Join-Path $proj3 "skillssource\AGENTS.md")

Assert ($afterRun1 -eq $afterRun2)                    'D1: skillssource/AGENTS.md: identical after run 1 and run 2'
Assert ($afterRun1 -notmatch '\[PROJEKTNAME\]')        'D2: no [PROJEKTNAME] after first run'
Assert (([regex]::Matches($afterRun1, 'Idempotency Check')).Count -ge 1) 'D3: project name appears at least once'

# ──────────────────────────────────────────────────────────────
# E  No-name fallback: [PROJEKTNAME] retained when mxagile-project.yaml has no name
# ──────────────────────────────────────────────────────────────
Write-Host "`n[E] No-name fallback: placeholder retained when name unavailable"

$projNoName = New-TestProject -ProjectName "NoNamePlaceholder"
# Overwrite mxagile-project.yaml WITHOUT a name field
$utf8 = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText(
    (Join-Path $projNoName "mxagile-project.yaml"),
    "development:`n  ui_driven: false`n",
    $utf8
)
$_ = Run-Apply -ProjectDir $projNoName
$noNameSkills = Read-Utf8 (Join-Path $projNoName "skillssource\AGENTS.md")
Assert ($noNameSkills -match '\[PROJEKTNAME\]') 'E1: [PROJEKTNAME] retained when mxagile-project.yaml has no name (safe unresolved state)'

# ──────────────────────────────────────────────────────────────
# Cleanup temp dirs
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
