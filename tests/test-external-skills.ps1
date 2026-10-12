#Requires -Version 7
# Tier 0 static validation for external skills integration (Ponytail + Superpowers).
# No network access, no LLM calls, no agent invocation.
# Tests: skill presence, provenance completeness, precedence contract, hygiene.
#
# Run from repository root:  pwsh tests/test-external-skills.ps1

param(
    [string]$RepoRoot = (Get-Location).Path
)

$RepoRoot = (Resolve-Path $RepoRoot).Path
$ErrorActionPreference = 'Stop'
$pass = 0; $fail = 0

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

$ExpectedSkills = @(
    'ponytail',
    'systematic-debugging',
    'verification-before-completion',
    'requesting-code-review',
    'receiving-code-review',
    'diagnosing-agent-session'
)

Write-Host "`nExternal Skills Integration — $RepoRoot" -ForegroundColor Cyan

# ──────────────────────────────────────────────────────────────
# A  Portable skill files present (.agents/skills/)
# ──────────────────────────────────────────────────────────────
Write-Host "`n[A] Portable skill files: .agents/skills/<name>/SKILL.md"
foreach ($skill in $ExpectedSkills) {
    $path = Join-Path $RepoRoot ".agents\skills\$skill\SKILL.md"
    Assert (Test-Path $path) "A: $skill/SKILL.md exists" ".agents/skills/$skill/SKILL.md not found"
}

# ──────────────────────────────────────────────────────────────
# B  Claude Code adapter files present (.claude/skills/)
# ──────────────────────────────────────────────────────────────
Write-Host "`n[B] Claude Code adapter files: .claude/skills/<name>/SKILL.md"
foreach ($skill in $ExpectedSkills) {
    $path = Join-Path $RepoRoot ".claude\skills\$skill\SKILL.md"
    Assert (Test-Path $path) "B: $skill/SKILL.md (Claude adapter) exists" ".claude/skills/$skill/SKILL.md not found"
}

# ──────────────────────────────────────────────────────────────
# C  Claude Code adapters have YAML frontmatter with name and description
# ──────────────────────────────────────────────────────────────
Write-Host "`n[C] Claude Code adapters have required frontmatter fields"
foreach ($skill in $ExpectedSkills) {
    $path = Join-Path $RepoRoot ".claude\skills\$skill\SKILL.md"
    if (Test-Path $path) {
        $content = Get-Content $path -Raw -Encoding UTF8
        Assert ($content -match '^---') "C: $skill has YAML frontmatter start" "Missing --- at start"
        Assert ($content -match "name:\s*$skill") "C: $skill name field matches directory" "name field missing or wrong"
        Assert ($content -match 'description:') "C: $skill has description field"
    }
}

# ──────────────────────────────────────────────────────────────
# D  PROVENANCE.md present for each skill
# ──────────────────────────────────────────────────────────────
Write-Host "`n[D] Provenance records: .agents/skills/<name>/PROVENANCE.md"
foreach ($skill in $ExpectedSkills) {
    $path = Join-Path $RepoRoot ".agents\skills\$skill\PROVENANCE.md"
    Assert (Test-Path $path) "D: $skill/PROVENANCE.md exists" ".agents/skills/$skill/PROVENANCE.md not found"
}

# ──────────────────────────────────────────────────────────────
# E  PROVENANCE.md contains required metadata fields
# ──────────────────────────────────────────────────────────────
Write-Host "`n[E] Provenance records contain required metadata fields"
$RequiredProvenanceFields = @('upstream_repository', 'pinned_commit', 'license', 'import_date', 'content_status')
foreach ($skill in $ExpectedSkills) {
    $path = Join-Path $RepoRoot ".agents\skills\$skill\PROVENANCE.md"
    if (Test-Path $path) {
        $content = Get-Content $path -Raw -Encoding UTF8
        foreach ($field in $RequiredProvenanceFields) {
            Assert ($content -match $field) "E: $skill PROVENANCE.md has $field" "Field '$field' missing from $skill/PROVENANCE.md"
        }
        Assert ($content -match 'MIT') "E: $skill PROVENANCE.md states MIT license"
        Assert ($content -match 'Rollback Procedure') "E: $skill PROVENANCE.md has Rollback Procedure"
        Assert ($content -match 'Update Procedure') "E: $skill PROVENANCE.md has Update Procedure"
    }
}

