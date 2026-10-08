<#
.SYNOPSIS
    Board Authority Hardening  -- Regression Tests

.DESCRIPTION
    Regression coverage for the MxAgile Board Authority Contract.
    Validates that the external Mendix Epics Board is treated as an optional
    organizational status projection  -- not a scope authority, lifecycle driver,
    or default continuation source.

    Scenarios:
    A. Board contains new stories → no scope change
    B. Board story changes → no automatic Wave/reopen
    C. Feature Scope complete → Project/Release Checkpoint before Board considerations
    D. "Continue with the project" → no automatic Board story selection
    E. Board disabled/not configured → no Board behavior
    F. Completed authorized scope → optional organizational status reflection
    G. Explicit user selection of Board story → normal intake/refinement as new input
    H. No external Board access required to complete/verify existing authorized scope

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
$BacklogSync      = Join-Path $RepoRoot '.mxagile/policies/backlog-sync.md'
$SourcePriority   = Join-Path $RepoRoot '.mxagile/policies/source-priority.md'
$MissionPolicy    = Join-Path $RepoRoot '.mxagile/policies/mission-completion.md'
$CheckpointPolicy = Join-Path $RepoRoot '.mxagile/policies/project-release-checkpoint.md'
$OrchestratorMd   = Join-Path $RepoRoot '.mxagile/orchestrator.md'
$GlossaryYaml     = Join-Path $RepoRoot '.mxagile/GLOSSARY.yaml'
$DiscoveryAgent   = Join-Path $RepoRoot '.mxagile/agents/discovery-agent.md'
$RefinementAgent  = Join-Path $RepoRoot '.mxagile/agents/refinement-agent.md'
$DiscoverySkill   = Join-Path $RepoRoot '.mxagile/skills/discovery.md'
$RefinementSkill  = Join-Path $RepoRoot '.mxagile/skills/refinement.md'
$GateToRefinement = Join-Path $RepoRoot '.mxagile/skills/gate-to-refinement.md'
$ExecutionWaves   = Join-Path $RepoRoot 'planning/execution-waves.md'
$PlanningReadme   = Join-Path $RepoRoot 'planning/README.md'

Write-Host ""
Write-Host "=== Board Authority Hardening Tests ===" -ForegroundColor White
Write-Host ""

# PREREQUISITE
Write-Host "PREREQUISITE: Canonical files exist" -ForegroundColor Cyan
Assert-FileExists "backlog-sync.md exists"          $BacklogSync
Assert-FileExists "source-priority.md exists"       $SourcePriority
Assert-FileExists "mission-completion.md exists"    $MissionPolicy
Assert-FileExists "project-release-checkpoint.md exists" $CheckpointPolicy
Assert-FileExists "orchestrator.md exists"          $OrchestratorMd
Assert-FileExists "GLOSSARY.yaml exists"            $GlossaryYaml
Assert-FileExists "discovery-agent.md exists"       $DiscoveryAgent
Assert-FileExists "refinement-agent.md exists"      $RefinementAgent

# =============================================================================
# SCENARIO A: Board contains new stories → no scope change
# =============================================================================
Write-Host ""
Write-Host "--- A: Board contains new stories → no scope change ---" -ForegroundColor Cyan

Assert-FileContains "A1: backlog-sync: Board Authority Contract section exists" `
    $BacklogSync '(?i)Board Authority Contract'

Assert-FileContains "A2: backlog-sync: Board MUST NOT create scope" `
    $BacklogSync '(?i)(MUST NOT.*create.*scope|create MxAgile scope)'

Assert-FileContains "A3: backlog-sync: Board MUST NOT extend mission" `
    $BacklogSync '(?i)(MUST NOT.*extend.*mission|extend an existing mission)'

Assert-FileContains "A4: backlog-sync: Board MUST NOT authorize implementation" `
    $BacklogSync '(?i)(MUST NOT.*authorize.*implementation|authorize implementation)'

Assert-FileContains "A5: backlog-sync: mere existence not authorization" `
    $BacklogSync '(?i)(Mere existence on the Board is not|existence.*is not.*authorization)'

Assert-FileContains "A6: backlog-sync: Scope-Separation Guard section exists" `
    $BacklogSync '(?i)Scope.Separation Guard'

Assert-FileContains "A7: backlog-sync: forbidden table  -- new stories no scope" `
    $BacklogSync '(?i)(Board.Sync discovers new stories.*scope|agent adds them to mission scope)'

Assert-FileContains "A8: mission-completion: false equivalence  -- Board new stories" `
    $MissionPolicy '(?i)(Board contains new.*stories.*NOT authorized scope|Board.*new.*NOT authorized)'

