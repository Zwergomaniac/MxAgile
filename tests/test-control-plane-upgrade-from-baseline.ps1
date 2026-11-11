<#
.SYNOPSIS
    Acceptance: a project installed from the pre-experiment baseline tag upgrades to the
    control-plane branch and becomes usable through the existing update/Doctor/re-sync path.

.DESCRIPTION
    previous tagged MxAgile -> project state -> update to current -> Doctor -> context invalidated
    -> re-sync -> guard verdicts. Needs a cached mxcli (MXCLI_TEST_BINARY or the shared test cache);
    without it the result is UNAVAILABLE (exit 2), never PASS.
#>

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$RepoRoot = Split-Path -Parent $PSScriptRoot
$BaselineTag = 'mxagile-reality-hardening-2026-11-11'
$Guard = Join-Path $RepoRoot 'experiments/control-plane/guard.py'
$PassCount = 0; $FailCount = 0
function Assert-True {
    param([string]$Name, [bool]$Condition, [string]$Message = '')
    if ($Condition) { Write-Host "  PASS: $Name" -ForegroundColor Green; $script:PassCount++ }
    else { Write-Host "  FAIL: $Name -- $Message" -ForegroundColor Red; $script:FailCount++ }
}
function Invoke-Git { param([string]$Root) & git -C $Root -c user.name=t -c user.email=t@example.invalid @args 2>&1 | Out-Null; if ($LASTEXITCODE) { throw "git $args failed" } }
$HookMarker = '.mxagile/tools/control-plane/enforcement.py'
function Get-PreToolGroups {
    param([string]$Root)
    $settingsPath = Join-Path $Root '.claude/settings.json'
    if (-not (Test-Path -LiteralPath $settingsPath)) { return @() }
    $settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
    if (-not $settings.PSObject.Properties['hooks'] -or -not $settings.hooks.PSObject.Properties['PreToolUse']) { return @() }
    return @($settings.hooks.PreToolUse)
}
function Test-OwnedGroup { param([object]$Group) @($Group.hooks | Where-Object { ([string]$_.command).Contains($HookMarker) }).Count -gt 0 }
function Invoke-InstalledAdapter {
    # Runs the adapter exactly where the registered hook command points (installed copy, not the repo source).
    param([string]$Root, [hashtable]$Payload)
    $env:CLAUDE_PROJECT_DIR = $Root
    try {
        $json = ($Payload + @{ cwd = $Root }) | ConvertTo-Json -Compress -Depth 10
        $output = $json | & python -B (Join-Path $Root '.mxagile/tools/control-plane/enforcement.py')
    } finally { Remove-Item Env:CLAUDE_PROJECT_DIR -ErrorAction SilentlyContinue }
    if (-not $output) { return $null }
    return ($output -join "`n") | ConvertFrom-Json
}
function Invoke-Guard {
    param([string]$Root, [hashtable]$Request)
    $requestPath = Join-Path $Root '.concord/guard-request.json'
    New-Item -ItemType Directory -Path (Split-Path $requestPath) -Force | Out-Null
    $Request | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $requestPath -Encoding UTF8
    $output = & python $Guard --project-root $Root --request $requestPath
    return ($output -join "`n") | ConvertFrom-Json
}

$mxcli = if ($env:MXCLI_TEST_BINARY) { $env:MXCLI_TEST_BINARY } else { Join-Path $env:TEMP 'mxagile-mxcli-test-cache/mxcli.exe' }
if (-not (Test-Path -LiteralPath $mxcli -PathType Leaf)) {
    Write-Host 'UNAVAILABLE: no cached mxcli binary; baseline upgrade acceptance not executed.' -ForegroundColor Yellow
    exit 2
}
$previousBinary = $env:MXCLI_TEST_BINARY
$env:MXCLI_TEST_BINARY = $mxcli

$baselineCommit = (& git -C $RepoRoot rev-parse "$BaselineTag^{commit}").Trim()
$currentCommit = (& git -C $RepoRoot rev-parse HEAD).Trim()
if ($currentCommit -eq $baselineCommit) {
    Write-Host 'UNAVAILABLE: HEAD equals the baseline tag; there is no version delta to upgrade.' -ForegroundColor Yellow
    exit 2
}
$work = Join-Path $env:TEMP "mxagile-cp-upgrade-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
$dist = Join-Path $work 'baseline-dist'
$project = Join-Path $work 'project'
New-Item -ItemType Directory -Path $dist, $project -Force | Out-Null

