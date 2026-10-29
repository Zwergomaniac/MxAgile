<#
.SYNOPSIS
    Context Mode harness integration hardening — operational tests

.DESCRIPTION
    Tests the context_mode_integration capability of Get-MxAgileCapabilities.ps1
    against GUID temp project roots / temp home directories.

    Covers: not installed, installed-not-configured, configured-not-healthy,
    healthy+usable, Claude Code / Copilot CLI / VS Code Copilot / OpenCode
    specific configuration, OpenCode plugin + legacy MCP conflict, timeout,
    unknown/unsupported harness, no side effects on user configuration,
    fallback never blocks MxAgile.

    No network. No MCP calls. PATH is replaced per test (fake context-mode shim).
#>

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ScriptDir = Split-Path -Parent $PSScriptRoot
$Resolver  = Join-Path (Join-Path $ScriptDir 'scripts') 'Get-MxAgileCapabilities.ps1'

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
        $script:FailDetails += "  FAIL: $TestName -- $Message"
    }
}

$TempRoots = @()
function New-TempDir {
    $p = Join-Path $env:TEMP "mxagile-cm-test-$(New-Guid)"
    New-Item -ItemType Directory -Path $p | Out-Null
    $script:TempRoots += $p
    return $p
}

function New-Fixture {
    param([bool]$Enabled = $true)
    $root = New-TempDir
    $homeDir = New-TempDir
    $mx = Join-Path $root '.mxagile'
    New-Item -ItemType Directory -Path $mx | Out-Null
    @('version: "1.7.1"', 'min_compatible: "1.0"') | Set-Content (Join-Path $mx 'version.yaml') -Encoding UTF8
    Copy-Item (Join-Path (Join-Path $ScriptDir '.mxagile') 'capabilities.yaml') (Join-Path $mx 'capabilities.yaml')
    Copy-Item (Join-Path (Join-Path $ScriptDir '.mxagile') 'adapters') (Join-Path $mx 'adapters') -Recurse
    @('context_lifecycle:', '  enabled: true', 'context_optimization:', '  enabled: true',
      '  context_mode:', "    enabled: $($Enabled.ToString().ToLower())") | Set-Content (Join-Path $mx 'config.yaml') -Encoding UTF8
    return @{ Root = $root; Home = $homeDir }
}

function Write-Fx {
    param([string]$Base, [string]$Rel, [string]$Content)
    $p = Join-Path $Base $Rel
    New-Item -ItemType Directory -Path (Split-Path -Parent $p) -Force | Out-Null
    Set-Content -Path $p -Value $Content -Encoding UTF8
    return $p
}

# PATH shims: $BinWith provides a context-mode executable, $BinWithout is empty.
$BinWith = New-TempDir
Set-Content -Path (Join-Path $BinWith 'context-mode.cmd') -Value '@echo 1.0.169' -Encoding ASCII
$BinWithout = New-TempDir
$OriginalPath = $env:PATH

function Invoke-Cm {
    param($Fx, [string]$Harness, [string]$Health = 'unknown', [bool]$WithBinary = $false, [switch]$Raw,
        [switch]$ToolsObserved, [string[]]$Tools = @(), [string[]]$RequiredTools = @())
    $savedEnv = @{}
    foreach ($n in 'MXAGILE_HARNESS', 'CLAUDECODE', 'OPENCODE_SESSION_ID', 'OPENCODE_BASE_URL', 'COPILOT_HOME') {
        $savedEnv[$n] = [Environment]::GetEnvironmentVariable($n)
        [Environment]::SetEnvironmentVariable($n, $null)
    }
    [Environment]::SetEnvironmentVariable('COPILOT_HOME', (Join-Path $Fx.Home '.copilot'))
    $env:PATH = if ($WithBinary) { $BinWith } else { $BinWithout }
    try {
        $resolverArgs = @{
            Format = 'json'; ProjectRoot = $Fx.Root; HomeDir = $Fx.Home
            Harness = $Harness; ContextModeHealth = $Health
        }
        if ($ToolsObserved) {
            $resolverArgs.ContextModeToolsObserved = $true
            $resolverArgs.ContextModeTools = $Tools
        }
        if ($RequiredTools.Count -gt 0) { $resolverArgs.ContextModeRequiredTools = $RequiredTools }
        $out = & $Resolver @resolverArgs 2>&1
        $code = $LASTEXITCODE
        if ($Raw) { return @{ Code = $code; Out = $out } }
        $json = $out | ConvertFrom-Json
        return @{
            Code = $code
            Cap  = ($json.capabilities | Where-Object { $_.id -eq 'context_mode_integration' })
            Lifecycle = ($json.capabilities | Where-Object { $_.id -eq 'context_lifecycle' })
        }
    } finally {
        $env:PATH = $OriginalPath
        foreach ($n in $savedEnv.Keys) { [Environment]::SetEnvironmentVariable($n, $savedEnv[$n]) }
    }
}

