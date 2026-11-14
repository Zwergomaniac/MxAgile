[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string]$ProjectRoot,

    [string]$CompanyLayerSource,

    [ValidateSet("Auto", "Git", "Local")]
    [string]$CompanyLayerSourceType = "Auto",

    [string]$CompanyLayerRef = "main",

    # When $true, the caller has already detected an existing MxAgile installation.
    # install-core.ps1 uses this to skip first-install-only initialization where safe.
    [bool]$IsUpdate = $false,

    [string]$ProvenanceFlavor         = "",
    [string]$ProvenanceCoreSource     = "",
    [string]$ProvenanceCoreSourceType = "",
    [string]$ProvenanceCoreRef        = "",
    [string]$ProvenanceCoreSubdir     = "",
    [string]$ProvenanceCoreCommit     = "",
    [switch]$DeferPostUpdateCompatibility,
    [switch]$ResumeUpdate,

    # Explicit opt-in: run the bounded Board smoke after the Doctor handoff (never implied by CI or updates).
    [switch]$BoardSmoke
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
$updateMutationStarted = $false
$updateStage = 'PREFLIGHT'
$updateTransactionPath = $null
$ownsUpdateTransaction = $false
. (Join-Path $PSScriptRoot 'update-transaction.ps1')

function Invoke-CoreProjectionResume {
    param([string]$Root, [bool]$DeferCompatibility)
    $python = Get-Command python -ErrorAction Stop
    $verify = @'
import hashlib, json, re, sys
from pathlib import Path
sys.path.insert(0, sys.argv[2])
from project_compatibility import contract_snapshot, safe_file
import subprocess
root=Path(sys.argv[1])
from projection_io import safe_path, validate_sources
for relative in ('.mxagile/state/core-provenance.json','.mxagile/state/projections-manifest.json','.mxagile/state/update-transaction.json'):
 safe_path(root,relative)
validate_sources([str(root/'.mxagile'/name) for name in ('skills','agents','schemas','tools')])
core=json.loads((root/'.mxagile/state/core-provenance.json').read_text(encoding='utf-8-sig'))
assert re.fullmatch('[a-f0-9]{40}', core.get('commit',''))
assert contract_snapshot(root)==core.get('artifact_contract')
actual={}
for path in (root/'.mxagile/tools').rglob('*.py'):
 relative=path.relative_to(root).as_posix()
 assert safe_file(root,relative)==path
 actual[path.relative_to(root/'.mxagile/tools').as_posix()]=hashlib.sha256(path.read_bytes()).hexdigest()
writer=root/'.mxagile/tools/Write-MxAgileEpochCheckpoint.ps1'
actual[writer.name]=hashlib.sha256(writer.read_bytes()).hexdigest()
assert actual==core.get('recovery_tools')
assert (root/'.mxagile/skills').is_dir()
repository=str(Path(sys.argv[2]).parent)
commit=core['commit']
paths=subprocess.check_output(['git','-C',repository,'ls-tree','-r','--name-only',commit,'--','.mxagile/skills','.mxagile/agents','products/MxMocketeer/skills'],stderr=subprocess.DEVNULL).decode().splitlines()
assert paths
for source in paths:
 target=('.mxagile/skills/'+source[len('products/MxMocketeer/skills/'):]) if source.startswith('products/MxMocketeer/skills/') else source
 path=safe_file(root,target)
 assert path is not None and path.is_file()
 expected=subprocess.check_output(['git','-C',repository,'cat-file','blob',commit+':'+source],stderr=subprocess.DEVNULL)
 actual_source=path.read_bytes()
 if source.endswith(('.md','.txt')):
  actual_source=actual_source.replace(b'\r\n',b'\n'); expected=expected.replace(b'\r\n',b'\n')
 assert actual_source==expected, 'Installed canonical source differs: '+source
print('INSTALLED_CORE_VERIFIED')
'@
    $PSNativeCommandUseErrorActionPreference = $false
    $verified = @(& $python.Source -B -c $verify $Root $PSScriptRoot 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "RESUME_CORE_NOT_VERIFIED: installed schema/tool/source integrity is not bound to current provenance. $($verified -join ' ')" }
    $corePath = Join-Path $Root '.mxagile/state/core-provenance.json'
    $core = Get-Content -LiteralPath $corePath -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable
    $path = Join-Path $Root '.mxagile/state/update-transaction.json'
    $manifestPath = Join-Path $Root '.mxagile/state/projections-manifest.json'
    $manifest = if (Test-Path -LiteralPath $manifestPath -PathType Leaf) { Get-Content -LiteralPath $manifestPath -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable } else { @{} }
    $transaction = if (Test-Path -LiteralPath $path -PathType Leaf) { Get-Content -LiteralPath $path -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable } else { $null }
    if (-not $transaction -and $manifest['generated_from_core_commit'] -eq $core['commit'] -and $manifest['projection_version'] -eq '2') {
        $checked = & (Join-Path $PSScriptRoot 'generate-mxagile-platform-skills.ps1') -ProjectRoot $Root -CoreCommit $core['commit'] -CoreVersion $core['version'] -PreflightOnly -PassThru
        if (-not $checked.ready -or @($checked.targets | Where-Object state -ne 'TARGET_OWNED_CURRENT').Count) { throw 'Completed projection resume is not current.' }
        & $python.Source -B -c 'import sys; from pathlib import Path; sys.path.insert(0,sys.argv[1]); from project_compatibility import projection_integrity; raise SystemExit(0 if projection_integrity(Path(sys.argv[2]))["ready"] else 2)' $PSScriptRoot $Root
        if ($LASTEXITCODE -ne 0) { throw 'Completed projection file proof or Core activation is inconsistent; no read-only completion can be claimed.' }
        Write-Host 'RESUME_STATUS: ALREADY_COMPLETE (read-only)'
        return
    }
    if ($transaction) {
        if ($transaction.state -notin @('UPDATE_IN_PROGRESS','PARTIAL_UPDATE','COMPATIBILITY_NOT_VERIFIED') -or $transaction.target_core.commit -ne $core['commit']) { throw 'RESUME_TARGET_CONFLICT: persisted target is not the verified installed Core.' }
        foreach ($field in @('version','source','source_type','ref')) {
            $expected=$transaction.target_core[$field]; $observed=$core[$field]
            if ($expected -and $observed -and $expected -ne 'UNKNOWN' -and $expected -ne $observed) { throw "RESUME_TARGET_CONFLICT: installed Core $field contradicts the recorded target." }
        }
    } else {
        if (-not $manifest['generated_from_core_commit'] -or $manifest['generated_from_core_commit'] -eq $core['commit']) { throw 'RESUME_STATE_NOT_OBSERVABLE: no pending transaction or bound legacy projection mismatch.' }
        $target = @{ commit=$core['commit']; version=$core['version']; source=$core['source']; source_type=$core['source_type']; ref=$core['ref'] }
        $transaction = New-MxAgileCoreUpdateTransaction -Root $Root -TargetCore $target
        $transaction.previous_core = @{ commit=$core['previous_commit']; version=$core['previous_version']; installed_at=$core['previous_installed_at'] }
    }
    if (-not $transaction.Contains('projection')) {
        $transaction.projection = @{ status='INCOMPLETE'; previous_commit=$manifest['generated_from_core_commit']; target_commit=$core['commit']; ownership_baseline=@(); plan_fingerprint=$null; core_applied=$true; contract_migration_started=$false; doctor_executed=$false; consumer_artifacts_changed=$false }
    }
    $script:updateMutationStarted = $true
    $script:updateStage = 'GENERATED_PROJECTIONS'
    $transaction.state = 'UPDATE_IN_PROGRESS'; $transaction.current_stage = 'GENERATED_PROJECTIONS'
    $transaction.resume_count = [int]$transaction.resume_count + 1
    $transaction.resumed_at = [DateTime]::UtcNow.ToString('o')
    $transaction.projection.core_applied = $true
    $transaction.completed_stages = @(@($transaction.completed_stages) + 'CORE_UPDATE' | Select-Object -Unique)
    Save-MxAgileUpdateTransaction -Root $Root -Transaction $transaction
    try {
        $preflight = & (Join-Path $PSScriptRoot 'generate-mxagile-platform-skills.ps1') -ProjectRoot $Root -CoreCommit $core['commit'] -CoreVersion $core['version'] -PreflightOnly -OwnershipBaseline @($transaction.projection.ownership_baseline) -PassThru
        $transaction.projection.plan_fingerprint = $preflight.plan_fingerprint
        $transaction.projection.ownership_baseline = @($preflight.ownership_baseline)
        Save-MxAgileUpdateTransaction -Root $Root -Transaction $transaction
        & (Join-Path $PSScriptRoot 'generate-mxagile-platform-skills.ps1') -ProjectRoot $Root -CoreCommit $core['commit'] -CoreVersion $core['version'] -OwnershipBaseline @($transaction.projection.ownership_baseline) -ExpectedPlanFingerprint $preflight.plan_fingerprint
        $transaction.projection.status = 'COMPLETE'
        if ($core['activation_state'] -eq 'CORE_APPLIED_PROJECTIONS_PENDING') {
            & $python.Source -B -c 'import json,sys; from pathlib import Path; sys.path.insert(0,sys.argv[1]); from projection_io import safe_path,atomic_replace; path=safe_path(Path(sys.argv[2]),".mxagile/state/core-provenance.json"); value=json.loads(path.read_text(encoding="utf-8-sig")); assert value["commit"]==sys.argv[3]; value["activation_state"]="ACTIVE"; atomic_replace(path,(json.dumps(value,indent=2)+"\n").encode())' $PSScriptRoot $Root $core['commit']
            if ($LASTEXITCODE -ne 0) { throw 'Core activation could not be finalized.' }
            $core.activation_state='ACTIVE'
        }
        $transaction.completed_stages = @(@($transaction.completed_stages) + 'GENERATED_PROJECTIONS' | Select-Object -Unique)
        $transaction.current_stage = 'COMPANY_LAYER_UPDATE'; $transaction.failed_stage=$null; $transaction.failure=$null
        Save-MxAgileUpdateTransaction -Root $Root -Transaction $transaction
        if ($DeferCompatibility) { Write-Host 'RESUME_STATUS: PROJECTIONS_COMPLETE; Company Layer/Doctor deferred.'; return }
        if ($transaction.target_company_layer.repository -and $transaction.completed_stages -notcontains 'COMPANY_LAYER_UPDATE') { throw 'RESUME_COMPANY_STAGE_REQUIRED: resume the enclosing Company Layer update, not a projection-only completion.' }
        $transaction.completed_stages = @(@($transaction.completed_stages) + 'COMPANY_LAYER_UPDATE' | Select-Object -Unique)
        $transaction.company_layer_result = 'NO_UPDATE_AVAILABLE'; $transaction.company_layer_completed = $true
        $transaction.current_stage = 'POST_UPDATE_DOCTOR'; $transaction.projection.contract_migration_started = $true
        Save-MxAgileUpdateTransaction -Root $Root -Transaction $transaction
        Invoke-PostUpdateCompatibility -Root $Root -ToolsDir (Join-Path $Root '.mxagile/tools') -CoreProvenance $core
        Complete-MxAgileCoreUpdateTransaction -Root $Root -Transaction $transaction
    } catch {
        $transaction.state='PARTIAL_UPDATE'; $transaction.failed_stage=$transaction.current_stage; $transaction.failure=$_.Exception.Message
        $script:updateStage=$transaction.current_stage
        if ($_.Exception.Data.Contains('projection_report')) { $transaction.projection.last_report=$_.Exception.Data['projection_report'] }
        if ($transaction.projection.status -ne 'COMPLETE') { $transaction.projection.status='INCOMPLETE' }
        Save-MxAgileUpdateTransaction -Root $Root -Transaction $transaction
        throw
    }
}

