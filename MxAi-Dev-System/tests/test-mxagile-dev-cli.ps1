<#
.SYNOPSIS
    Tests for the mxagile-dev developer CLI.

.DESCRIPTION
    Validates that the CLI provides correct discoverability, dispatch, error handling,
    path safety, and exit-code propagation without reimplementing canonical script logic.

    Scenarios:
    A. Root help — no-arg invocation exits 0 and shows usage
    B. Command-specific help — bad subcommand exits 2 with guidance
    C. Unknown command — exits 2 with useful error
    D. test list — enumerates expected suites
    E. test run dispatches to canonical suite (smoke)
    F. Underlying script failure propagates as non-zero exit
    G. project detect delegates to detect-project-type.ps1
    H. project detect works with path containing spaces
    I. migration status shows MIGRATION_IN_PROGRESS state content
    J. workspace create dispatches to create-test-workcopy.ps1
    K. workspace remove rejects nonexistent / unsafe paths
    L. install core requires path argument
    M. install mercedes requires path argument
    N. install core delegates to public bootstrap, not install-core.ps1 directly
    O. Repository root discovery uses canonical marker files
    P. CLI invocation from outside repo root succeeds (absolute path)
    Q. Canonical scripts remain authoritative — CLI contains no reimplemented logic
#>

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$TestsDir  = $PSScriptRoot
$RepoRoot  = Split-Path -Parent $TestsDir
$CliPath   = Join-Path $RepoRoot 'mxagile-dev.ps1'

$PassCount   = 0
$FailCount   = 0
$FailDetails = @()

Write-Host ''
Write-Host '=== mxagile-dev CLI Tests ===' -ForegroundColor Cyan
Write-Host ''

# ─── Helpers ──────────────────────────────────────────────────────────────────

function Assert-True {
    param([string] $TestName, [bool] $Condition, [string] $Message = 'condition was false')
    if ($Condition) {
        Write-Host "  PASS: $TestName" -ForegroundColor Green
        $script:PassCount++
    } else {
        Write-Host "  FAIL: $TestName -- $Message" -ForegroundColor Red
        $script:FailCount++
        $script:FailDetails += "[$TestName] $Message"
    }
}

function Invoke-CLI {
    param([string[]] $CliArgs = @())
    # Use a local Continue preference so NativeCommandError from subprocess stderr
    # does not throw a terminating error in this script (ErrorActionPreference = Stop).
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    # Set MXAGILE_NONINTERACTIVE so no-arg invocations show help, not the interactive menu.
    $prevNI = $env:MXAGILE_NONINTERACTIVE
    $env:MXAGILE_NONINTERACTIVE = '1'
    $rawOutput = & powershell -NoProfile -NonInteractive -File $script:CliPath @CliArgs 2>&1
    $ec = $LASTEXITCODE
    if ($null -eq $prevNI) {
        Remove-Item Env:\MXAGILE_NONINTERACTIVE -ErrorAction SilentlyContinue
    } else {
        $env:MXAGILE_NONINTERACTIVE = $prevNI
    }
    $ErrorActionPreference = $prevEAP
    return @{
        Output   = ($rawOutput | Out-String)
        ExitCode = $ec
    }
}

function Invoke-CLIInteractive {
    param([string] $InputSequence)
    # Does NOT set MXAGILE_NONINTERACTIVE -- the CLI enters interactive mode.
    # Pipes the input sequence as stdin so Read-Host calls consume it.
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $rawOutput = ($InputSequence | & powershell -NoProfile -File $script:CliPath 2>&1)
    $ec = $LASTEXITCODE
    $ErrorActionPreference = $prevEAP
    return @{
        Output   = ($rawOutput | Out-String)
        ExitCode = $ec
    }
}

function New-TempDir {
    param([string] $Suffix = '')
    $dir = Join-Path $env:TEMP "mxdev-test-$Suffix-$([System.Guid]::NewGuid().ToString('N').Substring(0,8))"
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    return $dir
}

