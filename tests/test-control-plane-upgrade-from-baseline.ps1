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
function Assert-RunStoreIgnored {
    param([string]$Root)
    $paths = @(
        '.mxagile/state/runs/append.lock',
        '.mxagile/state/runs/events-RUN_AUDIT-2000-01.jsonl',
        '.mxagile/state/runs/events-RUN_AUDIT-2000-01.lock',
        '.mxagile/state/runs/events-PROJECT_HISTORY-2000-01.jsonl',
        '.mxagile/state/runs/events-PROJECT_HISTORY-2000-01.lock'
    )
    foreach ($path in $paths) {
        & git -C $Root check-ignore --quiet -- $path 2>$null
        Assert-True "git check-ignore: $path" ($LASTEXITCODE -eq 0) 'runtime path is not effectively ignored'
    }
}
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

    Write-Host '--- 3. All-host preflight and update ---' -ForegroundColor Cyan
    $oldProjectionBytes=[IO.File]::ReadAllBytes((Join-Path $project '.mxagile/state/projections-manifest.json'))
    $coreBeforePreflight=(Get-FileHash (Join-Path $project '.mxagile/state/core-provenance.json')).Hash
    $foreignProjection=Join-Path $project '.hermes/skills/mxagile/.hidden-owner'
    [IO.File]::WriteAllText($foreignProjection, 'foreign hidden data')
    $blockedUpdate=@(& pwsh -NoProfile -Command "& '$(Join-Path $RepoRoot 'scripts/install-core.ps1')' -ProjectRoot '$project' -IsUpdate `$true -ProvenanceCoreCommit '$currentCommit'" 2>&1)
    Assert-True 'foreign late host blocks before Core activation' ($LASTEXITCODE -ne 0 -and (Get-FileHash (Join-Path $project '.mxagile/state/core-provenance.json')).Hash -eq $coreBeforePreflight) ($blockedUpdate | Select-Object -Last 5 | Out-String)
    Assert-True 'foreign hidden projection survives preflight' ([IO.File]::ReadAllText($foreignProjection) -eq 'foreign hidden data')
    Remove-Item -LiteralPath $foreignProjection
    foreach ($hostFamily in @('.claude','.github','.agents')) {
        $emptyTarget=Join-Path $project "$hostFamily/skills/mocketeer-business-flows"
        if (Test-Path -LiteralPath $emptyTarget) { Remove-Item -LiteralPath $emptyTarget -Recurse -Force }
        New-Item -ItemType Directory -Path $emptyTarget -Force | Out-Null
    }
    $update = @(& pwsh -NoProfile -Command "& '$(Join-Path $RepoRoot 'scripts/install-core.ps1')' -ProjectRoot '$project' -IsUpdate `$true -ProvenanceCoreCommit '$currentCommit'" 2>&1)
    Assert-True 'update from baseline succeeds' ($LASTEXITCODE -eq 0) ($update | Select-Object -Last 5 | Out-String)
    $handoff = Get-Content (Join-Path $project '.mxagile/state/last-update-result.json') -Raw | ConvertFrom-Json
    Assert-True 'update records PREVIOUS -> CURRENT identity' ($handoff.framework.previous_commit -eq $baselineCommit -and $handoff.framework.commit -eq $currentCommit) "$($handoff.framework.previous_commit) -> $($handoff.framework.commit)"
    Assert-True 'update invalidates the session context' ($handoff.update_state -eq 'UPDATE_INSTALLED_RESTART_REQUIRED' -and $handoff.context_state -eq 'STALE') $handoff.update_state
    Assert-True 'Doctor ran and the upgraded project is not BLOCKED' ($handoff.doctor.executed -and $handoff.doctor.compatibility -in @('COMPATIBLE', 'PARTIAL')) "compatibility=$($handoff.doctor.compatibility) reason=$($handoff.doctor.reason)"
    Assert-True 'no active update transaction remains after a clean update' (-not (Test-Path (Join-Path $project '.mxagile/state/update-transaction.json'))) 'transaction left behind'
    $preserved = @($owned.Keys | Where-Object { (Get-FileHash (Join-Path $project $_)).Hash -eq $ownedHashes[$_] })
    Assert-True 'project-owned lifecycle state is preserved byte-identically' ($preserved.Count -eq $owned.Count) "preserved=$($preserved.Count)/$($owned.Count)"
    $installedAdapter = @('guard.py', 'enforcement.py', 'child_contract.py', 'control-plane-verdict.schema.json', 'run_events.py', 'run-event.schema.json') | Where-Object { -not (Test-Path (Join-Path $project ".mxagile/tools/control-plane/$_")) }
    Assert-True 'update distributes the control-plane adapter into .mxagile/tools/control-plane' (@($installedAdapter).Count -eq 0) "missing=$($installedAdapter -join ',')"
    Assert-RunStoreIgnored $project
    Assert-True 'update reports the hook registration' (($update -join "`n") -match 'CONTROL_PLANE_HOOK: REGISTERED') (($update | Select-String 'CONTROL_PLANE_HOOK') -join ';')
    $projectionProof=Get-Content -LiteralPath (Join-Path $project '.mxagile/state/projections-manifest.json') -Raw | ConvertFrom-Json
    Assert-True 'empty unowned skills finalized for all three hosts' ($projectionProof.projection_version -eq '2' -and @($projectionProof.outputs | Where-Object target -match '/mocketeer-business-flows/SKILL.md$').Count -eq 3)
    $faultDist=Join-Path $work 'fault-distribution'
    $faultZip=Join-Path $work 'fault.zip'
    & git -C $RepoRoot archive --format=zip -o $faultZip HEAD
    Expand-Archive -LiteralPath $faultZip -DestinationPath $faultDist
    Copy-Item -Path (Join-Path $RepoRoot 'scripts/*') -Destination (Join-Path $faultDist 'scripts') -Recurse -Force
    Copy-Item -LiteralPath (Join-Path $RepoRoot '.mxagile/schemas/update-transaction.schema.json') -Destination (Join-Path $faultDist '.mxagile/schemas/update-transaction.schema.json') -Force
    foreach ($changedControlFile in @('guard.py','control-plane-verdict.schema.json')) { Copy-Item -LiteralPath (Join-Path $RepoRoot "experiments/control-plane/$changedControlFile") -Destination (Join-Path $faultDist "experiments/control-plane/$changedControlFile") -Force }
    $faultGenerator=Join-Path $faultDist 'scripts/generate-mxagile-platform-skills.ps1'
    $faultText=Get-Content -LiteralPath $faultGenerator -Raw -Encoding utf8
    $faultText=$faultText.Replace('# --- Main ---', '# --- Main ---' + "`n" + 'if (-not $PreflightOnly) { throw "fixture projection apply failure" }')
    [IO.File]::WriteAllText($faultGenerator,$faultText,[Text.UTF8Encoding]::new($false))
    $partialProject=Join-Path $work 'partial-project'
    Copy-Item -LiteralPath $project -Destination $partialProject -Recurse
    $partialManifest=Join-Path $partialProject '.mxagile/state/projections-manifest.json'
    $partialManifestBefore=(Get-FileHash $partialManifest).Hash
    $failedProjection=@(& pwsh -NoProfile -Command "& '$(Join-Path $faultDist 'scripts/install-core.ps1')' -ProjectRoot '$partialProject' -IsUpdate `$true -ProvenanceCoreCommit '$currentCommit'" 2>&1)
    Assert-True 'synthetic projection failure occurs after Core application' ($LASTEXITCODE -ne 0) ($failedProjection | Select-Object -Last 6 | Out-String)
    $partialTransaction=Get-Content -LiteralPath (Join-Path $partialProject '.mxagile/state/update-transaction.json') -Raw | ConvertFrom-Json
    Assert-True 'partial update is precise and migration/Doctor have not started' ($partialTransaction.state -eq 'PARTIAL_UPDATE' -and $partialTransaction.failed_stage -eq 'GENERATED_PROJECTIONS' -and $partialTransaction.projection.core_applied -and -not $partialTransaction.projection.contract_migration_started -and -not $partialTransaction.projection.doctor_executed)
    Assert-True 'partial failure retains previous projection manifest' ((Get-FileHash $partialManifest).Hash -eq $partialManifestBefore)
    $partialCoreBefore=Get-Content -LiteralPath (Join-Path $partialProject '.mxagile/state/core-provenance.json') -Raw | ConvertFrom-Json
    $partialCoreHash=(Get-FileHash (Join-Path $partialProject '.mxagile/state/core-provenance.json')).Hash
    $partialTxPath=Join-Path $partialProject '.mxagile/state/update-transaction.json'
    $wrongTarget=Get-Content -LiteralPath $partialTxPath -Raw | ConvertFrom-Json -AsHashtable
    $wrongTarget.target_core.version='contradictory-target'
    $wrongTarget | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $partialTxPath -Encoding utf8
    $rejectedResume=@(& pwsh -NoProfile -Command "& '$(Join-Path $RepoRoot 'scripts/install-core.ps1')' -ProjectRoot '$partialProject' -IsUpdate `$true -ResumeUpdate" 2>&1)
    $retainedPartial=Get-Content -LiteralPath $partialTxPath -Raw | ConvertFrom-Json -AsHashtable
    Assert-True 'contradictory resume fails closed without downgrading already-applied Core state' ($LASTEXITCODE -ne 0 -and $retainedPartial.state -eq 'PARTIAL_UPDATE' -and (Get-FileHash (Join-Path $partialProject '.mxagile/state/core-provenance.json')).Hash -eq $partialCoreHash -and (Get-FileHash $partialManifest).Hash -eq $partialManifestBefore)
    $retainedPartial.target_core.version=$partialCoreBefore.version
    $retainedPartial | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $partialTxPath -Encoding utf8
    $partialResume=@(& pwsh -NoProfile -Command "& '$(Join-Path $RepoRoot 'scripts/install-core.ps1')' -ProjectRoot '$partialProject' -IsUpdate `$true -ResumeUpdate" 2>&1)
    Assert-True 'existing partial transaction resumes with the installed Core' ($LASTEXITCODE -eq 0) ($partialResume | Select-Object -Last 8 | Out-String)
    $partialCoreAfter=Get-Content -LiteralPath (Join-Path $partialProject '.mxagile/state/core-provenance.json') -Raw | ConvertFrom-Json
    Assert-True 'resume activates projections without reinstalling Core' ($partialCoreAfter.installed_at -eq $partialCoreBefore.installed_at -and $partialCoreAfter.commit -eq $partialCoreBefore.commit -and $partialCoreAfter.activation_state -eq 'ACTIVE')
    Assert-True 'successful partial resume retires only the active transaction' (-not (Test-Path -LiteralPath (Join-Path $partialProject '.mxagile/state/update-transaction.json')))
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
    $runEvents = (& python (Join-Path $project '.mxagile/tools/control-plane/run_events.py') --project-root $project read | ConvertFrom-Json)
    Assert-True 're-sync lazily initializes audit history with start/completed events' (@($runEvents.events | Where-Object { $_.event_type -in @('lifecycle_resync_started', 'lifecycle_resync_completed') }).Count -ge 2) "events=$($runEvents.total_valid)"
    Assert-RunStoreIgnored $project
    $runStatus = @(& git -C $project status --porcelain --untracked-files=all | Where-Object { $_ -match '\.mxagile/state/runs/' })
    Assert-True 'event writing creates no untracked or modified run-store paths' ($runStatus.Count -eq 0) ($runStatus -join '; ')
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

    Write-Host '--- 9. Anonymized grown legacy consumer on the installed Core ---' -ForegroundColor Cyan
    $legacyFixture = Join-Path $PSScriptRoot 'fixtures/legacy-upgrade/realistic-consumer.json'
    $loadFixture = @'
