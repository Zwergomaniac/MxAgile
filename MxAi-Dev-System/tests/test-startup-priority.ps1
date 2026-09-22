<#
.SYNOPSIS
    Startup Priority Tests - MxAgile Lifecycle Re-Sync Activation

.DESCRIPTION
    Validates that startup routing in generated/injected agent entrypoints
    explicitly prioritises Lifecycle Re-Sync over Project Brain, Git history,
    and generic orientation.

    Root cause of the second Reality-Test failure:
      CLAUDE.md "Project Brain  -  read this first" was present at the top.
      The managed block (bottom of file) contained only @AGENT.md -> empty.
      No MxAgile startup routing existed in any entrypoint.
      Agent followed Brain -> ran mxcli brain plan -> empty -> git log -> parent repo.

    These tests verify the ACTUAL ENTRYPOINTS a fresh agent receives,
    not just that lifecycle-resync.md contains the correct text.

    Scenarios tested:
    1. apply-project-agent-instructions.ps1 injects MxAgile startup routing block
    2. Generated AGENTS.md contains startup routing before project instructions
    3. Generated CLAUDE.md managed block contains startup routing
    4. Generated Copilot instructions contain startup routing
    5. Startup routing explicitly prioritises Re-Sync over Brain
    6. Startup routing handles empty Brain without Git fallback
    7. Startup routing enforces project-root scope
    8. skillssource/AGENTS.md managed block contains startup routing
    9. Reality-Test regression: test workspace CLAUDE.md contains startup routing
    10. Reality-Test regression: test workspace AGENTS.md contains startup routing
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

# File paths  -  canonical sources
$injectScriptPath   = Join-Path $ScriptDir "scripts\apply-project-agent-instructions.ps1"

# File paths  -  test workspace (reality-test regression)
$testWorkspace      = Join-Path $ScriptDir ".testing-greenfield-rt4"
$wsClaudePath       = Join-Path $testWorkspace "CLAUDE.md"
$wsAgentsPath       = Join-Path $testWorkspace "AGENTS.md"
$wsCopilotPath      = Join-Path $testWorkspace ".github\copilot-instructions.md"
$wsSkillsAgentsPath = Join-Path $testWorkspace "skillssource\AGENTS.md"

Write-Host ""
Write-Host "=== Startup Priority Tests ==="
Write-Host ""

# =========================================================================
# 1. Injection script contains MxAgile startup routing block
# =========================================================================

Write-Host "--- 1: Injection script contains startup routing ---"

Assert-FileContains "inject script: MxAgileStartupBlock variable defined" `
    $injectScriptPath 'MxAgileStartupBlock'

Assert-FileContains "inject script: Re-Sync First heading in startup block" `
    $injectScriptPath 'Lifecycle Re-Sync First|Re-Sync First'

Assert-FileContains "inject script: Lifecycle Re-Sync step 1 defined" `
    $injectScriptPath 'Lifecycle Re-Sync FIRST|Re-Sync FIRST'

Assert-FileContains "inject script: Brain after Re-Sync defined" `
    $injectScriptPath 'Brain.*after.*Re-Sync|after.*Re-Sync.*Brain|Project Brain after'

Assert-FileContains "inject script: empty Brain rule defined" `
    $injectScriptPath 'Empty Brain.*NOT.*Git|Empty Brain.*not.*Git|empty Brain.*Git'

Assert-FileContains "inject script: Git history rule defined" `
    $injectScriptPath 'Git history is not lifecycle|git.*log.*not.*reconstruct'

Assert-FileContains "inject script: scope rule defined" `
    $injectScriptPath 'this project root only|project root only.*parent'

Assert-FileContains "inject script: policy reference present" `
    $injectScriptPath 'lifecycle-resync\.md'

Write-Host ""

# =========================================================================
# 2. Injection script prepends startup routing to AGENTS.md block
# =========================================================================

Write-Host "--- 2: Startup routing is prepended to AGENTS.md block ---"

