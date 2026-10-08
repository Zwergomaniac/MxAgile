<#
.SYNOPSIS
    Runtime Startup Recovery Tests

.DESCRIPTION
    Validates that MxAgile canonical guidance correctly implements the evidence-first
    startup diagnosis and bounded deterministic recovery model.

    Corresponds to the REAL FINDING where a startup timeout was incorrectly classified
    as a machine-load/infrastructure-failure, leading to premature human escalation,
    when the actual root cause was an orphan mxbuild process retaining file locks on
    the deployment/web path.

    Test scenarios:
    A. Startup timeout alone → no machine-load diagnosis allowed
    B. Startup timeout with no root-cause evidence → UNKNOWN / diagnosis required
    C. Orphan attributable local build process detected → bounded cleanup/recovery allowed
    D. Stale process/resource conflict recovered → retry startup → continue verification
    E. First startup attempt fails → mission not blocked while deterministic recovery exists
    F. APPLICATION_REACHABLE after recovery → resume pending runtime/browser verification
    G. Application startup failure caused by actual application defect → APPLICATION_DEFECT
    H. Test harness/startup tooling failure → TEST_DEFECT or TEST_INFRASTRUCTURE_GAP
    I. Infrastructure blocker after exhausted safe recovery → legitimate external/human gate
    J. Unrelated verification work remains possible → continue it
    K. Cleanup scope cannot be safely attributed to current project → no blind kill
    L. Credential failure → follow credential-discovery contract; no speculative mutation
    M. Project-specific lesson → remains outside Core
    N. Fresh projected agent → can discover runtime-recovery contract
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

function Assert-FileNotContains {
    param([string]$TestName, [string]$FilePath, [string]$Pattern)
    $content = Get-Content -LiteralPath $FilePath -Raw -ErrorAction SilentlyContinue
    if ($null -eq $content) {
        Assert-True $TestName $false "File not found: $FilePath"
    } else {
        Assert-True $TestName ($content -notmatch $Pattern) "Forbidden pattern '$Pattern' found in $FilePath"
    }
}

# Canonical source paths
$recoveryPolicyPath  = Join-Path $ScriptDir ".mxagile/policies/runtime-startup-recovery.md"
$devRuntimePath      = Join-Path $ScriptDir ".mxagile/policies/development-runtime.md"
$localProfilePath    = Join-Path $ScriptDir ".mxagile/policies/local-runtime-profile.md"
$testDefectPath      = Join-Path $ScriptDir ".mxagile/policies/test-defect-protection.md"
$credDiscoveryPath   = Join-Path $ScriptDir ".mxagile/policies/credential-discovery.md"
$missionPath         = Join-Path $ScriptDir ".mxagile/policies/mission-completion.md"
$implAgentPath       = Join-Path $ScriptDir ".mxagile/agents/implementation-agent.md"
$acceptanceAgentPath = Join-Path $ScriptDir ".mxagile/agents/acceptance-agent.md"
$uiAgentPath         = Join-Path $ScriptDir ".mxagile/agents/ui-agent.md"

# Generated projection paths
$genImplAgentPath       = Join-Path $ScriptDir ".claude/agents/mxagile-implementation-agent.md"
$genAcceptanceAgentPath = Join-Path $ScriptDir ".claude/agents/mxagile-acceptance-agent.md"
$genUiAgentPath         = Join-Path $ScriptDir ".claude/agents/mxagile-ui-agent.md"

Write-Host ""
Write-Host "=== Runtime Startup Recovery Tests ==="
Write-Host ""

# =========================================================================
# Policy exists
# =========================================================================

Write-Host "--- Policy existence ---"

Assert-True "runtime-startup-recovery.md exists" `
    (Test-Path -LiteralPath $recoveryPolicyPath) `
    "Canonical policy not found: $recoveryPolicyPath"

# =========================================================================
# A. Startup timeout alone → no machine-load diagnosis allowed
# =========================================================================

Write-Host "--- A: Startup timeout alone → no machine-load diagnosis allowed ---"

Assert-FileContains "recovery policy: timeout is observation not diagnosis" `
    $recoveryPolicyPath '(?i)timeout.*observation|observation.*not.*diagnosis|startup.*timeout.*must not.*establish'

Assert-FileContains "recovery policy: machine load prohibited without evidence" `
    $recoveryPolicyPath '(?i)machine load|MACHINE_LOAD_FAILURE'

