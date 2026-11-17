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

.PARAMETER ModelProfile
    Requested child reasoning profile. Automatic requests are bounded by MainProfile.

.PARAMETER MainProfile
    User-selected main reasoning profile, resolved by this host, never guessed from a model ID.

.PARAMETER MainModel
    Known main model identifier; dynamic effort requests must bind to this same supported model.

.PARAMETER ModelEscalation
    never, ask or autonomous. Defaults to agent_delegation.model_escalation, or never.
    A caller override must reflect an active user instruction, not self-granted permission.

.PARAMETER UserModelAuthority
    Task-scoped user approval/instruction reference for ask or an explicit model request.

.PARAMETER EscalationReason
    Substantive, auditable task-specific justification for autonomous upward escalation.

.PARAMETER RequestedChildModel
    Exact host model identifier explicitly requested by the user, not a universal model rank.

.PARAMETER ExplicitUserModelRequest
    The user explicitly requested RequestedChildModel for this task. Requires UserModelAuthority.

.PARAMETER AvailableChildModels
    Current observed host-supported child model IDs, including an empty catalog.
    Omission means availability unknown; the resolver does not discover or attest this list.

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
Context Mode operations required for the current task. Usability requires current
discovery and successful same-operation probes, not ctx_doctor alone.

.PARAMETER ContextModeExecutableTools
Canonical ctx_* operations successfully probed in this session and generation.
Inspect each actual tool schema before a bounded non-mutating probe. Never infer
this list from ctx_doctor, installation, another operation or historical evidence.

.PARAMETER ContextModeCheckUpdates
Explicitly check public release metadata when the dependency's 24-hour cache is due.
SessionStart and Doctor remain cache-only. This never installs or updates a plugin.

.PARAMETER ContextModeHooksRequired
The current task requires automatic routing hooks, not only direct ctx_* operations.

.PARAMETER ResolveOperatingMode
Include the current operating mode and tool-authority route in JSON/human output.
Uses the existing read-only Studio Pro detector; no MCP call is made by this resolver.

.PARAMETER StudioProProjectPath
Current project's .mpr path for the existing Studio Pro detector. When omitted,
the resolver uses the sole .mpr file in ProjectRoot, if there is exactly one.

.PARAMETER StudioProMcpProbeStatus
Current-session result of a successful non-mutating Studio Pro MCP probe:
NOT_OBSERVED (default), HEALTHY, FAILED, or TIMEOUT.

.PARAMETER StudioProMcpBoundProjectPath
Project identity returned by the current-session Studio Pro MCP probe.

.PARAMETER ConcordMcpProbeStatus
Current-session result of a successful non-mutating Concord MCP probe:
NOT_OBSERVED (default), HEALTHY, FAILED, or TIMEOUT.

.PARAMETER ConcordMcpBoundProjectPath
Project identity returned by the current-session Concord MCP probe.

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

    [ValidateSet('', 'LIGHT', 'MID', 'HIGH')]
    [string]$MainProfile = '',

    [string]$MainModel = '',

    [ValidateSet('', 'never', 'ask', 'autonomous')]
    [string]$ModelEscalation = '',

    [string]$UserModelAuthority = '',

    [string]$EscalationReason = '',

    [string]$RequestedChildModel = '',

    [switch]$ExplicitUserModelRequest,

    [string[]]$AvailableChildModels = @(),

    [ValidatePattern('^[A-Za-z0-9_-]*$')]
    [string]$AgentType = '',

    [switch]$AgentTypesObserved,

    [string[]]$AgentTypes = @(),

    [ValidateSet('unknown', 'healthy', 'failed', 'timeout')]
    [string]$ContextModeHealth = 'unknown',

    [switch]$ContextModeCheckUpdates,

    [switch]$ContextModeToolsObserved,

    [string[]]$ContextModeTools = @(),

    [string[]]$ContextModeRequiredTools = @(),

    [string[]]$ContextModeExecutableTools = @(),

    [switch]$ContextModeHooksRequired,

    [switch]$ResolveOperatingMode,

    [switch]$ResolveBuilderKit,

    [switch]$BuilderAgentObserved,

    [string]$BuilderAgentObservedName = '',

    [string]$StudioProProjectPath = '',

    [ValidateSet('NOT_OBSERVED', 'HEALTHY', 'FAILED', 'TIMEOUT')]
    [string]$StudioProMcpProbeStatus = 'NOT_OBSERVED',

    [string]$StudioProMcpBoundProjectPath = '',

    [ValidateSet('NOT_OBSERVED', 'HEALTHY', 'FAILED', 'TIMEOUT')]
    [string]$ConcordMcpProbeStatus = 'NOT_OBSERVED',

    [string]$ConcordMcpBoundProjectPath = '',

    [string]$HomeDir = '',

    [string]$ArtifactInvariantEvidenceFile = '',

    [string]$BrowserEvidenceFile = '',

    [string]$OperationEvidenceFile = '',

    [string]$ReferenceEvidenceFile = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$childModelCatalogObserved = $PSBoundParameters.ContainsKey('AvailableChildModels')
$ModelProfile = $ModelProfile.ToUpperInvariant()
$MainProfile = $MainProfile.ToUpperInvariant()

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

# Opt-in observation assessment does not scan the model, discover tools, or run a browser.
function Read-BoundedObservation {
    param([string]$Path)
    if ((Get-Item -LiteralPath $Path).Length -gt 262144) { throw 'Observation exceeds the 256 KiB compact evidence limit.' }
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
}

function Test-ObservationFields {
    param($Object, [string[]]$Fields)
    if ($null -eq $Object) { return $false }
    foreach ($field in $Fields) {
        if (@($Object.PSObject.Properties | ForEach-Object { $_.Name }) -notcontains $field -or $null -eq $Object.$field) { return $false }
    }
    return $true
}

function Test-ObservedStringArray {
    param($Value)
    if ($Value -isnot [array]) { return $false }
    foreach ($item in $Value) {
        if ($item -isnot [string] -or [string]::IsNullOrWhiteSpace($item)) { return $false }
    }
    return $true
}

function Test-ObservedRoleSet {
    param([string[]]$Expected, [string[]]$Observed)
    return (@($Expected | Where-Object { $_ -cnotin $Observed }).Count -eq 0 -and
            @($Observed | Where-Object { $_ -cnotin $Expected }).Count -eq 0)
}

