<#
.SYNOPSIS
    Mission Completion & Lifecycle Continuation Hardening Regression Tests

.DESCRIPTION
    Regression coverage for the MxAgile Mission Completion policy.
    Validates that the canonical framework sources contain the complete contracts
    required to prevent the autonomy failure observed during the CapTrack REV-014
    mission (implementation-checklist completion was incorrectly treated as
    USER_MISSION_COMPLETE; Verifying phase was never entered).

    Real failure classification: MULTIPLE_FRAMEWORK_CAUSES
    - Framework ambiguity: "definition of done" language competed with lifecycle.yaml
    - Agent execution failure: lifecycle re-sync not run after final implementation checkpoint
    - Mission contract: no durable mission criteria survived context compression

    Scenarios (see policies/mission-completion.md for full policy):

    A. Implementation gates pass — Verifying remains → USER_MISSION_COMPLETE = false
    B. Last Wave TODO completes → lifecycle re-sync required before stopping
    C. lifecycle.yaml routes implementing → verifying deterministically
    D. Working TODO list empty while mission criteria remain → derive next plan, continue
    E. Long mission context loss → durable mission-state.yaml reconstructs criteria
    F. Fresh session → mission + lifecycle reconstructed from repository evidence
    G. Implementation report created → does NOT imply mission completion
    H. Partial browser blocker → unaffected verification paths continue
    I. Genuine acceptance gate reached → stop at human boundary, not before
    J. Mission fully satisfied → terminal MISSION_REPORT allowed
    K. Simple "Implement REV-X" request → developer needs no lifecycle vocabulary
    L. Explicitly narrowed mission → framework does not exceed authorized scope
    M. Autonomous checkpoint commit → re-sync → continuation (no final report)
    N. CLOSED-AUTONOM detected → no unnecessary operating-mode question
    O. "Are you finished?" → agent checks mission contract and lifecycle first

    All tests are static content checks on canonical policy files.
    No CapTrack, KidsCompass, or Mercedes knowledge in this test file.
#>

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$TestsDir    = $PSScriptRoot
$RepoRoot    = Split-Path -Parent $TestsDir
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

# Canonical source paths
$MissionPolicy     = Join-Path $RepoRoot '.mxagile/policies/mission-completion.md'
$LifecycleYaml     = Join-Path $RepoRoot '.mxagile/lifecycle.yaml'
$ResyncPolicy      = Join-Path $RepoRoot '.mxagile/policies/lifecycle-resync.md'
$OrchestratorMd    = Join-Path $RepoRoot '.mxagile/orchestrator.md'
$CommitAuth        = Join-Path $RepoRoot '.mxagile/policies/commit-authority.md'
$ImplAgent         = Join-Path $RepoRoot '.mxagile/agents/implementation-agent.md'
$MissionSchema     = Join-Path $RepoRoot '.mxagile/schemas/mission-state.schema.json'

Write-Host ""
Write-Host "=== Mission Completion & Lifecycle Continuation Hardening Tests ===" -ForegroundColor White
Write-Host "Validates the MxAgile Mission Completion contracts."
Write-Host ""

# =============================================================================
# PREREQUISITE: All canonical files exist
# =============================================================================
Write-Host "PREREQUISITE: Canonical files exist" -ForegroundColor Cyan
Assert-FileExists "mission-completion.md exists"     $MissionPolicy
Assert-FileExists "lifecycle.yaml exists"            $LifecycleYaml
Assert-FileExists "lifecycle-resync.md exists"       $ResyncPolicy
Assert-FileExists "orchestrator.md exists"           $OrchestratorMd
Assert-FileExists "commit-authority.md exists"       $CommitAuth
Assert-FileExists "implementation-agent.md exists"   $ImplAgent
Assert-FileExists "mission-state.schema.json exists" $MissionSchema
Write-Host ""

# =============================================================================
# SECTION A: Implementation gates pass — Verifying remains → not complete
# =============================================================================
Write-Host "--- A: Implementation gates pass → USER_MISSION_COMPLETE = false ---" -ForegroundColor Cyan

Assert-FileContains "A1: mission-completion defines IMPLEMENTATION_CHANGE_COMPLETE level" `
    $MissionPolicy 'IMPLEMENTATION_CHANGE_COMPLETE'

Assert-FileContains "A2: mission-completion defines USER_MISSION_COMPLETE level" `
    $MissionPolicy 'USER_MISSION_COMPLETE'

