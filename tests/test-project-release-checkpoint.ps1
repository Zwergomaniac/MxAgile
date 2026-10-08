<#
.SYNOPSIS
    Project/Release Completion Checkpoint — Regression Tests

.DESCRIPTION
    Regression coverage for the MxAgile Project/Release Completion Checkpoint.
    Validates canonical policy, lifecycle, schema, and orchestrator sources contain
    the contracts required to:

    - prevent MISSION_COMPLETE after all Feature Waves without checkpoint evaluation
    - detect false "waves done" when UI ACs require unreachable surfaces
    - offer a non-technical project-wide review to the developer
    - classify and execute QUICK_HEALTH_CHECK, INTEGRATED_PRODUCT_REVIEW, RELEASE_READINESS_REVIEW
    - discover and present existing automated tests
    - route gap repair to the earliest necessary lifecycle phase
    - persist the developer's skip decision so the offer is not repeated
    - keep next-scope selection safety (no autonomous new-feature work after completion)

    Scenarios:
    A. Last authorized Wave done → checkpoint considered
    B. More authorized Waves remain → no checkpoint yet
    C. AC requires UI behavior; backend uncalled/unreachable → Feature Scope incomplete
    D. All Wave checks pass but unresolved required effect remains → incomplete
    E. User already requested release-readiness → integrated review starts without question
    F. Normal feature mission completes → concise review offer presented
    G. User declines review → decision persisted; mission may complete without repeat
    H. User accepts integrated review → UI/functional/regression/test discovery executed
    I. Automated tests present and current → detected and offered/executed per profile
    J. No automation exists → honest result; no fabricated tests
    K. One test infrastructure path blocked → other review work continues
    L. Integrated review finds authorized gap → scoped lifecycle return and repair
    M. Integrated review passes but NFR/privacy/deployment absent → RELEASE_READY not claimed
    N. Deferred scope → not started automatically
    O. External Board sync → not run before checkpoint completes
    P. Terminal-State Guard → cannot skip unresolved checkpoint decision
    Q. Explicit implementation-only mission → review not auto-run
    R. Fresh-session resume → checkpoint state reconstructed from mission-state.yaml
    S. Documentation reflects current behavior

    No CapTrack, KidsCompass, or Mercedes-specific knowledge in this file.
#>

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$TestsDir  = $PSScriptRoot
$RepoRoot  = Split-Path -Parent $TestsDir
$PassCount = 0
$FailCount = 0
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
$CheckpointPolicy = Join-Path $RepoRoot '.mxagile/policies/project-release-checkpoint.md'
$MissionPolicy    = Join-Path $RepoRoot '.mxagile/policies/mission-completion.md'
$LifecycleYaml    = Join-Path $RepoRoot '.mxagile/lifecycle.yaml'
$OrchestratorMd   = Join-Path $RepoRoot '.mxagile/orchestrator.md'
$MissionSchema    = Join-Path $RepoRoot '.mxagile/schemas/mission-state.schema.json'
$BacklogSync      = Join-Path $RepoRoot '.mxagile/policies/backlog-sync.md'
$ReadMe           = Join-Path $RepoRoot 'README.md'

Write-Host ""
Write-Host "=== Project/Release Completion Checkpoint Tests ===" -ForegroundColor White
Write-Host ""

# PREREQUISITE
Write-Host "PREREQUISITE: Canonical files exist" -ForegroundColor Cyan
Assert-FileExists "project-release-checkpoint.md exists"   $CheckpointPolicy
Assert-FileExists "mission-completion.md exists"           $MissionPolicy
Assert-FileExists "lifecycle.yaml exists"                  $LifecycleYaml
Assert-FileExists "orchestrator.md exists"                 $OrchestratorMd
Assert-FileExists "mission-state.schema.json exists"       $MissionSchema

# =============================================================================
# SCENARIO A: Last authorized Wave done → checkpoint considered
# =============================================================================
Write-Host ""
Write-Host "--- A: Last authorized Wave done → checkpoint considered ---" -ForegroundColor Cyan

