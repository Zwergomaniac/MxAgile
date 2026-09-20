<#
.SYNOPSIS
Runs the MxAgile installer regression suite against disposable project-template workcopies.

.DESCRIPTION
Uses the existing scripts/create-test-workcopy.ps1 helper and the two public bootstrap
installers. Installers are invoked through pwsh from inside each disposable target project,
so $PWD and the installer $PSScriptRoot are intentionally different.

The suite never targets a real Mendix project. Test workspaces are created directly below
the repository root using the .testing-* naming convention.

.PARAMETER GreenfieldTemplate
Directory name below project-templates used for Greenfield tests.

.PARAMETER BrownfieldTemplate
Directory name below project-templates used for Brownfield tests. Brownfield tests are
reported as SKIPPED_ENVIRONMENT when the template does not exist.

.PARAMETER SkipMercedesIntegration
Skips tests requiring access to the Mercedes-Benz Git repository.

.PARAMETER KeepSuccessfulWorkspaces
Keeps successful .testing-* workspaces. Failed workspaces are always retained.

.PARAMETER StopOnFailure
Stops after the first failed test. By default, independent tests continue.

.EXAMPLE
pwsh -NoProfile -File ./tests/run-installer-tests.ps1

.EXAMPLE
pwsh -NoProfile -File ./tests/run-installer-tests.ps1 -SkipMercedesIntegration
#>
[CmdletBinding()]
param(
    [string]$GreenfieldTemplate = 'greenfield',
    [string]$BrownfieldTemplate = 'brownfield',
    [switch]$SkipMercedesIntegration,
    [switch]$KeepSuccessfulWorkspaces,
    [switch]$StopOnFailure
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$SuitePath = $MyInvocation.MyCommand.Path
$TestsRoot = Split-Path -Parent $SuitePath
$RepoRoot = Split-Path -Parent $TestsRoot

$Pwsh = (Get-Command pwsh -ErrorAction Stop).Source
$WorkcopyScript = Join-Path $RepoRoot 'scripts/create-test-workcopy.ps1'
$GenericInstaller = Join-Path $RepoRoot 'install-mxagile.ps1'
$MercedesInstaller = Join-Path $RepoRoot 'install-mxagile-mercedes.ps1'
$ProjectTemplatesRoot = Join-Path $RepoRoot 'project-templates'

$Results = [System.Collections.Generic.List[object]]::new()
$CurrentTest = $null

function Add-TestResult {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ValidateSet('PASS', 'FAIL', 'SKIPPED_ENVIRONMENT')][string]$Status,
        [string]$Reason = '',
        [string]$Workspace = '',
        [string]$Command = '',
        [Nullable[int]]$ExitCode = $null,
        [string]$StdOut = '',
        [string]$StdErr = ''
    )

    $Results.Add([pscustomobject]@{
            Name      = $Name
            Status    = $Status
            Reason    = $Reason
            Workspace = $Workspace
            Command   = $Command
            ExitCode  = $ExitCode
            StdOut    = $StdOut
            StdErr    = $StdErr
        })

    $color = switch ($Status) {
        'PASS' { 'Green' }
        'FAIL' { 'Red' }
        default { 'Yellow' }
    }
    Write-Host ("{0,-20} {1}" -f $Status, $Name) -ForegroundColor $color
    if ($Reason) { Write-Host "  $Reason" }

    if ($Status -eq 'FAIL' -and $StopOnFailure) {
        throw "Stopping after failed test '$Name'."
    }
}

function Invoke-PwshFile {
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [string[]]$Arguments = @(),

        [Parameter(Mandatory)]
        [string]$WorkingDirectory
    )

    $psi = [System.Diagnostics.ProcessStartInfo]::new()

    $psi.FileName = $Pwsh
    $psi.WorkingDirectory = $WorkingDirectory

    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    # IMPORTANT:
    # ArgumentList preserves arguments containing spaces correctly.
    $psi.ArgumentList.Add("-NoProfile")
    $psi.ArgumentList.Add("-File")
    $psi.ArgumentList.Add($FilePath)

    foreach ($argument in $Arguments) {
        $psi.ArgumentList.Add($argument)
    }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $psi

    try {
        if (-not $process.Start()) {
            throw "Failed to start PowerShell process."
        }

        # Read both streams before/while waiting to avoid pipe deadlocks.
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()

        $process.WaitForExit()

        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()

        $displayArgs = @(
            "-NoProfile"
            "-File"
            "`"$FilePath`""
        )

        foreach ($argument in $Arguments) {
            if ($argument -match "\s") {
                $displayArgs += "`"$argument`""
            }
            else {
                $displayArgs += $argument
            }
        }

        return [pscustomobject]@{
            ExitCode        = $process.ExitCode
            StdOut          = $stdout
            StdErr          = $stderr
            Command         = "pwsh " + ($displayArgs -join " ")
            WorkingDirectory = $WorkingDirectory
        }
    }
    finally {
        $process.Dispose()
    }
}