Assert-FileContains "A9: discovery-agent: Board stories are Rang-3 context only" `
    $DiscoveryAgent '(?i)(Rang.3.Kontext|Board.*autorisieren.*keinen Scope)'

Assert-FileContains "A10: discovery-skill: Board-Sync is read-only context" `
    $DiscoverySkill '(?i)(read.only Kontextanreicherung|importiert oder autorisiert.*keinen.*Scope)'

# =============================================================================
# SCENARIO B: Board story changes → no automatic Wave/reopen
# =============================================================================
Write-Host ""
Write-Host "--- B: Board story changes → no automatic Wave/reopen ---" -ForegroundColor Cyan

Assert-FileContains "B1: backlog-sync: Board MUST NOT create or reopen Wave" `
    $BacklogSync '(?i)(MUST NOT.*reopen|create or reopen a Wave)'

Assert-FileContains "B2: backlog-sync: forbidden  -- Board story changes no Wave" `
    $BacklogSync '(?i)(Board story changes.*Wave reopened|Board does not drive lifecycle)'

Assert-FileContains "B3: mission-completion: false equivalence  -- Board story changed" `
    $MissionPolicy '(?i)(Board story changed.*NOT.*Wave reopen|Board does not drive lifecycle)'

Assert-FileContains "B4: refinement-agent: Board changes no new Waves" `
    $RefinementAgent '(?i)(Board.Aenderungen.*KEINE neuen Waves|Board.*keinen Scope)'

Assert-FileContains "B5: refinement-skill: Board changes no new scope" `
    $RefinementSkill '(?i)(Board.Aenderungen autorisieren keinen neuen Scope|Board.*Rang.3)'

# =============================================================================
# SCENARIO C: Feature Scope complete → Checkpoint before Board considerations
# =============================================================================
Write-Host ""
Write-Host "--- C: Feature Scope complete → Checkpoint before Board ---" -ForegroundColor Cyan

Assert-FileContains "C1: checkpoint: do not sync Board before checkpoint" `
    $CheckpointPolicy '(?i)(sync external Board.*features|Board scope.*new features)'

Assert-FileContains "C2: checkpoint: next-scope safety  -- no Board backlog feature" `
    $CheckpointPolicy '(?i)(choose a Board backlog feature|select any Board story)'

Assert-FileContains "C3: checkpoint: Board Authority Guard post-checkpoint" `
    $CheckpointPolicy '(?i)(Board Authority Guard.*post.checkpoint|NOT autonomous Board story selection)'

Assert-FileContains "C4: checkpoint: required order  -- report before next scope" `
    $CheckpointPolicy '(?i)(request product prioritization.*NOT.*Board|product prioritization from the developer)'

Assert-FileContains "C5: orchestrator: Board Authority Guard section" `
    $OrchestratorMd '(?i)Board Authority Guard'

Assert-FileContains "C6: orchestrator: Board-Sync in Verifying is reporting not import" `
    $OrchestratorMd '(?i)(Board.Sync.*Reporting.*nicht Scope.Import|organisatorische Status.Reflektion)'

Assert-FileContains "C7: backlog-sync: forbidden  -- Feature Scope complete no Board-Sync for next work" `
    $BacklogSync '(?i)(Feature Scope complete.*Board.Sync.*find next work|Board is not the continuation source)'

# =============================================================================
# SCENARIO D: "Continue with the project" → no automatic Board story selection
# =============================================================================
Write-Host ""
Write-Host "--- D: Continue → no automatic Board story selection ---" -ForegroundColor Cyan

Assert-FileContains "D1: mission-completion: Continue guard  -- never select Board item" `
    $MissionPolicy '(?i)(Continue with the project.*MUST NEVER select.*Board|MUST NEVER select a Board item)'

Assert-FileContains "D2: mission-completion: Continue guard  -- request product prioritization" `
    $MissionPolicy '(?i)(request product prioritization.*developer|not.*autonomously import Board stories)'

Assert-FileContains "D3: mission-completion: false equivalence  -- Board more stories not continuation" `
    $MissionPolicy '(?i)(Feature Scope complete.*Board.*NOT.*continuation trigger|Board has more stories)'

Assert-FileContains "D4: checkpoint: Scenario D  -- do not select Board story" `
    $CheckpointPolicy '(?i)(Do NOT select a Board story.*solely|Do NOT.*Board story.*exists on the Board)'

Assert-FileContains "D5: checkpoint: Scenario D  -- request product prioritization" `
    $CheckpointPolicy '(?i)(request product prioritization from the developer)'

Assert-FileContains "D6: backlog-sync: forbidden  -- Continue selects Board story" `
    $BacklogSync '(?i)(Continue with the project.*agent selects.*Board|Developer.*product authority selects scope)'

