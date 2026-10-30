<#
.SYNOPSIS
    Capability discovery routing + resolver distribution contract

.DESCRIPTION
    Static: the startup routing rule is short, generic, lazy and does not explain Context Mode;
    nothing in install/startup scripts invokes the resolver.
    E2E (GUID temp project, real install-core.ps1): fresh install and existing-project update
    distribute .mxagile/tools/Get-MxAgileCapabilities.ps1 and
    .mxagile/tools/check-studio-pro-status.ps1; the installed resolver is reachable,
    never executes context-mode, and repeated update is idempotent while project-owned
    files are preserved.

    No network is required by this test itself; install-core may skip network-dependent steps.
#>

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$RepoRoot = Split-Path -Parent $PSScriptRoot
$Scripts  = Join-Path $RepoRoot 'scripts'
$Installer = Join-Path $Scripts 'install-core.ps1'
$ResolverSrc = Join-Path $Scripts 'Get-MxAgileCapabilities.ps1'
$MxcliResolverSrc = Join-Path $Scripts 'Resolve-MxAgileMxcli.ps1'
$StudioProDetectorSrc = Join-Path $Scripts 'check-studio-pro-status.ps1'
$ProjectStatusSrc = Join-Path $Scripts 'build_project_status.py'
$ProjectBoardServerSrc = Join-Path $Scripts 'serve_project_board.py'
$CapabilityPolicySrc = Join-Path $RepoRoot '.mxagile/policies/capability-discovery.md'

$PassCount = 0; $FailCount = 0; $FailDetails = @()
function Assert-True {
    param([string]$TestName, [bool]$Condition, [string]$Message = '')
    if ($Condition) { Write-Host "  PASS: $TestName" -ForegroundColor Green; $script:PassCount++ }
    else { Write-Host "  FAIL: $TestName -- $Message" -ForegroundColor Red; $script:FailCount++; $script:FailDetails += "  FAIL: $TestName -- $Message" }
}

$Temps = @()
function New-TempDir { $p = Join-Path $env:TEMP "mxagile-disc-$(New-Guid)"; New-Item -ItemType Directory -Path $p | Out-Null; $script:Temps += $p; return $p }

Write-Host ""
Write-Host "=== Capability Discovery Routing & Distribution Tests ===" -ForegroundColor Cyan