function Resolve-ArtifactInvariant {
    param($Check)
    if (-not (Test-ObservationFields $Check @('invariant', 'artifact'))) { throw 'Each scoped check needs an invariant and artifact identity.' }
    $result = [ordered]@{ invariant = $Check.invariant; artifact = $Check.artifact; result = 'NOT_OBSERVABLE'; reason = 'Required fresh scope evidence is missing.' }
    if (-not (Test-ObservationFields $Check @('evidence_reference', 'view_state', 'expected', 'observed')) -or
        [string]::IsNullOrWhiteSpace([string]$Check.evidence_reference) -or $Check.view_state -cne 'FRESH') { return $result }
    $result.evidence_reference = $Check.evidence_reference
    $expected = $Check.expected
    $observed = $Check.observed
    $valid = $false
    switch ($Check.invariant) {
        'EXECUTABLE_NANOFLOW_ROLE_INVARIANT' {
            if (-not (Test-ObservationFields $expected @('required_roles')) -or
                -not (Test-ObservationFields $observed @('excluded', 'allowed_roles')) -or
                $observed.excluded -isnot [bool] -or
                -not (Test-ObservedStringArray $expected.required_roles) -or
                -not (Test-ObservedStringArray $observed.allowed_roles)) { return $result }
            $valid = -not $observed.excluded -and (Test-ObservedRoleSet $expected.required_roles $observed.allowed_roles)
        }
        'REPLACEMENT_TARGET_INVARIANT' {
            if (-not (Test-ObservationFields $expected @('active_page', 'required_roles', 'backup_pages')) -or
                -not (Test-ObservationFields $observed @('active_page', 'excluded', 'allowed_roles', 'navigation_targets', 'backup_pages')) -or
                $observed.excluded -isnot [bool] -or $observed.backup_pages -isnot [array] -or
                -not (Test-ObservedStringArray $expected.required_roles) -or -not (Test-ObservedStringArray $expected.backup_pages) -or
                -not (Test-ObservedStringArray $observed.allowed_roles) -or -not (Test-ObservedStringArray $observed.navigation_targets) -or
                [string]::IsNullOrWhiteSpace([string]$expected.active_page)) { return $result }
            $valid = $observed.active_page -ceq $expected.active_page -and -not $observed.excluded -and
                (Test-ObservedRoleSet $expected.required_roles $observed.allowed_roles) -and
                @($observed.navigation_targets | Where-Object { $_ -cne $expected.active_page }).Count -eq 0
            foreach ($page in $expected.backup_pages) {
                $backups = @($observed.backup_pages | Where-Object { (Test-ObservationFields $_ @('page')) -and $_.page -ceq $page })
                if ($backups.Count -ne 1 -or -not (Test-ObservationFields $backups[0] @('excluded', 'allowed_roles')) -or
                    $backups[0].excluded -isnot [bool] -or -not (Test-ObservedStringArray $backups[0].allowed_roles)) { return $result }
                # A deliberately excluded backup needs no roles; a runnable backup needs
                # an explicit accepted exception, not a name-based BAK exemption.
                if (-not $backups[0].excluded) {
                    if (-not (Test-ObservationFields $expected @('runnable_backup_pages')) -or
                        -not (Test-ObservedStringArray $expected.runnable_backup_pages) -or
                        $page -cnotin $expected.runnable_backup_pages -or
                        -not (Test-ObservedRoleSet $expected.required_roles $backups[0].allowed_roles)) { $valid = $false }
                }
            }
        }
        'JS_ACTION_PARAMETER_INVARIANT' {
            if (-not (Test-ObservationFields $expected @('user_code_identifiers')) -or
                -not (Test-ObservationFields $observed @('generated_identifiers')) -or
                -not (Test-ObservedStringArray $expected.user_code_identifiers) -or
                -not (Test-ObservedStringArray $observed.generated_identifiers)) { return $result }
            $valid = @($expected.user_code_identifiers | Where-Object { $_ -cnotin $observed.generated_identifiers }).Count -eq 0
        }
        'HTML_BRIDGE_MATERIALIZATION_INVARIANT' {
            if (-not (Test-ObservationFields $expected @('root_selector', 'required_resources')) -or
                -not (Test-ObservationFields $observed @('root_selector', 'root_materialized', 'materialized_resources', 'explicitly_loaded_resources')) -or
                $observed.root_materialized -isnot [bool] -or
                [string]::IsNullOrWhiteSpace([string]$expected.root_selector) -or
                -not (Test-ObservedStringArray $expected.required_resources) -or
                -not (Test-ObservedStringArray $observed.materialized_resources) -or
                -not (Test-ObservedStringArray $observed.explicitly_loaded_resources)) { return $result }
            $available = @($observed.materialized_resources) + @($observed.explicitly_loaded_resources)
            $valid = $observed.root_materialized -and $observed.root_selector -ceq $expected.root_selector -and
                @($expected.required_resources | Where-Object { $_ -cnotin $available }).Count -eq 0
        }
        default { $result.reason = 'Unknown invariant; no verification claim.'; return $result }
    }
    $result.result = if ($valid) { 'PASS' } else { 'FAIL' }
    $result.reason = if ($valid) { 'Observed scoped facts satisfy the accepted contract.' } else { 'Observed scoped facts violate the accepted contract.' }
    return $result
}

function Test-CurrentOperationEvidence {
    param($Evidence)
    $required = @('run_id', 'current_run_id', 'session_generation', 'current_session_generation',
                  'view_state', 'bound_target', 'required_target', 'observed_at')
    if (-not (Test-ObservationFields $Evidence $required)) { return $false }
    foreach ($field in @($required | Where-Object { $_ -ne 'observed_at' })) {
        if ($Evidence.$field -isnot [string] -or [string]::IsNullOrWhiteSpace($Evidence.$field) -or $Evidence.$field -eq 'UNKNOWN') { return $false }
    }
    $timestamp = [DateTimeOffset]::MinValue
    if ($Evidence.observed_at -is [datetime] -or $Evidence.observed_at -is [DateTimeOffset]) {
        $timestamp = [DateTimeOffset]$Evidence.observed_at
    } elseif (-not [DateTimeOffset]::TryParse([string]$Evidence.observed_at, [ref]$timestamp)) { return $false }
    if ($timestamp -gt [DateTimeOffset]::UtcNow) { return $false }
    return $Evidence.view_state -ceq 'FRESH' -and $Evidence.run_id -ceq $Evidence.current_run_id -and
        $Evidence.session_generation -ceq $Evidence.current_session_generation -and
        $Evidence.bound_target -ceq $Evidence.required_target
}

function Resolve-BrowserObservation {
    param($Evidence)
    $required = @('provider', 'host', 'run_id', 'observed_at', 'operation', 'declared_available', 'tools_observed', 'operation_discovered', 'execution_status')
    if (-not (Test-ObservationFields $Evidence $required)) { throw 'Browser observation requires provider, host, run, time, operation, declaration, discovery and execution evidence.' }
    foreach ($field in @('declared_available', 'tools_observed', 'operation_discovered')) {
        if ($Evidence.$field -isnot [bool]) { throw "Browser $field must be boolean." }
    }
    foreach ($field in @('provider', 'host', 'run_id', 'observed_at', 'operation')) {
        if ([string]::IsNullOrWhiteSpace([string]$Evidence.$field)) { throw "Browser $field must be non-empty; use UNKNOWN for an unobserved host." }
    }
    if ($Evidence.execution_status -notin @('NOT_OBSERVED', 'PASSED', 'FAILED', 'TIMEOUT')) { throw 'Invalid browser execution_status.' }
    if ($Evidence.execution_status -ne 'NOT_OBSERVED' -and
        (-not (Test-ObservationFields $Evidence @('execution_reference')) -or
         [string]::IsNullOrWhiteSpace([string]$Evidence.execution_reference))) {
        throw 'Observed browser execution requires a source execution_reference.'
    }
    $current = Test-CurrentOperationEvidence $Evidence
    $executable = $current -and $Evidence.tools_observed -and $Evidence.operation_discovered -and $Evidence.execution_status -eq 'PASSED'
    $state = 'UNKNOWN'
    if ($executable) { $state = 'EXECUTABLE_AVAILABLE' }
    elseif ($Evidence.execution_status -in @('FAILED', 'TIMEOUT')) { $state = 'PARTIAL' }
    elseif ($Evidence.tools_observed -and $Evidence.operation_discovered) { $state = 'DISCOVERED_AVAILABLE' }
    elseif ($Evidence.tools_observed) { $state = if ($Evidence.declared_available) { 'PARTIAL' } else { 'UNAVAILABLE' } }
    elseif ($Evidence.declared_available) { $state = 'DECLARED_AVAILABLE' }
    return [ordered]@{
        provider = $Evidence.provider; host = $Evidence.host; run_id = $Evidence.run_id
        observed_at = $Evidence.observed_at; operation = $Evidence.operation
        declared_available = $Evidence.declared_available
        discovered_available = if ($Evidence.tools_observed) { $Evidence.operation_discovered } else { $null }
        currently_available = if ($current -and $Evidence.tools_observed) { $Evidence.operation_discovered } else { $null }
        executable_available = $executable
        last_verified = if ($Evidence.execution_status -eq 'PASSED') { $Evidence.observed_at } else { $null }
        freshness = if ($current) { 'FRESH' } else { 'UNKNOWN_OR_INVALIDATED' }
        rediscovery_required = -not $current
        binding_verified = $current
        execution_status = $Evidence.execution_status
        execution_reference = if (Test-ObservationFields $Evidence @('execution_reference')) { $Evidence.execution_reference } else { $null }
        state = $state
        route_allowed = $state -eq 'EXECUTABLE_AVAILABLE'
    }
}

