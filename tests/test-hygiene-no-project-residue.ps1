<#
.SYNOPSIS
    Tier 0: Generic-repository hygiene guard (no project/customer residue).

.DESCRIPTION
    The distributable MxAgile Framework must not contain identifiers of reality-test
    projects, customers, or machine-specific locations in any tracked file or file name.

    The check is deliberately a deterministic forbidden-identifier list, NOT naive
    substring matching: generic words that merely contain "cap" (capability, escape, ...)
    are never flagged. The identifiers are assembled from fragments so that this file
    itself stays free of them.

    Allow-list: negative guard tests that must name the forbidden identifiers in order to
    assert their absence elsewhere. The allow-list is explicit; extend it only for such
    guards, never for product content.
#>

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$RepoRoot = Split-Path -Parent $PSScriptRoot
$Pass = 0; $Fail = 0; $Details = @()
function Assert-True([string]$Name, [bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS: $Name" -ForegroundColor Green; $script:Pass++ }
    else { Write-Host "  FAIL: $Name -- $Msg" -ForegroundColor Red; $script:Fail++; $script:Details += "[$Name] $Msg" }
}

# Identifier fragments (joined at runtime; never written as literals in this file).
$forbidden = [ordered]@{
    'reference-project-name' = ('Cap' + 'Track')
    'customer-name'          = ('Merce' + 'des')
    'customer-internal-host' = ('ghe' + '\.com')
    'local-project-path'     = ('MTC' + '\+Mendix\+Projekte')
    'local-benchmark-path'   = ('MxAgile' + 'BoardBench')
    'local-user-name'        = ('GBA' + 'NEMA')
}
$rx = @{}
foreach ($k in $forbidden.Keys) { $rx[$k] = [regex]::new($forbidden[$k], 'IgnoreCase') }

# Negative guards that legitimately name customer/project identifiers to assert their absence.
$allow = @(
    'products/MxMocketeer/tests/test-mocketeer-validation.ps1',
    'tests/test-architecture-drift-prevention.ps1',
    'tests/test-board-authority.ps1',
    'tests/test-core-regression.ps1',
    'tests/test-legacy-completion-reconciliation.ps1',
    'tests/test-mission-completion.ps1',
    'tests/test-orientation.ps1',
    'tests/test-project-release-checkpoint.ps1',
    'tests/test-revision-lifecycle.ps1',
    'tests/test-role-access-semantics.ps1',
    'tests/test-wp2-lifecycle-extensions.ps1'
)

Push-Location $RepoRoot
try { $files = @(& git ls-files) } finally { Pop-Location }
Assert-True 'git ls-files returns the tracked tree' ($files.Count -gt 100) "only $($files.Count) tracked files"

$hits = New-Object System.Collections.Generic.List[string]
foreach ($f in $files) {
    foreach ($k in $rx.Keys) { if ($rx[$k].IsMatch($f)) { $hits.Add("[$k] file name: $f") } }
    if ($allow -contains $f) { continue }
    $full = Join-Path $RepoRoot $f
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { continue }
    $bytes = [System.IO.File]::ReadAllBytes($full)
    if ([Array]::IndexOf($bytes, [byte]0) -ge 0) { continue }
    $text = [System.Text.Encoding]::UTF8.GetString($bytes)
    foreach ($k in $rx.Keys) {
        $m = $rx[$k].Match($text)
        if ($m.Success) { $hits.Add("[$k] $f (offset $($m.Index))") }
    }
}
Assert-True 'no project/customer/machine-specific identifiers in tracked tree' ($hits.Count -eq 0) ("`n    " + (($hits | Select-Object -First 25) -join "`n    "))

foreach ($a in $allow) {
    Assert-True "allow-list entry exists: $a" ($files -contains $a) 'stale allow-list entry (file no longer tracked)'
}

# Lexical false positives must never be flagged: the guard is not a bare 'cap' substring match.
Assert-True 'generic word "capability" is not a forbidden identifier' (-not ($rx.Values | Where-Object { $_.IsMatch('capability escape capture') })) 'guard matches generic cap* words'

Write-Host ""
Write-Host "Passed: $Pass  Failed: $Fail"
if ($Fail -gt 0) { $Details | ForEach-Object { Write-Host $_ -ForegroundColor Red }; exit 1 }
exit 0
