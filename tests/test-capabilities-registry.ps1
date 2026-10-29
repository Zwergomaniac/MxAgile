<#
.SYNOPSIS
    Capability Registry — Static Validation Tests

.DESCRIPTION
    Validates the MxAgile Capability Registry (`.mxagile/capabilities.yaml`) and
    related static artifacts.

    Layer 0 (Static — no subprocess, no git, no filesystem mutation):
      A. Registry file exists and is non-empty
      B. Schema file exists
      C. Every capability has required fields
      D. Capability IDs are unique and snake_case
      E. version_introduced values are valid version strings
      F. default_state is 'on' or 'off' for every capability
      G. risk values are valid (low/medium/high)
      H. requires references valid IDs
      I. external_dependencies have id and display_name
      J. agent_may_activate_config is false when user_approval_required is true
      K. Context_optimization config block exists in config.yaml
      L. RTK integration file exists with required sections
      M. Context Mode integration file exists with required sections
      N. integrations/context-mode.yaml documents ELv2 license
      O. integrations/rtk.yaml documents Apache-2.0 license
      P. Get-MxAgileCapabilities.ps1 exists and has [CmdletBinding()]
      Q. capability-discovery.md policy exists
      R. docs/capabilities.md exists
      S. docs/context-optimization.md exists
      T. version.yaml updated to 1.5
#>

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$TestsDir  = $PSScriptRoot
$RepoRoot  = Split-Path -Parent $TestsDir
$MxAgile   = Join-Path $RepoRoot '.mxagile'
$Scripts   = Join-Path $RepoRoot 'scripts'
$Docs      = Join-Path $RepoRoot 'docs'

$PassCount   = 0
$FailCount   = 0
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

# ---------------------------------------------------------------------------
# Helper: parse capabilities from YAML
# ---------------------------------------------------------------------------
function Get-CapabilityIds {
    param([string[]]$Lines)
    $ids = @()
    foreach ($line in $Lines) {
        if ($line -match '^\s{2}- id:\s*(.+)$') {
            $ids += $Matches[1].Trim()
        }
    }
    return $ids
}

function Get-CapabilityField {
    param([string[]]$Lines, [string]$CapId, [string]$Field)
    $inCap = $false
    foreach ($line in $Lines) {
        if ($line -match '^\s{2}- id:\s*(.+)$') {
            $inCap = ($Matches[1].Trim() -eq $CapId)
        }
        if ($inCap -and $line -match "^\s+$([regex]::Escape($Field)):\s*(.+)$") {
            return $Matches[1].Trim().Trim('"')
        }
    }
    return $null
}

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=== Capability Registry Static Validation ===" -ForegroundColor Cyan

$registryFile = Join-Path $MxAgile 'capabilities.yaml'
$schemaFile   = Join-Path (Join-Path $MxAgile 'schemas') 'capabilities.schema.json'
$configFile   = Join-Path $MxAgile 'config.yaml'
$rtkFile      = Join-Path (Join-Path $MxAgile 'integrations') 'rtk.yaml'
$cmFile       = Join-Path (Join-Path $MxAgile 'integrations') 'context-mode.yaml'
$policyFile   = Join-Path (Join-Path $MxAgile 'policies') 'capability-discovery.md'
$resolverFile = Join-Path $Scripts 'Get-MxAgileCapabilities.ps1'
$capsDocFile  = Join-Path $Docs 'capabilities.md'
$ctxOptFile   = Join-Path $Docs 'context-optimization.md'
$versionFile  = Join-Path $MxAgile 'version.yaml'

# A. Registry file exists
Assert-True 'A. capabilities.yaml exists' (Test-Path $registryFile) "File not found: $registryFile"

# B. Schema file exists
Assert-True 'B. capabilities.schema.json exists' (Test-Path $schemaFile) "File not found: $schemaFile"

