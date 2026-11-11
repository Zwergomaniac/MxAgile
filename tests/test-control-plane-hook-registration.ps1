[CmdletBinding()]
param()

# Phase 1C: structured, ownership-safe registration of the control-plane PreToolUse hook.
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$register = Join-Path $repoRoot 'scripts/Register-MxAgileControlPlaneHook.ps1'
$marker = '.mxagile/tools/control-plane/enforcement.py'
$failures = 0
$checks = 0

function Assert-True {
    param([bool]$Condition, [string]$Message)
    $script:checks++
    if ($Condition) { Write-Host "PASS: $Message" } else { Write-Host "FAIL: $Message"; $script:failures++ }
}

function Invoke-Register {
    param([string]$Path, [switch]$Remove)
    $arguments = @('-NoProfile', '-File', $register, '-SettingsPath', $Path)
    if ($Remove) { $arguments += '-Remove' }
    $output = & pwsh @arguments
    [pscustomobject]@{ Exit = $LASTEXITCODE; Result = (($output | Select-Object -Last 1) | ConvertFrom-Json) }
}

function Get-Groups {
    param([string]$Path)
    @((Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json).hooks.PreToolUse)
}

function Test-Owned { param([object]$Group) @($Group.hooks | Where-Object { ([string]$_.command).Contains($marker) }).Count -gt 0 }

$root = Join-Path ([System.IO.Path]::GetTempPath()) "mxagile-hook-reg-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $root | Out-Null
try {
    # Fresh registration creates the file with exactly one MxAgile group.
    $fresh = Join-Path $root 'fresh/.claude/settings.json'
    $run = Invoke-Register $fresh
    Assert-True ($run.Exit -eq 0 -and $run.Result.status -eq 'REGISTERED') 'fresh settings: REGISTERED'
    $groups = Get-Groups $fresh
    Assert-True ($groups.Count -eq 1 -and (Test-Owned $groups[0])) 'fresh settings: single MxAgile group'
    Assert-True ($groups[0].hooks[0].command.Contains('|| exit 2')) 'adapter command fails closed (exit 2)'
    $run = Invoke-Register $fresh
    Assert-True ($run.Result.status -eq 'CURRENT' -and $run.Result.detail -eq 'unchanged') 'rerun is idempotent (CURRENT, unchanged)'
    Assert-True ((Get-Groups $fresh).Count -eq 1) 'rerun creates no duplicate'

    # Foreign hooks and unrelated settings are preserved; MxAgile group is placed first.
    $foreignPath = Join-Path $root 'foreign/.claude/settings.json'
    New-Item -ItemType Directory -Path (Split-Path -Parent $foreignPath) -Force | Out-Null
    $foreignJson = '{"permissions":{"allow":["Bash(git status)"]},"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"foreign-check"}]}],"PostToolUse":[{"matcher":"Write","hooks":[{"type":"command","command":"post"}]}]}}'
    Set-Content -LiteralPath $foreignPath -Value $foreignJson -NoNewline
    $run = Invoke-Register $foreignPath
    $settings = Get-Content -LiteralPath $foreignPath -Raw | ConvertFrom-Json
    $groups = @($settings.hooks.PreToolUse)
    Assert-True ($run.Result.status -eq 'REGISTERED') 'foreign hooks: REGISTERED'
    Assert-True ($groups.Count -eq 2 -and (Test-Owned $groups[0]) -and $groups[1].hooks[0].command -eq 'foreign-check') 'MxAgile first, foreign group preserved'
    Assert-True ($settings.permissions.allow[0] -eq 'Bash(git status)' -and $settings.hooks.PostToolUse[0].hooks[0].command -eq 'post') 'unrelated settings preserved'

    # An outdated MxAgile entry in a later position is replaced and moved first.
    $stalePath = Join-Path $root 'stale/.claude/settings.json'
    New-Item -ItemType Directory -Path (Split-Path -Parent $stalePath) -Force | Out-Null
    Set-Content -LiteralPath $stalePath -NoNewline -Value ('{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"foreign-check"}]},{"matcher":"Write","hooks":[{"type":"command","command":"python ' + $marker + '"}]}]}}')
    $run = Invoke-Register $stalePath
    $groups = Get-Groups $stalePath
    Assert-True ($run.Result.status -eq 'UPDATED') 'outdated MxAgile entry: UPDATED'
    Assert-True ($groups.Count -eq 2 -and (Test-Owned $groups[0]) -and -not (Test-Owned $groups[1]) -and $groups[0].matcher.Contains('mcp__')) 'outdated entry replaced, not duplicated, moved first'

    # Unknown ownership: file stays byte-identical, exit 3.
    $unknownCases = [ordered]@{
        'invalid JSON' = '{"hooks": '
        'mixed group' = ('{"hooks":{"PreToolUse":[{"matcher":"*","hooks":[{"type":"command","command":"python ' + $marker + '"},{"type":"command","command":"foreign"}]}]}}')
        'PreToolUse not array' = '{"hooks":{"PreToolUse":{"matcher":"*"}}}'
    }
    foreach ($case in $unknownCases.GetEnumerator()) {
        $path = Join-Path $root "unknown-$([guid]::NewGuid().ToString('N'))/settings.json"
        New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
        Set-Content -LiteralPath $path -Value $case.Value -NoNewline
        $run = Invoke-Register $path
        Assert-True ($run.Exit -eq 3 -and $run.Result.status -eq 'UNKNOWN_OWNERSHIP') "$($case.Key): UNKNOWN_OWNERSHIP (exit 3)"
        Assert-True ((Get-Content -LiteralPath $path -Raw) -ceq $case.Value) "$($case.Key): file not modified"
    }

    # Removal drops only the MxAgile group.
    $run = Invoke-Register $foreignPath -Remove
    $groups = Get-Groups $foreignPath
    Assert-True ($run.Result.status -eq 'REMOVED' -and $groups.Count -eq 1 -and -not (Test-Owned $groups[0])) 'remove keeps foreign group only'
    $run = Invoke-Register $foreignPath -Remove
    Assert-True ($run.Result.status -eq 'NOT_REGISTERED') 'second remove: NOT_REGISTERED'
} finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "Checks: $checks, Failures: $failures"
if ($failures -gt 0) { exit 1 }
exit 0
