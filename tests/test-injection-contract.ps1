<#
.SYNOPSIS
    Tier 1: Injection Contract Snapshot Test

.DESCRIPTION
    Tests the complete injection contract by:
      1. Creating a disposable test project with a dummy .mpr file and pre-created
         instruction files (bypasses mxagile-init.ps1  -- tests agent setup only)
      2. Copying .mxagile/skills/ from the framework source
      3. Running setup-agent-system.ps1 (which calls apply-project-agent-instructions.ps1
         and generate-mxagile-platform-skills.ps1)
      4. Validating all expected outputs are present
      5. Validating no unexpected legacy output
      6. Validating managed block structure
      7. Validating generated skill file naming (mxagile/ not dfc/)

    Requirements:
      - setup-agent-system.ps1 must exist in scripts/
      - Does NOT require full mxcli installation

.NOTES
    This test does NOT run the full installer. It creates a minimal fixture project
    sufficient to test the agent system setup scripts.
#>

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$RepoRoot  = Split-Path -Parent $PSScriptRoot
$ScriptsDir = Join-Path $RepoRoot "scripts"
$MxagileSourceDir = Join-Path $RepoRoot ".mxagile"

$SetupScript = Join-Path $ScriptsDir "setup-agent-system.ps1"
if (-not (Test-Path -LiteralPath $SetupScript)) {
    Write-Error "setup-agent-system.ps1 not found at: $SetupScript"
    exit 1
}

if (-not (Test-Path -LiteralPath $MxagileSourceDir)) {
    Write-Error ".mxagile/ canonical source not found at: $MxagileSourceDir"
    exit 1
}

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

function Count-Occurrences {
    param([string]$Text, [string]$Pattern)
    return ([regex]::Matches($Text, [regex]::Escape($Pattern))).Count
}

$NewStart = "<!-- MXAGILE:MANAGED:START -->"
$NewEnd   = "<!-- MXAGILE:MANAGED:END -->"
$FixturePrefix = 'mxagile-contract-test-'
. (Join-Path $PSScriptRoot 'helpers/Remove-TestTempDirectory.ps1')

# =============================================================================
# Setup: Create fixture project
# =============================================================================
Write-Host "Setting up fixture project..." -ForegroundColor Cyan

