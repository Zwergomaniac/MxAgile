<#
.SYNOPSIS
    Legacy Completion Reconciliation — Regression Tests

.DESCRIPTION
    Regression coverage for the MxAgile Legacy Completion Reconciliation policy.
    Validates that canonical framework sources contain the contracts required to:

    - Classify historical Waves using evidence rather than stored phase alone
    - Promote VERIFIED_LEGACY_STATE without requiring implementation/verification replay
    - Apply canonical-state-wins authority when cache and canonical disagree
    - Ignore stale historical report markers when current canonical evidence is newer
    - Reconcile partial checklists against stronger acceptance evidence
    - Exclude DEFERRED_OUTSIDE_FEATURE_SCOPE from FEATURE_SCOPE_COMPLETE blocking
    - Handle SUPERSEDED artifacts as traceability-only
    - Avoid creating scope from requirement numbering gaps
    - Surface UNKNOWN_REQUIRES_RECONCILIATION as a legitimate blocker
    - Apply Observe-Before-Mutate to reconciliation repairs
    - Reproduce canonical state on fresh-session re-sync without stale-cache regression

    Scenarios:
    A. Legacy Wave phase=verifying + sufficient completion evidence
       → VERIFIED_LEGACY_STATE → no implementation replay
    B. Legacy Wave phase=verifying + genuine missing accepted scope
       → CURRENT_REQUIRED_SCOPE
    C. Canonical state=done, scratch cache=verifying
       → canonical state wins
    D. Stale historical report says Review required, newer canonical evidence says complete
       → no reopening
    E. Old checklist partial, stronger accepted evidence proves completion
       → reconcile metadata rather than repeat implementation
    F. Deferred Go-Live/NFR scope
       → does not block FEATURE_SCOPE_COMPLETE
       → may block RELEASE_READY
    G. Superseded revision
       → retained for traceability → no scope reactivation
    H. Requirement numbering gap
       → no automatic scope creation
    I. Unclassified legacy requirement with insufficient provenance
       → UNKNOWN_REQUIRES_RECONCILIATION → no fabricated authorization
    J. Historical note contradicted by current repository evidence
       → current evidence wins with provenance
    K. Prepared mutation becomes unnecessary after new evidence
       → mutation not executed
    L. Fresh-session re-sync
       → reproduces reconciled canonical state without stale-cache regression

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
$LegacyPolicy        = Join-Path $RepoRoot '.mxagile/policies/legacy-completion-reconciliation.md'
$CheckpointPolicy    = Join-Path $RepoRoot '.mxagile/policies/project-release-checkpoint.md'
$MissionPolicy       = Join-Path $RepoRoot '.mxagile/policies/mission-completion.md'
$ReconciliationMd    = Join-Path $RepoRoot '.mxagile/policies/reconciliation.md'
$OrchestratorMd      = Join-Path $RepoRoot '.mxagile/orchestrator.md'
$GlossaryYaml        = Join-Path $RepoRoot '.mxagile/GLOSSARY.yaml'

Write-Host ""
Write-Host "=== Legacy Completion Reconciliation Tests ===" -ForegroundColor White
Write-Host ""

# PREREQUISITE: canonical files exist
Write-Host "PREREQUISITE: Canonical files exist" -ForegroundColor Cyan
Assert-FileExists "legacy-completion-reconciliation.md exists"  $LegacyPolicy
Assert-FileExists "project-release-checkpoint.md exists"        $CheckpointPolicy
Assert-FileExists "mission-completion.md exists"                $MissionPolicy
Assert-FileExists "reconciliation.md exists"                    $ReconciliationMd
Assert-FileExists "orchestrator.md exists"                      $OrchestratorMd
Assert-FileExists "GLOSSARY.yaml exists"                        $GlossaryYaml

# =============================================================================
# SCENARIO A: Legacy Wave phase=verifying + sufficient evidence
# → VERIFIED_LEGACY_STATE → no implementation replay
# =============================================================================
Write-Host ""
Write-Host "--- A: Legacy Wave + sufficient evidence → VERIFIED_LEGACY_STATE ---" -ForegroundColor Cyan

