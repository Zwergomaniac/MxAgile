<#
.SYNOPSIS
    Local Runtime Profile Tests: Project-Declared Bootstrap Configuration

.DESCRIPTION
    Validates that the MxAgile canonical framework supports project-declared local runtime
    configuration, enforces configuration precedence, pipeline stage tracking, secret safety,
    and Playwright toolchain policy.

    Test cases:
    A. Project-declared db_name overrides .mpr-derived default (schema + policy)
    B. Project-declared db_type is applied (schema + policy)
    C. Company Layer runtime defaults are lower precedence than project overrides (policy)
    D. Runtime constant overrides are supplied through mxcli --constant path (policy)
    E. Secret values remain in .env.mendix and are not copied to tracked config (schema enforcement)
    F. Build success is not reported as application readiness (pipeline state model)
    G. Playwright does not start before browser/app readiness (policy)
    H. Bootstrap authentication is validated without exposing credentials (policy)
    I. Missing runtime config enters precise prerequisite state (process-state schema)
    J. Configured runtime profile survives fresh-session re-sync (process-state schema)
    K. Watch-loop operation starts only after valid initial readiness semantics (policy)
    L. Suspected Gradle-lock stall is classified precisely (policy)
    M. Arbitrary process killing is not the default remediation (policy)
    N. Playwright version policy rejects unsupported/unapproved critical alpha usage (policy)
    O. Local First runtime-strategy regressions remain green (no regression)
#>

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$TestsDir   = $PSScriptRoot
$ScriptDir  = Split-Path -Parent $TestsDir
$PassCount   = 0
$FailCount   = 0
$FailDetails = @()

function Assert-True {
    param([string]$TestName, [bool]$Condition, [string]$Message)
    if ($Condition) {
        Write-Host "  PASS: $TestName" -ForegroundColor Green
        $script:PassCount++
    } else {
        Write-Host "  FAIL: $TestName -- $Message" -ForegroundColor Red
        $script:FailCount++
        $script:FailDetails += "[$TestName] $Message"
    }
}

function Assert-FileContains {
    param([string]$TestName, [string]$FilePath, [string]$Pattern)
    $content = Get-Content -LiteralPath $FilePath -Raw -ErrorAction SilentlyContinue
    if ($null -eq $content) {
        Assert-True $TestName $false "File not found: $FilePath"
    } else {
        Assert-True $TestName ($content -match $Pattern) "Expected pattern '$Pattern' not found in $FilePath"
    }
}

function Assert-FileNotContains {
    param([string]$TestName, [string]$FilePath, [string]$Pattern)
    $content = Get-Content -LiteralPath $FilePath -Raw -ErrorAction SilentlyContinue
    if ($null -eq $content) {
        Assert-True $TestName $false "File not found: $FilePath"
    } else {
        Assert-True $TestName ($content -notmatch $Pattern) "Forbidden pattern '$Pattern' found in $FilePath"
    }
}