function Assert-Path {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Description)
    if (-not (Test-Path -LiteralPath $Path)) { throw "$Description not found: $Path" }
}

function Assert-SingleRootMpr {
    param([Parameter(Mandatory)][string]$ProjectRoot)
    $mpr = @(Get-ChildItem -LiteralPath $ProjectRoot -File -Filter '*.mpr')
    if ($mpr.Count -ne 1) {
        $names = ($mpr.Name -join ', ')
        throw "Expected exactly one root-level .mpr in '$ProjectRoot'; found $($mpr.Count): $names"
    }
    return $mpr[0]
}

function New-Workcopy {
    param(
        [Parameter(Mandatory)][string]$TemplateName,
        [Parameter(Mandatory)][string]$TestDirName
    )

    $workspace = Join-Path $RepoRoot ".testing-$TestDirName"
    $result = Invoke-PwshFile -FilePath $WorkcopyScript `
        -Arguments @('-TemplateName', $TemplateName, '-TestDirName', $TestDirName, '-Force') `
        -WorkingDirectory $RepoRoot

    if ($result.ExitCode -ne 0) {
        throw "Workcopy creation failed.`nCommand: $($result.Command)`nSTDOUT:`n$($result.StdOut)`nSTDERR:`n$($result.StdErr)"
    }
    Assert-Path -Path $workspace -Description 'Testing workspace'
    [void](Assert-SingleRootMpr -ProjectRoot $workspace)
    return $workspace
}

function Get-TreeFingerprint {
    param([Parameter(Mandatory)][string]$Root)
    $entries = Get-ChildItem -LiteralPath $Root -Recurse -File -Force |
    Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' } |
    ForEach-Object {
        $relative = [IO.Path]::GetRelativePath($Root, $_.FullName).Replace('\\', '/')
        $hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
        "$relative|$hash"
    } |
    Sort-Object
    return (($entries -join "`n") | ConvertTo-Json -Compress)
}

