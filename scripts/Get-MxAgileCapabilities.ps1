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
    auto = current-session MXAGILE_HARNESS attestation, CLAUDECODE=1, or
    OPENCODE_SESSION_ID/OPENCODE_BASE_URL. Contradictory evidence is ambiguous.
    A caller-supplied harness requires matching current-session evidence; otherwise it is ambiguous.

.PARAMETER ContextModeHealth
    Health evidence observed by the agent in the current session (one bounded,
    cached ctx_doctor/ctx_stats call): unknown (default), healthy, failed, timeout.
    The resolver never calls MCP tools itself; without evidence health is unknown.

.PARAMETER ContextModeToolsObserved
The agent inspected this session's actual tool namespace. This is separate from
configuration files and is never inferred by the resolver.

.PARAMETER ContextModeTools
Canonical ctx_* tool names observed in this session. Supply the complete current
Context Mode tool inventory when ContextModeToolsObserved is set.

.PARAMETER ContextModeRequiredTools
Context Mode operations required for the current task. Usability is not established
unless these operations are present in ContextModeTools.

.PARAMETER ContextModeHooksRequired
The current task requires automatic routing hooks, not only direct ctx_* operations.

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

    [ValidateSet('auto', 'claude_code', 'copilot_cli', 'vscode_copilot', 'opencode', 'codex', 'hermes', 'grok', 'concord', 'generic', 'other')]
    [string]$Harness = 'auto',

    [ValidateSet('', 'LIGHT', 'MID', 'HIGH')]
    [string]$ModelProfile = '',

    [ValidateSet('unknown', 'healthy', 'failed', 'timeout')]
    [string]$ContextModeHealth = 'unknown',

    [switch]$ContextModeToolsObserved,

    [string[]]$ContextModeTools = @(),

    [string[]]$ContextModeRequiredTools = @(),

    [switch]$ContextModeHooksRequired,

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
    $evidence = @()
    $envH = [Environment]::GetEnvironmentVariable('MXAGILE_HARNESS')
    if ($envH -in @('claude_code', 'copilot_cli', 'vscode_copilot', 'opencode', 'codex', 'hermes', 'grok', 'concord', 'generic', 'other')) {
        $evidence += [ordered]@{ id = $envH; source = 'MXAGILE_HARNESS' }
    } elseif ($envH -eq 'claude') {
        $evidence += [ordered]@{ id = 'claude_code'; source = 'MXAGILE_HARNESS' }
    }
    if ([Environment]::GetEnvironmentVariable('CLAUDECODE') -eq '1') {
        $evidence += [ordered]@{ id = 'claude_code'; source = 'CLAUDECODE' }
    }
    if ([Environment]::GetEnvironmentVariable('OPENCODE_SESSION_ID') -or [Environment]::GetEnvironmentVariable('OPENCODE_BASE_URL')) {
        $evidence += [ordered]@{ id = 'opencode'; source = 'OpenCode session environment' }
    }

    $detectedIds = @($evidence | ForEach-Object { $_.id } | Sort-Object -Unique)
    if ($detectedIds.Count -gt 1) {
        return [pscustomobject]@{
            id = 'unknown'; source = 'conflicting_runtime_evidence'; ambiguous = $true
            conflict = "Runtime markers identify different harnesses: $($detectedIds -join ', ')."
        }
    }
    if ($Requested -ne 'auto') {
        if ($detectedIds.Count -eq 0) {
            return [pscustomobject]@{
                id = 'unknown'; source = 'unattested_caller'; ambiguous = $true
                conflict = "Requested harness '$Requested' has no current-session runtime attestation."
            }
        }
        if ($detectedIds.Count -eq 1 -and $Requested -ne $detectedIds[0]) {
            return [pscustomobject]@{
                id = 'unknown'; source = 'caller_runtime_conflict'; ambiguous = $true
                conflict = "Requested harness '$Requested' conflicts with current-session evidence '$($detectedIds[0])'."
            }
        }
        return [pscustomobject]@{
            id = $Requested
            source = ($evidence | Select-Object -First 1).source
            ambiguous = $false
            conflict = ''
        }
    }
    if ($detectedIds.Count -eq 1) {
        return [pscustomobject]@{
            id = $detectedIds[0]; source = (($evidence | ForEach-Object source | Sort-Object -Unique) -join ', ')
            ambiguous = $false; conflict = ''
        }
    }
    return [pscustomobject]@{ id = 'unknown'; source = 'none'; ambiguous = $false; conflict = '' }
}

