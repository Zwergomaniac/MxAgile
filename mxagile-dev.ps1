#Requires -Version 5.1
<#
.SYNOPSIS
    MxAgile Developer CLI -- thin maintainer dispatch layer.
.DESCRIPTION
    mxagile-dev wraps canonical MxAgile development scripts so maintainers can run common
    operations without browsing scripts/ manually.

    This script is a dispatch layer only. It does NOT reimplement script logic.
    All work is delegated to canonical scripts. If a canonical script changes, this
    CLI continues to use it -- no behaviour is duplicated here.

.EXAMPLE
    mxagile-dev
    mxagile-dev test all
    mxagile-dev test run migration-crash-safety
    mxagile-dev workspace list
    mxagile-dev workspace create brownfield_migration_captrack
    mxagile-dev project detect .testing-brownfield_migration_captrack
    mxagile-dev project status .testing-brownfield_migration_captrack
    mxagile-dev migration status .testing-brownfield_migration_captrack
    mxagile-dev install core /path/to/mendix-project
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)] [string] $Command    = '',
    [Parameter(Position = 1)] [string] $SubCommand = '',
    [Parameter(Position = 2)] [string] $Arg1       = '',
    [Alias('h')]
    [switch] $Help,
    [switch] $Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---- Repository root discovery -----------------------------------------------
#
# $PSScriptRoot is the script's own directory regardless of invocation CWD.
# Marker validation confirms we are in the MxAgile dev repo, not a test workspace.

$script:RepoRoot = $PSScriptRoot
$script:CliPath  = $PSCommandPath

foreach ($marker in @('tests\run-all-tests.ps1', 'scripts\detect-project-type.ps1')) {
    if (-not (Test-Path -LiteralPath (Join-Path $script:RepoRoot $marker) -PathType Leaf)) {
        Write-Host "mxagile-dev: Cannot confirm MxAgile dev repository root." -ForegroundColor Red
        Write-Host "  Expected marker: $marker" -ForegroundColor Red
        Write-Host "  Script location: $script:RepoRoot" -ForegroundColor Red
        exit 2
    }
}

# ---- Script catalog ----------------------------------------------------------
#
# Centralized metadata for maintainer-relevant scripts.
# Safety classifications: READ_ONLY | TEST | MUTATING | INTERNAL

$script:ScriptCatalog = @(
    @{ Display = 'Detect Project Type';            Path = 'scripts\detect-project-type.ps1';              Category = 'Project';    Purpose = 'Classify a directory: CLEAN / MXAGILE / LEGACY / MIGRATION';        Safety = 'READ_ONLY' },
    @{ Display = 'Create Test Workcopy';           Path = 'scripts\create-test-workcopy.ps1';             Category = 'Workspace';  Purpose = 'Create .testing-* workspace from a project template';               Safety = 'MUTATING'  },
    @{ Display = 'Run All Tests';                  Path = 'tests\run-all-tests.ps1';                      Category = 'Testing';    Purpose = 'Run all unit test suites in sequence';                               Safety = 'TEST'      },
    @{ Display = 'Run Installer Tests';            Path = 'tests\run-installer-tests.ps1';                Category = 'Testing';    Purpose = 'Run installer integration test suite';                               Safety = 'TEST'      },
    @{ Display = 'Install mxcli';                  Path = 'scripts\install-mxcli.ps1';                    Category = 'Tooling';    Purpose = 'Install or update the mxcli Mendix engineering tool';                Safety = 'MUTATING'  },
    @{ Display = 'Apply Agent Instructions';       Path = 'scripts\apply-project-agent-instructions.ps1'; Category = 'Framework';  Purpose = 'Inject AGENT.md managed block into platform projection files';       Safety = 'MUTATING'  },
    @{ Display = 'Generate Platform Skills';       Path = 'scripts\generate-mxagile-platform-skills.ps1'; Category = 'Framework';  Purpose = 'Generate platform projections from canonical .mxagile/ sources';     Safety = 'MUTATING'  },
    @{ Display = 'Setup Agent System';             Path = 'scripts\setup-agent-system.ps1';               Category = 'Framework';  Purpose = 'Set up agent tooling in a project directory';                        Safety = 'MUTATING'  },
    @{ Display = 'Public Bootstrap (Core)';        Path = 'install-mxagile.ps1';                          Category = 'Install';    Purpose = 'Entry point: install MxAgile Core into a project';                   Safety = 'MUTATING'  },
    @{ Display = 'Public Bootstrap (Mercedes)';    Path = 'install-mxagile-mercedes.ps1';                 Category = 'Install';    Purpose = 'Entry point: install MxAgile + Mercedes Company Layer';              Safety = 'MUTATING'  },
    @{ Display = 'Install Core (internal)';        Path = 'scripts\install-core.ps1';                     Category = 'Install';    Purpose = 'Internal installation engine -- use public bootstrap instead';       Safety = 'INTERNAL'  },
    @{ Display = 'Migration Bootstrap (internal)'; Path = 'scripts\install-migration-bootstrap.ps1';      Category = 'Migration';  Purpose = 'Internal migration bootstrap -- invoked by bootstrap automatically';  Safety = 'INTERNAL'  }
)