try {
# --- Static: routing rule ---------------------------------------------------
Write-Host "--- Routing rule ---" -ForegroundColor Yellow
$inject = Get-Content (Join-Path $Scripts 'apply-project-agent-instructions.ps1') -Raw
$m = [regex]::Match($inject, '(?s)\$MxAgileStartupBlock = @''\r?\n(.*?)\r?\n''@')
Assert-True 'startup block extractable' $m.Success 'block not found'
$block = $m.Groups[1].Value
$rule = [regex]::Match($block, '(?s)7\. \*\*Optional capabilities.*?(?=\r?\n\r?\nDetailed policy)').Value
Assert-True 'rule 7 present and routes to capability-discovery policy' ($rule -match 'capability-discovery\.md') 'rule/policy ref missing'
Assert-True 'rule is lazy: on demand, never at startup' (($rule -match 'on demand') -and ($rule -match 'never at startup')) $rule
Assert-True 'rule states installed != usable, no invented health, non-blocking' (($rule -match 'Installed does not mean usable') -and ($rule -match 'never assume health') -and ($rule -match 'never blocks')) $rule
Assert-True 'rule queries only the relevant capability' ($rule -match 'only that capability') $rule
Assert-True 'rule is short (<= 6 lines)' (($rule -split "`n").Count -le 6) "lines=$(($rule -split "`n").Count)"
Assert-True 'always-on block does not explain Context Mode' ($block -notmatch '(?i)context[- _]mode|ctx_') 'Context Mode leaked into always-on text'
Assert-True 'no "run at every startup" instruction' ($block -notmatch '(?i)every (start|session)|at startup.*Get-MxAgile|run capability discovery') 'startup probe instruction'

# nothing in installer/startup scripts invokes the resolver
$invokers = Get-ChildItem $Scripts -Filter *.ps1 -File | Where-Object { $_.Name -ne 'Get-MxAgileCapabilities.ps1' } |
    Where-Object { (Get-Content $_.FullName -Raw) -match '(?m)^\s*(&|\.)\s*.*Get-MxAgileCapabilities' }
Assert-True 'no script invokes the resolver automatically' (@($invokers).Count -eq 0) (($invokers | ForEach-Object Name) -join ', ')

$policy = Get-Content (Join-Path $RepoRoot '.mxagile/policies/capability-discovery.md') -Raw
Assert-True 'policy names installed resolver path and lazy -Capability use' (($policy -match '\.mxagile/tools/Get-MxAgileCapabilities\.ps1') -and ($policy -match '-Capability <id>') -and ($policy -match 'Never run it at startup')) 'policy incomplete'
Assert-True 'policy maps large-raw-data tasks to context_mode_integration' ($policy -match 'Large raw data.*context_mode_integration') 'task mapping missing'
Assert-True 'policy gives compact answer template using integration.guidance' (($policy -match 'integration\.guidance') -and ($policy -match 'normal MxAgile fallback')) 'template missing'
$resolverOrder = $policy.IndexOf('Get-MxAgileCapabilities.ps1')
$concordOrder = $policy.IndexOf('concord_discover')
Assert-True 'G1. MxAgile resolver precedes Concord discovery guidance' (($resolverOrder -ge 0) -and ($concordOrder -gt $resolverOrder)) 'resolver ordering missing'
Assert-True 'G1/G2. Concord discovery is not treated as Context Mode capability evidence' (($policy -match 'must not replace or precede') -and ($policy -match 'Concord discovery')) 'Concord substitution warning missing'
Assert-True 'policy separates live tool inventory, health and task-required operations' (($policy -match '-ContextModeToolsObserved') -and ($policy -match '-ContextModeRequiredTools') -and ($policy -match 'Never reuse health from an earlier session')) 'runtime contract incomplete'
Assert-True 'policy requires host-attested harness and fails closed on mismatch' (($policy -match 'MXAGILE_HARNESS') -and ($policy -match 'harness_ambiguous') -and ($policy -match 'never pass a guessed')) 'harness attestation rules missing'
Assert-True 'policy separates Concord source and terminal origin from harness' (($policy -match 'Concord under Claude remains') -and ($policy -match 'Windows Terminal') -and ($policy -match 'Studio-Pro-integrated terminal')) 'Concord/terminal semantics missing'
Assert-True 'policy defines task-specific hooks and self-service action classes' (($policy -match 'ContextModeHooksRequired') -and ($policy -match 'REQUIRES_USER_APPROVAL') -and ($policy -match 'REQUIRES_RESTART') -and ($policy -match 'UNSUPPORTED')) 'action routing incomplete'
Assert-True 'large-source fallback explicitly forbids direct full read' (($policy -match 'NOT_VERIFIABLE_FOR_CM_TEST') -and ($policy -match 'leave the large source unread')) 'large-source fallback missing'

# --- E2E: fresh install -------------------------------------------------------------
Write-Host "--- Fresh install ---" -ForegroundColor Yellow
$proj = New-TempDir
New-Item -ItemType File -Path (Join-Path $proj 'project.mpr') | Out-Null
$null = & pwsh -NoProfile -File $Installer -ProjectRoot $proj 2>&1
Assert-True 'fresh install exit 0' ($LASTEXITCODE -eq 0) "exit $LASTEXITCODE"
$freshGitignore = Get-Content (Join-Path $proj '.gitignore') -Raw
Assert-True 'fresh install ignores project-local Context Mode runtime roots' (($freshGitignore -match '(?m)^\.context-mode/\r?$') -and ($freshGitignore -match '(?m)^\.github/context-mode/\r?$')) 'runtime roots missing from .gitignore'
$tool = Join-Path $proj '.mxagile/tools/Get-MxAgileCapabilities.ps1'
$mxcliResolver = Join-Path $proj '.mxagile/tools/Resolve-MxAgileMxcli.ps1'
$detector = Join-Path $proj '.mxagile/tools/check-studio-pro-status.ps1'
$statusBuilder = Join-Path $proj '.mxagile/tools/build_project_status.py'
$boardServer = Join-Path $proj '.mxagile/tools/serve_project_board.py'
$statusSchema = Join-Path $proj '.mxagile/schemas/project-status.schema.json'
$boardIndex = Join-Path $proj '.mxagile/board/index.html'
$boardStyles = Join-Path $proj '.mxagile/board/styles.css'
$boardScript = Join-Path $proj '.mxagile/board/board.js'
$contextAdapter = Join-Path $proj '.mxagile/adapters/copilot/context-mode-cli.yaml'
$contextIntegration = Join-Path $proj '.mxagile/integrations/context-mode.yaml'
$capabilityPolicy = Join-Path $proj '.mxagile/policies/capability-discovery.md'
Assert-True 'capability discovery policy included in fresh install' ((Test-Path $capabilityPolicy) -and ((Get-FileHash $capabilityPolicy).Hash -eq (Get-FileHash $CapabilityPolicySrc).Hash)) 'policy missing or hash differs'
Assert-True 'resolver distributed to .mxagile/tools' (Test-Path $tool) 'tool missing'
Assert-True 'distributed resolver equals source' ((Test-Path $tool) -and ((Get-FileHash $tool).Hash -eq (Get-FileHash $ResolverSrc).Hash)) 'hash differs'
Assert-True 'status builder distributed to .mxagile/tools' ((Test-Path $statusBuilder) -and ((Get-FileHash $statusBuilder).Hash -eq (Get-FileHash $ProjectStatusSrc).Hash)) 'builder missing or hash differs'
Assert-True 'status schema distributed with canonical Core payload' ((Test-Path $statusSchema) -and ((Get-FileHash $statusSchema).Hash -eq (Get-FileHash (Join-Path $RepoRoot '.mxagile/schemas/project-status.schema.json')).Hash)) 'schema missing or hash differs'
Assert-True 'loopback board server distributed to .mxagile/tools' ((Test-Path $boardServer) -and ((Get-FileHash $boardServer).Hash -eq (Get-FileHash $ProjectBoardServerSrc).Hash)) 'board server missing or hash differs'
Assert-True 'read-only board UI distributed with canonical Core payload' ((Test-Path $boardIndex) -and ((Get-FileHash $boardIndex).Hash -eq (Get-FileHash (Join-Path $RepoRoot '.mxagile/board/index.html')).Hash)) 'board UI missing or hash differs'
Assert-True 'board CSS distributed with canonical Core payload' ((Test-Path $boardStyles) -and ((Get-FileHash $boardStyles).Hash -eq (Get-FileHash (Join-Path $RepoRoot '.mxagile/board/styles.css')).Hash)) 'board CSS missing or hash differs'
Assert-True 'board JavaScript distributed with canonical Core payload' ((Test-Path $boardScript) -and ((Get-FileHash $boardScript).Hash -eq (Get-FileHash (Join-Path $RepoRoot '.mxagile/board/board.js')).Hash)) 'board JavaScript missing or hash differs'
Assert-True 'mxcli runtime resolver distributed to .mxagile/tools' (Test-Path $mxcliResolver) 'mxcli resolver missing'
Assert-True 'distributed mxcli runtime resolver equals source' ((Test-Path $mxcliResolver) -and ((Get-FileHash $mxcliResolver).Hash -eq (Get-FileHash $MxcliResolverSrc).Hash)) 'mxcli resolver hash differs'
Assert-True 'Context Mode Copilot adapter included in fresh install' (Test-Path $contextAdapter) 'adapter missing'
Assert-True 'installed adapter equals canonical adapter' ((Test-Path $contextAdapter) -and ((Get-FileHash $contextAdapter).Hash -eq (Get-FileHash (Join-Path $RepoRoot '.mxagile/adapters/copilot/context-mode-cli.yaml')).Hash)) 'adapter hash differs'
Assert-True 'Context Mode integration contract included in fresh install' (Test-Path $contextIntegration) 'integration contract missing'
Assert-True 'installed integration contract equals canonical source' ((Test-Path $contextIntegration) -and ((Get-FileHash $contextIntegration).Hash -eq (Get-FileHash (Join-Path $RepoRoot '.mxagile/integrations/context-mode.yaml')).Hash)) 'integration contract hash differs'
Assert-True 'Studio Pro detector distributed to .mxagile/tools' (Test-Path $detector) 'detector missing'
Assert-True 'distributed detector equals canonical source' ((Test-Path $detector) -and ((Get-FileHash $detector).Hash -eq (Get-FileHash $StudioProDetectorSrc).Hash)) 'hash differs'
$detectorResult = (& $detector -Json -TimeoutSeconds 30 | ConvertFrom-Json)
Assert-True 'installed detector resolves project root by default' ($detectorResult.projectPath -eq (Join-Path $proj 'project.mpr')) "projectPath=$($detectorResult.projectPath)"
Assert-True 'no scripts/ directory created in project' (-not (Test-Path (Join-Path $proj 'scripts'))) 'project-owned scripts/ touched'
Assert-True 'startup did not run resolver (no discovery state)' (-not (Test-Path (Join-Path $proj '.concord/capability-discovery.yaml'))) 'discovery state written'
foreach ($f in 'AGENTS.md', 'CLAUDE.md', '.github/copilot-instructions.md') {
    $p = Join-Path $proj $f
    if (Test-Path $p) {
        $t = Get-Content $p -Raw
        Assert-True "$f carries rule 7 without Context Mode text" (($t -match 'Optional capabilities, on demand only') -and ($t -notmatch '(?i)context-mode')) 'rule missing or leaked'
    }
}
$prov = Get-Content (Join-Path $proj '.mxagile/state/core-provenance.json') -Raw | ConvertFrom-Json
Assert-True 'provenance lists project-distributed resolver' (@($prov.distribution.project_distributed) -contains '.mxagile/tools/Get-MxAgileCapabilities.ps1') 'provenance missing resolver entry'
Assert-True 'provenance lists project-distributed mxcli runtime resolver' (@($prov.distribution.project_distributed) -contains '.mxagile/tools/Resolve-MxAgileMxcli.ps1') 'provenance missing mxcli resolver entry'
Assert-True 'provenance lists project-distributed detector' (@($prov.distribution.project_distributed) -contains '.mxagile/tools/check-studio-pro-status.ps1') 'provenance missing detector entry'
Assert-True 'provenance lists project-distributed status builder' (@($prov.distribution.project_distributed) -contains '.mxagile/tools/build_project_status.py') 'provenance missing status builder entry'
Assert-True 'provenance lists project-distributed board server' (@($prov.distribution.project_distributed) -contains '.mxagile/tools/serve_project_board.py') 'provenance missing board server entry'

# installed agent reaches resolver (default project root = installed project) and gets guidance
$bin = New-TempDir
$marker = Join-Path $bin 'executed.marker'
Set-Content (Join-Path $bin 'context-mode.cmd') "@echo executed> `"$marker`"`r`n@echo 1.0.169" -Encoding ASCII
$savedPath = $env:PATH
$savedEnv = @{}
foreach ($n in 'MXAGILE_HARNESS','CLAUDECODE','OPENCODE_SESSION_ID','OPENCODE_BASE_URL') { $savedEnv[$n] = [Environment]::GetEnvironmentVariable($n); [Environment]::SetEnvironmentVariable($n, $null) }
try {
    $env:PATH = $bin
    [Environment]::SetEnvironmentVariable('MXAGILE_HARNESS', 'opencode')
    $homeDir = New-TempDir
    $json = & $tool -Capability context_mode_integration -Format json -Harness opencode -HomeDir $homeDir | ConvertFrom-Json
    $i = $json.capabilities[0].integration
    Assert-True 'installed resolver resolves the installed project root' ($json.project_root -eq $proj) "root=$($json.project_root)"
    Assert-True 'targeted discovery returns harness-specific guidance' (($i.status -eq 'installed_not_configured') -and (($i.guidance -join ' ') -match 'opencode\.json')) "status=$($i.status)"
    Assert-True 'discovery never executes context-mode' (-not (Test-Path $marker)) 'context-mode executed'
    Assert-True 'unusable Context Mode does not block (fallback intact)' (($i.usable -eq $false) -and ($i.fallback.blocks_mxagile -eq $false) -and ($LASTEXITCODE -eq 0)) 'blocked'
    $loaded = & $tool -Capability context_mode_integration -Format json -Harness opencode -HomeDir $homeDir -ContextModeToolsObserved -ContextModeTools ctx_doctor -ContextModeRequiredTools ctx_doctor | ConvertFrom-Json
    $loadedIntegration = $loaded.capabilities[0].integration
    Assert-True 'installed resolver accepts current-session runtime evidence' (($loadedIntegration.loaded -eq $true) -and ($loadedIntegration.loaded_tools -contains 'ctx_doctor') -and ($loadedIntegration.status -eq 'loaded_unconfigured')) "status=$($loadedIntegration.status)"
    $json2 = & $tool -Capability context_lifecycle -Format json | ConvertFrom-Json
    Assert-True 'small-task capability query does not touch Context Mode' ((-not (Test-Path $marker)) -and (@($json2.capabilities).Count -eq 1)) 'probe happened'
} finally {
    $env:PATH = $savedPath
    foreach ($n in $savedEnv.Keys) { [Environment]::SetEnvironmentVariable($n, $savedEnv[$n]) }
}

# --- E2E: existing-project update + idempotence ---------------------------------------------
Write-Host "--- Existing project update ---" -ForegroundColor Yellow
Set-Content $tool '# tampered' -Encoding UTF8
Set-Content $detector '# tampered' -Encoding UTF8
Set-Content $statusBuilder '# tampered' -Encoding UTF8
Set-Content $boardServer '# tampered' -Encoding UTF8
Set-Content $contextAdapter '# tampered' -Encoding UTF8
Set-Content $contextIntegration '# tampered' -Encoding UTF8
Set-Content $capabilityPolicy '# tampered' -Encoding UTF8
Set-Content (Join-Path $proj '.mxagile/tools/stale.ps1') '# stale' -Encoding UTF8
New-Item -ItemType Directory -Path (Join-Path $proj 'scripts') | Out-Null
Set-Content (Join-Path $proj 'scripts/mine.ps1') '# project-owned' -Encoding UTF8
$projectGitignore = Join-Path $proj '.gitignore'
Set-Content $projectGitignore "# project-owned`ncustom-runtime/`n" -Encoding UTF8
$null = & pwsh -NoProfile -Command "& '$Installer' -ProjectRoot '$proj' -IsUpdate `$true" 2>&1
Assert-True 'update exit 0' ($LASTEXITCODE -eq 0) "exit $LASTEXITCODE"
Assert-True 'update restores capability discovery policy' ((Get-FileHash $capabilityPolicy).Hash -eq (Get-FileHash $CapabilityPolicySrc).Hash) 'policy not restored'
$updatedGitignore = Get-Content $projectGitignore -Raw
Assert-True 'update preserves project .gitignore and adds runtime ignores' (($updatedGitignore -match 'project-owned') -and ($updatedGitignore -match 'custom-runtime/') -and ($updatedGitignore -match '(?m)^\.context-mode/\r?$') -and ($updatedGitignore -match '(?m)^\.github/context-mode/\r?$')) "project .gitignore was overwritten or runtime ignores missing: $updatedGitignore"
$srcHash = (Get-FileHash $ResolverSrc).Hash
Assert-True 'update restores resolver to current distribution version' ((Get-FileHash $tool).Hash -eq $srcHash) 'not restored'
Assert-True 'update restores mxcli runtime resolver to current distribution version' ((Get-FileHash $mxcliResolver).Hash -eq (Get-FileHash $MxcliResolverSrc).Hash) 'mxcli resolver not restored'
Assert-True 'update restores detector to current distribution version' ((Get-FileHash $detector).Hash -eq (Get-FileHash $StudioProDetectorSrc).Hash) 'not restored'
Assert-True 'update restores status builder to current distribution version' ((Get-FileHash $statusBuilder).Hash -eq (Get-FileHash $ProjectStatusSrc).Hash) 'not restored'
Assert-True 'update restores board server to current distribution version' ((Get-FileHash $boardServer).Hash -eq (Get-FileHash $ProjectBoardServerSrc).Hash) 'not restored'
$adapterHash = (Get-FileHash (Join-Path $RepoRoot '.mxagile/adapters/copilot/context-mode-cli.yaml')).Hash
$integrationHash = (Get-FileHash (Join-Path $RepoRoot '.mxagile/integrations/context-mode.yaml')).Hash
Assert-True 'update restores Context Mode adapter' ((Get-FileHash $contextAdapter).Hash -eq $adapterHash) 'adapter not restored'
Assert-True 'update restores Context Mode integration contract' ((Get-FileHash $contextIntegration).Hash -eq $integrationHash) 'contract not restored'
Assert-True 'update retires stale files in .mxagile/tools' (-not (Test-Path (Join-Path $proj '.mxagile/tools/stale.ps1'))) 'stale file kept'
Assert-True 'update preserves project-owned scripts/' ((Get-Content (Join-Path $proj 'scripts/mine.ps1') -Raw) -match 'project-owned') 'project file lost'
$null = & pwsh -NoProfile -Command "& '$Installer' -ProjectRoot '$proj' -IsUpdate `$true" 2>&1
Assert-True 'repeated update exit 0 and tool payload remains idempotent' (($LASTEXITCODE -eq 0) -and ((Get-FileHash $tool).Hash -eq $srcHash) -and ((Get-FileHash $mxcliResolver).Hash -eq (Get-FileHash $MxcliResolverSrc).Hash) -and ((Get-FileHash $detector).Hash -eq (Get-FileHash $StudioProDetectorSrc).Hash) -and ((Get-FileHash $contextAdapter).Hash -eq $adapterHash) -and ((Get-FileHash $contextIntegration).Hash -eq $integrationHash) -and ((Get-FileHash $capabilityPolicy).Hash -eq (Get-FileHash $CapabilityPolicySrc).Hash)) 'not idempotent'
$repeatedGitignore = Get-Content $projectGitignore -Raw
Assert-True 'repeated update does not duplicate Context Mode ignore entries' ((([regex]::Matches($repeatedGitignore, '(?m)^\.context-mode/\r?$')).Count -eq 1) -and (([regex]::Matches($repeatedGitignore, '(?m)^\.github/context-mode/\r?$')).Count -eq 1)) 'ignore entries duplicated'
$agents = Get-Content (Join-Path $proj 'AGENTS.md') -Raw
Assert-True 'repeated update does not duplicate rule 7' (([regex]::Matches($agents, 'Optional capabilities, on demand only')).Count -eq 1) 'rule duplicated'
} finally {
    foreach ($t in $Temps) { Remove-Item -Recurse -Force $t -ErrorAction SilentlyContinue }
}

Write-Host ""
Write-Host "=== Results ===" -ForegroundColor Cyan
Write-Host "  Passed: $PassCount" -ForegroundColor Green
Write-Host "  Failed: $FailCount" -ForegroundColor $(if ($FailCount -gt 0) { 'Red' } else { 'Green' })
if ($FailCount -gt 0) { $FailDetails | ForEach-Object { Write-Host $_ -ForegroundColor Red }; exit 1 }
exit 0