# ──────────────────────────────────────────────────────────────
# F  CLAUDE.md precedence section present and correct
# ──────────────────────────────────────────────────────────────
Write-Host "`n[F] CLAUDE.md: External Skills section and precedence model"
$claudeMd = Get-Content (Join-Path $RepoRoot 'CLAUDE.md') -Raw -Encoding UTF8
Assert ($claudeMd -match '## External Skills') 'F1: CLAUDE.md has External Skills section'
Assert ($claudeMd -match 'Instruction precedence') 'F2: CLAUDE.md has precedence list'
Assert ($claudeMd -match '1\.\s.*user instruction|Explicit current user') 'F3: user instruction is precedence 1'
Assert ($claudeMd -match '2\.\s.*MxAgile|MxAgile safety') 'F4: MxAgile contracts are precedence 2'
Assert ($claudeMd -match '3\.\s.*Repository|Repository-specific') 'F5: repo rules are precedence 3'
Assert ($claudeMd -match '4\.\s.*External skills|External skills') 'F6: external skills are precedence 4'
Assert ($claudeMd -match 'do not own or replace any MxAgile lifecycle') 'F7: CLAUDE.md states external skills do not own lifecycle'
Assert ($claudeMd -match 'Unavailable verification is not passed') 'F8: CLAUDE.md states unavailable verification is not passed'
Assert ($claudeMd -match 'docs/external-skills\.md') 'F9: CLAUDE.md references external-skills.md'

# ──────────────────────────────────────────────────────────────
# G  MxAgile override present in ponytail skill
# ──────────────────────────────────────────────────────────────
Write-Host "`n[G] Ponytail MxAgile override"
$ponytailClaude = Get-Content (Join-Path $RepoRoot '.claude\skills\ponytail\SKILL.md') -Raw -Encoding UTF8
$ponytailAgents = Get-Content (Join-Path $RepoRoot '.agents\skills\ponytail\SKILL.md') -Raw -Encoding UTF8
Assert ($ponytailClaude -match 'MxAgile.*Smallest Complete Change Override') 'G1: ponytail Claude adapter has MxAgile override section'
Assert ($ponytailAgents -match 'MxAgile.*Smallest Complete Change Override') 'G2: ponytail portable version has MxAgile override section'
Assert ($ponytailClaude -match 'acceptance gates') 'G3: ponytail override mentions acceptance gates'
Assert ($ponytailClaude -match 'evidence preservation|Evidence preservation') 'G4: ponytail override mentions evidence preservation'
Assert ($ponytailClaude -match "Smallest.*complete.*change.*not.*smallest.*textual|not.*smallest.*textual.*diff") 'G5: ponytail override clarifies "smallest" meaning'

# ──────────────────────────────────────────────────────────────
# H  requesting-code-review MxAgile override restricts subagent dispatch
# ──────────────────────────────────────────────────────────────
Write-Host "`n[H] requesting-code-review MxAgile override"
$rcr = Get-Content (Join-Path $RepoRoot '.claude\skills\requesting-code-review\SKILL.md') -Raw -Encoding UTF8
Assert ($rcr -match 'MxAgile Override') 'H1: requesting-code-review has MxAgile Override section'
Assert ($rcr -match 'explicit user or MxAgile mission approval') 'H2: override requires explicit approval for subagent dispatch'
Assert ($rcr -match 'mandatory after each task.*does not apply|does not apply automatically') 'H3: override disables automatic mandatory dispatch'

# ──────────────────────────────────────────────────────────────
# I  diagnosing-agent-session documents adaptation from upstream
# ──────────────────────────────────────────────────────────────
Write-Host "`n[I] diagnosing-agent-session: upstream adaptation documented"
$das = Get-Content (Join-Path $RepoRoot '.agents\skills\diagnosing-agent-session\PROVENANCE.md') -Raw -Encoding UTF8
Assert ($das -match 'diagnosing-superpowers') 'I1: PROVENANCE.md names the upstream skill (diagnosing-superpowers)'
Assert ($das -match 'upstream_skill_name') 'I2: PROVENANCE.md has upstream_skill_name field'
Assert ($das -match 'substantially_adapted') 'I3: PROVENANCE.md classifies content as substantially_adapted'
Assert ($das -match 'infrastructure.*not.*present|infrastructure is not present|None of this infrastructure exists') 'I4: PROVENANCE.md notes missing infrastructure'