Assert-FileContains "A1: legacy policy defines VERIFIED_LEGACY_STATE classification" `
    $LegacyPolicy 'VERIFIED_LEGACY_STATE'

Assert-FileContains "A2: legacy policy: VERIFIED_LEGACY_STATE requires acceptance evidence" `
    $LegacyPolicy '(?i)(wave report|acceptance.*evidence|acceptance_gate.*passed|acceptance campaign)'

Assert-FileContains "A3: legacy policy: VERIFIED_LEGACY_STATE permits count as done without replay" `
    $LegacyPolicy '(?i)(count as done|counted.*done|without.*repeat|without.*replay|no.*replay)'

Assert-FileContains "A4: legacy policy: phase != done is NOT automatically incomplete" `
    $LegacyPolicy '(?i)(phase.*!=.*done.*NOT|phase != done.*MUST NOT|phase.*not.*done.*not.*automatically)'

Assert-FileContains "A5: checkpoint policy: legacy reconciliation step 0 defined" `
    $CheckpointPolicy '(?i)(Legacy Scope Reconciliation|Step 0|legacy.*reconciliation.*step)'

Assert-FileContains "A6: checkpoint policy: VERIFIED_LEGACY_STATE → count as done" `
    $CheckpointPolicy '(?i)(VERIFIED_LEGACY_STATE.*count as done|count as done.*VERIFIED_LEGACY_STATE)'

Assert-FileContains "A7: mission-completion: historical wave phase != done not automatically incomplete" `
    $MissionPolicy '(?i)(historical.*wave|phase.*not.*done.*not.*automatically|VERIFIED_LEGACY_STATE)'

Assert-FileContains "A8: orchestrator: legacy reconciliation before concluding historical incompleteness" `
    $OrchestratorMd '(?i)(VERIFIED_LEGACY_STATE|legacy.*reconciliation.*historisch|legacy-completion-reconciliation)'

# =============================================================================
# SCENARIO B: Legacy Wave phase=verifying + genuine missing accepted scope
# → CURRENT_REQUIRED_SCOPE
# =============================================================================
Write-Host ""
Write-Host "--- B: Legacy Wave + missing accepted scope → CURRENT_REQUIRED_SCOPE ---" -ForegroundColor Cyan

Assert-FileContains "B1: legacy policy defines CURRENT_REQUIRED_SCOPE classification" `
    $LegacyPolicy 'CURRENT_REQUIRED_SCOPE'

Assert-FileContains "B2: legacy policy: CURRENT_REQUIRED_SCOPE = accepted, authorized, not yet verified" `
    $LegacyPolicy '(?i)(accepted.*authorized.*not yet|Accepted.*authorized.*not.*fully)'

Assert-FileContains "B3: legacy policy: CURRENT_REQUIRED_SCOPE → genuine remaining work" `
    $LegacyPolicy '(?i)(genuine remaining work|genuine.*remaining)'

Assert-FileContains "B4: legacy policy: implementation evidence alone is NOT VERIFIED_LEGACY_STATE" `
    $LegacyPolicy '(?i)(implementation.*evidence alone.*MUST NOT|Implementation.*alone.*not.*VERIFIED)'

# =============================================================================
# SCENARIO C: Canonical state=done, scratch cache=verifying
# → canonical state wins
# =============================================================================
Write-Host ""
Write-Host "--- C: Canonical=done, cache=verifying → canonical wins ---" -ForegroundColor Cyan

Assert-FileContains "C1: legacy policy: canonical state wins authority order defined" `
    $LegacyPolicy '(?i)(Canonical State.*Wins|Canonical State Authority Order|canonical.*wins)'

Assert-FileContains "C2: legacy policy: canonical state outranks scratch/session cache" `
    $LegacyPolicy '(?i)(scratch.*session.*cache|\.concord.scratch|session cache)'

Assert-FileContains "C3: legacy policy: session cache reconstructed from canonical, not vice versa" `
    $LegacyPolicy '(?i)(reconstruct.*session.*canonical|canonical.*reconstruct.*cache|not.*reverse|NOT.*vice versa)'

Assert-FileContains "C4: legacy policy: do NOT downgrade canonical completion" `
    $LegacyPolicy '(?i)(do NOT downgrade|not.*downgrad|never.*downgrad)'