Write-Host ""
Write-Host "=== Context Mode Harness Integration Tests ===" -ForegroundColor Cyan

try {

# --- Static: adapter files ---------------------------------------------------
Write-Host "--- Adapters ---" -ForegroundColor Yellow
$adapterFiles = @(
    '.mxagile/adapters/claude/context-mode.yaml',
    '.mxagile/adapters/copilot/context-mode-cli.yaml',
    '.mxagile/adapters/copilot/context-mode-vscode.yaml',
    '.mxagile/adapters/opencode/context-mode.yaml'
)
foreach ($rel in $adapterFiles) {
    $p = Join-Path $ScriptDir $rel
    Assert-True "Adapter exists: $rel" (Test-Path $p) "Not found: $p"
    if (Test-Path $p) {
        $t = Get-Content $p -Raw
        Assert-True "Adapter has upstream, runtime, load, verify and health guidance: $rel" (($t -match '(?m)^upstream_ref:') -and ($t -match '(?m)^runtime_probe:') -and ($t -match '(?m)^load_hint:') -and ($t -match '(?m)^verify:') -and ($t -match '(?m)^health_probe:')) 'missing key'
        Assert-True "Adapter pins assessed upstream commit: $rel" ($t -match '397137b0cfc2') 'commit missing'
    }
}
$ocAdapter = Get-Content (Join-Path $ScriptDir '.mxagile/adapters/opencode/context-mode.yaml') -Raw
Assert-True 'OpenCode adapter documents plugin + legacy MCP incompatibility' (($ocAdapter -match 'ZERO ctx_\* tools') -and ($ocAdapter -match 'repair_hint:')) 'conflict doc missing'

# --- 1. Not installed ----------------------------------------------------------
Write-Host "--- 1 not installed ---" -ForegroundColor Yellow
$fx = New-Fixture
$r = Invoke-Cm $fx 'claude_code'
$i = $r.Cap.integration
Assert-True '1. resolver exits 0' ($r.Code -eq 0) "exit $($r.Code)"
Assert-True '1. status not_installed' ($i.status -eq 'not_installed') "status=$($i.status)"
Assert-True '1. unavailable, not active' ($r.Cap.state.unavailable -eq $true -and $r.Cap.state.active -eq $false) 'state wrong'
Assert-True '1. platform supported, setup needed' ($i.platform_supported -eq $true -and $i.setup_needed -eq $true) 'flags wrong'
Assert-True '1. guidance is harness-specific (plugin install)' (($i.guidance -join ' ') -match 'plugin marketplace add mksglu/context-mode') ($i.guidance -join '|')
Assert-True '1. no automatic action' ($i.automatic_action -eq 'none') $i.automatic_action
Assert-True '1. fallback does not block MxAgile' ($i.fallback.blocks_mxagile -eq $false -and $i.fallback.full_repository_read -eq $false) 'fallback wrong'
Assert-True '1. fallback order' (($i.fallback.order -join ',') -eq 'deterministic_helpers,bounded_semantic_delegation,targeted_direct_read') ($i.fallback.order -join ',')
Assert-True '1. other capabilities unaffected' ($r.Lifecycle.state.active -eq $true) 'context_lifecycle not active'

# --- 2. Installed but not configured -------------------------------------------
Write-Host "--- 2 installed, not configured ---" -ForegroundColor Yellow
foreach ($h in 'claude_code', 'copilot_cli', 'vscode_copilot', 'opencode') {
    $fx = New-Fixture
    $r = Invoke-Cm $fx $h -WithBinary $true
    $i = $r.Cap.integration
    Assert-True "2. $h installed_not_configured" ($i.status -eq 'installed_not_configured') "status=$($i.status)"
    Assert-True "2. $h available but NOT active/usable" ($r.Cap.state.available -eq $true -and $r.Cap.state.active -eq $false -and $i.usable -eq $false) 'available must not imply usable'
    Assert-True "2. $h guidance present" ($i.guidance.Count -gt 0) 'no guidance'
}

# --- 3/4/11. Claude plugin: health matrix ---------------------------------------
Write-Host "--- 3/4/11 Claude plugin health ---" -ForegroundColor Yellow
$fx = New-Fixture
$null = Write-Fx $fx.Home '.claude/settings.json' '{ "enabledPlugins": { "context-mode@context-mode": true } }'
$r = Invoke-Cm $fx 'claude_code'
$i = $r.Cap.integration
Assert-True '3. configured, load evidence unknown -> configured_load_unknown' ($i.status -eq 'configured_load_unknown') "status=$($i.status)"
Assert-True '3. degraded, not active, not usable' ($r.Cap.state.degraded -eq $true -and $r.Cap.state.active -eq $false -and $i.usable -eq $false) 'must not be active without health'
Assert-True '3. plugin runtime detected without binary in PATH' ($i.runtime_present -eq $true -and $i.components.plugin -eq $true) 'plugin not detected'
Assert-True '3. hooks bundled with plugin' ($i.components.hooks -eq 'bundled_with_plugin') $i.components.hooks
$r = Invoke-Cm $fx 'claude_code' -ToolsObserved
Assert-True '3. config present, session tools explicitly absent -> configured_not_loaded' ($r.Cap.integration.status -eq 'configured_not_loaded' -and $r.Cap.integration.loaded -eq $false) "status=$($r.Cap.integration.status)"
$r = Invoke-Cm $fx 'claude_code' -Health 'healthy'
Assert-True '3b. health claim without observed tools is ignored' ($r.Cap.integration.status -eq 'configured_load_unknown' -and $r.Cap.integration.health -eq 'unknown' -and $r.Cap.integration.usable -eq $false) "status=$($r.Cap.integration.status) health=$($r.Cap.integration.health)"
$r = Invoke-Cm $fx 'claude_code' -ToolsObserved -Tools @('ctx_doctor', 'ctx_execute_file') -RequiredTools @('ctx_execute_file')
Assert-True '4. tools loaded, health unknown -> not healthy or usable' ($r.Cap.integration.status -eq 'loaded_health_unknown' -and $r.Cap.integration.loaded -eq $true -and $r.Cap.integration.health -eq 'unknown' -and $r.Cap.integration.usable -eq $false) "status=$($r.Cap.integration.status)"
$r = Invoke-Cm $fx 'claude_code' -Health 'healthy' -ToolsObserved -Tools @('ctx_execute_file') -RequiredTools @('ctx_execute_file')
Assert-True '4c. health claim without ctx_doctor in the observed tool set is ignored' ($r.Cap.integration.health -eq 'unknown' -and $r.Cap.integration.usable -eq $false) "health=$($r.Cap.integration.health)"
$r = Invoke-Cm $fx 'claude_code' -Health 'healthy' -ToolsObserved -Tools @('ctx_doctor') -RequiredTools @('ctx_execute_file')
Assert-True '4b. loaded tools do not include task operation -> not usable' ($r.Cap.integration.status -eq 'task_tools_missing' -and $r.Cap.integration.missing_required_tools -contains 'ctx_execute_file' -and $r.Cap.integration.usable -eq $false) "status=$($r.Cap.integration.status)"
$r = Invoke-Cm $fx 'claude_code' -Health 'failed' -ToolsObserved -Tools @('ctx_doctor', 'ctx_execute_file') -RequiredTools @('ctx_execute_file')
Assert-True '3. health failed -> loaded_unhealthy, not active' ($r.Cap.integration.status -eq 'loaded_unhealthy' -and $r.Cap.state.active -eq $false) "status=$($r.Cap.integration.status)"
$r = Invoke-Cm $fx 'claude_code' -Health 'timeout' -ToolsObserved -Tools @('ctx_doctor', 'ctx_execute_file') -RequiredTools @('ctx_execute_file')
Assert-True '11. timeout -> loaded_unhealthy, degraded, not active' ($r.Cap.integration.status -eq 'loaded_unhealthy' -and $r.Cap.state.degraded -eq $true -and $r.Cap.state.active -eq $false) "status=$($r.Cap.integration.status)"
Assert-True '11. timeout: resolver still exit 0, fallback non-blocking, lifecycle active' ($r.Code -eq 0 -and $r.Cap.integration.fallback.blocks_mxagile -eq $false -and $r.Lifecycle.state.active -eq $true) 'MxAgile blocked'
Assert-True '11. timeout guidance mentions doctor' (($r.Cap.integration.guidance -join ' ') -match 'ctx-doctor|doctor') ($r.Cap.integration.guidance -join '|')
$r = Invoke-Cm $fx 'claude_code' -Health 'healthy' -ToolsObserved -Tools @('ctx_doctor', 'ctx_execute_file') -RequiredTools @('ctx_execute_file')
Assert-True '4. healthy + enabled -> usable and active' ($r.Cap.integration.status -eq 'healthy' -and $r.Cap.integration.usable -eq $true -and $r.Cap.state.active -eq $true) "status=$($r.Cap.integration.status) active=$($r.Cap.state.active)"
Assert-True '4. load and health evidence are session-scoped' ($r.Cap.integration.load_source -eq 'agent_observed_tool_namespace' -and $r.Cap.integration.health_source -eq 'agent_observed_session_probe') "$($r.Cap.integration.load_source)|$($r.Cap.integration.health_source)"
Assert-True '4. hooks runtime is healthy only after ctx_doctor' ($r.Cap.integration.components.hooks_loaded -eq $true) "hooks_loaded=$($r.Cap.integration.components.hooks_loaded)"
$fxOff = New-Fixture -Enabled $false
$null = Write-Fx $fxOff.Home '.claude/settings.json' '{ "enabledPlugins": { "context-mode@context-mode": true } }'
$r = Invoke-Cm $fxOff 'claude_code' -Health 'healthy' -ToolsObserved -Tools @('ctx_doctor', 'ctx_execute_file') -RequiredTools @('ctx_execute_file')
Assert-True '4. healthy but disabled in config -> not usable or active (default OFF)' ($r.Cap.integration.usable -eq $false -and $r.Cap.state.enabled -eq $false -and $r.Cap.state.active -eq $false) 'disabled must not be usable'

# --- 5. Claude MCP-only vs disabled plugin --------------------------------------
Write-Host "--- 5 Claude specific ---" -ForegroundColor Yellow
$fx = New-Fixture
$null = Write-Fx $fx.Root '.mcp.json' '{ "mcpServers": { "context-mode": { "command": "npx", "args": ["-y","context-mode"] } } }'
$r = Invoke-Cm $fx 'claude_code' -WithBinary $true
$i = $r.Cap.integration
Assert-True '5. MCP-only mode detected, hooks absent' ($i.integration_mode -eq 'mcp_only' -and $i.components.hooks -eq 'absent' -and $i.components.mcp -eq $true) "mode=$($i.integration_mode) hooks=$($i.components.hooks)"
Assert-True '5. MCP-only reports no-routing finding' (($i.findings -join ' ') -match 'no hooks') ($i.findings -join '|')
$r = Invoke-Cm $fx 'claude_code' -Health 'healthy' -ToolsObserved -Tools @('ctx_doctor', 'ctx_execute_file') -RequiredTools @('ctx_execute_file')
Assert-True '5. loaded and healthy MCP-only stays non-usable without routing hooks' ($r.Cap.integration.status -eq 'loaded_hooks_missing' -and $r.Cap.integration.components.hooks_loaded -eq $false -and $r.Cap.integration.usable -eq $false) "status=$($r.Cap.integration.status)"
$fx = New-Fixture
$null = Write-Fx $fx.Home '.claude/settings.json' '{ "enabledPlugins": { "context-mode@context-mode": false } }'
$r = Invoke-Cm $fx 'claude_code'
Assert-True '5. explicitly disabled plugin is not configured' ($r.Cap.integration.configured -eq $false) "configured=$($r.Cap.integration.configured)"

# --- 6. Copilot CLI ----------------------------------------------------------------
Write-Host "--- 6 Copilot CLI ---" -ForegroundColor Yellow
$hookJson = '{ "version": 1, "hooks": { "preToolUse": [{"type":"command","command":"context-mode hook copilot-cli pretooluse"}], "postToolUse": [{"type":"command","command":"context-mode hook copilot-cli posttooluse"}], "sessionStart": [{"type":"command","command":"context-mode hook copilot-cli sessionstart"}], "preCompact": [{"type":"command","command":"context-mode hook copilot-cli precompact"}], "userPromptSubmitted": [{"type":"command","command":"context-mode hook copilot-cli userpromptsubmit"}], "agentStop": [{"type":"command","command":"context-mode hook copilot-cli stop"}] } }'
$fx = New-Fixture
$null = Write-Fx $fx.Home '.copilot/mcp-config.json' '{ "mcpServers": { "context-mode": { "command": "context-mode" } } }'
$null = Write-Fx $fx.Home '.copilot/hooks/context-mode.json' $hookJson
$r = Invoke-Cm $fx 'copilot_cli' -WithBinary $true -Health 'healthy' -ToolsObserved -Tools @('ctx_doctor', 'ctx_execute_file') -RequiredTools @('ctx_execute_file')
$i = $r.Cap.integration
Assert-True '6. MCP + hooks configured, healthy -> active' ($i.configured -eq $true -and $i.components.mcp -eq $true -and $i.components.hooks -eq 'present' -and $r.Cap.state.active -eq $true) "status=$($i.status) hooks=$($i.components.hooks)"
$priorSession = $r
$r = Invoke-Cm $fx 'copilot_cli'
Assert-True 'G3. prior-session health is not reused and missing runtime is distinguished' ($priorSession.Cap.integration.status -eq 'healthy' -and $r.Cap.integration.status -eq 'configured_runtime_missing' -and $r.Cap.integration.runtime_present -eq $false -and $r.Cap.integration.health -eq 'unknown' -and $r.Cap.integration.usable -eq $false -and (($r.Cap.integration.guidance -join ' ') -match 'npm install -g context-mode')) "current=$($r.Cap.integration.status) guidance=$($r.Cap.integration.guidance -join '|')"
$fx = New-Fixture
$null = Write-Fx $fx.Home '.copilot/hooks/context-mode.json' $hookJson
$r = Invoke-Cm $fx 'copilot_cli' -WithBinary $true -Health 'healthy'
Assert-True '6. hooks without MCP registration -> misconfigured (inert hooks)' ($r.Cap.integration.status -eq 'misconfigured' -and $r.Cap.state.degraded -eq $true -and $r.Cap.state.active -eq $false) "status=$($r.Cap.integration.status)"
$fx = New-Fixture
$null = Write-Fx $fx.Home '.claude/settings.json' '{ "enabledPlugins": { "context-mode@context-mode": true } }'
$null = Write-Fx $fx.Root '.mcp.json' '{ "mcpServers": { "context-mode": { "command": "npx" } } }'
$r = Invoke-Cm $fx 'copilot_cli' -WithBinary $true
Assert-True '6. Claude config is NOT projected onto Copilot CLI' ($r.Cap.integration.configured -eq $false -and $r.Cap.integration.status -eq 'installed_not_configured') "status=$($r.Cap.integration.status)"
Assert-True '6. Copilot CLI guidance names copilot plugin/mcp path' (($r.Cap.integration.guidance -join ' ') -match 'copilot (plugin install|mcp add)') ($r.Cap.integration.guidance -join '|')
$fx = New-Fixture
$pluginBase = '.copilot/plugins/context-mode'
$null = Write-Fx $fx.Home "$pluginBase/.github/plugin/plugin.json" '{ "name": "context-mode", "version": "1.0.169" }'
$null = Write-Fx $fx.Home "$pluginBase/.mcp.json" '{ "mcpServers": { "context-mode": { "command": "context-mode", "env": { "CONTEXT_MODE_PLATFORM": "copilot-cli" } } } }'
$null = Write-Fx $fx.Home "$pluginBase/hooks.json" $hookJson
$r = Invoke-Cm $fx 'copilot_cli' -WithBinary $true -Health 'healthy' -ToolsObserved -Tools @('ctx_doctor', 'ctx_execute_file') -RequiredTools @('ctx_execute_file')
Assert-True 'G4. official Copilot CLI plugin bundle detects MCP, hooks and live usability' ($r.Cap.integration.integration_mode -eq 'plugin' -and $r.Cap.integration.components.plugin -eq $true -and $r.Cap.integration.components.mcp -eq $true -and $r.Cap.integration.components.hooks -eq 'bundled_with_plugin' -and $r.Cap.integration.components.hooks_loaded -eq $true -and $r.Cap.integration.usable -eq $true) "status=$($r.Cap.integration.status)"
$fx = New-Fixture
$copilotProjectMcp = '{ "mcpServers": { "context-mode": { "command": "context-mode", "env": { "CONTEXT_MODE_PLATFORM": "copilot-cli" } } } }'
$null = Write-Fx $fx.Root '.mcp.json' $copilotProjectMcp
$null = Write-Fx $fx.Root '.github/hooks/context-mode.json' $hookJson
$r = Invoke-Cm $fx 'copilot_cli' -WithBinary $true -Health 'healthy' -ToolsObserved -Tools @('ctx_doctor', 'ctx_execute_file') -RequiredTools @('ctx_execute_file')
Assert-True '6. Copilot-marked project MCP + repo hooks are detected' ($r.Cap.integration.configured -eq $true -and $r.Cap.integration.components.hooks -eq 'present' -and $r.Cap.integration.usable -eq $true) "status=$($r.Cap.integration.status)"
$fx = New-Fixture
$r = Invoke-Cm $fx 'copilot_cli' -WithBinary $true
Assert-True 'G2. absent ctx tools in Concord discovery are not evidence of not-installed' ($r.Cap.integration.status -eq 'installed_not_configured' -and $r.Cap.integration.runtime_present -eq $true) "status=$($r.Cap.integration.status)"

$fx = New-Fixture
$null = Write-Fx $fx.Home '.copilot/mcp-config.json' '{ "mcpServers": { "context-mode": { "command": "context-mode" } } }'
$null = Write-Fx $fx.Home '.copilot/hooks/context-mode.json' $hookJson
$savedWtSession = [Environment]::GetEnvironmentVariable('WT_SESSION')
try {
    [Environment]::SetEnvironmentVariable('WT_SESSION', 'windows-terminal-session')
    $windowsTerminal = Invoke-Cm $fx 'copilot_cli' -WithBinary $true -Health 'healthy' -ToolsObserved -Tools @('ctx_doctor', 'ctx_execute_file') -RequiredTools @('ctx_execute_file')
    [Environment]::SetEnvironmentVariable('WT_SESSION', $null)
    $studioProTerminal = Invoke-Cm $fx 'copilot_cli' -WithBinary $true -Health 'healthy' -ToolsObserved -Tools @('ctx_doctor', 'ctx_execute_file') -RequiredTools @('ctx_execute_file')
} finally {
    [Environment]::SetEnvironmentVariable('WT_SESSION', $savedWtSession)
}
Assert-True 'G5. Studio Pro and Windows Terminal origin do not change equal project/session evidence' (($windowsTerminal.Cap.integration.status -eq $studioProTerminal.Cap.integration.status) -and ($windowsTerminal.Cap.integration.usable -eq $studioProTerminal.Cap.integration.usable) -and ($windowsTerminal.Cap.state.active -eq $studioProTerminal.Cap.state.active)) 'terminal origin changed capability semantics'

# --- 7. VS Code Copilot --------------------------------------------------------------
Write-Host "--- 7 VS Code Copilot ---" -ForegroundColor Yellow
$vsHooks = '{ "hooks": { "PreToolUse": [{"type":"command","command":"context-mode hook vscode-copilot pretooluse"}], "PostToolUse": [{"type":"command","command":"context-mode hook vscode-copilot posttooluse"}], "PreCompact": [{"type":"command","command":"context-mode hook vscode-copilot precompact"}], "SessionStart": [{"type":"command","command":"context-mode hook vscode-copilot sessionstart"}] } }'
$vsMcp = '{ "servers": { "context-mode": { "command": "context-mode" } } }'
$fx = New-Fixture
$null = Write-Fx $fx.Root '.vscode/mcp.json' $vsMcp
$null = Write-Fx $fx.Root '.github/hooks/context-mode.json' $vsHooks
$r = Invoke-Cm $fx 'vscode_copilot' -WithBinary $true -Health 'healthy' -ToolsObserved -Tools @('ctx_doctor', 'ctx_execute_file') -RequiredTools @('ctx_execute_file')
Assert-True '7. project mcp + hooks, healthy -> active' ($r.Cap.integration.status -eq 'healthy' -and $r.Cap.integration.components.hooks -eq 'present' -and $r.Cap.state.active -eq $true) "status=$($r.Cap.integration.status)"
Assert-True '7. VS Code hooks_loaded follows current-session ctx_doctor' ($r.Cap.integration.components.hooks_loaded -eq $true) "hooks_loaded=$($r.Cap.integration.components.hooks_loaded)"
$fx = New-Fixture
$null = Write-Fx $fx.Root '.vscode/mcp.json' $vsMcp
$null = Write-Fx $fx.Root '.github/hooks/context-mode.json' '{ "hooks": { "PreToolUse": [{"command":"context-mode hook vscode-copilot pretooluse"}], "PostToolUse": [{"command":"context-mode hook vscode-copilot posttooluse"}], "SessionStart": [{"command":"context-mode hook vscode-copilot sessionstart"}] } }'
$r = Invoke-Cm $fx 'vscode_copilot' -WithBinary $true
Assert-True '7. VS Code hooks missing PreCompact are misconfigured' ($r.Cap.integration.status -eq 'misconfigured') "status=$($r.Cap.integration.status)"
$fx = New-Fixture
$null = Write-Fx $fx.Root '.vscode/mcp.json' $vsMcp
$r = Invoke-Cm $fx 'vscode_copilot' -WithBinary $true
Assert-True '7. mcp without hooks -> configured, hooks absent, load unverified' ($r.Cap.integration.configured -eq $true -and $r.Cap.integration.components.hooks -eq 'absent' -and $r.Cap.integration.status -eq 'configured_load_unknown') "status=$($r.Cap.integration.status)"
$r = Invoke-Cm $fx 'vscode_copilot' -WithBinary $true -Health 'healthy' -ToolsObserved -Tools @('ctx_doctor', 'ctx_execute_file') -RequiredTools @('ctx_execute_file')
Assert-True '7. loaded VS Code MCP without hooks is not usable' ($r.Cap.integration.status -eq 'loaded_hooks_missing' -and $r.Cap.integration.usable -eq $false) "status=$($r.Cap.integration.status)"
$fx = New-Fixture
$null = Write-Fx $fx.Root '.github/hooks/context-mode.json' $vsHooks
$r = Invoke-Cm $fx 'vscode_copilot' -WithBinary $true
Assert-True '7. hooks without mcp.json entry -> misconfigured' ($r.Cap.integration.status -eq 'misconfigured') "status=$($r.Cap.integration.status)"
$fx = New-Fixture
$r = Invoke-Cm $fx 'vscode_copilot' -WithBinary $true
Assert-True '7. guidance names .vscode/mcp.json' (($r.Cap.integration.guidance -join ' ') -match '\.vscode/mcp\.json') ($r.Cap.integration.guidance -join '|')

# --- 8/9/10. OpenCode -------------------------------------------------------------------
Write-Host "--- 8/9/10 OpenCode ---" -ForegroundColor Yellow
$fx = New-Fixture
$null = Write-Fx $fx.Root 'opencode.json' '{ "$schema": "https://opencode.ai/config.json", "plugin": ["context-mode"] }'
$r = Invoke-Cm $fx 'opencode' -Health 'healthy' -ToolsObserved -Tools @('ctx_doctor', 'ctx_execute_file') -RequiredTools @('ctx_execute_file')
$i = $r.Cap.integration
Assert-True '8. plugin correct, no stdio binary needed, healthy -> active' ($i.integration_mode -eq 'plugin' -and $i.components.plugin -eq $true -and $i.components.mcp -eq $false -and $i.runtime_present -eq $true -and $r.Cap.state.active -eq $true) "status=$($i.status) runtime=$($i.runtime_present)"
Assert-True '8. in-process hooks recognised' ($i.components.hooks -eq 'in_process_plugin') $i.components.hooks
Assert-True '8. OpenCode plugin hooks are runtime-healthy' ($i.components.hooks_loaded -eq $true) "hooks_loaded=$($i.components.hooks_loaded)"
$fx = New-Fixture
$null = Write-Fx $fx.Home '.config/opencode/opencode.jsonc' "// global`n{ `"plugin`": [`"context-mode@1.0.169`"] }"
$r = Invoke-Cm $fx 'opencode'
Assert-True '8. global jsonc plugin with version suffix and comment detected' ($r.Cap.integration.components.plugin -eq $true) "plugin=$($r.Cap.integration.components.plugin)"

