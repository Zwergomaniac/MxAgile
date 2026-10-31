$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$RepoRoot = Split-Path -Parent $PSScriptRoot
$Writer = Join-Path $RepoRoot 'scripts/Write-MxAgileEpochCheckpoint.ps1'
$Save = Join-Path $RepoRoot 'scripts/Save-MxAgileDelegationResult.ps1'
$Get = Join-Path $RepoRoot 'scripts/Get-MxAgileDelegationResult.ps1'
$PassCount = 0
$FailCount = 0

function Assert-True {
    param([string]$Name, [bool]$Condition, [string]$Message = '')
    if ($Condition) { Write-Host "PASS: $Name" -ForegroundColor Green; $script:PassCount++ }
    else { Write-Host "FAIL: $Name -- $Message" -ForegroundColor Red; $script:FailCount++ }
}

function Write-JsonFile {
    param([string]$Path, $Value)
    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    [System.IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 20) + "`n", [System.Text.UTF8Encoding]::new($false))
}

$root = Join-Path $env:TEMP "mxagile-delegation-result-$(New-Guid)"
try {
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    & git -C $root init -q
    & git -C $root config user.email 'test@mxagile.test'
    & git -C $root config user.name 'MxAgile Test'
    $source = Join-Path $root 'requirements/REQ-001.yml'
    New-Item -ItemType Directory -Path (Split-Path -Parent $source) -Force | Out-Null
    [System.IO.File]::WriteAllText($source, "id: REQ-001`nrevision: 7`n", [System.Text.UTF8Encoding]::new($false))
    & $Writer -ProjectRoot $root -MissionId 'MISSION-TEST-001' -MissionObjective 'Test result reuse' `
        -MissionStatus active -CurrentPhase implementing -EpochId EPOCH-001 | Out-Null
    $checkpointPath = Join-Path $root '.concord/context-epoch.yaml'
    $checkpointText = Get-Content $checkpointPath -Raw
    $lineEnding = if ($checkpointText.Contains("`r`n")) { "`r`n" } else { "`n" }
    $checkpointText = $checkpointText.Replace("scope:$lineEnding", "scope:$lineEnding  framework: `".mxagile/`"$lineEnding")
    $checkpointText = $checkpointText.Replace('open_gates: []', "open_gates:$lineEnding  - gate_id: GATE-001$lineEnding    status: open")
    $checkpointText = $checkpointText.Replace('user_overrides: []', "user_overrides:$lineEnding  - instruction: `"preserve this checkpoint state`"$lineEnding    still_active: true")
    $checkpointText = $checkpointText.Replace("context:$lineEnding", "context:$lineEnding  transition_state: CHECKPOINT_VALIDATED$lineEnding")
    [System.IO.File]::WriteAllText($checkpointPath, $checkpointText, [System.Text.UTF8Encoding]::new($false))

    $input = [ordered]@{
        schema_version = '1.0'
        mission_id = 'MISSION-TEST-001'
        delegation_id = 'DELEGATION-001'
        scope = [ordered]@{ summary = 'Classify REQ-001'; paths = @('requirements/REQ-001.yml') }
        references = @([ordered]@{ path = 'requirements/REQ-001.yml'; identity = 'REQ-001@7' })
        conclusion = 'The requirement is internally consistent.'
        findings = @('No conflicts found.')
        provenance = @('requirements/REQ-001.yml, revision 7')
        affected_ids = @('REQ-001')
        unknowns = @()
        conflicts = @()
        decision_candidates = @()
        evidence_references = @('requirements/REQ-001.yml')
        model_profile = 'MID'
    }
    $inputPath = Join-Path $root 'handoff.json'
    Write-JsonFile $inputPath $input
    $saved = (& $Save -ProjectRoot $root -InputFile $inputPath | ConvertFrom-Json)
    Assert-True 'Result is saved with a durable reference' ($saved.state -eq 'COMPLETED' -and (Test-Path (Join-Path $root $saved.result_reference))) 'Save result missing'
    $checkpoint = Get-Content (Join-Path $root '.concord/context-epoch.yaml') -Raw
    Assert-True 'Checkpoint links the compact result' ($checkpoint -match 'DELEGATION-001' -and $checkpoint -match 'delegated-results') 'Checkpoint reference missing'
    Assert-True 'Adding a result reference preserves unrelated lifecycle state' `
        (($checkpoint -match 'framework: ".mxagile/"') -and ($checkpoint -match 'GATE-001') -and ($checkpoint -match 'preserve this checkpoint state') -and ($checkpoint -match 'transition_state: CHECKPOINT_VALIDATED')) 'Checkpoint fields were rewritten'

    & $Writer -ProjectRoot $root -MissionId 'MISSION-TEST-001' -MissionObjective 'Test result reuse' `
        -MissionStatus active -CurrentPhase implementing -EpochId EPOCH-001 -PreserveEvidence -WriteHandoffCopy | Out-Null
    $handoff = Get-Content (Join-Path $root 'planning/lifecycle/context-epoch.yaml') -Raw
    Assert-True 'Compaction checkpoint rewrite retains the result reference' ($handoff -match 'DELEGATION-001' -and $handoff -match 'delegated-results') 'Compaction dropped result reference'

    $current = (& $Get -ProjectRoot $root -DelegationId 'DELEGATION-001' | ConvertFrom-Json)
    Assert-True 'Matching source fingerprints permit compact result reuse' ($current.state -eq 'CURRENT' -and $current.reusable -and $current.result.mission_id -eq 'MISSION-TEST-001') 'Current result not reusable'
    $linkedCheckpoint = Get-Content (Join-Path $root '.concord/context-epoch.yaml') -Raw
    & $Writer -ProjectRoot $root -MissionId 'MISSION-TEST-001' -MissionObjective 'Test result reuse' `
        -MissionStatus active -CurrentPhase implementing -EpochId EPOCH-001 | Out-Null
    $unlinked = (& $Get -ProjectRoot $root -DelegationId 'DELEGATION-001' | ConvertFrom-Json)
    Assert-True 'Unreferenced result is not reusable after checkpoint rollover' `
        ($unlinked.state -eq 'NOT_REFERENCED' -and -not $unlinked.reusable) 'Unreferenced result was accepted'
    [System.IO.File]::WriteAllText((Join-Path $root '.concord/context-epoch.yaml'), $linkedCheckpoint, [System.Text.UTF8Encoding]::new($false))
    & $Writer -ProjectRoot $root -MissionId 'MISSION-TEST-002' -MissionObjective 'Different active mission' `
        -MissionStatus active -CurrentPhase implementing -EpochId EPOCH-001 -PreserveEvidence | Out-Null
    $wrongMission = (& $Get -ProjectRoot $root -DelegationId 'DELEGATION-001' | ConvertFrom-Json)
    Assert-True 'Result from another mission is not reusable' ($wrongMission.state -eq 'MISSION_MISMATCH' -and -not $wrongMission.reusable) 'Mission mismatch was accepted'
    & $Writer -ProjectRoot $root -MissionId 'MISSION-TEST-001' -MissionObjective 'Test result reuse' `
        -MissionStatus active -CurrentPhase implementing -EpochId EPOCH-001 -PreserveEvidence | Out-Null
    [System.IO.File]::AppendAllText($source, "updated: true`n", [System.Text.UTF8Encoding]::new($false))
    $stale = (& $Get -ProjectRoot $root -DelegationId 'DELEGATION-001' | ConvertFrom-Json)
    Assert-True 'Changed source fingerprint blocks reuse' ($stale.state -eq 'STALE' -and -not $stale.reusable -and $stale.stale_references -contains 'requirements/REQ-001.yml') 'Stale result was reusable'

    $resultPath = Join-Path $root '.concord/delegated-results/DELEGATION-001.json'
    $tampered = Get-Content $resultPath -Raw | ConvertFrom-Json
    $tampered.source_fingerprints[0].path = '../outside.txt'
    Write-JsonFile $resultPath $tampered
    $rejectedTamper = $false
    try { & $Get -ProjectRoot $root -DelegationId 'DELEGATION-001' | Out-Null } catch { $rejectedTamper = $true }
    Assert-True 'Tampered result cannot read fingerprint paths outside the project' $rejectedTamper 'Out-of-project result path was read'

    $unsafe = $input | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    $unsafe.delegation_id = 'DELEGATION-002'
    $unsafe.conclusion = 'password="long-secret-value-should-not-be-saved"'
    Write-JsonFile $inputPath $unsafe
    $rejectedSecret = $false
    try { & $Save -ProjectRoot $root -InputFile $inputPath | Out-Null } catch { $rejectedSecret = $true }
    Assert-True 'Secret-like handoff content is rejected' $rejectedSecret 'Secret-like result was accepted'

    $unsafe.delegation_id = 'DELEGATION-003'
    $unsafe.conclusion = 'bounded scope traversal probe'
    $unsafe.references = @([ordered]@{ path = '../outside.txt'; identity = 'outside' })
    Write-JsonFile $inputPath $unsafe
    $rejectedTraversal = $false
    try { & $Save -ProjectRoot $root -InputFile $inputPath | Out-Null } catch { $rejectedTraversal = $true }
    Assert-True 'Out-of-project references are rejected' $rejectedTraversal 'Traversal reference was accepted'
} finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "PASS: $PassCount; FAIL: $FailCount"
if ($FailCount -gt 0) { exit 1 }