# ──────────────────────────────────────────────────────────────
# J  No global hooks installed
# ──────────────────────────────────────────────────────────────
Write-Host "`n[J] Repository hygiene: no global hook installation"
$gitHooks = Join-Path $RepoRoot '.git\hooks'
$externalHookFiles = @('ponytail', 'superpowers', 'systematic-debugging', 'verification')
if (Test-Path $gitHooks) {
    foreach ($hookName in $externalHookFiles) {
        $hookFile = Get-ChildItem $gitHooks -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $hookName }
        Assert ($null -eq $hookFile -or @($hookFile).Count -eq 0) "J: no external hook file named '$hookName' in .git/hooks"
    }
} else {
    Write-Host "  INFO  J: .git/hooks directory not found — skipping hook check" -ForegroundColor Yellow
    $script:pass++
}
# No .gitmodules should reference external skill repos
$gitmodulesPath = Join-Path $RepoRoot '.gitmodules'
if (Test-Path $gitmodulesPath) {
    $gitmodules = Get-Content $gitmodulesPath -Raw -Encoding UTF8
    Assert ($gitmodules -notmatch 'ponytail') 'J: .gitmodules does not reference ponytail'
    Assert ($gitmodules -notmatch 'superpowers') 'J: .gitmodules does not reference superpowers'
} else {
    Write-Host "  INFO  J: no .gitmodules file — expected (no submodules added)" -ForegroundColor Yellow
    $script:pass++
}

# ──────────────────────────────────────────────────────────────
# K  External skills do not appear in .mxagile/ (not framework skills)
# ──────────────────────────────────────────────────────────────
Write-Host "`n[K] Isolation: external skills not in .mxagile/"
foreach ($skill in $ExpectedSkills) {
    $mxagilePath = Join-Path $RepoRoot ".mxagile\skills\$skill.md"
    Assert (-not (Test-Path $mxagilePath)) "K: $skill is not in .mxagile/skills/ (external, not framework)" "$skill found in .mxagile/skills/ — should not be there"
}

# ──────────────────────────────────────────────────────────────
# L  External skills documentation exists
# ──────────────────────────────────────────────────────────────
Write-Host "`n[L] External skills documentation"
$docPath = Join-Path $RepoRoot 'docs\external-skills.md'
Assert (Test-Path $docPath) 'L1: docs/external-skills.md exists'
$doc = Get-Content $docPath -Raw -Encoding UTF8
Assert ($doc -match 'Precedence Model') 'L2: docs has Precedence Model section'
Assert ($doc -match 'Rollback Procedure|Disable or Remove') 'L3: docs has rollback/removal instructions'
Assert ($doc -match 'Overlap and Conflict Analysis') 'L4: docs has conflict analysis'
Assert ($doc -match 'Validation Report') 'L5: docs has validation report'
Assert ($doc -match 'pinned_commit|Pinned Commit') 'L6: docs records pinned commits'

# ──────────────────────────────────────────────────────────────
# M  Superpowers inactive capabilities not auto-triggered
# ──────────────────────────────────────────────────────────────
Write-Host "`n[M] Inactive Superpowers capabilities not in active skill files"
$activeSkillContent = ''
foreach ($skill in $ExpectedSkills) {
    $p = Join-Path $RepoRoot ".claude\skills\$skill\SKILL.md"
    if (Test-Path $p) { $activeSkillContent += Get-Content $p -Raw -Encoding UTF8 }
}
# None of the inactive capabilities should appear as automatic triggers in active skills
Assert ($activeSkillContent -notmatch 'automatic brainstorming|brainstorm before every') 'M1: no automatic brainstorming trigger in active skills'
Assert ($activeSkillContent -notmatch 'universal.*startup.*lifecycle|bootstrap.*lifecycle.*universal') 'M2: no universal startup lifecycle in active skills'
Assert ($activeSkillContent -notmatch 'create worktree automatically|automatic worktree') 'M3: no automatic worktree creation in active skills'

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