Assert-FileContains "A3: mission-completion: docker check pass != USER_MISSION_COMPLETE" `
    $MissionPolicy 'docker check'

Assert-FileContains "A4: mission-completion: mxcli check pass != USER_MISSION_COMPLETE" `
    $MissionPolicy 'mxcli check'

Assert-FileContains "A5: mission-completion: build succeeds != USER_MISSION_COMPLETE" `
    $MissionPolicy '(?i)(build succeeds|build pass|technical gate)'

Assert-FileContains "A6: orchestrator: implementation gates are not overall mission completion" `
    $OrchestratorMd 'IMPLEMENTATION_CHANGE_COMPLETE'

Assert-FileContains "A7: orchestrator: terminal state guard required before finished statement" `
    $OrchestratorMd '(?i)(Terminal-State Guard|terminal.state.guard)'

Write-Host ""

# =============================================================================
# SECTION B: Last Wave TODO completes → lifecycle re-sync required
# =============================================================================
Write-Host "--- B: Last Wave TODO completes → lifecycle re-sync required ---" -ForegroundColor Cyan

Assert-FileContains "B1: lifecycle-resync: checklist empty triggers re-sync" `
    $ResyncPolicy '(?i)(TODO empty|checklist.*empty|empty.*checklist|Checklisten.*leer|leer.*Checkliste|Phase-Boundary Continuation)'

Assert-FileContains "B2: lifecycle-resync: phase-boundary continuation section" `
    $ResyncPolicy 'Phase-Boundary Continuation'

Assert-FileContains "B3: lifecycle-resync: implementing → verifying is deterministic" `
    $ResyncPolicy '(?i)(WAVE_IMPLEMENTATION_COMPLETE|implementing.*verifying|verifying.*deterministic)'

Assert-FileContains "B4: orchestrator: phase-boundary continuation after implementing" `
    $OrchestratorMd 'WAVE_IMPLEMENTATION_COMPLETE'

Assert-FileContains "B5: orchestrator: DO NOT stop after checklist complete" `
    $OrchestratorMd '(?i)(DO NOT stop|nicht stoppen|nicht.*stop)'

Write-Host ""

# =============================================================================
# SECTION C: lifecycle.yaml routes implementing → verifying deterministically
# =============================================================================
Write-Host "--- C: lifecycle.yaml: implementing.next = [verifying] ---" -ForegroundColor Cyan

Assert-FileContains "C1: lifecycle.yaml: implementing phase defined" `
    $LifecycleYaml 'implementing:'

Assert-FileContains "C2: lifecycle.yaml: implementing.next includes verifying" `
    $LifecycleYaml '(?m)next:\s*\[verifying\]'

Assert-FileContains "C3: lifecycle.yaml: implementing exit gate = all items terminal" `
    $LifecycleYaml '(?i)(done \| blocked \| deferred|terminal state)'

Assert-FileContains "C4: lifecycle.yaml: verifying defined" `
    $LifecycleYaml 'verifying:'

Assert-FileContains "C5: lifecycle.yaml: only done is terminal state" `
    $LifecycleYaml 'terminal_states:.*done'

Assert-FileContains "C6: mission-completion: implementing → verifying requires no user confirmation" `
    $MissionPolicy '(?i)(no user confirmation|not.*user.*confirmation|deterministic.*no user|kein.*User|no.*confirmation required)'

Write-Host ""

# =============================================================================
# SECTION D: Working TODO empty while mission criteria remain → continue
# =============================================================================
Write-Host "--- D: TODO empty while mission criteria remain → continue ---" -ForegroundColor Cyan

Assert-FileContains "D1: mission-completion: TODO empty is not stop condition" `
    $MissionPolicy '(?i)(TODO empty|TODO.*empty|empty.*stop|not.*stop condition)'

Assert-FileContains "D2: mission-completion: TODO → Mission hierarchy defined" `
    $MissionPolicy '(?i)(TODO.*Mission|Mission.*Hierarchy|MISSION.*LIFECYCLE.*WAVE.*TODO|TODO → Mission|TODO.*lifecycle)'

