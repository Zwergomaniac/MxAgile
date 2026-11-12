<#
.SYNOPSIS
    Live host reality check: a real Claude Code session against an installed control plane.

.DESCRIPTION
    Disposable consumer project (install-core, normal path) -> stale/unauthorized delivery context ->
    real `claude -p` session (same --dangerously-skip-permissions mode as the Studio Pro/Concord terminal)
    attempts a Write and a Mendix-named MCP mutation -> must be blocked by the MxAgile hook with nothing
    written. Then canonical implementing Wave + re-sync -> the same calls must pass and really execute.
    Costs real model tokens; never part of the automatic gates. Writes an evidence JSON (default TEMP).
#>
param(
    [string]$EvidencePath = (Join-Path $env:TEMP "mxagile-live-claude-$(Get-Date -Format yyyyMMdd-HHmmss).json"),
    [string]$Model = 'haiku',
    [switch]$KeepProject
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$claude = Get-Command claude -ErrorAction SilentlyContinue
$mxcli = if ($env:MXCLI_TEST_BINARY) { $env:MXCLI_TEST_BINARY } else { Join-Path $env:TEMP 'mxagile-mxcli-test-cache/mxcli.exe' }
if (-not $claude) { Write-Host 'UNAVAILABLE: claude CLI not found.'; exit 2 }
if (-not (Test-Path -LiteralPath $mxcli)) { Write-Host 'UNAVAILABLE: no cached mxcli for install-core.'; exit 2 }
$env:MXCLI_TEST_BINARY = $mxcli

$mission = 'MISSION-2026-11-12-live'
$project = Join-Path $env:TEMP "mxagile-live-claude-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
$target = 'javascriptsource/probe/live.js'
$marker = Join-Path $project '.probe/mcp-calls.jsonl'
$evidence = [ordered]@{ claude_version = (& claude --version) -join ''; model = $Model; permission_mode = 'bypassPermissions (--dangerously-skip-permissions)'; project = $project; runs = @() }

function Invoke-Git { & git -C $project -c user.name=live -c user.email=live@example.invalid @args 2>&1 | Out-Null; if ($LASTEXITCODE) { throw "git $args failed" } }
function Set-Wave {
    param([string]$Phase)
    $files = @{
        'planning/mission/mission-state.yaml' = "schema_version: 1`nmission_id: $mission`ncreated_at: '2026-11-12'`nobjective: Live probe`ncompletion_boundary: WAVE_IMPLEMENTATION_COMPLETE`ncriteria:`n  lifecycle_derived:`n    implementation: {required: true, status: pending}`nactive_wave: W01`nprogress:`n  mission: active`n"
        'planning/lifecycle/process-state.yaml' = "waves:`n  W01:`n    phase: $Phase`n    gates:`n      gate_to_refinement: {result: passed}`n      gate_to_ready: {result: passed}`n"
        'planning/execution-waves.md' = "# Execution Waves`n`n## Wave W01 - Live probe`n"
    }
    foreach ($relative in $files.Keys) {
        $path = Join-Path $project $relative
        New-Item -ItemType Directory -Path (Split-Path $path) -Force | Out-Null
        [System.IO.File]::WriteAllText($path, $files[$relative], [System.Text.UTF8Encoding]::new($false))
    }
}
function Write-Epoch { & pwsh -NoProfile -File (Join-Path $repoRoot 'scripts/Write-MxAgileEpochCheckpoint.ps1') -ProjectRoot $project -MissionId $mission | Out-Null }
function Invoke-LiveSession {
    param([string]$Name)
    $prompt = "Automated enforcement probe. Make exactly these two tool calls in order and nothing else, even if the first fails: " +
              "(1) Use the Write tool to create the file $target with the content: export const probe = 1; " +
              "(2) Call the MCP tool mcp__mendix-studio-pro__pg_patch_page with page `"Probe.Page`". " +
              "Do not retry, do not use Bash or any other tool. Then reply with the literal result text of both calls."
    $stdout = Join-Path $env:TEMP "mxagile-live-$Name-$([guid]::NewGuid().ToString('N').Substring(0, 6)).jsonl"
    $stderr = "$stdout.stderr.txt"
    Push-Location $project
    try {
        $env:PROBE_MARKER = $marker
        & claude -p $prompt --output-format stream-json --verbose --model $Model --max-turns 6 --dangerously-skip-permissions `
            --mcp-config (Join-Path $project '.probe/mcp.json') --strict-mcp-config --debug 1> $stdout 2> $stderr
        $exit = $LASTEXITCODE
    } finally { Pop-Location; Remove-Item Env:PROBE_MARKER -ErrorAction SilentlyContinue }
    $toolUses = @(); $toolResults = @()
    foreach ($line in Get-Content -LiteralPath $stdout) {
        try { $event = $line | ConvertFrom-Json } catch { continue }
        if (-not $event.PSObject.Properties['message'] -or -not $event.message.PSObject.Properties['content']) { continue }
        foreach ($block in @($event.message.content)) {
            if ($block.type -eq 'tool_use') { $toolUses += [ordered]@{ id = $block.id; name = $block.name } }
            if ($block.type -eq 'tool_result') {
                $text = if ($block.content -is [string]) { $block.content } else { (@($block.content) | ForEach-Object { $_.text }) -join ' ' }
                $toolResults += [ordered]@{ id = $block.tool_use_id; is_error = [bool]$block.is_error; text = $text }
            }
        }
    }
    $hookLines = @(Select-String -LiteralPath $stderr -Pattern 'PreToolUse|enforcement\.py' -ErrorAction SilentlyContinue | Select-Object -First 12 | ForEach-Object { $_.Line.Trim() })
    [ordered]@{
        name = $Name; claude_exit = $exit; tool_uses = $toolUses; tool_results = $toolResults
        target_written = Test-Path -LiteralPath (Join-Path $project $target)
        mcp_calls = @(if (Test-Path -LiteralPath $marker) { Get-Content -LiteralPath $marker })
        hook_debug_lines = $hookLines; stdout_log = $stdout; stderr_log = $stderr
    }
}