Assert-FileNotContains "recovery policy: no blanket machine-load classification" `
    $recoveryPolicyPath '(?i)timeout.*machine load.*diagnosis|classify.*timeout.*machine.load'

Assert-FileContains "development-runtime: startup failure → gather evidence rule" `
    $devRuntimePath '(?i)evidence.*before.*classif|gather.*diagnos|observation.*not.*diagnosis'

Write-Host ""

# =========================================================================
# B. Startup timeout with no root-cause evidence → UNKNOWN / diagnosis required
# =========================================================================

Write-Host "--- B: Timeout with no evidence → diagnosis required, not infrastructure failure ---"

Assert-FileContains "recovery policy: evidence inventory defined" `
    $recoveryPolicyPath '(?i)evidence inventory|evidence.*to collect|signals.*before'

Assert-FileContains "recovery policy: prohibited classifications without evidence listed" `
    $recoveryPolicyPath '(?i)prohibited.*classification|machine_load_failure|infrastructure_failure|environment_performance'

Assert-FileNotContains "recovery policy: no automatic infrastructure failure from timeout" `
    $recoveryPolicyPath '(?i)timeout.*automatically.*infrastructure.failure|timeout.*means.*infrastructure'

Write-Host ""

# =========================================================================
# C. Orphan attributable local build process → bounded cleanup/recovery allowed
# =========================================================================

Write-Host "--- C: Orphan build process detected → bounded cleanup allowed ---"

Assert-FileContains "recovery policy: orphan mxbuild process class covered" `
    $recoveryPolicyPath '(?i)mxbuild.*orphan|orphan.*mxbuild|stale.*build.*process|stale_owned_build'

Assert-FileContains "recovery policy: deployment/web file lock scenario covered" `
    $recoveryPolicyPath '(?i)deployment.web|build.*file.*lock|file.*lock.*deployment'

Assert-FileContains "recovery policy: STALE_OWNED_BUILD termination allowed with evidence" `
    $recoveryPolicyPath '(?i)STALE_OWNED_BUILD.*terminat|terminat.*STALE_OWNED_BUILD'

Assert-FileContains "recovery policy: two-signal ownership evidence required" `
    $recoveryPolicyPath '(?i)two.signal|two.*evidence|minimum.*two|two.*ownership'

Assert-FileContains "development-runtime: stale mxbuild detection before startup" `
    $devRuntimePath '(?i)mxbuild.*process.*matching|stale.*mxbuild|mxbuild.*processes'

Write-Host ""

# =========================================================================
# D. Stale process recovered → retry startup → continue verification
# =========================================================================

Write-Host "--- D: Stale process recovered → retry → continue verification ---"

Assert-FileContains "recovery policy: safe build recovery ladder defined" `
    $recoveryPolicyPath '(?i)safe build recovery|recovery ladder|STALE_OWNED_BUILD.*retry'

Assert-FileContains "recovery policy: STALE_PROCESS_RECOVERED classification defined" `
    $recoveryPolicyPath '(?i)STALE_PROCESS_RECOVERED'

Assert-FileContains "recovery policy: retry after recovery is materially different path" `
    $recoveryPolicyPath '(?i)materially different.*recovery|different.*recovery.*path|not.*blind.*retry'

Write-Host ""

# =========================================================================
# E. First startup fails → mission not blocked while deterministic recovery exists
# =========================================================================

Write-Host "--- E: First failure → mission not blocked while recovery exists ---"

Assert-FileContains "recovery policy: deterministic recovery before human gate" `
    $recoveryPolicyPath '(?i)deterministic recovery.*before.*human|recovery.*before.*external|bounded.*before.*gate'

Assert-FileContains "recovery policy: human gate only after exhausted recovery" `
    $recoveryPolicyPath '(?i)recovery.*exhausted|exhausted.*recovery|STARTUP_RECOVERY_EXHAUSTED'

Assert-FileContains "recovery policy: evidence-first model flow defined" `
    $recoveryPolicyPath '(?i)STARTUP.*TIMEOUT.*PROBE.*FAILURE|startup.*failure.*response|gather.*diagnostic'

Write-Host ""

# =========================================================================
# F. APPLICATION_REACHABLE after recovery → resume pending verification
# =========================================================================

Write-Host "--- F: APPLICATION_REACHABLE after recovery → resume pending verification ---"

Assert-FileContains "recovery policy: APPLICATION_REACHABLE resumes verification" `
    $recoveryPolicyPath '(?i)APPLICATION_REACHABLE.*resumes|APPLICATION_REACHABLE.*resume.*verification|resume.*pending.*verification'

Assert-FileContains "recovery policy: successful recovery does not create new mission" `
    $recoveryPolicyPath '(?i)successful recovery.*does not.*new mission|not.*new mission|does not.*start.*new mission'