import json, sys, yaml
from pathlib import Path
root = Path(sys.argv[2])
for relative, value in json.loads(Path(sys.argv[1]).read_text()).items():
    path = root / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(yaml.safe_dump(value, sort_keys=False), encoding="utf-8")
# The installed hook reads the session Epoch before the tracked historical copy.
epoch = root / ".concord/context-epoch.yaml"
epoch.parent.mkdir(parents=True, exist_ok=True)
epoch.write_bytes((root / "planning/lifecycle/context-epoch.yaml").read_bytes())
'@
    & python -B -c $loadFixture $legacyFixture $project
    if ($LASTEXITCODE) { throw 'Legacy fixture could not be loaded.' }
    $doctorTool = Join-Path $project '.mxagile/tools/project_compatibility.py'
    $legacyDecision = Join-Path $project 'planning/decisions/DEC-101.yml'
    $decisionBefore = (Get-FileHash $legacyDecision).Hash
    $legacyDoctor = (& python -B $doctorTool doctor --project-root $project --format json) | ConvertFrom-Json
    Assert-True 'legacy complete does not hide the real missing successor' ($legacyDoctor.compatibility -eq 'BLOCKED' -and @($legacyDoctor.diagnostics | Where-Object blocking).Count -eq 1) 'unexpected blocking diagnostics'
    $missingSuccessor = @($legacyDoctor.diagnostics | Where-Object blocking)[0]
    Assert-True 'only the real Requirement successor decision remains' ($missingSuccessor.source_path -eq 'requirements/REQ-001.yml' -and $missingSuccessor.repairability -eq 'DECISION_REQUIRED') $missingSuccessor.source_path
    Assert-True 'legacy normalization Doctor is read-only' ((Get-FileHash $legacyDecision).Hash -eq $decisionBefore) 'Doctor rewrote a Decision'
    $legacyTransition = @{ gate_type = 'transition'; mission_id = 'MISSION-2026-01-01-legacy-upgrade'; wave_id = 'W01'; target_phase = 'implementing'; authorization = @{ status = 'confirmed'; reference = 'acceptance-test' } }
    $legacyGuard = Invoke-Guard $project $legacyTransition
    $legacyCodes = @($legacyGuard.must_findings | ForEach-Object code)
    Assert-True 'stale branch HEAD and Mission remain blocked, not normalized' ($legacyGuard.verdict -ne 'pass' -and $legacyCodes -contains 'DOCTOR_BLOCKED' -and $legacyCodes -contains 'BRANCH_STALE' -and $legacyCodes -contains 'HEAD_STALE' -and $legacyCodes -contains 'EPOCH_MISSION_MISMATCH') ($legacyCodes -join ',')
    $legacyPlan = (& python -B $doctorTool repair --project-root $project --dry-run) | ConvertFrom-Json
    Assert-True 'both legacy Decision aliases have scoped deterministic repair plans' (@($legacyPlan.repairs | Where-Object repair_type -eq 'LEGACY_DECISION_ALIASES_V1').Count -eq 2) 'missing Decision repair plans'
    $prepareContract = @'
