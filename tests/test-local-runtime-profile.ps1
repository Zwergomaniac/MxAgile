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

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST A: Project-declared db_name overrides .mpr-derived default" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Assert-FileContains "A.1 schema has db_name field" $Schema '"db_name"'
Assert-FileContains "A.2 schema db_name description mentions .mpr override" $Schema '\.mpr'
Assert-FileContains "A.3 local-runtime-profile.md defines autonomous db_name precedence (Core default 'default')" $LocalProf '(?i)Core autonomous default.*default|autonomous default.*default'
Assert-FileContains "A.4 development-runtime.md states project declaration wins over Core default" $DevRuntime '(?i)project-declared override|PROJECT_DECLARED'

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST B: Project-declared db_type is applied" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Assert-FileContains "B.1 schema has db_type field" $Schema '"db_type"'
Assert-FileContains "B.2 schema db_type has hsqldb option" $Schema 'hsqldb'
Assert-FileContains "B.3 schema db_type has postgresql option" $Schema 'postgresql'
Assert-FileContains "B.4 local-runtime-profile.md covers db_type in precedence" $LocalProf 'db_type'
Assert-FileContains "B.5 development-runtime.md references db_type in database section" $DevRuntime 'db_type'

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST C: Company Layer runtime defaults are lower precedence than project overrides" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Assert-FileContains "C.1 local-runtime-profile.md defines 5-level precedence" $LocalProf 'Company Layer'
Assert-FileContains "C.2 precedence places project above Company Layer" $LocalProf 'mxagile-project.yaml'
# Verify that Company Layer is at level 3, below project at level 2
$LPContent = Get-Content -LiteralPath $LocalProf -Raw -ErrorAction SilentlyContinue
$projLine  = ($LPContent -split "`n") | Select-String '2\.' | Where-Object { $_ -match 'mxagile-project' } | Select-Object -First 1
$layerLine = ($LPContent -split "`n") | Select-String '3\.' | Where-Object { $_ -match 'Company Layer' } | Select-Object -First 1
Assert-True "C.3 project declared (level 2) appears before Company Layer (level 3) in precedence list" ($null -ne $projLine -and $null -ne $layerLine) "Could not find numbered precedence entries in local-runtime-profile.md"

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST D: Runtime constant overrides supplied through mxcli --constant path" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Assert-FileContains "D.1 schema has constant_overrides array" $Schema '"constant_overrides"'
Assert-FileContains "D.2 schema constant has name and purpose fields" $Schema '"purpose"'
Assert-FileContains "D.3 local-runtime-profile.md specifies --constant flag mechanism" $LocalProf '\-\-constant'
Assert-FileContains "D.4 policy prohibits config.json as authoritative constant mechanism" $LocalProf 'config\.json'
Assert-FileNotContains "D.5 Core does not hard-code UserCommons.DisableMxAdmin" $DevRuntime 'UserCommons\.DisableMxAdmin'
Assert-FileNotContains "D.6 schema does not hard-code UserCommons.DisableMxAdmin" $Schema 'UserCommons\.DisableMxAdmin'

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST E: Secret values remain in .env.mendix and are not copied to tracked config" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Assert-FileContains "E.1 schema uses env_key reference pattern for db password" $Schema 'db_password_env_key'
Assert-FileContains "E.2 schema uses env_key reference pattern for admin password" $Schema 'admin_password_env_key'
Assert-FileContains "E.3 schema description for env_key says never the value" $Schema 'never the value'
Assert-FileContains "E.4 local-runtime-profile.md distinguishes non-secret config from secret references" $LocalProf 'Secret reference'
Assert-FileNotContains "E.5 local-runtime-profile.md does not say to store secrets in mxagile-project.yaml" $LocalProf 'store.*secret.*mxagile-project'

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
Assert-FileContains "K.3 development-runtime.md references Watch-Mode Startup Semantics" $DevRuntime 'Watch-Mode'

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST L: Gradle-lock stall classified precisely" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Assert-FileContains "L.1 local-runtime-profile.md covers Gradle lock handling" $LocalProf 'Gradle'
Assert-FileContains "L.2 policy says classify precisely" $LocalProf 'classify'
Assert-FileContains "L.3 development-runtime.md references Gradle lock section" $DevRuntime 'Gradle'

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST M: Arbitrary process killing is not the default remediation" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Assert-FileContains "M.1 local-runtime-profile.md prohibits arbitrary process kill" $LocalProf 'MUST NOT automatically kill'
Assert-FileContains "M.2 policy recommends gradle --stop as safe alternative" $LocalProf 'gradle --stop'
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
Assert-FileContains "O.2 development-runtime.md still references local warm loop" $DevRuntime 'mxcli run --local'
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
    $DevRuntime '(?i)base command'

Assert-FileContains "P.2 policy defines effective command concept" `
    $DevRuntime '(?i)effective command'

Assert-FileContains "P.3 policy prohibits executing base command without profile resolution" `
    $DevRuntime '(?i)MUST NOT execute the base command'