# ---- Exit-code contract -------------------------------------------------------
#   0   Success
#   1   Underlying canonical script failure (propagated)
#   2   CLI usage / argument error, or repo-root not found
#   3   Safety violation (destructive operation on non-workspace path)

# ---- Output helpers -----------------------------------------------------------

function Write-Section { param([string] $T) Write-Host "`n  $T" -ForegroundColor Cyan }
function Write-Row     { param([string] $T) Write-Host "    $T" }
function Write-Faint   { param([string] $T) Write-Host "    $T" -ForegroundColor DarkGray }

# ---- Root help ----------------------------------------------------------------

function Show-RootHelp {
    Write-Host ""
    Write-Host "  mxagile-dev  --  MxAgile Maintainer CLI"
    Write-Host "  Repo root: $($script:RepoRoot)"
    Write-Host ""
    Write-Host "  USAGE"
    Write-Host "    mxagile-dev <command> <subcommand> [arg]"
    Write-Host ""
    Write-Host "  COMMANDS"
    Write-Host ""
    Write-Host "    test"
    Write-Host "      list                  List available test suites"
    Write-Host "      run <suite>           Run a specific test suite by name"
    Write-Host "      all                   Run all unit test suites (run-all-tests.ps1)"
    Write-Host ""
    Write-Host "    workspace"
    Write-Host "      list                  List existing test workspaces"
    Write-Host "      create <template>     Create workspace from project template"
    Write-Host "      reset <workspace>     Recreate workspace from same-named template"
    Write-Host "      remove <workspace>    Remove a test workspace (safety-checked)"
    Write-Host ""
    Write-Host "    project"
    Write-Host "      detect [path]         Classify project type (detect-project-type.ps1)"
    Write-Host "      status [path]         Show aggregated project diagnostics"
    Write-Host ""
    Write-Host "    install"
    Write-Host "      core <path>           Install MxAgile core (install-mxagile.ps1)"
    Write-Host "      mercedes <path>       Install with MB layer (install-mxagile-mercedes.ps1)"
    Write-Host ""
    Write-Host "    migration"
    Write-Host "      status [path]         Show migration diagnostic status (read-only)"
    Write-Host ""
    Write-Host "  [path] defaults to current directory when omitted."
    Write-Host ""
    Write-Host "  EXAMPLES"
    Write-Host "    mxagile-dev test all"
    Write-Host "    mxagile-dev test run migration-crash-safety"
    Write-Host "    mxagile-dev workspace list"
    Write-Host "    mxagile-dev workspace create brownfield_migration_captrack"
    Write-Host "    mxagile-dev project detect .testing-brownfield_migration_captrack"
    Write-Host "    mxagile-dev project status .testing-brownfield_migration_captrack"
    Write-Host "    mxagile-dev migration status .testing-brownfield_migration_captrack"
    Write-Host "    mxagile-dev install core /path/to/mendix-project"
    Write-Host ""
}

# ---- Interactive menu helpers ------------------------------------------------

function Read-MenuChoice {
    param([string] $Prompt = '  Choice')
    $raw = $null
    try { $raw = Read-Host $Prompt } catch { $raw = '' }
    if ($null -eq $raw) { $raw = '' }
    $raw = $raw.Trim()
    if ($raw.ToUpper() -eq 'Q') {
        Write-Host '  Goodbye.' -ForegroundColor DarkGray
        exit 0
    }
    return $raw
}

function Wait-Continue {
    Write-Host ''
    try { $null = Read-Host '  Press Enter to continue' } catch { }
}

function Get-TestSuites {
    $testsDir = Join-Path $script:RepoRoot 'tests'
    $named = @(Get-ChildItem -LiteralPath $testsDir -Filter 'test-*.ps1' |
        Sort-Object Name |
        ForEach-Object { $_.BaseName -replace '^test-', '' })
    return (@('smoke', 'installer') + $named)
}

function Get-TestWorkspaces {
    @(Get-ChildItem -LiteralPath $script:RepoRoot -Filter '.testing-*' -Directory -ErrorAction SilentlyContinue)
}

function Select-FromList {
    param([string] $Prompt, [string[]] $Items)
    if ($Items.Count -eq 0) {
        Write-Host '  (none available)' -ForegroundColor Yellow
        return $null
    }
    Write-Host ''
    for ($i = 0; $i -lt $Items.Count; $i++) {
        Write-Host "  [$($i+1)] $($Items[$i])"
    }
    Write-Host ''
    Write-Host '  [B] Cancel'
    $choice = Read-MenuChoice -Prompt $Prompt
    if ($choice.ToUpper() -eq 'B') { return $null }
    $idx = 0
    if ([int]::TryParse($choice, [ref]$idx) -and $idx -ge 1 -and $idx -le $Items.Count) {
        return $Items[$idx - 1]
    }
    Write-Host "  Invalid selection '$choice'." -ForegroundColor Yellow
    return $null
}

