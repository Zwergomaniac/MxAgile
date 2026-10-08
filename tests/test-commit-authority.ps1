<#
.SYNOPSIS
    Commit Authority Policy Regression Tests

.DESCRIPTION
    Regression coverage for the autonomous checkpoint commit authority model.
    Validates that the canonical commit-authority.md policy contains the complete
    contract required to prevent the autonomy failure observed during the CapTrack
    REV-014 mission (agent stopped at first checkpoint commit, did not continue).

    Scenarios:
      A. Interactive small task - no delegated commit authority - proposal required
      B. Large autonomous mission - cohesive checkpoint commits permitted
      C. Autonomous mission "do not push" - local commit allowed, push forbidden
      D. Competing template "ask before commit" overridden by explicit mission delegation
      E. Repository policy (signing/approval) cannot be satisfied - commit blocked
      F. Unrelated user changes - excluded/preserved; authorized scope may commit
      G. Secrets detected - commit blocked
      H. Required validation fails - no misleading checkpoint commit
      I. Successful checkpoint - lifecycle re-sync; next step continues
      J. No push performed - push authority never implied by commit authority
      K. No destructive Git operations - always prohibited without explicit request
      L. Interrupted mission - committed checkpoint is resumable
      M. Staged-only state - not treated as successful mission completion

    All tests are static content checks on canonical policy files.
    No CapTrack, KidsCompass, or Mercedes knowledge in this test file.
#>

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$TestsDir  = $PSScriptRoot
$RepoRoot  = Split-Path -Parent $TestsDir
$PassCount   = 0
$FailCount   = 0
$FailDetails = @()

function Assert-True {
    param([string]$TestName, [bool]$Condition, [string]$Message = '')
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
    if ($null -eq $content) { Assert-True $TestName $false "File not found: $FilePath" }
    else { Assert-True $TestName ($content -match $Pattern) "Pattern '$Pattern' not found in $FilePath" }
}
function Assert-FileNotContains {
    param([string]$TestName, [string]$FilePath, [string]$Pattern)
    $content = Get-Content -LiteralPath $FilePath -Raw -ErrorAction SilentlyContinue
    if ($null -eq $content) { Assert-True $TestName $false "File not found: $FilePath" }
    else { Assert-True $TestName ($content -notmatch $Pattern) "Forbidden pattern '$Pattern' found in $FilePath" }
}
function Assert-FileExists {
    param([string]$TestName, [string]$FilePath)
    Assert-True $TestName (Test-Path -LiteralPath $FilePath) "File not found: $FilePath"
}

$CommitAuth  = Join-Path $RepoRoot '.mxagile/policies/commit-authority.md'
$SafetyRules = Join-Path $RepoRoot '.mxagile/policies/safety-rules.md'

Write-Host ""
Write-Host "=== Commit Authority Policy Regression Tests ===" -ForegroundColor White
Write-Host "Validates the autonomous checkpoint commit contract."
Write-Host ""

# =============================================================================
# PREREQUISITE: Policy file exists
# =============================================================================
Write-Host "PREREQUISITE: Canonical policy exists" -ForegroundColor Cyan
Assert-FileExists "commit-authority.md exists" $CommitAuth

# =============================================================================
# SCENARIO A: Interactive task - no delegated commit authority
# =============================================================================
Write-Host ""
Write-Host "SCENARIO A: Interactive task - proposal required when no delegation" -ForegroundColor Cyan

Assert-FileContains "A.1 INTERACTIVE_COMMIT_APPROVAL authority level defined" `
    $CommitAuth 'INTERACTIVE_COMMIT_APPROVAL'

Assert-FileContains "A.2 Default is interactive proposal, not autonomous commit" `
    $CommitAuth 'Default.*propose commits interactively|propose.*interactively.*wait for developer'

Assert-FileContains "A.3 Commit proposal continues safe work while awaiting confirmation" `
    $CommitAuth 'Continue unrelated safe.*work.*awaiting confirmation|continue.*safe.*read.*analysis.*preparation'

# =============================================================================
# SCENARIO B: Autonomous mission - checkpoint commits permitted
# =============================================================================
Write-Host ""
Write-Host "SCENARIO B: Autonomous mission - checkpoint commits without confirmation" -ForegroundColor Cyan

Assert-FileContains "B.1 AUTONOMOUS_CHECKPOINT_COMMITS authority level defined" `
    $CommitAuth 'AUTONOMOUS_CHECKPOINT_COMMITS'