Assert-FileContains "A1: lifecycle.yaml defines feature_scope_completion section" `
    $LifecycleYaml 'feature_scope_completion'

Assert-FileContains "A2: lifecycle.yaml: trigger_conditions includes all waves done" `
    $LifecycleYaml '(?i)(all waves.*terminal.*done|planning/execution-waves)'

Assert-FileContains "A3: mission-completion: all waves done is NOT USER_MISSION_COMPLETE" `
    $MissionPolicy '(?i)(all waves done|FEATURE_SCOPE_COMPLETE.*NOT USER_MISSION_COMPLETE|project.release.*checkpoint.*must)'

Assert-FileContains "A4: mission-completion: FEATURE_SCOPE_COMPLETE completion level defined" `
    $MissionPolicy 'FEATURE_SCOPE_COMPLETE'

Assert-FileContains "A5: mission-completion: PROJECT_RELEASE_CHECKPOINT_PENDING defined" `
    $MissionPolicy 'PROJECT_RELEASE_CHECKPOINT_PENDING'

Assert-FileContains "A6: mission-completion: Terminal-State Guard check 8 covers feature scope" `
    $MissionPolicy '(?i)(Guard Check 8|check 8|Feature scope.*guard|guard.*feature scope|project.release-checkpoint)'

Assert-FileContains "A7: mission-completion: PROJECT_RELEASE_CHECKPOINT_REQUIRED guard result" `
    $MissionPolicy 'PROJECT_RELEASE_CHECKPOINT_REQUIRED'

Assert-FileContains "A8: orchestrator: feature-scope completion section present" `
    $OrchestratorMd '(?i)(Feature.Scope Completion|Project.Release Checkpoint)'

# =============================================================================
# SCENARIO B: More authorized Waves remain → no checkpoint yet
# =============================================================================
Write-Host ""
Write-Host "--- B: More authorized Waves remain → no checkpoint ---" -ForegroundColor Cyan

Assert-FileContains "B1: lifecycle.yaml: non_trigger_conditions defined" `
    $LifecycleYaml 'non_trigger_conditions'

Assert-FileContains "B2: lifecycle.yaml: individual wave done does not trigger checkpoint" `
    $LifecycleYaml '(?i)(One individual Wave is done|one.*wave.*done.*while.*more|individual wave)'

Assert-FileContains "B3: checkpoint policy: non-trigger condition — more waves remain" `
    $CheckpointPolicy '(?i)(One individual Wave is done while more authorized Waves remain|more.*waves.*remain)'

# =============================================================================
# SCENARIO C: AC requires UI behavior; backend unreachable → Feature Scope incomplete
# =============================================================================
Write-Host ""
Write-Host "--- C: AC requires UI behavior; backend unreachable → incomplete ---" -ForegroundColor Cyan

Assert-FileContains "C1: checkpoint policy: Feature-Scope Completeness Check section" `
    $CheckpointPolicy '(?i)(Feature.Scope Completeness Check|Completeness Check)'

Assert-FileContains "C2: checkpoint policy: real failure mode documented (backend-only false completion)" `
    $CheckpointPolicy '(?i)(backend logic exists|backend.only|false.*complet|uncalled|unreachable.*AC)'

Assert-FileContains "C3: checkpoint policy: UI surface reachability check" `
    $CheckpointPolicy '(?i)(UI Surface Reachability|reachability check|reachable.*UI surface|UI.*reachable)'

Assert-FileContains "C4: checkpoint policy: if UI unreachable, wave is not complete" `
    $CheckpointPolicy '(?i)(Wave is.*not complete|not complete.*UI.*unreachable|unreachable.*wave not)'

Assert-FileContains "C5: mission-completion: false equivalence: checklist done + no UI surface" `
    $MissionPolicy '(?i)(checklist.*wired|UI ACs.*no.*UI entry|backend.*UI.*wired)'

# =============================================================================
# SCENARIO D: All Wave checks pass but unresolved required effect remains → incomplete
# =============================================================================
Write-Host ""
Write-Host "--- D: Required effect unresolved → Feature Scope incomplete ---" -ForegroundColor Cyan