function Select-ProjectPath {
    param([string] $Verb = 'target')
    Write-Host ''
    Write-Host "  Select $Verb" -ForegroundColor DarkCyan
    Write-Host "  [C] Current directory  ($((Get-Location).Path))"
    Write-Host '  [W] Pick from test workspaces'
    Write-Host '  [E] Enter path manually'
    Write-Host ''
    Write-Host '  [B] Cancel'
    $choice = Read-MenuChoice
    switch ($choice.ToUpper()) {
        'C' { return (Get-Location).Path }
        'B' { return $null }
        'W' {
            $workspaces = @(Get-TestWorkspaces)
            if ($workspaces.Count -eq 0) {
                Write-Host '  No test workspaces found.' -ForegroundColor Yellow
                return $null
            }
            $paths = @($workspaces | ForEach-Object { $_.FullName })
            return (Select-FromList -Prompt '  Workspace number' -Items $paths)
        }
        'E' {
            $path = $null
            try { $path = (Read-Host '  Path').Trim() } catch { }
            if ([string]::IsNullOrWhiteSpace($path)) { return $null }
            return $path
        }
        default {
            Write-Host "  Invalid selection '$choice'." -ForegroundColor Yellow
            return $null
        }
    }
}

function Invoke-MenuOperation {
    param([string[]] $CmdArgs)
    Write-Host ''
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $env:MXAGILE_NONINTERACTIVE = '1'
    # Capture output explicitly so it reliably flows through this process's
    # stdout pipeline regardless of grandchild handle inheritance.
    $cmdOutput = & powershell -NoProfile -File $script:CliPath @CmdArgs 2>&1
    $ec = $LASTEXITCODE
    Remove-Item Env:\MXAGILE_NONINTERACTIVE -ErrorAction SilentlyContinue
    $ErrorActionPreference = $prevEAP
    if ($null -ne $cmdOutput) {
        foreach ($line in $cmdOutput) {
            if ($line -is [System.Management.Automation.ErrorRecord]) {
                Write-Host $line.ToString() -ForegroundColor Red
            } else {
                Write-Host $line
            }
        }
    }
    return $ec
}

# ---- Interactive menu screens ------------------------------------------------

function Show-TestsMenu {
    while ($true) {
        Write-Host ''
        Write-Host '  Tests' -ForegroundColor Cyan
        Write-Host '  -----' -ForegroundColor DarkCyan
        Write-Host ''
        Write-Host '  [1] List test suites'
        Write-Host '  [2] Run one test suite'
        Write-Host '  [3] Run all tests'
        Write-Host ''
        Write-Host '  [B] Back  [Q] Quit'
        $choice = Read-MenuChoice
        switch ($choice.ToUpper()) {
            '1' {
                $null = Invoke-MenuOperation @('test', 'list')
                Wait-Continue
            }
            '2' {
                $suites = @(Get-TestSuites)
                Write-Host ''
                Write-Host '  Available test suites:' -ForegroundColor DarkCyan
                $selected = Select-FromList -Prompt '  Suite number' -Items $suites
                if ($null -ne $selected) {
                    $null = Invoke-MenuOperation @('test', 'run', $selected)
                    Wait-Continue
                }
            }
            '3' {
                $null = Invoke-MenuOperation @('test', 'all')
                Wait-Continue
            }
            'B' { return }
            default { Write-Host "  Unknown option '$choice'." -ForegroundColor Yellow }
        }
    }
}

function Show-WorkspacesMenu {
    while ($true) {
        Write-Host ''
        Write-Host '  Test Workspaces' -ForegroundColor Cyan
        Write-Host '  ---------------' -ForegroundColor DarkCyan
        Write-Host ''
        Write-Host '  [1] List workspaces'
        Write-Host '  [2] Create workspace'
        Write-Host '  [3] Reset workspace'
        Write-Host '  [4] Remove workspace'
        Write-Host ''
        Write-Host '  [B] Back  [Q] Quit'
        $choice = Read-MenuChoice
        switch ($choice.ToUpper()) {
            '1' {
                $null = Invoke-MenuOperation @('workspace', 'list')
                Wait-Continue
            }
            '2' {
                $templates = @(Get-AvailableTemplates)
                if ($templates.Count -eq 0) {
                    Write-Host '  No templates found.' -ForegroundColor Yellow
                    Wait-Continue
                } else {
                    Write-Host ''
                    Write-Host '  Available templates:' -ForegroundColor DarkCyan
                    $selected = Select-FromList -Prompt '  Template number' -Items $templates
                    if ($null -ne $selected) {
                        $null = Invoke-MenuOperation @('workspace', 'create', $selected)
                        Wait-Continue
                    }
                }
            }
            '3' {
                $workspaces = @(Get-TestWorkspaces)
                if ($workspaces.Count -eq 0) {
                    Write-Host '  No workspaces found.' -ForegroundColor Yellow
                    Wait-Continue
                } else {
                    Write-Host ''
                    Write-Host '  Existing workspaces:' -ForegroundColor DarkCyan
                    $names = @($workspaces | ForEach-Object { $_.Name -replace '^\.testing-', '' })
                    $selected = Select-FromList -Prompt '  Workspace number' -Items $names
                    if ($null -ne $selected) {
                        Write-Host ''
                        Write-Host "  Reset .testing-$selected from template '$selected'?" -ForegroundColor Yellow
                        Write-Host '  Confirm? [y/N] ' -NoNewline
                        $confirm = $null
                        try { $confirm = (Read-Host).Trim() } catch { $confirm = '' }
                        if ($confirm -eq 'y' -or $confirm -eq 'Y') {
                            $null = Invoke-MenuOperation @('workspace', 'reset', $selected)
                        } else {
                            Write-Host '  Cancelled.' -ForegroundColor DarkGray
                        }
                        Wait-Continue
                    }
                }
            }
            '4' {
                $workspaces = @(Get-TestWorkspaces)
                if ($workspaces.Count -eq 0) {
                    Write-Host '  No workspaces found.' -ForegroundColor Yellow
                    Wait-Continue
                } else {
                    Write-Host ''
                    Write-Host '  Existing workspaces:' -ForegroundColor DarkCyan
                    $names = @($workspaces | ForEach-Object { $_.Name -replace '^\.testing-', '' })
                    $selected = Select-FromList -Prompt '  Workspace number' -Items $names
                    if ($null -ne $selected) {
                        $fullPath = Join-Path $script:RepoRoot ".testing-$selected"
                        Write-Host ''
                        Write-Host "  Remove: $fullPath" -ForegroundColor Yellow
                        Write-Host '  Confirm? [y/N] ' -NoNewline
                        $confirm = $null
                        try { $confirm = (Read-Host).Trim() } catch { $confirm = '' }
                        if ($confirm -eq 'y' -or $confirm -eq 'Y') {
                            $null = Invoke-MenuOperation @('workspace', 'remove', $selected)
                        } else {
                            Write-Host '  Cancelled.' -ForegroundColor DarkGray
                        }
                        Wait-Continue
                    }
                }
            }
            'B' { return }
            default { Write-Host "  Unknown option '$choice'." -ForegroundColor Yellow }
        }
    }
}

