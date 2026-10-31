$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$RepoRoot = Split-Path -Parent $PSScriptRoot
$Writer = Join-Path $RepoRoot 'scripts/Write-MxAgileEpochCheckpoint.ps1'
$Save = Join-Path $RepoRoot 'scripts/Save-MxAgileDelegationResult.ps1'
$Get = Join-Path $RepoRoot 'scripts/Get-MxAgileDelegationResult.ps1'
$RoutingSave = Join-Path $RepoRoot 'scripts/Save-MxAgileRoutingDecision.ps1'
$PassCount = 0
$FailCount = 0
$script:SpawnCount = 0

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

function Invoke-FixtureHarnessSpawn {
    param($Decision, [switch]$FailSpawn)
    if ($Decision.requested_agent_type -ne 'semantic-review' -or $Decision.requested_profile -ne 'MID' -or $Decision.artifact_count -ne 20) {
        throw 'Fixture spawn received an unexpected agent type or profile.'
    }
    $script:SpawnCount++
    return [ordered]@{ state = if ($FailSpawn) { 'failed' } else { 'started' }; agent_type = $Decision.requested_agent_type; requested_profile = $Decision.requested_profile }
}

function Copy-RoutingDecision {
    param($Decision)
    $copy = [ordered]@{}
    foreach ($key in $Decision.Keys) { $copy[$key] = $Decision[$key] }
    return $copy
}

