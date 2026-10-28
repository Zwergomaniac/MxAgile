<#
.SYNOPSIS
    MxAgile Capability Resolver — authoritative source for Framework capability state.

.DESCRIPTION
    Combines Framework version, capability registry, project configuration, and
    environment detection to produce a resolved capability inventory.

    Both human diagnostics and AI-facing discovery consume this resolver.
    Do not independently reimplement capability logic for humans or agents.

    Capability state model:
      SUPPORTED   — Framework knows how to use the capability
      AVAILABLE   — Required environment/dependency detected and compatible
      ENABLED     — Project configuration allows use
      ACTIVE      — Capability is actually in use in the current context
      DEGRADED    — Operating partially or via fallback
      UNAVAILABLE — Environment/dependency absent or incompatible

.PARAMETER Format
    Output format. 'human' (default) prints concise status. 'json' returns
    machine-readable structured result for agent consumption.

.PARAMETER Capability
    Optional. Resolve a single capability by id (e.g., 'rtk_optimization').
    Returns full detail for that capability.

.PARAMETER ProjectRoot
    Optional. Project root directory. Defaults to the repository root containing
    the .mxagile directory.

.PARAMETER CheckUpgrades
    When present, compare current Framework version against the last-seen version
    stored in .concord/capability-discovery.yaml and report new capabilities.

.PARAMETER UpdateDiscoveryState
    When present, write the current Framework version to .concord/capability-discovery.yaml
    so upgrade-awareness comparisons work on the next invocation.

.PARAMETER Harness
    Harness for the optional Context Mode integration check: auto (default),
    claude_code, copilot_cli, vscode_copilot, opencode, other.
    auto = MXAGILE_HARNESS env, CLAUDECODE=1, OPENCODE_SESSION_ID/OPENCODE_BASE_URL;
    otherwise the harness stays unknown (never guessed from files).

.PARAMETER ContextModeHealth
    Health evidence observed by the agent in the current session (one bounded,
    cached ctx_doctor/ctx_stats call): unknown (default), healthy, failed, timeout.
    The resolver never calls MCP tools itself; without evidence health is unknown.

.PARAMETER HomeDir
    User home used to read global harness configuration (read-only). Defaults to
    the current user profile. Mainly for tests.

.EXAMPLE
    # Human-readable summary
    scripts/Get-MxAgileCapabilities.ps1

.EXAMPLE
    # Machine-readable JSON for agent consumption
    scripts/Get-MxAgileCapabilities.ps1 -Format json

.EXAMPLE
    # Single capability detail
    scripts/Get-MxAgileCapabilities.ps1 -Capability rtk_optimization

.EXAMPLE
    # Check what's new since last seen version
    scripts/Get-MxAgileCapabilities.ps1 -CheckUpgrades -UpdateDiscoveryState

.NOTES
    Part of MxAgile 1.5 — Context Optimization & Capability Discovery.
    Policy: .mxagile/capabilities.yaml
    Authority: scripts/Get-MxAgileCapabilities.ps1 (this file)