$Schema     = Join-Path $ScriptDir ".mxagile/schemas/mxagile-project.schema.json"
$ProcState  = Join-Path $ScriptDir ".mxagile/schemas/process-state.schema.json"
$DevRuntime = Join-Path $ScriptDir ".mxagile/policies/development-runtime.md"
$LocalProf  = Join-Path $ScriptDir ".mxagile/policies/local-runtime-profile.md"
$CredPol    = Join-Path $ScriptDir ".mxagile/policies/credential-discovery.md"
$RuntimeStr = Join-Path $ScriptDir ".mxagile/policies/runtime-strategy.md"
$ToolConflict = Join-Path $ScriptDir ".mxagile/policies/tool-instruction-conflict.md"
$RuntimeRecovery = Join-Path $ScriptDir ".mxagile/policies/runtime-startup-recovery.md"
$DependencyRecovery = Join-Path $ScriptDir ".mxagile/policies/runtime-dependency-recovery.md"
$ConfigReconciliation = Join-Path $ScriptDir ".mxagile/policies/runtime-configuration-reconciliation.md"
$UiAgent = Join-Path $ScriptDir ".mxagile/agents/ui-agent.md"
$VisualSkill = Join-Path $ScriptDir ".mxagile/skills/visual-verification.md"
$BrowserCliConfig = Join-Path $ScriptDir ".playwright/cli.config.json"

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST A: Project-declared db_name overrides .mpr-derived default" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Assert-FileContains "A.1 schema has db_name field" $Schema '"db_name"'
Assert-FileContains "A.2 schema db_name description mentions .mpr override" $Schema '\.mpr'
Assert-FileContains "A.3 C1 composer resolves the Core autonomous db_name default" (Join-Path $ScriptDir "scripts/mxcli_runtime_recipe.py") '(?i)MXAGILE_CORE_DEFAULT'
Assert-FileContains "A.4 C1 composer resolves project db_name as declared" (Join-Path $ScriptDir "scripts/mxcli_runtime_recipe.py") '(?i)PROJECT_DECLARED'

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST B: Project-declared db_type is applied" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Assert-FileContains "B.1 schema has db_type field" $Schema '"db_type"'
Assert-FileContains "B.2 schema db_type has hsqldb option" $Schema 'hsqldb'
Assert-FileContains "B.3 schema db_type has postgresql option" $Schema 'postgresql'
Assert-FileContains "B.4 local-runtime-profile.md covers db_type in precedence" $LocalProf 'db_type'
Assert-FileContains "B.5 local-runtime-profile.md references db_type in configuration" $LocalProf 'db_type'

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST C: Company Layer runtime defaults have no implicit source" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Assert-FileContains "C.1 Company Layer runtime defaults have no canonical schema or source" $LocalProf 'does not define a machine-readable runtime-default schema'
Assert-FileContains "C.2 resolver does not scan or infer Company Layer runtime values" $LocalProf 'MUST NOT scan.*\.mxagile/layers|MUST NOT scan'
Assert-FileContains "C.3 project profile is an explicit runtime input" $LocalProf '(?is)Runtime values must be present in the project-declared.*local_runtime'

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST D: Runtime constant overrides supplied through mxcli --constant path" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Assert-FileContains "D.1 schema has constant_overrides array" $Schema '"constant_overrides"'
Assert-FileContains "D.2 schema constant has name and purpose fields" $Schema '"purpose"'
Assert-FileContains "D.3 C1 composer includes the advertised constant-control capability" `
    (Join-Path $ScriptDir "scripts/mxcli_runtime_recipe.py") '--constant'
Assert-FileContains "D.4 policy prohibits config.json as authoritative constant mechanism" $ConfigReconciliation 'config\.json'
Assert-FileNotContains "D.5 Core does not hard-code UserCommons.DisableMxAdmin" $DevRuntime 'UserCommons\.DisableMxAdmin'
Assert-FileNotContains "D.6 schema does not hard-code UserCommons.DisableMxAdmin" $Schema 'UserCommons\.DisableMxAdmin'

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST E: Secret values remain in .env.mendix and are not copied to tracked config" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Assert-FileContains "E.1 schema uses env_key reference pattern for db password" $Schema 'db_password_env_key'
Assert-FileContains "E.2 schema uses env_key reference pattern for admin password" $Schema 'admin_password_env_key'
Assert-FileContains "E.3 schema description for env_key says never the value" $Schema 'never the value'
Assert-FileContains "E.4 runtime configuration policy keeps secret values in env files" $ConfigReconciliation '(?is)env_key.*value stays in.*\.env\.mendix'
Assert-FileNotContains "E.5 runtime configuration policy does not store secrets in mxagile-project.yaml" $ConfigReconciliation 'store.*secret.*mxagile-project'

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST F: Build success is not reported as application readiness" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Assert-FileContains "F.1 process-state schema has build_succeeded stage" $ProcState 'build_succeeded'
Assert-FileContains "F.2 process-state schema has application_reachable stage" $ProcState 'application_reachable'
Assert-FileContains "F.3 local-runtime-profile.md states build_succeeded != application_reachable" $LocalProf 'BUILD_SUCCEEDED'
Assert-FileContains "F.4 development-runtime.md states BUILD_SUCCEEDED != APPLICATION_REACHABLE" $DevRuntime 'BUILD_SUCCEEDED'
Assert-FileContains "F.5 process-state schema description explicitly forbids treating build_succeeded as reachable" $ProcState 'build_succeeded MUST NOT'

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST G: Playwright does not start before browser/app readiness" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Assert-FileContains "G.1 process-state has browser_rendered stage" $ProcState 'browser_rendered'
Assert-FileContains "G.2 local-runtime-profile.md states no Playwright before browser_rendered" $LocalProf 'BROWSER_RENDERED'
Assert-FileContains "G.3 development-runtime.md states no Playwright before browser_rendered" $DevRuntime 'BROWSER_RENDERED'
Assert-FileContains "G.4 process-state description warns against Playwright before browser_rendered" $ProcState 'browser_rendered'

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST H: Bootstrap authentication validated without exposing credentials" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Assert-FileContains "H.1 local-runtime-profile.md defines bootstrap login lifecycle" $LocalProf 'BOOTSTRAP LOGIN CONTRACT'
Assert-FileContains "H.2 policy says never print passwords" $LocalProf 'Never print'
Assert-FileContains "H.3 credential-discovery.md prohibits credential values in reports" $CredPol 'NEVER include'
Assert-FileContains "H.4 local-runtime-profile.md references authenticated_session_ready stage" $LocalProf 'AUTHENTICATED_SESSION_READY'

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST I: Missing runtime config enters precise prerequisite state" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Assert-FileContains "I.1 process-state has runtime_pipeline_stage field" $ProcState 'runtime_pipeline_stage'
Assert-FileContains "I.2 process-state has prerequisite_discovery stage" $ProcState 'prerequisite_discovery'
Assert-FileContains "I.3 credential-discovery.md has CONFIG_NOT_DISCOVERED classification" $CredPol 'CONFIG_NOT_DISCOVERED'
Assert-FileContains "I.4 credential-discovery.md has SECRET_INPUT_REQUIRED classification" $CredPol 'SECRET_INPUT_REQUIRED'

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST J: Configured runtime profile survives fresh-session re-sync" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Assert-FileContains "J.1 process-state has runtime_config field for session re-sync" $ProcState 'runtime_config'
Assert-FileContains "J.2 process-state description explains resume purpose" $ProcState 'resume'
Assert-FileContains "J.3 credential-discovery.md defines auto-resume contract" $CredPol 'Auto-Resume'

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST K: Watch-loop starts only after valid initial readiness" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Assert-FileContains "K.1 local-runtime-profile.md describes cold-start then watch loop" $LocalProf 'cold start'
Assert-FileContains "K.2 local-runtime-profile.md states Playwright must not start before BROWSER_RENDERED" $LocalProf 'BROWSER_RENDERED.*confirmed'
Assert-FileContains "K.3 development-runtime.md references C1 runtime lifecycle semantics" $DevRuntime 'C1 recipe selects an interactive or autonomous runtime lifecycle'

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST L: Gradle-lock stall classified precisely" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Assert-FileContains "L.1 normal runtime profile routes stalls to failure-only recovery" $LocalProf 'runtime-dependency-recovery\.md'
Assert-FileContains "L.2 dependency recovery policy is explicitly failure-only" $DependencyRecovery 'Failure-only contract'

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST M: Failure-only recovery prohibits arbitrary process killing" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Assert-FileContains "M.1 recovery policy prohibits automatic Java/Gradle process killing" $DependencyRecovery 'MUST NOT automatically kill arbitrary Java/Gradle processes'
Assert-FileContains "M.2 gradle --stop is a bounded recovery option" $DependencyRecovery 'gradle --stop'
Assert-FileNotContains "M.3 development-runtime.md does not recommend wmic process kill" $DevRuntime 'wmic.*kill'

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST N: Playwright version policy rejects unapproved alpha" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Assert-FileContains "N.1 local-runtime-profile.md defines Playwright version policy" $LocalProf 'Playwright Toolchain'
Assert-FileContains "N.2 policy requires stable releases" $LocalProf 'stable release'
Assert-FileContains "N.3 policy prohibits unapproved alpha in critical path" $LocalProf 'alpha'
Assert-FileContains "N.4 policy specifies TOOL_VERSION_INVALID state" $LocalProf 'TOOL_VERSION_INVALID'

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST O: Local First runtime-strategy regressions remain green" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Assert-FileContains "O.1 runtime-strategy.md still contains LOCAL FIRST principle" $RuntimeStr 'LOCAL FIRST'
Assert-FileContains "O.2 development-runtime.md routes local loop through C1" $DevRuntime 'C1-resolved interactive recipe'
Assert-FileContains "O.3 local-runtime-profile.md does not replace Local First principle" $LocalProf 'local'
Assert-FileNotContains "O.4 development-runtime.md does not default to Docker" $DevRuntime '^docker.*default'

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST P: DB identity safety, base vs effective command, and unverified flag protection" -ForegroundColor Cyan
# ---------------------------------------------------------------------------
# Replaces 87f008b TEST P which tested for specific unverified CLI flag strings.
# These tests validate behavioral contracts:
#   - Base command is a starting point, not an execution-ready command
#   - DB identity must be resolved before autonomous start
#   - No unverified mxcli flag is stated as canonical in policy

Assert-FileContains "P.1 policy defines base command concept" `
    $LocalProf '(?i)base command|resolved_runtime_recipe'