function Show-ProjectMenu {
    while ($true) {
        Write-Host ''
        Write-Host '  Project Diagnostics' -ForegroundColor Cyan
        Write-Host '  -------------------' -ForegroundColor DarkCyan
        Write-Host ''
        Write-Host '  [1] Detect project type'
        Write-Host '  [2] Project status'
        Write-Host ''
        Write-Host '  [B] Back  [Q] Quit'
        $choice = Read-MenuChoice
        switch ($choice.ToUpper()) {
            '1' {
                $path = Select-ProjectPath -Verb 'project to detect'
                if ($null -ne $path) {
                    Write-Host "  Target: $path" -ForegroundColor DarkCyan
                    $null = Invoke-MenuOperation @('project', 'detect', $path)
                    Wait-Continue
                }
            }
            '2' {
                $path = Select-ProjectPath -Verb 'project for status'
                if ($null -ne $path) {
                    Write-Host "  Target: $path" -ForegroundColor DarkCyan
                    $null = Invoke-MenuOperation @('project', 'status', $path)
                    Wait-Continue
                }
            }
            'B' { return }
            default { Write-Host "  Unknown option '$choice'." -ForegroundColor Yellow }
        }
    }
}

function Show-InstallMenu {
    while ($true) {
        Write-Host ''
        Write-Host '  Installation' -ForegroundColor Cyan
        Write-Host '  ------------' -ForegroundColor DarkCyan
        Write-Host ''
        Write-Host '  [1] Core installer       (install-mxagile.ps1)'
        Write-Host '  [2] Mercedes installer   (install-mxagile-mercedes.ps1)'
        Write-Host ''
        Write-Host '  [B] Back  [Q] Quit'
        $choice = Read-MenuChoice
        switch ($choice.ToUpper()) {
            '1' {
                $path = $null
                try { $path = (Read-Host '  Target project path').Trim() } catch { }
                if (-not [string]::IsNullOrWhiteSpace($path)) {
                    $resolved = if ([System.IO.Path]::IsPathRooted($path)) { $path } else { Join-Path (Get-Location).Path $path }
                    Write-Host ''
                    Write-Host '  Install MxAgile Core to:' -ForegroundColor Yellow
                    Write-Host "    $resolved" -ForegroundColor Yellow
                    Write-Host '  Confirm? [y/N] ' -NoNewline
                    $confirm = $null
                    try { $confirm = (Read-Host).Trim() } catch { $confirm = '' }
                    if ($confirm -eq 'y' -or $confirm -eq 'Y') {
                        $null = Invoke-MenuOperation @('install', 'core', $resolved)
                    } else {
                        Write-Host '  Cancelled.' -ForegroundColor DarkGray
                    }
                    Wait-Continue
                }
            }
            '2' {
                $path = $null
                try { $path = (Read-Host '  Target project path').Trim() } catch { }
                if (-not [string]::IsNullOrWhiteSpace($path)) {
                    $resolved = if ([System.IO.Path]::IsPathRooted($path)) { $path } else { Join-Path (Get-Location).Path $path }
                    Write-Host ''
                    Write-Host '  Install MxAgile (Mercedes) to:' -ForegroundColor Yellow
                    Write-Host "    $resolved" -ForegroundColor Yellow
                    Write-Host '  Confirm? [y/N] ' -NoNewline
                    $confirm = $null
                    try { $confirm = (Read-Host).Trim() } catch { $confirm = '' }
                    if ($confirm -eq 'y' -or $confirm -eq 'Y') {
                        $null = Invoke-MenuOperation @('install', 'mercedes', $resolved)
                    } else {
                        Write-Host '  Cancelled.' -ForegroundColor DarkGray
                    }
                    Wait-Continue
                }
            }
            'B' { return }
            default { Write-Host "  Unknown option '$choice'." -ForegroundColor Yellow }
        }
    }
}

