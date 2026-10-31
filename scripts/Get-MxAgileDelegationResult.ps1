[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectRoot,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^DELEGATION-[A-Za-z0-9._-]+$')]
    [string]$DelegationId
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
$rootPrefix = $ProjectRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
$resultPath = Join-Path $ProjectRoot ".concord/delegated-results/$DelegationId.json"
if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
    [ordered]@{ state = 'NOT_FOUND'; reusable = $false; delegation_id = $DelegationId; result = $null; stale_references = @() } |
        ConvertTo-Json -Depth 20 -Compress
    exit 0
}

$result = Get-Content -LiteralPath $resultPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
if ($result.schema_version -ne '1.0' -or $result.delegation_id -ne $DelegationId) {
    throw 'Delegation result identity or schema version is invalid.'
}
$allowedProperties = @(
    'schema_version', 'mission_id', 'delegation_id', 'completed_at', 'scope', 'source_fingerprints',
    'conclusion', 'findings', 'provenance', 'affected_ids', 'unknowns', 'conflicts',
    'decision_candidates', 'evidence_references', 'model_profile'
)
$unexpectedProperties = @($result.PSObject.Properties.Name | Where-Object { $_ -notin $allowedProperties })
if ($unexpectedProperties.Count -gt 0) { throw 'Delegation result contains fields outside its compact schema.' }
$resultText = $result | ConvertTo-Json -Depth 20 -Compress
if ($resultText -match '(?i)-----BEGIN [A-Z ]*PRIVATE KEY-----|\bAKIA[0-9A-Z]{16}\b|\b(?:gh[pousr]_[A-Za-z0-9]{20,}|sk-[A-Za-z0-9]{20,})\b|\bBearer\s+[A-Za-z0-9._~+/-]{16,}') {
    throw 'Delegation result contains a value matching a secret pattern.'
}
$reader = Join-Path $PSScriptRoot 'Read-MxAgileEpochCheckpoint.ps1'
$checkpoint = & $reader -ProjectRoot $ProjectRoot
if (-not $checkpoint.Valid -or $checkpoint.MissionId -ne $result.mission_id) {
    [ordered]@{
        state = if (-not $checkpoint.Valid) { 'CHECKPOINT_INVALID' } else { 'MISSION_MISMATCH' }
        reusable = $false
        mission_id = $result.mission_id
        delegation_id = $DelegationId
        stale_references = @()
        result = $null
    } | ConvertTo-Json -Depth 20 -Compress
    exit 0
}
$artifactMatch = [regex]::Match($checkpoint.RawYaml, '(?ms)^artifacts:[ \t]*(?:\r?\n)?(.*?)(?=^[^ \t#][^:\r\n]*:|\z)')
$expectedReference = ".concord/delegated-results/$DelegationId.json"
$hasArtifactId = $artifactMatch.Success -and $artifactMatch.Groups[1].Value -match "(?m)^[ \t]*-[ \t]+id:[ \t]*`"?$([regex]::Escape($DelegationId))`"?[ \t]*$"
$hasArtifactPath = $artifactMatch.Success -and $artifactMatch.Groups[1].Value -match "(?m)^[ \t]+path_or_reference:[ \t]*`"?$([regex]::Escape($expectedReference))`"?[ \t]*$"
if (-not ($hasArtifactId -and $hasArtifactPath)) {
    [ordered]@{
        state = 'NOT_REFERENCED'
        reusable = $false
        mission_id = $result.mission_id
        delegation_id = $DelegationId
        stale_references = @()
        result = $null
    } | ConvertTo-Json -Depth 20 -Compress
    exit 0
}
$staleReferences = @()
foreach ($fingerprint in @($result.source_fingerprints)) {
    if ([System.IO.Path]::IsPathRooted([string]$fingerprint.path) -or ([string]$fingerprint.path -match '(^|[\\/])\.\.([\\/]|$)')) {
        throw 'Delegation result contains a non-project-relative source path.'
    }
    $relativePath = ([string]$fingerprint.path).Replace('/', [System.IO.Path]::DirectorySeparatorChar)
    $fullPath = [System.IO.Path]::GetFullPath((Join-Path $ProjectRoot $relativePath))
    if (-not $fullPath.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'Delegation result source path resolves outside the project.'
    }
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        $staleReferences += [string]$fingerprint.path
        continue
    }
    $currentHash = (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($currentHash -ne $fingerprint.sha256) { $staleReferences += [string]$fingerprint.path }
}
$reusable = ($staleReferences.Count -eq 0)
[ordered]@{
    state = if ($reusable) { 'CURRENT' } else { 'STALE' }
    reusable = $reusable
    mission_id = $result.mission_id
    delegation_id = $result.delegation_id
    stale_references = @($staleReferences)
    result = $result
} | ConvertTo-Json -Depth 20 -Compress