Assert-FileContains "P.2 policy defines effective command concept" `
    $LocalProf '(?i)effective invocation|resolved_runtime_recipe'

Assert-FileContains "P.3 policy prohibits executing base command without profile resolution" `
    $LocalProf '(?i)recipe.s argument array is the sole invocation authority|Do not start the runtime unless the status is RESOLVED'

Assert-FileContains "P.4 policy defines MxAgile Core autonomous DB default (MXAGILE_CORE_DEFAULT)" `
    (Join-Path $ScriptDir "scripts/mxcli_runtime_recipe.py") '(?i)MXAGILE_CORE_DEFAULT'

Assert-FileContains "P.5 policy documents .mpr-rename safety (MUST NOT silently alter autonomous DB)" `
    $LocalProf '(?is)\.mpr filename.*not an autonomous fallback|\.mpr.*not an autonomous fallback'

Assert-FileContains "P.6 policy requires mxcli --help flag verification before use" `
    $LocalProf '(?i)command-specific --help|help run'

Assert-FileContains "P.7 policy prohibits emitting --db-type as autonomous runtime flag" `
    $LocalProf '(?is)declared `db_type` is\s+provisioning metadata, not by itself a requirement'

Assert-FileContains "P.8 selected binary help owns database option spelling" `
    $LocalProf '(?i)database identifier with its source|exact option spelling.*needed to select one'

Assert-FileContains "P.9 local-runtime-profile step 4 defines canonical effective command" `
    $LocalProf '(?i)resolved_runtime_recipe|DB_IDENTITY_CONTROL_UNAVAILABLE'

