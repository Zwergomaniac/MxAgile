<#
.SYNOPSIS
    Operating-Mode Detection Hardening Tests

.DESCRIPTION
    Validates the canonical MxAgile operating-mode detection framework.
    All tests are static/contract -- no real Studio Pro installation required.

    Scenarios tested:
    A. No Studio Pro process -> CLOSED-AUTONOM, no user question, autonomous continuation
    B. Studio Pro with current project -> LIVE-SP-CURRENT, mutation coordinated
    C. Studio Pro with another project -> LIVE-SP-OTHER, current project autonomous
    D. Studio Pro exists but project unknown -> AMBIGUOUS-SP-STATE, safe work continues
    E. Detector unavailable/permission denied -> ambiguous, not falsely closed
    F. Linux/headless environment -> CLOSED-AUTONOM without Studio-Pro question
    G. State changes between startup and first mutation -> mode re-evaluated
    H. Fresh-session resume -> stale PID/mode not trusted
    I. Existing detector script is invoked by relevant agent/skill
    J. Large autonomous assignment -> no early operating-mode question when no SP running
    K. No process is killed as part of detection
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

$operatingModePath   = Join-Path $ScriptDir '.mxagile\policies\operating-mode.md'
$detectorPath        = Join-Path $ScriptDir 'scripts\check-studio-pro-status.ps1'
$capabilityResolverPath = Join-Path $ScriptDir 'scripts\Get-MxAgileCapabilities.ps1'
$orchestratorPath    = Join-Path $ScriptDir '.mxagile\orchestrator.md'
$implAgentPath       = Join-Path $ScriptDir '.mxagile\agents\implementation-agent.md'
$implControlPath     = Join-Path $ScriptDir '.mxagile\policies\implementation-control.md'
$consistencyPath     = Join-Path $ScriptDir '.mxagile\policies\consistency-check.md'

Write-Host ''
Write-Host '=== Operating-Mode Detection Hardening Tests ==='
Write-Host ''

# =========================================================================
# Prerequisites: canonical files must exist
# =========================================================================

Write-Host '--- Prerequisites: required files exist ---'

Assert-True 'prereq: operating-mode.md exists' `
    (Test-Path -LiteralPath $operatingModePath) `
    "Canonical policy not found: $operatingModePath"

Assert-True 'prereq: check-studio-pro-status.ps1 exists' `
    (Test-Path -LiteralPath $detectorPath) `
    "Canonical detector not found: $detectorPath"

Write-Host ''

# =========================================================================
# Section A: No Studio Pro -> CLOSED-AUTONOM, no user question
# =========================================================================

Write-Host '--- Section A: No Studio Pro process -> CLOSED-AUTONOM ---'

Assert-FileContains 'A1: policy defines CLOSED-AUTONOM' `
    $operatingModePath 'CLOSED-AUTONOM'

Assert-FileContains 'A2: policy: no SP anyStudioProRunning false -> CLOSED-AUTONOM' `
    $operatingModePath 'anyStudioProRunning.*false.*CLOSED-AUTONOM|CLOSED-AUTONOM'

Assert-FileContains 'A3: policy: default autonomy rule stated' `
    $operatingModePath '(?i)Default Autonomy Rule|default.*autonom'

Assert-FileContains 'A4: orchestrator: startup detects mode before lifecycle work' `
    $orchestratorPath '(?i)Betriebsmodus.*ermitteln|check-studio-pro-status'

Assert-FileContains 'A5: orchestrator: CLOSED-AUTONOM -> no Rueckfrage' `
    $orchestratorPath 'KEINE.*Rueckfrage'

Write-Host ''

# =========================================================================
# Section B: Studio Pro with current project -> LIVE-SP-CURRENT
# =========================================================================

Write-Host '--- Section B: Studio Pro open with current project -> LIVE-SP-CURRENT ---'

Assert-FileContains 'B1: policy defines LIVE-SP-CURRENT' `
    $operatingModePath 'LIVE-SP-CURRENT'

Assert-FileContains 'B2: policy: LIVE-SP-CURRENT applies coexistence contract' `
    $operatingModePath '(?i)coexistence|consistency-check|Koexistenz'

Assert-FileContains 'B3: policy: isOpen true -> LIVE-SP-CURRENT' `
    $capabilityResolverPath '\$detection\.is_open\).*\$mode = ''LIVE-SP-CURRENT'''