Assert-FileContains "C5: mission-completion: canonical state wins over cache (false equivalence)" `
    $MissionPolicy '(?i)(Wave phase.*verifying.*session cache.*canonical.*wins|canonical state wins|stale.*cache.*canonical)'

Assert-FileContains "C6: orchestrator: canonical state wins on conflict with session cache" `
    $OrchestratorMd '(?i)(kanonische.*Zustand gewinnt|canonical.*wins.*cache|Kanonischer Zustand gewinnt)'

# =============================================================================
# SCENARIO D: Stale historical report says Review required, newer canonical evidence complete
# → no reopening
# =============================================================================
Write-Host ""
Write-Host "--- D: Stale historical marker → no reopening when current evidence is complete ---" -ForegroundColor Cyan

Assert-FileContains "D1: legacy policy: stale historical metadata section" `
    $LegacyPolicy '(?i)(Stale Historical Metadata|stale.*historical.*metadata)'

Assert-FileContains "D2: legacy policy: Review required marker must not automatically become current work" `
    $LegacyPolicy '(?i)(Review required|review required.*MUST NOT|review required.*must not.*current work)'

Assert-FileContains "D3: legacy policy: verify before acting on stale marker" `
    $LegacyPolicy '(?i)(Verification-Before-Action|verify before.*stale|Before.*acting.*stale)'

Assert-FileContains "D4: legacy policy: new evidence can invalidate stale historical notes" `
    $LegacyPolicy '(?i)(new.*evidence.*invalidat|newer.*evidence.*invalidat|current evidence.*outranks)'

Assert-FileContains "D5: mission-completion: historical report marker does not override canonical evidence" `
    $MissionPolicy '(?i)(historical report.*does not override|stale historical marker|Review required.*NOT a current)'

# =============================================================================
# SCENARIO E: Old checklist partial, stronger accepted evidence proves completion
# → reconcile metadata rather than repeat implementation
# =============================================================================
Write-Host ""
Write-Host "--- E: Partial checklist + acceptance evidence → reconcile, not repeat ---" -ForegroundColor Cyan

Assert-FileContains "E1: legacy policy: checklist is lower-authority than acceptance evidence" `
    $LegacyPolicy '(?i)(checklist|Checklists.*lower|Rank.*checklists|checklist.*implementation detail)'

Assert-FileContains "E2: legacy policy: VERIFIED_LEGACY_STATE promotion criteria include acceptance records" `
    $LegacyPolicy '(?i)(acceptance records|wave report.*acceptance_gate.*passed|acceptance.*campaign.*result)'

Assert-FileContains "E3: legacy policy: VERIFIED_LEGACY_STATE permits count as done without repeat" `
    $LegacyPolicy '(?i)(without repeating|without.*repeat.*implement|no.*replay|not.*repeat.*implementat)'

Assert-FileContains "E4: mission-completion: old checklist open item + wave report passed = not currently open" `
    $MissionPolicy '(?i)(old checklist.*open.*wave report.*acceptance_gate.*passed|checklist.*open.*acceptance evidence|acceptance evidence outranks checklist)'

# =============================================================================
# SCENARIO F: Deferred Go-Live/NFR scope
# → does not block FEATURE_SCOPE_COMPLETE → may block RELEASE_READY
# =============================================================================
Write-Host ""
Write-Host "--- F: Deferred NFR/Go-Live → does not block FEATURE_SCOPE_COMPLETE ---" -ForegroundColor Cyan

Assert-FileContains "F1: legacy policy defines DEFERRED_OUTSIDE_FEATURE_SCOPE classification" `
    $LegacyPolicy 'DEFERRED_OUTSIDE_FEATURE_SCOPE'

Assert-FileContains "F2: legacy policy: deferred NFR/Go-Live does NOT block FEATURE_SCOPE_COMPLETE" `
    $LegacyPolicy '(?i)(Does NOT block.*FEATURE_SCOPE_COMPLETE|does not block.*FEATURE_SCOPE_COMPLETE)'

Assert-FileContains "F3: legacy policy: deferred scope may block RELEASE_READY" `
    $LegacyPolicy '(?i)(may block.*RELEASE_READY|RELEASE_READY.*block|may block RELEASE)'

