<#
.SYNOPSIS
    Resolves context transition capabilities for the current harness.

.DESCRIPTION
    Reads the appropriate harness transition adapter definition and returns
    a structured capability record for the current environment.

    Harness detection order:
      1. -HarnessId parameter (explicit override)
      2. MXAGILE_HARNESS environment variable
      3. Presence of .claude/settings.json → 'claude_code'
      4. OPENCODE_SESSION_ID or OPENCODE_BASE_URL env var → 'opencode'
      5. GH_TOKEN or GITHUB_TOKEN + gh binary present → 'copilot_cli'
      6. Fallback → 'generic'

    All unknown capability values remain UNKNOWN — never fabricated.
    Capability state uses: SUPPORTED/AVAILABLE/ENABLED/ACTIVE/DEGRADED/UNAVAILABLE/UNKNOWN

.PARAMETER ProjectRoot
    Absolute path to the project root.

.PARAMETER HarnessId
    Override harness detection. One of: opencode | claude_code | copilot_cli | generic

.PARAMETER OutputFormat
    'object' (default) | 'json' | 'human'

.OUTPUTS
    PSCustomObject with:
      .HarnessId                  — detected or overridden harness identifier
      .HarnessVersion             — harness version string or $null
      .AdapterPath                — path to the loaded adapter YAML or $null
      .TransitionSupported        — boolean: any autonomous transition possible
      .CompactCurrentSession      — capability state hashtable
      .FreshContext               — capability state hashtable
      .Hooks                      — hashtable of hook states
      .PreferredStrategy          — COMPACT_CURRENT_SESSION | FRESH_CONTEXT_EPOCH | EXTERNAL_ACTION_REQUIRED
      .AutonomousCompactionPossible — boolean: all conditions for autonomous compaction present
      .Reason                     — human-readable explanation
      .RawAdapter                 — raw parsed adapter data (hashtable)
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$ProjectRoot,

    [string]$HarnessId = "",

    [string]$OutputFormat = "object"
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)

# ---------------------------------------------------------------------------
# Harness detection
# ---------------------------------------------------------------------------
function Detect-Harness {
    param([string]$ProjectRoot)

    # Explicit env override
    $envHarness = [System.Environment]::GetEnvironmentVariable('MXAGILE_HARNESS')
    if (-not [string]::IsNullOrEmpty($envHarness)) { return $envHarness }

    # Claude Code: settings.json present
    $claudeSettings = Join-Path $ProjectRoot ".claude\settings.json"
    $globalClaudeSettings = Join-Path $env:USERPROFILE ".claude\settings.json"
    if ((Test-Path -LiteralPath $claudeSettings) -or (Test-Path -LiteralPath $globalClaudeSettings)) {
        return 'claude_code'
    }

    # OpenCode: session env vars
    if (-not [string]::IsNullOrEmpty([System.Environment]::GetEnvironmentVariable('OPENCODE_SESSION_ID')) -or
        -not [string]::IsNullOrEmpty([System.Environment]::GetEnvironmentVariable('OPENCODE_BASE_URL'))) {
        return 'opencode'
    }

    # Copilot CLI: gh binary + token
    $ghBinary = Get-Command gh -ErrorAction SilentlyContinue
    $ghToken   = [System.Environment]::GetEnvironmentVariable('GH_TOKEN')
    $githubToken = [System.Environment]::GetEnvironmentVariable('GITHUB_TOKEN')
    if ($null -ne $ghBinary -and (-not [string]::IsNullOrEmpty($ghToken) -or -not [string]::IsNullOrEmpty($githubToken))) {
        return 'copilot_cli'
    }

    return 'generic'
}

# ---------------------------------------------------------------------------
# Load adapter YAML (minimal parser — key: value only, no nested objects)
# ---------------------------------------------------------------------------
function Read-AdapterFile {
    param([string]$AdapterPath)

    if (-not (Test-Path -LiteralPath $AdapterPath)) { return $null }

    $raw = Get-Content -LiteralPath $AdapterPath -Raw -Encoding UTF8
    return $raw
}

# ---------------------------------------------------------------------------
# Adapter path resolution
# ---------------------------------------------------------------------------
function Resolve-AdapterPath {
    param([string]$ProjectRoot, [string]$HarnessId)

    $adapterDir = Join-Path $ProjectRoot ".mxagile\adapters"

    $dirMap = @{
        'opencode'   = 'opencode'
        'claude_code' = 'claude'
        'copilot_cli' = 'copilot'
        'generic'    = 'generic'
    }

    $subDir = if ($dirMap.ContainsKey($HarnessId)) { $dirMap[$HarnessId] } else { 'generic' }
    return Join-Path $adapterDir "$subDir\transition-adapter.yaml"
}

# ---------------------------------------------------------------------------
# Parse capability from raw YAML content
# ---------------------------------------------------------------------------
function Get-YamlBoolValue {
    param([string]$Content, [string]$Key)
    if ($Content -match "(?m)^\s*${Key}:\s*(true|false)") {
        return $Matches[1] -eq 'true'
    }
    return $null
}