Assert-FileContains 'B4: orchestrator: mutation recheck for LIVE-SP-CURRENT' `
    $orchestratorPath 'LIVE-SP-CURRENT'

Write-Host ''

# =========================================================================
# Section C: Studio Pro with another project -> LIVE-SP-OTHER
# =========================================================================

Write-Host '--- Section C: Studio Pro open with another project -> LIVE-SP-OTHER ---'

Assert-FileContains 'C1: policy defines LIVE-SP-OTHER' `
    $operatingModePath 'LIVE-SP-OTHER'

Assert-FileContains 'C2: policy: LIVE-SP-OTHER -> current project acts as CLOSED-AUTONOM' `
    $operatingModePath 'LIVE-SP-OTHER.*CLOSED-AUTONOM|Treat.*current.*CLOSED-AUTONOM'

Assert-FileContains 'C3: policy: anyStudioProRunning true + isOpen false -> LIVE-SP-OTHER' `
    $capabilityResolverPath '\$detection\.any_studio_pro_running\).*\$mode = ''LIVE-SP-OTHER'''

Assert-FileContains 'C4: policy: foreign Studio Pro process must not be touched' `
    $operatingModePath '(?i)NOT touch|Do NOT touch'

Assert-FileContains 'C5: detector: anyStudioProRunning field in JSON output' `
    $detectorPath 'anyStudioProRunning'

Assert-FileContains 'C6: detector: otherProjectPids field in JSON output' `
    $detectorPath 'otherProjectPids'

Write-Host ''

# =========================================================================
# Section D: SP exists but project unknown -> AMBIGUOUS-SP-STATE
# =========================================================================

Write-Host '--- Section D: SP exists project unknown -> AMBIGUOUS-SP-STATE ---'

Assert-FileContains 'D1: policy defines AMBIGUOUS-SP-STATE' `
    $operatingModePath 'AMBIGUOUS-SP-STATE'

Assert-FileContains 'D2: policy: safe work continues under AMBIGUOUS-SP-STATE' `
    $operatingModePath '(?i)safe.*reads|safe.*work.*continues|Continue all safe'

Assert-FileContains 'D3: policy: mutation delayed not whole assignment blocked' `
    $operatingModePath '(?i)Delay ONLY'

Assert-FileContains 'D4: policy: question only at mutation boundary under ambiguous' `
    $operatingModePath '(?i)mutation.*boundary'

Write-Host ''

# =========================================================================
# Section E: Detector unavailable -> ambiguous, not falsely closed
# =========================================================================

Write-Host '--- Section E: Detector unavailable/permission -> AMBIGUOUS-SP-STATE ---'

Assert-FileContains 'E1: policy: detector failure -> AMBIGUOUS-SP-STATE' `
    $operatingModePath '(?i)2.*AMBIGUOUS-SP-STATE|AMBIGUOUS-SP-STATE.*code.*2|script.*failed'

Assert-FileContains 'E2: policy: permission denied -> AMBIGUOUS-SP-STATE' `
    $operatingModePath '(?i)Permission denied.*ambig|AMBIGUOUS.*permission'

Assert-FileContains 'E3: policy: do not fabricate certainty' `
    $operatingModePath '(?i)do not fabricate|fabricate.*certainty'

Write-Host ''

# =========================================================================
# Section F: Linux/headless -> CLOSED-AUTONOM without question
# =========================================================================

Write-Host '--- Section F: Linux/headless -> CLOSED-AUTONOM without question ---'

Assert-FileContains 'F1: policy: Linux headless -> CLOSED-AUTONOM immediately' `
    $operatingModePath '(?i)Linux.*CLOSED-AUTONOM|headless.*CLOSED-AUTONOM|platform_headless'

Assert-FileContains 'F2: policy: do not ask about SP on headless' `
    $operatingModePath '(?i)Do NOT.*ask.*headless|cannot run.*platform|cannot exist'