import json, sys
from pathlib import Path
root = Path(sys.argv[1])
sys.path.insert(0, str(root / '.mxagile/tools'))
from project_compatibility import contract_snapshot
schema_path = root / '.mxagile/schemas/requirement.schema.json'
schema = json.loads(schema_path.read_text(encoding='utf-8-sig'))
schema['properties']['source']['enum'].remove('parity_check')
schema_path.write_text(json.dumps(schema), encoding='utf-8')
provenance_path = root / '.mxagile/state/core-provenance.json'
provenance = json.loads(provenance_path.read_text(encoding='utf-8-sig'))
provenance['artifact_contract'] = contract_snapshot(root)
provenance['flavor'] = 'legacy-brand'
provenance['product_flavor'] = None
provenance_path.write_text(json.dumps(provenance), encoding='utf-8')
'@
    & python -B -c $prepareContract $project
    if ($LASTEXITCODE) { throw 'Legacy contract identity fixture failed.' }
    $beforeContract = Get-Content (Join-Path $project '.mxagile/state/core-provenance.json') -Raw | ConvertFrom-Json
    $layerProvenancePath = Join-Path $project '.mxagile/layers/fixture-company/provenance.json'
    New-Item -ItemType Directory -Path (Split-Path $layerProvenancePath) -Force | Out-Null
    '{"layer_id":"fixture-company","version":"1.0.0","ref":"main","commit":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}' | Set-Content -LiteralPath $layerProvenancePath -Encoding utf8
    $layerHash = (Get-FileHash $layerProvenancePath).Hash
    $protectedLegacy = @{}
    foreach ($relative in @('planning/mission/mission-state.yaml','planning/lifecycle/process-state.yaml','planning/lifecycle/context-epoch.yaml','requirements/REQ-001.yml')) {
        $protectedLegacy[$relative] = (Get-FileHash (Join-Path $project $relative)).Hash
    }
    $legacyUpdate = @(& pwsh -NoProfile -Command "& '$(Join-Path $RepoRoot 'scripts/install-core.ps1')' -ProjectRoot '$project' -IsUpdate `$true -ProvenanceFlavor 'company-layer' -ProvenanceCoreCommit '$currentCommit' -ProvenanceCoreRef 'experiment/control-plane-sak-principles'" 2>&1)
    Assert-True 'contract-delta update installs despite the human decision blocker' ($LASTEXITCODE -eq 0) ($legacyUpdate | Select-Object -Last 5 | Out-String)
    $legacyHandoff = Get-Content (Join-Path $project '.mxagile/state/last-update-result.json') -Raw | ConvertFrom-Json
    $afterContract = Get-Content (Join-Path $project '.mxagile/state/core-provenance.json') -Raw | ConvertFrom-Json
    Assert-True 'same version and commit still observe the schema contract delta' ($afterContract.version -eq $beforeContract.version -and $afterContract.commit -eq $beforeContract.commit -and $afterContract.artifact_contract.fingerprint -ne $beforeContract.artifact_contract.fingerprint -and $afterContract.previous_artifact_contract.fingerprint -eq $beforeContract.artifact_contract.fingerprint) 'contract identity was replaced by version or commit equality'
    Assert-True 'update normalizes safe aliases before final Doctor and retains NEEDS_HUMAN' ($legacyHandoff.migration.status -eq 'NEEDS_HUMAN' -and @($legacyHandoff.migration.applied).Count -eq 2 -and $legacyHandoff.doctor.executed -and $legacyHandoff.doctor.compatibility -eq 'BLOCKED') ($legacyHandoff | ConvertTo-Json -Compress -Depth 8)
    Assert-True 'semantic product identity and company installation identity stay separate' ($afterContract.product_flavor -eq 'legacy-brand' -and $afterContract.flavor -eq 'legacy-brand' -and $afterContract.installation_flavor -eq 'company-layer') 'product flavor overwritten'
    Assert-True 'Core experimental ref never replaces Company Layer provenance' ($afterContract.ref -eq 'experiment/control-plane-sak-principles' -and (Get-FileHash $layerProvenancePath).Hash -eq $layerHash) 'layer identity changed'
    foreach ($relative in $protectedLegacy.Keys) {
        Assert-True "contract migration preserves $relative" ((Get-FileHash (Join-Path $project $relative)).Hash -eq $protectedLegacy[$relative]) 'project authority changed'
    }
    $readMigration = @'