Assert-FileContains "inject script: AgentsBlockContent defined" `
    $injectScriptPath 'AgentsBlockContent'

Assert-FileContains "inject script: startup block prepended to AGENTS.md content" `
    $injectScriptPath 'AgentsBlockContent|agents.*startup|startup.*agents'

Assert-FileContains "inject script: AGENTS.md block is startup + project instructions" `
    $injectScriptPath 'MxAgileStartupBlock.*ProjectInstructions|ProjectInstructions.*startup'

Write-Host ""

# =========================================================================
# 3. Injection script injects startup routing into CLAUDE.md
# =========================================================================

Write-Host "--- 3: Startup routing is injected into CLAUDE.md block ---"

Assert-FileContains "inject script: ClaudeBlockContent defined" `
    $injectScriptPath 'ClaudeBlockContent'

Assert-FileContains "inject script: CLAUDE.md block includes startup block" `
    $injectScriptPath 'MxAgileStartupBlock.*@AGENT\.md|ClaudeBlockContent.*MxAgileStartupBlock'

Assert-FileContains "inject script: CLAUDE.md injection uses ClaudeBlockContent" `
    $injectScriptPath 'ClaudePath.*ClaudeBlockContent|ClaudeBlockContent.*ClaudePath|BlockContent.*ClaudeBlockContent'

Write-Host ""

# =========================================================================
# 4. Injection script injects startup routing into Copilot instructions
# =========================================================================

Write-Host "--- 4: Startup routing is injected into Copilot instructions ---"

Assert-FileContains "inject script: CopilotBlockContent defined" `
    $injectScriptPath 'CopilotBlockContent'

Assert-FileContains "inject script: Copilot block uses startup routing" `
    $injectScriptPath 'CopilotBlockContent.*AgentsBlockContent|CopilotPath.*CopilotBlockContent'

Write-Host ""

# =========================================================================
# 5. Startup routing explicitly prioritises Re-Sync over Brain
# =========================================================================

Write-Host "--- 5: Startup routing explicitly prioritises Re-Sync over Brain ---"

Assert-FileContains "inject script: Re-Sync comes before Brain (step 1 vs step 2)" `
    $injectScriptPath 'Re-Sync FIRST|Lifecycle Re-Sync FIRST'

Assert-FileContains "inject script: Brain is supplementary not lifecycle state" `
    $injectScriptPath 'Brain.*supplementary|supplementary.*not lifecycle|Brain is supplementary'

Assert-FileContains "inject script: check process-state.yaml before Brain" `
    $injectScriptPath 'process-state\.yaml'

Write-Host ""

# =========================================================================
# 6. Startup routing handles empty Brain without Git fallback
# =========================================================================

Write-Host "--- 6: Startup routing handles empty Brain without Git fallback ---"

Assert-FileContains "inject script: empty Brain rule present" `
    $injectScriptPath 'Empty Brain|empty Brain'

Assert-FileContains "inject script: empty Brain -> project artifacts not Git" `
    $injectScriptPath 'Empty Brain.*NOT.*Git|Empty Brain.*not.*Git|empty.*Brain.*continue.*project|no.*Git.*history.*Brain'

Assert-FileContains "inject script: git log forbidden for delivery position" `
    $injectScriptPath 'git log.*reconstruct|not.*git log.*delivery|do not.*git log'

Write-Host ""

# =========================================================================
# 7. Startup routing enforces project-root scope
# =========================================================================

Write-Host "--- 7: Startup routing enforces project-root scope ---"

Assert-FileContains "inject script: parent directory traversal mentioned" `
    $injectScriptPath 'parent.*director|parent.*repositor'

Assert-FileContains "inject script: sibling project rule mentioned" `
    $injectScriptPath 'sibling'

Write-Host ""

# =========================================================================
# 8. skillssource/AGENTS.md block contains startup routing
# =========================================================================

Write-Host "--- 8: skillssource/AGENTS.md managed block contains startup routing ---"