function Get-CoreArtifactContract {
    param([string]$Root)
    $python = Get-Command python -ErrorAction SilentlyContinue
    if (-not $python) { $python = Get-Command python3 -ErrorAction SilentlyContinue }
    if (-not $python) { return $null }
    try {
        $PSNativeCommandUseErrorActionPreference = $false
        $output = & $python.Source -B (Join-Path $PSScriptRoot 'project_compatibility.py') contract-snapshot --project-root $Root --format json 2>$null
        if ($LASTEXITCODE -ne 0) { return $null }
        return (($output -join "`n") | ConvertFrom-Json -AsHashtable -ErrorAction Stop)
    } catch { return $null }
}

function Invoke-PostUpdateCompatibility {
    param([string]$Root, [string]$ToolsDir, [System.Collections.IDictionary]$CoreProvenance)

    $restartRequired = $false
    $restartPath = Join-Path $Root '.mxagile/state/runs/framework-update-recovery.json'
    if (Test-Path -LiteralPath $restartPath -PathType Leaf) {
        $restartRecord = Get-Content -LiteralPath $restartPath -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable
        $restartRequired = $restartRecord['restart_required'] -and $restartRecord['commit'] -eq $CoreProvenance.commit
    }
    $result = [ordered]@{
        schema_version = 1
        installed_at = $CoreProvenance.installed_at
        update_state = if ($CoreProvenance.install_mode -eq 'update') { 'UPDATE_INSTALLED_RESTART_REQUIRED' } else { 'INSTALL_COMPLETED' }
        completed_stages = @('CORE_INSTALL', 'GENERATED_PROJECTIONS')
        failed_stage = $null
        migration = [ordered]@{ status = 'NOT_VERIFIED' }
        context_state = 'STALE'
        restart_required = [bool]$restartRequired
        resync_required = $true
        rollback_available = $false
        resume_available = $false
        framework = [ordered]@{
            update_successful = $true
            previous_version = $CoreProvenance.previous_version
            previous_commit = $CoreProvenance.previous_commit
            version = $CoreProvenance.version
            commit = $CoreProvenance.commit
        }
        session_contract = [ordered]@{
            state = if ($restartRequired) { 'SESSION_RESTART_REQUIRED' } else { 'RE_SYNC_REQUIRED' }
            policy = '.mxagile/policies/update-contract.md'
        }
        doctor = [ordered]@{
            executed = $false
            exit_code = $null
            compatibility = 'NOT_VERIFIED'
            reason = 'PYTHON_UNAVAILABLE'
            repair_status = $null
            blocking_diagnostic_count = $null
            safe_deterministic_count = $null
            agent_repairable_count = $null
            decision_required_count = $null
            unsupported_count = $null
            report = $null
        }
    }
    $doctor = $result.doctor
    $pythonCommand = Get-Command python -ErrorAction SilentlyContinue
    if (-not $pythonCommand) { $pythonCommand = Get-Command python3 -ErrorAction SilentlyContinue }
    if ($pythonCommand) {
        try {
            $doctorPath = Join-Path $ToolsDir 'project_compatibility.py'
            $doctor.reason = 'DOCTOR_SCRIPT_UNAVAILABLE'
            if (-not (Test-Path -LiteralPath $doctorPath -PathType Leaf)) { throw 'Doctor script missing' }
            $doctor.reason = 'DOCTOR_EXECUTION_FAILED: check Python and .mxagile/tools/requirements.txt'
            $PSNativeCommandUseErrorActionPreference = $false
            $doctorOutput = & $pythonCommand.Source -B $doctorPath migrate --apply-safe --project-root $Root --format json 2>$null
            $doctor.exit_code = $LASTEXITCODE
            if ($doctor.exit_code -notin @(0, 1, 2)) {
                $doctor.reason = "DOCTOR_EXIT_$($doctor.exit_code): check Python and .mxagile/tools/requirements.txt"
                throw 'Doctor unavailable'
            }
            $doctor.reason = 'DOCTOR_OUTPUT_INVALID'
            $migrationResult = ($doctorOutput -join "`n") | ConvertFrom-Json
            if ($migrationResult.stage -ne 'CONTRACT_MIGRATION_CHECKED') { throw 'Migration contract invalid' }
            $result.migration = $migrationResult.migration
            $result.completed_stages += 'CONTRACT_MIGRATION'
            $report = $migrationResult.doctor
            $doctor.executed = $true
            $result.completed_stages += 'DOCTOR'
            if ($report.stage -ne 'PROJECT_COMPATIBILITY_CHECKED' -or $report.read_only -ne $true -or
                $report.compatibility -notin @('COMPATIBLE', 'PARTIAL', 'BLOCKED') -or
                $doctor.exit_code -ne @{'COMPATIBLE'=0; 'PARTIAL'=1; 'BLOCKED'=2}[$report.compatibility]) {
                throw 'Doctor contract invalid'
            }
            $unavailable = @($report.diagnostics | Where-Object {
                ($_.category -eq 'UNSUPPORTED_VARIANT' -and $_.affected_board_area -eq 'schemas') -or
                ($_.category -eq 'SCHEMA_ERROR' -and $_.message -match 'VALIDATOR_UNAVAILABLE|SCHEMA_UNAVAILABLE')
            })
            if ($unavailable.Count -gt 0) {
                $doctor.reason = 'DOCTOR_REQUIREMENTS_OR_SCHEMAS_UNAVAILABLE'
            } else {
                $doctor.blocking_diagnostic_count = @($report.diagnostics | Where-Object { $_.blocking }).Count
                $doctor.safe_deterministic_count = @($report.diagnostics | Where-Object { $_.repairability -eq 'SAFE_DETERMINISTIC' }).Count
                $doctor.agent_repairable_count = @($report.diagnostics | Where-Object { $_.repairability -eq 'AGENT_REPAIRABLE' }).Count
                $doctor.decision_required_count = @($report.diagnostics | Where-Object { $_.repairability -eq 'DECISION_REQUIRED' }).Count
                $doctor.unsupported_count = @($report.diagnostics | Where-Object { $_.repairability -eq 'UNSUPPORTED' }).Count
                $doctor.repair_status = $report.repair_status
                $doctor.compatibility = $report.compatibility
                $doctor.reason = $null
            }
            $doctor.report = $report
        } catch { }
    }

    $handoff = Join-Path $Root '.mxagile/state/last-update-result.json'
    $json = $result | ConvertTo-Json -Depth 30
    try {
        [System.IO.File]::WriteAllText($handoff, $json + "`n", [System.Text.UTF8Encoding]::new($false))
    } catch {
        Write-Host 'Compatibility handoff could not be saved; consume the result below.' -ForegroundColor Yellow
    }
    Write-Host ''
    Write-Host 'MxAgile update completion (framework and project compatibility are separate):'
    Write-Host "Update: SUCCESS"
    $previousVersion = if ($CoreProvenance.previous_version) { $CoreProvenance.previous_version } else { 'UNKNOWN' }
    $previousCommit = if ($CoreProvenance.previous_commit) { $CoreProvenance.previous_commit } else { 'UNKNOWN' }
    $commit = if ($CoreProvenance.commit) { $CoreProvenance.commit } else { 'UNKNOWN' }
    Write-Host "Framework previous: $previousVersion / $previousCommit"
    Write-Host "Framework installed: $($CoreProvenance.version) / $commit"
    Write-Host "Contract migration: $($result.migration.status)"
    Write-Host "Doctor executed: $($doctor.executed)"
    Write-Host "PROJECT_COMPATIBILITY: $($doctor.compatibility)"
    if ($doctor.reason) { Write-Host "  Reason: $($doctor.reason)" }
    if ($doctor.compatibility -eq 'NOT_VERIFIED') {
        Write-Host '  Blocking diagnostics / SAFE_DETERMINISTIC / AGENT_REPAIRABLE / DECISION_REQUIRED / UNSUPPORTED: UNKNOWN'
    } else {
        Write-Host "  Blocking diagnostics: $($doctor.blocking_diagnostic_count); repair status: $($doctor.repair_status)"
        Write-Host "  SAFE_DETERMINISTIC: $($doctor.safe_deterministic_count); AGENT_REPAIRABLE: $($doctor.agent_repairable_count); DECISION_REQUIRED: $($doctor.decision_required_count); UNSUPPORTED: $($doctor.unsupported_count)"
    }
    if ($null -ne $doctor.report) {
        Write-Host "  PROJECT_COMPATIBILITY_CHECKED: $($doctor.report.compatibility) (read-only; no repairs applied)."
        if ($doctor.compatibility -ne 'COMPATIBLE') {
            $diagnostics = @($doctor.report.diagnostics | Sort-Object -Property @{Expression='blocking'; Descending=$true}, source_path, category)
            foreach ($diagnostic in ($diagnostics | Select-Object -First 10)) {
                Write-Host "  $($diagnostic.category): $($diagnostic.source_path) (blocking=$($diagnostic.blocking); $($diagnostic.repairability))"
            }
            if ($diagnostics.Count -gt 10) { Write-Host "  Remaining diagnostics: $($diagnostics.Count - 10); see handoff." }
        }
    }
    Write-Host 'Agent completion MUST report framework success AND project compatibility; read .mxagile/state/last-update-result.json.'
    Write-Host 'SESSION_CONTRACT: RE_SYNC_REQUIRED (installed projections do not reload this running session).'
    Write-Host 'Before answering, explicitly re-read .mxagile/policies/update-contract.md and follow its same-session contract re-sync, including active instructions/skills.'
    Write-Host 'Report CONTRACTS_RE_SYNCED only after successful re-reads; otherwise UPDATE_INSTALLED_RESTART_REQUIRED and Project compatibility NOT_VERIFIED.'
    $countFields = @('blocking_diagnostic_count', 'safe_deterministic_count', 'agent_repairable_count', 'decision_required_count', 'unsupported_count')
    $counts = foreach ($field in $countFields) {
        $value = if ($null -eq $doctor[$field]) { 'UNKNOWN' } else { $doctor[$field] }
        "$field=$value"
    }
    Write-Host "version=$($CoreProvenance.version) commit=$commit Framework_update=SUCCESS Doctor_executed=$($doctor.executed) Compatibility=$($doctor.compatibility) repair_status=$($doctor.repair_status) $($counts -join ' ') SESSION_CONTRACT=RE_SYNC_REQUIRED; re-read .mxagile/policies/update-contract.md before completion; otherwise UPDATE_INSTALLED_RESTART_REQUIRED / NOT_VERIFIED"
    $summary = [ordered]@{ installed_at = $result.installed_at; framework = $result.framework; migration = $result.migration; session_contract = $result.session_contract; doctor = [ordered]@{} }
    foreach ($key in $doctor.Keys) {
        if ($key -ne 'report') { $summary.doctor[$key] = $doctor[$key] }
    }
    Write-Output ($summary | ConvertTo-Json -Depth 10 -Compress)
}

