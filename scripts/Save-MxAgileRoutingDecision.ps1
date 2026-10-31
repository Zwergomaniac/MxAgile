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
    'schema_version', 'mission_id', 'decision_id', 'session_identity', 'work_package', 'requested_agent_type', 'work_class',
    'scope', 'artifact_count', 'semantic', 'deterministic', 'capability_state', 'requested_profile',
    'route', 'reason', 'fallback_reason', 'delegation_attempted', 'spawn_outcome', 'delegation_id',
    'result_reference', 'main_consumed', 'compaction_occurred', 'result_reused', 'stale_result_rejected',
    'batch_restarted', 'references'
)
$actualProperties = @($input.PSObject.Properties.Name)
$unexpected = @($actualProperties | Where-Object { $_ -notin $allowedProperties })
$missing = @($allowedProperties | Where-Object { $_ -notin $actualProperties })
if ($unexpected.Count -gt 0) { throw "Unexpected routing decision properties: $($unexpected -join ', ')" }
if ($missing.Count -gt 0) { throw "Missing routing decision properties: $($missing -join ', ')" }
if ($input.schema_version -ne '1.0') { throw "Unsupported routing decision schema version '$($input.schema_version)'" }
if ($input.decision_id -notmatch '^ROUTE-[A-Za-z0-9._-]+$') { throw 'Invalid decision_id.' }
if ($input.work_class -notin @('deterministic', 'raw_source_retrieval', 'bounded_semantic', 'integration', 'lifecycle', 'other')) { throw 'Invalid work_class.' }
if ($input.capability_state -notin @('supported', 'unsupported', 'unknown', 'not_applicable')) { throw 'Invalid capability_state.' }
if ($input.requested_profile -notin @('LIGHT', 'MID', 'HIGH', $null)) { throw 'Invalid requested_profile.' }
if ($input.route -notin @('DELEGATE', 'MAIN_AGENT', 'CONTEXT_MODE', 'HELPER', 'FALLBACK')) { throw 'Invalid route.' }
if ($input.spawn_outcome -notin @('not_attempted', 'pending', 'started', 'failed', 'completed')) { throw 'Invalid spawn_outcome.' }
if ([string]::IsNullOrWhiteSpace([string]$input.work_package) -or [string]::IsNullOrWhiteSpace([string]$input.reason)) { throw 'work_package and reason must be non-empty.' }
if ([int]$input.artifact_count -lt 0) { throw 'artifact_count cannot be negative.' }
if ($input.semantic -isnot [bool] -or $input.deterministic -isnot [bool] -or $input.delegation_attempted -isnot [bool]) { throw 'Routing classifications and delegation_attempted must be booleans.' }
if ($input.route -eq 'DELEGATE') {
    if ($input.work_class -ne 'bounded_semantic' -or -not $input.semantic -or $input.deterministic) { throw 'DELEGATE requires bounded semantic, non-deterministic work.' }
    if ($input.capability_state -ne 'supported') { throw 'DELEGATE requires current-session capability state supported.' }
    if ($null -eq $input.requested_profile) { throw 'DELEGATE requires a requested model profile.' }
    if ([string]::IsNullOrWhiteSpace([string]$input.requested_agent_type)) { throw 'DELEGATE requires a requested agent type.' }
    if ($input.spawn_outcome -eq 'not_attempted') { throw 'A DELEGATE decision must be pending or record an actual spawn outcome.' }
} elseif ($input.route -eq 'FALLBACK') {
    if ([string]::IsNullOrWhiteSpace([string]$input.fallback_reason)) { throw 'FALLBACK requires a concrete fallback_reason.' }
    if ($input.delegation_attempted -and $input.spawn_outcome -ne 'failed') { throw 'A fallback after dispatch requires an observed failed spawn.' }
    if (-not $input.delegation_attempted -and $input.spawn_outcome -ne 'not_attempted') { throw 'A fallback without dispatch cannot claim a spawn outcome.' }
} elseif ($input.delegation_attempted -or $input.spawn_outcome -ne 'not_attempted') {
    throw 'Non-delegation routes cannot claim a spawn attempt.'
}
if ($input.spawn_outcome -in @('started', 'failed', 'completed') -and -not $input.delegation_attempted) { throw 'A completed spawn outcome requires delegation_attempted=true.' }
if ($input.result_reused -and -not $input.compaction_occurred) { throw 'result_reused requires compaction_occurred=true.' }
if ($input.main_consumed -and ([string]::IsNullOrWhiteSpace([string]$input.result_reference) -or $input.spawn_outcome -ne 'completed')) { throw 'Main consumption requires a completed delegation result reference.' }
if ($input.result_reused -and -not $input.main_consumed) { throw 'A reused result must be marked consumed by the main agent.' }
if ($null -eq $input.scope -or [string]::IsNullOrWhiteSpace([string]$input.scope.summary) -or $null -eq $input.scope.paths) { throw 'scope must contain a non-empty summary and paths array.' }