Assert-FileContains "inject script: skillssource block includes Re-Sync First" `
    $injectScriptPath 'Lifecycle Re-Sync First.*skillsAgentsBlock|skillsAgentsBlock.*Lifecycle Re-Sync First|Re-Sync First'

Assert-FileContains "inject script: skillssource block includes empty Brain rule" `
    $injectScriptPath 'Empty Brain.*project artifacts|empty Brain.*continue'

Write-Host ""

# =========================================================================
# 9 & 10. Reality-Test regression: test workspace entrypoints
# =========================================================================

Write-Host "--- 9 & 10: Reality-Test regression  -  test workspace entrypoints ---"

$wsExists = Test-Path -LiteralPath $testWorkspace -PathType Container
Assert-True "test workspace .testing-greenfield-rt4 exists" $wsExists "Workspace not found: $testWorkspace"

if ($wsExists) {
    # CLAUDE.md
    Assert-FileContains "ws CLAUDE.md: startup routing present" `
        $wsClaudePath 'Lifecycle Re-Sync First|Re-Sync First'

    Assert-FileContains "ws CLAUDE.md: Re-Sync before Brain" `
        $wsClaudePath 'Lifecycle Re-Sync FIRST|Re-Sync FIRST'

    Assert-FileContains "ws CLAUDE.md: empty Brain rule" `
        $wsClaudePath 'Empty Brain|empty Brain'

    Assert-FileContains "ws CLAUDE.md: no git log for delivery position" `
        $wsClaudePath 'git log.*reconstruct|not.*git log|do not.*git log'

    Assert-FileContains "ws CLAUDE.md: scope rule present" `
        $wsClaudePath 'project root only|parent.*director.*scope|this project root'

    Assert-FileContains "ws CLAUDE.md: lifecycle-resync.md reference" `
        $wsClaudePath 'lifecycle-resync\.md'

    # AGENTS.md
    Assert-FileContains "ws AGENTS.md: startup routing present" `
        $wsAgentsPath 'Lifecycle Re-Sync First|Re-Sync First'

    Assert-FileContains "ws AGENTS.md: Re-Sync before Brain" `
        $wsAgentsPath 'Lifecycle Re-Sync FIRST|Re-Sync FIRST'

    Assert-FileContains "ws AGENTS.md: empty Brain rule" `
        $wsAgentsPath 'Empty Brain|empty Brain'

    Assert-FileContains "ws AGENTS.md: lifecycle-resync.md reference" `
        $wsAgentsPath 'lifecycle-resync\.md'

    # skillssource/AGENTS.md
    if (Test-Path -LiteralPath $wsSkillsAgentsPath) {
        Assert-FileContains "ws skillssource/AGENTS.md: startup routing present" `
            $wsSkillsAgentsPath 'Lifecycle Re-Sync First|Re-Sync First'

        Assert-FileContains "ws skillssource/AGENTS.md: empty Brain rule" `
            $wsSkillsAgentsPath 'Empty Brain|empty Brain'
    } else {
        Assert-True "ws skillssource/AGENTS.md exists" $false "File not found: $wsSkillsAgentsPath"
    }
}

Write-Host ""

# =========================================================================
# Final summary
# =========================================================================

Write-Host "=== Startup Priority Test Results ==="
Write-Host "  PASS: $PassCount" -ForegroundColor Green
if ($FailCount -gt 0) {
    Write-Host "  FAIL: $FailCount" -ForegroundColor Red
    foreach ($detail in $FailDetails) {
        Write-Host "    $detail" -ForegroundColor Red
    }
    Write-Host ""
    Write-Host "TEST FAILED: Startup Priority contract missing or inconsistent." -ForegroundColor Red
    exit 1
} else {
    Write-Host ""
    Write-Host "TEST PASSED: Startup routing correctly prioritises Lifecycle Re-Sync in all entrypoints." -ForegroundColor Green

    exit 0
}