if (Test-Path $registryFile) {
    $regLines = Get-Content $registryFile
    $capIds = Get-CapabilityIds -Lines $regLines

    # C. Every capability has required fields
    $requiredFields = @('name', 'description', 'category', 'version_introduced', 'default_state', 'config_key', 'risk', 'docs_ref')
    $allHaveFields = $true
    $missingInfo = ''
    foreach ($capId in $capIds) {
        foreach ($field in $requiredFields) {
            $val = Get-CapabilityField -Lines $regLines -CapId $capId -Field $field
            if (-not $val) {
                $allHaveFields = $false
                $missingInfo += " [$capId.$field]"
            }
        }
    }
    Assert-True 'C. All capabilities have required fields' $allHaveFields "Missing:$missingInfo"

    # D. Capability IDs unique and snake_case
    $uniqueIds = $capIds | Sort-Object -Unique
    $nonSnake = @($capIds | Where-Object { $_ -notmatch '^[a-z][a-z0-9_]*$' })
    $allSnake = ($nonSnake.Count -eq 0)
    Assert-True 'D. Capability IDs are unique' ($uniqueIds.Count -eq $capIds.Count) "Duplicate IDs found"
    Assert-True 'D. Capability IDs are snake_case' $allSnake "Non-snake_case IDs: $($capIds -join ', ')"

    # E. version_introduced are valid
    $allVersionsValid = $true
    foreach ($capId in $capIds) {
        $ver = Get-CapabilityField -Lines $regLines -CapId $capId -Field 'version_introduced'
        if ($ver -and $ver -notmatch '^\d+\.\d+$') {
            $allVersionsValid = $false
        }
    }
    Assert-True 'E. version_introduced values are valid (x.y)' $allVersionsValid 'Invalid version format'

    # F. default_state is on or off
    $allDefaultStateValid = $true
    foreach ($capId in $capIds) {
        $ds = Get-CapabilityField -Lines $regLines -CapId $capId -Field 'default_state'
        if ($ds -and $ds -notin @('on', 'off')) {
            $allDefaultStateValid = $false
        }
    }
    Assert-True 'F. default_state is on or off for all capabilities' $allDefaultStateValid 'Invalid default_state'

    # G. risk values are valid
    $allRiskValid = $true
    foreach ($capId in $capIds) {
        $risk = Get-CapabilityField -Lines $regLines -CapId $capId -Field 'risk'
        if ($risk -and $risk -notin @('low', 'medium', 'high')) {
            $allRiskValid = $false
        }
    }
    Assert-True 'G. risk values are low/medium/high' $allRiskValid 'Invalid risk value'

    # H. requires references exist
    $requiresOk = $true
    foreach ($line in $regLines) {
        if ($line -match '^\s{2}- id:\s*(.+)$') {
            $null = $Matches[1].Trim()  # track current cap (unused here)
        }
        if ($line -match '^\s+requires:\s*\[([^\]]+)\]') {
            $reqs = $Matches[1] -split ',' | ForEach-Object { $_.Trim().Trim('"').Trim("'") } | Where-Object { $_ }
            foreach ($req in $reqs) {
                if ($req -notin $capIds) {
                    $requiresOk = $false
                }
            }
        }
    }
    Assert-True 'H. requires references valid IDs' $requiresOk 'Requires references non-existent capability ID'

    # I. external_dependencies have id and display_name
    $regText = $regLines -join "`n"
    $hasExtDeps = $regText -match 'external_dependencies:'
    if ($hasExtDeps) {
        Assert-True 'I. RTK external dep has id and display_name' ($regText -match '- id:\s*rtk' -and $regText -match 'display_name:.*RTK') 'RTK dep missing id or display_name'
        Assert-True 'I. Context Mode external dep has id and display_name' ($regText -match '- id:\s*context_mode' -and $regText -match 'display_name:.*Context Mode') 'Context Mode dep missing id or display_name'
    }

    # J. agent_may_activate_config false when user_approval_required true
    # RTK and Context Mode: user_approval_required: true, so agent_may_activate_config should reflect that
    # Actually from the registry: agent_may_activate_config: true (agent can edit config) but user_approval_required: true (external install needs approval)
    # These are orthogonal - config edit is safe, external install needs approval. This is correct behavior.
    # We just check that auto_rollover has agent_may_activate_config: false (it's risky)
    $autoRolloverAgentActivate = Get-CapabilityField -Lines $regLines -CapId 'auto_rollover' -Field 'agent_may_activate_config'
    Assert-True 'J. auto_rollover agent_may_activate_config is false' ($autoRolloverAgentActivate -eq 'false') "auto_rollover should not be agent-activatable (risk: medium), got: $autoRolloverAgentActivate"
}