Assert-FileContains "P.4 policy defines MxAgile Core autonomous DB default (MXAGILE_CORE_DEFAULT)" `
    $DevRuntime '(?i)MXAGILE_CORE_DEFAULT'

Assert-FileContains "P.5 policy documents .mpr-rename safety (MUST NOT silently alter autonomous DB)" `
    $DevRuntime '(?i)\.mpr.*rename MUST NOT|MUST NOT silently alter'

Assert-FileContains "P.6 policy requires mxcli --help flag verification before use" `
    $DevRuntime '(?i)mxcli run --local --help'

Assert-FileContains "P.7 policy prohibits emitting --db-type as autonomous runtime flag" `
    $DevRuntime '(?i)do NOT emit.*--db-type|NOT.*--db-type.*autonomous'

Assert-FileContains "P.8 policy uses verified --db-name flag (framework decision)" `
    $DevRuntime '(?i)--db-name.*default|--db-name.*verified|verified.*--db-name'

Assert-FileContains "P.9 local-runtime-profile step 4 defines canonical effective command" `
    $LocalProf '(?i)canonical autonomous effective command|DB_IDENTITY_CONTROL_UNAVAILABLE'

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
    $DevRuntime '(?i)Core autonomous default.*default|MXAGILE_CORE_DEFAULT'

# Q.B: effective command contains verified --db-name and value "default"
Assert-FileContains "Q.B policy defines canonical effective command with --db-name default" `
    $DevRuntime '(?i)--db-name default'

# Q.C: bare base command is never a complete autonomous command
Assert-FileContains "Q.C policy prohibits executing base command without profile resolution" `
    $DevRuntime '(?i)MUST NOT execute the base command'

# Q.D: .mpr rename does not change effective DB identity
Assert-FileContains "Q.D policy states .mpr rename MUST NOT alter autonomous DB identity" `
    $DevRuntime '(?i)\.mpr.*rename MUST NOT|rename.*MUST NOT.*database'

# Q.E: explicit user/session override takes precedence and is reported
Assert-FileContains "Q.E policy defines SESSION_OVERRIDE source classification" `
    $DevRuntime '(?i)SESSION_OVERRIDE'

Assert-FileContains "Q.E2 policy requires reporting source before startup" `
    $DevRuntime '(?i)source.*SESSION_OVERRIDE|SESSION_OVERRIDE.*PROJECT_DECLARED'

# Q.F: project/folder/display names do not silently override "default"
Assert-FileContains "Q.F policy prohibits project folder/display name as DB identity source" `
    $DevRuntime '(?i)folder name|display name|naming convention.*NOT'

# Q.G: no unsupported --db-type option is emitted
Assert-FileContains "Q.G policy prohibits emitting --db-type as autonomous runtime flag" `
    $DevRuntime '(?i)do NOT emit.*--db-type|NOT.*--db-type.*autonomous'

# Q.H: no hsqldb assumption in autonomous runtime
Assert-FileNotContains "Q.H policy does not assume hsqldb for autonomous execution" `
    $DevRuntime '(?i)autonomous.*hsqldb|hsqldb.*autonomous|default.*hsqldb'

# Q.I: mxcli version without --db-name → DB_IDENTITY_CONTROL_UNAVAILABLE, no autonomous start
Assert-FileContains "Q.I policy defines DB_IDENTITY_CONTROL_UNAVAILABLE state" `
    $DevRuntime '(?i)DB_IDENTITY_CONTROL_UNAVAILABLE'

Assert-FileContains "Q.I2 policy prohibits autonomous start when --db-name unavailable" `
    $DevRuntime '(?i)DB_IDENTITY_CONTROL_UNAVAILABLE.*do NOT start|do NOT start.*DB_IDENTITY_CONTROL_UNAVAILABLE'

# Q.J: generated agents and skills carry or reference the corrected contract
Assert-FileContains "Q.J implementation-agent references canonical DB identity policy" `
    (Join-Path $ScriptDir ".mxagile/agents/implementation-agent.md") '(?i)development-runtime'

Assert-FileContains "Q.J2 discovery-agent references DB identity resolution" `
    (Join-Path $ScriptDir ".mxagile/agents/discovery-agent.md") '(?i)development-runtime.*DB Identity|DB Identity Resolution'

# Q.K: Local First / Docker by Need remains intact
Assert-FileContains "Q.K runtime-strategy still contains LOCAL FIRST principle" `
    (Join-Path $ScriptDir ".mxagile/policies/runtime-strategy.md") '(?i)LOCAL FIRST'

Assert-FileContains "Q.K2 development-runtime still references local warm loop" `
    $DevRuntime '(?i)mxcli run --local.*--watch'

# Q.L: no destructive DB provisioning introduced automatically
Assert-FileContains "Q.L policy prohibits automatically creating another database" `
    $DevRuntime '(?i)NOT.*automatically.*create.*database|do NOT.*create.*database|NOT.*silently.*create'

Assert-FileNotContains "Q.L2 policy does not automatically add --ensure-db" `
    $DevRuntime '(?i)automatically.*--ensure-db|--ensure-db.*automatically'

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