Assert-FileContains "B.2 Requires explicit user delegation of autonomous execution" `
    $CommitAuth 'user has explicitly delegated autonomous execution|explicitly delegates autonomous'

Assert-FileContains "B.3 Continue to next action after commit without waiting" `
    $CommitAuth 'Continue to the next deterministic action without waiting|next deterministic action.*without'

Assert-FileContains "B.4 Agent must not stop only because a commit was created" `
    $CommitAuth 'MUST NOT produce.*final.*report merely because a commit|not.*produce.*final.*merely because a commit'

# =============================================================================
# SCENARIO C: "do not push" - local commit allowed, push forbidden
# =============================================================================
Write-Host ""
Write-Host "SCENARIO C: Autonomous mission 'do not push' - local commit OK, push blocked" -ForegroundColor Cyan

Assert-FileContains "C.1 Push requires separate explicit authorization, never inferred" `
    $CommitAuth 'ALWAYS requires explicit user authorization.*never inferred|never inferred from commit authority'

Assert-FileContains "C.2 'do not push' phrase recognized as autonomous delegation signal" `
    $CommitAuth '"do not push"'

Assert-FileContains "C.3 No push follows is a precondition before autonomous commit" `
    $CommitAuth 'No push follows|no.*git push.*command will follow'

# =============================================================================
# SCENARIO D: Competing template overridden by explicit mission delegation
# =============================================================================
Write-Host ""
Write-Host "SCENARIO D: Explicit mission delegation overrides generic 'confirm' default" -ForegroundColor Cyan

Assert-FileContains "D.1 Explicit mission delegation overrides project-level defaults" `
    $CommitAuth 'active mission.*this overrides|mission.*this overrides|this overrides.*project-level'

Assert-FileContains "D.2 Agent MUST NOT ignore explicit autonomous authority from template rule" `
    $CommitAuth 'MUST NOT ignore explicit autonomous checkpoint authority'

Assert-FileContains "D.3 Precedence rules explicitly ordered" `
    $CommitAuth 'Precedence Rules'

Assert-FileContains "D.4 Explicit user mission higher priority than agent defaults in precedence list" `
    $CommitAuth 'Explicit current user mission delegation|Agent defaults'

# =============================================================================
# SCENARIO E: Repository policy cannot be satisfied - commit blocked
# =============================================================================
Write-Host ""
Write-Host "SCENARIO E: Repository signing/approval cannot be satisfied - COMMIT_BLOCKED" -ForegroundColor Cyan

Assert-FileContains "E.1 COMMIT_BLOCKED authority level defined" `
    $CommitAuth 'COMMIT_BLOCKED'

Assert-FileContains "E.2 Signing enforcement is a mandatory control that cannot be overridden" `
    $CommitAuth 'Signing enforcement|signing.*mandatory'

Assert-FileContains "E.3 Branch protection is a mandatory control that cannot be overridden" `
    $CommitAuth 'Mandatory repository controls.*branch protection|branch protection.*mandatory'

Assert-FileContains "E.4 Mandatory controls cannot be overridden by user delegation" `
    $CommitAuth 'cannot be overridden by any user delegation|These cannot be overridden'

# =============================================================================
# SCENARIO F: Unrelated user changes - excluded, authorized scope may commit
# =============================================================================
Write-Host ""
Write-Host "SCENARIO F: Unrelated changes excluded; authorized scope proceeds" -ForegroundColor Cyan

Assert-FileContains "F.1 Unrelated user changes must be excluded from commit" `
    $CommitAuth 'Unrelated user changes excluded|unrelated.*changes.*not.*committed'

Assert-FileContains "F.2 Unrelated changes preserved, not deleted or lost" `
    $CommitAuth 'preserved|must not be committed'

Assert-FileContains "F.3 COMMIT_BLOCKED when staged content has unrelated unknown changes" `
    $CommitAuth 'Staged content contains unrelated or unknown changes'

# =============================================================================
# SCENARIO G: Secrets detected - commit blocked
# =============================================================================
Write-Host ""
Write-Host "SCENARIO G: Secrets detected - commit blocked" -ForegroundColor Cyan

Assert-FileContains "G.1 Secrets detection triggers COMMIT_BLOCKED" `
    $CommitAuth 'Secrets or sensitive data are detected|secrets.*commit.*blocked|Secrets scan passes'