function Resolve-ProviderSelection {
    param($Evidence)
    if (-not (Test-ObservationFields $Evidence @('operation', 'providers', 'preferred_providers', 'preference_reason',
                                                'current_run_id', 'current_session_generation', 'required_target')) -or
        $Evidence.providers -isnot [array] -or -not (Test-ObservedStringArray $Evidence.preferred_providers) -or
        [string]::IsNullOrWhiteSpace([string]$Evidence.operation) -or
        [string]::IsNullOrWhiteSpace([string]$Evidence.preference_reason)) { throw 'Provider selection requires operation, current target/run/generation, providers and explicit preference rationale.' }
    $assessments = @()
    $seen = @()
    foreach ($provider in $Evidence.providers) {
        if ($provider.provider -cin $seen) { throw 'Provider evidence must be unique for this operation.' }
        $seen += $provider.provider
        $assessment = Resolve-BrowserObservation $provider
        $matches = $provider.operation -ceq $Evidence.operation
        $sameContext = (Test-ObservationFields $provider @('current_run_id', 'current_session_generation', 'required_target')) -and
            $provider.current_run_id -ceq $Evidence.current_run_id -and
            $provider.current_session_generation -ceq $Evidence.current_session_generation -and
            $provider.required_target -ceq $Evidence.required_target
        $assessment['route_allowed'] = $assessment.route_allowed -and $matches -and $sameContext
        if (Test-ObservationFields $provider @('limitations')) {
            if (-not (Test-ObservedStringArray $provider.limitations)) { throw 'Provider limitations must be a string array.' }
            $assessment['limitations'] = @($provider.limitations)
        } else { $assessment['limitations'] = @('NOT_OBSERVABLE') }
        $assessment['selection_reason'] = if (-not $matches) { 'CAPABILITY_MISMATCH' } elseif (-not $assessment.route_allowed) { 'NOT_CURRENTLY_EXECUTABLE_OR_BOUND' } else { 'CURRENT_EXECUTION_AND_TARGET_BINDING_VERIFIED' }
        $assessments += $assessment
    }
    $eligible = @($Evidence.preferred_providers | Where-Object { $name = $_; @($assessments | Where-Object { $_.provider -ceq $name -and $_.route_allowed }).Count -eq 1 } | Select-Object -Unique)
    return [ordered]@{
        operation = $Evidence.operation; providers = $assessments; preference_reason = $Evidence.preference_reason
        selected_provider = if ($eligible.Count) { $eligible[0] } else { $null }
        fallback_providers = @($eligible | Select-Object -Skip 1)
        reason = if ($eligible.Count) { 'First eligible provider in the explicitly recorded task preference; no package-presence inference.' } else { 'NEEDS_ALTERNATIVE_TOOL: no preferred provider has current executable and target-bound evidence.' }
    }
}

function Resolve-ReferenceSafety {
    param($Evidence)
    $required = @('provider', 'operation', 'scan_status', 'reference_count', 'index_state',
                  'dynamic_reference_possible', 'coverage_complete', 'evidence_reference')
    if (-not (Test-ObservationFields $Evidence $required)) { throw 'Reference safety requires scoped scan and coverage evidence.' }
    if ($Evidence.reference_count -isnot [long] -and $Evidence.reference_count -isnot [int]) { throw 'reference_count must be an integer.' }
    if ($Evidence.reference_count -lt 0 -or $Evidence.coverage_complete -isnot [bool] -or
        $Evidence.dynamic_reference_possible -isnot [bool]) { throw 'Invalid reference coverage types.' }
    if ($Evidence.scan_status -cnotin @('COMPLETE', 'PARTIAL', 'TIMEOUT', 'NOT_OBSERVABLE', 'UNKNOWN') -or
        $Evidence.index_state -cnotin @('FRESH', 'STALE', 'NOT_USED', 'UNKNOWN')) { throw 'Invalid reference scan status.' }
    $state = 'UNKNOWN'
    if ($Evidence.scan_status -ceq 'NOT_OBSERVABLE') { $state = 'NOT_OBSERVABLE' }
    elseif ($Evidence.index_state -ceq 'STALE') { $state = 'STALE_INDEX' }
    elseif ($Evidence.scan_status -cin @('PARTIAL', 'TIMEOUT') -or -not $Evidence.coverage_complete) { $state = 'PARTIAL_SCAN' }
    elseif ($Evidence.dynamic_reference_possible) { $state = 'DYNAMIC_REFERENCE_POSSIBLE' }
    elseif ((Test-CurrentOperationEvidence $Evidence) -and $Evidence.scan_status -ceq 'COMPLETE' -and
            $Evidence.index_state -cin @('FRESH', 'NOT_USED') -and
            -not [string]::IsNullOrWhiteSpace([string]$Evidence.evidence_reference)) {
        $state = if ($Evidence.reference_count -eq 0) { 'COMPLETE_SCAN_NO_REFERENCES' } else { 'REFERENCES_FOUND' }
    }
    return [ordered]@{ state = $state; provider = $Evidence.provider; operation = $Evidence.operation
        evidence_reference = $Evidence.evidence_reference
        reference_clearance = $state -ceq 'COMPLETE_SCAN_NO_REFERENCES'
        mutation_authorized = $false
        reason = 'Reference clearance is necessary, never sufficient: destructive writes still require explicit scope, authority and current preflight.' }
}