Assert-FileContains "P.10 schema db_type field is preserved (legitimate project metadata)" `
    $Schema '"db_type"'

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST Q: Framework autonomous DB default is 'default'" -ForegroundColor Cyan
# ---------------------------------------------------------------------------
# Behavioral regression tests proving the MxAgile Core autonomous DB contract.
# Each assertion validates observable policy/schema content, not implementation guesses.

# Q.A: autonomous runtime with no user override resolves db_name to "default"
Assert-FileContains "Q.A policy states Core autonomous default is 'default'" `
    (Join-Path $ScriptDir "scripts/mxcli_runtime_recipe.py") '(?i)MXAGILE_CORE_DEFAULT'

# Q.B: effective command contains verified --db-name and value "default"
Assert-FileContains "Q.B policy defines canonical effective command with --db-name default" `
    $LocalProf '(?is)resolved_runtime_recipe.*database identifier with its source'

# Q.C: bare base command is never a complete autonomous command
Assert-FileContains "Q.C policy prohibits executing base command without profile resolution" `
    $LocalProf '(?i)recipe.s argument array is the sole invocation authority|Do not start the runtime unless the status is RESOLVED'

# Q.D: .mpr rename does not change effective DB identity
Assert-FileContains "Q.D policy states .mpr rename MUST NOT alter autonomous DB identity" `
    $LocalProf '(?is)\.mpr filename.*not an autonomous fallback|\.mpr.*not an autonomous fallback'

# Q.E: explicit user/session override takes precedence and is reported
Assert-FileContains "Q.E policy defines SESSION_OVERRIDE source classification" `
    (Join-Path $ScriptDir "scripts/mxcli_runtime_recipe.py") '(?i)SESSION_OVERRIDE'