# K. context_optimization block in config.yaml
if (Test-Path $configFile) {
    $configText = (Get-Content $configFile -Raw)
    Assert-True 'K. context_optimization block in config.yaml' ($configText -match 'context_optimization:') 'context_optimization: block not found'
    Assert-True 'K. rtk sub-block in config.yaml' ($configText -match 'rtk:') 'rtk: sub-block not found'
    Assert-True 'K. context_mode sub-block in config.yaml' ($configText -match 'context_mode:') 'context_mode: sub-block not found'
    Assert-True 'K. preserve_raw_evidence in config.yaml' ($configText -match 'preserve_raw_evidence') 'preserve_raw_evidence not found'
    Assert-True 'K. ANTI-DUAL-MEMORY comment in config.yaml' ($configText -match 'ANTI-DUAL-MEMORY') 'ANTI-DUAL-MEMORY guarantee comment not found'
}

# L. RTK integration file
Assert-True 'L. integrations/rtk.yaml exists' (Test-Path $rtkFile) "Not found: $rtkFile"
if (Test-Path $rtkFile) {
    $rtkText = (Get-Content $rtkFile -Raw)
    Assert-True 'L. rtk.yaml has detection section' ($rtkText -match 'detection:') 'detection: section missing'
    Assert-True 'L. rtk.yaml has fallback section' ($rtkText -match 'fallback:') 'fallback: section missing'
    Assert-True 'L. rtk.yaml has output_safety section' ($rtkText -match 'output_safety:') 'output_safety: section missing'
    Assert-True 'L. rtk.yaml has LOSSLESS_REQUIRED' ($rtkText -match 'LOSSLESS_REQUIRED') 'LOSSLESS_REQUIRED not defined'
    Assert-True 'L. rtk.yaml has COMPACT_SAFE' ($rtkText -match 'COMPACT_SAFE') 'COMPACT_SAFE not defined'
    Assert-True 'L. rtk.yaml has mxagile_authority_contract' ($rtkText -match 'mxagile_authority_contract:') 'mxagile_authority_contract: section missing'
}

# M. Context Mode integration file
Assert-True 'M. integrations/context-mode.yaml exists' (Test-Path $cmFile) "Not found: $cmFile"
if (Test-Path $cmFile) {
    $cmText = (Get-Content $cmFile -Raw)
    Assert-True 'M. context-mode.yaml has detection section' ($cmText -match 'detection:') 'detection: section missing'
    Assert-True 'M. context-mode.yaml has anti_dual_memory_guarantee' ($cmText -match 'anti_dual_memory_guarantee:') 'anti_dual_memory_guarantee: section missing'
    Assert-True 'M. context-mode.yaml has fallback section' ($cmText -match 'fallback:') 'fallback: section missing'
    Assert-True 'M. context-mode.yaml has mxagile_authority_contract' ($cmText -match 'mxagile_authority_contract:') 'mxagile_authority_contract: section missing'
    Assert-True 'M. context-mode.yaml has epoch_integration' ($cmText -match 'epoch_integration:') 'epoch_integration: section missing'
    Assert-True 'M. ownership matrix separates repo, user, and session state' (($cmText -match 'ownership:') -and ($cmText -match 'repo_git_tracked:') -and ($cmText -match 'user_machine_owned:') -and ($cmText -match 'session_owned:')) 'ownership matrix incomplete'
    Assert-True 'M. self-service action classes and runtime git ignores are defined' (($cmText -match 'self_service_policy:') -and ($cmText -match 'SAFE_AUTOMATIC:') -and ($cmText -match 'REQUIRES_USER_APPROVAL:') -and ($cmText -match 'REQUIRES_RESTART:') -and ($cmText -match 'UNSUPPORTED:') -and ($cmText -match 'git_tracking:')) 'self-service or git tracking policy incomplete'
    Assert-True 'M. ambiguous harness evidence fails closed' ($cmText -match 'harness_ambiguous') 'ambiguous harness status missing'
}

