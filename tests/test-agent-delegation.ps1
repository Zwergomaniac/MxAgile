$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$RepoRoot = Split-Path -Parent $PSScriptRoot
$Resolver = Join-Path $RepoRoot 'scripts/Get-MxAgileCapabilities.ps1'
$PolicyPath = Join-Path $RepoRoot '.mxagile/policies/agent-delegation.md'
$PassCount = 0
$FailCount = 0
$tempRoot = Join-Path $env:TEMP "mxagile-delegation-cap-$(New-Guid)"

function Assert-True {
    param([string]$Name, [bool]$Condition, [string]$Message = '')
    if ($Condition) { Write-Host "PASS: $Name" -ForegroundColor Green; $script:PassCount++ }
    else { Write-Host "FAIL: $Name -- $Message" -ForegroundColor Red; $script:FailCount++ }
}

function Invoke-DelegationCapability {
    param([string]$Harness = '', [string]$Profile = '', [string]$SessionHarness = '')
    $saved = @{}
    foreach ($name in @('MXAGILE_HARNESS', 'CLAUDECODE', 'OPENCODE_SESSION_ID', 'OPENCODE_BASE_URL')) {
        $saved[$name] = [Environment]::GetEnvironmentVariable($name)
        [Environment]::SetEnvironmentVariable($name, $null)
    }
    if ($SessionHarness) { [Environment]::SetEnvironmentVariable('MXAGILE_HARNESS', $SessionHarness) }
    try {
        $args = @{ ProjectRoot = $tempRoot; Capability = 'subagent_spawn'; Format = 'json' }
        if ($Harness) { $args.Harness = $Harness }
        if ($Profile) { $args.ModelProfile = $Profile }
        $output = & $Resolver @args 2>&1
        if ($LASTEXITCODE -ne 0) { throw "Resolver failed: $output" }
        return ($output | ConvertFrom-Json).capabilities[0]
    } finally {
        foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name, $saved[$name]) }
    }
}