function Show-MigrationMenu {
    while ($true) {
        Write-Host ''
        Write-Host '  Migration' -ForegroundColor Cyan
        Write-Host '  ---------' -ForegroundColor DarkCyan
        Write-Host ''
        Write-Host '  [1] Migration status'
        Write-Host ''
        Write-Host '  [B] Back  [Q] Quit'
        $choice = Read-MenuChoice
        switch ($choice.ToUpper()) {
            '1' {
                $path = Select-ProjectPath -Verb 'project for migration status'
                if ($null -ne $path) {
                    Write-Host "  Target: $path" -ForegroundColor DarkCyan
                    $null = Invoke-MenuOperation @('migration', 'status', $path)
                    Wait-Continue
                }
            }
            'B' { return }
            default { Write-Host "  Unknown option '$choice'." -ForegroundColor Yellow }
        }
    }
}

function Show-ScriptsMenu {
    while ($true) {
        Write-Host ''
        Write-Host '  Developer Scripts' -ForegroundColor Cyan
        Write-Host '  -----------------' -ForegroundColor DarkCyan
        Write-Host ''
        for ($i = 0; $i -lt $script:ScriptCatalog.Count; $i++) {
            $entry = $script:ScriptCatalog[$i]
            $safetyColor = switch ($entry.Safety) {
                'READ_ONLY' { 'DarkGreen' }
                'TEST'      { 'Cyan' }
                'MUTATING'  { 'Yellow' }
                'INTERNAL'  { 'DarkGray' }
                default     { 'White' }
            }
            $num  = "[$($i+1)]".PadRight(5)
            $name = $entry.Display.PadRight(38)
            Write-Host "  $num $name" -NoNewline
            Write-Host "[$($entry.Safety)]" -ForegroundColor $safetyColor
        }
        Write-Host ''
        Write-Host '  [B] Back  [Q] Quit'
        $choice = Read-MenuChoice
        if ($choice.ToUpper() -eq 'B') { return }
        $idx = 0
        if ([int]::TryParse($choice, [ref]$idx) -and $idx -ge 1 -and $idx -le $script:ScriptCatalog.Count) {
            $entry = $script:ScriptCatalog[$idx - 1]
            Write-Host ''
            Write-Host "  $($entry.Display)" -ForegroundColor Cyan
            Write-Host "  Path    : $($entry.Path)" -ForegroundColor DarkGray
            Write-Host "  Purpose : $($entry.Purpose)" -ForegroundColor DarkGray
            Write-Host "  Safety  : $($entry.Safety)" -ForegroundColor DarkGray
            Write-Host "  Category: $($entry.Category)" -ForegroundColor DarkGray
            if ($entry.Safety -eq 'INTERNAL') {
                Write-Host ''
                Write-Host '  INTERNAL: run via a higher-level command instead.' -ForegroundColor Yellow
            }
            Wait-Continue
        } else {
            Write-Host "  Unknown option '$choice'." -ForegroundColor Yellow
        }
    }
}

function Start-InteractiveMenu {
    while ($true) {
        Write-Host ''
        Write-Host '  MxAgile Developer Tools' -ForegroundColor Cyan
        Write-Host '  =======================' -ForegroundColor DarkCyan
        Write-Host ''
        Write-Host '  [1] Tests'
        Write-Host '  [2] Test Workspaces'
        Write-Host '  [3] Project Diagnostics'
        Write-Host '  [4] Installation'
        Write-Host '  [5] Migration'
        Write-Host '  [6] Scripts / Tools'
        Write-Host ''
        Write-Host '  [Q] Quit'
        $choice = Read-MenuChoice
        switch ($choice.ToUpper()) {
            '1' { Show-TestsMenu }
            '2' { Show-WorkspacesMenu }
            '3' { Show-ProjectMenu }
            '4' { Show-InstallMenu }
            '5' { Show-MigrationMenu }
            '6' { Show-ScriptsMenu }
            default { Write-Host "  Unknown option '$choice'. Press Q to quit." -ForegroundColor Yellow }
        }
    }
}

# ---- test --------------------------------------------------------------------

