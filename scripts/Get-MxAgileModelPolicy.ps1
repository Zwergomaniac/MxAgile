<#
.SYNOPSIS
    Resolves model-aware context policy through a deterministic hierarchy.

.DESCRIPTION
    Separates three concerns:
      A. MODEL CAPABILITY — physical context-window size, model identity
      B. MXAGILE WORKING-CONTEXT POLICY — effective budget, pressure thresholds
      C. OBSERVED CONTEXT STATE — current tokens, measurement source

    Resolution hierarchy (highest priority first):
      1. Reliable value from active harness/provider/gateway adapter
      2. Explicitly configured model profile (matched by ModelId)
      3. Explicitly configured generic fallback (where safe)
      4. UNKNOWN

    Never fabricates model identity, context-window size, token consumption,
    or pressure state. UNKNOWN remains UNKNOWN when data is unavailable.

    Does not hard-code a single model or physical window into generic
    lifecycle semantics. Model-specific policy is configurable without
    changing lifecycle code.

.PARAMETER ProjectRoot
    Absolute path to the project root.

.PARAMETER ModelId
    Model identifier supplied by harness (e.g. 'claude-opus-4-6').
    Optional. If omitted, falls back through the resolution hierarchy.

.PARAMETER HarnessContextWindow
    Physical context-window size in tokens supplied by harness.
    Overrides profile value when present.

.OUTPUTS
    PSCustomObject with:
      .Resolved         — boolean (true if at least context_window is known)
      .ModelId          — string or empty
      .ContextWindow    — integer or $null (UNKNOWN)
      .CapabilitySource — string: harness | profile | fallback | unknown
      .WorkingBudget    — integer or $null
      .PressureTokens   — integer or $null (threshold for PRESSURE)
      .RolloverRecommendedTokens — integer or $null
      .RolloverRequiredTokens    — integer or $null
      .SafetyReserve    — integer or $null
      .PolicySource     — string: config_absolute | profile_ratio | unconfigured
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$ProjectRoot,

    [string]$ModelId = "",

    [int]$HarnessContextWindow = 0
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)

# ---------------------------------------------------------------------------
# Load model profiles
# ---------------------------------------------------------------------------
$profilesPath = Join-Path $ProjectRoot ".mxagile\model-profiles.yaml"
$profilesContent = $null
if (Test-Path -LiteralPath $profilesPath) {
    $profilesContent = Get-Content -LiteralPath $profilesPath -Raw -Encoding UTF8
}

# ---------------------------------------------------------------------------
# Load config for absolute thresholds and policy overrides
# ---------------------------------------------------------------------------
$configPath = Join-Path $ProjectRoot ".mxagile\config.yaml"
$configContent = $null
if (Test-Path -LiteralPath $configPath) {
    $configContent = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8
}

# ---------------------------------------------------------------------------
# Helper: extract integer value from YAML content
# ---------------------------------------------------------------------------
function Get-YamlInt {
    param([string]$content, [string]$key)
    if ([string]::IsNullOrEmpty($content)) { return $null }
    if ($content -match "(?m)^\s+${key}:\s+(\d+)") { return [int]$Matches[1] }
    if ($content -match "(?m)^\s+${key}:\s+null") { return $null }
    return $null
}

function Get-YamlFloat {
    param([string]$content, [string]$key)
    if ([string]::IsNullOrEmpty($content)) { return $null }
    if ($content -match "(?m)^\s+${key}:\s+([\d.]+)") { return [double]$Matches[1] }
    if ($content -match "(?m)^\s+${key}:\s+null") { return $null }
    return $null
}

# ---------------------------------------------------------------------------
# Step 1: Resolve context window through hierarchy
# ---------------------------------------------------------------------------
$contextWindow    = $null
$capabilitySource = "unknown"

# Priority 1: harness-supplied value
if ($HarnessContextWindow -gt 0) {
    $contextWindow    = $HarnessContextWindow
    $capabilitySource = "harness"
}

