<#
.SYNOPSIS
    Architecture Drift Prevention Tests

.DESCRIPTION
    Regression tests for the Architecture Drift Prevention Hardening.
    Validates that the framework contains the contracts required to prevent
    locally correct Requirement implementation converging on a globally poor
    Mendix module/domain architecture.

    Scenarios:
      A. LOCAL GAP repair -> no architecture ceremony required
      B. Single capability refinement inside established module -> existing ownership reused
      C. New feature in established capability/module -> FEATURE Wave + ownership stated
      D. Multiple capabilities/modules -> CROSS_CUTTING escalation required
      E. New module/domain boundary -> ARCHITECTURALLY_SIGNIFICANT + architecture DEC required
      F. Existing large module receives unrelated new capability -> monolith/domain-ownership warning
      G. Company Layer/platform-owned concern -> local custom not silently selected
      H. Architecture assessment -> does NOT generate verification artifacts (TC/VPL/Evidence)
      I. Interrupted/resumed flow -> architecture classification remains reconstructable

    All fixtures use synthetic names only.
    No Example Project, KidsCompass, or Mercedes knowledge in this test file.
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

# File paths
$ImplControl = Join-Path $RepoRoot '.mxagile/policies/implementation-control.md'
$GateReady   = Join-Path $RepoRoot '.mxagile/skills/gate-to-ready.md'
$ImplAgent   = Join-Path $RepoRoot '.mxagile/agents/implementation-agent.md'
$Glossary    = Join-Path $RepoRoot '.mxagile/GLOSSARY.yaml'
$DecSchema   = Join-Path $RepoRoot '.mxagile/schemas/decision.schema.json'
$DecTemplate = Join-Path $RepoRoot '.mxagile/templates/generic/decisions/template.yml'
$DepMatrix   = Join-Path $RepoRoot 'planning/dependency-matrix.md'
$PlanReadme  = Join-Path $RepoRoot 'planning/README.md'
$LifecycleYaml = Join-Path $RepoRoot '.mxagile/lifecycle.yaml'
$DelegationPolicy = Join-Path $RepoRoot '.mxagile/policies/agent-delegation.md'
$TestWorkflow = Join-Path $RepoRoot '.mxagile/policies/test-workflow.md'
$TaskSchema = Join-Path $RepoRoot '.mxagile/schemas/task.schema.json'
$MissionCompletion = Join-Path $RepoRoot '.mxagile/policies/mission-completion.md'
$AcceptanceCampaign = Join-Path $RepoRoot '.mxagile/policies/acceptance-campaign.md'
$RealityReport = Join-Path $RepoRoot 'docs/context-architecture-baseline.md'
$TaskSchemaData = Get-Content -LiteralPath $TaskSchema -Raw | ConvertFrom-Json

Write-Host ""
Write-Host "=== Architecture Drift Prevention Tests ===" -ForegroundColor White
Write-Host "Validates that MxAgile prevents locally correct but globally poor architecture."
Write-Host ""

# =============================================================================
# SCENARIO A: LOCAL GAP repair -> no architecture ceremony required
# =============================================================================
Write-Host "SCENARIO A: LOCAL GAP repair -> no architecture ceremony" -ForegroundColor Cyan

Assert-FileContains "A1: LOCAL significance defined" $ImplControl "LOCAL"
Assert-FileContains "A2: LOCAL does not require new architecture decision" $ImplControl "Kein neuer Architektur-Entscheid erforderlich"
Assert-FileContains "A3: GAP repair stays on bounded path for LOCAL" $ImplControl "GAP[- ]Repair.*verbleibt|GAP repair.*bounded"
Assert-FileContains "A4: gate-to-ready LOCAL does not force architecture assessment" $GateReady "LOCAL.*optional|LOCAL.*weglass|LOCAL.*omit|LOCAL.*duerfen.*weglassen"
Assert-FileContains "A5: Proportionality rule exists for GAP REPAIR" $ImplControl "GAP REPAIR"

# =============================================================================
# SCENARIO B: Single capability refinement in established module -> reuse ownership
# =============================================================================
Write-Host ""
Write-Host "SCENARIO B: Single capability refinement -> established ownership reused" -ForegroundColor Cyan

Assert-FileContains "B1: FEATURE significance defined" $ImplControl "FEATURE"
Assert-FileContains "B2: EXISTING ownership_type defined in checklist" $GateReady "ownership_type.*EXISTING|EXISTING.*ownership"
Assert-FileContains "B3: Established architecture reused for FEATURE" $ImplControl "FEATURE.*keine neue Architektur-Review|keine neue Architektur-Review|Bestehende Architektur.*unveraendert"
Assert-FileContains "B4: No new DEC required for EXISTING boundary" $GateReady "null.*erlaubt.*EXISTING|null.*EXISTING"