function Invoke-TestCommand {
    param([string] $Sub, [string] $SuiteName)

    $testsDir = Join-Path $script:RepoRoot 'tests'

    switch ($Sub) {

        'list' {
            Write-Section 'Available test suites'
            Write-Row 'smoke        basic script-existence checks (smoke-test.ps1)'
            Write-Row 'installer    full installer regression (run-installer-tests.ps1)'
            Get-ChildItem -LiteralPath $testsDir -Filter 'test-*.ps1' |
                Sort-Object Name |
                ForEach-Object { Write-Row ($_.BaseName -replace '^test-', '') }
            Write-Host ''
            Write-Faint "Run a suite : mxagile-dev test run <suite>"
            Write-Faint "Run all     : mxagile-dev test all"
            return
        }

        'all' {
            & powershell -NoProfile -File (Join-Path $testsDir 'run-all-tests.ps1')
            exit $LASTEXITCODE
        }

        'run' {
            if ([string]::IsNullOrWhiteSpace($SuiteName)) {
                Write-Host 'mxagile-dev test run: suite name required.' -ForegroundColor Red
                Write-Host "  Run 'mxagile-dev test list' to see available suites."
                exit 2
            }
            switch -Exact ($SuiteName) {
                'smoke' {
                    & powershell -NoProfile -File (Join-Path $testsDir 'smoke-test.ps1')
                    exit $LASTEXITCODE
                }
                'installer' {
                    & powershell -NoProfile -File (Join-Path $testsDir 'run-installer-tests.ps1') `
                        -Test All -SkipMercedesIntegration
                    exit $LASTEXITCODE
                }
                'all' {
                    & powershell -NoProfile -File (Join-Path $testsDir 'run-all-tests.ps1')
                    exit $LASTEXITCODE
                }
                default {
                    $target = Join-Path $testsDir "test-$SuiteName.ps1"
                    if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
                        Write-Host "mxagile-dev test run: unknown suite '$SuiteName'." -ForegroundColor Red
                        Write-Host "  Run 'mxagile-dev test list' to see available suites."
                        exit 2
                    }
                    & powershell -NoProfile -File $target
                    exit $LASTEXITCODE
                }
            }
        }

        default {
            $q = if ([string]::IsNullOrWhiteSpace($Sub)) { 'subcommand required' } else { "unknown subcommand '$Sub'" }
            Write-Host "mxagile-dev test: $q." -ForegroundColor Red
            Write-Host '  Expected: list, run <suite>, all'
            exit 2
        }
    }
}

# ---- workspace ---------------------------------------------------------------

function Get-AvailableTemplates {
    $dir = Join-Path $script:RepoRoot 'project-templates'
    if (Test-Path -LiteralPath $dir -PathType Container) {
        (Get-ChildItem -LiteralPath $dir -Directory).Name
    }
}

function Assert-WorkspaceSafety {
    param([string] $RawName)

    # Accept name with or without .testing- prefix
    $leafName = $RawName -replace '^\.testing-', ''
    $fullPath = Join-Path $script:RepoRoot ".testing-$leafName"

    if (-not (Test-Path -LiteralPath $fullPath -PathType Container)) {
        Write-Host "mxagile-dev: workspace '.testing-$leafName' not found." -ForegroundColor Red
        exit 2
    }

    $resolved     = [System.IO.Path]::GetFullPath($fullPath)
    $resolvedRoot = [System.IO.Path]::GetFullPath($script:RepoRoot)
    $resolvedLeaf = Split-Path $resolved -Leaf

    if (-not ($resolved.StartsWith($resolvedRoot + [System.IO.Path]::DirectorySeparatorChar) -or
              $resolved -eq $resolvedRoot)) {
        Write-Host 'mxagile-dev: Safety violation -- workspace path escapes repo root.' -ForegroundColor Red
        exit 3
    }
    if ($resolvedLeaf -notlike '.testing-*') {
        Write-Host "mxagile-dev: Safety violation -- '$resolvedLeaf' does not have .testing- prefix." -ForegroundColor Red
        exit 3
    }

    return $resolved
}

function Invoke-WorkspaceCommand {
    param([string] $Sub, [string] $WsName)

    switch ($Sub) {

        'list' {
            $workspaces = @(Get-ChildItem -LiteralPath $script:RepoRoot -Filter '.testing-*' -Directory -ErrorAction SilentlyContinue)
            if ($workspaces.Count -eq 0) {
                Write-Host '  No test workspaces found.'
                $templates = @(Get-AvailableTemplates)
                if ($templates.Count -gt 0) {
                    Write-Faint "  Templates: $($templates -join ', ')"
                    Write-Faint '  Run: mxagile-dev workspace create <template>'
                }
                return
            }
            Write-Section "Test workspaces ($($workspaces.Count))"
            foreach ($ws in $workspaces) {
                $label    = $ws.Name -replace '^\.testing-', ''
                $modified = $ws.LastWriteTime.ToString('yyyy-MM-dd')
                Write-Row "$label  ($modified)"
            }
            Write-Host ''
            return
        }

        'create' {
            if ([string]::IsNullOrWhiteSpace($WsName)) {
                Write-Host 'mxagile-dev workspace create: template name required.' -ForegroundColor Red
                $templates = @(Get-AvailableTemplates)
                if ($templates.Count -gt 0) { Write-Host "  Templates: $($templates -join ', ')" }
                exit 2
            }
            $createScript = Join-Path $script:RepoRoot 'scripts\create-test-workcopy.ps1'
            $scriptArgs   = @('-TemplateName', $WsName)
            if ($Force) { $scriptArgs += '-Force' }
            & powershell -NoProfile -File $createScript @scriptArgs
            exit $LASTEXITCODE
        }

        'reset' {
            if ([string]::IsNullOrWhiteSpace($WsName)) {
                Write-Host 'mxagile-dev workspace reset: workspace name required.' -ForegroundColor Red
                exit 2
            }
            $leafName     = $WsName -replace '^\.testing-', ''
            $createScript = Join-Path $script:RepoRoot 'scripts\create-test-workcopy.ps1'
            & powershell -NoProfile -File $createScript -TemplateName $leafName -TestDirName $leafName -Force
            exit $LASTEXITCODE
        }

        'remove' {
            if ([string]::IsNullOrWhiteSpace($WsName)) {
                Write-Host 'mxagile-dev workspace remove: workspace name required.' -ForegroundColor Red
                exit 2
            }
            $resolved = Assert-WorkspaceSafety -RawName $WsName
            Write-Host "  Removing: $resolved" -ForegroundColor Yellow
            try {
                Remove-Item -LiteralPath $resolved -Recurse -Force
                Write-Host "  Removed: $(Split-Path $resolved -Leaf)" -ForegroundColor Green
            } catch {
                Write-Host "mxagile-dev workspace remove: failed -- $_" -ForegroundColor Red
                exit 1
            }
            return
        }

        default {
            $q = if ([string]::IsNullOrWhiteSpace($Sub)) { 'subcommand required' } else { "unknown subcommand '$Sub'" }
            Write-Host "mxagile-dev workspace: $q." -ForegroundColor Red
            Write-Host '  Expected: list, create <template>, reset <workspace>, remove <workspace>'
            exit 2
        }
    }
}

# ---- project -----------------------------------------------------------------

function Resolve-ProjectArg {
    param([string] $PathArg)
    if ([string]::IsNullOrWhiteSpace($PathArg)) { return (Get-Location).Path }
    if ([System.IO.Path]::IsPathRooted($PathArg)) { return $PathArg }
    return Join-Path (Get-Location).Path $PathArg
}

function Invoke-ProjectCommand {
    param([string] $Sub, [string] $PathArg)

    $detectScript = Join-Path $script:RepoRoot 'scripts\detect-project-type.ps1'

    switch ($Sub) {

        'detect' {
            $projectPath = Resolve-ProjectArg $PathArg
            if (-not (Test-Path -LiteralPath $projectPath -PathType Container)) {
                Write-Host "mxagile-dev project detect: path not found: $projectPath" -ForegroundColor Red
                exit 2
            }
            & powershell -NoProfile -File $detectScript -ProjectRoot $projectPath
            exit $LASTEXITCODE
        }

        'status' {
            $projectPath = Resolve-ProjectArg $PathArg
            if (-not (Test-Path -LiteralPath $projectPath -PathType Container)) {
                Write-Host "mxagile-dev project status: path not found: $projectPath" -ForegroundColor Red
                exit 2
            }

            Write-Section "Project status: $projectPath"

            # Mendix project file
            $mprs = @(Get-ChildItem -LiteralPath $projectPath -Filter '*.mpr' -File -ErrorAction SilentlyContinue)
            Write-Row ("Mendix project  : " + $(switch ($mprs.Count) {
                0       { '(none)' }
                1       { $mprs[0].Name }
                default { "$($mprs.Count) files (AMBIGUOUS)" }
            }))

            # Classification via canonical script
            $rawLines = @(& powershell -NoProfile -File $detectScript -ProjectRoot $projectPath 2>$null)
            $lastExit = $LASTEXITCODE
            if ($lastExit -eq 0) {
                try {
                    $parsed = ($rawLines -join "`n") | ConvertFrom-Json -ErrorAction Stop
                    Write-Row "Project type    : $($parsed.Classification)"
                    if ($parsed.DfcEvidence.Count     -gt 0) { Write-Faint "  dfc      : $($parsed.DfcEvidence     -join '; ')" }
                    if ($parsed.MxAgileEvidence.Count  -gt 0) { Write-Faint "  mxagile  : $($parsed.MxAgileEvidence  -join '; ')" }
                    if ($parsed.MigrationEvidence.Count -gt 0) { Write-Faint "  migration: $($parsed.MigrationEvidence -join '; ')" }
                } catch {
                    Write-Row "Project type    : (parse error -- run 'project detect' for raw output)"
                }
            } else {
                Write-Row "Project type    : (detection failed, exit $lastExit)"
            }

            # Lifecycle
            $lcPath = Join-Path $projectPath '.mxagile\lifecycle.yaml'
            Write-Row ("lifecycle.yaml  : " + $(if (Test-Path -LiteralPath $lcPath -PathType Leaf) { 'present' } else { 'absent' }))

            # Migration state
            $migPath = Join-Path $projectPath '.mxagile\migration\state.yaml'
            if (Test-Path -LiteralPath $migPath -PathType Leaf) {
                Write-Row "migration state : present"
                $sc = Get-Content -LiteralPath $migPath -Raw -ErrorAction SilentlyContinue
                if ($sc -match 'status:\s*(\S+)')              { Write-Faint "  status   : $($Matches[1])" }
                if ($sc -match 'last_completed_step:\s*(\S+)') { Write-Faint "  last_step: $($Matches[1])" }
            } else {
                Write-Row "migration state : absent"
            }

            # Brownfield baseline
            $bfPath = Join-Path $projectPath '.mxagile\brownfield-baseline.md'
            Write-Row ("brownfield base : " + $(if (Test-Path -LiteralPath $bfPath -PathType Leaf) { 'present' } else { 'absent' }))

            Write-Host ''
            return
        }

        default {
            $q = if ([string]::IsNullOrWhiteSpace($Sub)) { 'subcommand required' } else { "unknown subcommand '$Sub'" }
            Write-Host "mxagile-dev project: $q." -ForegroundColor Red
            Write-Host '  Expected: detect [path], status [path]'
            exit 2
        }
    }
}