Assert-FileContains "G.2 Credentials, tokens, passwords, PATs, keys named explicitly" `
    $CommitAuth 'credentials.*tokens.*passwords.*PATs|tokens.*passwords.*PATs.*API keys'

Assert-FileContains "G.3 .env.mendix, .mcp.json named as examples of blocked files" `
    $CommitAuth '\.env\.mendix.*\.mcp\.json|\.mcp\.json.*\.env'

# =============================================================================
# SCENARIO H: Required validation fails - no misleading commit
# =============================================================================
Write-Host ""
Write-Host "SCENARIO H: Required validation fails - no misleading checkpoint commit" -ForegroundColor Cyan

Assert-FileContains "H.1 Required validation is a precondition before autonomous commit" `
    $CommitAuth 'Required validation passes'

Assert-FileContains "H.2 Known failures allowed only with explicit baseline classification" `
    $CommitAuth 'known failures are explicitly baseline-classified|baseline-classified.*documented rationale'

Assert-FileContains "H.3 COMMIT_BLOCKED when validation fails without WIP classification" `
    $CommitAuth 'validation for the current checkpoint fails without explicit WIP baseline'

# =============================================================================
# SCENARIO I: Successful checkpoint - lifecycle re-sync; next step continues
# =============================================================================
Write-Host ""
Write-Host "SCENARIO I: Successful checkpoint - lifecycle re-sync, mission continues" -ForegroundColor Cyan

Assert-FileContains "I.1 Agent must record commit hash after successful commit" `
    $CommitAuth 'Record the commit hash|record.*commit hash'

Assert-FileContains "I.2 Lifecycle re-sync required if mission state demands it" `
    $CommitAuth 'lifecycle re-sync if required|Perform a lifecycle re-sync'

Assert-FileContains "I.3 Agent identifies next deterministic action and continues" `
    $CommitAuth 'Identify the next deterministic action|next deterministic action'

Assert-FileContains "I.4 Commit hashes included in final mission report" `
    $CommitAuth 'Include all commit hashes in the final mission report|commit hashes.*final.*report'

# =============================================================================
# SCENARIO J: No push performed - push authority never inferred
# =============================================================================
Write-Host ""
Write-Host "SCENARIO J: Push authority never inferred from commit authority" -ForegroundColor Cyan

Assert-FileContains "J.1 Policy explicitly states push authority never implied by commit authority" `
    $CommitAuth 'Push authority is never implied by commit authority'

Assert-FileContains "J.2 git push always requires explicit user authorization" `
    $CommitAuth 'ALWAYS requires explicit user authorization'

Assert-FileContains "J.3 safety-rules.md updated to state push is never derived from commit" `
    $SafetyRules 'Push-Autoritaet wird NIEMALS.*aus Commit-Autoritaet|push.*never.*inferred.*commit|manuell'

# =============================================================================
# SCENARIO K: No destructive Git operations - always prohibited
# =============================================================================
Write-Host ""
Write-Host "SCENARIO K: Destructive Git operations always prohibited without explicit request" -ForegroundColor Cyan

Assert-FileContains "K.1 DESTRUCTIVE_HISTORY_OPERATION category defined" `
    $CommitAuth 'DESTRUCTIVE_HISTORY_OPERATION'

Assert-FileContains "K.2 git reset --hard listed as destructive operation" `
    $CommitAuth 'git reset --hard'

Assert-FileContains "K.3 git push --force listed as destructive operation" `
    $CommitAuth 'git push --force'

Assert-FileContains "K.4 Destructive operations always prohibited without explicit same-turn request" `
    $CommitAuth 'ALWAYS prohibited.*unless explicitly requested|ALWAYS prohibited.*explicitly requested.*same turn'

Assert-FileContains "K.5 Destructive operation authority never implied by commit or push authority" `
    $CommitAuth 'Destructive operation authority is never implied by commit or push authority'

# =============================================================================
# SCENARIO L: Interrupted mission - committed checkpoint is resumable
# =============================================================================
Write-Host ""
Write-Host "SCENARIO L: Interrupted mission - checkpoint is resumable" -ForegroundColor Cyan

Assert-FileContains "L.1 Interrupted session must leave clean committed checkpoint or resume status" `
    $CommitAuth 'interrupted autonomous session must leave either|Interrupted.*checkpoint.*resumable'