Assert-FileContains "D1: checkpoint policy: required change effects check" `
    $CheckpointPolicy '(?i)(change effect|required.*effect|open required change effect)'

Assert-FileContains "D2: checkpoint policy: FEATURE_SCOPE_COMPLETE requires no open required effect" `
    $CheckpointPolicy '(?i)(No open required change effect|required change effect.*remains unresolved)'

Assert-FileContains "D3: checkpoint policy: deferred scope must be classified" `
    $CheckpointPolicy '(?i)(Unclassified deferrals block|deferred.*classif|classif.*deferred)'

# =============================================================================
# SCENARIO E: User requested release-readiness → review without extra question
# =============================================================================
Write-Host ""
Write-Host "--- E: Release-readiness requested → no extra question ---" -ForegroundColor Cyan

Assert-FileContains "E1: checkpoint policy: behavior by mission intent — B already authorized" `
    $CheckpointPolicy '(?i)(Scenario B.*release.readiness|bring.*release readiness|already authorized.*mission)'

Assert-FileContains "E2: checkpoint policy: explicit release-readiness → proceed autonomously" `
    $CheckpointPolicy '(?i)(proceed autonomously.*RELEASE_READINESS|No additional review question)'

Assert-FileContains "E3: checkpoint policy: RELEASE_READINESS_REVIEW profile defined" `
    $CheckpointPolicy 'RELEASE_READINESS_REVIEW'

# =============================================================================
# SCENARIO F: Normal feature mission completes → concise review offer
# =============================================================================
Write-Host ""
Write-Host "--- F: Normal mission completes → concise offer presented ---" -ForegroundColor Cyan

Assert-FileContains "F1: checkpoint policy: standard offer text defined" `
    $CheckpointPolicy '(?i)(Feature Scope is complete|geplante Feature-Scope ist vollstaendig|planned Feature Scope is complete)'

Assert-FileContains "F2: orchestrator: concise non-technical offer to developer" `
    $OrchestratorMd '(?i)(geplante Feature-Scope ist vollstaendig|planned Feature Scope|Feature.Scope.*vollstaendig)'

Assert-FileContains "F3: checkpoint policy: standard offer lists review profiles in non-technical language" `
    $CheckpointPolicy '(?i)(Quick Health Check|Integrated Product Review|Release Readiness Review)'

Assert-FileContains "F4: checkpoint policy: do not ask about internal terms" `
    $CheckpointPolicy '(?i)(do NOT ask about|Do not.*ask.*VPL|Do not present framework.internal)'

# =============================================================================
# SCENARIO G: User declines review → decision persisted; no repeat
# =============================================================================
Write-Host ""
Write-Host "--- G: Developer declines → decision persisted, no repeat ---" -ForegroundColor Cyan

Assert-FileContains "G1: checkpoint policy: skip semantics defined" `
    $CheckpointPolicy '(?i)(skip.*semantic|Skip semantics|declined.*stored|decision.*persisted)'

Assert-FileContains "G2: checkpoint policy: skip stored in mission-state.yaml" `
    $CheckpointPolicy '(?i)(mission-state\.yaml.*declined|project_release_checkpoint\.status.*declined|status.*declined)'

Assert-FileContains "G3: checkpoint policy: once declined, do not offer again" `
    $CheckpointPolicy '(?i)(Do not offer again|not.*offer.*again|PROJECT_RELEASE_CHECKPOINT_REQUIRED.*does NOT fire again)'

Assert-FileContains "G4: checkpoint policy: skip decision persisted (non-trigger condition)" `
    $CheckpointPolicy '(?i)(developer already declined.*skip decision persisted|skip decision persisted|already.*declined.*current mission)'

