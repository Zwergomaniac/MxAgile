#Requires -Version 7
# MxAgile Core Provenance Contract — Tier 0 static validation
# Validates that the installer chain correctly writes Core installation identity,
# that the setup scripts resolve commit SHA, that system-check covers Core identity
# and currency, and that the update-contract policy is present and complete.
# Run from repository root:  pwsh tests/test-core-provenance.ps1

param(
    [string]$RepoRoot = (Get-Location).Path
)

$RepoRoot = (Resolve-Path $RepoRoot).Path
$ErrorActionPreference = 'Stop'
$pass = 0; $fail = 0

function Assert {
    param([bool]$Condition, [string]$Label, [string]$Detail = '')
    if ($Condition) {
        Write-Host "  PASS  $Label" -ForegroundColor Green
        $script:pass++
    } else {
        $msg = if ($Detail) { "  FAIL  $Label — $Detail" } else { "  FAIL  $Label" }
        Write-Host $msg -ForegroundColor Red
        $script:fail++
    }
}

function Assert-FileContains {
    param([string]$File, [string]$Pattern, [string]$Label)
    $path = Join-Path $RepoRoot $File
    if (-not (Test-Path $path)) {
        Write-Host "  FAIL  $Label — file not found: $File" -ForegroundColor Red
        $script:fail++
        return
    }
    $content = Get-Content $path -Raw -Encoding UTF8
    Assert ($content -match $Pattern) $Label "pattern: $Pattern"
}

Write-Host "`nCore Provenance Contract — $RepoRoot" -ForegroundColor Cyan

# ──────────────────────────────────────────────────────────────
# A  install-core.ps1: accepts ProvenanceCoreCommit and writes provenance
# ──────────────────────────────────────────────────────────────
Write-Host "`n[A] install-core.ps1: Core identity contract"
$ic = Get-Content (Join-Path $RepoRoot 'scripts\install-core.ps1') -Raw -Encoding UTF8
Assert ($ic -match 'ProvenanceCoreCommit') 'A1: accepts ProvenanceCoreCommit parameter'
Assert ($ic -match 'core-provenance\.json') 'A2: writes core-provenance.json'
Assert ($ic -match 'schema_version') 'A3: provenance has schema_version field'
Assert ($ic -match 'install_mode') 'A4: provenance has install_mode field (install vs update)'
Assert ($ic -match 'previous_commit') 'A5: provenance tracks previous_commit on update'
Assert ($ic -match 'distribution_owned') 'A6: provenance declares distribution_owned scripts'
Assert ($ic -match 'canonical_url') 'A7: provenance records canonical_url for update discovery'
Assert ($ic -match 'update_entry_point') 'A8: provenance records update_entry_point'
Assert ($ic -match 'consumer_note') 'A9: provenance carries consumer_note about absent scripts'
Assert ($ic -match "CoreCommit.*CoreVersion|CoreVersion.*CoreCommit") 'A10: passes CoreCommit and CoreVersion to setup-agent-system'
Assert ($ic -match 'IsNullOrWhiteSpace.*ProvenanceCoreCommit|ProvenanceCoreCommit.*IsNullOrWhiteSpace') 'A11: self-resolves commit when caller did not provide it'
Assert ($ic -match 'Split-Path.*PSScriptRoot.*Parent|PSScriptRoot.*Parent') 'A12: self-resolution uses PSScriptRoot parent as distribution root'

# ──────────────────────────────────────────────────────────────
# B  mxagile-setup.ps1: resolves commit SHA and passes it through
# ──────────────────────────────────────────────────────────────
Write-Host "`n[B] mxagile-setup.ps1: commit resolution"
$setup = Get-Content (Join-Path $RepoRoot 'mxagile-setup.ps1') -Raw -Encoding UTF8
Assert ($setup -match 'rev-parse HEAD') 'B1: resolves commit SHA via git rev-parse HEAD'
Assert ($setup -match 'provenanceCoreCommit') 'B2: stores resolved commit in provenanceCoreCommit'
Assert ($setup -match 'a-f0-9.*40|40.*a-f0-9') 'B3: validates SHA is 40-char hex before accepting'
Assert ($setup -match 'ProvenanceCoreCommit.*provenanceCoreCommit') 'B4: passes ProvenanceCoreCommit to install-core.ps1'
Assert ($setup -match 'Commit hash is the primary currency signal|primary currency') 'B5: comment explains commit as primary currency signal'

# ──────────────────────────────────────────────────────────────
# C  mxagile-setup-mercedes.ps1: same commit resolution, both call sites
# ──────────────────────────────────────────────────────────────
Write-Host "`n[C] mxagile-setup-mercedes.ps1: commit resolution"
$merc = Get-Content (Join-Path $RepoRoot 'mxagile-setup-mercedes.ps1') -Raw -Encoding UTF8
Assert ($merc -match 'rev-parse HEAD') 'C1: resolves commit SHA'
Assert ($merc -match 'provenanceCoreCommit') 'C2: stores resolved commit'
Assert (([regex]::Matches($merc, 'ProvenanceCoreCommit')).Count -ge 2) 'C3: ProvenanceCoreCommit passed at both call sites'

# ──────────────────────────────────────────────────────────────
# D  setup-agent-system.ps1 and generate-mxagile-platform-skills.ps1: projections manifest
# ──────────────────────────────────────────────────────────────
Write-Host "`n[D] Projections manifest chain"
$sas = Get-Content (Join-Path $RepoRoot 'scripts\setup-agent-system.ps1') -Raw -Encoding UTF8
Assert ($sas -match 'CoreCommit') 'D1: setup-agent-system accepts CoreCommit param'
Assert ($sas -match 'CoreVersion') 'D2: setup-agent-system accepts CoreVersion param'
Assert ($sas -match 'CoreCommit.*CoreCommit|CoreVersion.*CoreVersion') 'D3: forwards CoreCommit/CoreVersion to generator'

