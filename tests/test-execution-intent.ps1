<#
.SYNOPSIS
    LIVE-SP operating-mode and tool-routing regression tests.

.DESCRIPTION
    Static contract tests for the existing detector, MCP evidence rules and
    implementation routing. Runtime MCP health cannot be simulated by this suite.
    Covers the Concord/LIVE-SP reality case and boundaries R1-R8.
#>

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
$modePolicy = Join-Path $repoRoot '.mxagile\policies\operating-mode.md'
$routePolicy = Join-Path $repoRoot '.mxagile\policies\execution-intent.md'
$orchestrator = Join-Path $repoRoot '.mxagile\orchestrator.md'
$implementationAgent = Join-Path $repoRoot '.mxagile\agents\implementation-agent.md'
$capabilities = Join-Path $repoRoot '.mxagile\capabilities.yaml'
$detector = Join-Path $repoRoot 'scripts\check-studio-pro-status.ps1'

$passCount = 0
$failCount = 0
$failDetails = @()

function Assert-True {
    param([string]$Name, [bool]$Condition, [string]$Message)
    if ($Condition) {
        Write-Host "  PASS: $Name" -ForegroundColor Green
        $script:passCount++
    } else {
        Write-Host "  FAIL: $Name -- $Message" -ForegroundColor Red
        $script:failCount++
        $script:failDetails += "[$Name] $Message"
    }
}

function Assert-Contains {
    param([string]$Name, [string]$Path, [string]$Pattern)
    $content = Get-Content -LiteralPath $Path -Raw -ErrorAction SilentlyContinue
    Assert-True $Name ($null -ne $content -and $content -match $Pattern) "Expected '$Pattern' in $Path"
}

function Assert-NotContains {
    param([string]$Name, [string]$Path, [string]$Pattern)
    $content = Get-Content -LiteralPath $Path -Raw -ErrorAction SilentlyContinue
    Assert-True $Name ($null -ne $content -and $content -notmatch $Pattern) "Forbidden '$Pattern' found in $Path"
}

Write-Host ''
Write-Host '=== LIVE-SP Routing Regression Tests ==='

# R1: Same-project LIVE-SP plus healthy MCPs routes without a mode prompt.
Write-Host '--- R1: Concord terminal + same-project LIVE-SP ---'
Assert-Contains 'R1.1 mode is detected before tool selection' $orchestrator '(?i)Betriebsmodus.*ermitteln.*PFLICHT|Mode detection must happen before'
Assert-Contains 'R1.2 LIVE-SP route prefers Studio Pro MCP' $modePolicy 'LIVE-SP-CURRENT.*Studio-Pro-MCP first'
Assert-Contains 'R1.3 Concord fallback requires a successful probe' $modePolicy 'successful read-only probe confirms it is healthy'
Assert-Contains 'R1.3 Concord fallback requires project binding' $modePolicy 'bound to this project'
Assert-Contains 'R1.4 no prompt when evidence is conclusive' $orchestrator 'Keine.*Nutzerfrage bei eindeutigem Ergebnis'
Assert-Contains 'R1.5 mxcli model mutations are forbidden in LIVE-SP' $implementationAgent 'mxcli-Modellmutationen sind in LIVE-SP-CURRENT verboten'
Assert-NotContains 'R1.6 old strong-signal prompt is removed' $routePolicy 'MUST ask exactly once when the strong signal'

# R2: A positively absent process is CLOSED-AUTONOM, not a failed-probe guess.
Write-Host '--- R2: Studio Pro closed ---'
Assert-Contains 'R2.1 no running process means CLOSED-AUTONOM' $modePolicy 'anyStudioProRunning = false.*CLOSED-AUTONOM'
Assert-Contains 'R2.2 timeout remains ambiguous' $modePolicy 'timeout.*UNKNOWN|timeout.*AMBIGUOUS-SP-STATE'