function Invoke-BoardSmokeOffer {
    # Optional and advisory: the smoke result never changes the installer exit code.
    # Offered only after a Core update, only interactively, never in CI; -BoardSmoke is the explicit opt-in.
    param([string]$Root, [string]$ToolsDir, [bool]$Requested, [bool]$IsUpdateRun)

    $ciVariables = @('CI', 'TF_BUILD', 'GITHUB_ACTIONS', 'GITLAB_CI', 'JENKINS_URL', 'BUILD_BUILDID', 'TEAMCITY_VERSION')
    $inCi = @($ciVariables | Where-Object { -not [string]::IsNullOrEmpty([Environment]::GetEnvironmentVariable($_)) }).Count -gt 0
    $interactive = [Environment]::UserInteractive -and -not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected -and -not $inCi

    if (-not $Requested) {
        if (-not $IsUpdateRun) { return }
        if (-not $interactive) {
            Write-Host 'Board Smoke: NOT RUN (non-interactive)'
            return
        }
    }
    $smokeScript = Join-Path $ToolsDir 'board_smoke.py'
    $pythonCommand = Get-Command python -ErrorAction SilentlyContinue
    if (-not $pythonCommand) { $pythonCommand = Get-Command python3 -ErrorAction SilentlyContinue }
    if (-not $pythonCommand) {
        Write-Host 'Board Smoke: UNAVAILABLE (Python not found)'
        return
    }
    if (-not (Test-Path -LiteralPath $smokeScript -PathType Leaf)) {
        Write-Host 'Board Smoke: UNAVAILABLE (board_smoke.py not installed)'
        return
    }
    if (-not $Requested) {
        $answer = Read-Host 'Run the bounded Board smoke check now? It starts the Board locally for a few seconds (opt-in) [y/N]'
        if ($answer -notmatch '^(y|yes|j|ja)$') {
            Write-Host 'Board Smoke: NOT RUN (declined)'
            return
        }
    }
    $PSNativeCommandUseErrorActionPreference = $false
    $smokeOutput = & $pythonCommand.Source -B $smokeScript --project-root $Root --format json 2>$null
    $smokeExit = $LASTEXITCODE
    try {
        $smoke = ($smokeOutput -join "`n") | ConvertFrom-Json
        Write-Host "Board Smoke: $($smoke.result) ($($smoke.duration_seconds) s; exit $smokeExit; reported separately from Doctor)"
        foreach ($warning in @($smoke.warnings)) { if ($warning) { Write-Host "  WARNING: $warning" } }
        foreach ($failure in @($smoke.failures | Select-Object -First 3)) { Write-Host "  FAILURE [$($failure.stage)] $($failure.kind): $($failure.message)" }
    } catch {
        Write-Host "Board Smoke: ERROR (no parsable result; exit $smokeExit)"
    }
}