$FixtureDir = Join-Path ([System.IO.Path]::GetTempPath()) ($FixturePrefix + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $FixtureDir -Force | Out-Null

try {
    # Dummy .mpr file
    [System.IO.File]::WriteAllText((Join-Path $FixtureDir "FixtureProject.mpr"), "DUMMY_MPR")

    # Pre-created instruction files (as mxagile-init.ps1 would create them)
    [System.IO.File]::WriteAllText((Join-Path $FixtureDir "AGENT.md"), "# Fixture Agent`r`nFixture project instructions.", [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::WriteAllText((Join-Path $FixtureDir "AGENTS.md"), "", [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::WriteAllText((Join-Path $FixtureDir "CLAUDE.md"), "", [System.Text.UTF8Encoding]::new($false))

    # Copy .mxagile/ from framework source (includes skills + agents)
    $fixtureMxagile = Join-Path $FixtureDir ".mxagile"
    Copy-Item -Path $MxagileSourceDir -Destination $fixtureMxagile -Recurse -Force
    Write-Host "  Copied .mxagile/ from: $MxagileSourceDir"

    $productSkillSource = Join-Path $RepoRoot 'products/MxMocketeer/skills'
    $fixtureSkillRoot = Join-Path $fixtureMxagile 'skills'
    foreach ($skillSource in (Get-ChildItem -LiteralPath $productSkillSource -Directory -Filter 'mocketeer-*')) {
        $skillDestination = Join-Path $fixtureSkillRoot $skillSource.Name
        New-Item -ItemType Directory -Path $skillDestination -Force | Out-Null
        Copy-Item -Path (Join-Path $skillSource.FullName '*') -Destination $skillDestination -Recurse -Force
    }

    # The known interim one-skill package is retired only when its manifest hashes verify.
    $legacyMaster = Join-Path $FixtureDir '.claude/skills/mocketeer-design-contract'
    $legacyReferences = Join-Path $legacyMaster 'references'
    New-Item -ItemType Directory -Path $legacyReferences -Force | Out-Null
    $legacySkillPath = Join-Path $legacyMaster 'SKILL.md'
    $legacyReferencePath = Join-Path $legacyReferences 'stale-reference.md'
    [System.IO.File]::WriteAllText($legacySkillPath, "---`nname: mocketeer-design-contract`ndescription: obsolete bundled master skill`n---`n# Old master`n", [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::WriteAllText($legacyReferencePath, "obsolete reference copy`n", [System.Text.UTF8Encoding]::new($false))
    $legacyManifest = [ordered]@{
        schema_version = 1
        managed_by = 'skill-bundle-v1'
        skill_name = 'mocketeer-design-contract'
        bundle_sha256 = 'sha256:' + ('a' * 64)
        files = @(
            [ordered]@{ path = 'SKILL.md'; sha256 = (Get-FileHash -LiteralPath $legacySkillPath -Algorithm SHA256).Hash.ToLowerInvariant() },
            [ordered]@{ path = 'references/stale-reference.md'; sha256 = (Get-FileHash -LiteralPath $legacyReferencePath -Algorithm SHA256).Hash.ToLowerInvariant() }
        )
    }
    $legacyManifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $legacyMaster 'bundle-manifest.json') -Encoding UTF8

    # Run setup-agent-system.ps1
    Write-Host "  Running setup-agent-system.ps1..."
    $setupOutput = & powershell.exe -NonInteractive -NoProfile -File $SetupScript -ProjectRoot $FixtureDir 2>&1
    $setupExitCode = $LASTEXITCODE

    if ($setupExitCode -ne 0) {
        Write-Host "  WARNING: setup-agent-system.ps1 exited with code $setupExitCode" -ForegroundColor Yellow
        Write-Host "  Output: $($setupOutput | Out-String)" -ForegroundColor Yellow
        # Some assertions may still pass; continue
    }

    # ==========================================================================
    # Section 1: Managed Block Structure
    # ==========================================================================
    Write-Host "`n--- Section 1: Managed Block Structure ---" -ForegroundColor Cyan

    $agentsContent = if (Test-Path (Join-Path $FixtureDir "AGENTS.md")) {
        Get-Content -LiteralPath (Join-Path $FixtureDir "AGENTS.md") -Raw
    } else { "" }

    $claudeContent = if (Test-Path (Join-Path $FixtureDir "CLAUDE.md")) {
        Get-Content -LiteralPath (Join-Path $FixtureDir "CLAUDE.md") -Raw
    } else { "" }

    $copilotPath = Join-Path $FixtureDir ".github\copilot-instructions.md"
    $copilotContent = if (Test-Path $copilotPath) {
        Get-Content -LiteralPath $copilotPath -Raw
    } else { "" }

    Assert-True "AGENTS.md: exactly 1 START marker"   ((Count-Occurrences $agentsContent $NewStart) -eq 1) "Found $(Count-Occurrences $agentsContent $NewStart) START markers"
    Assert-True "AGENTS.md: exactly 1 END marker"     ((Count-Occurrences $agentsContent $NewEnd)   -eq 1) "Found $(Count-Occurrences $agentsContent $NewEnd) END markers"
    Assert-True "CLAUDE.md: exactly 1 START marker"   ((Count-Occurrences $claudeContent  $NewStart) -eq 1) "Found $(Count-Occurrences $claudeContent $NewStart) START markers"
    Assert-True "CLAUDE.md: exactly 1 END marker"     ((Count-Occurrences $claudeContent  $NewEnd)   -eq 1) "Found $(Count-Occurrences $claudeContent $NewEnd) END markers"
    Assert-True "copilot-instructions: exists"         ($copilotContent.Length -gt 0)                        "copilot-instructions.md is empty or missing"
    Assert-True "copilot-instructions: exactly 1 START" ((Count-Occurrences $copilotContent $NewStart) -eq 1) "Found $(Count-Occurrences $copilotContent $NewStart)"
    Assert-True "copilot-instructions: exactly 1 END"  ((Count-Occurrences $copilotContent $NewEnd)   -eq 1) "Found $(Count-Occurrences $copilotContent $NewEnd)"

    # CLAUDE.md should contain @AGENT.md reference
    Assert-True "CLAUDE.md block contains @AGENT.md"  ($claudeContent -match "@AGENT\.md") "@AGENT.md reference not found in CLAUDE.md"
    Assert-True "CLAUDE.md managed block routes tool conflicts to canonical policy" `
        ($claudeContent -match 'tool-instruction-conflict\.md') "Tool conflict policy reference not found in CLAUDE.md"

    # AGENTS.md should contain actual AGENT.md content
    Assert-True "AGENTS.md block contains agent content" ($agentsContent -match "Fixture project instructions") "AGENT.md content not found in AGENTS.md"
    Assert-True "AGENTS.md managed block routes tool conflicts to canonical policy" `
        ($agentsContent -match 'tool-instruction-conflict\.md') "Tool conflict policy reference not found in AGENTS.md"

    # ==========================================================================
    # Section 2: Claude Skill Projections
    # ==========================================================================
    Write-Host "`n--- Section 2: Claude Skill Projections ---" -ForegroundColor Cyan

    $claudeSkillsDir = Join-Path $FixtureDir ".claude\skills"
    Assert-True "Claude skills dir exists" (Test-Path $claudeSkillsDir) ".claude/skills/ not found"

    if (Test-Path $claudeSkillsDir) {
        $claudeSkillDirs = @(Get-ChildItem $claudeSkillsDir -Directory | Where-Object { $_.Name -like "mxagile-*" })
        Assert-True "Claude skills: mxagile- prefix dirs exist" ($claudeSkillDirs.Count -gt 0) "No mxagile-* dirs in .claude/skills/"

        foreach ($skillDir in $claudeSkillDirs) {
            $skillFile = Join-Path $skillDir.FullName "SKILL.md"
            Assert-True "Claude skill file exists: $($skillDir.Name)" (Test-Path $skillFile) "SKILL.md not found in $($skillDir.Name)"

            if (Test-Path $skillFile) {
                $skillContent = Get-Content -LiteralPath $skillFile -Raw
                Assert-True "Claude skill has GENERATED header: $($skillDir.Name)" ($skillContent -match "# GENERATED") "Missing GENERATED header"
                Assert-True "Claude skill has mxagile- name in frontmatter: $($skillDir.Name)" ($skillContent -match "name: `"mxagile-") "Missing mxagile- name in frontmatter"
            }
        }

        # Check system-check skill specifically
        $sysCheckDir = Join-Path $claudeSkillsDir "mxagile-system-check"
        Assert-True "Claude skills: mxagile-system-check present" (Test-Path $sysCheckDir) "mxagile-system-check not found in .claude/skills/"
    }

    # ==========================================================================
    # Section 3: Copilot Skill Projections
    # ==========================================================================
    Write-Host "`n--- Section 3: Copilot Skill Projections ---" -ForegroundColor Cyan

    $copilotSkillsDir = Join-Path $FixtureDir ".github\skills"
    Assert-True "Copilot skills dir exists" (Test-Path $copilotSkillsDir) ".github/skills/ not found"

    if (Test-Path $copilotSkillsDir) {
        $copilotSkillDirs = @(Get-ChildItem $copilotSkillsDir -Directory | Where-Object { $_.Name -like "mxagile-*" })
        Assert-True "Copilot skills: mxagile- prefix dirs exist" ($copilotSkillDirs.Count -gt 0) "No mxagile-* dirs in .github/skills/"

        foreach ($skillDir in $copilotSkillDirs) {
            $skillFile = Join-Path $skillDir.FullName "SKILL.md"
            Assert-True "Copilot skill file exists: $($skillDir.Name)" (Test-Path $skillFile) "SKILL.md not found"
        }
    }

    # ==========================================================================
    # Section 4: Claude Agent Projections
    # ==========================================================================
    Write-Host "`n--- Section 4: Claude Agent Projections ---" -ForegroundColor Cyan

    $claudeAgentsDir = Join-Path $FixtureDir ".claude\agents"
    if (Test-Path $claudeAgentsDir) {
        $agentFiles = @(Get-ChildItem $claudeAgentsDir -Filter "mxagile-*.md" -File)
        if ($agentFiles.Count -gt 0) {
            foreach ($agentFile in $agentFiles) {
                $agentContent = Get-Content -LiteralPath $agentFile.FullName -Raw
                Assert-True "Claude agent has GENERATED header: $($agentFile.Name)" ($agentContent -match "# GENERATED") "Missing GENERATED header"
            }
            Write-Host "  INFO: $($agentFiles.Count) mxagile-* agent files found" -ForegroundColor DarkGray
        } else {
            Write-Host "  INFO: No agent source files found  -- skipping agent assertions" -ForegroundColor DarkGray
        }
    } else {
        Write-Host "  INFO: .claude/agents/ not created  -- no agent sources or skipped" -ForegroundColor DarkGray
    }

    # ==========================================================================
    # Section 5: mxagile/ directory naming (not dfc/)
    # ==========================================================================
    Write-Host "`n--- Section 5: mxagile/ directory naming (not dfc/) ---" -ForegroundColor Cyan

    # Codex
    $codexMxagile = Join-Path $FixtureDir ".agents\skills\mxagile"
    $codexDfc      = Join-Path $FixtureDir ".agents\skills\dfc"
    Assert-True "Codex: .agents/skills/mxagile/ exists (not dfc/)" (Test-Path $codexMxagile) ".agents/skills/mxagile/ not found"
    Assert-True "Codex: .agents/skills/dfc/ does NOT exist"        (-not (Test-Path $codexDfc))  ".agents/skills/dfc/ found (stale naming)"

    # Grok
    $grokMxagile = Join-Path $FixtureDir ".grok\skills\mxagile"
    $grokDfc      = Join-Path $FixtureDir ".grok\skills\dfc"
    Assert-True "Grok: .grok/skills/mxagile/ exists (not dfc/)"   (Test-Path $grokMxagile) ".grok/skills/mxagile/ not found"
    Assert-True "Grok: .grok/skills/dfc/ does NOT exist"          (-not (Test-Path $grokDfc))   ".grok/skills/dfc/ found (stale naming)"

    # OpenCode
    $opencodeMxagile = Join-Path $FixtureDir ".opencode\skills\mxagile"
    $opencodeDfc      = Join-Path $FixtureDir ".opencode\skills\dfc"
    Assert-True "OpenCode: .opencode/skills/mxagile/ exists"      (Test-Path $opencodeMxagile) ".opencode/skills/mxagile/ not found"
    Assert-True "OpenCode: .opencode/skills/dfc/ does NOT exist"  (-not (Test-Path $opencodeDfc)) ".opencode/skills/dfc/ found (stale naming)"

    # Hermes
    $hermesMxagile = Join-Path $FixtureDir ".hermes\skills\mxagile"
    $hermesDfc      = Join-Path $FixtureDir ".hermes\skills\dfc"
    Assert-True "Hermes: .hermes/skills/mxagile/ exists"          (Test-Path $hermesMxagile) ".hermes/skills/mxagile/ not found"
    Assert-True "Hermes: .hermes/skills/dfc/ does NOT exist"      (-not (Test-Path $hermesDfc)) ".hermes/skills/dfc/ found (stale naming)"

    # ==========================================================================
    # Section 6: mxagile-system-check in Copilot projections
    # ==========================================================================
    Write-Host "`n--- Section 6: mxagile-system-check skill present ---" -ForegroundColor Cyan

    if (Test-Path $copilotSkillsDir) {
        $copilotSysCheck = Get-ChildItem $copilotSkillsDir -Directory | Where-Object { $_.Name -like "*system-check*" }
        Assert-True "Copilot: mxagile-system-check present" ($null -ne $copilotSysCheck -and @($copilotSysCheck).Count -gt 0) "mxagile-system-check not in .github/skills/"
    }

    # ======================================================================
    # Section 7: Installer-delivered Mocketeer directory skills
    # ======================================================================
    Write-Host "`n--- Section 7: Mocketeer skills delivered from canonical .mxagile source ---" -ForegroundColor Cyan

    $mocketeerSkillNames = @(
        'mocketeer-discovery',
        'mocketeer-design-contract',
        'mocketeer-refinement',
        'mocketeer-preservation',
        'mocketeer-business-flows',
        'mocketeer-mockup-generation',
        'mocketeer-handoff'
    )
    foreach ($skillName in $mocketeerSkillNames) {
        $sourceSkill = Join-Path $FixtureDir ".mxagile/skills/$skillName/SKILL.md"
        Assert-True "Mocketeer source skill exists: $skillName" (Test-Path -LiteralPath $sourceSkill -PathType Leaf) "Missing $sourceSkill"

        foreach ($platformRoot in @('.claude/skills', '.github/skills', '.agents/skills')) {
            $projectedSkill = Join-Path $FixtureDir "$platformRoot/$skillName/SKILL.md"
            Assert-True "Mocketeer projection exists: $platformRoot/$skillName" (Test-Path -LiteralPath $projectedSkill -PathType Leaf) "Missing $projectedSkill"
            if (Test-Path -LiteralPath $projectedSkill -PathType Leaf) {
                $projectedContent = Get-Content -LiteralPath $projectedSkill -Raw -Encoding UTF8
                Assert-True "Mocketeer projection is generated: $platformRoot/$skillName" ($projectedContent -match '# GENERATED - DO NOT EDIT - Source: \.mxagile/') 'Generated source marker missing'
                Assert-True "Mocketeer projection name is valid: $platformRoot/$skillName" ($projectedContent -match "(?s)^---\s*`r?`nname: $skillName`r?`n") 'Frontmatter name does not match canonical skill name'
            }
        }
    }
    $businessFlowSource = Join-Path $fixtureMxagile 'skills/mocketeer-business-flows/SKILL.md'
    $businessFlowContent = Get-Content -LiteralPath $businessFlowSource -Raw -Encoding UTF8
    Assert-True 'Mocketeer Business Flow knowledge is embedded in its skill' ($businessFlowContent -match 'Flow-to-Verification Traceability' -and $businessFlowContent -match 'DECLARED') 'Full Business Flow/Interaction content is missing'
    Assert-True 'Mocketeer is not delivered as separate reference files' (-not (Test-Path -LiteralPath (Join-Path $fixtureMxagile 'skills/mocketeer/references'))) 'Unexpected separate references directory'
    $updatedMaster = Get-Content -LiteralPath (Join-Path $FixtureDir '.claude/skills/mocketeer-design-contract/SKILL.md') -Raw -Encoding UTF8
    Assert-True 'Legacy bundled master skill is replaced by the canonical design-contract skill' ($updatedMaster -match 'DESIGN CONTRACT' -and $updatedMaster -notmatch 'Old master') 'Legacy master content remains'
    Assert-True 'Legacy reference copies are retired on update' (-not (Test-Path -LiteralPath (Join-Path $FixtureDir '.claude/skills/mocketeer-design-contract/references/stale-reference.md'))) 'Stale reference remains'
    Assert-True 'Legacy bundle manifest is retired on update' (-not (Test-Path -LiteralPath (Join-Path $FixtureDir '.claude/skills/mocketeer-design-contract/bundle-manifest.json'))) 'Legacy bundle manifest remains'

} finally {
    Write-Host "`nCleaning up fixture project: $FixtureDir" -ForegroundColor DarkGray
    Remove-TestTempDirectory -Path $FixtureDir -ExpectedPrefix $FixturePrefix
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
    Write-Host "All injection contract tests passed." -ForegroundColor Green
    exit 0
}