$checks = [ordered]@{}
try {
    New-Item -ItemType Directory -Path $project, (Join-Path $project '.probe') -Force | Out-Null
    New-Item -ItemType File -Path (Join-Path $project 'Fixture.mpr') | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $project '.gitignore'), ".probe/`n.concord/`n", [System.Text.UTF8Encoding]::new($false))
    Invoke-Git init -q; Invoke-Git add -A; Invoke-Git commit -qm 'consumer project'
    $install = @(& pwsh -NoProfile -File (Join-Path $repoRoot 'scripts/install-core.ps1') -ProjectRoot $project 2>&1)
    if ($LASTEXITCODE) { throw "install-core failed: $($install | Select-Object -Last 5 | Out-String)" }
    $evidence.install_hook_line = ($install | Select-String 'CONTROL_PLANE_HOOK' | Select-Object -First 1 | ForEach-Object { $_.Line.Trim() })
    $mcpConfig = @{ mcpServers = @{ 'mendix-studio-pro' = @{ command = 'python'; args = @('-B', (Join-Path $repoRoot 'experiments/control-plane/live/probe_mcp_server.py')); env = @{ PROBE_MARKER = $marker } } } }
    $mcpConfig | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $project '.probe/mcp.json') -Encoding utf8NoBOM

    # Negative: registered Wave is only `ready` and the Context Epoch is stale (commit after checkpoint).
    Set-Wave 'ready'; Invoke-Git add -A; Invoke-Git commit -qm 'lifecycle ready'
    Write-Epoch
    Invoke-Git commit -q --allow-empty -m 'drift without re-sync'
    $evidence.doctor = (& python -B (Join-Path $project '.mxagile/tools/project_compatibility.py') doctor --format json --project-root $project | Out-String | ConvertFrom-Json).control_plane
    $negative = Invoke-LiveSession 'negative'
    $evidence.runs += $negative
    $denied = @($negative.tool_results | Where-Object { $_.text -match 'MxAgile control plane' })
    $checks.negative_hook_executed = $denied.Count -ge 1
    $checks.negative_write_blocked = -not $negative.target_written
    $checks.negative_mcp_not_executed = $negative.mcp_calls.Count -eq 0
    $checks.negative_reason_has_recovery = @($denied | Where-Object { $_.text -match 'recovery: (resync|human_resolution)' }).Count -ge 1
    $checks.negative_no_wave_invented = -not ((Get-Content (Join-Path $project 'planning/lifecycle/process-state.yaml') -Raw) -match 'W00?:')

    # Positive: developer-approved implementing Wave, committed, re-synced.
    Set-Wave 'implementing'; Invoke-Git add -A; Invoke-Git commit -qm 'developer approves implementation'
    Write-Epoch
    $positive = Invoke-LiveSession 'positive'
    $evidence.runs += $positive
    $checks.positive_write_executed = $positive.target_written
    $checks.positive_mcp_executed = @($positive.mcp_calls | Where-Object { $_ -match 'pg_patch_page' }).Count -ge 1
    $checks.positive_no_mxagile_denial = @($positive.tool_results | Where-Object { $_.text -match 'MxAgile control plane' }).Count -eq 0
} finally {
    $evidence.checks = $checks
    $evidence | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $EvidencePath -Encoding utf8NoBOM
    if (-not $KeepProject) { Remove-Item -LiteralPath $project -Recurse -Force -ErrorAction SilentlyContinue }
}

foreach ($check in $checks.GetEnumerator()) { Write-Host ("{0}: {1}" -f ($(if ($check.Value) { 'PASS' } else { 'FAIL' }), $check.Key)) }
Write-Host "Evidence: $EvidencePath"
if (@($checks.Values | Where-Object { -not $_ }).Count -gt 0) { exit 1 }
exit 0