Assert-FileContains "acceptance-agent: startup failure after recovery → TEST_INFRASTRUCTURE_GAP" `
    $acceptanceAgentPath '(?i)TEST_INFRASTRUCTURE_GAP.*not APPLICATION_DEFECT|exhausted.*recovery.*TEST_INFRA'

Write-Host ""

# =========================================================================
# G. Application startup failure caused by actual defect → APPLICATION_DEFECT
# =========================================================================

Write-Host "--- G: Actual application defect → APPLICATION_DEFECT ---"

Assert-FileContains "recovery policy: APPLICATION_DEFECT classification defined" `
    $recoveryPolicyPath '(?i)APPLICATION_DEFECT.*application reachable.*authenticated|application reachable.*unexpected result.*APPLICATION_DEFECT'

Assert-FileContains "recovery policy: do not mutate app behavior to force startup" `
    $recoveryPolicyPath '(?i)do not mutate.*application|not.*mutate.*behavior|not.*mutate.*app'

Assert-FileContains "test-defect-protection: APPLICATION_DEFECT defined" `
    $testDefectPath 'APPLICATION_DEFECT'

Write-Host ""

# =========================================================================
# H. Test harness/tooling failure → TEST_DEFECT or TEST_INFRASTRUCTURE_GAP
# =========================================================================

Write-Host "--- H: Test harness failure → TEST_DEFECT or TEST_INFRASTRUCTURE_GAP ---"

Assert-FileContains "recovery policy: TEST_INFRASTRUCTURE_GAP classification defined" `
    $recoveryPolicyPath '(?i)TEST_INFRASTRUCTURE_GAP.*test.*tooling|test.*harness.*TEST_INFRA'

Assert-FileContains "test-defect-protection: TEST_INFRASTRUCTURE_GAP defined" `
    $testDefectPath 'TEST_INFRASTRUCTURE_GAP'

Assert-FileContains "test-defect-protection: TEST_DEFECT defined" `
    $testDefectPath 'TEST_DEFECT'

Write-Host ""

# =========================================================================
# I. Infrastructure blocker after exhausted recovery → legitimate human gate
# =========================================================================

Write-Host "--- I: Exhausted recovery → legitimate human/external gate ---"

Assert-FileContains "recovery policy: legitimate human gate conditions defined" `
    $recoveryPolicyPath '(?i)legitimate.*human.*gate|legitimate.*external.*gate|are legitimate'

Assert-FileContains "recovery policy: STARTUP_RECOVERY_EXHAUSTED classification defined" `
    $recoveryPolicyPath 'STARTUP_RECOVERY_EXHAUSTED'

Assert-FileContains "recovery policy: foreign/unknown process escalates to human" `
    $recoveryPolicyPath '(?i)FOREIGN_BUILD.*escalat|UNKNOWN_BUILD.*escalat|foreign.*escalat'

Write-Host ""

# =========================================================================
# J. Unrelated verification work continues when startup blocked
# =========================================================================

Write-Host "--- J: Unrelated verification work continues ---"

Assert-FileContains "recovery policy: partial blockers do not terminate whole mission" `
    $recoveryPolicyPath '(?i)partial.*blocker.*not.*terminate|not.*block.*all.*remaining|unrelated.*verification'

Assert-FileContains "recovery policy: MODEL/BUILD proof continues when runtime blocked" `
    $recoveryPolicyPath '(?i)model.*build.*continue|non.runtime.*proof.*point|continue.*non-runtime'

Assert-FileContains "mission-completion: partial blockers blast radius defined" `
    $missionPath '(?i)blast radius|partial.*blocker|continue.*not blocked'

Write-Host ""

# =========================================================================
# K. Cleanup scope cannot be attributed to current project → no blind kill
# =========================================================================

Write-Host "--- K: Cleanup attribution required — no blind kill ---"

Assert-FileContains "recovery policy: FOREIGN_BUILD must not be terminated" `
    $recoveryPolicyPath '(?i)FOREIGN_BUILD.*do not.*terminat|UNKNOWN_BUILD.*do not.*terminat'

Assert-FileContains "recovery policy: blind kill prohibited" `
    $recoveryPolicyPath '(?i)pkill mxbuild|killall.*prohibited|blind.*kill.*not|not.*arbitrary.*terminat'

Assert-FileContains "recovery policy: bounded to current project/tooling" `
    $recoveryPolicyPath '(?i)bounded.*current.*project|attributable.*current.*project|project.*tooling.*session'