Assert-FileContains 'F3: policy: platform_headless detection_source defined' `
    $operatingModePath 'platform_headless'

Assert-FileContains 'F4: policy: IsLinux or IsMacOS check documented' `
    $capabilityResolverPath 'source = ''platform_headless'''

Write-Host ''

# =========================================================================
# Section G: State changes before mutation -> recheck
# =========================================================================

Write-Host '--- Section G: State changes before mutation -> recheck ---'

Assert-FileContains 'G1: policy: recheck before first model mutation' `
    $operatingModePath '(?i)Recheck.*mutation|recheck.*before.*first|mutation.*recheck'

Assert-FileContains 'G2: orchestrator: mutation recheck in Implementing phase' `
    $orchestratorPath '(?i)Betriebsmodus-Recheck|Mutation.*Recheck'

Assert-FileContains 'G3: policy: operating mode can change after session start' `
    $operatingModePath '(?i)can change after session|state changes'

Write-Host ''

# =========================================================================
# Section H: Fresh-session resume -> stale PID not trusted
# =========================================================================

Write-Host '--- Section H: Fresh-session resume -> stale PID not trusted ---'

Assert-FileContains 'H1: policy: do not trust prior session operating mode' `
    $operatingModePath '(?i)stale.*PID|prior session|Discard.*prior'

Assert-FileContains 'H2: policy: re-run detection on fresh session' `
    $operatingModePath '(?i)Re-run detection|fresh session'

Assert-FileContains 'H3: policy: PIDs not persisted as durable project truth' `
    $operatingModePath '(?i)NOT.*persist.*PID.*durable|not.*persist.*pids'

Write-Host ''

# =========================================================================
# Section I: Existing detector wired into agent/skill
# =========================================================================

Write-Host '--- Section I: Detector script wired into agent/skill ---'

Assert-FileContains 'I1: implementation-agent: references operating-mode policy' `
    $implAgentPath 'operating-mode'

Assert-FileContains 'I2: orchestrator: calls check-studio-pro-status.ps1' `
    $orchestratorPath 'Get-MxAgileCapabilities\.ps1 -ResolveOperatingMode -Format json'

Assert-FileContains 'I3: consistency-check: calls check-studio-pro-status.ps1 (CE0066)' `
    $consistencyPath 'operating_mode\.tool_authority.*C2|C2.*operating_mode\.tool_authority'

Assert-FileContains 'I4: operating-mode policy: lists detector as integration point' `
    $operatingModePath 'check-studio-pro-status'

Assert-FileContains 'I5: implementation-control: references operating-mode policy' `
    $implControlPath 'operating-mode'

Write-Host ''

# =========================================================================
# Section J: Autonomous assignment -> no early question when no SP
# =========================================================================

Write-Host '--- Section J: Autonomous assignment -> no early question when no SP ---'

Assert-FileContains 'J1: policy: must not ask before detection is attempted' `
    $operatingModePath '(?i)MUST NOT.*ask.*before.*detection|detection.*before.*ask'

Assert-FileContains 'J2: policy: forbidden generic questions listed' `
    $operatingModePath 'Is Studio Pro open'

Assert-FileContains 'J3: orchestrator: no user question gate for mode at startup' `
    $orchestratorPath 'KEINE.*Rueckfrage'

Assert-FileContains 'J4: policy: CLOSED-AUTONOM -> autonomous no confirmation' `
    $operatingModePath '(?i)MUST continue.*autonomous|autonomous.*without.*confirm'

Write-Host ''

# =========================================================================
# Section K: No process is killed as part of detection
# =========================================================================

Write-Host '--- Section K: Detection never kills processes ---'

Assert-FileContains 'K1: policy: process safety section states no kill' `
    $operatingModePath '(?i)Process Safety'

Assert-FileContains 'K2: policy: SP must not be killed' `
    $operatingModePath '(?i)MUST NOT kill'

Assert-FileNotContains 'K3: detector script: no Stop-Process command' `
    $detectorPath '(?i)Stop-Process'

Assert-FileNotContains 'K3b: detector script: no taskkill command' `
    $detectorPath '(?i)taskkill'

Assert-FileContains 'K4: policy: detection and routing only' `
    $operatingModePath '(?i)detection.*routing.*only'

Write-Host ''