# ---- install -----------------------------------------------------------------

function Invoke-InstallCommand {
    param([string] $Sub, [string] $PathArg)

    switch ($Sub) {

        'core' {
            if ([string]::IsNullOrWhiteSpace($PathArg)) {
                Write-Host 'mxagile-dev install core: project path required.' -ForegroundColor Red
                Write-Host '  Usage: mxagile-dev install core <path>'
                exit 2
            }
            $targetPath    = Resolve-ProjectArg $PathArg
            $installScript = Join-Path $script:RepoRoot 'install-mxagile.ps1'
            & powershell -NoProfile -File $installScript -ProjectRoot $targetPath
            exit $LASTEXITCODE
        }

        'mercedes' {
            if ([string]::IsNullOrWhiteSpace($PathArg)) {
                Write-Host 'mxagile-dev install mercedes: project path required.' -ForegroundColor Red
                Write-Host '  Usage: mxagile-dev install mercedes <path>'
                exit 2
            }
            $targetPath    = Resolve-ProjectArg $PathArg
            $installScript = Join-Path $script:RepoRoot 'install-mxagile-mercedes.ps1'
            & powershell -NoProfile -File $installScript -ProjectRoot $targetPath
            exit $LASTEXITCODE
        }

        default {
            $q = if ([string]::IsNullOrWhiteSpace($Sub)) { 'subcommand required' } else { "unknown subcommand '$Sub'" }
            Write-Host "mxagile-dev install: $q." -ForegroundColor Red
            Write-Host '  Expected: core <path>, mercedes <path>'
            exit 2
        }
    }
}