Assert-FileContains "D3: lifecycle-resync: empty TODO triggers re-sync and mission evaluation" `
    $ResyncPolicy '(?i)(TODO empty|re-sync.*trigger|Checklisten.*Auswertung|evaluate.*Mission|Phase-Boundary)'

Assert-FileContains "D4: mission-completion: if mission criteria remain, create next working plan" `
    $MissionPolicy '(?i)(mission criteria remain|next.*working plan|create next|criteria.*remain)'

Write-Host ""

# =============================================================================
# SECTION E: Long mission context loss → mission-state.yaml reconstructs
# =============================================================================
Write-Host "--- E: Context loss → durable mission-state.yaml reconstructs ---" -ForegroundColor Cyan

Assert-FileContains "E1: mission-completion: durable mission contract section" `
    $MissionPolicy '(?i)(Durable Mission Contract|mission.state\.yaml)'

Assert-FileContains "E2: mission-completion: mission-state.yaml is Git-tracked" `
    $MissionPolicy '(?i)(Git-tracked|git.tracked)'

Assert-FileContains "E3: mission-completion: mission-state.yaml path = planning/mission/" `
    $MissionPolicy 'planning/mission/mission-state\.yaml'

Assert-FileExists "E4: mission-state schema exists" $MissionSchema

Assert-FileContains "E5: mission schema: criteria.lifecycle_derived defined" `
    $MissionSchema 'lifecycle_derived'

Assert-FileContains "E6: mission schema: criteria.additional defined" `
    $MissionSchema '"additional"'

Assert-FileContains "E7: mission-completion: resume procedure described" `
    $MissionPolicy '(?i)(resume|Resume|fresh session|fresh.session)'

Write-Host ""

# =============================================================================
# SECTION F: Fresh session → mission + lifecycle reconstructed from repo
# =============================================================================
Write-Host "--- F: Fresh session → reconstruct from repository evidence ---" -ForegroundColor Cyan

Assert-FileContains "F1: lifecycle-resync: fresh agent can reconstruct from artifacts" `
    $ResyncPolicy '(?i)(fresh|frisch|reconstruct|ohne Konversationsgeschichte|frischer Agent)'

Assert-FileContains "F2: lifecycle-resync: process-state.yaml is canonical (Git-tracked)" `
    $ResyncPolicy 'planning/lifecycle/process-state\.yaml'

Assert-FileContains "F3: lifecycle-resync: conversational memory is supplementary only" `
    $ResyncPolicy '(?i)(Konversationsspeicher.*ergaenzend|supplementary|not sufficient alone|nicht ausreichend)'

Assert-FileContains "F4: mission-completion: on restart, reconstruct active mission" `
    $MissionPolicy '(?i)(restart|context loss|fresh session)'

Assert-FileContains "F5: mission-completion: do not persist ephemeral reasoning" `
    $MissionPolicy '(?i)(ephemeral|compact durable state|not persist ephemeral)'

Write-Host ""

# =============================================================================
# SECTION G: Implementation report created → does NOT imply mission completion
# =============================================================================
Write-Host "--- G: Implementation report != mission completion ---" -ForegroundColor Cyan

Assert-FileContains "G1: mission-completion: reporting semantics section" `
    $MissionPolicy '(?i)(Reporting Semantics|Report.*Terminates.*mission|report.*mission)'

Assert-FileContains "G2: mission-completion: implementation report does not terminate mission" `
    $MissionPolicy '(?i)(IMPLEMENTATION_REPORT.*NO|implementation.*report.*not.*terminat|report.*does.*not.*terminat)'

Assert-FileContains "G3: mission-completion: delivery-report filename does not establish mission completion" `
    $MissionPolicy 'delivery.report'

Assert-FileContains "G4: commit-authority: report semantics non-terminal section" `
    $CommitAuth '(?i)(Report Semantics|report.*non.terminal|Non-Terminal)'

Assert-FileContains "G5: commit-authority: wave report does not terminate mission" `
    $CommitAuth '(?i)(wave.report|wave report)'

Assert-FileContains "G6: commit-authority: commit is NOT stop condition" `
    $CommitAuth '(?i)(NOT.*stop condition|not.*stop|commit.*NOT.*stop|commit is not.*user)'

Write-Host ""

# =============================================================================
# SECTION H: Partial browser blocker → unaffected verification continues
# =============================================================================
Write-Host "--- H: Partial blocker → unaffected work continues ---" -ForegroundColor Cyan

Assert-FileContains "H1: mission-completion: partial blockers section" `
    $MissionPolicy '(?i)(Partial Blockers|partial.*blocker)'