if ($ArtifactInvariantEvidenceFile -or $BrowserEvidenceFile -or $OperationEvidenceFile -or $ReferenceEvidenceFile) {
    if ($Format -ne 'json' -or $UpdateDiscoveryState -or $CheckUpgrades -or $Capability -or $ResolveBuilderKit -or $ResolveOperatingMode) {
        throw 'Scoped observation assessment requires -Format json and cannot update or mix registry discovery.'
    }
    $assessment = [ordered]@{ project_root = $ProjectRoot; resolved_at = (Get-Date).ToUniversalTime().ToString('o') }
    if ($ArtifactInvariantEvidenceFile) {
        $inputEvidence = Read-BoundedObservation $ArtifactInvariantEvidenceFile
        if (-not (Test-ObservationFields $inputEvidence @('checks')) -or $inputEvidence.checks -isnot [array]) { throw 'Artifact evidence requires a checks array.' }
        $assessment.artifact_invariants = @($inputEvidence.checks | ForEach-Object { Resolve-ArtifactInvariant $_ })
    }
    if ($BrowserEvidenceFile) { $assessment.browser = Resolve-BrowserObservation (Read-BoundedObservation $BrowserEvidenceFile) }
    if ($OperationEvidenceFile) { $assessment.provider_selection = Resolve-ProviderSelection (Read-BoundedObservation $OperationEvidenceFile) }
    if ($ReferenceEvidenceFile) { $assessment.reference_safety = Resolve-ReferenceSafety (Read-BoundedObservation $ReferenceEvidenceFile) }
    $assessment | ConvertTo-Json -Depth 10
    exit 0
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
                config_location = ''
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
        elseif ($line -match '^\s+config_location:\s*"?(.+?)"?\s*$') { $currentCap.config_location = $Matches[1].Trim('"') }
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

    $policy = $ModelEscalation
    if (-not $policy) { $policy = Get-ConfigValue -Lines $configLines -KeyPath 'agent_delegation.model_escalation' }
    if (-not $policy) { $policy = 'never' }
    $policy = ([string]$policy).ToLowerInvariant()
    if ($policy -notin @('never', 'ask', 'autonomous')) { throw 'Invalid agent_delegation.model_escalation; expected never, ask or autonomous.' }
    $ranks = @{ LIGHT = 0; MID = 1; HIGH = 2 }
    $selectedProfile = $Profile
    $decision = 'allowed'
    $authority = 'main_profile_ceiling'
    $authorityReference = $null
    $reason = 'Requested child profile does not exceed the chosen main profile.'
    $explicit = $ExplicitUserModelRequest -and $RequestedChildModel.Trim() -and $UserModelAuthority.Trim()
    if ($explicit) {
        $authority = 'explicit_user_model'
        $authorityReference = $UserModelAuthority
        $reason = 'Explicit task-scoped user model instruction overrides the escalation policy.'
    } elseif ($RequestedChildModel -or $ExplicitUserModelRequest) {
        $decision = 'blocked'; $reason = 'EXPLICIT_USER_MODEL_AUTHORITY_REQUIRED: a model parameter alone is not user authorization.'
    } elseif (-not $MainProfile) {
        $decision = 'blocked'; $reason = 'MAIN_PROFILE_UNKNOWN: do not infer the main profile from a model name.'
    } elseif (-not $Profile) {
        $decision = 'blocked'; $reason = 'CHILD_PROFILE_UNKNOWN: resolve the requested child profile before dispatch.'
    } elseif ($ranks[$Profile] -gt $ranks[$MainProfile]) {
        switch ($policy) {
            'never' { $selectedProfile = $MainProfile; $decision = 'limited'; $reason = 'MAIN_PROFILE_CEILING: child request limited before host model resolution.' }
            'ask' {
                if ($UserModelAuthority.Trim()) {
                    $authority = 'user_approval'; $authorityReference = $UserModelAuthority
                    $reason = 'Task-scoped user approval permits the higher child profile.'
                } else { $decision = 'needs_user_approval'; $reason = 'USER_MODEL_APPROVAL_REQUIRED: ask before spawning the higher profile.' }
            }
            'autonomous' {
                if ($EscalationReason.Trim()) {
                    $authority = 'autonomous_policy'
                    $authorityReference = if ($ModelEscalation) { 'caller:model_escalation' } else { '.mxagile/config.yaml#agent_delegation.model_escalation' }
                    $reason = $EscalationReason
                } else { $decision = 'blocked'; $reason = 'ESCALATION_JUSTIFICATION_REQUIRED: autonomous escalation must be audited.' }
            }
        }
    }

    $result = Get-DelegationIntegration -ProjectRoot_ $ProjectRoot_ -HarnessResolution $HarnessResolution -Profile $selectedProfile -Enabled $Enabled
    $resolvedProfile = $null
    if ($decision -in @('allowed', 'limited')) {
        if (-not $result.route_allowed) {
            $decision = 'blocked'; $reason = "HOST_DELEGATION_UNAVAILABLE: $($result.reason)"
        } elseif ($explicit) {
            if ($result.model_selection -ne 'supported') {
                $decision = 'blocked'; $reason = 'HOST_MODEL_SELECTION_UNAVAILABLE: the requested model cannot be selected.'
            } elseif (-not $childModelCatalogObserved) {
                $decision = 'blocked'; $reason = 'MODEL_AVAILABILITY_UNKNOWN: discover current host-supported model identifiers first.'
            } elseif ($AvailableChildModels -cnotcontains $RequestedChildModel) {
                $decision = 'blocked'; $reason = 'MODEL_UNAVAILABLE: the explicit model is not supported in the supplied current host catalog; no silent replacement.'
            } else {
                if ($result.model_resolution -eq 'static_mapping' -and $result.resolved_model -ceq $RequestedChildModel) { $resolvedProfile = $selectedProfile }
                $result.resolved_model = $RequestedChildModel
                $result.requested_reasoning_effort = $null
                $result.model_resolution = 'explicit_model_request'
                $result.fallback_used = $false; $result.fallback_reason = $null
            }
        } elseif ($result.model_resolution -eq 'static_mapping') {
            if ($childModelCatalogObserved -and $AvailableChildModels -cnotcontains $result.resolved_model) {
                $decision = 'blocked'; $reason = 'MODEL_UNAVAILABLE: mapped child model is unavailable; continue with the main agent.'
            } else { $resolvedProfile = $selectedProfile }
        } elseif ($result.model_resolution -eq 'dynamic_capability_request' -and $MainModel -and $childModelCatalogObserved -and $AvailableChildModels -ccontains $MainModel) {
            $result.resolved_model = $MainModel
            $resolvedProfile = $selectedProfile
        } else {
            $decision = 'blocked'; $reason = "MODEL_PROFILE_UNRESOLVED: $($result.fallback_reason) No verified profile mapping or same-main-model request binding; do not spawn an arbitrary default model."
        }
    }
    if ($decision -in @('blocked', 'needs_user_approval')) {
        $result.route_allowed = $false
        $result.resolved_model = $null; $result.requested_reasoning_effort = $null
        $result.model_resolution = 'fallback_available_model'
        $result.fallback_used = $true; $result.fallback_reason = $reason
        $result.fallback = 'main_agent'
        $authority = if ($explicit) { $authority } else { 'none' }
    }
    $result.requested_profile = if ($Profile) { $Profile } else { $null }
    $result.reason += " Model policy: $reason"
    $result['escalation'] = [ordered]@{
        main_profile = if ($MainProfile) { $MainProfile } else { $null }
        main_model = if ($MainModel) { $MainModel } else { $null }
        requested_child_profile = if ($Profile) { $Profile } else { $null }
        resolved_child_profile = $resolvedProfile
        requested_child_model = if ($RequestedChildModel) { $RequestedChildModel } else { $null }
        spawn_request_model = $null
        actual_model = $null
        actual_model_status = 'NOT_OBSERVABLE'
        actual_model_source = $null
        escalation_policy = $policy
        escalation_authority = $authority
        authority_reference = $authorityReference
        decision = $decision
        reason = $reason
    }
    return $result
}