Assert-FileContains "G5: mission schema: project_release_checkpoint.status includes declined" `
    $MissionSchema '"declined"'

# =============================================================================
# SCENARIO H: User accepts integrated review → review executed
# =============================================================================
Write-Host ""
Write-Host "--- H: User accepts integrated review → review executed ---" -ForegroundColor Cyan

Assert-FileContains "H1: checkpoint policy: INTEGRATED_PRODUCT_REVIEW profile defined" `
    $CheckpointPolicy 'INTEGRATED_PRODUCT_REVIEW'

Assert-FileContains "H2: checkpoint policy: integrated review covers UI/UX parity" `
    $CheckpointPolicy '(?i)(UI.UX parity|Overall UI.*parity|ui.*fidelity.*integrat)'

Assert-FileContains "H3: checkpoint policy: integrated review covers functional parity" `
    $CheckpointPolicy '(?i)(Functional Parity|functional.*parity|parity.*functional)'

Assert-FileContains "H4: checkpoint policy: integrated review covers cross-wave regression" `
    $CheckpointPolicy '(?i)(Cross.Wave.*[Rr]egression|cross.wave.*integrat)'

Assert-FileContains "H5: checkpoint policy: integrated review covers role coverage" `
    $CheckpointPolicy '(?i)(Role.*authorization|role.*coverage|authorization coverage)'

Assert-FileContains "H6: checkpoint policy: integrated review includes automated tests per profile" `
    $CheckpointPolicy '(?i)(Available automated tests|automated test.*profile|AVAILABLE_CURRENT)'

# =============================================================================
# SCENARIO I: Automated tests present and current → detected, offered/executed
# =============================================================================
Write-Host ""
Write-Host "--- I: Automated tests detected → offered/executed per profile ---" -ForegroundColor Cyan

Assert-FileContains "I1: checkpoint policy: Automated Test Discovery section" `
    $CheckpointPolicy '(?i)(Automated Test Discovery|test automation discovery)'

Assert-FileContains "I2: checkpoint policy: AVAILABLE_CURRENT classification defined" `
    $CheckpointPolicy 'AVAILABLE_CURRENT'

Assert-FileContains "I3: checkpoint policy: if tests safe and current, execute autonomously" `
    $CheckpointPolicy '(?i)(execute.*autonomously.*without.*confirmation|safe.*current.*explicitly.*execute)'

Assert-FileContains "I4: checkpoint policy: detects planning/test-contracts/ and verification-plans/" `
    $CheckpointPolicy '(?i)(planning/test-contracts|TC-NNN\.yaml|VPL-NNN\.yaml|verification-plans)'

Assert-FileContains "I5: checkpoint policy: detects Playwright tests" `
    $CheckpointPolicy '(?i)(Playwright|\.spec\.ts|\.spec\.js|\.test\.ts)'

# =============================================================================
# SCENARIO J: No automation exists → honest result
# =============================================================================
Write-Host ""
Write-Host "--- J: No automation → honest result; no fabrication ---" -ForegroundColor Cyan

Assert-FileContains "J1: checkpoint policy: NO_AUTOMATION classification" `
    $CheckpointPolicy 'NO_AUTOMATION'

Assert-FileContains "J2: checkpoint policy: do not fabricate test automation" `
    $CheckpointPolicy '(?i)(Do not fabricate|no fabricat|not fabricate.*automation)'

Assert-FileContains "J3: checkpoint policy: do not install heavy infrastructure" `
    $CheckpointPolicy '(?i)(do not install.*heavy|heavy infrastructure.*absent|not.*install.*infrastructure)'

# =============================================================================
# SCENARIO K: One infrastructure path blocked → other work continues
# =============================================================================
Write-Host ""
Write-Host "--- K: Partial infrastructure block → other work continues ---" -ForegroundColor Cyan

Assert-FileContains "K1: checkpoint policy: INFRASTRUCTURE_BLOCKED classification" `
    $CheckpointPolicy 'INFRASTRUCTURE_BLOCKED'

Assert-FileContains "K2: mission-completion: partial blockers — blast radius classification" `
    $MissionPolicy '(?i)(blast radius|Partial Blockers)'

Assert-FileContains "K3: mission-completion: one blocked path does not stop whole mission" `
    $MissionPolicy '(?i)(stop.*WHOLE|whole mission only|one.*locator.*unstable.*continue)'