Assert-FileContains "H2: mission-completion: blast radius classification" `
    $MissionPolicy '(?i)(blast radius|blast.radius)'

Assert-FileContains "H3: mission-completion: one path blocked does not stop whole mission" `
    $MissionPolicy '(?i)(stop.*WHOLE|whole mission only|locator.*unstable|role.switch)'

Assert-FileContains "H4: mission-completion: continue model+build when browser blocked" `
    $MissionPolicy '(?i)(model.*build.*evidence|model\+build|continue.*model)'

Assert-FileContains "H5: mission-completion: blocker type classification table" `
    $MissionPolicy '(?i)(INFRASTRUCTURE_GAP|LOCATOR_UNSTABLE|ROLE_SWITCH_BLOCKED)'

Write-Host ""

# =============================================================================
# SECTION I: Genuine acceptance gate → stop at human boundary, not before
# =============================================================================
Write-Host "--- I: Genuine acceptance gate → stop at actual human boundary ---" -ForegroundColor Cyan

Assert-FileContains "I1: mission-completion: human acceptance boundary section" `
    $MissionPolicy '(?i)(Human Acceptance Boundary|human.*boundary|human gate)'

Assert-FileContains "I2: mission-completion: complete all deterministic steps before human gate" `
    $MissionPolicy '(?i)(complete ALL deterministic|all deterministic.*before|before.*human gate|preparation steps)'

Assert-FileContains "I3: mission-completion: stopping before human gate is framework failure" `
    $MissionPolicy '(?i)(stopping earlier.*failure|before.*human.*failure|earlier.*framework failure)'

Assert-FileContains "I4: mission-completion: WAITING_FOR_HUMAN_ACCEPTANCE terminal guard result" `
    $MissionPolicy 'WAITING_FOR_HUMAN_ACCEPTANCE'

Write-Host ""

# =============================================================================
# SECTION J: Mission fully satisfied → terminal MISSION_REPORT allowed
# =============================================================================
Write-Host "--- J: Mission fully satisfied → terminal report allowed ---" -ForegroundColor Cyan

Assert-FileContains "J1: mission-completion: MISSION_COMPLETE guard result defined" `
    $MissionPolicy 'MISSION_COMPLETE'

Assert-FileContains "J2: mission-completion: only MISSION_COMPLETE permits unqualified finished" `
    $MissionPolicy '(?i)(Only MISSION_COMPLETE.*finished|Only.*MISSION_COMPLETE.*terminal|unqualified.*finished)'

Assert-FileContains "J3: mission-completion: MISSION_REPORT type defined" `
    $MissionPolicy 'MISSION_REPORT'

Assert-FileContains "J4: mission-completion: all USER_MISSION_COMPLETE criteria must be verified" `
    $MissionPolicy '(?i)(all.*USER_MISSION_COMPLETE|USER_MISSION_COMPLETE.*criteria|criteria.*verified)'

Write-Host ""

# =============================================================================
# SECTION K: Simple "Implement REV-X" → developer needs no lifecycle vocabulary
# =============================================================================
Write-Host "--- K: Simple developer prompt maps to full lifecycle ---" -ForegroundColor Cyan

Assert-FileContains "K1: mission-completion: simple developer UX section" `
    $MissionPolicy '(?i)(Simple Developer UX|simple.*developer)'

Assert-FileContains "K2: mission-completion: 'Implement REV-014' maps to full lifecycle" `
    $MissionPolicy '(?i)(Implement REV|REV-014)'

Assert-FileContains "K3: mission-completion: developer does not need to enumerate phases" `
    $MissionPolicy '(?i)(does NOT need to|developer.*NOT.*say|not.*enumerate)'

Assert-FileContains "K4: mission-completion: framework derives lifecycle from simple prompt" `
    $MissionPolicy '(?i)(derives.*lifecycle|framework derives|The framework derives)'

Write-Host ""

# =============================================================================
# SECTION L: Explicitly narrowed mission → framework respects scope boundary
# =============================================================================
Write-Host "--- L: Explicit scope boundary is honored ---" -ForegroundColor Cyan