Assert-FileContains "D7: orchestrator: Board Authority Guard  -- product prioritization not Board selection" `
    $OrchestratorMd '(?i)(product prioritization.*NOT Board story selection|Absence.*new authorized scope)'

# =============================================================================
# SCENARIO E: Board disabled/not configured → no Board behavior
# =============================================================================
Write-Host ""
Write-Host "--- E: Board disabled → no Board behavior ---" -ForegroundColor Cyan

Assert-FileContains "E1: backlog-sync: Board Authority Contract  -- no Board behavior when absent" `
    $BacklogSync '(?i)(experience no Board.related lifecycle|no Board.related.*prompts)'

Assert-FileContains "E2: backlog-sync: Board is optional" `
    $BacklogSync '(?i)(optional.*D52|optional organizational status projection)'

Assert-FileContains "E3: source-priority: Board-Sync optional D52" `
    $SourcePriority '(?i)(Board.Sync ist optional|Fehlendes Board blockiert keinen Gate)'

Assert-FileContains "E4: backlog-sync: forbidden  -- Board disabled but prompts shown" `
    $BacklogSync '(?i)(Optional means invisible when absent|Board disabled.*no Board.related prompts)'

Assert-FileContains "E5: gate-to-refinement: Board sync does not block gate" `
    $GateToRefinement '(?i)(Board.Sync.*blockiert.*Gate NICHT|fehlender.*veralteter Board.Sync)'

Assert-FileContains "E6: discovery-skill: Board-Sync conditional on configuration" `
    $DiscoverySkill '(?i)(nur wenn Board konfiguriert|optional.*D52)'

Assert-FileContains "E7: planning/README: Board traceability fields optional" `
    $PlanningReadme '(?i)(Optionale Board.Traceability|Projekte ohne Board.Integration)'

Assert-FileContains "E8: execution-waves: Waves exist independently of Board" `
    $ExecutionWaves '(?i)(unabhaengig.*externen Board|MxAgile.Konstrukte)'

# =============================================================================
# SCENARIO F: Completed authorized scope → optional organizational status reflection
# =============================================================================
Write-Host ""
Write-Host "--- F: Completed scope → optional status reflection ---" -ForegroundColor Cyan

Assert-FileContains "F1: backlog-sync: Board-Completed-Scope Reflection section" `
    $BacklogSync '(?i)(Board.Completed.Scope Reflection|status reflection)'

Assert-FileContains "F2: backlog-sync: direction of authority  -- scope to Board not reverse" `
    $BacklogSync '(?i)(MxAgile authorized scope.*optional Board status reflection|direction of authority)'

Assert-FileContains "F3: checkpoint: offer organizational Board completion reflection" `
    $CheckpointPolicy '(?i)(organizational Board completion reflection|status only)'

Assert-FileContains "F4: orchestrator: Board-Sync in Verifying is organizational status" `
    $OrchestratorMd '(?i)(organisatorische Status.Reflektion|Reporting.*nicht Scope.Import)'

# =============================================================================
# SCENARIO G: Explicit user selection → normal intake/refinement
# =============================================================================
Write-Host ""
Write-Host "--- G: Explicit user selection → normal intake as new input ---" -ForegroundColor Cyan

Assert-FileContains "G1: backlog-sync: explicit developer selection may enter intake" `
    $BacklogSync '(?i)(Explicit user selection.*may enter normal intake|developer selects the scope)'

Assert-FileContains "G2: backlog-sync: developer selection does not grant Board authority" `
    $BacklogSync '(?i)(without granting the Board itself.*authority|Board is only the surface)'

Assert-FileContains "G3: source-priority: Board-Scope-Abgrenzung  -- explicit selection required" `
    $SourcePriority '(?i)(Entwickler.*autorisierte Produktautoritaet.*explizit.*neuen Scope|Board.Scope.Abgrenzung)'

# =============================================================================
# SCENARIO H: No external Board access required for existing authorized scope
# =============================================================================
Write-Host ""
Write-Host "--- H: No Board access needed for existing authorized scope ---" -ForegroundColor Cyan

Assert-FileContains "H1: source-priority: Board missing does not block gate" `
    $SourcePriority '(?i)(Fehlendes Board blockiert keinen Gate)'

Assert-FileContains "H2: gate-to-refinement: Board sync does not block gate" `
    $GateToRefinement '(?i)(blockiert das Gate NICHT|Board.Sync does not block)'