# =============================================================================
# SCENARIO L: Review finds authorized gap → scoped lifecycle return + repair
# =============================================================================
Write-Host ""
Write-Host "--- L: Review finds authorized gap → scoped return and repair ---" -ForegroundColor Cyan

Assert-FileContains "L1: checkpoint policy: Gap Repair section" `
    $CheckpointPolicy '(?i)(Gap Repair|gap repair)'

Assert-FileContains "L2: checkpoint policy: routes to earliest necessary phase" `
    $CheckpointPolicy '(?i)(earliest necessary lifecycle phase|earliest.*phase.*repair|return.*earliest)'

Assert-FileContains "L3: checkpoint policy: repair within accepted scope only" `
    $CheckpointPolicy '(?i)(within accepted scope|authorized.*scope.*only|Do NOT repair.*deferred)'

Assert-FileContains "L4: checkpoint policy: after repair, re-run affected review scope" `
    $CheckpointPolicy '(?i)(Re-run affected review scope|re-run.*review|re.verify.*repair)'

Assert-FileContains "L5: lifecycle.yaml: return routing exists" `
    $LifecycleYaml 'return_routing'

# =============================================================================
# SCENARIO M: Review passes but NFR/privacy/deployment absent → RELEASE_READY not claimed
# =============================================================================
Write-Host ""
Write-Host "--- M: Functional review passes; NFR absent → RELEASE_READY not claimed ---" -ForegroundColor Cyan

Assert-FileContains "M1: checkpoint policy: release-readiness result vocabulary defined" `
    $CheckpointPolicy 'RELEASE_READINESS_NOT_ASSESSED'

Assert-FileContains "M2: checkpoint policy: product correctness not collapsed into production readiness" `
    $CheckpointPolicy '(?i)(Do NOT collapse product correctness|correctness.*production.*readiness|collapse.*production)'

Assert-FileContains "M3: checkpoint policy: RELEASE_READY_PENDING_HUMAN_APPROVAL defined" `
    $CheckpointPolicy 'RELEASE_READY_PENDING_HUMAN_APPROVAL'

Assert-FileContains "M4: checkpoint policy: RELEASE_READINESS_REVIEW excludes NFRs from INTEGRATED_PRODUCT_REVIEW" `
    $CheckpointPolicy '(?i)(non.functional.*RELEASE_READINESS_REVIEW|NFR.*RELEASE_READINESS|Excludes.*NFR|nonfunctional.*readiness.*where)'

Assert-FileContains "M5: checkpoint policy: no Go-Live claim without human approvals" `
    $CheckpointPolicy '(?i)(does not claim Go.Live|Go.Live.*absent.*human|without.*human.*approvals)'

# =============================================================================
# SCENARIO N: Deferred requirements not started automatically
# =============================================================================
Write-Host ""
Write-Host "--- N: Deferred scope not started autonomously ---" -ForegroundColor Cyan

Assert-FileContains "N1: checkpoint policy: next-scope safety section" `
    $CheckpointPolicy '(?i)(Next.Scope Safety|next.scope safety)'

Assert-FileContains "N2: checkpoint policy: do not start deferred NFR/go-live scope autonomously" `
    $CheckpointPolicy '(?i)(start deferred NFR|deferred NFR.go-live|must NOT autonomously)'

Assert-FileContains "N3: checkpoint policy: required order — report readiness before identifying next scope" `
    $CheckpointPolicy '(?i)(report.*readiness.*then|only then.*next.*scope|order.*complete.*offer.*report.*identify)'

# =============================================================================
# SCENARIO O: External Board sync not run before checkpoint completes
# =============================================================================
Write-Host ""
Write-Host "--- O: Board sync not before checkpoint completes ---" -ForegroundColor Cyan

Assert-FileContains "O1: checkpoint policy: do not sync Board before checkpoint" `
    $CheckpointPolicy '(?i)(sync external Board.*features|Board scope.*new features|external Board.*scope)'