# =============================================================================
# SCENARIO C: New feature in established capability -> FEATURE Wave + ownership stated
# =============================================================================
Write-Host ""
Write-Host "SCENARIO C: New feature -> FEATURE Wave with ownership required" -ForegroundColor Cyan

Assert-FileContains "C1: FEATURE requires explicit ownership statement" $ImplControl "Modul-Ownership.*explizit|explizit.*Modul-Ownership|Modul.*Ownership.*explizit"
Assert-FileContains "C2: gate-to-ready requires capability field for FEATURE+" $GateReady "capability.*FEATURE|FEATURE.*capability|FEATURE.*Capability"
Assert-FileContains "C3: execution-waves.md entry format includes capability field" $ImplControl "Capability.*Wave|Wave.*Capability"
Assert-FileContains "C4: Checklist items have capability field for FEATURE+" $GateReady "capability:.*Business.capability|capability.*owning"

# =============================================================================
# SCENARIO D: Multiple capabilities/modules -> CROSS_CUTTING escalation
# =============================================================================
Write-Host ""
Write-Host "SCENARIO D: Multiple capabilities -> CROSS_CUTTING escalation" -ForegroundColor Cyan

Assert-FileContains "D1: CROSS_CUTTING significance defined" $ImplControl "CROSS_CUTTING"
Assert-FileContains "D2: CROSS_CUTTING escalation trigger: multiple capabilities" $ImplControl "Mehrere Capabilities|multiple capabilities"
Assert-FileContains "D3: CROSS_CUTTING requires architecture ownership assessment" $ImplControl "Architektur-Ownership-Assessment vor Readiness|CROSS_CUTTING.*Architektur"
Assert-FileContains "D4: Shared microflow/page triggers cross-cutting" $ImplControl "geteilter.*Microflow|shared.*microflow|shared.*Microflow"
Assert-FileContains "D5: gate-to-ready checks CROSS_CUTTING ownership" $GateReady "CROSS_CUTTING"

# =============================================================================
# SCENARIO E: New module/domain boundary -> ARCHITECTURALLY_SIGNIFICANT + DEC required
# =============================================================================
Write-Host ""
Write-Host "SCENARIO E: New module boundary -> ARCHITECTURALLY_SIGNIFICANT + DEC required" -ForegroundColor Cyan

Assert-FileContains "E1: ARCHITECTURALLY_SIGNIFICANT defined" $ImplControl "ARCHITECTURALLY_SIGNIFICANT"
Assert-FileContains "E2: New Mendix module triggers ARCHITECTURALLY_SIGNIFICANT" $ImplControl "neues Mendix-Modul|new.*Mendix.*module|neues.*Modul.*wird benoetigt"
Assert-FileContains "E3: DEC with decision_type architecture required" $ImplControl "DEC.*architecture|decision_type.*architecture"
Assert-FileContains "E4: gate-to-ready blocks readiness without DEC for ARCHITECTURALLY_SIGNIFICANT" $GateReady "ARCHITECTURALLY_SIGNIFICANT.*DEC|DEC.*ARCHITECTURALLY_SIGNIFICANT"
Assert-FileContains "E5: architecture decision_type exists in schema" $DecSchema '"architecture"'
Assert-FileContains "E6: architecture decision_type documented in template" $DecTemplate "architecture"
Assert-FileContains "E7: NEW ownership_type triggers DEC requirement" $GateReady "ownership_type.*NEW.*Pflicht|ownership_type.*NEW|NEW.*architecture_decision.*Pflicht"
Assert-FileContains "E8: Glossary defines ARCHITECTURALLY_SIGNIFICANT" $Glossary "ARCHITECTURALLY_SIGNIFICANT"

# =============================================================================
# SCENARIO F: Existing large module receives unrelated capability -> monolith warning
# =============================================================================
Write-Host ""
Write-Host "SCENARIO F: Unrelated capability in large module -> monolith warning" -ForegroundColor Cyan

Assert-FileContains "F1: Monolith risk is an escalation trigger" $ImplControl "Monolith|monolith"
Assert-FileContains "F2: Unrelated domain in module triggers escalation" $ImplControl "bestehende.*Verantwortlichkeit.*unterscheidet|Verantwortlichkeit.*unterscheidet"
Assert-FileContains "F3: Domain ownership question 9 exists in gate-to-ready" $GateReady "Monolith-Risiko|monolith risk"
Assert-FileContains "F4: Agent must not use convenient existing module silently" $ImplAgent "General-Purpose-Modul|general.purpose module"
Assert-FileContains "F5: Implementation agent must not silently choose boundary" $ImplAgent "stille.*Architektur|silent.*architecture|keine.*stille"