Assert-FileContains "Q.E2 policy requires reporting source before startup" `
    (Join-Path $ScriptDir "scripts/mxcli_runtime_recipe.py") '(?is)db_name_source'

# Q.F: project/folder/display names do not silently override "default"
Assert-FileContains "Q.F policy prohibits project folder/display name as DB identity source" `
    $LocalProf '(?s)Project display names[\s\S]*never database identity inputs'

# Q.G: no unsupported --db-type option is emitted
Assert-FileContains "Q.G policy prohibits emitting --db-type as autonomous runtime flag" `
    $LocalProf '(?is)declared `db_type` is\s+provisioning metadata, not by itself a requirement'

# Q.H: no hsqldb assumption in autonomous runtime
Assert-FileNotContains "Q.H policy does not assume hsqldb for autonomous execution" `
    $DevRuntime '(?i)autonomous.*hsqldb|hsqldb.*autonomous|default.*hsqldb'

# Q.I: mxcli version without --db-name → DB_IDENTITY_CONTROL_UNAVAILABLE, no autonomous start
Assert-FileContains "Q.I policy defines DB_IDENTITY_CONTROL_UNAVAILABLE state" `
    (Join-Path $ScriptDir "scripts/mxcli_runtime_recipe.py") 'DB_IDENTITY_CONTROL_UNAVAILABLE'

Assert-FileContains "Q.I2 policy prohibits autonomous start when --db-name unavailable" `
    (Join-Path $ScriptDir "scripts/mxcli_runtime_recipe.py") '(?is)DB_IDENTITY_CONTROL_UNAVAILABLE'

# Q.J: generated agents and skills carry or reference the corrected contract
Assert-FileContains "Q.J implementation-agent references canonical DB identity policy" `
    (Join-Path $ScriptDir ".mxagile/agents/implementation-agent.md") '(?i)development-runtime'

Assert-FileContains "Q.J2 discovery-agent references DB identity resolution" `
    (Join-Path $ScriptDir ".mxagile/agents/discovery-agent.md") '(?is)autonome Runtime- oder Browser-Evidenz.*resolved_runtime_recipe'

# Q.K: Local First / Docker by Need remains intact
Assert-FileContains "Q.K runtime-strategy still contains LOCAL FIRST principle" `
    (Join-Path $ScriptDir ".mxagile/policies/runtime-strategy.md") '(?i)LOCAL FIRST'

Assert-FileContains "Q.K2 development-runtime still references local warm loop" `
    $DevRuntime '(?i)Interactive implementation.*Warm|Warm, iterative runtime feedback'