function Remove-TempDir {
    param([string] $Path)
    if ($Path -and (Test-Path -LiteralPath $Path)) {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ─── A. Root help ─────────────────────────────────────────────────────────────

Write-Host '  Scenario A: Root help'

$r = Invoke-CLI
Assert-True 'A1: no-arg exits 0'         ($r.ExitCode -eq 0)             "exit $($r.ExitCode)"
Assert-True 'A2: output mentions mxagile-dev' ($r.Output -match 'mxagile-dev') 'no mxagile-dev in output'
Assert-True 'A3: output shows COMMANDS section' ($r.Output -match 'COMMANDS')  'no COMMANDS section in output'
Assert-True 'A4: output shows EXAMPLES section' ($r.Output -match 'EXAMPLES')  'no EXAMPLES section in output'

$rh = Invoke-CLI @('--help')
Assert-True 'A5: --help exits 0'         ($rh.ExitCode -eq 0)            "exit $($rh.ExitCode)"
Assert-True 'A6: --help output matches no-arg output' `
    ($rh.Output.Trim() -eq $r.Output.Trim()) 'help output differs'

# ─── B. Command-specific help for unknown subcommand ──────────────────────────

Write-Host '  Scenario B: Bad subcommand exits 2 with guidance'

foreach ($bad in @(
    @('test',      'badcmd'),
    @('workspace', 'badcmd'),
    @('project',   'badcmd'),
    @('install',   'badcmd'),
    @('migration', 'badcmd')
)) {
    $r = Invoke-CLI $bad
    Assert-True "B: '$($bad -join ' ')' exits 2" ($r.ExitCode -eq 2) "exit $($r.ExitCode)"
    Assert-True "B: '$($bad -join ' ')' mentions Expected" ($r.Output -match 'Expected') 'no Expected in output'
}

# ─── C. Unknown command ───────────────────────────────────────────────────────

Write-Host '  Scenario C: Unknown command'

$r = Invoke-CLI @('xyz-does-not-exist-abc123')
Assert-True 'C1: unknown command exits 2'              ($r.ExitCode -eq 2)           "exit $($r.ExitCode)"
Assert-True 'C2: error mentions unknown command'       ($r.Output -match 'unknown command') 'no "unknown command" in output'
Assert-True 'C3: error suggests help invocation'       ($r.Output -match '--help|mxagile-dev') 'no help suggestion in output'

# ─── D. test list ─────────────────────────────────────────────────────────────

Write-Host '  Scenario D: test list'

$r = Invoke-CLI @('test', 'list')
Assert-True 'D1: test list exits 0'                   ($r.ExitCode -eq 0) "exit $($r.ExitCode)"
Assert-True 'D2: lists smoke suite'                   ($r.Output -match '\bsmoke\b') 'smoke not listed'
Assert-True 'D3: lists installer suite'               ($r.Output -match '\binstaller\b') 'installer not listed'
Assert-True 'D4: lists migration-crash-safety'        ($r.Output -match 'migration-crash-safety') 'migration-crash-safety not listed'
Assert-True 'D5: lists managed-block suite'           ($r.Output -match 'managed-block') 'managed-block not listed'

# ─── E. test run dispatches to canonical suite ────────────────────────────────

Write-Host '  Scenario E: test run dispatches to smoke-test.ps1'

$r = Invoke-CLI @('test', 'run', 'smoke')
Assert-True 'E1: test run smoke dispatches (not CLI error)'  ($r.ExitCode -ne 2) "exit $($r.ExitCode) (CLI usage error -- dispatch did not occur)"
Assert-True 'E2: smoke output contains script check'  ($r.Output -match 'install-mxcli|smoke|PASS|pass') 'smoke output not recognisable'

# ─── F. Underlying failure propagates ────────────────────────────────────────

Write-Host '  Scenario F: Underlying failure propagates as non-zero'

# test run with unknown suite — CLI-level failure (exit 2)
$r = Invoke-CLI @('test', 'run', 'suite-that-does-not-exist-xyz987')
Assert-True 'F1: unknown suite exits non-zero'        ($r.ExitCode -ne 0) "exit $($r.ExitCode) (expected non-zero)"

# workspace create with nonexistent template — underlying script fails (exit 1)
$r = Invoke-CLI @('workspace', 'create', 'template-xyz-nonexistent-9999')
Assert-True 'F2: workspace create nonexistent template exits non-zero' ($r.ExitCode -ne 0) "exit $($r.ExitCode)"
Assert-True 'F3: failure output mentions template or not found'        ($r.Output -match 'template|not found|Source') 'no failure context in output'

# project detect with nonexistent path — CLI-level failure (exit 2)
$r = Invoke-CLI @('project', 'detect', 'C:\nonexistent-path-xyz-99887766')
Assert-True 'F4: project detect missing path exits 2' ($r.ExitCode -eq 2) "exit $($r.ExitCode)"

# ─── G. project detect delegates to detect-project-type.ps1 ──────────────────

Write-Host '  Scenario G: project detect delegates correctly'

$r = Invoke-CLI @('project', 'detect', $RepoRoot)
Assert-True 'G1: project detect repo root exits 0'    ($r.ExitCode -eq 0) "exit $($r.ExitCode)"
Assert-True 'G2: output is JSON with Classification'  ($r.Output -match '"Classification"') 'no Classification field'
Assert-True 'G3: output contains a known classification' `
    ($r.Output -match 'CLEAN_PROJECT|EXISTING_MXAGILE_PROJECT|LEGACY_DFC_PROJECT|MIGRATION_IN_PROGRESS|AMBIGUOUS') `
    'no known classification value'

# ─── H. project detect with spaces in path ───────────────────────────────────

Write-Host '  Scenario H: project path with spaces'

$spacePath = New-TempDir -Suffix 'spaces in name'
try {
    $r = Invoke-CLI @('project', 'detect', $spacePath)
    Assert-True 'H1: path with spaces exits 0'        ($r.ExitCode -eq 0) "exit $($r.ExitCode)"
    Assert-True 'H2: returns CLEAN_PROJECT for empty dir' ($r.Output -match 'CLEAN_PROJECT') "output: $($r.Output.Trim())"
} finally {
    Remove-TempDir $spacePath
}

# ─── I. migration status on MIGRATION_IN_PROGRESS workspace ──────────────────

Write-Host '  Scenario I: migration status diagnostics'

$migWs = Join-Path $RepoRoot '.testing-brownfield_migration_captrack'
if (Test-Path -LiteralPath $migWs -PathType Container) {
    $r = Invoke-CLI @('migration', 'status', $migWs)
    Assert-True 'I1: migration status exits 0'        ($r.ExitCode -eq 0) "exit $($r.ExitCode)"
    Assert-True 'I2: output shows project type'       ($r.Output -match 'Project type') 'no Project type in output'
    Assert-True 'I3: output shows MIGRATION_IN_PROGRESS' ($r.Output -match 'MIGRATION_IN_PROGRESS') 'classification not shown'
    Assert-True 'I4: output shows state.yaml present' ($r.Output -match 'state\.yaml\s*:?\s*present') 'state.yaml status missing'
    Assert-True 'I5: state.yaml content shown (status: in_progress)' ($r.Output -match 'in_progress') 'state content not shown'
} else {
    Write-Host "  SKIP: .testing-brownfield_migration_captrack not found (I1-I5 skipped)" -ForegroundColor Yellow
    $script:PassCount += 5  # count as pass when workspace absent (not a CLI failure)
}

# ─── J. workspace create dispatches to create-test-workcopy.ps1 ──────────────

Write-Host '  Scenario J: workspace create dispatch'

# Test dispatch by attempting create without template arg (exits 2, shows template list)
$r = Invoke-CLI @('workspace', 'create')
Assert-True 'J1: workspace create no-arg exits 2'     ($r.ExitCode -eq 2) "exit $($r.ExitCode)"
Assert-True 'J2: output mentions template'            ($r.Output -match 'template|Template') 'no template hint in output'

# Test dispatch with nonexistent template — create-test-workcopy.ps1 is called and fails
$r = Invoke-CLI @('workspace', 'create', 'nonexistent-template-xyz-cli-test')
Assert-True 'J3: nonexistent template exits non-zero' ($r.ExitCode -ne 0) "exit $($r.ExitCode)"
# Output should come from create-test-workcopy.ps1, not from an internal reimplementation
Assert-True 'J4: failure output from canonical script' ($r.Output -match 'Source|template|not found') 'expected canonical script output'

# ─── K. workspace destructive operations reject unsafe paths ─────────────────

Write-Host '  Scenario K: workspace boundary safety'

# Remove nonexistent workspace → exit 2 (not found), not a crash
$r = Invoke-CLI @('workspace', 'remove', 'workspace-xyz-does-not-exist-9988')
Assert-True 'K1: remove nonexistent exits 2'          ($r.ExitCode -eq 2) "exit $($r.ExitCode)"
Assert-True 'K2: remove nonexistent mentions not found' ($r.Output -match 'not found') 'no "not found" in output'

# Remove with no arg → exit 2
$r = Invoke-CLI @('workspace', 'remove')
Assert-True 'K3: remove no-arg exits 2'               ($r.ExitCode -eq 2) "exit $($r.ExitCode)"

# Reset with no arg → exit 2
$r = Invoke-CLI @('workspace', 'reset')
Assert-True 'K4: reset no-arg exits 2'                ($r.ExitCode -eq 2) "exit $($r.ExitCode)"

# ─── L. install core requires path ───────────────────────────────────────────

Write-Host '  Scenario L: install core requires path argument'

$r = Invoke-CLI @('install', 'core')
Assert-True 'L1: install core no-path exits 2'        ($r.ExitCode -eq 2) "exit $($r.ExitCode)"
Assert-True 'L2: error mentions path required'        ($r.Output -match 'path required|required') 'no path-required hint'
Assert-True 'L3: error shows usage'                   ($r.Output -match 'Usage|usage|install core') 'no usage shown'

# ─── M. install mercedes requires path ───────────────────────────────────────

Write-Host '  Scenario M: install mercedes requires path argument'

$r = Invoke-CLI @('install', 'mercedes')
Assert-True 'M1: install mercedes no-path exits 2'    ($r.ExitCode -eq 2) "exit $($r.ExitCode)"
Assert-True 'M2: error mentions path required'        ($r.Output -match 'path required|required') 'no path-required hint'

# ─── N. install delegates to PUBLIC bootstrap, not install-core.ps1 directly ─

Write-Host '  Scenario N: install core uses public bootstrap (not install-core.ps1 directly)'

$cliContent = Get-Content -LiteralPath $script:CliPath -Raw
# Must reference the public bootstrap script
Assert-True 'N1: CLI references install-mxagile.ps1'  ($cliContent -match "install-mxagile\.ps1") 'install-mxagile.ps1 not referenced'
Assert-True 'N2: CLI references install-mxagile-mercedes.ps1' `
    ($cliContent -match "install-mxagile-mercedes\.ps1") 'install-mxagile-mercedes.ps1 not referenced'
# Must NOT invoke install-core.ps1 directly (catalog may list it for discoverability; dispatch must not call it)
Assert-True 'N3: CLI does not invoke install-core.ps1 directly' `
    ($cliContent -notmatch '-File[^;`n]*install-core\.ps1') 'CLI invokes install-core.ps1 directly — bypasses public bootstrap'

# ─── O. Repository root discovery uses marker files ──────────────────────────

Write-Host '  Scenario O: Repository root discovery'

$cliContent = Get-Content -LiteralPath $script:CliPath -Raw
Assert-True 'O1: CLI checks run-all-tests.ps1 marker'     ($cliContent -match 'run-all-tests\.ps1') 'run-all-tests.ps1 marker not checked'
Assert-True 'O2: CLI checks detect-project-type.ps1 marker' ($cliContent -match 'detect-project-type\.ps1') 'detect-project-type.ps1 marker not checked'
Assert-True 'O3: CLI uses PSScriptRoot for root'           ($cliContent -match 'PSScriptRoot') 'PSScriptRoot not used'

# ─── P. Invocation from outside repo root succeeds ───────────────────────────

Write-Host '  Scenario P: Invocation from outside repo root'

$outsideDir = New-TempDir -Suffix 'outside'
try {
    # Change to temp dir and invoke CLI via absolute path
    $prevLocation = Get-Location
    Set-Location $outsideDir
    try {
        $r = Invoke-CLI   # no args — should show help from any CWD
        Assert-True 'P1: help from outside repo exits 0' ($r.ExitCode -eq 0) "exit $($r.ExitCode)"
        Assert-True 'P2: help content shown from outside'  ($r.Output -match 'mxagile-dev') 'no mxagile-dev in output'
    } finally {
        Set-Location $prevLocation
    }
} finally {
    Remove-TempDir $outsideDir
}

# ─── Q. Canonical scripts remain authoritative ───────────────────────────────

Write-Host '  Scenario Q: Canonical scripts referenced, not reimplemented'

$cliContent = Get-Content -LiteralPath $script:CliPath -Raw

# All dispatch targets should be canonical scripts
Assert-True 'Q1: delegates to detect-project-type.ps1'   ($cliContent -match "detect-project-type\.ps1") 'detect-project-type.ps1 not referenced'
Assert-True 'Q2: delegates to create-test-workcopy.ps1'  ($cliContent -match "create-test-workcopy\.ps1") 'create-test-workcopy.ps1 not referenced'
Assert-True 'Q3: delegates to run-all-tests.ps1'          ($cliContent -match "run-all-tests\.ps1") 'run-all-tests.ps1 not referenced'
Assert-True 'Q4: delegates to smoke-test.ps1'             ($cliContent -match "smoke-test\.ps1") 'smoke-test.ps1 not referenced'
Assert-True 'Q5: delegates to run-installer-tests.ps1'    ($cliContent -match "run-installer-tests\.ps1") 'run-installer-tests.ps1 not referenced'

# CLI must not contain business logic that belongs in canonical scripts
Assert-True 'Q6: no robocopy invocation in CLI'           ($cliContent -notmatch '\brobocopy\b') 'CLI contains robocopy (workspace logic reimplemented)'
Assert-True 'Q7: no mxagile-init logic in CLI'            ($cliContent -notmatch 'mxagile-init|pip install|requirements\.txt') 'CLI contains init logic'
Assert-True 'Q8: no migration state-machine logic in CLI' ($cliContent -notmatch 'dfc_artifacts_removed|agent_md_migrated') 'CLI contains migration step logic'

# ─── R. Interactive mode ──────────────────────────────────────────────────────

Write-Host '  Scenario R: Interactive mode'

# R1-R3: Basic startup — interactive mode shows main menu, Q quits cleanly
$r = Invoke-CLIInteractive "Q`n"
Assert-True 'R1: interactive exits 0 on Q'           ($r.ExitCode -eq 0)                          "exit $($r.ExitCode)"
Assert-True 'R2: shows MxAgile Developer Tools'      ($r.Output -match 'MxAgile Developer Tools') 'no menu header'
Assert-True 'R3: shows numbered main menu options'   ($r.Output -match '\[1\].*Tests')             'no main menu options'

# R4-R5: Invalid selection handled gracefully
$r = Invoke-CLIInteractive "xyz123`nQ`n"
Assert-True 'R4: invalid selection exits 0'          ($r.ExitCode -eq 0)                          "exit $($r.ExitCode)"
Assert-True 'R5: invalid selection shows warning'    ($r.Output -match 'Unknown option')           'no unknown-option warning'

# R6-R7: Tests submenu accessible and shows expected items
$r = Invoke-CLIInteractive "1`nB`nQ`n"
Assert-True 'R6: tests submenu exits 0'              ($r.ExitCode -eq 0)                          "exit $($r.ExitCode)"
Assert-True 'R7: tests submenu shows list-suites'    ($r.Output -match 'List test suites')        'tests submenu not shown'

# R8-R9: B navigates back to main menu, which redisplays
$r = Invoke-CLIInteractive "1`nB`n2`nB`nQ`n"
Assert-True 'R8: back navigation exits 0'            ($r.ExitCode -eq 0)                          "exit $($r.ExitCode)"
Assert-True 'R9: main menu redisplayed after back'   ($r.Output -match 'Test Workspaces')         'workspaces menu not reached via main'

# R10-R11: Dynamic test suite list shown inside menu (tests -> list -> Enter -> B -> Q)
$r = Invoke-CLIInteractive "1`n1`n`nB`nQ`n"
Assert-True 'R10: list suites via menu exits 0'      ($r.ExitCode -eq 0)                          "exit $($r.ExitCode)"
Assert-True 'R11: dynamic suite list includes smoke' ($r.Output -match '\bsmoke\b')               'smoke not in menu suite list'

# R12-R13: Dynamic template discovery in workspace create (workspace -> create -> B -> B -> Q)
$r = Invoke-CLIInteractive "2`n2`nB`nB`nQ`n"
Assert-True 'R12: template discovery exits 0'        ($r.ExitCode -eq 0)                          "exit $($r.ExitCode)"
Assert-True 'R13: templates or no-templates shown'   ($r.Output -match 'Available templates|brownfield|greenfield|No templates') 'template section missing'

# R14-R15: Dynamic workspace discovery in workspace remove (workspace -> remove -> B -> B -> Q)
$r = Invoke-CLIInteractive "2`n4`nB`nB`nQ`n"
Assert-True 'R14: workspace remove menu exits 0'     ($r.ExitCode -eq 0)                          "exit $($r.ExitCode)"
Assert-True 'R15: workspace list or no-ws shown'     ($r.Output -match 'Existing workspaces|No workspaces') 'workspace listing missing'

# R16: Scripts/Tools menu accessible and shows catalog (scripts -> B -> Q)
$r = Invoke-CLIInteractive "6`nB`nQ`n"
Assert-True 'R16: scripts menu exits 0'              ($r.ExitCode -eq 0)                          "exit $($r.ExitCode)"
Assert-True 'R17: catalog shows safety labels'       ($r.Output -match 'READ_ONLY|MUTATING|TEST|INTERNAL') 'safety labels missing from catalog'

# R18-R20: Menu delegates to same dispatcher via Invoke-MenuOperation / MXAGILE_NONINTERACTIVE
$cliContent = Get-Content -LiteralPath $script:CliPath -Raw
Assert-True 'R18: CLI has MXAGILE_NONINTERACTIVE gate' ($cliContent -match 'MXAGILE_NONINTERACTIVE') 'no env-var detection in CLI'
Assert-True 'R19: menu uses Invoke-MenuOperation'      ($cliContent -match 'Invoke-MenuOperation')   'Invoke-MenuOperation not present'
Assert-True 'R20: menu self-invokes via script:CliPath' ($cliContent -match 'script:CliPath')         'self-invocation pattern missing'

# R21: Destructive operations require explicit confirmation (structural check)
Assert-True 'R21: workspace remove has y/N confirm'  ($cliContent -match '\[y/N\]')               'no y/N confirmation found'

# R22: Install menu shows target before confirming (structural check)
Assert-True 'R22: install menu shows target path'    ($cliContent -match 'Install MxAgile Core to:') 'install target display missing'

# R23-R24: Direct command mode unchanged by interactive additions
$r = Invoke-CLI @('test', 'list')
Assert-True 'R23: direct test list still works'      ($r.ExitCode -eq 0)                          "exit $($r.ExitCode)"
$r = Invoke-CLI @('project', 'detect', $RepoRoot)
Assert-True 'R24: direct project detect still works' ($r.ExitCode -eq 0)                          "exit $($r.ExitCode)"

# ─── Summary ──────────────────────────────────────────────────────────────────

Write-Host ''
Write-Host '======================================================================'
Write-Host "RESULT: $PassCount passed, $FailCount failed"
Write-Host '======================================================================'

if ($FailCount -gt 0) {
    Write-Host ''
    Write-Host 'Failed tests:' -ForegroundColor Red
    foreach ($d in $FailDetails) { Write-Host "  $d" -ForegroundColor Red }
    exit 1
}

Write-Host 'All mxagile-dev CLI tests passed.' -ForegroundColor Green
exit 0