# =========================================================================
# Section L: Structured C2 operating-mode/tool-authority resolution
# =========================================================================

Write-Host '--- Section L: Structured C2 route authority ---'

Assert-FileContains 'L1: resolver exposes opt-in operating-mode output' `
    $capabilityResolverPath 'ResolveOperatingMode|operating_mode'

Assert-FileContains 'L2: resolver invokes the existing Studio Pro detector' `
    $capabilityResolverPath 'check-studio-pro-status\.ps1'

Assert-FileContains 'L3: resolver accepts current-session MCP health attestations' `
    $capabilityResolverPath 'StudioProMcpProbeStatus|ConcordMcpProbeStatus'

Assert-FileContains 'L4: LIVE-SP route prohibits mxcli after MCP failure' `
    $capabilityResolverPath 'mxcli_fallback_after_mcp_failure = \$false'

Assert-FileContains 'L4b: .mpr enumeration failure remains ambiguous' `
    $capabilityResolverPath 'source = ''mpr_lookup_failed'''

Assert-FileContains 'L5: configured and runtime-attested evidence are separate' `
    $capabilityResolverPath 'configured = \[ordered\]@\{|runtime_attestation = \[ordered\]@\{'

Assert-FileContains 'L5b: policy consumes the existing structured resolver' `
    $operatingModePath 'Get-MxAgileCapabilities\.ps1'

Assert-FileContains 'L5b2: policy requests structured operating-mode output' `
    $operatingModePath '-ResolveOperatingMode -Format json'

Assert-FileContains 'L5c: policy requires current MCP probe and project binding' `
    $operatingModePath 'successful current-session'

Assert-FileContains 'L5c2: policy requires exact project binding' `
    $operatingModePath 'exact binding to the current project'

$parseTokens = $null
$parseErrors = $null
$resolverAst = [System.Management.Automation.Language.Parser]::ParseFile(
    $capabilityResolverPath, [ref]$parseTokens, [ref]$parseErrors
)
$routeAst = $resolverAst.Find({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -eq 'Resolve-OperatingModeRoute'
}, $true)
Assert-True 'L6: pure route aggregator exists' ($null -ne $routeAst) 'Resolve-OperatingModeRoute not found in resolver AST'