Assert-FileContains "L1: mission-completion: scope_boundary field defined" `
    $MissionPolicy '(?i)(scope.boundary|scope_boundary|completion_boundary)'

Assert-FileContains "L2: mission-completion: 'implementation only' scope boundary honored" `
    $MissionPolicy '(?i)(implementation.only|implementation_only|model changes only)'

Assert-FileContains "L3: mission-completion: user-stated boundary limits completion level" `
    $MissionPolicy '(?i)(explicit.*scope.*honored|scope.*boundary.*honored|boundary.*respected|explicitly.*narrow)'

Assert-FileContains "L4: mission schema: scope_boundary field exists" `
    $MissionSchema 'scope_boundary'

Assert-FileContains "L5: mission schema: completion_boundary field exists" `
    $MissionSchema 'completion_boundary'

Write-Host ""

# =============================================================================
# SECTION M: Checkpoint commit → re-sync → continuation (no final report)
# =============================================================================
Write-Host "--- M: Checkpoint commit → re-sync → continue, no final report ---" -ForegroundColor Cyan

Assert-FileContains "M1: commit-authority: after commit run lifecycle re-sync" `
    $CommitAuth '(?i)(lifecycle re-sync|lifecycle.*re.sync|Perform a lifecycle re-sync)'

Assert-FileContains "M2: commit-authority: commit is NOT stop condition" `
    $CommitAuth '(?i)(NOT a user.interaction gate|NOT produce a final mission report.*commit|commit.*not.*stop)'

Assert-FileContains "M3: commit-authority: terminal state guard before final report" `
    $CommitAuth '(?i)(Terminal-State Guard|terminal.state.guard.*final)'

Assert-FileContains "M4: mission-completion: checkpoint commits recorded in mission-state" `
    $MissionPolicy '(?i)(checkpoint.*mission.state|commit hash.*mission|record.*commit)'

Assert-FileContains "M5: mission schema: checkpoint_commits array defined" `
    $MissionSchema 'checkpoint_commits'

Write-Host ""

# =============================================================================
# SECTION N: CLOSED-AUTONOM → no unnecessary operating-mode question
# =============================================================================
Write-Host "--- N: CLOSED-AUTONOM → no unnecessary question ---" -ForegroundColor Cyan

$OperatingMode = Join-Path $RepoRoot '.mxagile/policies/operating-mode.md'
Assert-FileExists "N1: operating-mode.md exists" $OperatingMode

Assert-FileContains "N2: operating-mode: detection before asking user" `
    $OperatingMode '(?i)(detect.*before|before.*ask|asking before.*detection.*defect|Verboten.*fragen)'

Assert-FileContains "N3: operating-mode: CLOSED-AUTONOM autonomous continuation" `
    $OperatingMode '(?i)(CLOSED.AUTONOM|CLOSED_AUTONOM)'

Assert-FileContains "N4: orchestrator: operating mode detection is mandatory before Lifecycle work" `
    $OrchestratorMd '(?i)(Betriebsmodus.*PFLICHT|operating mode.*mandatory|PFLICHT.*Betriebsmodus)'

Write-Host ""

# =============================================================================
# SECTION O: "Are you finished?" → agent checks mission contract first
# =============================================================================
Write-Host "--- O: 'Are you finished?' → Terminal-State Guard first ---" -ForegroundColor Cyan

Assert-FileContains "O1: mission-completion: terminal state guard section" `
    $MissionPolicy '(?i)(Terminal.State Guard|terminal.*guard)'

Assert-FileContains "O2: mission-completion: guard checks current lifecycle phase" `
    $MissionPolicy '(?i)(current lifecycle phase|current.*phase|lifecycle phase.*guard)'

Assert-FileContains "O3: mission-completion: guard checks next required phase" `
    $MissionPolicy '(?i)(next.*required phase|next.*phase.*lifecycle|what.*lifecycle.*says.*next)'

Assert-FileContains "O4: mission-completion: guard checks mission completion criteria" `
    $MissionPolicy '(?i)(mission criteria|Mission.*criteria.*guard|criteria.*guard)'

Assert-FileContains "O5: mission-completion: CONTINUE_DETERMINISTICALLY result defined" `
    $MissionPolicy 'CONTINUE_DETERMINISTICALLY'