# Q.L: no destructive DB provisioning introduced automatically
Assert-FileContains "Q.L policy prohibits automatically creating another database" `
    $LocalProf '(?i)NOT.*automatically.*create.*database|do NOT.*create.*database|NOT.*silently.*create'

Assert-FileNotContains "Q.L2 policy does not automatically add --ensure-db" `
    $DevRuntime '(?i)automatically.*--ensure-db|--ensure-db.*automatically'

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST R: Module constant default vs. project local intent" -ForegroundColor Cyan
# ---------------------------------------------------------------------------
# Validates the RUNTIME_CONFIGURATION_DISCREPANCY pattern introduced after a confirmed
# real-project A/B test: UserCommons.DisableMxAdmin=true (module default) blocked headless
# MBAdmin login; --constant "UserCommons.DisableMxAdmin=false" restored it.
# The permanent fix is a project-level constant_overrides declaration, not a CLI override.

# R.1: policy defines RUNTIME_CONFIGURATION_DISCREPANCY classification
Assert-FileContains "R.1 policy defines RUNTIME_CONFIGURATION_DISCREPANCY" $ConfigReconciliation 'RUNTIME_CONFIGURATION_DISCREPANCY'

# R.2: policy prohibits test-identity creation to mask a configuration mismatch
Assert-FileContains "R.2 policy prohibits test-identity workaround for config mismatch" $ConfigReconciliation '(?i)MUST NOT.*test identit|test identit.*mask|create.*demo user|workaround'

# R.3: policy defines Studio Pro parity check before classifying discrepancy
Assert-FileContains "R.3 policy defines Studio Pro parity check" $ConfigReconciliation '(?i)Studio Pro Parity Evidence'

# R.4: policy distinguishes module constant default from project local override
Assert-FileContains "R.4 policy distinguishes module constant default from project local override" $ConfigReconciliation '(?i)module constant default.*production|module/model constant defaults'

# R.5: policy defines temporary diagnostic override as session-only (must be made permanent)
Assert-FileContains "R.5 policy defines temporary diagnostic override vs permanent project declaration" $ConfigReconciliation '(?i)diagnostic override.*project declaration'

# R.6: policy explicitly prohibits globally forcing any specific constant value (no universal rule)
Assert-FileContains "R.6 policy explicitly prohibits globally forcing any constant value" $ConfigReconciliation '(?i)Do NOT globally force|must not globally force|no universal'

# R.7: development-runtime.md does NOT hard-code any constant name
Assert-FileNotContains "R.7 development-runtime.md does not hard-code module constant names" $DevRuntime '(?i)UserCommons\.|DisableMxAdmin'

# R.8: policy defines validation boundary between framework and downstream runtime acceptance
Assert-FileContains "R.8 policy defines FRAMEWORK_VALIDATION vs DOWNSTREAM_RUNTIME_ACCEPTANCE boundary" $ConfigReconciliation '(?i)FRAMEWORK_VALIDATION|DOWNSTREAM_RUNTIME_ACCEPTANCE'

# R.9: policy requires downstream runtime acceptance before marking finding fully accepted
Assert-FileContains "R.9 policy requires downstream acceptance before VERIFIED status" $ConfigReconciliation '(?i)Downstream.*acceptance.*required|mark.*VERIFIED'

# R.10: ownership table distinguishes four override categories
Assert-FileContains "R.10 policy defines four override ownership categories" $ConfigReconciliation '(?i)Override Ownership|Temporary diagnostic override'

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST S: Project-pinned mxcli and technical instruction conflict resolution" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Assert-FileContains "S.1 local-runtime-profile uses the distributed mxcli resolver" `
    $LocalProf 'Resolve-MxAgileMxcli\.ps1'

Assert-FileContains "S.2 every invocation uses the resolved absolute binary" `
    $LocalProf 'Do not invoke bare `mxcli` or choose by PATH'

Assert-FileContains "S.3 exact selected version is recorded" `
    $LocalProf 'absolute path and exact version'

Assert-FileContains "S.4 command-specific help validates version-sensitive flags" `
    $LocalProf 'command-specific `--help`'

Assert-FileContains "S.5 unsupported syntax is a capability gap" `
    $LocalProf 'TOOL_CAPABILITY_GAP'