try {
    Write-Host "--- 1. Baseline distribution $BaselineTag ($($baselineCommit.Substring(0, 8))) ---" -ForegroundColor Cyan
    $zip = Join-Path $work 'baseline.zip'
    & git -C $RepoRoot archive --format=zip -o $zip $BaselineTag
    Expand-Archive -LiteralPath $zip -DestinationPath $dist

    New-Item -ItemType File -Path (Join-Path $project 'Fixture.mpr') | Out-Null
    Invoke-Git $project init -q
    Invoke-Git $project add -A
    Invoke-Git $project commit -qm 'mendix project'
    $baselineInstall = @(& pwsh -NoProfile -File (Join-Path $dist 'scripts/install-core.ps1') -ProjectRoot $project -ProvenanceCoreCommit $baselineCommit 2>&1)
    Assert-True 'baseline install succeeds' ($LASTEXITCODE -eq 0) ($baselineInstall | Select-Object -Last 5 | Out-String)
    $baselineProvenance = Get-Content (Join-Path $project '.mxagile/state/core-provenance.json') -Raw | ConvertFrom-Json
    Assert-True 'baseline version is detectable from Core provenance' ($baselineProvenance.commit -eq $baselineCommit) "commit=$($baselineProvenance.commit)"
    Assert-True 'baseline installs no control-plane hook (no persistent host config before Phase 1C)' (@(Get-PreToolGroups $project | Where-Object { Test-OwnedGroup $_ }).Count -eq 0) 'baseline already registered'
    # A developer-owned PreToolUse hook that every update must preserve.
    $settingsPath = Join-Path $project '.claude/settings.json'
    $settings = if (Test-Path -LiteralPath $settingsPath) { Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json } else { [pscustomobject]@{} }
    if (-not $settings.PSObject.Properties['hooks']) { $settings | Add-Member -NotePropertyName hooks -NotePropertyValue ([pscustomobject]@{}) }
    $foreignGroup = [pscustomobject]@{ matcher = 'Bash'; hooks = @([pscustomobject]@{ type = 'command'; command = 'developer-audit-hook' }) }
    if ($settings.hooks.PSObject.Properties['PreToolUse']) { $settings.hooks.PreToolUse = @($settings.hooks.PreToolUse) + $foreignGroup }
    else { $settings.hooks | Add-Member -NotePropertyName PreToolUse -NotePropertyValue @($foreignGroup) }
    New-Item -ItemType Directory -Path (Split-Path $settingsPath) -Force | Out-Null
    [System.IO.File]::WriteAllText($settingsPath, ($settings | ConvertTo-Json -Depth 100), [System.Text.UTF8Encoding]::new($false))

    Write-Host '--- 2. Realistic project state at baseline (legacy Wave without testability_gate) ---' -ForegroundColor Cyan
    $mission = "schema_version: 1`nmission_id: MISSION-2026-11-11-upgrade`ncreated_at: '2026-11-11'`nobjective: Upgrade fixture`ncompletion_boundary: WAVE_IMPLEMENTATION_COMPLETE`ncriteria:`n  lifecycle_derived:`n    implementation: {required: true, status: pending}`nactive_wave: W01`nprogress:`n  mission: active`n"
    $process = "waves:`n  W01:`n    phase: ready`n    gates:`n      gate_to_refinement: {result: passed}`n      gate_to_ready: {result: passed}`n"
    $owned = @{
        'planning/mission/mission-state.yaml' = $mission
        'planning/lifecycle/process-state.yaml' = $process
        'planning/execution-waves.md' = "# Execution Waves`n`n## Wave W01 - Upgrade fixture`n"
    }
    foreach ($relative in $owned.Keys) {
        $path = Join-Path $project $relative
        New-Item -ItemType Directory -Path (Split-Path $path) -Force | Out-Null
        [System.IO.File]::WriteAllText($path, $owned[$relative], [System.Text.UTF8Encoding]::new($false))
    }
    Invoke-Git $project add -A
    Invoke-Git $project commit -qm 'baseline project state'
    & pwsh -NoProfile -File (Join-Path $dist 'scripts/Write-MxAgileEpochCheckpoint.ps1') -ProjectRoot $project -MissionId 'MISSION-2026-11-11-upgrade' | Out-Null
    $ownedHashes = @{}
    foreach ($relative in $owned.Keys) { $ownedHashes[$relative] = (Get-FileHash (Join-Path $project $relative)).Hash }

    Write-Host '--- 3. Update to the control-plane branch ---' -ForegroundColor Cyan
    $update = @(& pwsh -NoProfile -Command "& '$(Join-Path $RepoRoot 'scripts/install-core.ps1')' -ProjectRoot '$project' -IsUpdate `$true -ProvenanceCoreCommit '$currentCommit'" 2>&1)
    Assert-True 'update from baseline succeeds' ($LASTEXITCODE -eq 0) ($update | Select-Object -Last 5 | Out-String)
    $handoff = Get-Content (Join-Path $project '.mxagile/state/last-update-result.json') -Raw | ConvertFrom-Json
    Assert-True 'update records PREVIOUS -> CURRENT identity' ($handoff.framework.previous_commit -eq $baselineCommit -and $handoff.framework.commit -eq $currentCommit) "$($handoff.framework.previous_commit) -> $($handoff.framework.commit)"
    Assert-True 'update invalidates the session context' ($handoff.update_state -eq 'UPDATE_INSTALLED_RESTART_REQUIRED' -and $handoff.context_state -eq 'STALE') $handoff.update_state
    Assert-True 'Doctor ran and the upgraded project is not BLOCKED' ($handoff.doctor.executed -and $handoff.doctor.compatibility -in @('COMPATIBLE', 'PARTIAL')) "compatibility=$($handoff.doctor.compatibility) reason=$($handoff.doctor.reason)"
    Assert-True 'no active update transaction remains after a clean update' (-not (Test-Path (Join-Path $project '.mxagile/state/update-transaction.json'))) 'transaction left behind'
    $preserved = @($owned.Keys | Where-Object { (Get-FileHash (Join-Path $project $_)).Hash -eq $ownedHashes[$_] })
    Assert-True 'project-owned lifecycle state is preserved byte-identically' ($preserved.Count -eq $owned.Count) "preserved=$($preserved.Count)/$($owned.Count)"
    $installedAdapter = @('guard.py', 'enforcement.py', 'child_contract.py', 'control-plane-verdict.schema.json') | Where-Object { -not (Test-Path (Join-Path $project ".mxagile/tools/control-plane/$_")) }
    Assert-True 'update distributes the control-plane adapter into .mxagile/tools/control-plane' (@($installedAdapter).Count -eq 0) "missing=$($installedAdapter -join ',')"
    Assert-True 'update reports the hook registration' (($update -join "`n") -match 'CONTROL_PLANE_HOOK: REGISTERED') (($update | Select-String 'CONTROL_PLANE_HOOK') -join ';')
    $groups = @(Get-PreToolGroups $project)
    $ownedGroups = @($groups | Where-Object { Test-OwnedGroup $_ })
    Assert-True 'hook registered once, first in PreToolUse, with fail-closed command' ($ownedGroups.Count -eq 1 -and (Test-OwnedGroup $groups[0]) -and $groups[0].hooks[0].command.Contains('|| exit 2')) "groups=$($groups.Count) owned=$($ownedGroups.Count)"
    Assert-True 'developer-owned PreToolUse hook survives the update' (@($groups | Where-Object { $_.hooks[0].command -eq 'developer-audit-hook' }).Count -eq 1) 'foreign hook lost'
    Invoke-Git $project add -A
    Invoke-Git $project commit -qm 'update MxAgile Core'
    $handoffSchema = Get-Content (Join-Path $project '.mxagile/schemas/delegation-handoff.schema.json') -Raw | ConvertFrom-Json
    $versions = @($handoffSchema.properties.schema_version.enum)
    Assert-True 'installed handoff schema accepts existing 1.3 and new 1.4 handoffs' ($versions -contains '1.3' -and $versions -contains '1.4') ($versions -join ',')

    Write-Host '--- 4. Guard before re-sync must not pass ---' -ForegroundColor Cyan
    $transition = @{ gate_type = 'transition'; mission_id = 'MISSION-2026-11-11-upgrade'; wave_id = 'W01'; target_phase = 'implementing'; authorization = @{ status = 'confirmed'; reference = 'acceptance-test' } }
    $stale = Invoke-Guard $project $transition
    $staleCodes = @($stale.must_findings | ForEach-Object code)
    Assert-True 'stale context after update is refused with a re-sync recovery' ($stale.verdict -ne 'pass' -and $staleCodes -contains 'CONTEXT_STALE_AFTER_UPDATE') "verdict=$($stale.verdict) codes=$($staleCodes -join ',')"
    $mcpWrite = Invoke-InstalledAdapter $project @{ tool_name = 'mcp__mendix-studio-pro__create_page'; tool_input = @{ name = 'Orders' } }
    Assert-True 'installed adapter denies a Mendix MCP write before re-sync with recovery resync' ($mcpWrite -and $mcpWrite.hookSpecificOutput.permissionDecision -eq 'deny' -and $mcpWrite.hookSpecificOutput.permissionDecisionReason -match 'recovery: resync') ($mcpWrite | ConvertTo-Json -Compress)
    # Claude Code on Windows runs hook commands through Git Bash; WSL bash cannot see Windows paths.
    $gitBash = Join-Path ((& git --exec-path) -replace '/', '\') '..\..\..\bin\bash.exe'
    $bash = if (Test-Path -LiteralPath $gitBash) { Get-Item -LiteralPath $gitBash | Select-Object @{ n = 'Source'; e = { $_.FullName } } } else { $null }
    if ($bash) {
        # Exact registered command line, including the fail-closed `|| exit 2` wrapper.
        $registered = (Get-PreToolGroups $project)[0].hooks[0].command
        $env:CLAUDE_PROJECT_DIR = $project.Replace('\', '/')
        try {
            $shellOut = '{"tool_name":"Write","tool_input":{"file_path":"javascriptsource/x.js"}}' | & $bash.Source -c $registered
            $shellExit = $LASTEXITCODE
        } finally { Remove-Item Env:CLAUDE_PROJECT_DIR -ErrorAction SilentlyContinue }
        Assert-True 'registered command line runs the installed adapter and denies' ($shellExit -eq 0 -and (($shellOut -join '') -match '"permissionDecision": "deny"')) "exit=$shellExit out=$shellOut"
        $broken = $registered.Replace('enforcement.py', 'missing-adapter.py')
        $env:CLAUDE_PROJECT_DIR = $project.Replace('\', '/')
        try { '{}' | & $bash.Source -c $broken 2>&1 | Out-Null; $brokenExit = $LASTEXITCODE } finally { Remove-Item Env:CLAUDE_PROJECT_DIR -ErrorAction SilentlyContinue }
        Assert-True 'unrunnable adapter blocks the call (exit 2)' ($brokenExit -eq 2) "exit=$brokenExit"
    } else {
        Write-Host '  UNAVAILABLE: Git Bash not found; registered command line not executed (direct adapter call only).' -ForegroundColor Yellow
    }

    Write-Host '--- 5. Re-sync, then use the new guard on the upgraded project ---' -ForegroundColor Cyan
    & pwsh -NoProfile -File (Join-Path $RepoRoot 'scripts/Write-MxAgileEpochCheckpoint.ps1') -ProjectRoot $project -MissionId 'MISSION-2026-11-11-upgrade' | Out-Null
    $ready = Invoke-Guard $project $transition
    Assert-True 'upgraded legacy project passes the transition guard after re-sync' ($ready.verdict -eq 'pass') (($ready.must_findings | ForEach-Object code) -join ',')
    Assert-True 'legacy Wave without testability_gate is tolerated, not required' (@($ready.should_findings | ForEach-Object code) -contains 'LEGACY_GATE_NOT_RECORDED') 'advisory missing'
    $done = $transition.Clone(); $done.target_phase = 'done'
    $illegal = Invoke-Guard $project $done
    Assert-True 'illegal transition remains refused after upgrade' ($illegal.verdict -eq 'fail') $illegal.verdict
    $payload = @{ tool_name = 'Write'; tool_input = @{ file_path = 'javascriptsource/orders/x.js' } }
    $hook = Invoke-InstalledAdapter $project $payload
    Assert-True 'host enforcement denies an implementation write while the Wave is not implementing' ($hook.hookSpecificOutput.permissionDecision -eq 'deny' -and $hook.hookSpecificOutput.permissionDecisionReason -match 'MUTATION_PHASE_BLOCKED') ($hook | ConvertTo-Json -Compress)

    Write-Host '--- 6. Reality prompt on the upgraded project (Wave ready) ---' -ForegroundColor Cyan
    $processPath = Join-Path $project 'planning/lifecycle/process-state.yaml'
    $processBefore = (Get-FileHash $processPath).Hash
    $prompt = 'Plane und setze alle in der Navigation verlinkten Seiten HTML-first um.'
    $spawn = Invoke-InstalledAdapter $project @{ tool_name = 'Agent'; tool_input = @{ subagent_type = 'mxagile-implementation-agent'; prompt = $prompt } }
    $pageWrite = Invoke-InstalledAdapter $project @{ tool_name = 'mcp__concord-v2-mcp__apply_model_change'; tool_input = @{ unit = 'Navigation' } }
    Assert-True 'reality prompt: no writing child is started' ($spawn.hookSpecificOutput.permissionDecision -eq 'deny') ($spawn | ConvertTo-Json -Compress)
    Assert-True 'reality prompt: no model write via Concord MCP' ($pageWrite.hookSpecificOutput.permissionDecision -eq 'deny') ($pageWrite | ConvertTo-Json -Compress)
    Assert-True 'reality prompt: lifecycle untouched, no Wave 0 invented' ((Get-FileHash $processPath).Hash -eq $processBefore -and -not ((Get-Content $processPath -Raw) -match 'W00?:')) 'process-state changed'

    Write-Host '--- 7. Explicit implementing Wave + re-sync allows delivery ---' -ForegroundColor Cyan
    [System.IO.File]::WriteAllText($processPath, $process.Replace('phase: ready', 'phase: implementing'), [System.Text.UTF8Encoding]::new($false))
    Invoke-Git $project add -A
    Invoke-Git $project commit -qm 'developer approves implementation'
    $drift = Invoke-InstalledAdapter $project $payload
    Assert-True 'lifecycle commit without re-sync is still refused (HEAD_STALE)' ($drift.hookSpecificOutput.permissionDecision -eq 'deny' -and $drift.hookSpecificOutput.permissionDecisionReason -match 'HEAD_STALE') ($drift | ConvertTo-Json -Compress)
    & pwsh -NoProfile -File (Join-Path $RepoRoot 'scripts/Write-MxAgileEpochCheckpoint.ps1') -ProjectRoot $project -MissionId 'MISSION-2026-11-11-upgrade' | Out-Null
    $allowed = Invoke-InstalledAdapter $project $payload
    Assert-True 'implementation write is allowed after re-sync on an implementing Wave' ($allowed.hookSpecificOutput.permissionDecision -eq 'allow') ($allowed | ConvertTo-Json -Compress)

    Write-Host '--- 8. Second update is idempotent for the host registration ---' -ForegroundColor Cyan
    Invoke-Git $project add -A
    Invoke-Git $project commit -qm 'resync' --allow-empty
    $second = @(& pwsh -NoProfile -Command "& '$(Join-Path $RepoRoot 'scripts/install-core.ps1')' -ProjectRoot '$project' -IsUpdate `$true -ProvenanceCoreCommit '$currentCommit'" 2>&1)
    Assert-True 'second update succeeds' ($LASTEXITCODE -eq 0) ($second | Select-Object -Last 5 | Out-String)
    Assert-True 'second update reports CURRENT registration' (($second -join "`n") -match 'CONTROL_PLANE_HOOK: CURRENT') (($second | Select-String 'CONTROL_PLANE_HOOK') -join ';')
    $groups = @(Get-PreToolGroups $project)
    Assert-True 'no duplicate hook, developer hook still present' (@($groups | Where-Object { Test-OwnedGroup $_ }).Count -eq 1 -and @($groups | Where-Object { $_.hooks[0].command -eq 'developer-audit-hook' }).Count -eq 1) "groups=$($groups.Count)"
} finally {
    $env:MXCLI_TEST_BINARY = $previousBinary
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "PASS: $PassCount; FAIL: $FailCount"
if ($FailCount -gt 0) { exit 1 }