function Add-ContextModeRuntimeGitIgnore {
    param([Parameter(Mandatory = $true)][string]$Root)

    $gitignorePath = Join-Path $Root '.gitignore'
    $content = if (Test-Path -LiteralPath $gitignorePath -PathType Leaf) {
        [System.IO.File]::ReadAllText($gitignorePath)
    } else { '' }
    $existing = @($content -split '\r?\n' | ForEach-Object { $_.Trim().TrimStart('/').Replace('\', '/') })
    $required = @('.context-mode/', '.github/context-mode/', '.mxagile/state/runs/')
    $missing = @($required | Where-Object { $_ -notin $existing })
    if ($missing.Count -gt 0) {
        $newline = if ($content -match "`r`n") { "`r`n" } else { "`n" }
        $block = '# MxAgile Context Mode runtime state (session-owned; do not commit)' + $newline + ($missing -join $newline) + $newline
        if ($content.Length -gt 0) {
            $separator = if ($content -match '(\r\n|\n|\r)$') { $newline } else { $newline + $newline }
            $block = $separator + $block
        }
        [System.IO.File]::AppendAllText($gitignorePath, $block, [System.Text.UTF8Encoding]::new($false))
    }

    $gitCommand = Get-Command git -ErrorAction SilentlyContinue
    if (-not $gitCommand) { return }
    & $gitCommand.Source -C $Root rev-parse --git-dir 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { return }

    # Existing negation rules can override a correct-looking earlier entry.
    $probe = '.mxagile/state/runs/append.lock'
    & $gitCommand.Source -C $Root check-ignore --quiet -- $probe 2>$null
    if ($LASTEXITCODE -ne 0) {
        $current = [System.IO.File]::ReadAllText($gitignorePath)
        $newline = if ($current -match "`r`n") { "`r`n" } else { "`n" }
        $separator = if ($current.Length -eq 0 -or $current -match '(\r\n|\n|\r)$') { $newline } else { $newline + $newline }
        [System.IO.File]::AppendAllText($gitignorePath, $separator + '# MxAgile Run Event runtime files (including locks)' + $newline + '.mxagile/state/runs/' + $newline, [System.Text.UTF8Encoding]::new($false))
        & $gitCommand.Source -C $Root check-ignore --quiet -- $probe 2>$null
        if ($LASTEXITCODE -ne 0) { throw 'RUN_EVENT_STORE_NOT_GITIGNORED: .mxagile/state/runs/append.lock is not ignored.' }
    }
}

# =========================================================================
# PowerShell Version Preflight (RF-005)
# MxAgile requires PowerShell 7+ (pwsh). Windows PowerShell 5.x is NOT
# supported — it has known encoding and parsing incompatibilities that cause
# cryptic mid-install failures. Fail before any state mutation.
# =========================================================================
if ($PSVersionTable.PSVersion.Major -lt 7) {
    $installedVersion = $PSVersionTable.PSVersion.ToString()
    Write-Host ""
    Write-Host "ERROR: PowerShell 7 or later is required to install or update MxAgile." -ForegroundColor Red
    Write-Host ""
    Write-Host "  Detected: Windows PowerShell $installedVersion"
    Write-Host "  Required: PowerShell 7+ (pwsh)"
    Write-Host ""
    Write-Host "Install PowerShell 7:"
    Write-Host "  winget install Microsoft.PowerShell"
    Write-Host "  https://aka.ms/powershell"
    Write-Host ""
    Write-Host "Then re-run the setup script with: pwsh -File mxagile-setup.ps1"
    Write-Host ""
    exit 1
}

try {
    # =========================================================================
    # 0. Pre-flight: Legacy DFC-AI Detection
    # =========================================================================

    $ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
    if (-not (Test-Path -LiteralPath $ProjectRoot -PathType Container)) {
        throw "ProjectRoot directory not found: $ProjectRoot"
    }
    $updateTransactionPath = Join-Path $ProjectRoot '.mxagile/state/update-transaction.json'

    if (Test-Path -LiteralPath (Join-Path $ProjectRoot '.git')) {
        $guardPython = Get-Command python -ErrorAction SilentlyContinue
        if (-not $guardPython) { $guardPython = Get-Command python3 -ErrorAction SilentlyContinue }
        if (-not $guardPython) { throw 'GIT_INDEX_NOT_CHECKED: Python unavailable; update stopped before mutation.' }
        $PSNativeCommandUseErrorActionPreference = $false
        $guardOutput = & $guardPython.Source (Join-Path $PSScriptRoot 'git_index_integrity.py') --project-root $ProjectRoot
        if ($LASTEXITCODE -ne 0) {
            Write-Host ($guardOutput -join "`n")
            throw 'Git index preflight blocked update; no automatic recovery or lock removal.'
        }
    }

    if ($ResumeUpdate) {
        Invoke-CoreProjectionResume -Root $ProjectRoot -DeferCompatibility ([bool]$DeferPostUpdateCompatibility)
        exit 0
    }

    $detectScript = Join-Path $PSScriptRoot "detect-project-type.ps1"
    if (-not (Test-Path -LiteralPath $detectScript)) {
        throw "detect-project-type.ps1 not found in script directory."
    }

    Write-Host "Running project type detection..."
    $detectionJson = & $detectScript -ProjectRoot $ProjectRoot
    $detection = $detectionJson | ConvertFrom-Json

    Write-Host "  Detected: $($detection.Classification)"

    if ($detection.Classification -eq "LEGACY_DFC_PROJECT") {
        Write-Host ""
        Write-Host "========================================================"  -ForegroundColor Yellow
        Write-Host "MxAgile Installation: MIGRATION REQUIRED"                   -ForegroundColor Yellow
        Write-Host "========================================================"  -ForegroundColor Yellow
        Write-Host ""
        Write-Host "An existing DFC-AI installation was detected in:"           -ForegroundColor White
        Write-Host "  $ProjectRoot"                                              -ForegroundColor White
        Write-Host ""
        Write-Host "Normal MxAgile initialization was NOT performed."           -ForegroundColor White
        Write-Host "DFC-AI artifacts found:"                                    -ForegroundColor White
        foreach ($ev in $detection.DfcEvidence) {
            Write-Host "  - $ev"                                                -ForegroundColor DarkYellow
        }
        Write-Host ""

        # Install minimal migration bootstrap
        $bootstrapScript = Join-Path $PSScriptRoot "install-migration-bootstrap.ps1"
        if (-not (Test-Path -LiteralPath $bootstrapScript)) {
            throw "install-migration-bootstrap.ps1 not found in script directory."
        }
        Write-Host "Installing migration bootstrap..."
        & $bootstrapScript `
            -ProjectRoot              $ProjectRoot `
            -ProvenanceFlavor         $ProvenanceFlavor `
            -ProvenanceCoreSource     $ProvenanceCoreSource `
            -ProvenanceCoreSourceType $ProvenanceCoreSourceType `
            -ProvenanceCoreRef        $ProvenanceCoreRef `
            -ProvenanceCoreSubdir     $ProvenanceCoreSubdir `
            -CompanyLayerSource       $CompanyLayerSource `
            -CompanyLayerSourceType   $CompanyLayerSourceType `
            -CompanyLayerRef          $CompanyLayerRef
        if ($LASTEXITCODE -ne 0) {
            throw "Migration bootstrap installation failed with exit code $LASTEXITCODE."
        }

        Write-Host ""
        Write-Host "========================================================"  -ForegroundColor Cyan
        Write-Host "Start a NEW agent session in this project directory"       -ForegroundColor Cyan
        Write-Host "and enter:"                                                  -ForegroundColor Cyan
        Write-Host ""
        Write-Host "    Migrate this existing DFC-AI project to MxAgile"       -ForegroundColor Yellow
        Write-Host "    according to the migration instructions in"             -ForegroundColor Yellow
        Write-Host "    .mxagile/migration/"                                    -ForegroundColor Yellow
        Write-Host ""
        Write-Host "The migration agent will safely inventory, preserve, and"  -ForegroundColor Cyan
        Write-Host "migrate your existing project artifacts without loss of"    -ForegroundColor Cyan
        Write-Host "project knowledge."                                          -ForegroundColor Cyan
        Write-Host "========================================================"  -ForegroundColor Cyan
        Write-Host ""
        Write-Output "MIGRATION_REQUIRED"
        exit 2
    }

    if ($detection.Classification -eq "AMBIGUOUS") {
        Write-Host ""
        Write-Host "========================================================"  -ForegroundColor Red
        Write-Host "MxAgile Installation: AMBIGUOUS PROJECT STATE"              -ForegroundColor Red
        Write-Host "========================================================"  -ForegroundColor Red
        Write-Host ""
        Write-Host "Both DFC-AI and MxAgile markers were found:"               -ForegroundColor White
        Write-Host "  DFC-AI evidence:"                                         -ForegroundColor DarkYellow
        foreach ($ev in $detection.DfcEvidence) { Write-Host "    - $ev" }
        Write-Host "  MxAgile evidence:"                                        -ForegroundColor Cyan
        foreach ($ev in $detection.MxAgileEvidence) { Write-Host "    - $ev" }
        Write-Host ""
        Write-Host "Manual review required. Resolve the conflict before"        -ForegroundColor White
        Write-Host "retrying installation."                                      -ForegroundColor White
        Write-Host "========================================================"  -ForegroundColor Red
        Write-Host ""
        exit 3
    }

    if ($detection.Classification -eq "MIGRATION_IN_PROGRESS") {
        Write-Host ""
        Write-Host "  Resuming migration: proceeding with canonical MxAgile installation."
        Write-Host ""
        # Fall through to normal installation below
    }

    # =========================================================================
    # 1. Core Installation
    # =========================================================================

    Write-Host "---"
    Write-Host "Step 1: Core Installation" -ForegroundColor Cyan
    Write-Host "---"

    Write-Host "Project root: $ProjectRoot"

    # Preflight: Check for exactly one .mpr file
    $mprFiles = @(Get-ChildItem -Path $ProjectRoot -Filter "*.mpr" -File)
    if ($mprFiles.Count -ne 1) {
        throw "Expected exactly one .mpr file in the project root, but found $($mprFiles.Count). Please specify a valid Mendix project directory."
    }
    Write-Host "[OK] Project preflight check passed (found $($mprFiles.Name))"

    # Derive project name from .mpr filename (authoritative Mendix project identity).
    # Materialize into mxagile-project.yaml after mxagile-init.ps1 runs (Step 1a).
    $mprProjectName = [System.IO.Path]::GetFileNameWithoutExtension($mprFiles[0].Name)

    # mxcli init may regenerate host/project MCP configuration whose ownership and merge
    # contract are not known to MxAgile Core. If initialization is required, fail before
    # even additive project writes rather than overwriting a foreign host configuration.
    $mxcliInitMarkersBefore = @('CLAUDE.md', 'AGENTS.md', 'AGENT.md')
    $mxcliMarkersCompleteBefore = ($mxcliInitMarkersBefore | ForEach-Object {
        Test-Path -LiteralPath (Join-Path $ProjectRoot $_) -PathType Leaf
    } | Where-Object { $_ -eq $false } | Measure-Object).Count -eq 0
    $mxcliInitProvenanceBefore = Join-Path (Join-Path (Join-Path $ProjectRoot '.mxagile') 'state') 'mxcli-init.txt'
    $mxcliInitWouldRun = -not ($IsUpdate -and ((Test-Path -LiteralPath $mxcliInitProvenanceBefore -PathType Leaf) -or $mxcliMarkersCompleteBefore))
    $hostMcpConfigPaths = @('.mcp.json', '.vscode/mcp.json', '.agents/mcp_config.json', '.cortex/mcp.json')
    $existingHostMcpConfigs = @($hostMcpConfigPaths | Where-Object {
        Test-Path -LiteralPath (Join-Path $ProjectRoot $_) -PathType Leaf
    })
    if ($mxcliInitWouldRun -and $existingHostMcpConfigs.Count -gt 0) {
        throw "HOST_CONFIG_CONFLICT: mxcli init --all-tools would run while host/unknown MCP configuration exists ($($existingHostMcpConfigs -join ', ')); resolve ownership before setup. No project mutation has started."
    }

    $updateStage = 'PROJECTION_PREFLIGHT'
    $distributionRoot = Split-Path $PSScriptRoot -Parent
    foreach ($requiredScript in @('install-core.ps1', 'setup-agent-system.ps1', 'apply-project-agent-instructions.ps1', 'generate-mxagile-platform-skills.ps1')) {
        $tokens = $null; $parseErrors = $null
        [Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot $requiredScript), [ref]$tokens, [ref]$parseErrors) > $null
        if ($parseErrors) { throw "Projection input script is syntactically invalid: $requiredScript" }
    }
    $mocketeerSkillSource = Join-Path $distributionRoot 'products/MxMocketeer/skills'
    $expectedMocketeerSkills = @('mocketeer-discovery','mocketeer-design-contract','mocketeer-refinement','mocketeer-preservation','mocketeer-business-flows','mocketeer-mockup-generation','mocketeer-handoff')
    $sourceMocketeerSkills = @(Get-ChildItem -LiteralPath $mocketeerSkillSource -Directory -Filter 'mocketeer-*' -Force)
    if ((@($sourceMocketeerSkills.Name | Sort-Object) -join ',') -ne (@($expectedMocketeerSkills | Sort-Object) -join ',')) { throw 'Mocketeer source must contain exactly seven canonical skills before Core mutation.' }
    foreach ($skill in $sourceMocketeerSkills) { if (-not (Test-Path -LiteralPath (Join-Path $skill.FullName 'SKILL.md') -PathType Leaf)) { throw "Missing canonical SKILL.md: $($skill.Name)" } }
    $projectionPreflight = & (Join-Path $PSScriptRoot 'generate-mxagile-platform-skills.ps1') -ProjectRoot $ProjectRoot -SourceRoot (Join-Path $distributionRoot '.mxagile') -BundledSkillRoot (Join-Path $distributionRoot 'products/MxMocketeer/skills') -PreflightOnly -PassThru
    if (-not $projectionPreflight.ready) { throw 'Projection preflight did not produce a complete safe output plan.' }
    $previousArtifactContract = Get-CoreArtifactContract -Root $ProjectRoot
    if ($IsUpdate) {
        if (-not $ProvenanceCoreCommit) { $ProvenanceCoreCommit = (& git -C $distributionRoot rev-parse HEAD 2>$null | Select-Object -First 1) }
        $versionText = Get-Content -LiteralPath (Join-Path $distributionRoot '.mxagile/version.yaml') -Raw -Encoding utf8
        $targetVersion = if ($versionText -match '(?m)^version:\s+"?([^"\s]+)') { $Matches[1] } else { 'UNKNOWN' }
        if (Test-Path -LiteralPath $updateTransactionPath -PathType Leaf) {
            $transaction = Get-Content -LiteralPath $updateTransactionPath -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable
            if (-not $DeferPostUpdateCompatibility -or $transaction.state -ne 'UPDATE_IN_PROGRESS') { throw 'An active update requires explicit -ResumeUpdate, not another Core installation.' }
        } else {
            $transaction = New-MxAgileCoreUpdateTransaction -Root $ProjectRoot -TargetCore @{ version=$targetVersion; commit=$ProvenanceCoreCommit; source=$ProvenanceCoreSource; source_type=$ProvenanceCoreSourceType; ref=$ProvenanceCoreRef } -CompanySource $CompanyLayerSource -CompanyRef $CompanyLayerRef
            $ownsUpdateTransaction = $true
        }
        $priorProjectionPath=Join-Path $ProjectRoot '.mxagile/state/projections-manifest.json'
        $priorProjectionCommit=if (Test-Path -LiteralPath $priorProjectionPath -PathType Leaf) { (Get-Content -LiteralPath $priorProjectionPath -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable).generated_from_core_commit } else { $null }
        $transaction.projection = @{ status='PREFLIGHT_READY'; previous_commit=$priorProjectionCommit; target_commit=$ProvenanceCoreCommit; ownership_baseline=@($projectionPreflight.ownership_baseline); plan_fingerprint=$projectionPreflight.plan_fingerprint; core_applied=$false; contract_migration_started=$false; doctor_executed=$false; consumer_artifacts_changed=$false }
        $transaction.current_stage='PROJECT_INITIALIZATION'
        Save-MxAgileUpdateTransaction -Root $ProjectRoot -Transaction $transaction
    }
    $updateMutationStarted = $true
    $updateStage = 'PROJECT_INITIALIZATION'
    Add-ContextModeRuntimeGitIgnore -Root $ProjectRoot

    # Step 1a: MxAgile directory scaffold  -  also installs mxcli.exe
    $initScript = Join-Path $PSScriptRoot "mxagile-init.ps1"
    if (-not (Test-Path -LiteralPath $initScript)) {
        throw "mxagile-init.ps1 not found in script directory."
    }
    Write-Host "Calling mxagile-init.ps1..."
    & $initScript -ProjectRoot $ProjectRoot
    Write-Host "[OK] mxagile-init.ps1 executed."

    # Materialize project name into mxagile-project.yaml if still a template placeholder.
    # mxagile-init.ps1 creates the file with name: "[PROJEKTNAME]"; resolve it now.
    $projectYamlPath = Join-Path $ProjectRoot "mxagile-project.yaml"
    if (Test-Path -LiteralPath $projectYamlPath -PathType Leaf) {
        try {
            $yamlContent = [System.IO.File]::ReadAllText($projectYamlPath, [System.Text.UTF8Encoding]::new($false))
            if ($yamlContent -match '\[PROJEKTNAME\]') {
                $yamlContent = $yamlContent -replace '\[PROJEKTNAME\]', $mprProjectName
                [System.IO.File]::WriteAllText($projectYamlPath, $yamlContent, [System.Text.UTF8Encoding]::new($false))
                Write-Host "[OK] mxagile-project.yaml: materialized project name '$mprProjectName'"
            }
        } catch { }
    }

    # Step 1b: mxcli init --all-tools
    # ORDERING CONSTRAINT: must run AFTER mxcli is installed (Step 1a) and
    # BEFORE MxAgile managed-block injection (Step 2), because mxcli init overwrites
    # CLAUDE.md and AGENTS.md — MxAgile then re-injects its managed block.
    #
    # INSTALL vs UPDATE behavior:
    #   NEW INSTALL : always run — generates CLAUDE.md, AGENTS.md, AGENT.md, devcontainer, etc.
    #   UPDATE      : skip if key mxcli-generated files already exist and are not stale.
    #                 MxAgile managed-block injection is idempotent on existing files.
    #                 Re-running mxcli init on every UPDATE generates devcontainer/tool noise
    #                 unrelated to the framework change.
    #
    # Files that prove mxcli init has run at least once (minimum required presence check):
    $mxcliInitMarkers = @("CLAUDE.md", "AGENTS.md", "AGENT.md")
    $mxcliAlreadyInitialized = $IsUpdate -and ($mxcliInitMarkers | ForEach-Object {
        Test-Path -LiteralPath (Join-Path $ProjectRoot $_) -PathType Leaf
    } | Where-Object { $_ -eq $false } | Measure-Object).Count -eq 0

    # Platform-aware mxcli binary name (mxcli.exe on Windows, mxcli on Linux/macOS)
    $isWindowsPlatform = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
        [System.Runtime.InteropServices.OSPlatform]::Windows)
    $mxcliName = if ($isWindowsPlatform) { 'mxcli.exe' } else { 'mxcli' }
    $mxcliExe = Join-Path $ProjectRoot $mxcliName
    if (-not (Test-Path -LiteralPath $mxcliExe -PathType Leaf)) {
        throw "$mxcliName not found after mxagile-init.ps1 -- mxcli installation may have failed."
    }

    # More robust check: prefer provenance marker over bare file existence.
    # After successful mxcli init, a provenance marker is written to .mxagile/state/mxcli-init.txt.
    # This marker stores the mxcli version at init time and is more reliable than checking
    # whether CLAUDE.md/AGENTS.md happen to exist (which could be created by other means).
    #
    # If mxcli exposes a stronger initialization-state mechanism in future, replace this with it
    # rather than inventing redundant state. See upstream finding in policies/local-runtime-profile.md.
    $mxcliInitProvenanceFile = [System.IO.Path]::Combine($ProjectRoot, ".mxagile", "state", "mxcli-init.txt")
    $provenanceExists = Test-Path -LiteralPath $mxcliInitProvenanceFile -PathType Leaf

    # Fall back to marker-file check if provenance file is absent (first run after this contract was introduced)
    if ($IsUpdate -and -not $provenanceExists) {
        $mxcliAlreadyInitialized = ($mxcliInitMarkers | ForEach-Object {
            Test-Path -LiteralPath (Join-Path $ProjectRoot $_) -PathType Leaf
        } | Where-Object { $_ -eq $false } | Measure-Object).Count -eq 0
        if ($mxcliAlreadyInitialized) {
            Write-Host "[INFO] mxcli-init provenance file absent; using file-existence fallback for UPDATE check."
        }
    } elseif ($IsUpdate -and $provenanceExists) {
        $mxcliAlreadyInitialized = $true
        $provenanceContent = Get-Content -LiteralPath $mxcliInitProvenanceFile -Raw -ErrorAction SilentlyContinue
        Write-Host "[INFO] mxcli-init provenance: $provenanceContent"
    }

    if ($mxcliAlreadyInitialized) {
        Write-Host "[SKIP] mxcli init --all-tools: UPDATE and mxcli integration already initialized."
        Write-Host "       To force re-initialization: delete .mxagile/state/mxcli-init.txt and re-run."
    } else {
        Write-Host "Running mxcli init --all-tools ($(if ($IsUpdate) { 'UPDATE: not yet initialized' } else { 'NEW INSTALL' }))..."
        & $mxcliExe init --all-tools $ProjectRoot
        if ($LASTEXITCODE -ne 0) { throw "mxcli init --all-tools failed with exit code $LASTEXITCODE." }
        Write-Host "[OK] mxcli init --all-tools completed."

        # Write provenance marker for future UPDATE runs
        $stateDir = Join-Path $ProjectRoot ".mxagile\state"
        if (-not (Test-Path -LiteralPath $stateDir -PathType Container)) {
            New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
        }
        $mxcliVersion = "unknown"
        try {
            $mxcliVersion = (& $mxcliExe --version 2>&1 | Select-Object -First 1).ToString().Trim()
        } catch { }
        $provenanceContent = "mxcli_version=$mxcliVersion`ninitialized_at=$(Get-Date -Format 'yyyy-MM-dd')"
        [System.IO.File]::WriteAllText($mxcliInitProvenanceFile, $provenanceContent, [System.Text.Encoding]::UTF8)
        Write-Host "[OK] mxcli-init provenance written to .mxagile/state/mxcli-init.txt"
    }

    # =========================================================================
    # Step 1b-fix: Bootstrap SessionStart fixup (runs on EVERY install/update)
    # =========================================================================
    # mxcli init generates bootstrap-mxcli.sh with a blocking
    #   exec ./mxcli run --local --setup --ensure-db
    # which holds the Claude Code VS Code Extension's hook-wait loop open for
    # 60+ seconds and triggers "Subprocess initialization did not complete
    # within 60000ms".
    #
    # This step removes that line and adds a bounded curl download timeout so
    # both fresh installs and existing-project UPDATEs receive a safe bootstrap.
    # It is idempotent: projects that already have the safe variant are untouched.
    $bootstrapPath = Join-Path $ProjectRoot ".claude\bootstrap-mxcli.sh"
    if (Test-Path -LiteralPath $bootstrapPath -PathType Leaf) {
        $bsRaw = Get-Content -LiteralPath $bootstrapPath -Raw
        # Normalize line endings for consistent processing
        $bsLines = $bsRaw -replace "`r`n", "`n" -replace "`r", "`n" -split "`n"
        $changed = $false

        $resultLines = [System.Collections.Generic.List[string]]::new()
        $timeoutVarInserted = $false

        foreach ($line in $bsLines) {
            # 1) Remove the blocking exec line (exact form generated by mxcli init)
            if ($line -match '^exec\s+\./mxcli\s+run\s+--local') {
                $changed = $true
                Write-Host "[FIX] bootstrap-mxcli.sh: removed blocking 'exec ./mxcli run --local' from SessionStart."
                continue  # drop this line
            }

            # 2) Add bounded download timeout to curl if absent
            if ($line -match 'curl\s+-fsSL' -and $line -notmatch '--max-time') {
                $line = $line -replace '(curl\s+-fsSL)', '$1 --max-time "$DL_TIMEOUT" --connect-timeout 10'
                $changed = $true
            }

            $resultLines.Add($line)

            # 3) Insert DL_TIMEOUT variable on the line following the TAG= assignment
            if ($line -match '^TAG=' -and -not $timeoutVarInserted -and ($bsRaw -notmatch 'DL_TIMEOUT=')) {
                $resultLines.Add('DL_TIMEOUT="${MXCLI_DOWNLOAD_TIMEOUT:-30}"')
                $timeoutVarInserted = $true
                $changed = $true
            }
        }

        if ($changed) {
            # Append explanatory comment if not already present
            $joined = $resultLines -join "`n"
            if ($joined -notmatch '--setup.*--ensure-db.*NOT run here|NOT run here') {
                $resultLines.Add('')
                $resultLines.Add('# Runtime provisioning (--setup, --ensure-db) is NOT run here — it would block')
                $resultLines.Add('# Claude Code VS Code Extension initialization.  Run explicitly when needed:')
                $resultLines.Add('#   ./mxcli run --local --setup --ensure-db -p "${MPR}"')
            }
            $fixedContent = ($resultLines -join "`n").TrimEnd() + "`n"
            [System.IO.File]::WriteAllText($bootstrapPath, $fixedContent, [System.Text.Encoding]::UTF8)
            Write-Host "[OK] bootstrap-mxcli.sh SessionStart fixup applied."
        } else {
            Write-Host "[OK] bootstrap-mxcli.sh: SessionStart is already safe (no fix needed)."
        }
    } else {
        Write-Host "[INFO] .claude/bootstrap-mxcli.sh not found -- skipping SessionStart fixup."
    }

    # Normalize mxcli-generated SessionStart hook registrations structurally.
    # This runs after mxcli init on fresh installs and on every UPDATE, while
    # preserving unrelated hooks and failing without edits on ambiguous JSON.
    $sessionStartNormalizer = Join-Path $PSScriptRoot 'Normalize-MxcliSessionStart.ps1'
    if (-not (Test-Path -LiteralPath $sessionStartNormalizer -PathType Leaf)) {
        throw "SessionStart normalizer not found: $sessionStartNormalizer"
    }
    & $sessionStartNormalizer -SettingsPath (Join-Path $ProjectRoot '.claude\settings.json')

    # Step 1c: Copy canonical .mxagile/ payload (skills, agents, policies, lifecycle.yaml, etc.)
    # The canonical source is at $PSScriptRoot/../.mxagile/ (the framework dev tree).
    $canonicalSource = [System.IO.Path]::GetFullPath((Join-Path (Join-Path $PSScriptRoot "..") ".mxagile"))
    if (-not (Test-Path -LiteralPath $canonicalSource -PathType Container)) {
        throw "Canonical .mxagile/ source not found at: $canonicalSource"
    }
    Write-Host "Installing canonical MxAgile payload from: $canonicalSource"
    $destMxAgile = Join-Path $ProjectRoot ".mxagile"
    # Exclude 'layers'  -  Company Layer content; installed through its own mechanism.
    # Exclude 'state'   -  Framework-internal state (trace indexes, tool caches). Must never be
    #                    distributed from the framework dev repository.
    #                    NOTE: durable project lifecycle state is in planning/lifecycle/ (Git-tracked),
    #                    not in .mxagile/state/ — see policies/project-knowledge.md.
    #                    The empty state/ scaffold is created by mxagile-init.ps1.
    #
    # PS5.1 nesting-bug fix: when a same-named subdirectory already exists at the destination,
    # Copy-Item -LiteralPath places the SOURCE directory INSIDE the existing one instead of
    # merging contents (e.g. skills/skills/*.md instead of skills/*.md).
    # Fix: use content-merge - pre-create each destination subdirectory, then copy with -Path "*".
    #
    # Step 1c.1: Ownership-aware stale file retirement
    # Content-merge (Copy-Item without Remove-Item) preserves files that were intentionally
    # removed from the canonical source between Core versions. Left unchecked, the project's
    # framework surface diverges from the intended version (updated-install != fresh-install).
    # Fix: clear all framework-owned content from .mxagile/ before the canonical copy so the
    # resulting surface always matches the canonical source exactly.
    # Protected dirs are never touched: layers/ (Company Layer), state/ (runtime state),
    # migration/ (project migration history - never in canonical source).
    $protectedMxAgileDirs = @("layers", "state", "migration")
    $retiredCount = 0
    Get-ChildItem -LiteralPath $destMxAgile -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.PSIsContainer) {
            if ($protectedMxAgileDirs -notcontains $_.Name) {
                Remove-Item -LiteralPath $_.FullName -Recurse -Force
                $retiredCount++
            }
        } else {
            Remove-Item -LiteralPath $_.FullName -Force
            $retiredCount++
        }
    }
    Write-Host "[OK] Stale framework-owned content cleared ($retiredCount items) - canonical copy proceeds fresh."

    Get-ChildItem -LiteralPath $canonicalSource -Exclude "layers", "state" | ForEach-Object {
        if ($_.PSIsContainer) {
            # Content-merge: copy directory CONTENTS to the named subdirectory.
            # This avoids the PS5.1 nesting bug AND preserves project-owned subdirs
            # (e.g. .mxagile/migration/) that have no canonical counterpart.
            $destSubDir = Join-Path $destMxAgile $_.Name
            if (-not (Test-Path -LiteralPath $destSubDir -PathType Container)) {
                New-Item -ItemType Directory -Path $destSubDir -Force | Out-Null
            }
            Copy-Item -Path (Join-Path $_.FullName '*') -Destination $destSubDir -Recurse -Force
        } else {
            Copy-Item -LiteralPath $_.FullName -Destination $destMxAgile -Force
        }
    }
    # Ensure state/ exists as an empty project-owned directory (mxagile-init.ps1 creates it
    # before this step, but guard here so the contract holds even if init order changes).
    $destState = Join-Path $destMxAgile "state"
    if (-not (Test-Path -LiteralPath $destState -PathType Container)) {
        New-Item -ItemType Directory -Path $destState -Force | Out-Null
    }
    Write-Host "[OK] Canonical MxAgile payload installed."

    # Capability resolver: framework-owned tool inside .mxagile/ (cleared and re-copied on every
    # install/update by Step 1c.1), so it is never stale and never touches project-owned scripts/.
    $resolverSource = Join-Path $PSScriptRoot "Get-MxAgileCapabilities.ps1"
    if (-not (Test-Path -LiteralPath $resolverSource -PathType Leaf)) {
        throw "Get-MxAgileCapabilities.ps1 not found in script directory: $resolverSource"
    }
    $destToolsDir = Join-Path $destMxAgile "tools"
    New-Item -ItemType Directory -Path $destToolsDir -Force | Out-Null
    Copy-Item -LiteralPath $resolverSource -Destination (Join-Path $destToolsDir "Get-MxAgileCapabilities.ps1") -Force
    Write-Host "[OK] Distributed .mxagile/tools/Get-MxAgileCapabilities.ps1 (on-demand only)."

    $epochReaderSource = Join-Path $PSScriptRoot 'Read-MxAgileEpochCheckpoint.ps1'
    if (-not (Test-Path -LiteralPath $epochReaderSource -PathType Leaf)) {
        throw "Read-MxAgileEpochCheckpoint.ps1 not found in script directory: $epochReaderSource"
    }
    Copy-Item -LiteralPath $epochReaderSource -Destination (Join-Path $destToolsDir 'Read-MxAgileEpochCheckpoint.ps1') -Force
    Write-Host "[OK] Distributed .mxagile/tools/Read-MxAgileEpochCheckpoint.ps1."
    $epochWriterSource = Join-Path $PSScriptRoot 'Write-MxAgileEpochCheckpoint.ps1'
    Copy-Item -LiteralPath $epochWriterSource -Destination (Join-Path $destToolsDir 'Write-MxAgileEpochCheckpoint.ps1') -Force

    foreach ($delegationTool in @('Save-MxAgileDelegationResult.ps1', 'Get-MxAgileDelegationResult.ps1', 'Save-MxAgileRoutingDecision.ps1')) {
        $delegationToolSource = Join-Path $PSScriptRoot $delegationTool
        if (-not (Test-Path -LiteralPath $delegationToolSource -PathType Leaf)) {
            throw "$delegationTool not found in script directory: $delegationToolSource"
        }
        Copy-Item -LiteralPath $delegationToolSource -Destination (Join-Path $destToolsDir $delegationTool) -Force
        Write-Host "[OK] Distributed .mxagile/tools/$delegationTool."
    }

    # Control plane (experimental product path): read-only guard, host adapter, child acceptance.
    $controlPlaneSource = Join-Path (Split-Path -Parent $PSScriptRoot) 'experiments/control-plane'
    $controlPlaneDest = Join-Path $destToolsDir 'control-plane'
    New-Item -ItemType Directory -Path $controlPlaneDest -Force | Out-Null
    foreach ($controlPlaneFile in @('guard.py', 'enforcement.py', 'child_contract.py', 'control-plane-verdict.schema.json')) {
        $controlPlaneFileSource = Join-Path $controlPlaneSource $controlPlaneFile
        if (-not (Test-Path -LiteralPath $controlPlaneFileSource -PathType Leaf)) {
            throw "Control-plane component not found: $controlPlaneFileSource"
        }
        Copy-Item -LiteralPath $controlPlaneFileSource -Destination (Join-Path $controlPlaneDest $controlPlaneFile) -Force
    }
    foreach ($runEventFile in @(@{ Source = (Join-Path $PSScriptRoot 'run_events.py'); Name = 'run_events.py' },
                                 @{ Source = (Join-Path $PSScriptRoot 'run-event.schema.json'); Name = 'run-event.schema.json' })) {
        if (-not (Test-Path -LiteralPath $runEventFile.Source -PathType Leaf)) { throw "Run event component missing: $($runEventFile.Source)" }
        Copy-Item -LiteralPath $runEventFile.Source -Destination (Join-Path $controlPlaneDest $runEventFile.Name) -Force
    }
    Write-Host '[OK] Distributed .mxagile/tools/control-plane/ (guard, adapter, acceptor, run-event writer/schema).'
    $hookRegistration = & (Join-Path $PSScriptRoot 'Register-MxAgileControlPlaneHook.ps1') -SettingsPath (Join-Path $ProjectRoot '.claude\settings.json')
    $hookStatus = ($hookRegistration | ConvertFrom-Json).status
    if ($hookStatus -eq 'UNKNOWN_OWNERSHIP') {
        Write-Host "[WARN] CONTROL_PLANE_HOOK: UNKNOWN_OWNERSHIP - .claude/settings.json left unchanged; enforcement is NOT active." -ForegroundColor Yellow
    } else {
        Write-Host "[OK] CONTROL_PLANE_HOOK: $hookStatus (Claude Code PreToolUse)."
    }

    $mxcliResolverSource = Join-Path $PSScriptRoot "Resolve-MxAgileMxcli.ps1"
    if (-not (Test-Path -LiteralPath $mxcliResolverSource -PathType Leaf)) {
        throw "Resolve-MxAgileMxcli.ps1 not found in script directory: $mxcliResolverSource"
    }
    Copy-Item -LiteralPath $mxcliResolverSource -Destination (Join-Path $destToolsDir "Resolve-MxAgileMxcli.ps1") -Force
    Write-Host "[OK] Distributed .mxagile/tools/Resolve-MxAgileMxcli.ps1."

    $runtimeRecipeSource = Join-Path $PSScriptRoot 'mxcli_runtime_recipe.py'
    if (-not (Test-Path -LiteralPath $runtimeRecipeSource -PathType Leaf)) {
        throw "mxcli_runtime_recipe.py not found in script directory: $runtimeRecipeSource"
    }
    Copy-Item -LiteralPath $runtimeRecipeSource -Destination (Join-Path $destToolsDir 'mxcli_runtime_recipe.py') -Force
    Write-Host '[OK] Distributed .mxagile/tools/mxcli_runtime_recipe.py.'

    $studioProDetectorSource = Join-Path $PSScriptRoot "check-studio-pro-status.ps1"
    if (-not (Test-Path -LiteralPath $studioProDetectorSource -PathType Leaf)) {
        throw "check-studio-pro-status.ps1 not found in script directory: $studioProDetectorSource"
    }
    Copy-Item -LiteralPath $studioProDetectorSource -Destination (Join-Path $destToolsDir "check-studio-pro-status.ps1") -Force
    Write-Host "[OK] Distributed .mxagile/tools/check-studio-pro-status.ps1."

    $projectStatusSource = Join-Path $PSScriptRoot "build_project_status.py"
    if (-not (Test-Path -LiteralPath $projectStatusSource -PathType Leaf)) {
        throw "build_project_status.py not found in script directory: $projectStatusSource"
    }
    Copy-Item -LiteralPath $projectStatusSource -Destination (Join-Path $destToolsDir "build_project_status.py") -Force
    Write-Host "[OK] Distributed .mxagile/tools/build_project_status.py (read-only projection)."

    $reconciliationSource = Join-Path $PSScriptRoot "reconcile_external_changes.py"
    if (-not (Test-Path -LiteralPath $reconciliationSource -PathType Leaf)) {
        throw "reconcile_external_changes.py not found in script directory."
    }
    Copy-Item -LiteralPath $reconciliationSource -Destination (Join-Path $destToolsDir "reconcile_external_changes.py") -Force
    Write-Host "[OK] Distributed .mxagile/tools/reconcile_external_changes.py (read-only report; explicit baseline adoption)."
    $reconciliationGitSource = Join-Path $PSScriptRoot "reconciliation_git.py"
    if (-not (Test-Path -LiteralPath $reconciliationGitSource -PathType Leaf)) {
        throw "reconciliation_git.py not found in script directory."
    }
    Copy-Item -LiteralPath $reconciliationGitSource -Destination (Join-Path $destToolsDir "reconciliation_git.py") -Force
    Write-Host "[OK] Distributed .mxagile/tools/reconciliation_git.py (parent-aware delta verification)."
    $timelineSource = Join-Path $PSScriptRoot "build_project_timeline.py"
    if (-not (Test-Path -LiteralPath $timelineSource -PathType Leaf)) {
        throw "build_project_timeline.py not found in script directory."
    }
    Copy-Item -LiteralPath $timelineSource -Destination (Join-Path $destToolsDir "build_project_timeline.py") -Force
    Write-Host "[OK] Distributed .mxagile/tools/build_project_timeline.py (derived project timeline; index only in the OS cache)."
    $impactResolverSource = Join-Path $PSScriptRoot "resolve_impact.py"
    if (-not (Test-Path -LiteralPath $impactResolverSource -PathType Leaf)) {
        throw "resolve_impact.py not found in script directory."
    }
    Copy-Item -LiteralPath $impactResolverSource -Destination (Join-Path $destToolsDir "resolve_impact.py") -Force
    Write-Host "[OK] Distributed .mxagile/tools/resolve_impact.py (read-only impact fingerprint support)."
    foreach ($securityProjectionTool in @("security_projection.py", "generate-security-matrix.ps1")) {
        $securityProjectionSource = Join-Path $PSScriptRoot $securityProjectionTool
        if (-not (Test-Path -LiteralPath $securityProjectionSource -PathType Leaf)) {
            throw "$securityProjectionTool not found in script directory."
        }
        Copy-Item -LiteralPath $securityProjectionSource -Destination (Join-Path $destToolsDir $securityProjectionTool) -Force
        Write-Host "[OK] Distributed .mxagile/tools/$securityProjectionTool (read-only Security Projection; opt-in generation)."
    }

    $projectBoardServerSource = Join-Path $PSScriptRoot "serve_project_board.py"
    if (-not (Test-Path -LiteralPath $projectBoardServerSource -PathType Leaf)) {
        throw "serve_project_board.py not found in script directory: $projectBoardServerSource"
    }
    Copy-Item -LiteralPath $projectBoardServerSource -Destination (Join-Path $destToolsDir "serve_project_board.py") -Force
    Write-Host "[OK] Distributed .mxagile/tools/serve_project_board.py (loopback only)."

    $boardSmokeSource = Join-Path $PSScriptRoot "board_smoke.py"
    if (-not (Test-Path -LiteralPath $boardSmokeSource -PathType Leaf)) {
        throw "board_smoke.py not found in script directory: $boardSmokeSource"
    }
    Copy-Item -LiteralPath $boardSmokeSource -Destination (Join-Path $destToolsDir "board_smoke.py") -Force
    Write-Host "[OK] Distributed .mxagile/tools/board_smoke.py (opt-in bounded Board smoke; never runs automatically)."

    $doctorSource = Join-Path $PSScriptRoot "project_compatibility.py"
    if (-not (Test-Path -LiteralPath $doctorSource -PathType Leaf)) {
        throw "project_compatibility.py not found in script directory."
    }
    Copy-Item -LiteralPath $doctorSource -Destination (Join-Path $destToolsDir "project_compatibility.py") -Force
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'projection_io.py') -Destination (Join-Path $destToolsDir 'projection_io.py') -Force
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'wave_ids.py') -Destination (Join-Path $destToolsDir 'wave_ids.py') -Force
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'framework_update_recovery.py') -Destination (Join-Path $destToolsDir 'framework_update_recovery.py') -Force
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'git_index_integrity.py') -Destination (Join-Path $destToolsDir 'git_index_integrity.py') -Force
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'test_harness_cleanup.py') -Destination (Join-Path $destToolsDir 'test_harness_cleanup.py') -Force
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'mendix_merge_preflight.py') -Destination (Join-Path $destToolsDir 'mendix_merge_preflight.py') -Force
    Copy-Item -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) "requirements.txt") -Destination (Join-Path $destToolsDir "requirements.txt") -Force
    Write-Host "[OK] Distributed Compatibility Doctor and Python requirements."

    # =========================================================================
    # Core Installation Provenance
    # Writes machine-readable identity to .mxagile/state/core-provenance.json so
    # consumer agents can determine the installed Core without guessing repo paths.
    # =========================================================================
    $coreVersion = "unknown"
    try {
        $installedVersionYaml = Join-Path $destMxAgile "version.yaml"
        if (Test-Path -LiteralPath $installedVersionYaml -PathType Leaf) {
            $vc = Get-Content -LiteralPath $installedVersionYaml -Raw
            if ($vc -match '(?m)^version:\s+"?([^"\s\r\n]+)"?') { $coreVersion = $Matches[1] }
        }
    } catch { }

    $coreProvPath        = Join-Path $destState "core-provenance.json"
    $previousCommit      = $null
    $previousVersion     = $null
    $previousInstalledAt = $null
    $previousFlavor = $null
    $previousProductFlavor = $null
    if ($IsUpdate -and (Test-Path -LiteralPath $coreProvPath -PathType Leaf)) {
        try {
            $prevProv = Get-Content -LiteralPath $coreProvPath -Raw | ConvertFrom-Json -ErrorAction Stop
            if ($prevProv.PSObject.Properties.Name -contains 'commit')       { $previousCommit      = $prevProv.commit }
            if ($prevProv.PSObject.Properties.Name -contains 'version')      { $previousVersion     = $prevProv.version }
            if ($prevProv.PSObject.Properties.Name -contains 'installed_at') { $previousInstalledAt = $prevProv.installed_at }
            if ($prevProv.PSObject.Properties.Name -contains 'flavor') { $previousFlavor = $prevProv.flavor }
            if ($prevProv.PSObject.Properties.Name -contains 'product_flavor') { $previousProductFlavor = $prevProv.product_flavor }
        } catch { }
    }

    # Self-resolve source commit when caller did not provide it.
    # install-core.ps1 lives at <distribution>/scripts/ so its parent IS the distribution root.
    # This ensures commit is populated whether this script is called directly by a consumer agent
    # (following update_entry_point) or via mxagile-setup.ps1 which already resolved the commit.
    if ([string]::IsNullOrWhiteSpace($ProvenanceCoreCommit)) {
        try {
            $distRoot    = Split-Path $PSScriptRoot -Parent
            $resolvedSha = (& git -C $distRoot rev-parse HEAD 2>&1 |
                Select-Object -First 1).ToString().Trim()
            if ($resolvedSha -match '^[a-f0-9]{40}$') {
                $ProvenanceCoreCommit = $resolvedSha
            }
        } catch { }
    }

    $stableSourceIdentity = $null
    if ($ProvenanceCoreSourceType -eq 'git' -and -not [string]::IsNullOrWhiteSpace($ProvenanceCoreSource)) {
        $stableSourceIdentity = if ($ProvenanceCoreCommit) {
            "git:$ProvenanceCoreSource#$ProvenanceCoreCommit"
        } elseif ($ProvenanceCoreRef) {
            "git:$ProvenanceCoreSource@$ProvenanceCoreRef"
        } else { "git:$ProvenanceCoreSource" }
    } elseif ($ProvenanceCoreCommit) {
        $stableSourceIdentity = "commit:$ProvenanceCoreCommit"
    }
    $stagingSource = $null
    if (-not [string]::IsNullOrWhiteSpace($ProvenanceCoreSource)) {
        $tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
        try {
            $sourcePath = [System.IO.Path]::GetFullPath($ProvenanceCoreSource)
            if ($sourcePath.StartsWith($tempRoot, [System.StringComparison]::OrdinalIgnoreCase)) { $stagingSource = $ProvenanceCoreSource }
        } catch { }
    }

    $productFlavor = $previousProductFlavor
    if (-not $productFlavor -and $previousFlavor -and $previousFlavor -notin @('core', 'company-layer')) { $productFlavor = $previousFlavor }
    if ($ProvenanceFlavor -and $ProvenanceFlavor -notin @('core', 'company-layer')) { $productFlavor = $ProvenanceFlavor }
    $effectiveFlavor = if ($productFlavor) { $productFlavor } elseif ($ProvenanceFlavor) { $ProvenanceFlavor } else { $previousFlavor }
    $hasCompanyLayers = ($ProvenanceFlavor -eq 'company-layer') -or $CompanyLayerSource -or @(Get-ChildItem -LiteralPath (Join-Path $destMxAgile 'layers') -Directory -ErrorAction SilentlyContinue).Count -gt 0
    $recoveryTools = [ordered]@{}
    foreach ($tool in (Get-ChildItem -LiteralPath $destToolsDir -Filter '*.py' -Recurse -File)) {
        $relative = [System.IO.Path]::GetRelativePath($destToolsDir, $tool.FullName).Replace('\', '/')
        $recoveryTools[$relative] = (Get-FileHash -LiteralPath $tool.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    $recoveryTools['Write-MxAgileEpochCheckpoint.ps1'] = (Get-FileHash -LiteralPath (Join-Path $destToolsDir 'Write-MxAgileEpochCheckpoint.ps1') -Algorithm SHA256).Hash.ToLowerInvariant()
    $coreProv = [ordered]@{
        schema_version        = "1"
        activation_state      = 'CORE_APPLIED_PROJECTIONS_PENDING'
        flavor                = $effectiveFlavor
        product_flavor        = $productFlavor
        installation_flavor   = if ($hasCompanyLayers) { 'company-layer' } else { 'core' }
        artifact_contract     = Get-CoreArtifactContract -Root $ProjectRoot
        previous_artifact_contract = $previousArtifactContract
        recovery_tools        = $recoveryTools
        source                = $ProvenanceCoreSource
        source_type           = $ProvenanceCoreSourceType
        source_identity       = $stableSourceIdentity
        source_identity_status = if ($stableSourceIdentity) { 'STABLE' } else { 'NOT_STABLE' }
        staging_source        = $stagingSource
        ref                   = $ProvenanceCoreRef
        commit                = if ($ProvenanceCoreCommit) { $ProvenanceCoreCommit } else { $null }
        version               = $coreVersion
        installed_at          = (Get-Date -Format 'o')
        install_mode          = if ($IsUpdate) { "update" } else { "install" }
        previous_commit       = $previousCommit
        previous_version      = $previousVersion
        previous_installed_at = $previousInstalledAt
        distribution          = [ordered]@{
            canonical_url      = "https://github.com/Zwergomaniac/MxAgile.git"
            update_entry_point = "scripts/install-core.ps1"
            update_flag        = '-IsUpdate $true'
            distribution_owned = @(
                "scripts/install-core.ps1",
                "scripts/setup-agent-system.ps1",
                "scripts/generate-mxagile-platform-skills.ps1",
                "scripts/projection_io.py",
                "scripts/update-transaction.ps1"
            )
            consumer_note      = "Distribution-owned scripts are NOT consumer project artifacts. Their absence in a consumer project is expected and normal, never a defect."
            project_distributed = @(
                ".mxagile/tools/Get-MxAgileCapabilities.ps1",
                ".mxagile/tools/Read-MxAgileEpochCheckpoint.ps1",
                ".mxagile/tools/Write-MxAgileEpochCheckpoint.ps1",
                ".mxagile/tools/Save-MxAgileDelegationResult.ps1",
                ".mxagile/tools/Get-MxAgileDelegationResult.ps1",
                ".mxagile/tools/Save-MxAgileRoutingDecision.ps1",
                ".mxagile/tools/Resolve-MxAgileMxcli.ps1",
                ".mxagile/tools/mxcli_runtime_recipe.py",
                ".mxagile/tools/check-studio-pro-status.ps1",
                ".mxagile/tools/build_project_status.py",
                ".mxagile/tools/reconcile_external_changes.py",
                ".mxagile/tools/reconciliation_git.py",
                ".mxagile/tools/build_project_timeline.py",
                ".mxagile/tools/resolve_impact.py",
                ".mxagile/tools/security_projection.py",
                ".mxagile/tools/generate-security-matrix.ps1",
                ".mxagile/tools/serve_project_board.py",
                ".mxagile/tools/board_smoke.py",
                ".mxagile/tools/project_compatibility.py",
                ".mxagile/tools/git_index_integrity.py",
                ".mxagile/tools/test_harness_cleanup.py",
                ".mxagile/tools/mendix_merge_preflight.py",
                ".mxagile/tools/control-plane/guard.py",
                ".mxagile/tools/control-plane/enforcement.py",
                ".mxagile/tools/control-plane/child_contract.py",
                ".mxagile/tools/control-plane/control-plane-verdict.schema.json",
                ".mxagile/tools/control-plane/run_events.py",
                ".mxagile/tools/control-plane/run-event.schema.json",
                ".mxagile/tools/requirements.txt"
            )
        }
    }
    $coreProv | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $coreProvPath -Encoding UTF8
    if ($IsUpdate) {
        $transaction.target_core.version=$coreVersion; $transaction.target_core.commit=$coreProv.commit
        $transaction.projection.core_applied=$true; $transaction.projection.status='INCOMPLETE'
        $transaction.completed_stages=@(@($transaction.completed_stages) + 'CORE_UPDATE' | Select-Object -Unique)
        $transaction.current_stage='GENERATED_PROJECTIONS'
        Save-MxAgileUpdateTransaction -Root $ProjectRoot -Transaction $transaction
    }
    $shortCommit = if ($ProvenanceCoreCommit) { $ProvenanceCoreCommit.Substring(0,[Math]::Min(8,$ProvenanceCoreCommit.Length)) } else { "(unknown)" }
    Write-Host "[OK] Core provenance written to .mxagile/state/core-provenance.json"
    Write-Host "     version=$coreVersion  commit=$shortCommit  mode=$(if ($IsUpdate) { 'update' } else { 'install' })"

    # Step 1d: Post-install migration state reconciliation
    # For already-migrated projects that predate WP-10, artifact_canonicalization
    # is absent from state.yaml — the field did not exist at migration time.
    # Adding it as 'pending' here is the correct and safe default: the project's
    # legacy artifacts exist and have not yet been through canonical conversion.
    # This step is a no-op on fresh installations (no state.yaml present) and
    # idempotent on projects that already have the field.
    $migrationStateFile = Join-Path $ProjectRoot (Join-Path ".mxagile" (Join-Path "migration" "state.yaml"))
    if (Test-Path -LiteralPath $migrationStateFile -PathType Leaf) {
        $stateText = Get-Content -LiteralPath $migrationStateFile -Raw
        if ($stateText -match '(?m)^status:' -and $stateText -notmatch '(?m)^artifact_canonicalization:') {
            # Append the field — preserve all existing content unchanged
            $stateText = $stateText.TrimEnd("`r", "`n") + "`nartifact_canonicalization: pending`n"
            [System.IO.File]::WriteAllText(
                $migrationStateFile,
                $stateText,
                [System.Text.Encoding]::UTF8
            )
            Write-Host "[OK] Migration state reconciled: artifact_canonicalization: pending"
            Write-Host "     (pre-WP-10 project - existing artifacts not yet canonicalized)"
        } else {
            Write-Host "[OK] Migration state: artifact_canonicalization already set - no reconciliation needed."
        }
    }


    # Distribute update-mxcli.ps1
    $sourceMxCliScript = Join-Path $PSScriptRoot "install-mxcli.ps1"
    $destMxCliScript = Join-Path $ProjectRoot "update-mxcli.ps1"

    if (Test-Path -LiteralPath $sourceMxCliScript) {
        Copy-Item -LiteralPath $sourceMxCliScript -Destination $destMxCliScript -Force
        Write-Host "[OK] Distributed update-mxcli.ps1 to project."
    } else {
        Write-Warning "install-mxcli.ps1 not found, cannot distribute updater script."
    }


    # Install the independently owned Mocketeer product skills into the Core payload.
    # The product directory is the single source of their full Markdown content; the
    # existing platform generator projects these files after setup-agent-system starts.
    $installedSkillRoot = Join-Path $destMxAgile 'skills'
    foreach ($mocketeerSkill in $sourceMocketeerSkills) {
        $skillFile = Join-Path $mocketeerSkill.FullName 'SKILL.md'
        if (-not (Test-Path -LiteralPath $skillFile -PathType Leaf)) {
            throw "Mocketeer skill is missing SKILL.md: $($mocketeerSkill.Name)"
        }
        $installedSkill = Join-Path $installedSkillRoot $mocketeerSkill.Name
        if (Test-Path -LiteralPath $installedSkill) {
            throw "Mocketeer installer skill ownership conflict: $installedSkill"
        }
        New-Item -ItemType Directory -Path $installedSkill -Force | Out-Null
        Copy-Item -Path (Join-Path $mocketeerSkill.FullName '*') -Destination $installedSkill -Recurse -Force
    }
    Write-Host '[OK] Seven canonical Mocketeer skills installed into .mxagile/skills.'

    # Call setup-agent-system.ps1
    $setupScript = Join-Path $PSScriptRoot "setup-agent-system.ps1"
    if (-not (Test-Path -LiteralPath $setupScript)) {
        throw "setup-agent-system.ps1 not found in script directory."
    }
    Write-Host "Calling setup-agent-system.ps1..."
    $updateStage = 'GENERATED_PROJECTIONS'
    & $setupScript -ProjectRoot $ProjectRoot -CoreCommit $ProvenanceCoreCommit -CoreVersion $coreVersion -SourceRoot (Join-Path $distributionRoot '.mxagile') -BundledSkillRoot $mocketeerSkillSource -OwnershipBaseline @($projectionPreflight.ownership_baseline) -ExpectedPlanFingerprint $projectionPreflight.plan_fingerprint
    Write-Host "[OK] setup-agent-system.ps1 executed."
    $coreProv.activation_state='ACTIVE'
    $coreProv | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $coreProvPath -Encoding UTF8
    if ($IsUpdate) {
        $transaction.projection.status='COMPLETE'
        $transaction.completed_stages=@(@($transaction.completed_stages) + 'GENERATED_PROJECTIONS' | Select-Object -Unique)
        $transaction.current_stage='COMPANY_LAYER_UPDATE'
        Save-MxAgileUpdateTransaction -Root $ProjectRoot -Transaction $transaction
    }

    # =========================================================================
    # Reconciliation detection (informational only — setup does NOT perform
    # semantic Discovery/Refinement/Evidence reconciliation)
    # =========================================================================
    if ($IsUpdate) {
        $legacyArtifactLocations = @()

        # Detect legacy process-state location (pre-canonical-lifecycle-state-move)
        $scratchState = Join-Path $ProjectRoot ".concord\scratch\process-state.yaml"
        $canonicalState = Join-Path $ProjectRoot "planning\lifecycle\process-state.yaml"
        if ((Test-Path -LiteralPath $scratchState) -and (-not (Test-Path -LiteralPath $canonicalState))) {
            $legacyArtifactLocations += ".concord/scratch/process-state.yaml (migrate to planning/lifecycle/)"
        }

        # Detect legacy story location
        $storiesDir = Join-Path $ProjectRoot "planning\stories"
        if (Test-Path -LiteralPath $storiesDir -PathType Container) {
            $legacyArtifactLocations += "planning/stories/ (legacy format; canonical: requirements/REQ-NNN.yml)"
        }

        Write-Host ""
        if ($legacyArtifactLocations.Count -gt 0) {
            Write-Host "--- Reconciliation Notice ---" -ForegroundColor Yellow
            Write-Host "The following legacy artifact locations were detected:" -ForegroundColor Yellow
            foreach ($loc in $legacyArtifactLocations) {
                Write-Host "  * $loc" -ForegroundColor DarkYellow
            }
            Write-Host ""
            Write-Host "Reconciliation is NOT performed by setup." -ForegroundColor DarkGray
            Write-Host "Start a new agent session and invoke: Run MxAgile system check" -ForegroundColor DarkGray
            Write-Host "The reconciliation agent will inventory, preserve and migrate durable knowledge." -ForegroundColor DarkGray
        } else {
            Write-Host "  Reconciliation    : not required" -ForegroundColor DarkGray
        }
    }

    # =========================================================================
    # 2. Company Layer Installation (Optional)
    # =========================================================================
    $updateStage='COMPANY_LAYER_UPDATE'
    if ($CompanyLayerSource) {
        Write-Host "---"
        Write-Host "Step 2: Company Layer Installation" -ForegroundColor Cyan
        Write-Host "---"

        $layerId = $null
        $layerName = $null
        $destinationDir = $null

        # Auto-detect source type
        $resolvedSourceType = $CompanyLayerSourceType
        if ($resolvedSourceType -eq "Auto") {
            if (Test-Path -LiteralPath $CompanyLayerSource -PathType Container) {
                $resolvedSourceType = "Local"
            } else {
                $resolvedSourceType = "Git"
            }
            Write-Host "Auto-detected source type: $resolvedSourceType"
        }

        if ($resolvedSourceType -eq "Git") {
            # --- GIT SOURCE ---
            $fetchScript = Join-Path $PSScriptRoot "fetch-layer.ps1"
            if (-not (Test-Path -LiteralPath $fetchScript)) {
                throw "fetch-layer.ps1 not found in script directory."
            }
            Write-Host "Calling fetch-layer.ps1..."
            & $fetchScript -RepositoryUrl $CompanyLayerSource -Ref $CompanyLayerRef -ProjectRoot $ProjectRoot
            Write-Host "[OK] fetch-layer.ps1 executed."

            # For validation, we need to read the layer.json from the temp dir, which fetch-layer doesn't expose
            # We will rely on the output of fetch-layer.ps1 for success and find the layer afterwards for validation
            $layersDir = Join-Path $ProjectRoot ".mxagile\layers"
            # This is a bit brittle, we assume fetch-layer succeeded and there's only one layer.
            $installedLayer = Get-ChildItem -Path $layersDir | Select-Object -First 1
            if($installedLayer) {
                $layerId = $installedLayer.Name
                $destinationDir = $installedLayer.FullName
            }

        } elseif ($resolvedSourceType -eq "Local") {
            # --- LOCAL SOURCE ---
            Write-Host "Installing from local source: $CompanyLayerSource"
            $sourcePath = Resolve-Path -LiteralPath $CompanyLayerSource

            # 1. Validation
            if (-not (Test-Path -LiteralPath $sourcePath -PathType Container)) {
                throw "Local source directory not found: $sourcePath"
            }

            # 2. Safety
            $layersBaseDir = Resolve-Path -LiteralPath (Join-Path $ProjectRoot ".mxagile\layers")
            if ($sourcePath.ToString() -eq $layersBaseDir.ToString() -or $sourcePath.ToString().StartsWith($($layersBaseDir.ToString() + "\\"))) {
                throw "Safety error: The source directory cannot be the same as or inside the destination layers directory."
            }

            # 3. Manifest
            $manifestPath = Join-Path $sourcePath "layer.json"
            if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
                throw "layer.json not found in the source directory."
            }
            $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
            # Guard all property accesses against StrictMode throwing on absent properties
            $layerId            = try { [string]$manifest.id }            catch { "" }
            $layerName          = try { [string]$manifest.name }          catch { "" }
            $layerVersion       = try { [string]$manifest.version }       catch { "" }
            $layerSchemaVersion = try { [string]$manifest.schemaVersion } catch { "" }
            if ([string]::IsNullOrWhiteSpace($layerId)) {
                throw "layer.json is missing a valid 'id'."
            }
            Write-Host "Found Layer '$layerName' with ID '$layerId'."

            # 4. Destination
            $destinationDir = Join-Path $ProjectRoot ".mxagile\layers\$layerId"

            # 5. Copy — Layer-owned artifacts only (declared in layer.json → artifacts)
            if (Test-Path -LiteralPath $destinationDir) {
                Write-Host "Removing existing layer directory..."
                Remove-Item -LiteralPath $destinationDir -Recurse -Force
            }
            Write-Host "Copying layer contents to $destinationDir..."
            New-Item -Path $destinationDir -ItemType Directory -Force | Out-Null

            # artifacts is optional — guard against StrictMode throwing on absent property
            $localArtifacts = try { $manifest.artifacts } catch { $null }
            $localAllowed = [System.Collections.Generic.HashSet[string]]::new(
                [System.StringComparer]::OrdinalIgnoreCase)
            $localAllowed.Add("layer.json") | Out-Null
            if ($null -ne $localArtifacts) {
                foreach ($prop in $localArtifacts.PSObject.Properties) {
                    $topLevel = (([string]$prop.Value) -split '[/\\]', 2)[0].Trim()
                    if (-not [string]::IsNullOrWhiteSpace($topLevel)) {
                        $localAllowed.Add($topLevel) | Out-Null
                    }
                }
            }
            Get-ChildItem -LiteralPath "$sourcePath" -Force |
                Where-Object { $_.Name -ne ".git" -and
                               $_.Name -ne "provenance.json" -and
                               $localAllowed.Contains($_.Name) } |
                ForEach-Object {
                    $dest2 = Join-Path $destinationDir $_.Name
                    if ($_.PSIsContainer) {
                        Copy-Item -LiteralPath $_.FullName -Destination $dest2 -Recurse -Force
                    } else {
                        Copy-Item -LiteralPath $_.FullName -Destination $dest2 -Force
                    }
                }

            # 6. Provenance — UPDATE-CONTRACT.md field schema
            $provenancePath = Join-Path $destinationDir "provenance.json"
            $provenance = [ordered]@{
                layerId          = $layerId
                installedVersion = $layerVersion
                schemaVersion    = $layerSchemaVersion
                source_type      = "Local"
                sourceRepository = $sourcePath.ToString()
                sourceRef        = "local"
                sourceCommit     = $null
                installedAt      = (Get-Date -Format 'o')
                installedBy      = 'mxagile-core/install-core-local'
                previousVersion  = $null
                previousCommit   = $null
            }
            $provenance | ConvertTo-Json | Set-Content -LiteralPath $provenancePath -Encoding UTF8
            Write-Host "[OK] Provenance file created."

            # 7. Validation
            if (Test-Path -LiteralPath (Join-Path $destinationDir ".git")) {
                throw "Validation failed: .git directory was found in the installed layer."
            }
            Write-Host "[OK] Installation integrity verified (no .git directory)."
        }

        # --- Final Validation ---
        if (-not $destinationDir) {
             throw "Could not determine layer destination directory for validation."
        }
        $provenanceFile = Join-Path $destinationDir "provenance.json"
        if (-not (Test-Path -LiteralPath $destinationDir -PathType Container)) {
            throw "Final validation failed: Layer directory '$destinationDir' does not exist."
        }
        if (-not (Test-Path -LiteralPath $provenanceFile -PathType Leaf)) {
            throw "Final validation failed: Provenance file '$provenanceFile' does not exist."
        }
        Write-Host "[OK] Final validation passed for layer '$layerId'."
    }

    Write-Host ""
    Write-Host "[OK] Core installation complete." -ForegroundColor Green
    Write-Host "FRAMEWORK_INSTALLED (project compatibility is checked separately)."

    if ($DeferPostUpdateCompatibility) {
        Write-Host 'Post-update Doctor deferred to the enclosing multi-layer update transaction.' -ForegroundColor DarkYellow
        Write-Host 'Board Smoke deferred until the enclosing multi-layer update transaction completes.' -ForegroundColor DarkYellow
    } else {
        $updateStage='POST_UPDATE_DOCTOR'
        if ($ownsUpdateTransaction) {
            $transaction.completed_stages=@(@($transaction.completed_stages) + 'COMPANY_LAYER_UPDATE' | Select-Object -Unique)
            $transaction.current_stage='POST_UPDATE_DOCTOR'; $transaction.projection.contract_migration_started=$true
            Save-MxAgileUpdateTransaction -Root $ProjectRoot -Transaction $transaction
        }
        Invoke-PostUpdateCompatibility -Root $ProjectRoot -ToolsDir $destToolsDir -CoreProvenance $coreProv
        if ($ownsUpdateTransaction) { Complete-MxAgileCoreUpdateTransaction -Root $ProjectRoot -Transaction $transaction }
        Invoke-BoardSmokeOffer -Root $ProjectRoot -ToolsDir $destToolsDir -Requested ([bool]$BoardSmoke) -IsUpdateRun ([bool]$IsUpdate)
    }

    Write-Host ""
    Write-Host "--------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "MxAgile Recommended Validation:" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Start a NEW agent session in this project and enter:" -ForegroundColor White
    Write-Host ""
    Write-Host "  Run the MxAgile system check and output the complete diagnostic report." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  (New session required: the check must verify discovery from the" -ForegroundColor DarkGray
    Write-Host "   installed repository, not from this installation session.)" -ForegroundColor DarkGray
    if (-not $IsUpdate) {
        Write-Host ""
        Write-Host "  After the system check, simply describe what you want to achieve." -ForegroundColor Cyan
        Write-Host "  MxAgile will orient you and route the work — no agent or skill selection needed." -ForegroundColor DarkGray
    }
    Write-Host "--------------------------------------------------------" -ForegroundColor DarkGray

    exit 0

} catch {
    Write-Host ""
    Write-Host "[FAILED] Installation failed!" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    if ($IsUpdate -and $updateTransactionPath -and (Test-Path -LiteralPath $updateTransactionPath -PathType Leaf)) {
        try {
            $transaction = Get-Content -LiteralPath $updateTransactionPath -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable
            $coreAlreadyApplied=@($transaction['completed_stages']) -contains 'CORE_UPDATE'
            $updateMutationStarted=$updateMutationStarted -or ($ResumeUpdate -and $coreAlreadyApplied)
            $transaction.state = if ($updateMutationStarted) { 'PARTIAL_UPDATE' } else { 'BLOCKED_BEFORE_MUTATION' }
            if ($transaction.Contains('projection') -and $_.Exception.Data.Contains('projection_report')) { $transaction.projection.last_report=$_.Exception.Data['projection_report'] }
            $transaction.current_stage = $updateStage
            $transaction.failed_stage = $updateStage
            $transaction.failure = $_.Exception.Message
            $transaction.compatibility_status = 'NOT_VERIFIED'
            $transaction.context_state = if ($updateMutationStarted) { 'STALE' } else { 'UNCHANGED' }
            $transaction.resync_required = [bool]$updateMutationStarted
            $transaction.resume_available = [bool]$updateMutationStarted
            $transaction.updated_at = (Get-Date).ToUniversalTime().ToString('o')
            $transactionTempPath = "$updateTransactionPath.$([Guid]::NewGuid().ToString('N')).tmp"
            [System.IO.File]::WriteAllText($transactionTempPath, (($transaction | ConvertTo-Json -Depth 30) + "`n"), [System.Text.UTF8Encoding]::new($false))
            Move-Item -LiteralPath $transactionTempPath -Destination $updateTransactionPath -Force
        } catch { Write-Host "Update transaction failure state could not be persisted: $($_.Exception.Message)" -ForegroundColor Red }
    }
    exit 1
}