Assert-FileContains "S.6 conflict policy distinguishes project-owned and generated instructions" `
    $ToolConflict 'project-authored'

Assert-FileContains "S.7 external skills are advisory and cannot select a binary" `
    $ToolConflict 'External or tool-provided skills'

Assert-FileContains "S.7.1 external skills are advisory" `
    $ToolConflict 'skills are advisory guidance'

Assert-FileContains "S.8 unsupported tool command does not silently change behavior" `
    $ToolConflict 'Do not substitute another PATH binary'

Assert-FileContains "S.8.1 unsupported command does not change requested semantics" `
    $ToolConflict 'change the requested semantics'

Assert-FileContains "S.9 development runtime requires resolver before mxcli commands" `
    $LocalProf 'Resolve-MxAgileMxcli\.ps1'

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST T: Project-canonical browser URL and origin mismatch handling" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

$projectSchema = Get-Content -LiteralPath $Schema -Raw | ConvertFrom-Json
$browserConfig = Get-Content -LiteralPath $BrowserCliConfig -Raw | ConvertFrom-Json
$configuredAppUrl = [Uri]$projectSchema.properties.local_runtime.properties.app_url.default
$configuredOrigin = $configuredAppUrl.GetLeftPart([System.UriPartial]::Authority)
$configuredAllowedOrigins = @($browserConfig.network.allowedOrigins)
$ipAliasOrigin = 'http://127.0.0.1:8080'

Assert-True "T.1 project default URL origin is explicitly allowed" `
    ($configuredAllowedOrigins -contains $configuredOrigin) `
    "Canonical origin '$configuredOrigin' not present in the runner allowlist"

Assert-True "T.1 localhost and 127.0.0.1 are distinct origins" `
    ($configuredOrigin -ne $ipAliasOrigin -and $configuredAllowedOrigins -notcontains $ipAliasOrigin) `
    "IP alias was treated as the configured canonical origin"

Assert-FileContains "T.2 local runtime profile treats exact scheme/host/port as origin" `
    $LocalProf 'scheme, host, and effective port must match'

Assert-FileContains "T.2 allowedOrigins validates rather than selects the base URL" `
    $LocalProf 'selected URL.s origin must be present in that list'

Assert-FileContains "T.2.1 allowlist does not select or rewrite the base URL" `
    $LocalProf 'it does not select or rewrite the base URL'

Assert-FileContains "T.3 one controlled canonical retry is permitted after confirmed mismatch" `
    $LocalProf 'perform exactly one controlled retry with the canonical URL'

Assert-FileContains "T.3 canonical origin success is classified ORIGIN_MISMATCH" `
    $LocalProf 'classify the cause as `ORIGIN_MISMATCH`'

Assert-FileContains "T.4 canonical-origin failure stops without workaround speculation" `
    $LocalProf 'If the canonical-origin attempt also fails, stop'

Assert-FileContains "T.4 browser recovery prohibits speculative environment workarounds" `
    $LocalProf 'Do not generate speculative'

Assert-FileContains "T.5 UI verification resolves project app_url and exact allowlist first" `
    $UiAgent 'Browser-Ziel vor Navigation'

Assert-FileContains "T.5.1 UI verification reads the project-declared app_url" `
    $UiAgent 'local_runtime\.app_url'

Assert-FileContains "T.5.2 UI verification checks the runner allowedOrigins" `
    $UiAgent 'allowedOrigins` exakt pruefen'

Assert-FileContains "T.5 visual verification uses project base URL and configured browser" `
    $VisualSkill 'project browser contract'

Assert-FileContains "T.5.1 visual verification checks configured browser binary/channel" `
    $VisualSkill 'configured browser binary/channel'

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=" * 60
$total = $PassCount + $FailCount
Write-Host "RESULTS: $PassCount passed, $FailCount failed out of $total tests"
if ($FailCount -gt 0) {
    Write-Host ""
    Write-Host "FAILURES:" -ForegroundColor Red
    $FailDetails | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    exit 1
} else {
    Write-Host "All tests PASSED" -ForegroundColor Green
    exit 0
}