Assert-FileContains "H3: backlog-sync: no Board does not block process" `
    $BacklogSync '(?i)(Prozess zu blockieren|entfallen.*ohne.*blockieren)'

Assert-FileContains "H4: orchestrator: Board Authority Guard  -- no Board needed for completion" `
    $OrchestratorMd '(?i)(without Board integration.*no Board.related behavior|Board.*optional organizational)'

# =============================================================================
# GLOSSARY: Board terms use correct authority language
# =============================================================================
Write-Host ""
Write-Host "--- GLOSSARY: Board terms hardened ---" -ForegroundColor Cyan

Assert-FileContains "GL1: Mendix_Epics_Board: optional organizational status projection" `
    $GlossaryYaml '(?i)(optional organizational status projection|Rank 3 context source)'

Assert-FileNotContains "GL2: Mendix_Epics_Board: no 'source of truth' for Board" `
    $GlossaryYaml '(?i)Mendix_Epics_Board[\s\S]{0,200}source of truth'

Assert-FileContains "GL3: Mendix_Epics_Board: agent hint  -- no scope authorization" `
    $GlossaryYaml '(?i)(Board item existence as scope authorization|not treat Board item)'

Assert-FileContains "GL4: MxScrumMaster: no 'source of truth' language" `
    $GlossaryYaml '(?i)(optional organizational status projection.*tracking|does not authorize MxAgile scope)'

Assert-FileContains "GL5: Derived_work_artifact: derived from Requirements and Mockups" `
    $GlossaryYaml '(?i)(derived from.*Requirements and Mockups|Rank 1 sources)'

Assert-FileContains "GL6: Derived_work_artifact: Board-Story-ID is optional traceability" `
    $GlossaryYaml '(?i)(Board.Story.ID.*optional traceability|optional traceability.*not authority)'

Assert-FileContains "GL7: Implementation_Wave: Waves independent of Board" `
    $GlossaryYaml '(?i)(independently of.*external Board|not Board sprints)'

# =============================================================================
# CROSS-FILE CONSISTENCY: Authority direction enforced everywhere
# =============================================================================
Write-Host ""
Write-Host "--- CROSS-FILE: Authority direction consistent ---" -ForegroundColor Cyan

Assert-FileNotContains "XF1: backlog-sync: no 'Board bleibt verbindlich'" `
    $BacklogSync '(?i)Board bleibt verbindlich'

Assert-FileNotContains "XF2: source-priority: Board not primary for Scope" `
    $SourcePriority '(?i)Prioritaet.*Reihenfolge.*Scope.*Board'

Assert-FileNotContains "XF3: execution-waves: no 'Board-Sprint.*bleiben verbindlich'" `
    $ExecutionWaves '(?i)Board.Sprint.*bleiben verbindlich'

Assert-FileNotContains "XF4: execution-waves: no 'ausschliesslich Board-Story-IDs'" `
    $ExecutionWaves '(?i)referenziert ausschliesslich Board.Story.IDs'

Assert-FileNotContains "XF5: planning/README: no 'Ableitungen aus Mendix-Board-Stories'" `
    $PlanningReadme '(?i)Ableitungen aus Mendix.Board.Stories'

Assert-FileContains "XF6: planning/README: derived from MxAgile-authorized Requirements" `
    $PlanningReadme '(?i)(MxAgile.autorisiert|Rang.1.Quellen)'

Assert-FileContains "XF7: backlog-sync: Board-Story-ID optional traceability not authority" `
    $BacklogSync '(?i)(optional.*Traceability.*nicht Autoritaet|Board.Story.ID.*optional)'

# =============================================================================
# PURITY: No project-specific knowledge in Core
# =============================================================================
Write-Host ""
Write-Host "--- PURITY: No project-specific knowledge ---" -ForegroundColor Cyan

Assert-FileNotContains "PUR1: backlog-sync: no CapTrack reference" `
    $BacklogSync 'CapTrack'

Assert-FileNotContains "PUR2: backlog-sync: no KidsCompass reference" `
    $BacklogSync 'KidsCompass'

Assert-FileNotContains "PUR3: backlog-sync: no Mercedes reference" `
    $BacklogSync '(?i)mercedes'

Assert-FileNotContains "PUR4: glossary: no CapTrack reference" `
    $GlossaryYaml 'CapTrack'

Assert-FileNotContains "PUR5: orchestrator: no CapTrack reference" `
    $OrchestratorMd 'CapTrack'

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
    Write-Error "Board Authority Hardening test suite FAILED with $FailCount failure(s)."
} else {
    Write-Host "Board Authority Hardening test suite PASSED." -ForegroundColor Green
}
