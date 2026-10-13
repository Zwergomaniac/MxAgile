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

    [switch]$UpdateDiscoveryState
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# ---------------------------------------------------------------------------
# Resolve project root
# ---------------------------------------------------------------------------
if (-not $ProjectRoot) {
    $scriptDir = $PSScriptRoot
    $ProjectRoot = Split-Path -Parent $scriptDir
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
        $verOutput = & $Dep.executable --version 2>&1 | Select-Object -First 1
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

    # Active = available AND enabled AND not unavailable
    if ($resolved.available -and $resolved.enabled -and -not $resolved.unavailable) {
        $resolved.active = $true
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