#>
[CmdletBinding()]
param(
    [ValidateSet('human', 'json')]
    [string]$Format = 'human',

    [string]$Capability = '',

    [string]$ProjectRoot = '',

    [switch]$CheckUpgrades,

    [switch]$UpdateDiscoveryState,

    [ValidateSet('auto', 'claude_code', 'copilot_cli', 'vscode_copilot', 'opencode', 'other')]
    [string]$Harness = 'auto',

    [ValidateSet('unknown', 'healthy', 'failed', 'timeout')]
    [string]$ContextModeHealth = 'unknown',

    [string]$HomeDir = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# ---------------------------------------------------------------------------
# Resolve project root
# ---------------------------------------------------------------------------
if (-not $ProjectRoot) {
    $scriptDir = $PSScriptRoot
    $ProjectRoot = Split-Path -Parent $scriptDir
    # Distributed copy lives in <project>/.mxagile/tools/
    if ((Split-Path -Leaf $scriptDir) -eq 'tools' -and (Split-Path -Leaf $ProjectRoot) -eq '.mxagile') {
        $ProjectRoot = Split-Path -Parent $ProjectRoot
    }
}

$mxagileDir = Join-Path $ProjectRoot '.mxagile'
if (-not (Test-Path $mxagileDir)) {
    Write-Error "Not an MxAgile project: .mxagile directory not found at '$ProjectRoot'"
    exit 1
}

# ---------------------------------------------------------------------------
# Load framework version
# ---------------------------------------------------------------------------
$versionFile = Join-Path $mxagileDir 'version.yaml'
$frameworkVersion = 'unknown'
$versionChanges = @{}
if (Test-Path $versionFile) {
    $versionLines = Get-Content $versionFile
    foreach ($line in $versionLines) {
        if ($line -match '^version:\s*"?([^"]+)"?') {
            $frameworkVersion = $Matches[1].Trim()
        }
    }
    # Parse changes block for upgrade awareness
    $currentVersion = ''
    foreach ($line in $versionLines) {
        if ($line -match '^\s+"?(\d+\.\d+)"?:\s*$') {
            $currentVersion = $Matches[1]
            $versionChanges[$currentVersion] = @()
        } elseif ($currentVersion -and $line -match '^\s+-\s+"(.+)"') {
            $versionChanges[$currentVersion] += $Matches[1]
        }
    }
}

# ---------------------------------------------------------------------------
# Load capabilities registry
# ---------------------------------------------------------------------------
$capRegistryFile = Join-Path $mxagileDir 'capabilities.yaml'
if (-not (Test-Path $capRegistryFile)) {
    Write-Error "Capability registry not found: $capRegistryFile"
    exit 1
}

# Parse capabilities from YAML manually (PS5.1 compatible, no module dependency)
function Read-CapabilitiesYaml {
    param([string]$FilePath)
    $caps = @()
    $lines = Get-Content $FilePath
    $inCapability = $false
    $currentCap = $null
    $inExternalDeps = $false
    $inRequires = $false

    foreach ($line in $lines) {
        # Start of a capability block
        if ($line -match '^  - id:\s*(.+)$') {
            if ($currentCap) { $caps += $currentCap }
            $currentCap = @{
                id = $Matches[1].Trim()
                name = ''
                description = ''
                category = ''
                version_introduced = ''
                default_state = 'off'
                config_key = ''
                external_dependencies = @()
                requires = @()
                risk = 'low'
                agent_may_recommend = $false
                agent_may_activate_config = $false
                user_approval_required = $false
                docs_ref = ''
                notes = ''
            }
            $inCapability = $true
            $inExternalDeps = $false
            $inRequires = $false
            continue
        }
        if (-not $currentCap) { continue }

        if ($line -match '^\s+name:\s*"?(.+?)"?\s*$') { $currentCap.name = $Matches[1].Trim('"') }
        elseif ($line -match '^\s+description:\s*"?(.+?)"?\s*$') { $currentCap.description = $Matches[1].Trim('"') }
        elseif ($line -match '^\s+category:\s*(.+)$') { $currentCap.category = $Matches[1].Trim() }
        elseif ($line -match '^\s+version_introduced:\s*"?(.+?)"?\s*$') { $currentCap.version_introduced = $Matches[1].Trim('"') }
        elseif ($line -match '^\s+default_state:\s*"?(.+?)"?\s*$') { $currentCap.default_state = $Matches[1].Trim('"') }
        elseif ($line -match '^\s+config_key:\s*"?(.+?)"?\s*$') { $currentCap.config_key = $Matches[1].Trim('"') }
        elseif ($line -match '^\s+risk:\s*(.+)$') { $currentCap.risk = $Matches[1].Trim() }
        elseif ($line -match '^\s+docs_ref:\s*"?(.+?)"?\s*$') { $currentCap.docs_ref = $Matches[1].Trim('"') }
        elseif ($line -match '^\s+agent_may_recommend:\s*(true|false)') { $currentCap.agent_may_recommend = ($Matches[1] -eq 'true') }
        elseif ($line -match '^\s+agent_may_activate_config:\s*(true|false)') { $currentCap.agent_may_activate_config = ($Matches[1] -eq 'true') }
        elseif ($line -match '^\s+user_approval_required:\s*(true|false)') { $currentCap.user_approval_required = ($Matches[1] -eq 'true') }
        elseif ($line -match '^\s+notes:\s*"?(.+?)"?\s*$') { $currentCap.notes = $Matches[1].Trim('"') }
        elseif ($line -match '^\s+requires:\s*\[([^\]]*)\]') {
            $reqs = $Matches[1] -split ',' | ForEach-Object { $_.Trim().Trim('"').Trim("'") } | Where-Object { $_ }
            $currentCap.requires = $reqs
        }
        elseif ($line -match '^\s+external_dependencies:$') {
            $inExternalDeps = $true
            $inRequires = $false
        }
        elseif ($inExternalDeps -and $line -match '^\s+- id:\s*(.+)$') {
            $currentCap.external_dependencies += @{ id = $Matches[1].Trim(); executable = ''; minimum_version = ''; license = '' }
        }
        elseif ($inExternalDeps -and $currentCap.external_dependencies.Count -gt 0) {
            $lastDep = $currentCap.external_dependencies[-1]
            if ($line -match '^\s+executable:\s*(.+)$') { $lastDep.executable = $Matches[1].Trim() }
            elseif ($line -match '^\s+version_constraint:\s*"?(.+?)"?\s*$') { $lastDep.minimum_version = $Matches[1].Trim('"').TrimStart('>=') }
            elseif ($line -match '^\s+license:\s*"?(.+?)"?\s*$') { $lastDep.license = $Matches[1].Trim('"') }
            elseif ($line -match '^\s+display_name:\s*"?(.+?)"?\s*$') { $lastDep.display_name = $Matches[1].Trim('"') }
        }
    }
    if ($currentCap) { $caps += $currentCap }
    return $caps
}

$allCapabilities = Read-CapabilitiesYaml -FilePath $capRegistryFile

# ---------------------------------------------------------------------------
# Load project configuration
# ---------------------------------------------------------------------------
function Get-ConfigValue {
    param([string[]]$Lines, [string]$KeyPath)
    $keys = $KeyPath -split '\.'
    $depth = 0
    $currentDepth = 0
    $inBlock = $false
    $targetKey = $keys[$depth]

    foreach ($line in $Lines) {
        if ($line -match '^\s*#') { continue }
        $indent = ($line -replace '^(\s*).*$', '$1').Length

        if ($depth -eq $keys.Count - 1) {
            if ($line -match "^\s{$($indent)}$([regex]::Escape($targetKey)):\s*(.+)$") {
                $val = $Matches[1].Trim()
                if ($val -eq 'true') { return $true }
                if ($val -eq 'false') { return $false }
                return $val.Trim('"')
            }
        } else {
            if ($line -match "^\s*$([regex]::Escape($targetKey)):") {
                $depth++
                $targetKey = $keys[$depth]
            }
        }
    }
    return $null
}

$configFile = Join-Path $mxagileDir 'config.yaml'
$configLines = @()
if (Test-Path $configFile) {
    $configLines = Get-Content $configFile
}

function Get-ProjectConfigBool {
    param([string]$KeyPath, [bool]$Default = $false)
    $val = Get-ConfigValue -Lines $configLines -KeyPath $KeyPath
    if ($null -eq $val) { return $Default }
    return [bool]$val
}

# ---------------------------------------------------------------------------
# External dependency detection
# ---------------------------------------------------------------------------
function Resolve-ExternalDep {
    param([hashtable]$Dep)
    $result = @{
        id = $Dep.id
        display_name = if ($Dep.display_name) { $Dep.display_name } else { $Dep.id }
        detected = $false
        detected_version = ''
        compatible = $false
        minimum_version = $Dep.minimum_version
        license = $Dep.license
        reason = ''
    }

    if (-not $Dep.executable) {
        $result.detected = $true
        $result.compatible = $true
        $result.reason = 'No executable required'
        return $result
    }

    $cmd = Get-Command $Dep.executable -ErrorAction SilentlyContinue
    if (-not $cmd) {
        $result.reason = "$($Dep.executable) not found in PATH"
        return $result
    }

    $result.detected = $true
    try {
        if ($Dep.id -eq 'context_mode') {
            # Never execute context-mode: without args/with --version it can start the MCP server and
            # stall (CONNECT_TIMEOUT). Read the version from the installed package metadata instead.
            $pkg = Join-Path (Split-Path -Parent $cmd.Source) 'node_modules/context-mode/package.json'
            $pkgJson = Read-JsonLenient (Get-FileTextSafe $pkg)
            $verOutput = if ($pkgJson -and $pkgJson.PSObject.Properties['version']) { [string]$pkgJson.version } else { '' }
        } else {
            $verOutput = & $Dep.executable --version 2>&1 | Select-Object -First 1
        }
        if ($verOutput -match '(\d+\.\d+\.\d+)') {
            $result.detected_version = $Matches[1]
        } elseif ($verOutput -match '(\d+\.\d+)') {
            $result.detected_version = $Matches[1]
        }
    } catch {
        $result.detected_version = 'unknown'
    }

    if (-not $Dep.minimum_version -or -not $result.detected_version -or $result.detected_version -eq 'unknown') {
        $result.compatible = $true
        $result.reason = if ($result.detected_version) { "Version $($result.detected_version) detected (compatibility not verified)" } else { 'Detected; version unreadable' }
        return $result
    }

    try {
        $detected = [Version]($result.detected_version -replace '[^0-9\.]', '' -replace '\.{2,}', '.')
        $minimum  = [Version]($Dep.minimum_version -replace '[^0-9\.]', '' -replace '\.{2,}', '.')
        $result.compatible = ($detected -ge $minimum)
        if ($result.compatible) {
            $result.reason = "Version $($result.detected_version) >= $($Dep.minimum_version)"
        } else {
            $result.reason = "Version $($result.detected_version) is below minimum $($Dep.minimum_version)"
        }
    } catch {
        $result.compatible = $true
        $result.reason = "Version $($result.detected_version) detected (parse error on comparison)"
    }

    return $result
}

# ---------------------------------------------------------------------------
# Context Mode harness integration (read-only; never installs or edits config)
# Detection lives here; per-harness guidance lives in .mxagile/adapters/*/context-mode*.yaml
# ---------------------------------------------------------------------------
if (-not $HomeDir) { $HomeDir = if ($HOME) { $HOME } else { [Environment]::GetFolderPath('UserProfile') } }

$ContextModeAdapterFiles = @{
    claude_code    = 'adapters/claude/context-mode.yaml'
    copilot_cli    = 'adapters/copilot/context-mode-cli.yaml'
    vscode_copilot = 'adapters/copilot/context-mode-vscode.yaml'
    opencode       = 'adapters/opencode/context-mode.yaml'
}

function Get-FileTextSafe {
    param([string]$Path)
    if ($Path -and (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return (Get-Content -LiteralPath $Path -Raw -ErrorAction SilentlyContinue)
    }
    return ''
}

function Get-AdapterScalar {
    param([string]$Path, [string]$Key)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return '' }
    foreach ($line in (Get-Content -LiteralPath $Path)) {
        if ($line -match "^$([regex]::Escape($Key)):\s*`"(.*)`"\s*$") { return ($Matches[1] -replace '\\"', '"') }
    }
    return ''
}

function Read-JsonLenient {
    # Returns $null when unparseable. Only whole-line // comments are tolerated.
    param([string]$Text)
    if (-not $Text -or -not $Text.Trim()) { return $null }
    try { return ($Text | ConvertFrom-Json -ErrorAction Stop) } catch { }
    try {
        $clean = (($Text -split "`r?`n") | Where-Object { $_ -notmatch '^\s*//' }) -join "`n"
        return ($clean | ConvertFrom-Json -ErrorAction Stop)
    } catch { return $null }
}

function Resolve-HarnessId {
    param([string]$Requested)
    if ($Requested -ne 'auto') { return $Requested }
    $envH = [Environment]::GetEnvironmentVariable('MXAGILE_HARNESS')
    if ($envH -in @('claude_code', 'copilot_cli', 'vscode_copilot', 'opencode')) { return $envH }
    if ($envH -eq 'claude') { return 'claude_code' }
    if ([Environment]::GetEnvironmentVariable('CLAUDECODE') -eq '1') { return 'claude_code' }
    if ([Environment]::GetEnvironmentVariable('OPENCODE_SESSION_ID') -or [Environment]::GetEnvironmentVariable('OPENCODE_BASE_URL')) { return 'opencode' }
    return 'unknown'
}

function New-ContextModeDetection {
    return [ordered]@{
        mode = 'none'; configured = $false; misconfigured = $false
        plugin = $false; mcp = $false; hooks = 'absent'; conflict = ''
        runtime_present = $false; evidence = @(); findings = @()
    }
}

function Test-ContextModeBinary {
    return [bool](Get-Command 'context-mode' -ErrorAction SilentlyContinue)
}

function Test-ContextModeLauncher {
    return ((Test-ContextModeBinary) -or [bool](Get-Command 'npx' -ErrorAction SilentlyContinue))
}

function Get-ClaudeContextModeDetection {
    param([string]$Root, [string]$Home_)
    $d = New-ContextModeDetection
    $cached = $false
    foreach ($f in @((Join-Path $Home_ '.claude/settings.json'), (Join-Path $Root '.claude/settings.json'), (Join-Path $Root '.claude/settings.local.json'))) {
        if ((Get-FileTextSafe $f) -match '"context-mode@[^"]+"\s*:\s*true') { $d.plugin = $true; $d.evidence += $f }
    }
    if ((Get-FileTextSafe (Join-Path $Home_ '.claude/plugins/installed_plugins.json')) -match 'context-mode@') { $cached = $true }
    foreach ($f in @((Join-Path $Root '.mcp.json'), (Join-Path $Home_ '.claude.json'))) {
        if ((Get-FileTextSafe $f) -match '"context-mode"\s*:\s*\{') { $d.mcp = $true; $d.evidence += $f }
    }
    if ($d.plugin) { $d.mode = 'plugin'; $d.hooks = 'bundled_with_plugin' }
    elseif ($d.mcp) {
        $d.mode = 'mcp_only'
        $d.findings += 'MCP-only: tools available, but no hooks/routing enforcement (plugin not enabled).'
    }
    $d.configured = ($d.plugin -or $d.mcp)
    $d.runtime_present = ($d.plugin -or $cached -or (Test-ContextModeBinary) -or ($d.mcp -and (Test-ContextModeLauncher)))
    if ($cached -and -not $d.plugin) { $d.findings += 'Plugin is present in the plugin cache but not enabled in settings.' }
    return $d
}

function Get-CopilotCliContextModeDetection {
    param([string]$Home_)
    $d = New-ContextModeDetection
    $cHome = [Environment]::GetEnvironmentVariable('COPILOT_HOME')
    if (-not $cHome) { $cHome = Join-Path $Home_ '.copilot' }
    $mcpFile = Join-Path $cHome 'mcp-config.json'
    $hookFile = Join-Path $cHome 'hooks/context-mode.json'
    if ((Get-FileTextSafe $mcpFile) -match '"context-mode"') { $d.mcp = $true; $d.evidence += $mcpFile }
    $hookText = Get-FileTextSafe $hookFile
    $hooksPresent = $hookText -match 'context-mode hook copilot-cli'
    if ($hooksPresent) {
        $d.evidence += $hookFile
        $missing = @('preToolUse', 'postToolUse', 'sessionStart') | Where-Object { $hookText -notmatch "`"$_`"" }
        $d.hooks = if ($missing) { 'incomplete' } else { 'present' }
        if ($missing) { $d.findings += "Hooks file lacks events: $($missing -join ', ')." }
    }
    if (Test-Path -LiteralPath $cHome -PathType Container) {
        $pluginDir = Get-ChildItem -LiteralPath $cHome -Directory -Recurse -Depth 3 -Filter '*context-mode*' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($pluginDir) { $d.plugin = $true; $d.evidence += $pluginDir.FullName; if ($d.hooks -eq 'absent') { $d.hooks = 'bundled_with_plugin' } }
    }
    if ($d.hooks -in @('present', 'incomplete') -and -not $d.mcp -and -not $d.plugin) {
        $d.misconfigured = $true
        $d.findings += 'Hooks installed but no MCP server registered: hooks are inert and no ctx_* tools exist.'
    } elseif ($d.plugin) { $d.mode = 'plugin' }
    elseif ($d.mcp) {
        $d.mode = 'manual'
        if ($d.hooks -eq 'absent') { $d.findings += 'MCP registered without hooks: tools available, no routing enforcement.' }
    }
    $d.configured = (-not $d.misconfigured) -and ($d.mcp -or $d.plugin)
    $d.runtime_present = (Test-ContextModeBinary) -or $d.plugin
    return $d
}

function Get-VsCodeCopilotContextModeDetection {
    param([string]$Root)
    $d = New-ContextModeDetection
    $mcpFile = Join-Path $Root '.vscode/mcp.json'
    $hookFile = Join-Path $Root '.github/hooks/context-mode.json'
    if ((Get-FileTextSafe $mcpFile) -match '"context-mode"\s*:\s*\{') { $d.mcp = $true; $d.evidence += $mcpFile }
    $hookText = Get-FileTextSafe $hookFile
    if ($hookText -match 'context-mode hook vscode-copilot') {
        $d.evidence += $hookFile
        $missing = @('PreToolUse', 'PostToolUse', 'SessionStart') | Where-Object { $hookText -notmatch "`"$_`"" }
        $d.hooks = if ($missing) { 'incomplete' } else { 'present' }
        if ($missing) { $d.findings += "Hooks file lacks events: $($missing -join ', ')." }
    }
    if ($d.hooks -ne 'absent' -and -not $d.mcp) {
        $d.misconfigured = $true
        $d.findings += '.github/hooks/context-mode.json exists but .vscode/mcp.json has no context-mode server: no ctx_* tools.'
    } elseif ($d.mcp) {
        $d.mode = 'project_files'
        if ($d.hooks -eq 'absent') { $d.findings += 'MCP registered without hooks: tools available, no routing enforcement.' }
    }
    $d.configured = (-not $d.misconfigured) -and $d.mcp
    $d.runtime_present = (Test-ContextModeBinary)
    return $d
}

function Get-OpenCodeContextModeDetection {
    param([string]$Root, [string]$Home_)
    $d = New-ContextModeDetection
    $legacy = $false
    foreach ($f in @((Join-Path $Root 'opencode.json'), (Join-Path $Root 'opencode.jsonc'),
                     (Join-Path $Home_ '.config/opencode/opencode.json'), (Join-Path $Home_ '.config/opencode/opencode.jsonc'))) {
        $text = Get-FileTextSafe $f
        if (-not $text) { continue }
        $json = Read-JsonLenient $text
        if ($null -eq $json) { $d.findings += "Unparseable OpenCode config (not evaluated): $f"; continue }
        $d.evidence += $f
        $pl = $json.PSObject.Properties['plugin']
        if ($pl) {
            foreach ($p in @($pl.Value)) { if ("$p" -match '^context-mode(@.*)?$') { $d.plugin = $true } }
        }
        $mc = $json.PSObject.Properties['mcp']
        if ($mc -and $mc.Value -and $mc.Value.PSObject.Properties['context-mode']) {
            $entry = $mc.Value.PSObject.Properties['context-mode'].Value
            $disabled = ($entry -and $entry.PSObject.Properties['enabled'] -and $entry.enabled -eq $false)
            if (-not $disabled) { $legacy = $true }
        }
    }
    $d.mcp = $legacy
    if ($d.plugin -and $legacy) {
        $d.mode = 'plugin'; $d.misconfigured = $true; $d.conflict = 'plugin_and_legacy_mcp'
        $d.findings += 'Upstream: plugin ["context-mode"] together with mcp.context-mode registers ZERO ctx_* tools. Remove the legacy mcp entry (not done automatically).'
    } elseif ($d.plugin) {
        $d.mode = 'plugin'; $d.hooks = 'in_process_plugin'; $d.configured = $true
    } elseif ($legacy) {
        $d.mode = 'legacy_mcp'; $d.configured = $true
        $d.findings += 'Legacy mcp.context-mode only: upstream integration is the native plugin; hooks/routing absent.'
    }
    $d.runtime_present = ($d.plugin -or (Test-ContextModeBinary) -or ($legacy -and (Test-ContextModeLauncher)))
    return $d
}

function Resolve-ContextModeIntegration {
    param([string]$Root, [string]$Home_, [string]$HarnessRequested, [string]$Health, [string]$AdapterBase)

    $harnessId = Resolve-HarnessId -Requested $HarnessRequested
    $fallback = [ordered]@{
        blocks_mxagile = $false
        order = @('deterministic_helpers', 'bounded_semantic_delegation', 'targeted_direct_read')
        full_repository_read = $false
    }
    $r = [ordered]@{
        harness = $harnessId
        platform_supported = ($ContextModeAdapterFiles.ContainsKey($harnessId))
        runtime_present = $false
        integration_mode = 'none'
        configured = $false
        components = [ordered]@{ plugin = $false; mcp = $false; hooks = 'absent'; legacy_mcp_conflict = $false }
        health = $Health
        health_source = if ($Health -eq 'unknown') { 'none' } else { 'agent_observed_session_probe' }
        usable = $false
        status = 'harness_unknown'
        setup_needed = $false
        reason = ''
        findings = @()
        evidence = @()
        guidance = @()
        automatic_action = 'none'
        fallback = $fallback
        upstream_ref = ''
    }

    if ($harnessId -eq 'unknown') {
        $r.runtime_present = (Test-ContextModeBinary)
        $r.reason = 'Harness not identified (set -Harness or MXAGILE_HARNESS); integration cannot be verified, so Context Mode is not treated as usable.'
        $r.guidance = @('Identify the harness (claude_code | copilot_cli | vscode_copilot | opencode) to get setup guidance.')
        return $r
    }
    if (-not $r.platform_supported) {
        $r.status = 'harness_unsupported'
        $r.reason = "Harness '$harnessId' has no MxAgile Context Mode adapter; native MxAgile fallback applies."
        return $r
    }

    $adapter = Join-Path $AdapterBase $ContextModeAdapterFiles[$harnessId]
    $r.upstream_ref = Get-AdapterScalar $adapter 'upstream_ref'

    $d = switch ($harnessId) {
        'claude_code'    { Get-ClaudeContextModeDetection -Root $Root -Home_ $Home_ }
        'copilot_cli'    { Get-CopilotCliContextModeDetection -Home_ $Home_ }
        'vscode_copilot' { Get-VsCodeCopilotContextModeDetection -Root $Root }
        'opencode'       { Get-OpenCodeContextModeDetection -Root $Root -Home_ $Home_ }
    }
    $r.runtime_present = $d.runtime_present
    $r.integration_mode = $d.mode
    $r.configured = $d.configured
    $r.components = [ordered]@{ plugin = $d.plugin; mcp = $d.mcp; hooks = $d.hooks; legacy_mcp_conflict = ($d.conflict -ne '') }
    $r.findings = @($d.findings)
    $r.evidence = @($d.evidence)

    $setupGuidance = {
        $g = @()
        $p = Get-AdapterScalar $adapter 'setup_project'; if ($p) { $g += "Project: $p" }
        $gl = Get-AdapterScalar $adapter 'setup_global'; if ($gl) { $g += "Global: $gl" }
        $v = Get-AdapterScalar $adapter 'verify'; if ($v) { $g += "Verify: $v" }
        $g
    }

    if ($d.misconfigured) {
        $r.status = 'misconfigured'
        $r.setup_needed = $true
        $r.reason = "Context Mode is misconfigured for $harnessId" + $(if ($d.conflict) { " ($($d.conflict))" } else { '' }) + '; treated as degraded, not usable. No config was changed.'
        $r.guidance = @(Get-AdapterScalar $adapter 'repair_hint')
    } elseif ($d.configured) {
        switch ($Health) {
            'healthy' { $r.status = 'healthy'; $r.usable = $true; $r.reason = 'Configured for this harness and health probe succeeded in this session.' }
            'unknown' { $r.status = 'configured_health_unknown'; $r.reason = 'Configured for this harness, but no health evidence in this session (ctx_doctor not observed). Not treated as usable.'
                        $r.guidance = @("Health probe: $(Get-AdapterScalar $adapter 'health_probe')") }
            default   { $r.status = 'configured_unhealthy'; $r.reason = "Configured for this harness, but health probe reported '$Health'; native MxAgile fallback applies."
                        $r.guidance = @(Get-AdapterScalar $adapter 'health_hint') }
        }
        if ($d.mode -eq 'legacy_mcp') {
            $r.guidance += @(Get-AdapterScalar $adapter 'legacy_hint')
        }
    } elseif ($Health -eq 'healthy') {
        $r.status = 'healthy'; $r.usable = $true; $r.runtime_present = $true
        $r.reason = 'ctx_* tools observed healthy in this session (integration form not detectable from files).'
    } elseif ($d.runtime_present) {
        $r.status = 'installed_not_configured'; $r.setup_needed = $true
        $r.reason = "Context Mode is installed but not configured for $harnessId."
        $r.guidance = @(& $setupGuidance)
    } else {
        $r.status = 'not_installed'; $r.setup_needed = $true
        $r.reason = "Context Mode is supported for $harnessId but not set up. Native MxAgile fallback applies."
        $r.guidance = @(& $setupGuidance)
    }
    $r.guidance = @($r.guidance | Where-Object { $_ })
    return $r
}

# ---------------------------------------------------------------------------
# Resolve a single capability
# ---------------------------------------------------------------------------
function Resolve-Capability {
    param([hashtable]$Cap, [hashtable]$AllResolved)

    $resolved = @{
        id = $Cap.id
        name = $Cap.name
        description = $Cap.description
        category = $Cap.category
        version_introduced = $Cap.version_introduced
        config_key = $Cap.config_key
        risk = $Cap.risk
        docs_ref = $Cap.docs_ref
        agent_may_recommend = $Cap.agent_may_recommend
        agent_may_activate_config = $Cap.agent_may_activate_config
        user_approval_required = $Cap.user_approval_required
        notes = $Cap.notes

        supported = $true
        available = $true
        enabled = $false
        active = $false
        degraded = $false
        unavailable = $false
        state_reason = ''
        dependency_results = @()
        integration = $null
    }

    # Check requirements
    foreach ($reqId in $Cap.requires) {
        if ($AllResolved.ContainsKey($reqId)) {
            $req = $AllResolved[$reqId]
            if (-not $req.enabled) {
                $resolved.enabled = $false
                $resolved.active = $false
                $resolved.state_reason = "Required capability '$reqId' is not enabled"
                return $resolved
            }
        }
    }

    # Check external dependencies
    $depResults = @()
    $allDepsOk = $true
    $anyDepDegraded = $false
    foreach ($dep in $Cap.external_dependencies) {
        $depResult = Resolve-ExternalDep -Dep $dep
        $depResults += $depResult
        if (-not $depResult.detected) {
            $allDepsOk = $false
        } elseif (-not $depResult.compatible) {
            $anyDepDegraded = $true
        }
    }
    $resolved.dependency_results = $depResults

    if (-not $allDepsOk) {
        $resolved.available = $false
        $resolved.unavailable = $true
        $missingDep = ($depResults | Where-Object { -not $_.detected } | Select-Object -First 1)
        $resolved.state_reason = if ($missingDep) { $missingDep.reason } else { 'External dependency not detected' }
    } elseif ($anyDepDegraded) {
        $resolved.available = $true
        $resolved.degraded = $true
        $badDep = ($depResults | Where-Object { $_.detected -and -not $_.compatible } | Select-Object -First 1)
        $resolved.state_reason = if ($badDep) { "Dependency version incompatible: $($badDep.reason)" } else { 'Dependency version incompatible' }
    } else {
        $resolved.available = $true
    }

    # Check config
    $configEnabled = Get-ProjectConfigBool -KeyPath $Cap.config_key -Default ($Cap.default_state -eq 'on')
    $resolved.enabled = $configEnabled

    # Context Mode: harness-specific integration evidence replaces the bare executable check.
    # available = a runtime for this harness exists; it does NOT mean usable (see integration.usable).
    if ($Cap.id -eq 'context_mode_integration') {
        $int = Resolve-ContextModeIntegration -Root $ProjectRoot -Home_ $HomeDir -HarnessRequested $Harness -Health $ContextModeHealth -AdapterBase $mxagileDir
        $resolved.integration = $int
        $versionDegraded = $resolved.degraded
        switch ($int.status) {
            { $_ -in @('not_installed', 'harness_unsupported') } {
                $resolved.available = $false; $resolved.unavailable = $true; $resolved.degraded = $false
            }
            { $_ -in @('misconfigured', 'configured_health_unknown', 'configured_unhealthy') } {
                $resolved.available = $true; $resolved.unavailable = $false; $resolved.degraded = $true
            }
            'harness_unknown' {
                $resolved.available = $int.runtime_present; $resolved.unavailable = (-not $int.runtime_present)
                $resolved.degraded = ($configEnabled -and $int.runtime_present)
            }
            default {
                $resolved.available = $true; $resolved.unavailable = $false; $resolved.degraded = $false
            }
        }
        if ($versionDegraded -and $int.status -eq 'healthy') { $resolved.degraded = $true }
        $resolved.state_reason = $int.reason
        if (-not $configEnabled) { $resolved.state_reason += ' Not enabled in project configuration.' }
    }

    # Active = available AND enabled AND not unavailable (and, for integrations, verified usable)
    if ($resolved.available -and $resolved.enabled -and -not $resolved.unavailable) {
        $resolved.active = ($null -eq $resolved.integration) -or $resolved.integration.usable
        if ($resolved.degraded) {
            $resolved.active = $false  # degraded dep means DEGRADED, not ACTIVE
        }
    }

    # Resolve state_reason if not already set
    if (-not $resolved.state_reason) {
        if ($resolved.active) {
            $resolved.state_reason = 'Active'
        } elseif ($resolved.degraded) {
            $resolved.state_reason = 'Dependency version mismatch — operating in fallback'
        } elseif ($resolved.unavailable) {
            # already set above
        } elseif (-not $resolved.enabled) {
            if ($resolved.available) {
                $resolved.state_reason = 'Available but not enabled in project configuration'
            } else {
                $resolved.state_reason = 'Not enabled'
            }
        } else {
            $resolved.state_reason = 'Enabled but dependency unavailable'
        }
    }

    return $resolved
}

# ---------------------------------------------------------------------------
# Resolve all capabilities
# ---------------------------------------------------------------------------
$allResolved = [ordered]@{}
foreach ($cap in $allCapabilities) {
    $r = Resolve-Capability -Cap $cap -AllResolved $allResolved
    $allResolved[$cap.id] = $r
}

# Filter if single capability requested
if ($Capability) {
    if (-not $allResolved.Contains($Capability)) {
        Write-Error "Unknown capability: '$Capability'. Known IDs: $($allResolved.Keys -join ', ')"
        exit 1
    }
    $targetResolved = @{ $Capability = $allResolved[$Capability] }
} else {
    $targetResolved = $allResolved
}

# ---------------------------------------------------------------------------
# Upgrade awareness
# ---------------------------------------------------------------------------
$newCapabilities = @()
$discoveryStateFile = Join-Path (Join-Path $ProjectRoot '.concord') 'capability-discovery.yaml'
$lastSeenVersion = $null

if ($CheckUpgrades -or $UpdateDiscoveryState) {
    if (Test-Path $discoveryStateFile) {
        $dsLines = Get-Content $discoveryStateFile
        foreach ($line in $dsLines) {
            if ($line -match '^last_seen_framework_version:\s*"?(.+?)"?\s*$') {
                $lastSeenVersion = $Matches[1].Trim('"')
            }
        }
    }

    if ($CheckUpgrades -and $lastSeenVersion -and $lastSeenVersion -ne $frameworkVersion) {
        foreach ($cap in $allCapabilities) {
            $capVerStr = $cap.version_introduced
            # If capability was introduced after lastSeenVersion, it is new
            try {
                $capVer  = [Version]$capVerStr
                $lastVer = [Version]$lastSeenVersion
                if ($capVer -gt $lastVer) {
                    $newCapabilities += $cap
                }
            } catch { }
        }
    }

    if ($UpdateDiscoveryState) {
        $concordDir = Join-Path $ProjectRoot '.concord'
        if (-not (Test-Path $concordDir)) {
            New-Item -ItemType Directory -Path $concordDir -Force | Out-Null
        }
        $ts = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssZ')
        $dsContent = @"
# MxAgile Capability Discovery State
# Written by: scripts/Get-MxAgileCapabilities.ps1
# Do NOT commit this file (.concord/ is gitignored).
last_seen_framework_version: "$frameworkVersion"
updated: "$ts"
"@
        Set-Content -Path $discoveryStateFile -Value $dsContent -Encoding UTF8
    }
}

# ---------------------------------------------------------------------------
# Output — JSON format
# ---------------------------------------------------------------------------
if ($Format -eq 'json') {
    $output = [ordered]@{
        framework_version   = $frameworkVersion
        resolved_at         = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssZ')
        project_root        = $ProjectRoot
        capabilities        = @()
        upgrade_awareness   = @{
            last_seen_version = $lastSeenVersion
            new_capabilities  = @($newCapabilities | ForEach-Object { $_.id })
        }
    }
    foreach ($key in $targetResolved.Keys) {
        $r = $targetResolved[$key]
        $depSummary = @($r.dependency_results | ForEach-Object {
            [ordered]@{
                id               = $_.id
                display_name     = $_.display_name
                detected         = $_.detected
                detected_version = $_.detected_version
                compatible       = $_.compatible
                reason           = $_.reason
            }
        })
        $output.capabilities += [ordered]@{
            id                       = $r.id
            name                     = $r.name
            description              = $r.description
            category                 = $r.category
            version_introduced       = $r.version_introduced
            config_key               = $r.config_key
            state = [ordered]@{
                supported            = $r.supported
                available            = $r.available
                enabled              = $r.enabled
                active               = $r.active
                degraded             = $r.degraded
                unavailable          = $r.unavailable
                reason               = $r.state_reason
            }
            risk                     = $r.risk
            agent_may_recommend      = $r.agent_may_recommend
            agent_may_activate_config = $r.agent_may_activate_config
            user_approval_required   = $r.user_approval_required
            dependencies             = $depSummary
            integration              = $r.integration
            docs_ref                 = $r.docs_ref
            notes                    = $r.notes
        }
    }
    $output | ConvertTo-Json -Depth 10
    exit 0
}

# ---------------------------------------------------------------------------
# Output — Human format
# ---------------------------------------------------------------------------
function Get-StateIndicator {
    param([hashtable]$R)
    if ($R.active) { return '[ACTIVE]' }
    if ($R.degraded) { return '[DEGRADED]' }
    if ($R.unavailable) { return '[UNAVAILABLE]' }
    if ($R.enabled -and $R.available) { return '[ENABLED]' }
    if ($R.available -and -not $R.enabled) { return '[AVAILABLE — not enabled]' }
    return '[SUPPORTED — not configured]'
}

Write-Host ""
Write-Host "MxAgile $frameworkVersion - Capability Status" -ForegroundColor Cyan
Write-Host "Project: $ProjectRoot" -ForegroundColor DarkGray
Write-Host ""

$lastCategory = ''
foreach ($key in $targetResolved.Keys) {
    $r = $targetResolved[$key]
    if ($r.category -ne $lastCategory) {
        Write-Host "  [$($r.category.ToUpper())]" -ForegroundColor DarkYellow
        $lastCategory = $r.category
    }

    $indicator = Get-StateIndicator -R $r
    $color = switch ($true) {
        $r.active     { 'Green' }
        $r.degraded   { 'Yellow' }
        $r.unavailable { 'DarkRed' }
        $r.enabled    { 'Cyan' }
        default       { 'Gray' }
    }
    Write-Host "  $($r.name)" -ForegroundColor White
    Write-Host "    Status:  $indicator" -ForegroundColor $color
    Write-Host "    Reason:  $($r.state_reason)" -ForegroundColor DarkGray

    foreach ($dep in $r.dependency_results) {
        if ($dep.detected) {
            $depColor = if ($dep.compatible) { 'DarkGray' } else { 'Yellow' }
            Write-Host "    Dep:     $($dep.display_name) - $($dep.detected_version) ($($dep.reason))" -ForegroundColor $depColor
        } else {
            Write-Host "    Dep:     $($dep.display_name) - NOT DETECTED ($($dep.reason))" -ForegroundColor DarkRed
        }
    }
    if ($r.integration) {
        $i = $r.integration
        Write-Host "    Harness: $($i.harness) | mode=$($i.integration_mode) | configured=$($i.configured) | health=$($i.health) | usable=$($i.usable) [$($i.status)]" -ForegroundColor DarkGray
        foreach ($f in $i.findings) { Write-Host "    Finding: $f" -ForegroundColor Yellow }
        foreach ($g in $i.guidance) { Write-Host "    Setup:   $g" -ForegroundColor DarkGray }
        if (-not $i.usable) { Write-Host "    Fallback: native MxAgile (deterministic helpers -> bounded delegation -> targeted direct read)" -ForegroundColor DarkGray }
    }
    Write-Host ""
}

# Upgrade awareness summary
if ($CheckUpgrades -and $newCapabilities.Count -gt 0) {
    Write-Host "  Upgrade: New in MxAgile $frameworkVersion (since $lastSeenVersion):" -ForegroundColor Cyan
    foreach ($nc in $newCapabilities) {
        Write-Host "    + $($nc.name) [$($nc.id)]" -ForegroundColor Green
    }
    Write-Host ""
}

Write-Host "  Run with -Format json for machine-readable output." -ForegroundColor DarkGray
Write-Host "  Run with -Capability <id> for detail on a single capability." -ForegroundColor DarkGray
Write-Host "  Docs: docs/capabilities.md" -ForegroundColor DarkGray
Write-Host ""