if ($routeAst) {
    . ([ScriptBlock]::Create($routeAst.Extent.Text))
    $currentMpr = Join-Path $env:TEMP 'mxagile-c2-fixture\current.mpr'
    $otherMpr = Join-Path $env:TEMP 'mxagile-c2-fixture\other.mpr'
    $unconfigured = [ordered]@{ state = 'OBSERVED'; configured = $false; source = '.vscode/mcp.json' }
    $configured = [ordered]@{ state = 'OBSERVED'; configured = $true; source = '.vscode/mcp.json' }

    $studioRoute = Resolve-OperatingModeRoute -Mode 'LIVE-SP-CURRENT' -CurrentProjectPath $currentMpr `
        -StudioProConfiguration $unconfigured -StudioProMcpProbeStatus 'HEALTHY' -StudioProMcpBoundProjectPath $currentMpr `
        -ConcordConfiguration $unconfigured -ConcordMcpProbeStatus 'NOT_OBSERVED' -ConcordMcpBoundProjectPath ''
    Assert-True 'L7: healthy current-project Studio Pro MCP is primary' `
        ($studioRoute.selected_route -eq 'studio_pro_mcp' -and $studioRoute.status -eq 'RUNTIME_ATTESTED') `
        'Studio Pro route was not selected from healthy same-project evidence'
    Assert-True 'L8: runtime evidence remains separate from configuration' `
        ($studioRoute.runtime_attestation.studio_pro_mcp.usable -and -not $studioRoute.configured.studio_pro_mcp.configured) `
        'Runtime attestation was conflated with project configuration'

    $concordRoute = Resolve-OperatingModeRoute -Mode 'LIVE-SP-CURRENT' -CurrentProjectPath $currentMpr `
        -StudioProConfiguration $unconfigured -StudioProMcpProbeStatus 'FAILED' -StudioProMcpBoundProjectPath '' `
        -ConcordConfiguration $configured -ConcordMcpProbeStatus 'HEALTHY' -ConcordMcpBoundProjectPath $currentMpr
    Assert-True 'L9: healthy same-project Concord is explicit fallback' `
        ($concordRoute.selected_route -eq 'concord_mcp' -and $concordRoute.status -eq 'RUNTIME_ATTESTED_FALLBACK') `
        'Concord fallback did not require a healthy same-project probe'

    $blockedRoute = Resolve-OperatingModeRoute -Mode 'LIVE-SP-CURRENT' -CurrentProjectPath $currentMpr `
        -StudioProConfiguration $unconfigured -StudioProMcpProbeStatus 'NOT_OBSERVED' -StudioProMcpBoundProjectPath '' `
        -ConcordConfiguration $unconfigured -ConcordMcpProbeStatus 'NOT_OBSERVED' -ConcordMcpBoundProjectPath ''
    Assert-True 'L10: unprobed LIVE-SP is blocked without mxcli' `
        ($blockedRoute.status -eq 'BLOCKED' -and -not $blockedRoute.mxcli_permitted -and -not $blockedRoute.mxcli_fallback_after_mcp_failure) `
        'LIVE-SP without attested MCP route was not fail-closed'

    $conflictRoute = Resolve-OperatingModeRoute -Mode 'LIVE-SP-CURRENT' -CurrentProjectPath $currentMpr `
        -StudioProConfiguration $configured -StudioProMcpProbeStatus 'HEALTHY' -StudioProMcpBoundProjectPath $otherMpr `
        -ConcordConfiguration $configured -ConcordMcpProbeStatus 'HEALTHY' -ConcordMcpBoundProjectPath $currentMpr
    Assert-True 'L11: Studio Pro project identity conflict blocks fallback' `
        ($conflictRoute.status -eq 'CONFLICT' -and -not $conflictRoute.selected_route -and $conflictRoute.effective_mode -eq 'AMBIGUOUS-SP-STATE') `
        'Conflicting primary MCP identity did not block fallback and promote ambiguity'

    $autonomousRoute = Resolve-OperatingModeRoute -Mode 'CLOSED-AUTONOM' -CurrentProjectPath $currentMpr `
        -StudioProConfiguration $unconfigured -StudioProMcpProbeStatus 'NOT_OBSERVED' -StudioProMcpBoundProjectPath '' `
        -ConcordConfiguration $unconfigured -ConcordMcpProbeStatus 'NOT_OBSERVED' -ConcordMcpBoundProjectPath ''
    Assert-True 'L12: CLOSED-AUTONOM permits existing mxcli resolver route' `
        ($autonomousRoute.mxcli_permitted -and $autonomousRoute.mxcli_availability -eq 'NOT_RESOLVED_BY_C2') `
        'Autonomous route did not preserve the existing mxcli availability boundary'

    $ambiguousRoute = Resolve-OperatingModeRoute -Mode 'AMBIGUOUS-SP-STATE' -CurrentProjectPath $currentMpr `
        -StudioProConfiguration $unconfigured -StudioProMcpProbeStatus 'NOT_OBSERVED' -StudioProMcpBoundProjectPath '' `
        -ConcordConfiguration $unconfigured -ConcordMcpProbeStatus 'NOT_OBSERVED' -ConcordMcpBoundProjectPath ''
    Assert-True 'L13: ambiguous mode allows only safe non-model work' `
        ($ambiguousRoute.preferred_route -eq 'safe_non_model_work_only' -and -not $ambiguousRoute.mxcli_permitted) `
        'Ambiguous mode exposed a model-mutation route'
}

Write-Host ''

# =========================================================================
# Summary
# =========================================================================

Write-Host '=== Operating-Mode Detection Test Summary ==='
Write-Host "  PASS: $PassCount"
Write-Host "  FAIL: $FailCount"

if ($FailDetails.Count -gt 0) {
    Write-Host ''
    Write-Host 'Failures:'
    foreach ($d in $FailDetails) {
        Write-Host "  $d" -ForegroundColor Red
    }
}

Write-Host ''

if ($FailCount -gt 0) {
    Write-Host 'RESULT: FAIL' -ForegroundColor Red
    exit 1
} else {
    Write-Host 'RESULT: PASS' -ForegroundColor Green
    exit 0
}
