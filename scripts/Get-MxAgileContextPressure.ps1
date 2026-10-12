<#
.SYNOPSIS
    Evaluates context pressure from external token measurements.

.DESCRIPTION
    Implements operational evaluation for context pressure states:
      UNKNOWN — no reliable measurement or no configured thresholds
      NORMAL — below pressure threshold
      PRESSURE — at or above pressure threshold, below rollover recommended
      ROLLOVER_RECOMMENDED — at or above recommended threshold
      ROLLOVER_REQUIRED — at or above required threshold

    Prefers ratio-based policy relative to effective context capability.
    Supports explicit absolute overrides from config.yaml.

    Does not fabricate local token counts. Accepts measurements only from
    external sources (harness, gateway, user-supplied).

    UNKNOWN remains UNKNOWN when:
      - No token measurement is available
      - No configured thresholds exist
      - Measurement source is 'unknown'
      - Context window is unknown AND no absolute thresholds configured

    NORMAL requires a real measurement AND valid policy thresholds.

.PARAMETER ProjectRoot
    Absolute path to the project root.

.PARAMETER EstimatedContextTokens
    Current context size in tokens from external source.
    Zero or negative = no measurement.

.PARAMETER TokenSource
    How the measurement was obtained:
    harness_reported | gateway_measurement | user_supplied | unknown

.PARAMETER ModelId
    Optional model identifier for profile-based threshold resolution.

.PARAMETER HarnessContextWindow
    Optional harness-supplied context window (overrides profile).

.OUTPUTS
    PSCustomObject with:
      .PressureState              — UNKNOWN | NORMAL | PRESSURE | ROLLOVER_RECOMMENDED | ROLLOVER_REQUIRED
      .EstimatedContextTokens     — integer or $null
      .TokenSource                — string
      .ContextWindow              — integer or $null
      .PressureTokens             — integer or $null (threshold used)
      .RolloverRecommendedTokens  — integer or $null
      .RolloverRequiredTokens     — integer or $null
      .ContextRatio               — double or $null (tokens / context_window)
      .Reason                     — human-readable explanation
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$ProjectRoot,

    [int]$EstimatedContextTokens = 0,

    [string]$TokenSource = "unknown",

    [string]$ModelId = "",

    [int]$HarnessContextWindow = 0
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)

# ---------------------------------------------------------------------------
# Resolve model policy for thresholds
# ---------------------------------------------------------------------------
$policyScript = Join-Path $PSScriptRoot "Get-MxAgileModelPolicy.ps1"

$policyArgs = @{ ProjectRoot = $ProjectRoot }
if (-not [string]::IsNullOrEmpty($ModelId)) { $policyArgs['ModelId'] = $ModelId }
if ($HarnessContextWindow -gt 0) { $policyArgs['HarnessContextWindow'] = $HarnessContextWindow }

$policy = $null
if (Test-Path -LiteralPath $policyScript) {
    $policy = & $policyScript @policyArgs
}

$contextWindow             = if ($null -ne $policy) { $policy.ContextWindow } else { $null }
$pressureTokens            = if ($null -ne $policy) { $policy.PressureTokens } else { $null }
$rolloverRecommendedTokens = if ($null -ne $policy) { $policy.RolloverRecommendedTokens } else { $null }
$rolloverRequiredTokens    = if ($null -ne $policy) { $policy.RolloverRequiredTokens } else { $null }

# ---------------------------------------------------------------------------
# Evaluate pressure
# ---------------------------------------------------------------------------
$pressureState = "UNKNOWN"
$reason        = ""
$contextRatio  = $null
$tokens        = if ($EstimatedContextTokens -gt 0) { $EstimatedContextTokens } else { $null }

# Gate 1: measurement availability
if ($null -eq $tokens -or $TokenSource -eq "unknown") {
    $pressureState = "UNKNOWN"
    $reason = "No reliable token measurement available."
}
# Gate 2: threshold availability
elseif ($null -eq $pressureTokens -and $null -eq $rolloverRecommendedTokens -and $null -eq $rolloverRequiredTokens) {
    $pressureState = "UNKNOWN"
    $reason = "Token measurement available ($tokens tokens, source: $TokenSource) but no pressure thresholds configured."
}
# Gate 3: evaluate against thresholds
else {
    if ($null -ne $contextWindow -and $contextWindow -gt 0) {
        $contextRatio = [math]::Round($tokens / $contextWindow, 4)
    }

    if ($null -ne $rolloverRequiredTokens -and $tokens -ge $rolloverRequiredTokens) {
        $pressureState = "ROLLOVER_REQUIRED"
        $reason = "Context tokens ($tokens) at or above ROLLOVER_REQUIRED threshold ($rolloverRequiredTokens)."
    }
    elseif ($null -ne $rolloverRecommendedTokens -and $tokens -ge $rolloverRecommendedTokens) {
        $pressureState = "ROLLOVER_RECOMMENDED"
        $reason = "Context tokens ($tokens) at or above ROLLOVER_RECOMMENDED threshold ($rolloverRecommendedTokens)."
    }
    elseif ($null -ne $pressureTokens -and $tokens -ge $pressureTokens) {
        $pressureState = "PRESSURE"
        $reason = "Context tokens ($tokens) at or above PRESSURE threshold ($pressureTokens)."
    }
    else {
        $pressureState = "NORMAL"
        $reason = "Context tokens ($tokens) below all configured thresholds."
    }
}

# ---------------------------------------------------------------------------
# Return evaluation result
# ---------------------------------------------------------------------------
return [PSCustomObject]@{
    PressureState             = $pressureState
    EstimatedContextTokens    = $tokens
    TokenSource               = $TokenSource
    ContextWindow             = $contextWindow
    PressureTokens            = $pressureTokens
    RolloverRecommendedTokens = $rolloverRecommendedTokens
    RolloverRequiredTokens    = $rolloverRequiredTokens
    ContextRatio              = $contextRatio
    Reason                    = $reason
}