# R3: Project identity is the normalized full path, not a similar substring.
Write-Host '--- R3: Different project identity ---'
Assert-Contains 'R3.1 normalized absolute MPR path required' $modePolicy 'normalized absolute.*\.mpr.*confirmed'
Assert-Contains 'R3.2 detector builds a bounded path pattern' $detector '\$projectPattern = .*regex\]::Escape'
Assert-Contains 'R3.2 detector matches the bounded path pattern' $detector '\[regex\]::IsMatch'
Assert-NotContains 'R3.3 substring Contains matching removed' $detector '\.Contains\(\$projectArgument\)'
Assert-Contains 'R3.4 other project is not LIVE-SP-CURRENT' $modePolicy 'LIVE-SP-OTHER'
Assert-Contains 'R3.5 conflicting Studio Pro MCP identity is detected' $modePolicy 'Studio-Pro-MCP identity probe reports a different project'
Assert-Contains 'R3.5 conflicting identity uses existing ambiguous mode' $modePolicy 'use the existing\s+`AMBIGUOUS-SP-STATE` for that conflict'

# R4: Configured/offered is not healthy or project-correct.
Write-Host '--- R4: MCP configured but unhealthy ---'
Assert-Contains 'R4.1 tool presence is not health' $routePolicy 'Tool appears in the active tool set.*Successful operation'
Assert-Contains 'R4.2 a successful read-only call is required' $routePolicy 'successful non-mutating MCP call'
Assert-Contains 'R4.3 capability registry does not infer health' $capabilities 'Tool namespace presence means offered, not healthy'

# R5: Concord alone does not establish LIVE-SP; retain existing fallback order.
Write-Host '--- R5: Concord present, Studio Pro MCP absent ---'
Assert-Contains 'R5.1 Concord alone does not set LIVE-SP' $routePolicy 'Concord availability alone does not make the project LIVE-SP'
Assert-Contains 'R5.2 Concord is fallback, not primary' $modePolicy 'Studio-Pro-MCP first.*Concord MCP is the existing fallback'

# R6: mxcli installation never overrides a LIVE-SP prohibition.
Write-Host '--- R6: mxcli installed while LIVE-SP is definite ---'
Assert-Contains 'R6.1 operating-mode policy forbids mxcli mutations' $modePolicy 'Never use mxcli for model mutations'
Assert-Contains 'R6.2 implementation route has explicit mxcli prohibition' $implementationAgent 'mxcli-Modellmutationen sind in LIVE-SP-CURRENT verboten'
Assert-Contains 'R6.3 no mxcli fallback after MCP failure' $routePolicy 'never fall\s+back to mxcli after MCP failure'
Assert-Contains 'R6.4 orchestrator recheck is at first model mutation' $orchestrator 'ERSTEN Mendix-Modell-Mutation einer Session'
Assert-Contains 'R6.4 orchestrator recheck is route-independent' $orchestrator 'zulaessige Route: Betriebsmodus erneut'
Assert-NotContains 'R6.5 recheck is not limited to mxcli exec' $orchestrator 'vor dem ERSTEN `mxcli exec`'

# R7: Ask once only when mode remains ambiguous at a mutation boundary.
Write-Host '--- R7: Mode remains technically ambiguous ---'
Assert-Contains 'R7.1 ambiguity has distinct mode' $modePolicy 'AMBIGUOUS-SP-STATE'
Assert-Contains 'R7.2 question is limited to mutation boundary' $modePolicy 'ask ONE precise question'
Assert-Contains 'R7.2 question follows failed mutation-boundary recheck' $modePolicy 'ambiguity remains at the mutation boundary'
Assert-Contains 'R7.3 no mutation via mxcli while ambiguous' $routePolicy 'do not mutate through mxcli'

# R8: No repeated questions for unchanged state; freshness checks remain.
Write-Host '--- R8: Unchanged mode in same session ---'
Assert-Contains 'R8.1 unchanged mode is not re-asked' $routePolicy 'unchanged mode is not'
Assert-Contains 'R8.1 unchanged mode is not re-asked' $routePolicy 're-asked during the same session'
Assert-Contains 'R8.2 startup re-detects mode' $routePolicy 'Re-detect at Startup Re-Sync'
Assert-Contains 'R8.3 mutation-boundary recheck retained' $modePolicy 'Immediately before the first Mendix model mutation'

Write-Host ''
Write-Host "Results: $passCount passed, $failCount failed"
if ($failDetails.Count -gt 0) {
    $failDetails | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
}
exit $failCount