function Get-DelegationIntegration {
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
        profile_resolution = 'unknown'
        profile_resolution_notes = ''
        max_concurrency = $null
        concurrency_notes = ''
        requested_profile = if ($Profile) { $Profile } else { $null }
        resolved_model = $null
        requested_reasoning_effort = $null
        model_resolution = if ($Profile) { 'fallback_available_model' } else { 'not_requested' }
        fallback_used = [bool]$Profile
        fallback_reason = if ($Profile) { 'No verified profile-specific resolution was available.' } else { $null }
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
    $inReasoningEfforts = $false
    $profileMappings = @{}
    $reasoningEfforts = @{}
    foreach ($line in $adapterLines) {
        if ($line -match '^delegation:\s*$') { $inDelegation = $true; continue }
        if (-not $inDelegation) { continue }
        if ($line -match '^\S') { $inDelegation = $false; $inProfiles = $false; continue }
        if ($line -match '^  profiles:\s*$') { $inProfiles = $true; $inReasoningEfforts = $false; continue }
        if ($line -match '^  reasoning_efforts:\s*$') { $inProfiles = $false; $inReasoningEfforts = $true; continue }
        if ($line -match '^  (?:profile_resolution|profile_resolution_notes|harness_id|status|named_agents|generic_fork|model_selection|max_concurrency|concurrency_notes|evidence|assessed_date):') {
            $inProfiles = $false
            $inReasoningEfforts = $false
        }
        if ($line -match '^  harness_id:\s*([a-z0-9_]+)\s*$') { $result.adapter_harness_id = $Matches[1] }
        elseif ($line -match '^  concurrency_notes:\s*(.*?)\s*$') { $result.concurrency_notes = $Matches[1].Trim('"').Trim("'") }
        elseif ($line -match '^  profile_resolution:\s*(static_mapping|dynamic_capability|unknown|unsupported)\s*$') { $result.profile_resolution = $Matches[1] }
        elseif ($line -match '^  profile_resolution_notes:\s*(.*?)\s*$') { $result.profile_resolution_notes = $Matches[1].Trim('"').Trim("'") }
        if ($inProfiles -and $line -match '^    (LIGHT|MID|HIGH):\s*(.*?)\s*$') {
            $profileMappings[$Matches[1]] = $Matches[2].Trim().Trim('"').Trim("'")
            continue
        }
        if ($inReasoningEfforts -and $line -match '^    (LIGHT|MID|HIGH):\s*(.*?)\s*$') {
            $reasoningEfforts[$Matches[1]] = $Matches[2].Trim().Trim('"').Trim("'")
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
        if ($result.model_selection -eq 'supported' -and $result.profile_resolution -eq 'static_mapping' -and $profileMappings.ContainsKey($Profile) -and $profileMappings[$Profile] -and $profileMappings[$Profile] -ne 'null') {
            $result.resolved_model = $profileMappings[$Profile]
            $result.model_resolution = 'static_mapping'
            $result.fallback_used = $false
            $result.fallback_reason = $null
        } elseif ($result.model_selection -eq 'supported' -and $result.profile_resolution -eq 'dynamic_capability' -and $reasoningEfforts.ContainsKey($Profile)) {
            $result.requested_reasoning_effort = $reasoningEfforts[$Profile]
            $result.model_resolution = 'dynamic_capability_request'
            $result.fallback_used = $false
            $result.fallback_reason = $null
        } else {
            $result.model_resolution = 'fallback_available_model'
            $result.fallback_used = $true
            if ($result.model_selection -eq 'unsupported') {
                $result.fallback_reason = 'Harness does not support model selection.'
            } elseif ($result.model_selection -eq 'unknown') {
                $result.fallback_reason = 'Harness model-selection support is unknown.'
            } elseif ($result.profile_resolution -eq 'unknown') {
                $result.fallback_reason = 'No verified profile mapping or capability-based resolution is available.'
            } else {
                $result.fallback_reason = 'The requested profile has no supported mapping in this adapter.'
            }
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
function Resolve-BuilderKit {
    param(
        [string]$ProjectRoot_,
        [string]$Home_,
        [string]$HarnessRequested,
        [bool]$AgentObserved,
        [string]$AgentObservedName
    )

    $agentName = 'mendix-page-designer-html-mode'
    $harness = Resolve-HarnessId -Requested $HarnessRequested
    $manifestCandidates = @(
        (Join-Path $ProjectRoot_ '.mendix-page-designer-html-mode/manifest.json'),
        (Join-Path $Home_ '.mendix-page-designer-html-mode/manifest.json')
    )
    $manifest = $null
    $manifestPath = $null
    $manifestState = 'missing'
    foreach ($candidate in $manifestCandidates) {
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { continue }
        try {
            $parsed = Get-Content -LiteralPath $candidate -Raw | ConvertFrom-Json -ErrorAction Stop
            if ($parsed.kit -ne 'mendix-ui-builder-kit' -or $parsed.agent -ne $agentName) { continue }
            $manifest = $parsed
            $manifestPath = $candidate
            $manifestState = 'valid'
            break
        } catch {
            $manifestState = 'invalid'
        }
    }

    $agentLocations = @(switch ($harness.id) {
        { $_ -in @('vscode_copilot', 'copilot_cli') } {
            @(
                @{ path = (Join-Path $ProjectRoot_ '.github/agents/mendix-page-designer-html-mode.agent.md'); source = 'project' }
                @{ path = (Join-Path $Home_ '.copilot/agents/mendix-page-designer-html-mode.agent.md'); source = 'global' }
            )
        }
        'claude_code' {
            @(
                @{ path = (Join-Path $ProjectRoot_ '.claude/agents/mendix-page-designer-html-mode.md'); source = 'project' }
                @{ path = (Join-Path $Home_ '.claude/agents/mendix-page-designer-html-mode.md'); source = 'global' }
            )
        }
        'opencode' {
            @(
                @{ path = (Join-Path $ProjectRoot_ '.opencode/agents/mendix-page-designer-html-mode.md'); source = 'project' }
                @{ path = (Join-Path $Home_ '.config/opencode/agents/mendix-page-designer-html-mode.md'); source = 'global' }
            )
        }
        default { @() }
    })
    $agentPath = $null
    $agentSource = $null
    $agentAvailable = $null
    if ($agentLocations.Count -gt 0) {
        foreach ($candidate in $agentLocations) {
            if (-not (Test-Path -LiteralPath $candidate.path -PathType Leaf)) { continue }
            $content = Get-Content -LiteralPath $candidate.path -Raw
            if ($content -match [regex]::Escape($agentName)) {
                $agentPath = $candidate.path
                $agentSource = $candidate.source
                $agentAvailable = $true
                break
            }
        }
        if ($null -eq $agentAvailable) { $agentAvailable = $false }
    }

    $delegation = $null
    if (-not $harness.ambiguous -and $harness.id -ne 'unknown') {
        $delegation = Resolve-DelegationIntegration -ProjectRoot_ $ProjectRoot_ -HarnessResolution $harness `
            -Profile $ModelProfile -Enabled (Get-ProjectConfigBool -KeyPath 'agent_delegation.enabled' -Default $true)
    }

    $delegable = $null
    $delegableReason = 'Current-session agent inventory was not observed.'
    if ($AgentObserved) {
        if ($AgentObservedName -ne $agentName) {
            $delegable = $false
            $delegableReason = "Observed agent name does not match '$agentName'."
        } elseif ($harness.id -eq 'unknown' -or $null -eq $agentAvailable) {
            $delegable = $null
            $delegableReason = 'Current-session harness is not attested; agent availability and routing remain UNKNOWN.'
        } elseif ($agentAvailable -ne $true) {
            $delegable = $false
            $delegableReason = 'The agent file is unavailable for the attested current harness.'
        } elseif ($manifestState -ne 'valid') {
            $delegable = $false
            $delegableReason = 'The Kit manifest does not confirm that its private skills are installed.'
        } elseif (-not $delegation -or -not $delegation.route_allowed -or $delegation.named_agents -ne 'supported') {
            $delegable = $false
            $delegableReason = if ($delegation) { $delegation.reason } else { 'Current harness delegation is not attested.' }
        } else {
            $delegable = $true
            $delegableReason = 'Exact agent name was observed in this session and the harness adapter permits named delegation.'
        }
    }

    return [ordered]@{
        kit = 'mendix-ui-builder-kit'
        installed = ($manifestState -eq 'valid')
        installation_state = $manifestState
        version = if ($manifest) { $manifest.version } else { $null }
        manifest_path = $manifestPath
        current_harness = $harness.id
        harness_evidence = $harness.source
        agent = $agentName
        agent_path = $agentPath
        agent_source = $agentSource
        agent_available_for_harness = $agentAvailable
        agent_delegable = $delegable
        agent_observed = $AgentObserved
        delegation_status = if ($delegation) { $delegation.status } else { 'unknown' }
        delegation_reason = $delegableReason
        delegation_integration = $delegation
        note = 'Kit capability is independent from ui.implementation.html_first; no automatic installation or native fallback is performed.'
    }
}

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
    if ($Cap.id -in @('studio_pro_mcp', 'concord_mcp')) {
        $declaration = Get-DeclaredMcpConfiguration -CapabilityId $Cap.id
        $configEnabled = $declaration.configured -eq $true
        $resolved.integration = [ordered]@{ usable = $false; declaration = $declaration
            currently_available = $null; executable = $null; last_verified = $null
            reason = 'Static MCP configuration is DECLARED only; query scoped operation evidence for current executability.' }
    }
    $resolved.enabled = $configEnabled

    # Context Mode: harness-specific integration evidence replaces the bare executable check.
    # available = a runtime for this harness exists; it does NOT mean usable (see integration.usable).
    if ($Cap.id -eq 'context_mode_integration') {
        $int = Resolve-ContextModeIntegration -Root $ProjectRoot -Home_ $HomeDir -HarnessRequested $Harness `
            -Health $ContextModeHealth -ToolsObserved $ContextModeToolsObserved.IsPresent `
            -SessionTools $ContextModeTools -RequiredTools $ContextModeRequiredTools -HooksRequired $ContextModeHooksRequired.IsPresent `
            -Enabled $configEnabled -AdapterBase $mxagileDir
        $healthScript = Join-Path $PSScriptRoot 'dependency_health.py'
        $python = Get-Command python -ErrorAction SilentlyContinue
        if ($python -and (Test-Path -LiteralPath $healthScript -PathType Leaf)) {
            $healthArgs = @('-B', $healthScript, '--project-root', $ProjectRoot, '--home-dir', $HomeDir)
            if ($ContextModeCheckUpdates) { $healthArgs += '--check-updates' }
            if ($ContextModeToolsObserved -and $int.harness -ne 'unknown' -and -not $int.harness_conflict) {
                $healthArgs += @('--tools-observed', '--probe-status', $int.health)
                foreach ($tool in $int.loaded_tools) { $healthArgs += @('--tool', $tool) }
                foreach ($tool in $ContextModeExecutableTools) { $healthArgs += @('--executed-tool', $tool) }
            }
            foreach ($tool in $ContextModeRequiredTools) { $healthArgs += @('--required-tool', $tool) }
            $healthText = & $python.Source @healthArgs 2>$null
            $dependency = Read-JsonLenient ($healthText -join "`n")
        } else { $dependency = $null }
        if (-not $dependency) {
            $discoverable = @{}
            foreach ($tool in $ContextModeRequiredTools) { $discoverable[$tool] = if ($ContextModeToolsObserved) { $tool -in $int.loaded_tools } else { $null } }
            $missingExecution = @($ContextModeRequiredTools | Where-Object { $_ -notin $ContextModeExecutableTools -or $_ -notin $int.loaded_tools })
            $executable = if ($int.health_source -eq 'agent_observed_session_probe' -and $int.health -ne 'healthy') { $false }
                elseif ($ContextModeToolsObserved -and @($ContextModeRequiredTools).Count -gt 0 -and $missingExecution.Count -eq 0) { $true } else { $null }
            $dependency = [pscustomobject]@{ id = 'context_mode'; installed = $int.runtime_present; installed_version = $null;
                executable = $executable; required_capabilities = @($ContextModeRequiredTools); capabilities_discoverable = $discoverable;
                compatible = $null; latest_known_version = $null; update_available = $null; last_update_check = $null;
                update_check_status = 'UNKNOWN'; update_check_due = $true;
                health_status = if (@($ContextModeRequiredTools).Count -gt 0 -and (-not $int.usable -or $executable -ne $true)) { 'CAPABILITY_DEGRADED' } else { 'UNKNOWN' };
                route_allowed = ($int.usable -and $executable -eq $true); automatic_action = 'none'; blocking = $false }
        }
        $int.dependency_health = $dependency
        if ($int.usable -and -not $dependency.route_allowed) {
            $int.usable = $false
            $int.status = 'dependency_health_degraded'
            $int.reason = "Required Context Mode route is not executable/compatible: $($dependency.health_status)."
        }
        $resolved.integration = $int
        $versionDegraded = $resolved.degraded
        switch ($int.status) {
            { $_ -in @('not_installed', 'harness_unsupported') } {
                $resolved.available = $false; $resolved.unavailable = $true; $resolved.degraded = $false
            }
            { $_ -in @('misconfigured', 'configured_runtime_missing', 'configured_load_unknown', 'configured_not_loaded', 'loaded_health_unknown', 'loaded_unhealthy', 'loaded_hooks_missing', 'loaded_unconfigured', 'task_tools_missing', 'task_fit_unknown', 'harness_ambiguous', 'dependency_health_degraded') } {
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
        if ($AgentType) {
            $definitionPresent = $false
            $definitionNameValid = $false
            if ($harnessResolution.id -eq 'claude_code') {
                $agentPath = Join-Path $ProjectRoot ".claude/agents/$AgentType.md"
                $definitionPresent = Test-Path -LiteralPath $agentPath -PathType Leaf
                if ($definitionPresent) {
                    $agentText = Get-Content -LiteralPath $agentPath -Raw -Encoding UTF8
                    if ($agentText -match '\A---\r?\n([\s\S]*?)\r?\n---') {
                        $header = $Matches[1]
                        $names = @([regex]::Matches($header, '(?m)^name:\s*["'']?([A-Za-z0-9_-]+)["'']?\s*$'))
                        $definitionNameValid = $names.Count -eq 1 -and $names[0].Groups[1].Value -ceq $AgentType
                    }
                }
            }
            $registered = if ($AgentTypesObserved) { $AgentType -cin $AgentTypes } else { $null }
            $registrationStatus = if (-not $definitionPresent) { 'AGENT_DEFINITION_MISSING' }
                elseif (-not $definitionNameValid) { 'AGENT_DEFINITION_INVALID' }
                elseif (-not $AgentTypesObserved) { 'HOST_REGISTRATION_NOT_OBSERVABLE' }
                elseif (-not $registered) { 'AGENT_NOT_REGISTERED' }
                else { 'HOST_AGENT_DISCOVERED' }
            $delegation['agent_availability'] = [ordered]@{
                agent_type = $AgentType
                generated_definition_present = $definitionPresent
                definition_name_valid = $definitionNameValid
                host_inventory_observed = [bool]$AgentTypesObserved
                inventory_source = if ($AgentTypesObserved) { 'caller_observed_current_host_inventory' } else { 'NOT_OBSERVABLE' }
                host_registered = $registered
                execution_status = 'NOT_OBSERVABLE'
                status = $registrationStatus
                spawn_ready = $definitionPresent -and $definitionNameValid -and $registered -eq $true -and $delegation.route_allowed
                reload_required = 'NOT_OBSERVABLE'
            }
        }
        $resolved.integration = $delegation
        switch ($delegation.status) {
            'supported' { $resolved.available = $true; $resolved.unavailable = $false }
            'unsupported' { $resolved.available = $false; $resolved.unavailable = $true }
            default { $resolved.available = $false; $resolved.unavailable = $false }
        }
        $resolved.active = $false
        $resolved.state_reason = $delegation.reason
        if ($AgentType) {
            $resolved.available = [bool]$delegation.agent_availability.spawn_ready
            $resolved.unavailable = $delegation.agent_availability.status -in @('AGENT_DEFINITION_MISSING', 'AGENT_DEFINITION_INVALID', 'AGENT_NOT_REGISTERED')
            $resolved.state_reason = $delegation.agent_availability.status
        }
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
# Optional operating-mode/tool-authority resolution
# ---------------------------------------------------------------------------
function Get-DeclaredMcpConfiguration {
    param([string]$CapabilityId)

    $cap = $allCapabilities | Where-Object { $_.id -eq $CapabilityId } | Select-Object -First 1
    if (-not $cap -or -not $cap.config_location -or -not $cap.config_key) {
        return [ordered]@{ state = 'NOT_OBSERVED'; configured = $null; source = $null; reason = 'Registry configuration metadata is unavailable.' }
    }

    $configPath = Join-Path $ProjectRoot $cap.config_location
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
        return [ordered]@{ state = 'OBSERVED'; configured = $false; source = $cap.config_location; reason = 'Project MCP configuration file is absent.' }
    }

    try {
        $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
        $value = $config
        foreach ($segment in ($cap.config_key -split '\.')) {
            if ($null -eq $value) { break }
            $property = $value.PSObject.Properties[$segment]
            if (-not $property) { $value = $null; break }
            $value = $property.Value
        }
        $disabled = $null -ne $value -and $value.PSObject.Properties['enabled'] -and $value.enabled -eq $false
        return [ordered]@{
            state = 'OBSERVED'
            configured = ($null -ne $value -and -not $disabled)
            source = $cap.config_location
            reason = if ($disabled) { 'Project MCP entry is explicitly disabled.' } elseif ($null -ne $value) { 'Registry config key is present in project MCP configuration; declaration only.' } else { 'Registry config key is absent from project MCP configuration.' }
        }
    } catch {
        return [ordered]@{ state = 'UNKNOWN'; configured = $null; source = $cap.config_location; reason = 'Project MCP configuration could not be parsed.' }
    }
}

function Invoke-StudioProStatusDetector {
    param([string]$MprPath)

    $detectorPath = Join-Path $PSScriptRoot 'check-studio-pro-status.ps1'
    if (-not (Test-Path -LiteralPath $detectorPath -PathType Leaf) -or [string]::IsNullOrWhiteSpace($MprPath)) {
        return [ordered]@{ state = 'UNKNOWN'; is_open = $null; any_studio_pro_running = $null; project_path = $MprPath; source = $detectorPath; reason = 'Detector or current project path is unavailable.' }
    }

    $outputPath = Join-Path ([IO.Path]::GetTempPath()) "mxagile-studio-pro-$([guid]::NewGuid().ToString('N')).out"
    $errorPath = Join-Path ([IO.Path]::GetTempPath()) "mxagile-studio-pro-$([guid]::NewGuid().ToString('N')).err"
    try {
        $powershellPath = (Get-Process -Id $PID).Path
        $arguments = @('-NoProfile', '-File', $detectorPath, '-Json', '-TimeoutSeconds', '10', '-ProjectPath', $MprPath) |
            ForEach-Object { '"' + ($_ -replace '"', '\"') + '"' }
        $child = Start-Process -FilePath $powershellPath -ArgumentList ($arguments -join ' ') -PassThru -Wait `
            -RedirectStandardOutput $outputPath -RedirectStandardError $errorPath
        $parsed = Get-Content -LiteralPath $outputPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        $isOpenProperty = $parsed.PSObject.Properties['isOpen']
        $runningProperty = $parsed.PSObject.Properties['anyStudioProRunning']
        if ($child.ExitCode -eq 2 -or -not $isOpenProperty -or -not $runningProperty -or $null -eq $parsed.isOpen -or $null -eq $parsed.anyStudioProRunning) {
            return [ordered]@{ state = 'UNKNOWN'; is_open = $null; any_studio_pro_running = $null; project_path = $MprPath; source = $detectorPath; reason = [string]$parsed.error }
        }
        return [ordered]@{
            state = 'OBSERVED'
            is_open = [bool]$parsed.isOpen
            any_studio_pro_running = [bool]$parsed.anyStudioProRunning
            project_path = [string]$parsed.projectPath
            source = $detectorPath
            reason = if ($parsed.isOpen) { 'Studio Pro process identity matches the current project.' } elseif ($parsed.anyStudioProRunning) { 'Studio Pro is running for another project.' } else { 'No Studio Pro process is running.' }
        }
    } catch {
        return [ordered]@{ state = 'UNKNOWN'; is_open = $null; any_studio_pro_running = $null; project_path = $MprPath; source = $detectorPath; reason = 'Studio Pro detection failed or timed out.' }
    } finally {
        Remove-Item -LiteralPath $outputPath, $errorPath -Force -ErrorAction SilentlyContinue
    }
}

function Resolve-OperatingModeRoute {
    param(
        [string]$Mode,
        [string]$CurrentProjectPath,
        [System.Collections.IDictionary]$StudioProConfiguration,
        [string]$StudioProMcpProbeStatus,
        [string]$StudioProMcpBoundProjectPath,
        [System.Collections.IDictionary]$ConcordConfiguration,
        [string]$ConcordMcpProbeStatus,
        [string]$ConcordMcpBoundProjectPath
    )

    $normalizePath = {
        param([string]$Value)
        if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
        try { return [IO.Path]::GetFullPath($Value).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) }
        catch { return $null }
    }
    $currentPath = & $normalizePath $CurrentProjectPath
    $studioBoundPath = & $normalizePath $StudioProMcpBoundProjectPath
    $concordBoundPath = & $normalizePath $ConcordMcpBoundProjectPath
    $comparison = if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
    $studioMatches = ($currentPath -and $studioBoundPath -and $currentPath.Equals($studioBoundPath, $comparison))
    $concordMatches = ($currentPath -and $concordBoundPath -and $currentPath.Equals($concordBoundPath, $comparison))
    $studioUsable = ($StudioProMcpProbeStatus -eq 'HEALTHY' -and $studioMatches)
    $concordUsable = ($ConcordMcpProbeStatus -eq 'HEALTHY' -and $concordMatches)

    $result = [ordered]@{
        detected_mode = $Mode
        effective_mode = $Mode
        status = 'UNRESOLVED'
        preferred_route = 'none'
        selected_route = $null
        reason = ''
        mxcli_permitted = $false
        mxcli_availability = 'NOT_RESOLVED_BY_C2'
        mxcli_fallback_after_mcp_failure = $false
        configured = [ordered]@{
            studio_pro_mcp = $StudioProConfiguration
            concord_mcp = $ConcordConfiguration
        }
        runtime_attestation = [ordered]@{
            studio_pro_mcp = [ordered]@{
                status = $StudioProMcpProbeStatus
                bound_project_path = $StudioProMcpBoundProjectPath
                current_project_match = [bool]$studioMatches
                usable = [bool]$studioUsable
                source = 'caller-attested current-session read-only MCP probe'
            }
            concord_mcp = [ordered]@{
                status = $ConcordMcpProbeStatus
                bound_project_path = $ConcordMcpBoundProjectPath
                current_project_match = [bool]$concordMatches
                usable = [bool]$concordUsable
                source = 'caller-attested current-session read-only MCP probe'
            }
        }
    }

    switch ($Mode) {
        'LIVE-SP-CURRENT' {
            $result.preferred_route = 'studio_pro_mcp_then_concord_mcp'
            if ($StudioProMcpProbeStatus -eq 'HEALTHY' -and $studioBoundPath -and -not $studioMatches) {
                $result.status = 'CONFLICT'
                $result.effective_mode = 'AMBIGUOUS-SP-STATE'
                $result.reason = 'Studio Pro MCP reported a different project identity; no mutation route is selected.'
            } elseif ($studioUsable) {
                $result.status = 'RUNTIME_ATTESTED'
                $result.selected_route = 'studio_pro_mcp'
                $result.reason = 'Studio Pro MCP completed a successful read-only probe and is bound to the current project.'
            } elseif ($ConcordMcpProbeStatus -eq 'HEALTHY' -and $concordBoundPath -and -not $concordMatches) {
                $result.status = 'CONFLICT'
                $result.effective_mode = 'AMBIGUOUS-SP-STATE'
                $result.reason = 'Concord MCP reported a different project identity; no mutation route is selected.'
            } elseif ($concordUsable) {
                $result.status = 'RUNTIME_ATTESTED_FALLBACK'
                $result.selected_route = 'concord_mcp'
                $result.reason = 'Studio Pro MCP is not attested usable; Concord MCP passed a read-only health and current-project binding probe.'
            } else {
                $result.status = 'BLOCKED'
                $result.reason = 'Neither MCP route is attested healthy and bound to the current project. mxcli is prohibited in LIVE-SP-CURRENT.'
            }
            $result.mxcli_permitted = $false
            $result.mxcli_fallback_after_mcp_failure = $false
        }
        { $_ -in @('CLOSED-AUTONOM', 'LIVE-SP-OTHER') } {
            $result.status = 'AUTONOMOUS_ROUTE_ELIGIBLE'
            $result.preferred_route = 'mxcli'
            $result.mxcli_permitted = $true
            $result.reason = 'Autonomous mxcli use is permitted for this mode, subject to the existing project-local mxcli resolver.'
        }
        default {
            $result.status = 'RECHECK_REQUIRED'
            $result.preferred_route = 'safe_non_model_work_only'
            $result.reason = 'Operating mode is ambiguous or unobserved; recheck before any model mutation.'
        }
    }
    $result.user_interaction = [ordered]@{
        mode_choice_required = $false
        question_policy = if ($result.effective_mode -in @('CLOSED-AUTONOM', 'LIVE-SP-OTHER', 'LIVE-SP-CURRENT')) {
            'NONE'
        } else {
            'MUTATION_BOUNDARY_AFTER_RECHECK'
        }
    }
    return $result
}

function Resolve-OperatingModeAuthority {
    param()

    $mprPath = $StudioProProjectPath
    $mprCandidates = @()
    $mprLookupFailed = $false
    if ([string]::IsNullOrWhiteSpace($mprPath)) {
        try {
            $mprCandidates = @(Get-ChildItem -LiteralPath $ProjectRoot -File -Filter '*.mpr' -ErrorAction Stop)
        } catch {
            $mprLookupFailed = $true
        }
        if ($mprCandidates.Count -eq 1) { $mprPath = $mprCandidates[0].FullName }
    }
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
        $detection = [ordered]@{ state = 'OBSERVED'; mode = 'CLOSED-AUTONOM'; is_open = $false; any_studio_pro_running = $false; project_path = $null; source = 'platform_headless'; reason = 'Studio Pro is not available on this platform.' }
    } elseif ($mprLookupFailed) {
        $mode = 'AMBIGUOUS-SP-STATE'
        $detection = [ordered]@{ state = 'UNKNOWN'; mode = $mode; is_open = $null; any_studio_pro_running = $null; project_path = $null; source = 'mpr_lookup_failed'; reason = 'Project-root .mpr enumeration failed; absence of a project cannot be established.' }
    } elseif ([string]::IsNullOrWhiteSpace($mprPath) -and $mprCandidates.Count -eq 0) {
        $mode = 'CLOSED-AUTONOM'
        $detection = [ordered]@{ state = 'OBSERVED'; mode = 'CLOSED-AUTONOM'; is_open = $false; any_studio_pro_running = $false; project_path = $null; source = 'no_mpr_in_project_root'; reason = 'No Mendix .mpr project was found; Studio Pro mode is not applicable.' }
    } elseif ([string]::IsNullOrWhiteSpace($mprPath)) {
        $mode = 'AMBIGUOUS-SP-STATE'
        $detection = [ordered]@{ state = 'UNKNOWN'; mode = $mode; is_open = $null; any_studio_pro_running = $null; project_path = $null; source = 'multiple_mpr_candidates'; reason = 'Multiple .mpr files were found; project identity must be resolved before detection.' }
    } else {
        $detection = Invoke-StudioProStatusDetector -MprPath $mprPath
        if ($detection.state -eq 'OBSERVED') {
            if ($detection.is_open) { $mode = 'LIVE-SP-CURRENT' }
            elseif ($detection.any_studio_pro_running) { $mode = 'LIVE-SP-OTHER' }
            else { $mode = 'CLOSED-AUTONOM' }
        } else { $mode = 'AMBIGUOUS-SP-STATE' }
        $detection.mode = $mode
    }

    $studioConfig = Get-DeclaredMcpConfiguration -CapabilityId 'studio_pro_mcp'
    $concordConfig = Get-DeclaredMcpConfiguration -CapabilityId 'concord_mcp'
    $route = Resolve-OperatingModeRoute -Mode $mode -CurrentProjectPath $detection.project_path `
        -StudioProConfiguration $studioConfig -StudioProMcpProbeStatus $StudioProMcpProbeStatus `
        -StudioProMcpBoundProjectPath $StudioProMcpBoundProjectPath -ConcordConfiguration $concordConfig `
        -ConcordMcpProbeStatus $ConcordMcpProbeStatus -ConcordMcpBoundProjectPath $ConcordMcpBoundProjectPath
    return [ordered]@{ mode = $route.effective_mode; detected_mode = $mode; detection = $detection; tool_authority = $route }
}

# ---------------------------------------------------------------------------
# Resolve all capabilities
# ---------------------------------------------------------------------------
$allResolved = [ordered]@{}
foreach ($cap in $allCapabilities) {
    $r = Resolve-Capability -Cap $cap -AllResolved $allResolved
    $allResolved[$cap.id] = $r
}
$operatingModeResult = if ($ResolveOperatingMode) { Resolve-OperatingModeAuthority } else { $null }

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
    if ($ResolveBuilderKit) {
        $output.builder_kit = Resolve-BuilderKit -ProjectRoot_ $ProjectRoot -Home_ $HomeDir `
            -HarnessRequested $Harness -AgentObserved $BuilderAgentObserved.IsPresent `
            -AgentObservedName $BuilderAgentObservedName
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
    if ($ResolveOperatingMode) { $output.operating_mode = $operatingModeResult }
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
        if ($r.id -eq 'context_mode_integration') {
            $d = $i.dependency_health
            Write-Host "    Dependency health: $($d.health_status) | installed=$($d.installed) | version=$($d.installed_version) | executable=$($d.executable) | compatible=$($d.compatible)" -ForegroundColor DarkGray
            Write-Host "    Update: latest_known=$($d.latest_known_version) | available=$($d.update_available) | checked=$($d.last_update_check) | evidence=$($d.update_check_status); automatic action=none" -ForegroundColor DarkGray
        }
        if ($i.required_tools.Count -gt 0) { Write-Host "    Required tools: $($i.required_tools -join ', ') | missing: $($i.missing_required_tools -join ', ')" -ForegroundColor DarkGray }
        foreach ($f in $i.findings) { Write-Host "    Finding: $f" -ForegroundColor Yellow }
        foreach ($g in $i.guidance) { Write-Host "    Setup:   $g" -ForegroundColor DarkGray }
        if (-not $i.usable) { Write-Host "    Fallback: native MxAgile (deterministic helpers -> bounded delegation -> targeted direct read)" -ForegroundColor DarkGray }
    }
    Write-Host ""
}

if ($ResolveOperatingMode) {
    Write-Host 'Operating Mode' -ForegroundColor Cyan
    Write-Host "  Mode:  $($operatingModeResult.mode)" -ForegroundColor White
    Write-Host "  Route: $($operatingModeResult.tool_authority.status) / $($operatingModeResult.tool_authority.preferred_route)" -ForegroundColor DarkGray
    Write-Host "  Note:  $($operatingModeResult.tool_authority.reason)" -ForegroundColor DarkGray
    Write-Host ''
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