$fx = New-Fixture
$null = Write-Fx $fx.Root 'opencode.json' '{ "mcp": { "context-mode": { "type": "local", "command": ["npx","-y","context-mode"] } } }'
$r = Invoke-Cm $fx 'opencode' -WithBinary $true
$i = $r.Cap.integration
Assert-True '9. legacy MCP without plugin -> legacy_mcp, degraded, not active' ($i.integration_mode -eq 'legacy_mcp' -and $r.Cap.state.degraded -eq $true -and $r.Cap.state.active -eq $false) "mode=$($i.integration_mode)"
Assert-True '9. legacy hint recommends plugin path' (($i.guidance -join ' ') -match 'plugin') ($i.guidance -join '|')
$fx = New-Fixture
$null = Write-Fx $fx.Root 'opencode.json' '{ "mcp": { "context-mode": { "type": "local", "enabled": false } } }'
$r = Invoke-Cm $fx 'opencode' -WithBinary $true
Assert-True '9. disabled legacy MCP entry is ignored' ($r.Cap.integration.components.mcp -eq $false) 'disabled entry counted'

$fx = New-Fixture
$ocPath = Write-Fx $fx.Root 'opencode.json' '{ "plugin": ["context-mode"], "mcp": { "context-mode": { "type": "local", "command": ["npx","-y","context-mode"] }, "other": { "type": "local" } } }'
$before = (Get-FileHash $ocPath).Hash
$r = Invoke-Cm $fx 'opencode' -Health 'healthy' -WithBinary $true
$i = $r.Cap.integration
Assert-True '10. plugin + legacy MCP -> misconfigured' ($i.status -eq 'misconfigured' -and $i.components.legacy_mcp_conflict -eq $true) "status=$($i.status)"
Assert-True '10. reported degraded, never usable/active' ($r.Cap.state.degraded -eq $true -and $i.usable -eq $false -and $r.Cap.state.active -eq $false) 'conflict must not be usable'
Assert-True '10. conflict explained and repair hint given' ((($i.findings -join ' ') -match 'ZERO ctx_\* tools') -and (($i.guidance -join ' ') -match 'mcp\.context-mode')) (($i.findings + $i.guidance) -join '|')
Assert-True '10. opencode.json left untouched' ((Get-FileHash $ocPath).Hash -eq $before) 'config modified'
Assert-True '10. resolver exit 0, fallback non-blocking' ($r.Code -eq 0 -and $i.fallback.blocks_mxagile -eq $false) 'blocked'
# conflict split across project and global scope
$fx = New-Fixture
$null = Write-Fx $fx.Root 'opencode.json' '{ "plugin": ["context-mode"] }'
$null = Write-Fx $fx.Home '.config/opencode/opencode.json' '{ "mcp": { "context-mode": { "type": "local" } } }'
$r = Invoke-Cm $fx 'opencode'
Assert-True '10. conflict across project/global scopes detected' ($r.Cap.integration.status -eq 'misconfigured') "status=$($r.Cap.integration.status)"
# unparseable config
$fx = New-Fixture
$null = Write-Fx $fx.Root 'opencode.json' '{ this is not json'
$r = Invoke-Cm $fx 'opencode'
Assert-True '9. unparseable opencode.json is reported, not guessed' (($r.Code -eq 0) -and (($r.Cap.integration.findings -join ' ') -match 'Unparseable') -and $r.Cap.integration.configured -eq $false) 'unparseable handling'
$fx = New-Fixture
$null = Write-Fx $fx.Home '.claude/settings.json' '{ "enabledPlugins": { "context-mode@context-mode": true } }'
$r = Invoke-Cm $fx 'opencode'
Assert-True '8. Claude plugin config is NOT treated as OpenCode integration' ($r.Cap.integration.configured -eq $false) 'cross-harness leak'