import json, sys, yaml
from pathlib import Path
state = yaml.safe_load((Path(sys.argv[1]) / '.mxagile/migration/state.yaml').read_text(encoding='utf-8-sig'))
original = json.loads(Path(sys.argv[2]).read_text(encoding='utf-8-sig'))['.mxagile/migration/state.yaml']
print(json.dumps({'history_preserved': {k: v for k, v in state.items() if k != 'contract_migration'} == original, 'state': state}))
'@
    $migrationState = (& python -B -c $readMigration $project $legacyFixture) | ConvertFrom-Json
    Assert-True 'historical migration and canonicalization complete flags are retained' ($migrationState.history_preserved -and $migrationState.state.contract_migration.status -eq 'NEEDS_HUMAN') 'historical authority was rewritten'
    $rt2Project=Join-Path $work 'rt2-no-transaction'
    $rt2InstalledDistribution=Join-Path $work 'original-rt2-distribution'
    $rt2OriginalCommit='121499131e8476d79e4efa84dddb4858612dc21f'
    $rt2OriginalZip=Join-Path $work 'original-rt2.zip'
    & git -C $RepoRoot archive --format=zip -o $rt2OriginalZip $rt2OriginalCommit
    Expand-Archive -LiteralPath $rt2OriginalZip -DestinationPath $rt2InstalledDistribution
    New-Item -ItemType Directory -Path $rt2Project | Out-Null
    New-Item -ItemType File -Path (Join-Path $rt2Project 'RT2Fixture.mpr') | Out-Null
    Invoke-Git $rt2Project init -q
    Invoke-Git $rt2Project add -A
    Invoke-Git $rt2Project commit -qm 'original RT2 consumer fixture'
    $originalRT2Install=@(& pwsh -NoProfile -File (Join-Path $rt2InstalledDistribution 'scripts/install-core.ps1') -ProjectRoot $rt2Project -ProvenanceCoreCommit $rt2OriginalCommit -ProvenanceFlavor 'legacy-brand' 2>&1)
    Assert-True 'RT2 fixture uses the original pinned Core payload, not the repair runner payload' ($LASTEXITCODE -eq 0) ($originalRT2Install | Select-Object -Last 6 | Out-String)
    $rt2LayerPath=Join-Path $rt2Project '.mxagile/layers/fixture-company/provenance.json'
    New-Item -ItemType Directory -Path (Split-Path $rt2LayerPath) -Force | Out-Null
    Copy-Item -LiteralPath $layerProvenancePath -Destination $rt2LayerPath
    & python -B -c 'import json,sys; from pathlib import Path; path=Path(sys.argv[1])/".mxagile/state/core-provenance.json"; value=json.loads(path.read_text(encoding="utf-8-sig")); value["installation_flavor"]="company-layer"; path.write_text(json.dumps(value),encoding="utf-8")' $rt2Project
    & python -B -c $loadFixture $legacyFixture $rt2Project
    if ($LASTEXITCODE) { throw 'RT2 legacy-state fixture could not be loaded.' }
    [IO.File]::WriteAllBytes((Join-Path $rt2Project '.mxagile/state/projections-manifest.json'),$oldProjectionBytes)
    foreach ($hostFamily in @('.claude','.github','.agents')) {
        $emptyTarget=Join-Path $rt2Project "$hostFamily/skills/mocketeer-business-flows"
        Remove-Item -LiteralPath $emptyTarget -Recurse -Force
        New-Item -ItemType Directory -Path $emptyTarget | Out-Null
    }
    Assert-True 'RT2 fixture has no transaction, new Core and three empty host targets' (-not (Test-Path -LiteralPath (Join-Path $rt2Project '.mxagile/state/update-transaction.json')))
    $rt2CoreHash=(Get-FileHash (Join-Path $rt2Project '.mxagile/state/core-provenance.json')).Hash
    $rt2LayerHash=(Get-FileHash (Join-Path $rt2Project '.mxagile/layers/fixture-company/provenance.json')).Hash
    $rt2RequirementHash=(Get-FileHash (Join-Path $rt2Project 'requirements/REQ-001.yml')).Hash
    $rt2BeforeGuard=Invoke-Guard $rt2Project $legacyTransition
    Assert-True 'projection recovery precedes migration, human resolution and re-sync' ($rt2BeforeGuard.recovery_plan.primary_next_action -eq 'resume_projection' -and $rt2BeforeGuard.verdict -ne 'pass')
    $rt2Resume=@(& pwsh -NoProfile -Command "& '$(Join-Path $RepoRoot 'scripts/install-core.ps1')' -ProjectRoot '$rt2Project' -IsUpdate `$true -ResumeUpdate" 2>&1)
    Assert-True 'observable RT2 state without a transaction is safely adopted and resumed' ($LASTEXITCODE -eq 0) ($rt2Resume | Select-Object -Last 8 | Out-String)
    Assert-True 'legacy resume preserves Core, Company Layer and human-owned Requirement' ((Get-FileHash (Join-Path $rt2Project '.mxagile/state/core-provenance.json')).Hash -eq $rt2CoreHash -and (Get-FileHash (Join-Path $rt2Project '.mxagile/layers/fixture-company/provenance.json')).Hash -eq $rt2LayerHash -and (Get-FileHash (Join-Path $rt2Project 'requirements/REQ-001.yml')).Hash -eq $rt2RequirementHash)
    $rt2HandoffPath=Join-Path $rt2Project '.mxagile/state/last-update-result.json'
    $rt2Handoff=Get-Content -LiteralPath $rt2HandoffPath -Raw | ConvertFrom-Json
    Assert-True 'resumed projections hand off to real migration and blocked Doctor' ($rt2Handoff.migration.status -eq 'NEEDS_HUMAN' -and $rt2Handoff.doctor.executed -and $rt2Handoff.doctor.compatibility -eq 'BLOCKED' -and $rt2Handoff.update_transaction.projection.status -eq 'COMPLETE')
    $rt2HandoffHash=(Get-FileHash $rt2HandoffPath).Hash
    $rt2ManifestHash=(Get-FileHash (Join-Path $rt2Project '.mxagile/state/projections-manifest.json')).Hash
    $rt2Repeat=@(& pwsh -NoProfile -Command "& '$(Join-Path $RepoRoot 'scripts/install-core.ps1')' -ProjectRoot '$rt2Project' -IsUpdate `$true -ResumeUpdate" 2>&1)
    Assert-True 'repeat resume is a read-only no-op with unchanged identities and handoff' ($LASTEXITCODE -eq 0 -and (Get-FileHash $rt2HandoffPath).Hash -eq $rt2HandoffHash -and (Get-FileHash (Join-Path $rt2Project '.mxagile/state/projections-manifest.json')).Hash -eq $rt2ManifestHash -and (Get-FileHash (Join-Path $rt2Project '.mxagile/state/core-provenance.json')).Hash -eq $rt2CoreHash) ($rt2Repeat | Select-Object -Last 5 | Out-String)
    $rt2AfterGuard=Invoke-Guard $rt2Project $legacyTransition
    Assert-True 'projection success does not grant delivery through human or stale-context blockers' ($rt2AfterGuard.verdict -ne 'pass' -and @($rt2AfterGuard.must_findings | Where-Object code -eq 'PROJECTION_RECOVERY_REQUIRED').Count -eq 0)
    $secondPlan = (& python -B $doctorTool repair --project-root $project --dry-run) | ConvertFrom-Json
    Assert-True 'automatic Decision normalization is idempotent' (@($secondPlan.repairs).Count -eq 0) 'repeat mutation planned'
    $installedWriter = Join-Path $project '.mxagile/tools/Write-MxAgileEpochCheckpoint.ps1'
    $epochPath = Join-Path $project '.concord/context-epoch.yaml'
    $epochBefore = (Get-FileHash $epochPath).Hash
    & pwsh -NoProfile -File $installedWriter -ProjectRoot $project -PreserveEvidence 2>&1 | Out-Null
    Assert-True 'direct re-sync refuses a human-blocked migration without changing Epoch' ($LASTEXITCODE -ne 0 -and (Get-FileHash $epochPath).Hash -eq $epochBefore) 'Epoch was fabricated'
    $approveSuccessor = @'