# =============================================================================
# SCENARIO P: Terminal-State Guard cannot skip unresolved checkpoint decision
# =============================================================================
Write-Host ""
Write-Host "--- P: Terminal-State Guard cannot skip checkpoint decision ---" -ForegroundColor Cyan

Assert-FileContains "P1: mission-completion: TSG guard check 8 cannot be skipped when applicable" `
    $MissionPolicy '(?i)(PROJECT_RELEASE_CHECKPOINT_REQUIRED.*do NOT return MISSION_COMPLETE|do not.*MISSION_COMPLETE.*checkpoint)'

Assert-FileContains "P2: mission-completion: MISSION_COMPLETE requires checkpoint evaluated" `
    $MissionPolicy '(?i)(MISSION_COMPLETE.*checkpoint.*evaluated|checkpoint.*evaluated.*MISSION_COMPLETE|project.release checkpoint evaluated)'

Assert-FileContains "P3: checkpoint policy: terminal state guard integration section" `
    $CheckpointPolicy '(?i)(Terminal.State Guard Integration|Terminal-State Guard)'

# =============================================================================
# SCENARIO Q: Explicit implementation-only mission → review not auto-run
# =============================================================================
Write-Host ""
Write-Host "--- Q: Implementation-only mission → review not auto-run ---" -ForegroundColor Cyan

Assert-FileContains "Q1: checkpoint policy: Scenario D — implementation-only honored" `
    $CheckpointPolicy '(?i)(Only implement.*current Wave|Scenario D|implementation.only.*honored)'

Assert-FileContains "Q2: checkpoint policy: implementation-only scope → review NOT run" `
    $CheckpointPolicy '(?i)(project.release review NOT run|review.*not.*run.*implementation.only|do NOT run.*automatically)'

Assert-FileContains "Q3: checkpoint policy: implementation-only scope stores declined" `
    $CheckpointPolicy '(?i)(status.*declined.*implementation_only|implementation_only_scope)'

Assert-FileContains "Q4: mission-completion: scope_boundary implementation_only honored" `
    $MissionPolicy '(?i)(implementation.only|implementation_only)'

# =============================================================================
# SCENARIO R: Fresh-session resume → checkpoint state reconstructed
# =============================================================================
Write-Host ""
Write-Host "--- R: Fresh session → checkpoint state reconstructed ---" -ForegroundColor Cyan

Assert-FileContains "R1: checkpoint policy: Scenario C — 'Continue' reconstructs checkpoint" `
    $CheckpointPolicy '(?i)(Continue.*project.*Feature Scope.*complete|Scenario C|reconstruct.*checkpoint)'

Assert-FileContains "R2: checkpoint policy: reconstruct from mission-state.yaml" `
    $CheckpointPolicy '(?i)(Reconstruct.*mission-state\.yaml|mission.state.*reconstruct|planning/mission/mission-state)'

Assert-FileContains "R3: mission schema: project_release_checkpoint block persisted" `
    $MissionSchema 'project_release_checkpoint'

Assert-FileContains "R4: mission schema: project_release_checkpoint.status field" `
    $MissionSchema '"status"'

Assert-FileContains "R5: mission schema: project_release_checkpoint.decided_at field" `
    $MissionSchema 'decided_at'

# =============================================================================
# SCENARIO S: Documentation reflects current behavior
# =============================================================================
Write-Host ""
Write-Host "--- S: Documentation reflects current behavior ---" -ForegroundColor Cyan

Assert-FileContains "S1: README mentions project/release completion checkpoint" `
    $ReadMe '(?i)(project.*release.*checkpoint|feature.*scope.*complet|post.wave.*review|release.readiness.*assessment)'

Assert-FileContains "S2: lifecycle.yaml mentions review_profiles" `
    $LifecycleYaml 'review_profiles'

Assert-FileContains "S3: lifecycle.yaml mentions QUICK_HEALTH_CHECK profile" `
    $LifecycleYaml 'QUICK_HEALTH_CHECK'

Assert-FileContains "S4: orchestrator defines non-technical user interaction" `
    $OrchestratorMd '(?i)(Non-Technical|Nutzer-Interaktion|non.technical.*offer)'