try {
    New-Item -ItemType Directory -Path (Join-Path $tempRoot '.mxagile') -Force | Out-Null
    Copy-Item (Join-Path $RepoRoot '.mxagile/capabilities.yaml') (Join-Path $tempRoot '.mxagile/capabilities.yaml')
    Copy-Item (Join-Path $RepoRoot '.mxagile/version.yaml') (Join-Path $tempRoot '.mxagile/version.yaml')
    Copy-Item (Join-Path $RepoRoot '.mxagile/config.yaml') (Join-Path $tempRoot '.mxagile/config.yaml')
    Copy-Item (Join-Path $RepoRoot '.mxagile/adapters') (Join-Path $tempRoot '.mxagile/adapters') -Recurse

    $claude = Invoke-DelegationCapability -SessionHarness 'claude_code' -Profile 'MID'
    Assert-True 'R1 supported Claude adapter is available but not spuriously active' `
        ($claude.state.available -and -not $claude.state.active -and $claude.integration.status -eq 'supported') $claude.state.reason
    Assert-True 'Claude adapter resolves MID only in its harness layer' `
        ($claude.integration.resolved_model -eq 'sonnet' -and $claude.integration.model_resolution -eq 'adapter_profile_mapping') 'MID mapping missing'

    $copilot = Invoke-DelegationCapability -SessionHarness 'vscode_copilot' -Profile 'HIGH'
    Assert-True 'VS Code Copilot profile mapping may remain unresolved without blocking' `
        ($copilot.state.available -and $null -eq $copilot.integration.resolved_model -and $copilot.integration.model_resolution -eq 'use_available_agent_model') 'Model fallback failed'
    $copilotAdapter = Join-Path $tempRoot '.mxagile/adapters/copilot/agent-delegation-vscode.yaml'
    (Get-Content $copilotAdapter -Raw).Replace('model_selection: supported', 'model_selection: unsupported') |
        Set-Content -LiteralPath $copilotAdapter -Encoding UTF8
    $noModelSelection = Invoke-DelegationCapability -SessionHarness 'vscode_copilot' -Profile 'HIGH'
    Assert-True 'R14 no model-selection support falls back to the available agent model' `
        ($noModelSelection.state.available -and $noModelSelection.integration.resolved_model -eq $null -and $noModelSelection.integration.model_resolution -eq 'use_available_agent_model') 'Model selection blocked delegation'
    (Get-Content $copilotAdapter -Raw).Replace('model_selection: unsupported', 'model_selection: supported') |
        Set-Content -LiteralPath $copilotAdapter -Encoding UTF8

    $cli = Invoke-DelegationCapability -SessionHarness 'copilot_cli'
    Assert-True 'Copilot CLI is independently supported by its own adapter' `
        ($cli.integration.status -eq 'supported' -and $cli.state.available -and $cli.integration.model_selection -eq 'supported') 'Copilot CLI contract missing'
    Assert-True 'Plan-dependent concurrency is exposed without a false fixed cap' `
        ($null -eq $cli.integration.max_concurrency -and $cli.integration.concurrency_notes -match 'plan limits vary') 'Concurrency constraints missing'
    $openCode = Invoke-DelegationCapability -SessionHarness 'opencode'
    Assert-True 'OpenCode named subagents are supported while generic fork remains unknown' `
        ($openCode.integration.status -eq 'supported' -and $openCode.integration.named_agents -eq 'supported' -and $openCode.integration.generic_fork -eq 'unknown') 'OpenCode contract inaccurate'
    $codex = Invoke-DelegationCapability -SessionHarness 'codex'
    Assert-True 'Codex delegation is resolved from its own assessed adapter' `
        ($codex.integration.status -eq 'supported' -and $codex.state.available) 'Codex contract missing'

    $noAttestation = Invoke-DelegationCapability
    Assert-True 'R3 missing harness attestation remains unknown' ($noAttestation.integration.status -eq 'unknown') 'Support was guessed'
    $unassessed = Invoke-DelegationCapability -SessionHarness 'other'
    Assert-True 'R3 an attested but unassessed harness remains unknown' ($unassessed.integration.status -eq 'unknown') 'Unknown host was guessed'

    $genericAdapter = Join-Path $tempRoot '.mxagile/adapters/generic/agent-delegation.yaml'
    $genericOriginal = Get-Content $genericAdapter -Raw
    $mismatchedAdapter = $genericOriginal.Replace('harness_id: generic', 'harness_id: codex')
    Set-Content -LiteralPath $genericAdapter -Value $mismatchedAdapter -Encoding UTF8
    $identityMismatch = Invoke-DelegationCapability -SessionHarness 'generic'
    Assert-True 'Adapter identity mismatch fails closed to unknown' `
        ($identityMismatch.integration.status -eq 'unknown' -and -not $identityMismatch.integration.route_allowed) 'Mismatched adapter was trusted'
    Set-Content -LiteralPath $genericAdapter -Value $genericOriginal -Encoding UTF8
    (Get-Content $genericAdapter -Raw).Replace('status: unknown', 'status: unsupported') |
        Set-Content -LiteralPath $genericAdapter -Encoding UTF8
    $unsupported = Invoke-DelegationCapability -SessionHarness 'generic'
    Assert-True 'R2 explicit unsupported state is unavailable and falls back' `
        ($unsupported.integration.status -eq 'unsupported' -and $unsupported.state.unavailable -and -not $unsupported.integration.route_allowed) 'Unsupported fallback failed'

    $configPath = Join-Path $tempRoot '.mxagile/config.yaml'
    $configText = Get-Content $configPath -Raw
    $configText = [regex]::Replace($configText, '(?m)(^agent_delegation:\r?\n(?:[ \t]*#.*\r?\n)*[ \t]+enabled:[ \t]*)true', '${1}false')
    Set-Content -LiteralPath $configPath -Value $configText -Encoding UTF8
    $disabled = Invoke-DelegationCapability -SessionHarness 'claude_code'
    Assert-True 'Supported adapter does not route when project delegation is disabled' `
        ($disabled.state.available -and -not $disabled.state.enabled -and -not $disabled.integration.route_allowed) 'Config disable ignored'

    $adapterSchema = Get-Content (Join-Path $RepoRoot '.mxagile/schemas/harness-adapter.schema.json') -Raw | ConvertFrom-Json
    $handoffSchema = Get-Content (Join-Path $RepoRoot '.mxagile/schemas/delegation-handoff.schema.json') -Raw | ConvertFrom-Json
    $resultSchema = Get-Content (Join-Path $RepoRoot '.mxagile/schemas/delegation-result.schema.json') -Raw | ConvertFrom-Json
    $adapterFiles = @(Get-ChildItem (Join-Path $RepoRoot '.mxagile/adapters') -Recurse -File -Filter 'agent-delegation*.yaml')
    $allAdaptersValid = $adapterFiles.Count -gt 0
    foreach ($adapterFile in $adapterFiles) {
        $adapterText = Get-Content $adapterFile.FullName -Raw
        $adapterStatus = [regex]::Match($adapterText, '(?m)^  status:\s*(\S+)').Groups[1].Value
        $adapterHasFields = @(@('harness_id', 'named_agents', 'generic_fork', 'model_selection', 'max_concurrency', 'concurrency_notes', 'evidence') |
            Where-Object { $adapterText -notmatch ('(?m)^  {0}:' -f $_) })
        if ($adapterStatus -notin @('supported', 'unsupported', 'unknown') -or $adapterHasFields.Count -gt 0) { $allAdaptersValid = $false }
    }
    Assert-True 'Harness adapter schema includes three-state delegation contract' `
        ($adapterSchema.definitions.delegation_capability.properties.status.enum -join ',' -eq 'supported,unsupported,unknown') 'Adapter state enum missing'
    Assert-True 'Every present harness adapter declares identity, status, model and concurrency evidence' $allAdaptersValid 'Adapter inventory contains an incomplete declaration'
    $handoffFields = @('mission_id','task','scope','authority_references','artifact_paths','source_fingerprints','allowed_tools','forbidden_mutations','expected_result_schema')
    $missingHandoffFields = @($handoffFields | Where-Object { $_ -notin @($handoffSchema.required) })
    Assert-True 'R8 handoff carries mission, bounded scope, authority, tools, mutations, schema and budget' `
        ($missingHandoffFields.Count -eq 0 -and $handoffSchema.additionalProperties -eq $false -and $null -ne $handoffSchema.properties.context_budget_tokens) "Handoff fields missing: $($missingHandoffFields -join ', ')"
    $resultFields = @('conclusion','findings','provenance','affected_ids','unknowns','conflicts','decision_candidates','evidence_references','source_fingerprints')
    $missingResultFields = @($resultFields | Where-Object { $_ -notin @($resultSchema.required) })
    Assert-True 'R10 result schema carries provenance, fingerprints and compact findings' `
        ($missingResultFields.Count -eq 0 -and $resultSchema.additionalProperties -eq $false) "Result fields missing: $($missingResultFields -join ', ')"

    $policy = Get-Content $PolicyPath -Raw
    $profiles = Get-Content (Join-Path $RepoRoot '.mxagile/delegation.yaml') -Raw
    Assert-True 'R4 deterministic repair stays with helpers' (($policy -match 'Do not delegate YAML quoting') -and ($policy -match 'schema checks')) 'Deterministic routing missing'
    Assert-True 'R5/R6 batching rejects one-agent-per-artifact for 87/52 cases' `
        (($policy -match '87 requirements') -and ($policy -match '52 decisions') -and ($policy -match 'one subagent per file or requirement')) 'Anti-amplification fixture missing'
    Assert-True 'R7 main agent retains lifecycle and final planning authority' `
        (($policy -match 'ACTIVE_TARGET') -and ($policy -match 'gate decisions') -and ($policy -match 'planning decisions')) 'Authority contract incomplete'
    Assert-True 'Resume and Context Mode reuse are freshness- and mission-bounded' `
        (($policy -match 'active mission') -and ($policy -match 'fingerprints') -and ($policy -match 'do not automatically')) 'Resume/retrieval rules missing'
    Assert-True 'R11/R12 UI parity defaults MID and planning defaults HIGH' `
        (($profiles -match '(?m)^\s+ui:\s+MID\s*$') -and ($profiles -match '(?m)^\s+planning:\s+HIGH\s*$')) 'Mission profile defaults missing'
    Assert-True 'R13 deterministic migration and maintenance use no model; semantic work escalates by ambiguity' `
        (($profiles -match '(?m)^\s+deterministic_work:\s+null\s*$') -and ($profiles -match '(?m)^\s+deterministic_core_update:\s+null\s*$') -and ($profiles -match '(?m)^\s+migration_classification:\s+MID\s*$') -and ($profiles -match '(?m)^\s+ambiguous_historical_reconstruction:\s+HIGH\s*$') -and ($profiles -match '(?m)^\s+ambiguous_maintenance_root_cause:\s+HIGH\s*$')) 'Mission profile policy missing'
} finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "PASS: $PassCount; FAIL: $FailCount"
if ($FailCount -gt 0) { exit 1 }