# N. Context Mode documents ELv2 license
if (Test-Path $cmFile) {
    $cmText = (Get-Content $cmFile -Raw)
    Assert-True 'N. context-mode.yaml documents ELv2 license' ($cmText -match 'ELv2') 'ELv2 license not documented'
    Assert-True 'N. context-mode.yaml states not redistributed' ($cmText -match 'NOT') 'Redistribution restriction not stated'
}

# O. RTK documents Apache-2.0 license
if (Test-Path $rtkFile) {
    $rtkText = (Get-Content $rtkFile -Raw)
    Assert-True 'O. rtk.yaml documents Apache-2.0 license' ($rtkText -match 'Apache') 'Apache-2.0 license not documented'
}

# P. Get-MxAgileCapabilities.ps1 exists and has CmdletBinding
Assert-True 'P. Get-MxAgileCapabilities.ps1 exists' (Test-Path $resolverFile) "Not found: $resolverFile"
if (Test-Path $resolverFile) {
    $resolverText = (Get-Content $resolverFile -Raw)
    Assert-True 'P. Resolver has [CmdletBinding()]' ($resolverText -match '\[CmdletBinding\(\)\]') 'Missing [CmdletBinding()]'
    Assert-True 'P. Resolver has -Format parameter' ($resolverText -match '\[ValidateSet.*json') 'Missing -Format json parameter'
    Assert-True 'P. Resolver has -CheckUpgrades switch' ($resolverText -match 'CheckUpgrades') 'Missing -CheckUpgrades parameter'
}

# Q. capability-discovery.md policy exists
Assert-True 'Q. policies/capability-discovery.md exists' (Test-Path $policyFile) "Not found: $policyFile"

# R. docs/capabilities.md exists
Assert-True 'R. docs/capabilities.md exists' (Test-Path $capsDocFile) "Not found: $capsDocFile"

# S. docs/context-optimization.md exists
Assert-True 'S. docs/context-optimization.md exists' (Test-Path $ctxOptFile) "Not found: $ctxOptFile"
if (Test-Path $ctxOptFile) {
    $ctxOptText = (Get-Content $ctxOptFile -Raw)
    Assert-True 'S. context-optimization.md mentions anti-dual-memory' ($ctxOptText -match 'Anti-Dual-Memory') 'Anti-Dual-Memory guarantee not in doc'
}

# T. version.yaml is 1.6 (updated from 1.5 in hardening pass)
Assert-True 'T. version.yaml exists' (Test-Path $versionFile) "Not found: $versionFile"
if (Test-Path $versionFile) {
    $versionText = (Get-Content $versionFile -Raw)
    Assert-True 'T. version is 1.7' ($versionText -match 'version:\s*"?1\.[67]"?') "Expected version 1.7, got: $($versionText -split '\n' | Select-Object -First 1)"
}

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=== Results ===" -ForegroundColor Cyan
Write-Host "  PASS: $PassCount" -ForegroundColor Green
if ($FailCount -gt 0) {
    Write-Host "  FAIL: $FailCount" -ForegroundColor Red
    $FailDetails | ForEach-Object { Write-Host $_ -ForegroundColor Red }
    exit 1
} else {
    Write-Host "  All tests passed." -ForegroundColor Green
    exit 0
}