Assert-FileContains "O6: mission-completion: MISSION_BLOCKED result defined" `
    $MissionPolicy 'MISSION_BLOCKED'

Write-Host ""

# =============================================================================
# SECTION P: Purity — no project-specific knowledge in Core
# =============================================================================
Write-Host "--- P: Purity — no project-specific knowledge ---" -ForegroundColor Cyan

Assert-FileNotContains "P1: mission-completion.md: no CapTrack reference" `
    $MissionPolicy 'CapTrack'

Assert-FileNotContains "P2: mission-completion.md: no KidsCompass reference" `
    $MissionPolicy 'KidsCompass'

Assert-FileNotContains "P3: mission-completion.md: no Mercedes reference" `
    $MissionPolicy '(?i)mercedes'

Assert-FileNotContains "P4: mission-state.schema.json: no project-specific reference" `
    $MissionSchema '(?i)(CapTrack|KidsCompass|mercedes)'

Assert-FileNotContains "P5: lifecycle-resync: no CapTrack reference" `
    $ResyncPolicy 'CapTrack'

Write-Host ""

# =============================================================================
# SECTION Q: Schema integrity — mission-state.schema.json structure
# =============================================================================
Write-Host "--- Q: Mission state schema integrity ---" -ForegroundColor Cyan

Assert-FileContains "Q1: schema has schema_version field" `
    $MissionSchema 'schema_version'

Assert-FileContains "Q2: schema has mission_id field" `
    $MissionSchema 'mission_id'

Assert-FileContains "Q3: schema has objective field" `
    $MissionSchema '"objective"'

Assert-FileContains "Q4: schema has completion_boundary enum" `
    $MissionSchema 'completion_boundary'

Assert-FileContains "Q5: schema has criteria.lifecycle_derived" `
    $MissionSchema 'lifecycle_derived'

Assert-FileContains "Q6: schema has progress field" `
    $MissionSchema '"progress"'

Assert-FileContains "Q7: schema has terminal_guard_result field" `
    $MissionSchema 'terminal_guard_result'

Assert-FileContains "Q8: schema has blockers field" `
    $MissionSchema '"blockers"'

Assert-FileContains "Q9: schema: MISSION_COMPLETE is a valid terminal_guard_result value" `
    $MissionSchema 'MISSION_COMPLETE'

Assert-FileContains "Q10: schema: CONTINUE_DETERMINISTICALLY is a valid terminal_guard_result value" `
    $MissionSchema 'CONTINUE_DETERMINISTICALLY'

Write-Host ""

# =============================================================================
# SECTION R: Implementation-agent policy reference
# =============================================================================
Write-Host "--- R: Implementation-agent references mission-completion policy ---" -ForegroundColor Cyan

Assert-FileContains "R1: implementation-agent references mission-completion.md" `
    $ImplAgent 'mission-completion\.md'

Assert-FileContains "R2: implementation-agent: checklist abschluss is NOT mission complete" `
    $ImplAgent '(?i)(NICHT Mission.Abschluss|not.*mission.*complete|checklist.*not.*mission|checklist.abschluss.*nicht.*mission)'

Assert-FileContains "R3: implementation-agent: IMPLEMENTATION_CHANGE_COMPLETE terminology" `
    $ImplAgent 'IMPLEMENTATION_CHANGE_COMPLETE'

Write-Host ""

# =============================================================================
# FINAL SUMMARY
# =============================================================================
Write-Host ""
Write-Host "=== Summary ===" -ForegroundColor White
Write-Host "  PASS: $PassCount" -ForegroundColor Green
Write-Host "  FAIL: $FailCount" -ForegroundColor $(if ($FailCount -eq 0) { 'Green' } else { 'Red' })

if ($FailDetails.Count -gt 0) {
    Write-Host ""
    Write-Host "Failed tests:" -ForegroundColor Red
    foreach ($d in $FailDetails) {
        Write-Host "  $d" -ForegroundColor Red
    }
}

Write-Host ""

if ($FailCount -gt 0) {
    Write-Error "Mission completion hardening test suite FAILED with $FailCount failure(s)."
} else {
    Write-Host "Mission completion hardening test suite PASSED." -ForegroundColor Green
}