Assert-FileContains "development-runtime: broad kill-all behavior forbidden" `
    $devRuntimePath '(?i)blindly.*kill|blind.*kill|pkill|killall.*not permitted'

Write-Host ""

# =========================================================================
# L. Credential failure → credential-discovery contract; no speculative mutation
# =========================================================================

Write-Host "--- L: Credential failure → discovery contract; no mutation ---"

Assert-FileContains "recovery policy: credential failure follows credential-discovery" `
    $recoveryPolicyPath '(?i)credential.*discovery|credential-discovery.*contract'

Assert-FileContains "recovery policy: no speculative credential mutation" `
    $recoveryPolicyPath '(?i)no.*speculative.*credential|not.*mutate.*credential'

Assert-FileContains "development-runtime: credential mutation never permitted on auth failure" `
    $devRuntimePath '(?i)credential.*mutation|ALTER USER|speculative.*credential'

Write-Host ""

# =========================================================================
# M. Project-specific lesson → remains outside Core
# =========================================================================

Write-Host "--- M: Project-specific lessons remain outside Core ---"

Assert-FileContains "recovery policy: PROJECT_SPECIFIC lesson class defined" `
    $recoveryPolicyPath '(?i)PROJECT_SPECIFIC.*lesson|lesson.*PROJECT_SPECIFIC|project.specific.*knowledge'

Assert-FileContains "recovery policy: project-specific knowledge must not enter Core" `
    $recoveryPolicyPath '(?i)project.specific.*never.*core|project.specific.*outside.*core|never.*core.*project.specific'

Assert-FileContains "recovery policy: GENERIC_MXAGILE_CANDIDATE requires generalization" `
    $recoveryPolicyPath '(?i)GENERIC_MXAGILE_CANDIDATE'

Assert-FileContains "recovery policy: MXCLI_TOOLING_BEHAVIOR defined" `
    $recoveryPolicyPath '(?i)MXCLI_TOOLING_BEHAVIOR'

Write-Host ""

# =========================================================================
# N. Fresh projected agent → can discover runtime-recovery contract
# =========================================================================

Write-Host "--- N: Fresh projected agent discovers runtime-recovery contract ---"

# Canonical agent sources must reference the policy
Assert-FileContains "implementation-agent: references runtime-startup-recovery" `
    $implAgentPath 'runtime-startup-recovery'

Assert-FileContains "acceptance-agent: references runtime-startup-recovery" `
    $acceptanceAgentPath 'runtime-startup-recovery'

Assert-FileContains "ui-agent: references runtime-startup-recovery" `
    $uiAgentPath 'runtime-startup-recovery'

# Generated projections must also carry the reference
Assert-True "generated implementation-agent exists" `
    (Test-Path -LiteralPath $genImplAgentPath) `
    "Generated agent not found: $genImplAgentPath"

Assert-FileContains "generated implementation-agent: references runtime-startup-recovery" `
    $genImplAgentPath 'runtime-startup-recovery'

Assert-True "generated acceptance-agent exists" `
    (Test-Path -LiteralPath $genAcceptanceAgentPath) `
    "Generated agent not found: $genAcceptanceAgentPath"

Assert-FileContains "generated acceptance-agent: references runtime-startup-recovery" `
    $genAcceptanceAgentPath 'runtime-startup-recovery'

Assert-True "generated ui-agent exists" `
    (Test-Path -LiteralPath $genUiAgentPath) `
    "Generated agent not found: $genUiAgentPath"

Assert-FileContains "generated ui-agent: references runtime-startup-recovery" `
    $genUiAgentPath 'runtime-startup-recovery'

Write-Host ""

# =========================================================================
# Final summary
# =========================================================================

Write-Host "=== Runtime Startup Recovery Test Results ==="
Write-Host "  PASS: $PassCount" -ForegroundColor Green
if ($FailCount -gt 0) {
    Write-Host "  FAIL: $FailCount" -ForegroundColor Red
    foreach ($detail in $FailDetails) {
        Write-Host "    $detail" -ForegroundColor Red
    }
    Write-Host ""
    Write-Host "TEST FAILED: Runtime startup recovery guidance is missing or inconsistent." -ForegroundColor Red
    exit 1
} else {
    Write-Host ""
    Write-Host "TEST PASSED: Runtime startup recovery guidance (evidence-first, bounded recovery) is complete and consistent." -ForegroundColor Green
    exit 0
}
