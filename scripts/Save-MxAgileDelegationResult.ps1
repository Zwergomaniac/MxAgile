[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectRoot,

    [Parameter(Mandatory = $true)]
    [string]$InputFile
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
$rootPrefix = $ProjectRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
$input = Get-Content -LiteralPath $InputFile -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
$allowedProperties = @(
    'schema_version', 'mission_id', 'delegation_id', 'agent_type', 'scope', 'references', 'conclusion',
    'findings', 'provenance', 'affected_ids', 'unknowns', 'conflicts', 'decision_candidates',
    'evidence_references', 'model_profile', 'model_resolution', 'verdict_reference'
)
$actualProperties = @($input.PSObject.Properties.Name)
$unexpected = @($actualProperties | Where-Object { $_ -notin $allowedProperties })
$requiredProperties = @(
    'schema_version', 'mission_id', 'delegation_id', 'agent_type', 'scope', 'references', 'conclusion',
    'findings', 'provenance', 'affected_ids', 'unknowns', 'conflicts', 'decision_candidates',
    'evidence_references', 'model_profile', 'model_resolution'
)
$missing = @($requiredProperties | Where-Object { $_ -notin $actualProperties })
if ($unexpected.Count -gt 0) { throw "Unexpected result properties: $($unexpected -join ', ')" }
if ($missing.Count -gt 0) { throw "Missing result properties: $($missing -join ', ')" }
if ($input.schema_version -ne '1.1') { throw "Unsupported delegation result schema version '$($input.schema_version)'" }
if ($input.delegation_id -notmatch '^DELEGATION-[A-Za-z0-9._-]+$') { throw 'Invalid delegation_id.' }
if ([string]::IsNullOrWhiteSpace([string]$input.agent_type)) { throw 'agent_type must be non-empty.' }
if ($input.model_profile -notin @('LIGHT', 'MID', 'HIGH', $null)) { throw 'Invalid model_profile.' }
$resolution = $input.model_resolution
$resolutionProperties = @($resolution.PSObject.Properties.Name)
$requiredResolutionProperties = @('model_selection', 'profile_resolution', 'resolution', 'resolved_model', 'requested_reasoning_effort', 'fallback_used', 'fallback_reason')
$allowedResolutionProperties = $requiredResolutionProperties + @('escalation')
if (@($resolutionProperties | Where-Object { $_ -notin $allowedResolutionProperties }).Count -gt 0) { throw 'model_resolution contains unexpected properties.' }
if (@($requiredResolutionProperties | Where-Object { $_ -notin $resolutionProperties }).Count -gt 0) { throw 'model_resolution is incomplete.' }
if ($resolution.model_selection -notin @('supported', 'unsupported', 'unknown')) { throw 'Invalid model_selection status.' }
if ($resolution.profile_resolution -notin @('static_mapping', 'dynamic_capability', 'unknown', 'unsupported')) { throw 'Invalid profile_resolution status.' }
if ($resolution.resolution -notin @('static_mapping', 'dynamic_capability_request', 'explicit_model_request', 'fallback_available_model', 'not_requested')) { throw 'Invalid model resolution outcome.' }
if ($resolution.resolved_model -isnot [string] -and $null -ne $resolution.resolved_model) { throw 'resolved_model must be a string or null.' }
if ($resolution.requested_reasoning_effort -isnot [string] -and $null -ne $resolution.requested_reasoning_effort) { throw 'requested_reasoning_effort must be a string or null.' }
if ($resolution.fallback_used -isnot [bool]) { throw 'fallback_used must be a boolean.' }
if ($resolution.fallback_used -and [string]::IsNullOrWhiteSpace([string]$resolution.fallback_reason)) { throw 'A fallback requires a reason.' }
if (-not $resolution.fallback_used -and $null -ne $resolution.fallback_reason) { throw 'A non-fallback resolution must not report a fallback reason.' }
if ($resolution.resolution -in @('static_mapping', 'explicit_model_request') -and [string]::IsNullOrWhiteSpace([string]$resolution.resolved_model)) { throw 'Model selection requires a resolved model.' }
if ($resolutionProperties -contains 'escalation') {
    $e = $resolution.escalation
    $fields = @('main_profile', 'main_model', 'requested_child_profile', 'resolved_child_profile', 'requested_child_model', 'spawn_request_model', 'actual_model', 'actual_model_status', 'actual_model_source', 'escalation_policy', 'escalation_authority', 'authority_reference', 'decision', 'reason')
    if ($null -eq $e -or @($e.PSObject.Properties.Name).Count -ne $fields.Count -or @($fields | Where-Object { $_ -notin $e.PSObject.Properties.Name }).Count) { throw 'Escalation evidence must contain exactly the complete model/authority envelope.' }
    foreach ($field in @('main_profile', 'requested_child_profile', 'resolved_child_profile')) {
        if ($e.$field -notin @('LIGHT', 'MID', 'HIGH', $null)) { throw "Invalid escalation profile: $field" }
    }
    foreach ($field in @('main_model', 'requested_child_model', 'spawn_request_model', 'actual_model', 'actual_model_source', 'authority_reference', 'reason')) {
        if ($null -ne $e.$field -and $e.$field -isnot [string]) { throw "Escalation evidence $field must be a string or null." }
    }
    if ($e.escalation_policy -notin @('never', 'ask', 'autonomous')) { throw 'Invalid escalation policy.' }
    if ($e.escalation_authority -notin @('none', 'main_profile_ceiling', 'user_approval', 'explicit_user_model', 'autonomous_policy')) { throw 'Invalid escalation authority.' }
    if ($e.decision -notin @('allowed', 'limited') -or [string]::IsNullOrWhiteSpace($e.reason)) { throw 'A completed child cannot have blocked/pending or unaudited model authority.' }
    if ($e.actual_model_status -notin @('OBSERVED', 'NOT_OBSERVABLE')) { throw 'Invalid actual model observation status.' }
    if ($e.actual_model_status -eq 'NOT_OBSERVABLE' -and ($null -ne $e.actual_model -or $null -ne $e.actual_model_source)) { throw 'NOT_OBSERVABLE actual model must remain null, not guessed.' }
    if ($e.actual_model_status -eq 'OBSERVED' -and ([string]::IsNullOrWhiteSpace($e.actual_model) -or [string]::IsNullOrWhiteSpace($e.actual_model_source))) { throw 'Observed actual model requires child execution evidence.' }
    $authority = $e.escalation_authority
    if ($authority -in @('user_approval', 'explicit_user_model', 'autonomous_policy') -and [string]::IsNullOrWhiteSpace($e.authority_reference)) { throw 'Escalation authority requires a source reference.' }
    if ($authority -eq 'user_approval' -and $e.escalation_policy -ne 'ask') { throw 'User approval must bind an ask policy; explicit model instructions use explicit_user_model.' }
    if ($authority -eq 'autonomous_policy' -and $e.escalation_policy -ne 'autonomous') { throw 'Autonomous authority requires an autonomous policy.' }
    if ($authority -eq 'explicit_user_model' -and [string]::IsNullOrWhiteSpace($e.requested_child_model)) { throw 'Explicit user authority requires its requested model.' }
    $ranks = @{ LIGHT = 0; MID = 1; HIGH = 2 }
    if ($authority -eq 'none') { throw 'Completed child requires model-selection authority.' }
    if ($authority -ne 'explicit_user_model' -and ($null -eq $e.main_profile -or $null -eq $e.resolved_child_profile)) { throw 'Automatic child ceiling requires known main and resolved profiles.' }
    if ($null -ne $e.resolved_child_profile -and $input.model_profile -ne $e.resolved_child_profile) { throw 'Result profile contradicts resolved child profile.' }
    if ($null -ne $e.main_profile -and $null -ne $e.resolved_child_profile -and $ranks[$e.resolved_child_profile] -gt $ranks[$e.main_profile] -and $authority -notin @('user_approval', 'explicit_user_model', 'autonomous_policy')) { throw 'Child profile exceeds the main ceiling without escalation authority.' }
}
if ($null -eq $input.scope -or [string]::IsNullOrWhiteSpace($input.scope.summary) -or $null -eq $input.scope.paths) {
    throw 'scope must contain a non-empty summary and paths array.'
}

$reader = Join-Path $PSScriptRoot 'Read-MxAgileEpochCheckpoint.ps1'
if (-not (Test-Path -LiteralPath $reader -PathType Leaf)) { throw 'Checkpoint reader is unavailable.' }
$checkpoint = & $reader -ProjectRoot $ProjectRoot
if (-not $checkpoint.Valid) { throw "No valid active checkpoint: $($checkpoint.ConflictReason)" }
if ($checkpoint.MissionId -ne $input.mission_id) { throw 'Result mission_id does not match the active checkpoint.' }

$sourceFingerprints = @()
foreach ($reference in @($input.references)) {
    if ($null -eq $reference.path -or [System.IO.Path]::IsPathRooted([string]$reference.path)) {
        throw 'Reference paths must be project-relative.'
    }
    $relativePath = ([string]$reference.path).Replace('/', [System.IO.Path]::DirectorySeparatorChar)
    if ($relativePath -match '(^|[\\/])\.\.([\\/]|$)') { throw 'Reference paths cannot traverse outside the project.' }
    $fullPath = [System.IO.Path]::GetFullPath((Join-Path $ProjectRoot $relativePath))
    if (-not $fullPath.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'Reference paths must remain inside the project.'
    }
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { throw "Reference file not found: $($reference.path)" }
    $sourceFingerprints += [ordered]@{
        path = ([string]$reference.path).Replace('\\', '/')
        identity = if ($reference.identity) { [string]$reference.identity } else { '' }
        sha256 = (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}

$compactInput = $input | ConvertTo-Json -Depth 20 -Compress
$secretPatterns = @(
    '(?i)-----BEGIN [A-Z ]*PRIVATE KEY-----',
    '\bAKIA[0-9A-Z]{16}\b',
    '\b(?:gh[pousr]_[A-Za-z0-9]{20,}|sk-[A-Za-z0-9]{20,})\b',
    '(?i)\bBearer\s+[A-Za-z0-9._~+/-]{16,}',
    '(?i)\b(?:password|passwd|secret|api[_-]?key|access[_-]?token)\s*[:=]\s*\\?["'']?[A-Za-z0-9._~+/-]{16,}'
)
foreach ($pattern in $secretPatterns) {
    if ($compactInput -match $pattern) { throw 'Result contains a value matching a secret pattern; nothing was written.' }
}

$result = [ordered]@{
    schema_version = '1.1'
    mission_id = [string]$input.mission_id
    delegation_id = [string]$input.delegation_id
    agent_type = [string]$input.agent_type
    completed_at = (Get-Date).ToUniversalTime().ToString('o')
    scope = [ordered]@{ summary = [string]$input.scope.summary; paths = @($input.scope.paths) }
    source_fingerprints = @($sourceFingerprints)
    conclusion = [string]$input.conclusion
    findings = @($input.findings)
    provenance = @($input.provenance)
    affected_ids = @($input.affected_ids)
    unknowns = @($input.unknowns)
    conflicts = @($input.conflicts)
    decision_candidates = @($input.decision_candidates)
    evidence_references = @($input.evidence_references)
    model_profile = $input.model_profile
    model_resolution = $input.model_resolution
}

# A child spawned through the control plane has a canonical handoff; its result is never accepted unchecked.
$handoffRelative = ".concord/delegation-handoffs/$($input.delegation_id).json"
if (Test-Path -LiteralPath (Join-Path $ProjectRoot $handoffRelative) -PathType Leaf) {
    if ($resolutionProperties -contains 'escalation') {
        $parentHandoff = Get-Content -LiteralPath (Join-Path $ProjectRoot $handoffRelative) -Raw -Encoding UTF8 | ConvertFrom-Json
        $parentResolution = $parentHandoff.PSObject.Properties['model_resolution']
        $parentEscalation = if ($parentResolution -and $parentResolution.Value) { $parentResolution.Value.PSObject.Properties['escalation'] } else { $null }
        if (-not $parentEscalation) { throw 'Parent model authority is NOT_OBSERVABLE; a child cannot manufacture escalation evidence.' }
        foreach ($field in @('main_profile', 'main_model', 'requested_child_profile', 'resolved_child_profile', 'requested_child_model', 'escalation_policy', 'escalation_authority', 'authority_reference', 'decision', 'reason')) {
            if ($resolution.escalation.$field -cne $parentEscalation.Value.$field) { throw "Child result contradicts parent model authority: $field" }
        }
    }
    $acceptor = @(
        (Join-Path $PSScriptRoot 'control-plane/child_contract.py'),
        (Join-Path (Split-Path -Parent $PSScriptRoot) 'experiments/control-plane/child_contract.py')
    ) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
    $python = Get-Command python -ErrorAction SilentlyContinue
    if (-not $python) { $python = Get-Command python3 -ErrorAction SilentlyContinue }
    $verdictReference = if ($actualProperties -contains 'verdict_reference') { [string]$input.verdict_reference } else { '' }
    $classified = $null
    if ($acceptor -and $python) {
        $acceptArgs = @('-B', $acceptor, 'accept', '--project-root', $ProjectRoot, '--handoff', $handoffRelative)
        if ($verdictReference) { $acceptArgs += @('--verdict', $verdictReference) }
        $PSNativeCommandUseErrorActionPreference = $false
        $raw = & $python.Source @acceptArgs 2>$null
        try { $classified = ($raw -join "`n") | ConvertFrom-Json -ErrorAction Stop } catch { $classified = $null }
    }
    if ($null -eq $classified -or [string]::IsNullOrWhiteSpace([string]$classified.status)) {
        $classified = [pscustomobject]@{ status = 'NEEDS_HUMAN'; findings = @([pscustomobject]@{ code = 'ACCEPTANCE_UNAVAILABLE' }); gate = $null; event = [pscustomobject]@{ run_id = $null } }
    }
    $result['acceptance'] = [ordered]@{
        status = [string]$classified.status
        gate_result = if ($classified.gate) { [string]$classified.gate.gate_result } else { $null }
        finding_codes = @($classified.findings | ForEach-Object { [string]$_.code })
        run_id = $classified.event.run_id
        handoff_reference = $handoffRelative
        verdict_reference = if ($verdictReference) { $verdictReference } else { $null }
    }
}
$resultJson = $result | ConvertTo-Json -Depth 20
$resultJson = $resultJson + "`n"

$resultDir = Join-Path $ProjectRoot '.concord/delegated-results'
New-Item -ItemType Directory -Path $resultDir -Force | Out-Null
$resultPath = Join-Path $resultDir "$($input.delegation_id).json"
$tempPath = "$resultPath.tmp"
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($tempPath, $resultJson, $utf8NoBom)
Move-Item -LiteralPath $tempPath -Destination $resultPath -Force

$relativeResultPath = ".concord/delegated-results/$($input.delegation_id).json"
$resultHash = (Get-FileHash -LiteralPath $resultPath -Algorithm SHA256).Hash.ToLowerInvariant()
$artifactYaml = @"
  - id: "$($input.delegation_id)"
    type: delegated_result
    path_or_reference: "$relativeResultPath"
    integrity_metadata:
      sha256_prefix: "$($resultHash.Substring(0, 8))"
"@
$checkpointPath = $checkpoint.Path
$checkpointRaw = $checkpoint.RawYaml
if ($checkpointRaw -notmatch "(?m)^\s*-\s+id:\s*`"?$([regex]::Escape([string]$input.delegation_id))`"?\s*$") {
    $lineEnding = if ($checkpointRaw.Contains("`r`n")) { "`r`n" } else { "`n" }
    $artifactYaml = ($artifactYaml -replace "`r?`n", $lineEnding)
    $emptyArtifacts = [regex]::Match($checkpointRaw, '(?m)^artifacts:[ \t]*\[\][ \t]*(?=\r?$)')
    if ($emptyArtifacts.Success) {
        $replacement = "artifacts:$lineEnding$($artifactYaml.TrimEnd())"
        $checkpointRaw = $checkpointRaw.Remove($emptyArtifacts.Index, $emptyArtifacts.Length).Insert($emptyArtifacts.Index, $replacement)
    } else {
        $artifactSection = [regex]::Match($checkpointRaw, '(?m)^artifacts:[ \t]*(?=\r?$)')
        if (-not $artifactSection.Success) { throw 'Active checkpoint has no artifacts section.' }
        $nextSection = [regex]::new('(?m)^[^\s#][^:\r\n]*:').Match($checkpointRaw, $artifactSection.Index + $artifactSection.Length)
        $insertAt = if ($nextSection.Success) { $nextSection.Index } else { $checkpointRaw.Length }
        $checkpointRaw = $checkpointRaw.Insert($insertAt, "$($artifactYaml.TrimEnd())$lineEnding")
    }
    $checkpointTempPath = "$checkpointPath.$([Guid]::NewGuid().ToString('N')).tmp"
    [System.IO.File]::WriteAllText($checkpointTempPath, $checkpointRaw, $utf8NoBom)
    Move-Item -LiteralPath $checkpointTempPath -Destination $checkpointPath -Force
}

[ordered]@{
    state = 'COMPLETED'
    reusable = (-not $result.Contains('acceptance')) -or $result['acceptance'].status -eq 'ACCEPTED'
    acceptance = if ($result.Contains('acceptance')) { $result['acceptance'].status } else { 'NOT_REQUIRED' }
    mission_id = $result.mission_id
    delegation_id = $result.delegation_id
    result_reference = $relativeResultPath
    sha256 = $resultHash
} | ConvertTo-Json -Depth 5 -Compress