function Resolve-DelegationIntegration {
    param([string]$ProjectRoot_, $HarnessResolution, [string]$Profile, [bool]$Enabled)

    $result = [ordered]@{
        status = 'unknown'
        harness_id = $HarnessResolution.id
        harness_evidence = $HarnessResolution.source
        adapter = $null
        adapter_harness_id = $null
        named_agents = 'unknown'
        generic_fork = 'unknown'
        model_selection = 'unknown'
        max_concurrency = $null
        concurrency_notes = ''
        requested_profile = if ($Profile) { $Profile } else { $null }
        resolved_model = $null
        model_resolution = if ($Profile) { 'use_available_agent_model' } else { 'not_requested' }
        route_allowed = $false
        fallback = 'main_agent_or_context_mode'
        reason = ''
    }

    if ($HarnessResolution.ambiguous) {
        $result.reason = $HarnessResolution.conflict
        return $result
    }
    if ($HarnessResolution.id -eq 'unknown') {
        $result.reason = 'No current-session harness attestation; delegation support is UNKNOWN.'
        return $result
    }

    $adapterRelativePath = switch ($HarnessResolution.id) {
        'claude_code' { 'adapters/claude/agent-delegation.yaml' }
        'vscode_copilot' { 'adapters/copilot/agent-delegation-vscode.yaml' }
        'copilot_cli' { 'adapters/copilot/agent-delegation-cli.yaml' }
        default { "adapters/$($HarnessResolution.id)/agent-delegation.yaml" }
    }
    $adapterPath = Join-Path (Join-Path $ProjectRoot_ '.mxagile') $adapterRelativePath
    if (-not (Test-Path -LiteralPath $adapterPath -PathType Leaf)) {
        $result.reason = "No assessed delegation adapter for harness '$($HarnessResolution.id)'; support remains UNKNOWN."
        return $result
    }

    $adapterLines = Get-Content -LiteralPath $adapterPath
    $inDelegation = $false
    $inProfiles = $false
    $profileMappings = @{}
    foreach ($line in $adapterLines) {
        if ($line -match '^delegation:\s*$') { $inDelegation = $true; continue }
        if (-not $inDelegation) { continue }
        if ($line -match '^\S') { $inDelegation = $false; $inProfiles = $false; continue }
        if ($line -match '^  profiles:\s*$') { $inProfiles = $true; continue }
        if ($line -match '^  harness_id:\s*([a-z0-9_]+)\s*$') { $result.adapter_harness_id = $Matches[1] }
        elseif ($line -match '^  concurrency_notes:\s*(.*?)\s*$') { $result.concurrency_notes = $Matches[1].Trim('"').Trim("'") }
        if ($inProfiles -and $line -match '^    (LIGHT|MID|HIGH):\s*(.*?)\s*$') {
            $profileMappings[$Matches[1]] = $Matches[2].Trim().Trim('"').Trim("'")
            continue
        }
        if ($line -match '^  status:\s*(supported|unsupported|unknown)\s*$') { $result.status = $Matches[1] }
        elseif ($line -match '^  named_agents:\s*(supported|unsupported|unknown)\s*$') { $result.named_agents = $Matches[1] }
        elseif ($line -match '^  generic_fork:\s*(supported|unsupported|unknown)\s*$') { $result.generic_fork = $Matches[1] }
        elseif ($line -match '^  model_selection:\s*(supported|unsupported|unknown)\s*$') { $result.model_selection = $Matches[1] }
        elseif ($line -match '^  max_concurrency:\s*(\d+|null)\s*$') {
            if ($Matches[1] -ne 'null') { $result.max_concurrency = [int]$Matches[1] }
        }
    }
    $result.adapter = $adapterRelativePath
    if ($result.adapter_harness_id -ne $HarnessResolution.id) {
        $result.reason = "Adapter identity mismatch: expected '$($HarnessResolution.id)', received '$($result.adapter_harness_id)'; support remains UNKNOWN."
        return $result
    }
    if ($result.status -eq 'supported') {
        $result.route_allowed = $Enabled
        $result.reason = if ($Enabled) { 'Harness adapter explicitly supports bounded delegation.' } else { 'Delegation is disabled in project configuration.' }
    } elseif ($result.status -eq 'unsupported') {
        $result.reason = 'Harness adapter explicitly reports delegation unsupported; use the main-agent or Context Mode fallback.'
    } else {
        $result.reason = 'Harness adapter does not establish delegation support; use the main-agent or Context Mode fallback.'
    }

    if ($Profile) {
        if ($result.model_selection -eq 'supported' -and $profileMappings.ContainsKey($Profile) -and $profileMappings[$Profile] -and $profileMappings[$Profile] -ne 'null') {
            $result.resolved_model = $profileMappings[$Profile]
            $result.model_resolution = 'adapter_profile_mapping'
        } else {
            $result.model_resolution = 'use_available_agent_model'
        }
    }
    return $result
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
    param([string]$Root, [string]$Home_)
    $d = New-ContextModeDetection
    $cHome = [Environment]::GetEnvironmentVariable('COPILOT_HOME')
    if (-not $cHome) { $cHome = Join-Path $Home_ '.copilot' }
    $homeMcpFile = Join-Path $cHome 'mcp-config.json'
    if ((Get-FileTextSafe $homeMcpFile) -match '"context-mode"\s*:\s*\{') { $d.mcp = $true; $d.evidence += $homeMcpFile }
    $projectMcpFile = Join-Path $Root '.mcp.json'
    $projectMcpText = Get-FileTextSafe $projectMcpFile
    if (($projectMcpText -match '"context-mode"\s*:\s*\{') -and ($projectMcpText -match '"CONTEXT_MODE_PLATFORM"\s*:\s*"copilot-cli"')) {
        $d.mcp = $true
        $d.evidence += $projectMcpFile
    }

    $hookFiles = @((Join-Path $cHome 'hooks/context-mode.json'), (Join-Path $Root '.github/hooks/context-mode.json'))
    foreach ($hookFile in $hookFiles) {
        $hookText = Get-FileTextSafe $hookFile
        if ($hookText -notmatch 'context-mode hook copilot-cli') { continue }
        $d.evidence += $hookFile
        $missing = @('preToolUse', 'postToolUse', 'sessionStart', 'preCompact', 'userPromptSubmitted', 'agentStop') |
            Where-Object { $hookText -notmatch "`"$_`"" }
        $d.hooks = if ($missing) { 'incomplete' } else { 'present' }
        if ($missing) { $d.findings += "Hooks file lacks events: $($missing -join ', ')." }
        break
    }

    $pluginRoots = @()
    if (Test-Path -LiteralPath $cHome -PathType Container) {
        $pluginRoots += @(Get-ChildItem -LiteralPath $cHome -Directory -Recurse -Depth 4 -Filter '*context-mode*' -ErrorAction SilentlyContinue)
    }
    foreach ($pluginDir in $pluginRoots) {
        $manifest = Get-FileTextSafe (Join-Path $pluginDir.FullName '.github/plugin/plugin.json')
        if (-not $manifest) { $manifest = Get-FileTextSafe (Join-Path $pluginDir.FullName 'plugin.json') }
        if ($manifest -notmatch '"name"\s*:\s*"context-mode"') { continue }
        $d.plugin = $true
        $d.evidence += $pluginDir.FullName
        $pluginMcp = Join-Path $pluginDir.FullName '.mcp.json'
        $pluginHooks = Join-Path $pluginDir.FullName 'hooks.json'
        if (Test-Path -LiteralPath $pluginMcp -PathType Leaf) { $d.mcp = $true; $d.evidence += $pluginMcp }
        if ($d.hooks -eq 'absent' -and (Test-Path -LiteralPath $pluginHooks -PathType Leaf)) {
            $pluginHookText = Get-FileTextSafe $pluginHooks
            $missing = @('preToolUse', 'postToolUse', 'sessionStart', 'preCompact', 'userPromptSubmitted', 'agentStop') |
                Where-Object { $pluginHookText -notmatch "`"$_`"" }
            if ($missing) {
                $d.hooks = 'incomplete'
                $d.findings += "Plugin hooks file lacks events: $($missing -join ', ')."
            } else {
                $d.hooks = 'bundled_with_plugin'
            }
            $d.evidence += $pluginHooks
        }
        break
    }

    if ($d.hooks -eq 'incomplete') {
        $d.misconfigured = $true
        $d.findings += 'Context Mode hooks are incomplete for GitHub Copilot CLI.'
    } elseif ($d.hooks -eq 'present' -and -not $d.mcp -and -not $d.plugin) {
        $d.misconfigured = $true
        $d.findings += 'Hooks installed but no MCP server registered: hooks are inert and no ctx_* tools exist.'
    } elseif ($d.plugin) {
        $d.mode = 'plugin'
        if ($d.hooks -eq 'absent') {
            $d.misconfigured = $true
            $d.findings += 'Context Mode Copilot plugin is missing its bundled hooks.json.'
        }
    } elseif ($d.mcp) {
        $d.mode = 'manual'
        if ($d.hooks -eq 'absent') { $d.findings += 'MCP registered without hooks: tools available, no routing enforcement.' }
    }
    $d.configured = (-not $d.misconfigured) -and ($d.mcp -or $d.plugin)
    $d.runtime_present = (Test-ContextModeBinary)
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
        $missing = @('PreToolUse', 'PostToolUse', 'PreCompact', 'SessionStart') | Where-Object { $hookText -notmatch "`"$_`"" }
        $d.hooks = if ($missing) { 'incomplete' } else { 'present' }
        if ($missing) { $d.misconfigured = $true; $d.findings += "Hooks file lacks events: $($missing -join ', ')." }
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
    param(
        [string]$Root,
        [string]$Home_,
        [string]$HarnessRequested,
        [string]$Health,
        [bool]$ToolsObserved,
        [string[]]$SessionTools,
        [string[]]$RequiredTools,
        [bool]$HooksRequired,
        [bool]$Enabled,
        [string]$AdapterBase
    )

    $harnessEvidence = Resolve-HarnessId -Requested $HarnessRequested
    $harnessId = $harnessEvidence.id
    $observedTools = @()
    if ($ToolsObserved) {
        $observedTools = @($SessionTools | ForEach-Object { "$($_)".Trim() } |
            Where-Object { $_ -match '^ctx_[a-z0-9_]+$' } | Sort-Object -Unique)
    }
    $loadState = if (-not $ToolsObserved) { 'unknown' } elseif ($observedTools.Count -gt 0) { 'loaded' } else { 'not_loaded' }
    $missingRequiredTools = @($RequiredTools | Where-Object { $_ -notin $observedTools })
    $effectiveHealth = $Health
    $healthSource = 'none'
    $sessionFindings = @()
    if ($loadState -eq 'loaded' -and $Health -ne 'unknown' -and $observedTools -contains 'ctx_doctor') {
        $healthSource = 'agent_observed_session_probe'
    } elseif ($Health -ne 'unknown') {
        $effectiveHealth = 'unknown'
        $sessionFindings += 'Health evidence ignored: the current-session tool inventory does not include ctx_doctor.'
    }
    $fallback = [ordered]@{
        blocks_mxagile = $false
        order = @('deterministic_helpers', 'bounded_semantic_delegation', 'targeted_direct_read')
        full_repository_read = $false
    }
    $r = [ordered]@{
        harness = $harnessId
        harness_source = $harnessEvidence.source
        harness_conflict = $harnessEvidence.conflict
        platform_supported = ($ContextModeAdapterFiles.ContainsKey($harnessId))
        runtime_present = $false
        loaded = if ($loadState -eq 'unknown') { $null } else { $loadState -eq 'loaded' }
        load_state = $loadState
        load_source = if ($ToolsObserved) { 'agent_observed_tool_namespace' } else { 'none' }
        loaded_tools = $observedTools
        required_tools = @($RequiredTools)
        hooks_required = $HooksRequired
        missing_required_tools = $missingRequiredTools
        integration_mode = 'none'
        configured = $false
        components = [ordered]@{ plugin = $false; mcp = $false; hooks = 'unknown'; hooks_loaded = $null; legacy_mcp_conflict = $false }
        health = $effectiveHealth
        health_source = $healthSource
        usable = $false
        status = 'harness_unknown'
        setup_needed = $false
        reason = ''
        findings = @()
        evidence = @()
        guidance = @()
        automatic_action = 'none'
        action_classification = 'SAFE_AUTOMATIC'
        restart_required = $false
        fallback = $fallback
        upstream_ref = ''
    }

    if ($harnessId -eq 'unknown') {
        $r.runtime_present = (Test-ContextModeBinary) -or ($loadState -eq 'loaded')
        if ($harnessEvidence.ambiguous) {
            $r.status = 'harness_ambiguous'
            $r.reason = $harnessEvidence.conflict + ' Context Mode is not treated as usable; use the actual host harness, not a tool source or terminal origin.'
            $r.guidance = @('Do not retry with a guessed harness. Resolve the current session host identity; Concord discovery is not harness evidence.')
        } else {
            $r.reason = 'Current-session harness evidence is unavailable; integration cannot be verified, so Context Mode is not treated as usable.'
            $r.guidance = @('The host may attest claude_code, copilot_cli, vscode_copilot, or opencode for this session. Otherwise keep the harness unknown.')
        }
        $r.findings = @($sessionFindings)
        return $r
    }
    if (-not $r.platform_supported) {
        $r.status = 'harness_unsupported'
        $r.action_classification = 'UNSUPPORTED'
        $r.reason = "Harness '$harnessId' has no MxAgile Context Mode adapter; native MxAgile fallback applies."
        return $r
    }

    $adapter = Join-Path $AdapterBase $ContextModeAdapterFiles[$harnessId]
    $r.upstream_ref = Get-AdapterScalar $adapter 'upstream_ref'

    $d = switch ($harnessId) {
        'claude_code'    { Get-ClaudeContextModeDetection -Root $Root -Home_ $Home_ }
        'copilot_cli'    { Get-CopilotCliContextModeDetection -Root $Root -Home_ $Home_ }
        'vscode_copilot' { Get-VsCodeCopilotContextModeDetection -Root $Root }
        'opencode'       { Get-OpenCodeContextModeDetection -Root $Root -Home_ $Home_ }
    }
    $r.runtime_present = $d.runtime_present
    if ($loadState -eq 'loaded') { $r.runtime_present = $true }
    $r.integration_mode = $d.mode
    $r.configured = $d.configured
    $hooksConfigured = ($d.hooks -in @('present', 'bundled_with_plugin', 'in_process_plugin'))
    $hooksLoaded = if (-not $hooksConfigured) { $false } elseif ($loadState -eq 'loaded' -and $effectiveHealth -eq 'healthy') { $true } else { $null }
    $r.components = [ordered]@{ plugin = $d.plugin; mcp = $d.mcp; hooks = $d.hooks; hooks_loaded = $hooksLoaded; legacy_mcp_conflict = ($d.conflict -ne '') }
    $r.findings = @($d.findings) + @($sessionFindings)
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
        $r.action_classification = 'REQUIRES_USER_APPROVAL'
        $r.reason = "Context Mode is misconfigured for $harnessId" + $(if ($d.conflict) { " ($($d.conflict))" } else { '' }) + '; treated as degraded, not usable. No config was changed.'
        $r.guidance = @(Get-AdapterScalar $adapter 'repair_hint')
    } elseif ($d.configured) {
        if (-not $d.runtime_present -and $loadState -ne 'loaded') {
            $r.status = 'configured_runtime_missing'
            $r.setup_needed = $true
            $r.action_classification = 'REQUIRES_USER_APPROVAL'
            $r.reason = "Context Mode is configured for $harnessId, but its required runtime executable was not detected."
            $r.guidance = @(& $setupGuidance)
        } else { switch ($loadState) {
            'not_loaded' {
                $r.status = 'configured_not_loaded'
                $r.setup_needed = $true
                $r.reason = "Context Mode is configured for $harnessId, but no ctx_* tools are present in this session."
                $r.action_classification = 'REQUIRES_RESTART'
                $r.restart_required = $true
                if ($harnessId -eq 'claude_code' -and $d.mode -eq 'mcp_only' -and $HooksRequired) {
                    $r.action_classification = 'REQUIRES_USER_APPROVAL'
                    $r.guidance = @(Get-AdapterScalar $adapter 'hooks_required_hint')
                } elseif ($harnessId -eq 'claude_code' -and $d.mode -eq 'mcp_only') {
                    $r.guidance = @(Get-AdapterScalar $adapter 'mcp_only_load_hint')
                } else {
                    $r.guidance = @(Get-AdapterScalar $adapter 'load_hint')
                }
            }
            'unknown' {
                $r.status = 'configured_load_unknown'
                $r.reason = "Context Mode is configured for $harnessId, but current-session tool loading has not been observed. Configuration is not runtime evidence."
                $r.guidance = @(Get-AdapterScalar $adapter 'runtime_probe')
            }
            default {
                if (-not $hooksConfigured -and $HooksRequired) {
                    $r.status = 'loaded_hooks_missing'
                    $r.action_classification = 'REQUIRES_USER_APPROVAL'
                    $r.restart_required = $true
                    $r.reason = "Context Mode tools are loaded, but the $harnessId integration has no configured routing hooks; not usable."
                    if ($harnessId -eq 'claude_code' -and $d.mode -eq 'mcp_only') {
                        $r.guidance = @(Get-AdapterScalar $adapter 'hooks_required_hint')
                    } else {
                        $r.guidance = @(Get-AdapterScalar $adapter 'repair_hint')
                    }
                } else { switch ($effectiveHealth) {
                    'healthy' {
                        if (-not $Enabled) {
                            $r.status = 'healthy_but_disabled'
                            $r.reason = 'Context Mode tools and health are verified, but MxAgile configuration is disabled.'
                        } elseif (@($RequiredTools).Count -eq 0) {
                            $r.status = 'task_fit_unknown'
                            $r.reason = 'Context Mode is healthy, but no task-required operations were specified; task suitability is unverified.'
                        } elseif ($missingRequiredTools.Count -gt 0) {
                            $r.status = 'task_tools_missing'
                            $r.reason = "Context Mode is healthy, but required task tools are missing: $($missingRequiredTools -join ', ')."
                            $r.guidance = @(Get-AdapterScalar $adapter 'load_hint')
                        } else {
                            $r.status = 'healthy'
                            $r.usable = $true
                            $r.reason = 'Configured, loaded in this session, healthy, enabled, and all required task tools are present.'
                        }
                    }
                    'unknown' {
                        $r.status = 'loaded_health_unknown'
                        $r.reason = 'Context Mode tools are loaded in this session, but health is unknown (no successful health probe evidence).'
                        $r.guidance = @("Health probe: $(Get-AdapterScalar $adapter 'health_probe')")
                    }
                    default {
                        $r.status = 'loaded_unhealthy'
                        $r.reason = "Context Mode tools are loaded, but the health probe reported '$effectiveHealth'; native MxAgile fallback applies."
                        $r.guidance = @(Get-AdapterScalar $adapter 'health_hint')
                    }
                } }
            }
        } }
        if ($d.mode -eq 'legacy_mcp') {
            $r.guidance += @(Get-AdapterScalar $adapter 'legacy_hint')
        }
    } elseif ($loadState -eq 'loaded') {
        $r.status = 'loaded_unconfigured'
        $r.setup_needed = $true
        $r.reason = "ctx_* tools were observed in this session, but no supported $harnessId configuration was detected; configuration is unverified."
        $r.guidance = @(& $setupGuidance)
    } elseif ($d.runtime_present) {
        $r.status = 'installed_not_configured'; $r.setup_needed = $true
        $r.action_classification = 'REQUIRES_USER_APPROVAL'
        $r.reason = "Context Mode is installed but not configured for $harnessId."
        $r.guidance = @(& $setupGuidance)
    } else {
        $r.status = 'not_installed'; $r.setup_needed = $true
        $r.action_classification = 'REQUIRES_USER_APPROVAL'
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
        $int = Resolve-ContextModeIntegration -Root $ProjectRoot -Home_ $HomeDir -HarnessRequested $Harness `
            -Health $ContextModeHealth -ToolsObserved $ContextModeToolsObserved.IsPresent `
            -SessionTools $ContextModeTools -RequiredTools $ContextModeRequiredTools -HooksRequired $ContextModeHooksRequired.IsPresent `
            -Enabled $configEnabled -AdapterBase $mxagileDir
        $resolved.integration = $int
        $versionDegraded = $resolved.degraded
        switch ($int.status) {
            { $_ -in @('not_installed', 'harness_unsupported') } {
                $resolved.available = $false; $resolved.unavailable = $true; $resolved.degraded = $false
            }
            { $_ -in @('misconfigured', 'configured_runtime_missing', 'configured_load_unknown', 'configured_not_loaded', 'loaded_health_unknown', 'loaded_unhealthy', 'loaded_hooks_missing', 'loaded_unconfigured', 'task_tools_missing', 'task_fit_unknown', 'harness_ambiguous') } {
                $resolved.available = $int.runtime_present; $resolved.unavailable = (-not $int.runtime_present)
                $resolved.degraded = ($configEnabled -and $int.runtime_present)
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

    if ($Cap.id -eq 'subagent_spawn') {
        $harnessResolution = Resolve-HarnessId -Requested $Harness
        $delegation = Resolve-DelegationIntegration -ProjectRoot_ $ProjectRoot -HarnessResolution $harnessResolution `
            -Profile $ModelProfile -Enabled $configEnabled
        $resolved.integration = $delegation
        switch ($delegation.status) {
            'supported' { $resolved.available = $true; $resolved.unavailable = $false }
            'unsupported' { $resolved.available = $false; $resolved.unavailable = $true }
            default { $resolved.available = $false; $resolved.unavailable = $false }
        }
        $resolved.active = $false
        $resolved.state_reason = $delegation.reason
    }

    # Active = available AND enabled AND not unavailable (and, for integrations, verified usable)
    if ($Cap.id -ne 'subagent_spawn' -and $resolved.available -and $resolved.enabled -and -not $resolved.unavailable) {
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
        $loadLabel = if ($null -eq $i.loaded) { 'unknown' } elseif ($i.loaded) { 'loaded' } else { 'not_loaded' }
        $hooksLabel = if ($null -eq $i.components.hooks_loaded) { 'unknown' } elseif ($i.components.hooks_loaded) { 'loaded' } else { 'missing' }
        Write-Host "    Harness: $($i.harness) | mode=$($i.integration_mode) | configured=$($i.configured) | loaded=$loadLabel | hooks=$hooksLabel | health=$($i.health) | usable=$($i.usable) [$($i.status)]" -ForegroundColor DarkGray
        if ($i.required_tools.Count -gt 0) { Write-Host "    Required tools: $($i.required_tools -join ', ') | missing: $($i.missing_required_tools -join ', ')" -ForegroundColor DarkGray }
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