$root = Join-Path $env:TEMP "mxagile-delegation-result-$(New-Guid)"
try {
    $fixture = Get-Content (Join-Path $RepoRoot 'tests/fixtures/delegation/semantic-compatibility.json') -Raw | ConvertFrom-Json
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    & git -C $root init -q
    & git -C $root config user.email 'test@mxagile.test'
    & git -C $root config user.name 'MxAgile Test'
    $source = Join-Path $root 'requirements/REQ-001.yml'
    New-Item -ItemType Directory -Path (Split-Path -Parent $source) -Force | Out-Null
    [System.IO.File]::WriteAllText($source, "id: REQ-001`nrevision: 7`n", [System.Text.UTF8Encoding]::new($false))
    $routePaths = @('requirements/REQ-001.yml')
    for ($number = 2; $number -le 20; $number++) {
        $requirementId = 'REQ-{0:D3}' -f $number
        $requirementPath = "requirements/$requirementId.yml"
        [System.IO.File]::WriteAllText((Join-Path $root $requirementPath), "id: $requirementId`nrevision: 1`n", [System.Text.UTF8Encoding]::new($false))
        $routePaths += $requirementPath
    }
    $routeReferences = @($routePaths | ForEach-Object {
        [ordered]@{ path = $_; identity = ('{0}@1' -f [System.IO.Path]::GetFileNameWithoutExtension($_)) }
    })
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

    $routeDecision = [ordered]@{
        schema_version = '1.0'
        mission_id = 'MISSION-TEST-001'
        decision_id = 'ROUTE-SEMANTIC-001'
        session_identity = 'fixture-session-001'
        work_package = 'Requirements semantic review'
        requested_agent_type = 'semantic-review'
        work_class = 'bounded_semantic'
        scope = [ordered]@{ summary = 'Review the bounded requirement cluster'; paths = $routePaths }
        artifact_count = 20
        semantic = $true
        deterministic = $false
        capability_state = 'supported'
        requested_profile = 'MID'
        route = 'DELEGATE'
        reason = 'Independent bounded semantic review with a compact result.'
        fallback_reason = $null
        delegation_attempted = $false
        spawn_outcome = 'pending'
        delegation_id = 'DELEGATION-001'
        result_reference = $null
        main_consumed = $false
        compaction_occurred = $false
        result_reused = $false
        stale_result_rejected = $false
        batch_restarted = $false
        references = $routeReferences
    }
    $routeInputPath = Join-Path $root 'routing-decision.json'

    $helperRoute = Copy-RoutingDecision $routeDecision
    $helperRoute.decision_id = 'ROUTE-DETERMINISTIC-001'
    $helperRoute.work_package = 'YAML syntax repair'
    $helperRoute.requested_agent_type = $null
    $helperRoute.work_class = 'deterministic'
    $helperRoute.scope = [ordered]@{ summary = 'Repair one deterministic syntax issue'; paths = @('requirements/REQ-001.yml') }
    $helperRoute.artifact_count = 1
    $helperRoute.semantic = $false
    $helperRoute.deterministic = $true
    $helperRoute.capability_state = 'not_applicable'
    $helperRoute.requested_profile = $null
    $helperRoute.route = 'HELPER'
    $helperRoute.reason = 'A deterministic helper is sufficient.'
    $helperRoute.delegation_attempted = $false
    $helperRoute.spawn_outcome = 'not_attempted'
    $helperRoute.delegation_id = $null
    $helperRoute.result_reference = $null
    $helperRoute.main_consumed = $false
    $helperRoute.compaction_occurred = $false
    $helperRoute.result_reused = $false
    $helperRoute.stale_result_rejected = $false
    $helperRoute.batch_restarted = $false
    $helperRoute.references = @([ordered]@{ path = 'requirements/REQ-001.yml'; identity = 'REQ-001@7' })
    Write-JsonFile $routeInputPath $helperRoute
    & $RoutingSave -ProjectRoot $root -InputFile $routeInputPath | Out-Null
    $savedHelperRoute = Get-Content (Join-Path $root '.concord/routing-decisions/ROUTE-DETERMINISTIC-001.json') -Raw | ConvertFrom-Json
    Assert-True 'R1 deterministic syntax work is persisted as helper-only without a spawn' `
        ($savedHelperRoute.route -eq 'HELPER' -and -not $savedHelperRoute.delegation_attempted -and $savedHelperRoute.spawn_outcome -eq 'not_attempted') 'Deterministic work was delegated'

    $rawSourcePath = Join-Path $root 'large-source.md'
    [System.IO.File]::WriteAllText($rawSourcePath, 'An anonymized large raw source placeholder.', [System.Text.UTF8Encoding]::new($false))
    $contextRoute = Copy-RoutingDecision $routeDecision
    $contextRoute.decision_id = 'ROUTE-RAW-SOURCE-001'
    $contextRoute.work_package = 'Raw-source retrieval'
    $contextRoute.requested_agent_type = $null
    $contextRoute.work_class = 'raw_source_retrieval'
    $contextRoute.scope = [ordered]@{ summary = 'Retrieve a bounded finding from the raw source'; paths = @('large-source.md') }
    $contextRoute.artifact_count = 1
    $contextRoute.semantic = $false
    $contextRoute.deterministic = $false
    $contextRoute.capability_state = 'not_applicable'
    $contextRoute.requested_profile = $null
    $contextRoute.route = 'CONTEXT_MODE'
    $contextRoute.reason = 'Raw-source retrieval is a separate context operation.'
    $contextRoute.delegation_attempted = $false
    $contextRoute.spawn_outcome = 'not_attempted'
    $contextRoute.delegation_id = $null
    $contextRoute.result_reference = $null
    $contextRoute.main_consumed = $false
    $contextRoute.compaction_occurred = $false
    $contextRoute.result_reused = $false
    $contextRoute.stale_result_rejected = $false
    $contextRoute.batch_restarted = $false
    $contextRoute.references = @([ordered]@{ path = 'large-source.md'; identity = 'RAW-001' })
    Write-JsonFile $routeInputPath $contextRoute
    & $RoutingSave -ProjectRoot $root -InputFile $routeInputPath | Out-Null
    $savedContextRoute = Get-Content (Join-Path $root '.concord/routing-decisions/ROUTE-RAW-SOURCE-001.json') -Raw | ConvertFrom-Json
    Assert-True 'R4 raw-source retrieval is persisted separately without suppressing semantic routing' `
        ($savedContextRoute.route -eq 'CONTEXT_MODE' -and -not $savedContextRoute.delegation_attempted -and $fixture.runtime_expectations.separate_raw_retrieval_from_semantic_routing) 'Raw retrieval and semantic route were conflated'

    Write-JsonFile $routeInputPath $routeDecision
    $recordedRoute = (& $RoutingSave -ProjectRoot $root -InputFile $routeInputPath | ConvertFrom-Json)
    Assert-True 'Routing decision is persisted before semantic analysis and linked to checkpoint' `
        ($recordedRoute.state -eq 'RECORDED' -and (Test-Path (Join-Path $root $recordedRoute.decision_reference)) -and (Get-Content $checkpointPath -Raw) -match 'ROUTE-SEMANTIC-001') 'Routing decision evidence missing'
    $persistedRoute = Get-Content (Join-Path $root $recordedRoute.decision_reference) -Raw | ConvertFrom-Json
    Assert-True 'R2 twenty semantic requirements are grouped into one bounded MID spawn' `
        ($persistedRoute.artifact_count -eq 20 -and $persistedRoute.source_fingerprints.Count -eq 20 -and $fixture.main_profile -eq 'HIGH') 'Bounded cluster scope or source fingerprints missing'
    Assert-True 'Reality fixture requires a real dispatch when supported and compact reuse' `
        ($fixture.runtime_expectations.minimum_actual_spawn_calls_when_supported -ge 1 -and $fixture.runtime_expectations.persist_routing_before_analysis -and $fixture.runtime_expectations.reuse_after_compaction) 'Runtime fixture expectations missing'

    $spawn = $null
    if ($routeDecision.route -eq 'DELEGATE' -and $routeDecision.capability_state -eq 'supported' -and $fixture.runtime_expectations.minimum_actual_spawn_calls_when_supported -gt 0) {
        $spawn = Invoke-FixtureHarnessSpawn -Decision $routeDecision
    }
    $routeDecision.delegation_attempted = ($null -ne $spawn)
    $routeDecision.spawn_outcome = if ($null -ne $spawn) { 'started' } else { 'not_attempted' }
    $routeDecision.result_reference = '.concord/delegated-results/DELEGATION-001.json'
    Write-JsonFile $routeInputPath $routeDecision
    & $RoutingSave -ProjectRoot $root -InputFile $routeInputPath | Out-Null
    Assert-True 'Bounded semantic route invokes the harness callback with MID profile' `
        ($script:SpawnCount -eq $fixture.runtime_expectations.minimum_actual_spawn_calls_when_supported -and $spawn.agent_type -eq 'semantic-review') 'Spawn callback or profile contract missing'

    $failedRoute = [ordered]@{}
    foreach ($key in $routeDecision.Keys) { $failedRoute[$key] = $routeDecision[$key] }
    $failedRoute.decision_id = 'ROUTE-SPAWN-FAIL-001'
    $failedRoute.delegation_id = 'DELEGATION-SPAWN-FAIL-001'
    $failedRoute.spawn_outcome = 'pending'
    $failedRoute.delegation_attempted = $false
    $failedRoute.result_reference = $null
    $failedRoute.main_consumed = $false
    $failedRoute.compaction_occurred = $false
    $failedRoute.result_reused = $false
    $failedRoute.stale_result_rejected = $false
    $failedRoute.batch_restarted = $false
    Write-JsonFile $routeInputPath $failedRoute
    & $RoutingSave -ProjectRoot $root -InputFile $routeInputPath | Out-Null
    $failedSpawn = Invoke-FixtureHarnessSpawn -Decision $failedRoute -FailSpawn
    $failedRoute.route = 'FALLBACK'
    $failedRoute.reason = 'The current harness spawn failed; the main agent continues fail-soft.'
    $failedRoute.fallback_reason = 'Native spawn operation returned failure.'
    $failedRoute.delegation_attempted = $true
    $failedRoute.spawn_outcome = $failedSpawn.state
    Write-JsonFile $routeInputPath $failedRoute
    & $RoutingSave -ProjectRoot $root -InputFile $routeInputPath | Out-Null
    $savedFailedRoute = Get-Content (Join-Path $root '.concord/routing-decisions/ROUTE-SPAWN-FAIL-001.json') -Raw | ConvertFrom-Json
    Assert-True 'R6 spawn failure is observable and falls back without blocking the mission' `
        ($savedFailedRoute.route -eq 'FALLBACK' -and $savedFailedRoute.delegation_attempted -and $savedFailedRoute.spawn_outcome -eq 'failed' -and $savedFailedRoute.fallback_reason) 'Spawn failure fallback evidence missing'

    $unavailableRoute = [ordered]@{}
    foreach ($key in $routeDecision.Keys) { $unavailableRoute[$key] = $routeDecision[$key] }
    $unavailableRoute.decision_id = 'ROUTE-CAPABILITY-UNKNOWN-001'
    $unavailableRoute.route = 'FALLBACK'
    $unavailableRoute.reason = 'Current-session delegation capability is unknown.'
    $unavailableRoute.fallback_reason = 'No current-session attestation or supported adapter was available.'
    $unavailableRoute.capability_state = 'unknown'
    $unavailableRoute.requested_agent_type = $null
    $unavailableRoute.delegation_attempted = $false
    $unavailableRoute.spawn_outcome = 'not_attempted'
    $unavailableRoute.delegation_id = $null
    $unavailableRoute.result_reference = $null
    $unavailableRoute.main_consumed = $false
    $unavailableRoute.compaction_occurred = $false
    $unavailableRoute.result_reused = $false
    $unavailableRoute.stale_result_rejected = $false
    $unavailableRoute.batch_restarted = $false
    Write-JsonFile $routeInputPath $unavailableRoute
    & $RoutingSave -ProjectRoot $root -InputFile $routeInputPath | Out-Null
    $savedUnavailableRoute = Get-Content (Join-Path $root '.concord/routing-decisions/ROUTE-CAPABILITY-UNKNOWN-001.json') -Raw | ConvertFrom-Json
    Assert-True 'R5 unknown capability continues with persisted non-spawn fallback' `
        ($savedUnavailableRoute.capability_state -eq 'unknown' -and -not $savedUnavailableRoute.delegation_attempted -and $savedUnavailableRoute.spawn_outcome -eq 'not_attempted' -and $savedUnavailableRoute.fallback_reason) 'Unavailable-capability fallback missing'

    $input = [ordered]@{
        schema_version = '1.1'
        mission_id = 'MISSION-TEST-001'
        delegation_id = 'DELEGATION-001'
        agent_type = 'semantic-review'
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
        model_resolution = [ordered]@{
            model_selection = 'supported'
            profile_resolution = 'static_mapping'
            resolution = 'static_mapping'
            resolved_model = 'sonnet'
            requested_reasoning_effort = $null
            fallback_used = $false
            fallback_reason = $null
        }
    }
    $inputPath = Join-Path $root 'handoff.json'
    Write-JsonFile $inputPath $input
    $saved = (& $Save -ProjectRoot $root -InputFile $inputPath | ConvertFrom-Json)
    Assert-True 'Result is saved with a durable reference' ($saved.state -eq 'COMPLETED' -and (Test-Path (Join-Path $root $saved.result_reference))) 'Save result missing'
    $savedResult = Get-Content (Join-Path $root $saved.result_reference) -Raw | ConvertFrom-Json
    Assert-True 'Result persists requested-profile resolution and actual fallback evidence' `
        ($savedResult.model_resolution.model_selection -eq 'supported' -and $savedResult.model_resolution.resolved_model -eq 'sonnet' -and -not $savedResult.model_resolution.fallback_used) 'Model resolution evidence missing'
    $checkpoint = Get-Content (Join-Path $root '.concord/context-epoch.yaml') -Raw
    Assert-True 'Checkpoint links the compact result' ($checkpoint -match 'DELEGATION-001' -and $checkpoint -match 'delegated-results') 'Checkpoint reference missing'
    Assert-True 'Checkpoint retains routing-decision and result evidence' ($checkpoint -match 'ROUTE-SEMANTIC-001' -and $checkpoint -match 'DELEGATION-001') 'Routing/result link missing'
    Assert-True 'Adding a result reference preserves unrelated lifecycle state' `
        (($checkpoint -match 'framework: ".mxagile/"') -and ($checkpoint -match 'GATE-001') -and ($checkpoint -match 'preserve this checkpoint state') -and ($checkpoint -match 'transition_state: CHECKPOINT_VALIDATED')) 'Checkpoint fields were rewritten'

    & $Writer -ProjectRoot $root -MissionId 'MISSION-TEST-001' -MissionObjective 'Test result reuse' `
        -MissionStatus active -CurrentPhase implementing -EpochId EPOCH-001 -PreserveEvidence -WriteHandoffCopy | Out-Null
    $handoff = Get-Content (Join-Path $root 'planning/lifecycle/context-epoch.yaml') -Raw
    Assert-True 'Compaction checkpoint rewrite retains the result reference' ($handoff -match 'DELEGATION-001' -and $handoff -match 'delegated-results') 'Compaction dropped result reference'

    $current = (& $Get -ProjectRoot $root -DelegationId 'DELEGATION-001' | ConvertFrom-Json)
    Assert-True 'Matching source fingerprints permit compact result reuse' ($current.state -eq 'CURRENT' -and $current.reusable -and $current.result.mission_id -eq 'MISSION-TEST-001') 'Current result not reusable'
    $routeDecision.spawn_outcome = 'completed'
    $routeDecision.main_consumed = $current.reusable
    $routeDecision.compaction_occurred = $true
    $routeDecision.result_reused = $current.reusable
    Write-JsonFile $routeInputPath $routeDecision
    & $RoutingSave -ProjectRoot $root -InputFile $routeInputPath | Out-Null
    $savedRoute = Get-Content (Join-Path $root '.concord/routing-decisions/ROUTE-SEMANTIC-001.json') -Raw | ConvertFrom-Json
    Assert-True 'Main consumes the compact result after checkpoint compaction' `
        ($savedRoute.spawn_outcome -eq 'completed' -and $savedRoute.main_consumed -and $savedRoute.compaction_occurred -and $savedRoute.result_reused -and $savedRoute.requested_agent_type -eq 'semantic-review') 'Result consumption or reuse was not observed'
    $resultPath = Join-Path $root '.concord/delegated-results/DELEGATION-001.json'
    $currentResultJson = Get-Content $resultPath -Raw
    $legacyResult = $currentResultJson | ConvertFrom-Json
    $legacyResult.schema_version = '1.0'
    $legacyResult.PSObject.Properties.Remove('model_resolution')
    Write-JsonFile $resultPath $legacyResult
    $legacy = (& $Get -ProjectRoot $root -DelegationId 'DELEGATION-001' | ConvertFrom-Json)
    Assert-True 'Legacy 1.0 results remain reusable without model-resolution fields' `
        ($legacy.state -eq 'CURRENT' -and $legacy.result.schema_version -eq '1.0' -and 'model_resolution' -notin @($legacy.result.PSObject.Properties.Name)) 'Legacy result compatibility failed'
    [System.IO.File]::WriteAllText($resultPath, $currentResultJson, [System.Text.UTF8Encoding]::new($false))
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
    $routeDecision.stale_result_rejected = ($stale.state -eq 'STALE')
    Write-JsonFile $routeInputPath $routeDecision
    & $RoutingSave -ProjectRoot $root -InputFile $routeInputPath | Out-Null
    $savedRoute = Get-Content (Join-Path $root '.concord/routing-decisions/ROUTE-SEMANTIC-001.json') -Raw | ConvertFrom-Json
    Assert-True 'Stale result rejection is preserved in mission routing evidence' $savedRoute.stale_result_rejected 'Stale rejection missing'

    $reasonlessRoute = [ordered]@{}
    foreach ($key in $routeDecision.Keys) { $reasonlessRoute[$key] = $routeDecision[$key] }
    $reasonlessRoute.decision_id = 'ROUTE-NO-REASON-001'
    $reasonlessRoute.route = 'MAIN_AGENT'
    $reasonlessRoute.reason = ''
    $reasonlessRoute.fallback_reason = $null
    $reasonlessRoute.delegation_attempted = $false
    $reasonlessRoute.spawn_outcome = 'not_attempted'
    $reasonlessRoute.delegation_id = $null
    $reasonlessRoute.result_reference = $null
    $rejectedReasonlessRoute = $false
    try {
        Write-JsonFile $routeInputPath $reasonlessRoute
        & $RoutingSave -ProjectRoot $root -InputFile $routeInputPath | Out-Null
    } catch { $rejectedReasonlessRoute = $true }
    Assert-True 'R11 available-but-not-delegated semantic work requires an explicit reason' $rejectedReasonlessRoute 'Reasonless main-agent route was accepted'

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