Assert-FileContains "F4: legacy policy: circular semantics prohibition" `
    $LegacyPolicy '(?i)(Circular Semantics Prohibition|circular semantics|circular.*semantic)'

Assert-FileContains "F5: legacy policy: NFR/Go-Live MUST NOT block FEATURE_SCOPE_COMPLETE" `
    $LegacyPolicy '(?i)(NFR.*MUST NOT block|Go.live.*MUST NOT block|MUST NOT.*block FEATURE_SCOPE_COMPLETE)'

Assert-FileContains "F6: checkpoint policy: deferred scope excluded from completeness check" `
    $CheckpointPolicy '(?i)(DEFERRED_OUTSIDE_FEATURE_SCOPE.*exclude|exclude.*DEFERRED_OUTSIDE_FEATURE_SCOPE)'

# =============================================================================
# SCENARIO G: Superseded revision
# → retained for traceability → no scope reactivation
# =============================================================================
Write-Host ""
Write-Host "--- G: Superseded revision → traceability only, no scope reactivation ---" -ForegroundColor Cyan

Assert-FileContains "G1: legacy policy defines SUPERSEDED classification" `
    $LegacyPolicy 'SUPERSEDED'

Assert-FileContains "G2: legacy policy: SUPERSEDED retained for traceability" `
    $LegacyPolicy '(?i)(retained for traceability|traceability.*SUPERSEDED|SUPERSEDED.*traceability)'

Assert-FileContains "G3: legacy policy: SUPERSEDED is not current scope authorization" `
    $LegacyPolicy '(?i)(NOT current scope authorization|SUPERSEDED.*not.*current.*scope|NOT.*scope.*authorization)'

Assert-FileContains "G4: legacy policy: SUPERSEDED artifact existence is not incomplete scope" `
    $LegacyPolicy '(?i)(artifact existence.*not.*incomplete|existence.*NOT.*incomplete|SUPERSEDED.*not.*incomplete)'

Assert-FileContains "G5: legacy policy: do not create work items from superseded scope" `
    $LegacyPolicy '(?i)(Do NOT create work items.*superseded|not.*create.*work.*superseded|without explicit re-authorization)'

# =============================================================================
# SCENARIO H: Requirement numbering gap
# → no automatic scope creation
# =============================================================================
Write-Host ""
Write-Host "--- H: Numbering gap → no automatic scope creation ---" -ForegroundColor Cyan

Assert-FileContains "H1: legacy policy: requirement migration gaps section" `
    $LegacyPolicy '(?i)(Requirement Migration Gaps|requirement.*migration.*gap)'

Assert-FileContains "H2: legacy policy: numbering gap does NOT mean missing authorized scope" `
    $LegacyPolicy '(?i)(numbering gap.*MUST NOT|gap.*not.*authorized|MUST NOT.*interpreted as missing)'

Assert-FileContains "H3: legacy policy: do not create requirements to make numbering continuous" `
    $LegacyPolicy '(?i)(Do NOT create canonical requirements.*numbering continuous|not.*create.*requirements.*continuous)'

Assert-FileContains "H4: legacy policy: authority classification for migration requirements defined" `
    $LegacyPolicy '(?i)(migrated_renumbered|absorbed|draft_never_authorized|external_source_not_authorized)'

# =============================================================================
# SCENARIO I: Unclassified legacy requirement with insufficient provenance
# → UNKNOWN_REQUIRES_RECONCILIATION → no fabricated authorization
# =============================================================================
Write-Host ""
Write-Host "--- I: Unclassified legacy requirement → UNKNOWN_REQUIRES_RECONCILIATION ---" -ForegroundColor Cyan

Assert-FileContains "I1: legacy policy defines UNKNOWN_REQUIRES_RECONCILIATION classification" `
    $LegacyPolicy 'UNKNOWN_REQUIRES_RECONCILIATION'

Assert-FileContains "I2: legacy policy: UNKNOWN is legitimate reconciliation blocker" `
    $LegacyPolicy '(?i)(legitimate reconciliation blocker|legitimate.*blocker|UNKNOWN.*legitimate)'

Assert-FileContains "I3: legacy policy: do not fabricate authorization for UNKNOWN" `
    $LegacyPolicy '(?i)(do not fabricate authorization|not.*fabricate.*authoriz|UNKNOWN.*not.*fabricate)'

Assert-FileContains "I4: legacy policy: UNKNOWN blocks until classified" `
    $LegacyPolicy '(?i)(blocks until classified|block.*until.*classified|UNKNOWN.*blocker.*classified)'