Assert-FileContains "S5: orchestrator: false completion prevention documented" `
    $OrchestratorMd '(?i)(False Completion Prevention|false.*complet.*prevent|Checkliste sagt.*done.*keine.*UI)'

# =============================================================================
# PURITY: No project-specific knowledge in Core
# =============================================================================
Write-Host ""
Write-Host "--- PURITY: No project-specific knowledge ---" -ForegroundColor Cyan

Assert-FileNotContains "PUR1: checkpoint policy: no CapTrack reference" `
    $CheckpointPolicy 'CapTrack'

Assert-FileNotContains "PUR2: checkpoint policy: no KidsCompass reference" `
    $CheckpointPolicy 'KidsCompass'

Assert-FileNotContains "PUR3: checkpoint policy: no Mercedes reference" `
    $CheckpointPolicy '(?i)mercedes'

Assert-FileNotContains "PUR4: mission-completion.md: no CapTrack reference" `
    $MissionPolicy 'CapTrack'

Assert-FileNotContains "PUR5: lifecycle.yaml: no CapTrack reference" `
    $LifecycleYaml 'CapTrack'

# =============================================================================
# SCHEMA INTEGRITY
# =============================================================================
Write-Host ""
Write-Host "--- SCHEMA: mission-state schema extended correctly ---" -ForegroundColor Cyan

Assert-FileContains "SCH1: schema: FEATURE_SCOPE_COMPLETE in completion_boundary" `
    $MissionSchema 'FEATURE_SCOPE_COMPLETE'

Assert-FileContains "SCH2: schema: PROJECT_RELEASE_REVIEW_COMPLETE in completion_boundary" `
    $MissionSchema 'PROJECT_RELEASE_REVIEW_COMPLETE'

Assert-FileContains "SCH3: schema: PROJECT_RELEASE_CHECKPOINT_REQUIRED in terminal_guard_result" `
    $MissionSchema 'PROJECT_RELEASE_CHECKPOINT_REQUIRED'

Assert-FileContains "SCH4: schema: project_release_checkpoint object defined" `
    $MissionSchema 'project_release_checkpoint'

Assert-FileContains "SCH5: schema: review_profile field with correct enum" `
    $MissionSchema 'review_profile'

Assert-FileContains "SCH6: schema: feature_scope_complete boolean field" `
    $MissionSchema 'feature_scope_complete'

Assert-FileContains "SCH7: schema: review_result with readiness vocabulary" `
    $MissionSchema 'review_result'

Assert-FileContains "SCH8: schema: progress.feature_scope field" `
    $MissionSchema 'feature_scope'

Assert-FileContains "SCH9: schema: progress.project_release_review field" `
    $MissionSchema 'project_release_review'

Assert-FileContains "SCH10: schema: PROJECT_HEALTHY_FOR_CURRENT_ACCEPTED_SCOPE result value" `
    $MissionSchema 'PROJECT_HEALTHY_FOR_CURRENT_ACCEPTED_SCOPE'

# =============================================================================
# FINAL SUMMARY
# =============================================================================
Write-Host ""
Write-Host "=== Summary ===" -ForegroundColor White
Write-Host "  PASS: $PassCount" -ForegroundColor Green
if ($FailCount -eq 0) {
    Write-Host "  FAIL: $FailCount" -ForegroundColor Green
} else {
    Write-Host "  FAIL: $FailCount" -ForegroundColor Red
}

if ($FailDetails.Count -gt 0) {
    Write-Host ""
    Write-Host "Failed tests:" -ForegroundColor Red
    foreach ($d in $FailDetails) {
        Write-Host "  $d" -ForegroundColor Red
    }
}

Write-Host ""

if ($FailCount -gt 0) {
    Write-Error "Project/Release Completion Checkpoint test suite FAILED with $FailCount failure(s)."
} else {
    Write-Host "Project/Release Completion Checkpoint test suite PASSED." -ForegroundColor Green
}