function Remove-SuccessWorkspace {
    param([string]$Path)
    if ($KeepSuccessfulWorkspaces -or -not $Path) { return }
    $resolvedRepo = [IO.Path]::GetFullPath($RepoRoot).TrimEnd([IO.Path]::DirectorySeparatorChar)
    $resolvedPath = [IO.Path]::GetFullPath($Path)
    $leaf = Split-Path -Leaf $resolvedPath
    if (-not $resolvedPath.StartsWith($resolvedRepo + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or
        -not $leaf.StartsWith('.testing-', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to delete unsafe workspace path: $resolvedPath"
    }
    Remove-Item -LiteralPath $resolvedPath -Recurse -Force
}

function Test-PowerShellParser {
    $name = 'PowerShell parser'
    try {
        $files = @(
            $WorkcopyScript,
            $GenericInstaller,
            $MercedesInstaller,
            (Join-Path $RepoRoot 'scripts/fetch-layer.ps1'),
            (Join-Path $RepoRoot 'scripts/setup-agent-system.ps1'),
            (Join-Path $RepoRoot 'scripts/apply-project-agent-instructions.ps1')
        ) | Where-Object { Test-Path -LiteralPath $_ }

        $allErrors = @()
        foreach ($file in $files) {
            $tokens = $null
            $errors = $null
            [void][Management.Automation.Language.Parser]::ParseFile($file, [ref]$tokens, [ref]$errors)
            foreach ($error in @($errors)) {
                $allErrors += "${file}:$($error.Extent.StartLineNumber): $($error.Message)"
            }
        }
        if ($allErrors.Count) { throw ($allErrors -join "`n") }
        Add-TestResult -Name $name -Status PASS -Reason "$($files.Count) script(s) parsed successfully."
    }
    catch {
        Add-TestResult -Name $name -Status FAIL -Reason $_.Exception.Message
    }
}

function Test-MprSafety {
    $root = Join-Path $RepoRoot '.testing-mpr-safety'
    try {
        if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
        New-Item -ItemType Directory -Path $root | Out-Null

        $zero = Invoke-PwshFile -FilePath $GenericInstaller -WorkingDirectory $root
        if ($zero.ExitCode -eq 0) { throw 'Zero-MPR invocation unexpectedly succeeded.' }
        $zeroTouched = Test-Path -LiteralPath (Join-Path $root '.mxagile')
        if ($zeroTouched) { throw 'Zero-MPR invocation mutated the project.' }
        Add-TestResult -Name 'MPR safety: zero' -Status PASS -Reason 'Rejected before installation.' -Workspace $root -Command $zero.Command -ExitCode $zero.ExitCode

        Set-Content -LiteralPath (Join-Path $root 'One.mpr') -Value 'fixture'
        Set-Content -LiteralPath (Join-Path $root 'Two.mpr') -Value 'fixture'
        $multiple = Invoke-PwshFile -FilePath $GenericInstaller -WorkingDirectory $root
        if ($multiple.ExitCode -eq 0) { throw 'Multiple-MPR invocation unexpectedly succeeded.' }
        $multipleTouched = Test-Path -LiteralPath (Join-Path $root '.mxagile')
        if ($multipleTouched) { throw 'Multiple-MPR invocation mutated the project.' }
        Add-TestResult -Name 'MPR safety: multiple' -Status PASS -Reason 'Rejected before installation.' -Workspace $root -Command $multiple.Command -ExitCode $multiple.ExitCode
    }
    catch {
        Add-TestResult -Name 'MPR safety' -Status FAIL -Reason $_.Exception.Message -Workspace $root
    }
    finally {
        if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

function Test-GenericInstallation {
    param([string]$TemplateName, [string]$TestDirName, [string]$Label)
    $workspace = $null
    try {
        $workspace = New-Workcopy -TemplateName $TemplateName -TestDirName $TestDirName
        $sourceFingerprintBefore = Get-TreeFingerprint -Root $RepoRoot
        $first = Invoke-PwshFile -FilePath $GenericInstaller -WorkingDirectory $workspace
        if ($first.ExitCode -ne 0) {
            throw "First install failed with exit code $($first.ExitCode).`nSTDOUT:`n$($first.StdOut)`nSTDERR:`n$($first.StdErr)"
        }

        Assert-Path -Path (Join-Path $workspace '.mxagile') -Description '.mxagile directory'
        if (Test-Path -LiteralPath (Join-Path $workspace '.mxagile/layers/mercedes-benz')) {
            throw 'Generic installation unexpectedly installed the Mercedes layer.'
        }

        $second = Invoke-PwshFile -FilePath $GenericInstaller -WorkingDirectory $workspace
        if ($second.ExitCode -ne 0) {
            throw "Second install failed with exit code $($second.ExitCode).`nSTDOUT:`n$($second.StdOut)`nSTDERR:`n$($second.StdErr)"
        }

        Add-TestResult -Name "$Label generic" -Status PASS -Reason 'First install and idempotent rerun succeeded.' -Workspace $workspace -Command $first.Command -ExitCode $first.ExitCode
        Remove-SuccessWorkspace -Path $workspace
    }
    catch {
        Add-TestResult -Name "$Label generic" -Status FAIL -Reason $_.Exception.Message -Workspace $workspace
    }
}

function Test-MercedesInstallation {
    param([string]$TemplateName, [string]$TestDirName, [string]$Label)
    $workspace = $null
    if ($SkipMercedesIntegration) {
        Add-TestResult -Name "$Label Mercedes" -Status SKIPPED_ENVIRONMENT -Reason 'Skipped by -SkipMercedesIntegration.'
        return
    }
    try {
        $workspace = New-Workcopy -TemplateName $TemplateName -TestDirName $TestDirName
        $first = Invoke-PwshFile -FilePath $MercedesInstaller -WorkingDirectory $workspace
        if ($first.ExitCode -ne 0) {
            throw "First Mercedes install failed with exit code $($first.ExitCode).`nSTDOUT:`n$($first.StdOut)`nSTDERR:`n$($first.StdErr)"
        }

        $layer = Join-Path $workspace '.mxagile/layers/mercedes-benz'
        Assert-Path -Path $layer -Description 'Mercedes layer'
        Assert-Path -Path (Join-Path $layer 'provenance.json') -Description 'Mercedes layer provenance'
        if (Test-Path -LiteralPath (Join-Path $layer '.git')) { throw 'Installed Mercedes layer contains nested .git metadata.' }

        $provenance = Get-Content -LiteralPath (Join-Path $layer 'provenance.json') -Raw | ConvertFrom-Json
        $sourceText = [string]$provenance.source
        if ($sourceText -notlike '*mercedes-benz.ghe.com/DFC-Applikationsentwicklung/MxAgile-CompanyLayer.git*') {
            throw "Unexpected Mercedes provenance source: '$sourceText'"
        }

        $second = Invoke-PwshFile -FilePath $MercedesInstaller -WorkingDirectory $workspace
        if ($second.ExitCode -ne 0) {
            throw "Second Mercedes install failed with exit code $($second.ExitCode).`nSTDOUT:`n$($second.StdOut)`nSTDERR:`n$($second.StdErr)"
        }

        Add-TestResult -Name "$Label Mercedes" -Status PASS -Reason 'External layer install and idempotent rerun succeeded; no nested .git.' -Workspace $workspace -Command $first.Command -ExitCode $first.ExitCode
        Remove-SuccessWorkspace -Path $workspace
    }
    catch {
        $message = $_.Exception.Message
        $environmentPattern = '(?i)(authentication|credential|could not resolve host|network|unable to access|repository not found|ssl|tls|proxy)'
        if ($message -match $environmentPattern) {
            Add-TestResult -Name "$Label Mercedes" -Status SKIPPED_ENVIRONMENT -Reason $message -Workspace $workspace
        }
        else {
            Add-TestResult -Name "$Label Mercedes" -Status FAIL -Reason $message -Workspace $workspace
        }
    }
}

function Test-MercedesRemoteFailure {
    $name = 'Mercedes remote failure'
    $workspace = $null
    try {
        $workspace = New-Workcopy -TemplateName $GreenfieldTemplate -TestDirName 'remote-failure'
        $invalidUrl = 'https://invalid.invalid/MxAgile-CompanyLayer.git'
        $result = Invoke-PwshFile -FilePath $MercedesInstaller `
            -Arguments @('-MercedesGitUrl', $invalidUrl) `
            -WorkingDirectory $workspace

        if ($result.ExitCode -eq 0) { throw 'Mercedes installer returned success for an invalid layer URL.' }
        if ($result.StdOut -match '(?i)Mercedes-Benz installation complete') {
            throw 'Mercedes installer printed a false success message after layer failure.'
        }
        $localLayer = Join-Path $workspace '.mxagile/layers/mercedes-benz'
        if (Test-Path -LiteralPath $localLayer) {
            throw 'Mercedes layer exists after failed remote retrieval; possible fallback or partial-state issue.'
        }
        Add-TestResult -Name $name -Status PASS -Reason 'Invalid remote failed non-zero without false success or local fallback.' -Workspace $workspace -Command $result.Command -ExitCode $result.ExitCode
        Remove-SuccessWorkspace -Path $workspace
    }
    catch {
        Add-TestResult -Name $name -Status FAIL -Reason $_.Exception.Message -Workspace $workspace
    }
}

function Test-NoRuntimeLocalLayerDependency {
    $name = 'No local company-layers runtime dependency'
    try {
        $files = @($GenericInstaller, $MercedesInstaller, (Join-Path $RepoRoot 'scripts/fetch-layer.ps1')) |
        Where-Object { Test-Path -LiteralPath $_ }
        $hits = foreach ($file in $files) {
            $matches = Select-String -LiteralPath $file -Pattern 'company-layers[\\/]' -SimpleMatch:$false
            foreach ($match in $matches) {
                "{0}:{1}: {2}" -f $file, $match.LineNumber, $match.Line.Trim()
            }        
        }
        if (@($hits).Count) { throw "Runtime references found:`n$($hits -join "`n")" }
        Add-TestResult -Name $name -Status PASS -Reason 'No runtime installer references found.'
    }
    catch {
        Add-TestResult -Name $name -Status FAIL -Reason $_.Exception.Message
    }
}



Write-Host '=== MxAgile Installer Test Suite ===' -ForegroundColor Cyan
Write-Host "Repository: $RepoRoot"
Write-Host "PowerShell: $(& $Pwsh --version)"
Write-Host ''

foreach ($required in @($WorkcopyScript, $GenericInstaller, $MercedesInstaller)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        Add-TestResult -Name 'Suite preflight' -Status FAIL -Reason "Required file not found: $required"
    }
}

if (-not ($Results | Where-Object { $_.Status -eq 'FAIL' })) {
    Write-Host "`n---> Starting Test: PowerShellParser" -ForegroundColor Cyan
    Test-PowerShellParser
    Write-Host "`n---> Starting Test: MprSafety" -ForegroundColor Cyan
    Test-MprSafety
    Write-Host "`n---> Starting Test: NoRuntimeLocalLayerDependency" -ForegroundColor Cyan
    Test-NoRuntimeLocalLayerDependency
    Write-Host "`n---> Starting Test: Greenfield generic" -ForegroundColor Cyan
    Test-GenericInstallation -TemplateName $GreenfieldTemplate -TestDirName 'greenfield-generic' -Label 'Greenfield'
    Write-Host "`n---> Starting Test: Greenfield Mercedes" -ForegroundColor Cyan
    Test-MercedesInstallation -TemplateName $GreenfieldTemplate -TestDirName 'greenfield-mercedes' -Label 'Greenfield'
    Write-Host "`n---> Starting Test: MercedesRemoteFailure" -ForegroundColor Cyan
    Test-MercedesRemoteFailure

    $brownfieldTemplates = Get-ChildItem -Path $ProjectTemplatesRoot -Directory | Where-Object { $_.Name -like 'brownfield*' }

    if ($brownfieldTemplates.Count -eq 0) {
        Add-TestResult -Name 'Brownfield templates' -Status SKIPPED_ENVIRONMENT -Reason 'No brownfield* templates found in project-templates'
    }
    else {
        foreach ($template in $brownfieldTemplates) {
            $templateName = $template.Name
            # Create a label like "Brownfield (spec)" from "brownfield_spec"
            $labelSuffix = ($templateName -replace '^brownfield_?', '')
            $label = "Brownfield ($labelSuffix)"
            Write-Host "`n---> Starting Test: $($label) generic" -ForegroundColor Cyan
            Test-GenericInstallation -TemplateName $templateName -TestDirName "$templateName-generic" -Label $label
            Write-Host "`n---> Starting Test: $($label) Mercedes" -ForegroundColor Cyan
            Test-MercedesInstallation -TemplateName $templateName -TestDirName "$templateName-mercedes" -Label $label
        }
    }
}

$pass = @($Results | Where-Object Status -eq 'PASS').Count
$fail = @($Results | Where-Object Status -eq 'FAIL').Count
$skip = @($Results | Where-Object Status -eq 'SKIPPED_ENVIRONMENT').Count

Write-Host ''
Write-Host '-------------------------------------'
Write-Host "PASS:                $pass" -ForegroundColor Green
Write-Host "FAIL:                $fail" -ForegroundColor $(if ($fail) { 'Red' } else { 'Green' })
Write-Host "SKIPPED_ENVIRONMENT: $skip" -ForegroundColor Yellow
Write-Host '-------------------------------------'

if ($fail -gt 0) {
    Write-Host 'RESULT: FAIL' -ForegroundColor Red
    Write-Host ''
    Write-Host 'Failed workspaces were retained for diagnosis.'
    foreach ($item in $Results | Where-Object Status -eq 'FAIL') {
        Write-Host "`nFAIL: $($item.Name)" -ForegroundColor Red
        if ($item.Workspace) { Write-Host "Workspace: $($item.Workspace)" }
        if ($item.Command) { Write-Host "Command: $($item.Command)" }
        if ($null -ne $item.ExitCode) { Write-Host "Exit code: $($item.ExitCode)" }
        Write-Host "Reason: $($item.Reason)"
        if ($item.StdOut) { Write-Host "STDOUT:`n$($item.StdOut)" }
        if ($item.StdErr) { Write-Host "STDERR:`n$($item.StdErr)" }
    }
    exit 1
}

if ($skip -gt 0) {
    Write-Host 'RESULT: PASS WITH ENVIRONMENT SKIPS' -ForegroundColor Yellow
    exit 0
}

Write-Host 'RESULT: PASS' -ForegroundColor Green
exit 0