# Priority 2: model profile lookup
if ($null -eq $contextWindow -and -not [string]::IsNullOrEmpty($ModelId) -and $null -ne $profilesContent) {
    # Look for the model block in profiles
    $escapedId = [regex]::Escape($ModelId)
    if ($profilesContent -match "(?m)^\s+${escapedId}:\s*\r?\n\s+context_window_tokens:\s+(\d+)") {
        $contextWindow    = [int]$Matches[1]
        $capabilitySource = "profile"
    }
}

# Priority 3: generic fallback
if ($null -eq $contextWindow -and $null -ne $profilesContent) {
    $fallbackVal = Get-YamlInt $profilesContent 'context_window_tokens'
    # Only use fallback section value (under "fallback:" header)
    if ($profilesContent -match '(?m)^fallback:\s*\r?\n\s+context_window_tokens:\s+(\d+)') {
        $contextWindow    = [int]$Matches[1]
        $capabilitySource = "fallback"
    }
}

# Priority 4: UNKNOWN (contextWindow stays $null)

# ---------------------------------------------------------------------------
# Step 2: Resolve working-context policy (thresholds)
# ---------------------------------------------------------------------------
$workingBudget              = $null
$pressureTokens             = $null
$rolloverRecommendedTokens  = $null
$rolloverRequiredTokens     = $null
$safetyReserve              = $null
$policySource               = "unconfigured"

# Check config.yaml for absolute thresholds first
if ($null -ne $configContent) {
    $cfgPressure  = Get-YamlInt $configContent 'pressure_tokens'
    $cfgRecTokens = Get-YamlInt $configContent 'rollover_recommended_tokens'
    $cfgReqTokens = Get-YamlInt $configContent 'rollover_required_tokens'

    if ($null -ne $cfgPressure -or $null -ne $cfgRecTokens -or $null -ne $cfgReqTokens) {
        $pressureTokens            = $cfgPressure
        $rolloverRecommendedTokens = $cfgRecTokens
        $rolloverRequiredTokens    = $cfgReqTokens
        $policySource              = "config_absolute"
    }
}

# If no absolute thresholds, try ratio-based policy from model-profiles.yaml
if ($policySource -eq "unconfigured" -and $null -ne $contextWindow -and $null -ne $profilesContent) {
    $budgetRatio  = Get-YamlFloat $profilesContent 'working_budget_ratio'
    $pressRatio   = Get-YamlFloat $profilesContent 'pressure_ratio'
    $recRatio     = Get-YamlFloat $profilesContent 'rollover_recommended_ratio'
    $reqRatio     = Get-YamlFloat $profilesContent 'rollover_required_ratio'
    $reserveAbs   = Get-YamlInt   $profilesContent 'safety_reserve_tokens'

    if ($null -ne $pressRatio -or $null -ne $recRatio -or $null -ne $reqRatio) {
        if ($null -ne $budgetRatio)  { $workingBudget              = [int]([math]::Floor($contextWindow * $budgetRatio)) }
        if ($null -ne $pressRatio)   { $pressureTokens             = [int]([math]::Floor($contextWindow * $pressRatio)) }
        if ($null -ne $recRatio)     { $rolloverRecommendedTokens  = [int]([math]::Floor($contextWindow * $recRatio)) }
        if ($null -ne $reqRatio)     { $rolloverRequiredTokens     = [int]([math]::Floor($contextWindow * $reqRatio)) }
        if ($null -ne $reserveAbs)   { $safetyReserve              = $reserveAbs }
        $policySource = "profile_ratio"
    }
}

# ---------------------------------------------------------------------------
# Step 3: Return resolved policy
# ---------------------------------------------------------------------------
$resolved = ($null -ne $contextWindow)

return [PSCustomObject]@{
    Resolved                   = $resolved
    ModelId                    = $ModelId
    ContextWindow              = $contextWindow
    CapabilitySource           = $capabilitySource
    WorkingBudget              = $workingBudget
    PressureTokens             = $pressureTokens
    RolloverRecommendedTokens  = $rolloverRecommendedTokens
    RolloverRequiredTokens     = $rolloverRequiredTokens
    SafetyReserve              = $safetyReserve
    PolicySource               = $policySource
}