# ---- migration ---------------------------------------------------------------

function Invoke-MigrationCommand {
    param([string] $Sub, [string] $PathArg)

    switch ($Sub) {

        'status' {
            $projectPath = Resolve-ProjectArg $PathArg
            if (-not (Test-Path -LiteralPath $projectPath -PathType Container)) {
                Write-Host "mxagile-dev migration status: path not found: $projectPath" -ForegroundColor Red
                exit 2
            }

            Write-Section "Migration status: $projectPath"

            # Classification
            $detectScript = Join-Path $script:RepoRoot 'scripts\detect-project-type.ps1'
            $rawLines = @(& powershell -NoProfile -File $detectScript -ProjectRoot $projectPath 2>$null)
            if ($LASTEXITCODE -eq 0) {
                try {
                    $parsed = ($rawLines -join "`n") | ConvertFrom-Json -ErrorAction Stop
                    Write-Row "Project type    : $($parsed.Classification)"
                } catch {
                    Write-Row "Project type    : (parse error -- run 'project detect' for raw output)"
                }
            } else {
                Write-Row "Project type    : (detection failed)"
            }

            # Migration state.yaml
            $migPath = Join-Path $projectPath '.mxagile\migration\state.yaml'
            if (Test-Path -LiteralPath $migPath -PathType Leaf) {
                Write-Row "state.yaml      : present"
                Get-Content -LiteralPath $migPath | ForEach-Object { Write-Faint "  $_" }
            } else {
                Write-Row "state.yaml      : absent"
            }

            # Migration README
            $migReadme = Join-Path $projectPath '.mxagile\migration\README.md'
            Write-Row ("migration README: " + $(if (Test-Path -LiteralPath $migReadme -PathType Leaf) { 'present' } else { 'absent' }))

            # Brownfield baseline
            $bfPath = Join-Path $projectPath '.mxagile\brownfield-baseline.md'
            Write-Row ("brownfield base : " + $(if (Test-Path -LiteralPath $bfPath -PathType Leaf) { 'present' } else { 'absent' }))

            # Legacy DFC marker
            $dfcPath = Join-Path $projectPath '.dfc-ai'
            Write-Row (".dfc-ai/        : " + $(if (Test-Path -LiteralPath $dfcPath -PathType Container) { 'present' } else { 'absent' }))

            Write-Host ''
            return
        }

        default {
            $q = if ([string]::IsNullOrWhiteSpace($Sub)) { 'subcommand required' } else { "unknown subcommand '$Sub'" }
            Write-Host "mxagile-dev migration: $q." -ForegroundColor Red
            Write-Host '  Expected: status [path]'
            exit 2
        }
    }
}

# ---- Main dispatch -----------------------------------------------------------

if ($Help) {
    Show-RootHelp
    exit 0
}

if ([string]::IsNullOrWhiteSpace($Command)) {
    if ($env:MXAGILE_NONINTERACTIVE -ne '1') {
        Start-InteractiveMenu
    } else {
        Show-RootHelp
    }
    exit 0
}

switch ($Command) {
    'test'      { Invoke-TestCommand      -Sub $SubCommand -SuiteName $Arg1 }
    'workspace' { Invoke-WorkspaceCommand -Sub $SubCommand -WsName    $Arg1 }
    'project'   { Invoke-ProjectCommand   -Sub $SubCommand -PathArg   $Arg1 }
    'install'   { Invoke-InstallCommand   -Sub $SubCommand -PathArg   $Arg1 }
    'migration' { Invoke-MigrationCommand -Sub $SubCommand -PathArg   $Arg1 }
    default {
        Write-Host "mxagile-dev: unknown command '$Command'." -ForegroundColor Red
        Write-Host "  Run 'mxagile-dev' or 'mxagile-dev --help' for usage."
        exit 2
    }
}