# =============================================================================
# SCENARIO G: Company Layer / platform-owned concern -> not silently claimed locally
# =============================================================================
Write-Host ""
Write-Host "SCENARIO G: Company Layer concern -> not silently claimed locally" -ForegroundColor Cyan

Assert-FileContains "G1: Company Layer checked in ownership question 10" $GateReady "Company.Layer.*Concern|Company.Layer.*bereits|Company.*Layer.*platform"
Assert-FileContains "G2: Escalation trigger for Company Layer replacement" $ImplControl "Company.Layer.*ersetzt|Company.Layer.*extended|Company-Layer.*Modul"
Assert-FileContains "G3: Architecture question 10 in gate-to-ready" $GateReady "Company.Layer.*10|10.*Company"
Assert-FileContains "G4: Agent checks Company Layer before custom implementation" $ImplAgent "Company Layer.*Funktion|Layer.*bereits|Vor Eigenentwicklung"

# =============================================================================
# SCENARIO H: Architecture assessment does NOT generate verification artifacts
# =============================================================================
Write-Host ""
Write-Host "SCENARIO H: Architecture assessment -> no TC/VPL/Evidence generated" -ForegroundColor Cyan

Assert-FileContains "H1: Glossary explicitly states architecture does not trigger TC" $Glossary "Does not trigger verification|no.*TC|TC.*TC.*nicht|verification.*remain.*late"
Assert-FileContains "H2: Glossary states verification remains late-materialized" $Glossary "late-materialized|spaet.*materialisiert"
Assert-FileContains "H3: gate-to-ready architecture fields do not create TC" $GateReady "architecture_decision.*null|DEC.*null"
Assert-FileNotContains "H4: Architecture assessment section in gate-to-ready does not mention TC creation" $GateReady "Architecture Ownership Assessment.*TC-NNN.*erstellen|Architecture Ownership.*create TC"
Assert-FileContains "H5: VPL produced at Verifying entry, not at architecture assessment" $GateReady "VPL.*Verifying|Verification Plans.*Verifying|VPL.*not required.*Ready"
Assert-FileContains "H6: Lifecycle yaml confirms VPL is at verifying, not ready" $LifecycleYaml "Verification Plans.*Verifying|VPL.*Verifying entry"

# =============================================================================
# SCENARIO I: Interrupted/resumed flow -> architecture classification reconstructable
# =============================================================================
Write-Host ""
Write-Host "SCENARIO I: Interrupted/resumed flow -> classification reconstructable" -ForegroundColor Cyan

Assert-FileContains "I1: Wave significance persisted in execution-waves.md" $ImplControl "Significance.*FEATURE|Significance.*execution-waves"
Assert-FileContains "I2: Architecture decisions in DEC-NNN are durable" $DecTemplate "planning/decisions"
Assert-FileContains "I3: Checklist items carry architecture_decision reference" $GateReady "architecture_decision"
Assert-FileContains "I4: process-state tracks wave phase durably" $LifecycleYaml "process-state"
Assert-FileContains "I5: Agent reads checklist ownership fields before implementation" $ImplAgent "capability.*domain.*module|architecture.*Ownership"

# =============================================================================
# CROSS-CUTTING: framework purity
# =============================================================================
Write-Host ""
Write-Host "CROSS-CUTTING: Framework purity checks" -ForegroundColor Cyan

Assert-FileNotContains "P1: implementation-control does not mention Example Project" $ImplControl "Example Project|KidsCompass"
Assert-FileNotContains "P2: gate-to-ready does not mention Example Project" $GateReady "Example Project|KidsCompass"
Assert-FileNotContains "P3: GLOSSARY does not introduce company-specific knowledge" $Glossary "Example Project|KidsCompass|Mercedes"
Assert-FileContains "P4: dependency-matrix is marked OPTIONAL" $DepMatrix "OPTIONAL"
Assert-FileContains "P5: planning/README reflects dependency-matrix as optional" $PlanReadme "OPTIONAL"
Assert-FileContains "P6: Sprint remains external Board construct" $ImplControl "keine lokalen Sprints|not a local sprint"
Assert-FileContains "P7: Wave remains unit of progression in lifecycle" $LifecycleYaml "unit_of_progression: wave"

