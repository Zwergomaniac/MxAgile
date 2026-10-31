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
    'schema_version', 'mission_id', 'delegation_id', 'scope', 'references', 'conclusion',
    'findings', 'provenance', 'affected_ids', 'unknowns', 'conflicts', 'decision_candidates',
    'evidence_references', 'model_profile'
)
$actualProperties = @($input.PSObject.Properties.Name)
$unexpected = @($actualProperties | Where-Object { $_ -notin $allowedProperties })
$requiredProperties = @(
    'schema_version', 'mission_id', 'delegation_id', 'scope', 'references', 'conclusion',
    'findings', 'provenance', 'affected_ids', 'unknowns', 'conflicts', 'decision_candidates',
    'evidence_references', 'model_profile'
)
$missing = @($requiredProperties | Where-Object { $_ -notin $actualProperties })
if ($unexpected.Count -gt 0) { throw "Unexpected result properties: $($unexpected -join ', ')" }
if ($missing.Count -gt 0) { throw "Missing result properties: $($missing -join ', ')" }
if ($input.schema_version -ne '1.0') { throw "Unsupported delegation result schema version '$($input.schema_version)'" }
if ($input.delegation_id -notmatch '^DELEGATION-[A-Za-z0-9._-]+$') { throw 'Invalid delegation_id.' }
if ($input.model_profile -notin @('LIGHT', 'MID', 'HIGH', $null)) { throw 'Invalid model_profile.' }
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
    schema_version = '1.0'
    mission_id = [string]$input.mission_id
    delegation_id = [string]$input.delegation_id
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
    $emptyArtifacts = [regex]::Match($checkpointRaw, '(?m)^artifacts:\s*\[\]\s*$')
    if ($emptyArtifacts.Success) {
        $replacement = "artifacts:$lineEnding$($artifactYaml.TrimEnd())"
        $checkpointRaw = $checkpointRaw.Remove($emptyArtifacts.Index, $emptyArtifacts.Length).Insert($emptyArtifacts.Index, $replacement)
    } else {
        $artifactSection = [regex]::Match($checkpointRaw, '(?m)^artifacts:\s*$')
        if (-not $artifactSection.Success) { throw 'Active checkpoint has no artifacts section.' }
        $nextSection = [regex]::Match($checkpointRaw, '(?m)^[^\s#][^:\r\n]*:', $artifactSection.Index + $artifactSection.Length)
        $insertAt = if ($nextSection.Success) { $nextSection.Index } else { $checkpointRaw.Length }
        $checkpointRaw = $checkpointRaw.Insert($insertAt, "$($artifactYaml.TrimEnd())$lineEnding")
    }
    $checkpointTempPath = "$checkpointPath.$([Guid]::NewGuid().ToString('N')).tmp"
    [System.IO.File]::WriteAllText($checkpointTempPath, $checkpointRaw, $utf8NoBom)
    Move-Item -LiteralPath $checkpointTempPath -Destination $checkpointPath -Force
}

[ordered]@{
    state = 'COMPLETED'
    reusable = $true
    mission_id = $result.mission_id
    delegation_id = $result.delegation_id
    result_reference = $relativeResultPath
    sha256 = $resultHash
} | ConvertTo-Json -Depth 5 -Compress