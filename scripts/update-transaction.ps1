function Save-MxAgileUpdateTransaction {
    param([string]$Root, [System.Collections.IDictionary]$Transaction)
    $path = Join-Path $Root '.mxagile/state/update-transaction.json'
    $PSNativeCommandUseErrorActionPreference=$false
    & python -B -c 'import sys; from pathlib import Path; sys.path.insert(0,sys.argv[1]); from projection_io import safe_path; safe_path(Path(sys.argv[2]),".mxagile/state/update-transaction.json")' $PSScriptRoot $Root
    if ($LASTEXITCODE -ne 0) { throw 'Unsafe update transaction path.' }
    $Transaction.updated_at = [DateTime]::UtcNow.ToString('o')
    [void][IO.Directory]::CreateDirectory((Split-Path $path -Parent))
    $temporary = "$path.$([Guid]::NewGuid().ToString('N')).tmp"
    try {
        [IO.File]::WriteAllText($temporary, (($Transaction | ConvertTo-Json -Depth 40) + "`n"), [Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temporary -Destination $path -Force
    } finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force } }
}

function New-MxAgileCoreUpdateTransaction {
    param([string]$Root, [System.Collections.IDictionary]$TargetCore, [string]$CompanySource = '', [string]$CompanyRef = '')
    $previous = @{}
    $provenancePath = Join-Path $Root '.mxagile/state/core-provenance.json'
    if (Test-Path -LiteralPath $provenancePath -PathType Leaf) { $previous = Get-Content -LiteralPath $provenancePath -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable }
    $manifestPath = Join-Path $Root '.mxagile/state/projections-manifest.json'
    $projectionCommit = $null
    if (Test-Path -LiteralPath $manifestPath -PathType Leaf) { $projectionCommit = (Get-Content -LiteralPath $manifestPath -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable).generated_from_core_commit }
    $layers=@()
    $layersRoot=Join-Path $Root '.mxagile/layers'
    if (Test-Path -LiteralPath $layersRoot -PathType Container) {
        foreach ($directory in (Get-ChildItem -LiteralPath $layersRoot -Directory -Force)) {
            $layerPath=Join-Path $directory.FullName 'provenance.json'
            $value=if (Test-Path -LiteralPath $layerPath -PathType Leaf) { Get-Content -LiteralPath $layerPath -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable } else { @{} }
            $layers += @{ id=$directory.Name; version=($value['installedVersion'] ?? $value['version']); commit=($value['sourceCommit'] ?? $value['commit']) }
        }
    }
    return [ordered]@{
        schema_version = 1; update_attempt_id = "UPDATE-$([Guid]::NewGuid().ToString('N'))"
        state = 'UPDATE_IN_PROGRESS'; started_at = [DateTime]::UtcNow.ToString('o'); updated_at = [DateTime]::UtcNow.ToString('o'); current_stage = 'PRECHECK_COMPLETE'
        previous_core = @{ version = $previous['version']; commit = $previous['commit']; installed_at = $previous['installed_at'] }
        target_core = $TargetCore
        previous_company_layers = @($layers); target_company_layer = @{ repository = $CompanySource; ref = $CompanyRef; id = $null; version = 'NOT_RESOLVED'; commit = 'NOT_RESOLVED' }
        completed_stages = @(); failed_stage = $null; failure = $null
        affected_generated_artifacts = @('.mxagile/', '.claude/', '.github/', '.agents/', '.grok/', '.opencode/', '.hermes/')
        migrations_performed = @(); rollback = @{ available = $false; core = $false; company_layer = $false; backup_path = $null; performed = $false }
        compatibility_status = 'NOT_VERIFIED'; context_state = 'STALE'; restart_required = $false; resync_required = $true; resume_available = $true; resume_count = 0
        projection = @{ status = 'NOT_STARTED'; previous_commit = $projectionCommit; target_commit = $TargetCore.commit; ownership_baseline = @(); plan_fingerprint = $null; core_applied = $false; contract_migration_started = $false; doctor_executed = $false; consumer_artifacts_changed = $false }
    }
}

function Complete-MxAgileCoreUpdateTransaction {
    param([string]$Root, [System.Collections.IDictionary]$Transaction)
    $handoffPath=Join-Path $Root '.mxagile/state/last-update-result.json'
    $handoff=Get-Content -LiteralPath $handoffPath -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable
    $Transaction.projection.doctor_executed=[bool]$handoff.doctor.executed
    $Transaction.compatibility_status=$handoff.doctor.compatibility
    $Transaction.completed_stages=@(@($Transaction.completed_stages) + @($handoff.completed_stages) | Select-Object -Unique)
    $Transaction.state=if ($handoff.doctor.compatibility -eq 'NOT_VERIFIED') { 'COMPATIBILITY_NOT_VERIFIED' } else { 'UPDATE_INSTALLED_RESTART_REQUIRED' }
    $Transaction.current_stage=if ($handoff.doctor.compatibility -eq 'NOT_VERIFIED') { 'POST_UPDATE_DOCTOR' } else { 'CONTEXT_RESYNC' }
    $Transaction.resume_available=$handoff.doctor.compatibility -eq 'NOT_VERIFIED'
    Save-MxAgileUpdateTransaction -Root $Root -Transaction $Transaction
    $handoff.update_transaction=$Transaction
    [IO.File]::WriteAllText($handoffPath, (($handoff | ConvertTo-Json -Depth 40) + "`n"), [Text.UTF8Encoding]::new($false))
    if (-not $Transaction.resume_available) { Remove-Item -LiteralPath (Join-Path $Root '.mxagile/state/update-transaction.json') -Force }
}