Assert-FileContains "L.2 Resume status stored in process-state.yaml when committed checkpoint absent" `
    $CommitAuth 'process-state\.yaml'

Assert-FileContains "L.3 Commit granularity must be independently resumable" `
    $CommitAuth 'coherent and independently resumable'

# =============================================================================
# SCENARIO M: Staged-only state - not treated as successful completion
# =============================================================================
Write-Host ""
Write-Host "SCENARIO M: Staged-only state not valid terminal state for autonomous mission" -ForegroundColor Cyan

Assert-FileContains "M.1 Staged-only is NOT a valid terminal state for unattended mission" `
    $CommitAuth 'Staged-only state.*NOT a valid terminal state|staged.*not.*valid terminal'

Assert-FileContains "M.2 Policy names staged-without-committed as ending condition requiring blocker doc" `
    $CommitAuth 'all changes staged but uncommitted|staged but uncommitted.*without a documented blocker'

# =============================================================================
# CROSS-CHECKS: safety-rules.md updated correctly
# =============================================================================
Write-Host ""
Write-Host "CROSS-CHECK: safety-rules.md references commit-authority.md" -ForegroundColor Cyan

Assert-FileContains "X.1 safety-rules.md references commit-authority.md" `
    $SafetyRules 'commit-authority\.md'

Assert-FileContains "X.2 safety-rules.md states default is interactive proposal" `
    $SafetyRules 'interaktiv vorschlagen|propose.*interactively|interaktiv'

Assert-FileNotContains "X.3 safety-rules.md no longer contains vague 'Autopilot-Modus' commit clause" `
    $SafetyRules 'ausser Autopilot-Modus\s+ist explizit aktiviert'

Assert-FileContains "X.4 safety-rules.md states push is always manual" `
    $SafetyRules 'push.*immer manuell|manuell.*nutzergesteuert'

# =============================================================================
# PROJECT INSTRUCTION GENERATION GUIDANCE
# =============================================================================
Write-Host ""
Write-Host "GENERATION: Project instruction generation guidance present" -ForegroundColor Cyan

Assert-FileContains "GEN.1 Policy has Project Instruction Generation section" `
    $CommitAuth 'Project Instruction Generation'

Assert-FileContains "GEN.2 Policy forbids unconditional ask-before-commit without autonomous acknowledgement" `
    $CommitAuth 'MUST NOT contain an unconditional.*ask before every git commit|MUST NOT.*unconditional'

Assert-FileContains "GEN.3 Policy provides conditional template wording for generated instructions" `
    $CommitAuth 'Git Commit Authority'

Assert-FileContains "GEN.4 Template wording includes autonomous delegation branch" `
    $CommitAuth 'explicitly delegates autonomous local checkpoint commits'

# =============================================================================
# OPERATING MODE INTEGRATION
# =============================================================================
Write-Host ""
Write-Host "OPERATING MODE: Integration with CLOSED_AUTONOM defined" -ForegroundColor Cyan

Assert-FileContains "OM.1 CLOSED_AUTONOM permits bounded local checkpoint commits" `
    $CommitAuth 'CLOSED_AUTONOM.*permits bounded local'

Assert-FileContains "OM.2 STUDIO_PRO_ACTIVE must not block safe documentation/lifecycle commits" `
    $CommitAuth 'STUDIO_PRO_ACTIVE.*MUST NOT block commits of safe planning|STUDIO_PRO_ACTIVE_CURRENT_PROJECT.*restrict'

Assert-FileContains "OM.3 AMBIGUOUS_STUDIO_PRO_STATE must not block all checkpointing" `
    $CommitAuth 'AMBIGUOUS_STUDIO_PRO_STATE.*MUST block only.*model mutations'

# =============================================================================
$total = $PassCount + $FailCount
Write-Host ""
Write-Host "=" * 60
Write-Host "RESULTS: $PassCount passed, $FailCount failed out of $total tests"
if ($FailCount -gt 0) {
    Write-Host ""
    Write-Host "FAILURES:" -ForegroundColor Red
    $FailDetails | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    exit 1
} else {
    Write-Host "All tests PASSED" -ForegroundColor Green
    exit 0
}