$gen = Get-Content (Join-Path $RepoRoot 'scripts\generate-mxagile-platform-skills.ps1') -Raw -Encoding UTF8
Assert ($gen -match 'CoreCommit') 'D4: generator accepts CoreCommit param'
Assert ($gen -match 'CoreVersion') 'D5: generator accepts CoreVersion param'
Assert ($gen -match 'projections-manifest\.json') 'D6: generator writes projections-manifest.json'
Assert ($gen -match 'generated_from_core_commit') 'D7: manifest records generated_from_core_commit'
Assert ($gen -match 'generator_owned_by') 'D8: manifest declares generator_owned_by distribution'

# ──────────────────────────────────────────────────────────────
# E  system-check.md: Core identity and currency sections
# ──────────────────────────────────────────────────────────────
Write-Host "`n[E] system-check.md: Core identity and currency"
$sc = Get-Content (Join-Path $RepoRoot '.mxagile\skills\system-check.md') -Raw -Encoding UTF8
Assert ($sc -match '## J\. Core Installation Identity') 'E1: has Section J: Core Installation Identity'
Assert ($sc -match '## K\. Core Currency') 'E2: has Section K: Core Currency'
Assert ($sc -match 'core-provenance\.json') 'E3: references core-provenance.json'
Assert ($sc -match 'PROVENANCE_INCOMPLETE') 'E4: defines PROVENANCE_INCOMPLETE status'
Assert ($sc -match 'distribution_owned') 'E5: addresses distribution_owned scripts'
Assert ($sc -match 'distribution-owned.*defect|missing.*distribution-owned.*defect|distribution-owned.*consumer defect') 'E6: states absent distribution-owned script is not a defect'
Assert ($sc -match 'No-filesystem-guessing|no.filesystem.guessing|Do not search.*filesystem') 'E7: has no-filesystem-guessing invariant'
Assert ($sc -match 'git ls-remote') 'E8: uses git ls-remote for currency check (no clone)'
Assert ($sc -match 'SOURCE_UNAVAILABLE') 'E9: defines SOURCE_UNAVAILABLE for offline scenarios'
Assert ($sc -match 'do NOT claim CURRENT|Do NOT claim CURRENT') 'E10: offline rule — do not claim CURRENT without verification'
Assert ($sc -match 'UPDATE_AVAILABLE') 'E11: defines UPDATE_AVAILABLE status'
Assert ($sc -match 'projections.manifest\.json|projections_currency') 'E12: checks projections-manifest.json'
Assert ($sc -match 'STALE') 'E13: reports STALE when projections not regenerated'
Assert ($sc -match 'core_installation:') 'E14: machine-readable YAML has core_installation block'
Assert ($sc -match 'core_currency:') 'E15: machine-readable YAML has core_currency block'
Assert ($sc -match 'null.*never.*CURRENT|never.*CURRENT.*null|null.*not.*CURRENT|COMMIT_UNKNOWN') 'E16: null commit is never classified as CURRENT'
Assert ($sc -match 'null.*null.*not.*match|null.*not.*prove.*currency|null.*do not prove|null values do not prove') 'E17: null == null is not proof of projection currency'

# ──────────────────────────────────────────────────────────────
# F  update-contract.md policy: complete and correct
# ──────────────────────────────────────────────────────────────
Write-Host "`n[F] update-contract.md policy"
$uc = if (Test-Path (Join-Path $RepoRoot '.mxagile\policies\update-contract.md')) {
    Get-Content (Join-Path $RepoRoot '.mxagile\policies\update-contract.md') -Raw -Encoding UTF8
} else { '' }
Assert ($uc.Length -gt 0) 'F1: update-contract.md exists'
Assert ($uc -match 'Commit Hash Is the Primary Currency Signal|primary currency') 'F2: states commit hash is primary currency signal'
Assert ($uc -match 'No-Filesystem-Guessing Invariant|No.Filesystem.Guessing') 'F3: has no-filesystem-guessing invariant section'
Assert ($uc -match 'distribution.owned|Distribution.*Owned|distribution_owned') 'F4: defines distribution-owned scripts'
Assert ($uc -match 'consumer.owned|Consumer.Owned') 'F5: defines consumer-owned artifacts'
Assert ($uc -match 'Update Discovery|update.*discovery') 'F6: has update discovery section'
Assert ($uc -match 'Offline.*Behavior|offline.*behavior|SOURCE_UNAVAILABLE') 'F7: defines offline behavior'
Assert ($uc -match 'Projections Currency|projections.currency') 'F8: covers projections currency'
Assert ($uc -match 'Content Fingerprint|content.*fingerprint') 'F9: documents content fingerprint architectural decision'
Assert ($uc -match 'schema_version.*"1"') 'F10: provenance schema_version documented'
Assert ($uc -match 'install_mode') 'F11: install_mode field documented'
Assert ($uc -match 'previous_commit') 'F12: previous_commit field documented'
Assert ($uc -match 'null.*null.*not.*proof|null.*null.*not.*match|null.*never.*CURRENT|null.*PROVENANCE_INCOMPLETE|null.*UNVERIFIED') 'F13: null semantics documented — null is not CURRENT'

# ──────────────────────────────────────────────────────────────
# Summary
# ──────────────────────────────────────────────────────────────
Write-Host "`n========================================"
if ($fail -eq 0) {
    Write-Host "  PASS: $pass   FAIL: $fail — all checks passed" -ForegroundColor Green
} else {
    Write-Host "  PASS: $pass   FAIL: $fail — validation failed" -ForegroundColor Red
}
Write-Host "========================================`n"

exit ($fail -gt 0 ? 1 : 0)