Assert-FileContains "I5: glossary: UNKNOWN_REQUIRES_RECONCILIATION defined" `
    $GlossaryYaml 'UNKNOWN_REQUIRES_RECONCILIATION'

# =============================================================================
# SCENARIO J: Historical note contradicted by current repository evidence
# → current evidence wins with provenance
# =============================================================================
Write-Host ""
Write-Host "--- J: Historical note contradicted by current evidence → current wins ---" -ForegroundColor Cyan

Assert-FileContains "J1: legacy policy: current evidence outranks historical notes" `
    $LegacyPolicy '(?i)(current evidence.*outranks|current.*wins.*provenance|Current evidence always outranks)'

Assert-FileContains "J2: legacy policy: verification-before-action: check current canonical first" `
    $LegacyPolicy '(?i)(Read the current canonical evidence|re-read.*current|current canonical.*first)'

Assert-FileContains "J3: legacy policy: new evidence invalidates stale historical notes" `
    $LegacyPolicy '(?i)(New repository evidence.*invalidat|new.*evidence.*invalidat.*stale.*notes)'

Assert-FileContains "J4: legacy policy: provenance preservation when classifying VERIFIED_LEGACY_STATE" `
    $LegacyPolicy '(?i)(Provenance Preservation|record.*reconciliation|reconciliation.*basis|provenance)'

# =============================================================================
# SCENARIO K: Prepared mutation becomes unnecessary after new evidence
# → mutation not executed
# =============================================================================
Write-Host ""
Write-Host "--- K: Prepared mutation unnecessary after new evidence → not executed ---" -ForegroundColor Cyan

Assert-FileContains "K1: legacy policy: observe-before-mutate section in reconciliation" `
    $LegacyPolicy '(?i)(Observe.Before.Mutate in Reconciliation|observe.*before.*mutate.*reconcili)'

Assert-FileContains "K2: legacy policy: re-read before executing prepared repair" `
    $LegacyPolicy '(?i)(Re-read.*current.*canonical|re.read.*relevant.*current|Verify.*prepared mutation remains necessary)'

Assert-FileContains "K3: legacy policy: abandon prepared mutation when newer evidence invalidates" `
    $LegacyPolicy '(?i)(abandon.*prepared mutation|abandon.*mutation.*evidence.*invalidat|If newer evidence.*invalidated.*abandon)'

Assert-FileContains "K4: legacy policy: previously prepared repair is NOT authority to execute" `
    $LegacyPolicy '(?i)(previously prepared repair is NOT authority|prepared repair.*not.*authority|NOT authority to execute)'

Assert-FileContains "K5: legacy policy: staleness after intervening events defined" `
    $LegacyPolicy '(?i)(Staleness After Intervening Events|staleness.*intervening|intervening events)'

# =============================================================================
# SCENARIO L: Fresh-session re-sync → reproduces reconciled canonical state
# → no stale-cache regression
# =============================================================================
Write-Host ""
Write-Host "--- L: Fresh session re-sync → canonical state, not stale cache ---" -ForegroundColor Cyan

Assert-FileContains "L1: legacy policy: canonical state → reconstruct session/cache, not vice versa" `
    $LegacyPolicy '(?i)(canonical state.*reconstruct.*session|reconstruct.*cache.*from.*canonical|not.*vice versa)'

Assert-FileContains "L2: orchestrator: startup re-sync reads canonical process-state first" `
    $OrchestratorMd '(?i)(planning/lifecycle/process-state\.yaml.*kanonisch|kanonisch.*Git-tracked.*primaere Quelle)'

Assert-FileContains "L3: orchestrator: legacy reconciliation applied during startup re-sync" `
    $OrchestratorMd '(?i)(Legacy-Completion-Reconciliation|legacy.*reconciliation.*historisch|legacy-completion-reconciliation)'

Assert-FileContains "L4: reconciliation.md: lifecycle completion reconciliation section" `
    $ReconciliationMd '(?i)(Lifecycle Completion Reconciliation|lifecycle.*completion.*reconciliation)'