$reader = Join-Path $PSScriptRoot 'Read-MxAgileEpochCheckpoint.ps1'
if (-not (Test-Path -LiteralPath $reader -PathType Leaf)) { throw 'Checkpoint reader is unavailable.' }
$checkpoint = & $reader -ProjectRoot $ProjectRoot
if (-not $checkpoint.Valid) { throw "No valid active checkpoint: $($checkpoint.ConflictReason)" }
if ($checkpoint.MissionId -ne $input.mission_id) { throw 'Routing decision mission_id does not match the active checkpoint.' }

$sourceFingerprints = @()
foreach ($reference in @($input.references)) {
    if ($null -eq $reference.path -or [System.IO.Path]::IsPathRooted([string]$reference.path)) { throw 'Reference paths must be project-relative.' }
    $relativePath = ([string]$reference.path).Replace('/', [System.IO.Path]::DirectorySeparatorChar)
    if ($relativePath -match '(^|[\\/])\.\.([\\/]|$)') { throw 'Reference paths cannot traverse outside the project.' }
    $fullPath = [System.IO.Path]::GetFullPath((Join-Path $ProjectRoot $relativePath))
    if (-not $fullPath.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) { throw 'Reference paths must remain inside the project.' }
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
foreach ($pattern in $secretPatterns) { if ($compactInput -match $pattern) { throw 'Routing decision contains a value matching a secret pattern; nothing was written.' } }

$resultDir = Join-Path $ProjectRoot '.concord/routing-decisions'
New-Item -ItemType Directory -Path $resultDir -Force | Out-Null
$resultPath = Join-Path $resultDir "$($input.decision_id).json"
$recordedAt = (Get-Date).ToUniversalTime().ToString('o')
$updatedAt = $null
if (Test-Path -LiteralPath $resultPath -PathType Leaf) {
    $previous = Get-Content -LiteralPath $resultPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    foreach ($field in @('mission_id', 'session_identity', 'work_package', 'requested_agent_type', 'work_class', 'semantic', 'deterministic', 'capability_state', 'requested_profile', 'artifact_count')) {
        if ([string]$previous.$field -ne [string]$input.$field) { throw "Routing decision update changed immutable field '$field'." }
    }
    if (($previous.scope | ConvertTo-Json -Depth 10 -Compress) -ne ($input.scope | ConvertTo-Json -Depth 10 -Compress)) { throw 'Routing decision update changed immutable scope.' }
    if ($previous.route -ne $input.route -and -not ($previous.route -eq 'DELEGATE' -and $input.route -eq 'FALLBACK' -and $input.spawn_outcome -eq 'failed')) {
        throw 'Routing decision route may only transition from DELEGATE to FALLBACK after a failed spawn.'
    }
    if ($previous.delegation_attempted -and -not $input.delegation_attempted) { throw 'Routing decision cannot erase a previous spawn attempt.' }
    $validOutcomes = switch ($previous.spawn_outcome) {
        'not_attempted' { @('not_attempted', 'pending') }
        'pending' { @('pending', 'started', 'failed') }
        'started' { @('started', 'completed', 'failed') }
        'failed' { @('failed') }
        'completed' { @('completed') }
    }
    if ($input.spawn_outcome -notin $validOutcomes) { throw 'Routing decision spawn outcome cannot move backward.' }
    $sourceFingerprints = @($previous.source_fingerprints)
    $recordedAt = [string]$previous.recorded_at
    $updatedAt = (Get-Date).ToUniversalTime().ToString('o')
}

$result = [ordered]@{
    schema_version = '1.0'
    mission_id = [string]$input.mission_id
    decision_id = [string]$input.decision_id
    recorded_at = $recordedAt
    session_identity = $input.session_identity
    work_package = [string]$input.work_package
    requested_agent_type = $input.requested_agent_type
    work_class = [string]$input.work_class
    scope = [ordered]@{ summary = [string]$input.scope.summary; paths = @($input.scope.paths) }
    artifact_count = [int]$input.artifact_count
    semantic = [bool]$input.semantic
    deterministic = [bool]$input.deterministic
    capability_state = [string]$input.capability_state
    requested_profile = $input.requested_profile
    route = [string]$input.route
    reason = [string]$input.reason
    fallback_reason = $input.fallback_reason
    delegation_attempted = [bool]$input.delegation_attempted
    spawn_outcome = [string]$input.spawn_outcome
    delegation_id = $input.delegation_id
    result_reference = $input.result_reference
    main_consumed = [bool]$input.main_consumed
    compaction_occurred = [bool]$input.compaction_occurred
    result_reused = [bool]$input.result_reused
    stale_result_rejected = [bool]$input.stale_result_rejected
    batch_restarted = [bool]$input.batch_restarted
    source_fingerprints = @($sourceFingerprints)
}
if ($updatedAt) { $result['updated_at'] = $updatedAt }
$resultJson = ($result | ConvertTo-Json -Depth 20) + "`n"
$tempPath = "$resultPath.$([Guid]::NewGuid().ToString('N')).tmp"
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($tempPath, $resultJson, $utf8NoBom)
Move-Item -LiteralPath $tempPath -Destination $resultPath -Force

$relativeResultPath = ".concord/routing-decisions/$($input.decision_id).json"
$checkpointRaw = $checkpoint.RawYaml
if ($checkpointRaw -notmatch "(?m)^\s*-\s+id:\s*`"?$([regex]::Escape([string]$input.decision_id))`"?\s*$") {
    $artifactYaml = @"
  - id: "$($input.decision_id)"
    type: routing_decision
    path_or_reference: "$relativeResultPath"
"@
    $lineEnding = if ($checkpointRaw.Contains("`r`n")) { "`r`n" } else { "`n" }
    $emptyArtifacts = [regex]::Match($checkpointRaw, '(?m)^artifacts:\s*\[\]\s*$')
    if ($emptyArtifacts.Success) {
        $replacement = "artifacts:$lineEnding$($artifactYaml.TrimEnd())"
        $checkpointRaw = $checkpointRaw.Remove($emptyArtifacts.Index, $emptyArtifacts.Length).Insert($emptyArtifacts.Index, $replacement)
    } else {
        $artifactSection = [regex]::Match($checkpointRaw, '(?m)^artifacts:\s*$')
        if (-not $artifactSection.Success) { throw 'Active checkpoint has no artifacts section.' }
        $nextSection = [regex]::new('(?m)^[^\s#][^:\r\n]*:').Match($checkpointRaw, $artifactSection.Index + $artifactSection.Length)
        $insertAt = if ($nextSection.Success) { $nextSection.Index } else { $checkpointRaw.Length }
        $checkpointRaw = $checkpointRaw.Insert($insertAt, "$($artifactYaml.TrimEnd())$lineEnding")
    }
    $checkpointTempPath = "$($checkpoint.Path).$([Guid]::NewGuid().ToString('N')).tmp"
    [System.IO.File]::WriteAllText($checkpointTempPath, $checkpointRaw, $utf8NoBom)
    Move-Item -LiteralPath $checkpointTempPath -Destination $checkpoint.Path -Force
}

[ordered]@{
    state = 'RECORDED'
    mission_id = $result.mission_id
    decision_id = $result.decision_id
    route = $result.route
    decision_reference = $relativeResultPath
} | ConvertTo-Json -Depth 5 -Compress