# =============================================================================
# SCENARIO J: Tasks stay together unless a Wave boundary adds value
# =============================================================================
Write-Host ""
Write-Host "SCENARIO J: Task/Wave semantics -> minimal useful Waves" -ForegroundColor Cyan

Assert-FileContains "J1: Task is a concrete action using existing task/checklist artifacts" `
    $ImplControl 'Task` already has concrete semantics'
Assert-FileContains "J2: Task has no separate lifecycle, gate, or recovery strategy" `
    $ImplControl 'has no separate lifecycle'
Assert-FileContains "J3: Wave bundles Tasks by outcome and recovery value" `
    $ImplControl 'A `Wave` groups one or more related Tasks'
Assert-FileContains "J4: splitting requires a useful independent result or recovery point" `
    $ImplControl 'Add a Wave only when a meaningful split creates a useful independent outcome'
Assert-FileContains "J5: task count is only a soft signal, never a threshold" `
    $ImplControl 'Task count is only a soft decomposition check, never a threshold'
Assert-FileContains "J5b: task count has no fixed threshold" `
    $ImplControl 'Schwellenwert'
Assert-FileContains "J6: files, tools, skills, tests and subagents alone do not split Waves" `
    $ImplControl 'Do not split just for multiple'
Assert-FileContains "J7: routine decomposition stays with the agent" `
    $ImplControl 'routine choice belongs'
Assert-FileContains "J8: accepted in-scope Requirements must be assigned before Ready" `
    $GateReady "(?s)alle akzeptierten.*Requirements.*zugeordnet"
Assert-FileContains "J9: small cohesive change remains one Task/Wave" `
    $ImplControl 'One Task in one Wave'
Assert-FileContains "J10: substantial cohesive recovery may remain one Wave" `
    $RealityReport "(?s)CapTrack's undo/recovery remains a valid conceptual \*\*single Wave\*\*"
Assert-FileContains "J11: uncertainty can justify a separate Wave when it creates a gate" `
    $ImplControl '(?s)Investigation that must decide whether implementation can proceed.*own useful gate/recovery point'
Assert-FileContains "J11b: independent feature outcomes split only when useful alone" `
    $ImplControl '(?s)Feature with independently completable outcomes.*Split only when completing a Wave is useful on its own'
Assert-FileContains "J11c: parallel outcomes do not split solely for delegation" `
    $ImplControl '(?s)Independent, separately verifiable outcomes.*possible delegation alone is not a split reason'
Assert-FileContains "J12: Mission remains the user objective/completion boundary" `
    $MissionCompletion "Mission.*completion criteria|Mission bezeichnet Nutzerziel|USER_MISSION_COMPLETE"
Assert-FileContains "J13: Campaign remains wave-scoped verification, not a planning level" `
    $AcceptanceCampaign "planning/acceptance-campaigns/<wave>|one test contract.*requirement"
Assert-True "J14: wave_id and workpackage_id remain optional Task links" `
    (($null -ne $TaskSchemaData.properties.wave_id) -and ($null -ne $TaskSchemaData.properties.workpackage_id) -and @($TaskSchemaData.required) -notcontains 'wave_id' -and @($TaskSchemaData.required) -notcontains 'workpackage_id') `
    "Task link fields became required"
Assert-FileContains "J15: planning and state use the existing lifecycle artifacts" `
    $ImplControl "(?s)execution-waves\.md.*process-state\.yaml.*mission-state\.yaml.*reports/campaigns"
Assert-FileContains "J16: Wave completion does not require a Full Suite by itself" `
    $TestWorkflow "(?s)Eine Wave ist eine Grenze.*nicht automatisch fuer einen breiten Framework-Testlauf"
Assert-FileContains "J17: delegation remains separate from Wave decomposition" `
    $DelegationPolicy "Do not equate one Wave with one subagent"

# =============================================================================
# SUMMARY
# =============================================================================
Write-Host ""
Write-Host "=== Architecture Drift Prevention Test Results ===" -ForegroundColor White
Write-Host "  Passed: $PassCount" -ForegroundColor Green
Write-Host "  Failed: $FailCount" -ForegroundColor $(if ($FailCount -gt 0) { 'Red' } else { 'Green' })

if ($FailDetails.Count -gt 0) {
    Write-Host ""
    Write-Host "Failed tests:" -ForegroundColor Red
    foreach ($d in $FailDetails) { Write-Host "  $d" -ForegroundColor Red }
}

Write-Host ""

if ($FailCount -gt 0) {
    Write-Host "RESULT: FAIL ($FailCount test(s) failed)" -ForegroundColor Red
    exit 1
} else {
    Write-Host "RESULT: PASS" -ForegroundColor Green
    exit 0
}