Assert-FileContains "L5: reconciliation.md: canonical state outranks session cache" `
    $ReconciliationMd '(?i)(canonical.*outranks|canonical.*wins|canonical state.*session cache)'

Assert-FileContains "L6: mission-completion: fresh session reconstructs from repository evidence" `
    $MissionPolicy '(?i)(repository evidence.*reconstruct|reconstruct.*repository.*evidence|fresh session.*mission.*lifecycle.*reconstruct)'

# =============================================================================
# GLOSSARY: new classification vocabulary defined
# =============================================================================
Write-Host ""
Write-Host "--- GLOSSARY: legacy classification vocabulary defined ---" -ForegroundColor Cyan

Assert-FileContains "GLO1: CURRENT_REQUIRED_SCOPE in glossary" `
    $GlossaryYaml 'CURRENT_REQUIRED_SCOPE'

Assert-FileContains "GLO2: VERIFIED_LEGACY_STATE in glossary" `
    $GlossaryYaml 'VERIFIED_LEGACY_STATE'

Assert-FileContains "GLO3: DEFERRED_OUTSIDE_FEATURE_SCOPE in glossary" `
    $GlossaryYaml 'DEFERRED_OUTSIDE_FEATURE_SCOPE'

Assert-FileContains "GLO4: SUPERSEDED in glossary" `
    $GlossaryYaml 'SUPERSEDED'

Assert-FileContains "GLO5: GENUINE_DECISION_BLOCKER in glossary" `
    $GlossaryYaml 'GENUINE_DECISION_BLOCKER'

Assert-FileContains "GLO6: UNKNOWN_REQUIRES_RECONCILIATION in glossary" `
    $GlossaryYaml 'UNKNOWN_REQUIRES_RECONCILIATION'

Assert-FileContains "GLO7: completion_reconciliation category in glossary" `
    $GlossaryYaml 'completion_reconciliation'

# =============================================================================
# PURITY: No project-specific knowledge in Core
# =============================================================================
Write-Host ""
Write-Host "--- PURITY: No project-specific knowledge ---" -ForegroundColor Cyan

Assert-FileNotContains "PUR1: legacy policy: no CapTrack reference" `
    $LegacyPolicy 'CapTrack'

Assert-FileNotContains "PUR2: legacy policy: no KidsCompass reference" `
    $LegacyPolicy 'KidsCompass'

Assert-FileNotContains "PUR3: legacy policy: no Mercedes reference" `
    $LegacyPolicy '(?i)mercedes'

Assert-FileNotContains "PUR4: legacy policy: no REQ-NNN from real projects" `
    $LegacyPolicy '(?i)(REQ-084|REQ-014|REQ-017)'

Assert-FileNotContains "PUR5: orchestrator: no CapTrack reference in legacy reconciliation context" `
    $OrchestratorMd 'CapTrack'

# =============================================================================
# CROSS-POLICY CONSISTENCY
# =============================================================================
Write-Host ""
Write-Host "--- CROSS-POLICY: Consistent vocabulary across files ---" -ForegroundColor Cyan

Assert-FileContains "CRS1: checkpoint policy references legacy-completion-reconciliation.md" `
    $CheckpointPolicy '(?i)(legacy-completion-reconciliation|legacy.*reconciliation.*policy)'

Assert-FileContains "CRS2: mission-completion references legacy-completion-reconciliation.md" `
    $MissionPolicy '(?i)(legacy-completion-reconciliation|legacy.*reconciliation.*policy)'

Assert-FileContains "CRS3: reconciliation.md references legacy-completion-reconciliation.md" `
    $ReconciliationMd '(?i)(legacy-completion-reconciliation)'

Assert-FileContains "CRS4: orchestrator references legacy-completion-reconciliation.md" `
    $OrchestratorMd '(?i)(legacy-completion-reconciliation)'

Assert-FileContains "CRS5: legacy policy: agent orientation section names orchestrator" `
    $LegacyPolicy '(?i)(Orchestrator.*orchestrator\.md|Agent Orientation.*orchestrator)'

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
    Write-Error "Legacy Completion Reconciliation test suite FAILED with $FailCount failure(s)."
} else {
    Write-Host "Legacy Completion Reconciliation test suite PASSED." -ForegroundColor Green
}