function Get-YamlStringValue {
    param([string]$Content, [string]$Key)
    if ($Content -match "(?m)^\s*${Key}:\s*(.+)$") {
        $val = $Matches[1].Trim().Trim('"').Trim("'")
        if ($val -eq 'null') { return $null }
        return $val
    }
    return $null
}

function Get-YamlSectionContent {
    param([string]$Content, [string]$SectionName)

    $sectionPattern = "^([ \t]*)$([regex]::Escape($SectionName)):[ \t]*(?:#.*)?$"
    $sectionIndent = $null
    $sectionLines = [System.Collections.Generic.List[string]]::new()

    foreach ($line in ($Content -split '\r?\n')) {
        if ($null -eq $sectionIndent) {
            if ($line -match $sectionPattern) {
                $sectionIndent = $Matches[1].Length
            }
            continue
        }

        if ($line -match '^[ \t]*$') {
            $sectionLines.Add($line)
            continue
        }

        $lineIndent = [regex]::Match($line, '^[ \t]*').Length
        if ($lineIndent -le $sectionIndent) { break }
        $sectionLines.Add($line)
    }

    if ($null -eq $sectionIndent) { return $null }
    return ($sectionLines -join "`n")
}

function Get-YamlDirectBoolValue {
    param([string]$Content, [string]$Key)

    $sectionIndent = $null
    foreach ($line in ($Content -split '\r?\n')) {
        if ($line -match '^[ \t]*$') { continue }
        $sectionIndent = [regex]::Match($line, '^[ \t]*').Length
        break
    }

    if ($null -eq $sectionIndent) { return $null }
    $keyPattern = "(?m)^[ \t]{$sectionIndent}$([regex]::Escape($Key)):[ \t]*(true|false)[ \t]*(?:#.*)?$"
    if ($Content -match $keyPattern) {
        return $Matches[1] -eq 'true'
    }
    return $null
}

# ---------------------------------------------------------------------------
# Main resolution
# ---------------------------------------------------------------------------
$resolvedHarnessId = if (-not [string]::IsNullOrEmpty($HarnessId)) { $HarnessId } else { Detect-Harness -ProjectRoot $ProjectRoot }

$adapterPath = Resolve-AdapterPath -ProjectRoot $ProjectRoot -HarnessId $resolvedHarnessId
$adapterContent = Read-AdapterFile -AdapterPath $adapterPath

$adapterLoaded = ($null -ne $adapterContent)

# Parse key capabilities from adapter
$compactSupported           = if ($adapterLoaded) { Get-YamlBoolValue -Content $adapterContent -Key 'supported' } else { $false }
$automaticSupported         = if ($adapterLoaded) { Get-YamlBoolValue -Content $adapterContent -Key 'automatic_supported' } else { $false }
$programmaticSupported      = if ($adapterLoaded) { Get-YamlBoolValue -Content $adapterContent -Key 'programmatic_supported' } else { $false }
$completionObservable       = if ($adapterLoaded) { Get-YamlBoolValue -Content $adapterContent -Key 'completion_observable' } else { $false }
$idempotencySupported       = if ($adapterLoaded) { Get-YamlBoolValue -Content $adapterContent -Key 'idempotency_supported' } else { $false }
$freshContextSupported      = if ($adapterLoaded) { Get-YamlBoolValue -Content $adapterContent -Key 'supported' } else { $false }
$preCompactHook             = if ($adapterLoaded) { Get-YamlStringValue -Content $adapterContent -Key 'pre_compact' } else { 'UNKNOWN' }
$sessionStartHook           = if ($adapterLoaded) { Get-YamlStringValue -Content $adapterContent -Key 'session_start_after_compact' } else { 'UNKNOWN' }
$liveValidationStatus       = if ($adapterLoaded) { Get-YamlStringValue -Content $adapterContent -Key 'live_validation_status' } else { 'UNKNOWN' }

# Nulls default to false for boolean capabilities
if ($null -eq $compactSupported)       { $compactSupported = $false }
if ($null -eq $automaticSupported)     { $automaticSupported = $false }
if ($null -eq $programmaticSupported)  { $programmaticSupported = $false }
if ($null -eq $completionObservable)   { $completionObservable = $false }
if ($null -eq $idempotencySupported)   { $idempotencySupported = $false }
if ($null -eq $freshContextSupported)  { $freshContextSupported = $false }
if ($null -eq $preCompactHook)         { $preCompactHook = 'UNKNOWN' }
if ($null -eq $sessionStartHook)       { $sessionStartHook = 'UNKNOWN' }
if ($null -eq $liveValidationStatus)   { $liveValidationStatus = 'UNKNOWN' }