import sys, yaml
from pathlib import Path
path = Path(sys.argv[1]) / 'requirements/REQ-001.yml'
value = yaml.safe_load(path.read_text(encoding='utf-8-sig'))
value['superseded_by'] = 'REQ-111'
path.write_text(yaml.safe_dump(value, sort_keys=False), encoding='utf-8')
'@
    & python -B -c $approveSuccessor $project
    if ($LASTEXITCODE) { throw 'Explicit fixture successor decision failed.' }
    $migrationCommand = "python -B '$doctorTool' migrate --apply-safe --project-root '$project' --format json"
    $migrationHook = Invoke-InstalledAdapter $project @{ tool_name = 'Bash'; tool_input = @{ command = $migrationCommand } }
    Assert-True 'installed hook permits only the integrity-bound contract recovery' ($migrationHook.hookSpecificOutput.permissionDecision -eq 'allow') ($migrationHook | ConvertTo-Json -Compress)
    $resolved = (& python -B $doctorTool migrate --apply-safe --project-root $project --format json) | ConvertFrom-Json
    Assert-True 'explicit successor decision permits COMPLETE and a nonblocked Doctor' ($resolved.migration.status -eq 'COMPLETE' -and $resolved.doctor.compatibility -ne 'BLOCKED') ($resolved.migration | ConvertTo-Json -Compress -Depth 5)
    Invoke-Git $project add -A
    Invoke-Git $project commit -qm 'fixture developer resolves successor'
    $writerCommand = "pwsh -NoProfile -File '$installedWriter' -ProjectRoot '$project' -PreserveEvidence"
    $writerHook = Invoke-InstalledAdapter $project @{ tool_name = 'Bash'; tool_input = @{ command = $writerCommand } }
    Assert-True 'installed hook permits scope-preserving canonical re-sync' ($writerHook.hookSpecificOutput.permissionDecision -eq 'allow') ($writerHook | ConvertTo-Json -Compress)
    & pwsh -NoProfile -File $installedWriter -ProjectRoot $project -PreserveEvidence | Out-Null
    Assert-True 'installed Writer completes canonical re-sync' ($LASTEXITCODE -eq 0) 'Writer refused resolved scope'
    $resynced = Invoke-Guard $project $legacyTransition
    Assert-True 'resolved legacy project passes its real transition after re-sync' ($resynced.verdict -eq 'pass') (($resynced.must_findings | ForEach-Object code) -join ',')
    $stillReady = Invoke-InstalledAdapter $project $payload
    Assert-True 'recovery never grants ordinary implementation writes to a ready Wave' ($stillReady.hookSpecificOutput.permissionDecision -eq 'deny' -and $stillReady.hookSpecificOutput.permissionDecisionReason -match 'MUTATION_PHASE_BLOCKED') ($stillReady | ConvertTo-Json -Compress)
    $noRepeat = (& python -B $doctorTool migrate --apply-safe --project-root $project --format json) | ConvertFrom-Json
    Assert-True 'equal-contract retry requires no new migration' (-not $noRepeat.required) 'same contract restarted migration'
    $notStarted = $legacyTransition.Clone(); $notStarted.wave_id = 'W02'
    $unstarted = Invoke-Guard $project $notStarted
    Assert-True 'not_started never authorizes implementation' ($unstarted.verdict -ne 'pass') 'planned Wave was promoted'
} finally {
    $env:MXCLI_TEST_BINARY = $previousBinary
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "PASS: $PassCount; FAIL: $FailCount"
if ($FailCount -gt 0) { exit 1 }