# --- 12. Unknown / unsupported harness ------------------------------------------------------
Write-Host "--- 12 unknown / unsupported harness ---" -ForegroundColor Yellow
$fx = New-Fixture
$r = Invoke-Cm $fx 'auto' -WithBinary $true -Health 'healthy'
Assert-True '12. unknown harness: not usable, not active even with binary + healthy claim' ($r.Cap.integration.status -eq 'harness_unknown' -and $r.Cap.integration.usable -eq $false -and $r.Cap.state.active -eq $false) "status=$($r.Cap.integration.status)"
Assert-True '12. unknown harness: degraded when enabled (unverifiable)' ($r.Cap.state.degraded -eq $true) 'expected degraded'
$r = Invoke-Cm $fx 'other'
Assert-True '12. unsupported harness: unavailable, fallback non-blocking' ($r.Cap.integration.status -eq 'harness_unsupported' -and $r.Cap.state.unavailable -eq $true -and $r.Cap.integration.fallback.blocks_mxagile -eq $false -and $r.Code -eq 0) "status=$($r.Cap.integration.status)"
$env:MXAGILE_HARNESS = 'opencode'
try {
    $null = Write-Fx $fx.Root 'opencode.json' '{ "plugin": ["context-mode"] }'
    $out = & $Resolver -Format json -ProjectRoot $fx.Root -HomeDir $fx.Home 2>&1 | ConvertFrom-Json
    $c = $out.capabilities | Where-Object { $_.id -eq 'context_mode_integration' }
    Assert-True '12. auto detection via MXAGILE_HARNESS' ($c.integration.harness -eq 'opencode') "harness=$($c.integration.harness)"
} finally { Remove-Item Env:\MXAGILE_HARNESS -ErrorAction SilentlyContinue }