# Check config — is transition enabled?
$transitionEnabled = $false
$autonomousEnabled = $false
$configPath = Join-Path $ProjectRoot ".mxagile\config.yaml"
if (Test-Path -LiteralPath $configPath) {
    $cfgRaw = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8
    $lifecycleConfig = Get-YamlSectionContent -Content $cfgRaw -SectionName 'context_lifecycle'
    $transitionConfig = if ($null -ne $lifecycleConfig) {
        Get-YamlSectionContent -Content $lifecycleConfig -SectionName 'transition'
    } else {
        $null
    }
    $lifecycleEnabledFlag = if ($null -ne $lifecycleConfig) {
        Get-YamlDirectBoolValue -Content $lifecycleConfig -Key 'enabled'
    } else {
        $false
    }
    $transitionEnabledFlag = if ($null -ne $transitionConfig) {
        Get-YamlDirectBoolValue -Content $transitionConfig -Key 'enabled'
    } else {
        $false
    }
    $autonomousFlag = if ($null -ne $transitionConfig) {
        Get-YamlDirectBoolValue -Content $transitionConfig -Key 'autonomous'
    } else {
        $false
    }
    $transitionEnabled = ($lifecycleEnabledFlag -eq $true) -and ($transitionEnabledFlag -eq $true)
    $autonomousEnabled = ($lifecycleEnabledFlag -eq $true) -and ($transitionEnabledFlag -eq $true) -and ($autonomousFlag -eq $true)
}

# Select preferred strategy
$preferredStrategy = 'EXTERNAL_ACTION_REQUIRED'
$reason = "No autonomous transition supported."

if ($programmaticSupported -and $completionObservable) {
    $preferredStrategy = 'COMPACT_CURRENT_SESSION'
    $reason = "Programmatic compaction with observable completion supported."
} elseif ($automaticSupported -and ($preCompactHook -eq 'SUPPORTED')) {
    $preferredStrategy = 'COMPACT_CURRENT_SESSION'
    $reason = "Native auto-compaction with PreCompact hook integration available."
} elseif ($freshContextSupported) {
    $preferredStrategy = 'FRESH_CONTEXT_EPOCH'
    $reason = "Fresh context epoch available as transition strategy."
}

# Autonomous compaction possible? All conditions:
# 1. Programmatic trigger OR native auto with PreCompact hook
# 2. Completion observable (for programmatic) OR hook-based (for native auto)
# 3. Transition enabled in config
# 4. Autonomous enabled in config
$autonomousCompactionPossible = $false
if ($programmaticSupported -and $completionObservable -and $transitionEnabled -and $autonomousEnabled) {
    $autonomousCompactionPossible = $true
} elseif ($automaticSupported -and ($preCompactHook -eq 'SUPPORTED') -and $transitionEnabled) {
    # Native auto with PreCompact hook: autonomous in the sense that compaction
    # happens transparently and MxAgile hooks in via PreCompact/SessionStart
    $autonomousCompactionPossible = $true
}

# Transition capability summary
$transitionSupported = $compactSupported -or $freshContextSupported

$result = [PSCustomObject]@{
    HarnessId                  = $resolvedHarnessId
    HarnessVersion             = $null
    AdapterPath                = if ($adapterLoaded) { $adapterPath } else { $null }
    AdapterLoaded              = $adapterLoaded
    TransitionSupported        = $transitionSupported
    CompactCurrentSession      = @{
        Supported            = $compactSupported
        AutomaticSupported   = $automaticSupported
        ProgrammaticSupported = $programmaticSupported
        CompletionObservable = $completionObservable
        IdempotencySupported = $idempotencySupported
        LiveValidationStatus = $liveValidationStatus
    }
    FreshContext               = @{
        Supported = $freshContextSupported
    }
    Hooks                      = @{
        PreCompact              = $preCompactHook
        SessionStartAfterCompact = $sessionStartHook
    }
    TransitionEnabled          = $transitionEnabled
    AutonomousEnabled          = $autonomousEnabled
    PreferredStrategy          = $preferredStrategy
    AutonomousCompactionPossible = $autonomousCompactionPossible
    CompactionAutomatable      = $autonomousCompactionPossible
    Reason                     = $reason
    RawAdapter                 = $adapterContent
}

if ($OutputFormat -eq 'json') {
    return $result | ConvertTo-Json -Depth 5
} elseif ($OutputFormat -eq 'human') {
    Write-Host "Harness:              $resolvedHarnessId" -ForegroundColor Cyan
    Write-Host "Adapter loaded:       $adapterLoaded ($adapterPath)" -ForegroundColor $(if ($adapterLoaded) { 'Green' } else { 'Yellow' })
    Write-Host "Compact supported:    $compactSupported (auto: $automaticSupported, programmatic: $programmaticSupported)" -ForegroundColor $(if ($compactSupported) { 'Green' } else { 'Yellow' })
    Write-Host "Completion obs.:      $completionObservable" -ForegroundColor $(if ($completionObservable) { 'Green' } else { 'Yellow' })
    Write-Host "PreCompact hook:      $preCompactHook" -ForegroundColor $(if ($preCompactHook -eq 'SUPPORTED') { 'Green' } else { 'Yellow' })
    Write-Host "Preferred strategy:   $preferredStrategy" -ForegroundColor Cyan
    Write-Host "Autonomous possible:  $autonomousCompactionPossible" -ForegroundColor $(if ($autonomousCompactionPossible) { 'Green' } else { 'Yellow' })
    Write-Host "Reason:               $reason" -ForegroundColor Gray
    return $result
}

return $result