# --- 13. No side effects ----------------------------------------------------------------------------
Write-Host "--- 13 no side effects ---" -ForegroundColor Yellow
$fx = New-Fixture
$null = Write-Fx $fx.Root 'opencode.json' '{ "plugin": ["context-mode"] }'
$null = Invoke-Cm $fx 'opencode' -Health 'healthy'
$created = @(Get-ChildItem $fx.Home -Recurse -File -ErrorAction SilentlyContinue)
Assert-True '13. resolver writes nothing to the user home' ($created.Count -eq 0) "files: $(($created | ForEach-Object { $_.FullName }) -join ', ')"
Assert-True '13. resolver writes no .concord state without -UpdateDiscoveryState' (-not (Test-Path (Join-Path $fx.Root '.concord'))) '.concord created'
$resolverText = Get-Content $Resolver -Raw
Assert-True '13. resolver contains no install/package-manager invocations' ($resolverText -notmatch '(?m)^\s*(&\s*)?(npm|npx|winget|brew)\s+(install|i)\b' -and $resolverText -notmatch 'Set-Content\s+-Path\s+\$mcp') 'install command found'

# --- 13b. context-mode is never executed (it can start the MCP server and stall) ---------------
Write-Host "--- 13b never executes context-mode ---" -ForegroundColor Yellow
$probeBin = New-TempDir
$marker = Join-Path $probeBin 'executed.marker'
Set-Content -Path (Join-Path $probeBin 'context-mode.cmd') -Value "@echo executed> `"$marker`"`r`n@echo 1.0.169" -Encoding ASCII
$null = Write-Fx $probeBin 'node_modules/context-mode/package.json' '{ "name": "context-mode", "version": "1.0.10" }'
$fx = New-Fixture
$env:PATH = $probeBin
try {
    $out = & $Resolver -Format json -ProjectRoot $fx.Root -HomeDir $fx.Home -Harness claude_code 2>&1 | ConvertFrom-Json
} finally { $env:PATH = $OriginalPath }
$c = $out.capabilities | Where-Object { $_.id -eq 'context_mode_integration' }
Assert-True '13b. context-mode binary was not executed' (-not (Test-Path $marker)) 'resolver executed context-mode'
Assert-True '13b. version read from package metadata, incompatible version flagged' (($c.dependencies[0].detected_version -eq '1.0.10') -and ($c.dependencies[0].compatible -eq $false)) "version=$($c.dependencies[0].detected_version)"

# --- 14. Human output ------------------------------------------------------------------------------------
Write-Host "--- 14 human output ---" -ForegroundColor Yellow
$fx = New-Fixture
$null = Write-Fx $fx.Root 'opencode.json' '{ "plugin": ["context-mode"], "mcp": { "context-mode": { "type": "local" } } }'
$env:PATH = $BinWithout
try {
    $human = & $Resolver -Format human -ProjectRoot $fx.Root -HomeDir $fx.Home -Harness opencode -Capability context_mode_integration *>&1 | Out-String
} finally { $env:PATH = $OriginalPath }
Assert-True '14. human output shows harness, finding and fallback' (($human -match 'Harness: opencode') -and ($human -match 'Finding:') -and ($human -match 'Fallback: native MxAgile')) $human

} finally {
    $env:PATH = $OriginalPath
    foreach ($t in $TempRoots) { Remove-Item -Recurse -Force $t -ErrorAction SilentlyContinue }
}

Write-Host ""
Write-Host "=== Results ===" -ForegroundColor Cyan
Write-Host "  Passed: $PassCount" -ForegroundColor Green
Write-Host "  Failed: $FailCount" -ForegroundColor $(if ($FailCount -gt 0) { 'Red' } else { 'Green' })
if ($FailCount -gt 0) { $FailDetails | ForEach-Object { Write-Host $_ -ForegroundColor Red }; exit 1 }
exit 0
