#Requires -Version 7
# CapTrack Regression Tests — Tier 0 static fixture validation
# Validates CapTrack-specific business rules against canonical framework policies
# using fixture files in tests/fixtures/captrack/.
#
# CapTrack is used ONLY as a regression/reality fixture.
# This test does NOT modify CapTrack application logic or its Rev5 working state.
#
# Run from repository root:  pwsh tests/test-captrack-regression.ps1

param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
)

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

function ReadFile { param([string]$Path)
    if (Test-Path -LiteralPath $Path) { [string](Get-Content -LiteralPath $Path -Raw -Encoding UTF8) }
    else { '' }
}

function ReadYAML { param([string]$Path)
    if (Test-Path -LiteralPath $Path) { [string](Get-Content -LiteralPath $Path -Raw -Encoding UTF8) }
    else { '' }
}

$FixtureDir = Join-Path $RepoRoot 'tests/fixtures/captrack'
Write-Host "`nCapTrack Regression Tests — $RepoRoot" -ForegroundColor Cyan

# ──────────────────────────────────────────────────────────────
# [1] Fixture files exist
# ──────────────────────────────────────────────────────────────
Write-Host "`n[1] CapTrack fixture files exist"
$fixtures = @(
    'tests/fixtures/captrack/platform-boundaries.yaml',
    'tests/fixtures/captrack/role-coverage.yaml',
    'tests/fixtures/captrack/gap-records.yaml',
    'tests/fixtures/captrack/revision-lifecycle.yaml'
)
foreach ($f in $fixtures) {
    Assert (Test-Path (Join-Path $RepoRoot $f)) "Fixture exists: $f"
}

# ──────────────────────────────────────────────────────────────
# [2] Platform boundary fixture: MB_SSO correctly classified
# ──────────────────────────────────────────────────────────────
Write-Host "`n[2] Platform boundary: MB_SSO classification"
$pb = ReadYAML (Join-Path $FixtureDir 'platform-boundaries.yaml')
Assert ($pb -match 'PLATFORM-MB-SSO') 'fixture defines PLATFORM-MB-SSO boundary'
Assert ($pb -match 'MB_SSO') 'fixture names MB_SSO provider'
Assert ($pb -match 'EXCLUDE_FROM_UI_PARITY') 'MB_SSO boundary excludes UI parity'
Assert ($pb -match 'DO_NOT_MODIFY') 'MB_SSO boundary is DO_NOT_MODIFY'
Assert ($pb -match 'SCREEN-LOGIN') 'login screen is excluded'
Assert ($pb -match 'SCREEN-DEMO-ROLE-SWITCHER') 'demo role switcher is excluded'
Assert ($pb -match 'test-only mechanism') 'demo role switcher documented as test-only'
Assert ($pb -match 'NOT productive login|not productive login') 'demo role switcher is not productive login'
Assert ($pb -match 'NOT user.facing|not user-facing') 'Nutzerverwaltung not user-facing confirmed'

# Business rule: login/password screens are NOT fachliche requirements
Assert ($pb -match 'NOT fachliche|not fachliche') 'login explicitly marked NOT fachliche CapTrack requirement'
Assert ($pb -match 'REQ-NNN.*MUST NOT|must not.*REQ-NNN') 'excluded screens must not generate REQ-NNN'

# ──────────────────────────────────────────────────────────────
# [3] Role coverage fixture: all 9 mandatory CapTrack roles present
# ──────────────────────────────────────────────────────────────
Write-Host "`n[3] Role coverage: all 9 mandatory CapTrack roles"
$rc = ReadYAML (Join-Path $FixtureDir 'role-coverage.yaml')
$mandatoryRoles = @(
    'AppAdmin',
    'E2',
    'Center Koordinator',
    'CeKo Vertreter',
    'E3 Eintragung',
    'E3 Eintragung Vertreter',
    'E3 [Üü]berpr[üu]fung',
    'E4 Eintragung',
    'E4 [Üü]berpr[üu]fung'
)
foreach ($role in $mandatoryRoles) {
    Assert ($rc -match $role) "Mandatory role present: $role"
}

# Scope assertions
Assert ($rc -match 'required_scope: app') 'AppAdmin has app scope'
Assert ($rc -match 'required_scope: center') 'E2/CeKo roles have center scope'
Assert ($rc -match 'required_scope: abteilung') 'E3 roles have abteilung scope'
Assert ($rc -match 'required_scope: team') 'E4 roles have team scope'

# E4 COVERAGE_GAP is the known regression signal
Assert ($rc -match 'COVERAGE_GAP') 'fixture documents E4 COVERAGE_GAP'
Assert ($rc -match 'ROLE-E4-EINTRAGUNG') 'E4 Eintragung in fixture'
Assert ($rc -match 'ROLE_GAP.*not.*infrastructure|ROLE_GAP, not an infrastructure gap') 'E4 gap is ROLE_GAP not infrastructure gap'
Assert ($rc -match 'overall_status: COVERAGE_GAP') 'overall status is COVERAGE_GAP when E4 missing'

# Security: no production credentials or personal data
Assert ($rc -notmatch '@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}') 'no email addresses in role fixture'
Assert ($rc -notmatch 'password|passwort|secret|token') 'no credentials in role fixture'

# ──────────────────────────────────────────────────────────────
# [4] GAP records fixture: classification and routing rules
# ──────────────────────────────────────────────────────────────
Write-Host "`n[4] GAP records: classification and routing rules"
$gaps = ReadYAML (Join-Path $FixtureDir 'gap-records.yaml')
Assert ($gaps -match 'GAP-CAPTRACK-ABTEILUNG-EXPAND') 'expandable_area gap present'
Assert ($gaps -match 'GAP-CAPTRACK-E4-ROLE') 'E4 role gap present'
Assert ($gaps -match 'GAP-CAPTRACK-PLATFORM-LOGIN') 'platform boundary login gap present'

# Critical classification rules
Assert ($gaps -match 'NOT.*REQ-NNN|does NOT create new REQ-NNN') 'INTERACTION_GAP does not create REQ-NNN'
Assert ($gaps -match 'NOT.*Mockup Refinement|not route to Mockup Refinement') 'ROLE_GAP does not route to Mockup Refinement'
Assert ($gaps -match 'REMOVE.*not.*ALIGN|repair is REMOVE not ALIGN') 'PLATFORM_BOUNDARY_GAP repair is REMOVE'
Assert ($gaps -match 'technical.*repair.*NOT.*fachliche|purely technical.*not.*Decision') 'technical repair not fachliche decision'

# CapTrack expandable area business rule
Assert ($gaps -match 'Abteilungsbereiche|Abteilung section') 'Gesamtübersicht Abteilungsbereiche gap documented'
Assert ($gaps -match 'EFF-ABTEILUNG-EXPAND') 'specific expand effect referenced'
Assert ($gaps -match 'EFF-ABTEILUNG-COLLAPSE') 'specific collapse effect referenced'

# Security: no production data or credentials
Assert ($gaps -notmatch 'password|passwort|token|secret') 'no credentials in gap fixture'

# ──────────────────────────────────────────────────────────────
# [5] Revision lifecycle fixture: invariants
# ──────────────────────────────────────────────────────────────
Write-Host "`n[5] Revision lifecycle invariants"
$rl = ReadYAML (Join-Path $FixtureDir 'revision-lifecycle.yaml')
Assert ($rl -match 'REV-001') 'REV-001 source revision present'
Assert ($rl -match 'REV-002') 'REV-002 refined target revision present'
Assert ($rl -match 'lifecycle_status: SOURCE') 'REV-001 is SOURCE'
Assert ($rl -match 'lifecycle_status: REFINED_TARGET') 'REV-002 is REFINED_TARGET'

# Active target invariant: only one active_target: true
$activeTrueCount = ([regex]::Matches($rl, 'active_target: true')).Count
$activeFalseCount = ([regex]::Matches($rl, 'active_target: false')).Count
Assert ($activeTrueCount -eq 1) "Exactly one active_target: true ($activeTrueCount found)"
Assert ($activeFalseCount -ge 1) "At least one active_target: false ($activeFalseCount found)"

# Role preservation across revisions
Assert ($rl -match 'ROLE-E4-EINTRAGUNG') 'E4 Eintragung preserved in revision'
Assert ($rl -match 'ROLE-E4-UEBERPRUEFUNG') 'E4 Überprüfung preserved in revision'
Assert ($rl -match 'All 9 fachliche roles preserved') 'all 9 roles preserved statement'
Assert ($rl -match 'SCREEN-LOGIN.*expected_superseded|expected_superseded.*SCREEN-LOGIN') 'SCREEN-LOGIN is expected_superseded, not unexpected_missing'

# Effects do not derive pages
Assert ($rl -match 'derived_page: false') 'platform boundary effects have derived_page: false'
Assert ($rl -match 'PLATFORM_BOUNDARY.*REQ-NNN|does NOT create fachliche REQ-NNN') 'platform boundary effect does not create REQ-NNN'

# ──────────────────────────────────────────────────────────────
# [6] Framework policy alignment: CapTrack rules match canonical policy
# ──────────────────────────────────────────────────────────────
Write-Host "`n[6] Framework policy alignment"
$gapPolicy = ReadFile (Join-Path $RepoRoot '.mxagile/policies/gap-verification-repair.md')
$mlPolicy  = ReadFile (Join-Path $RepoRoot '.mxagile/policies/mockup-lifecycle.md')

# GAP policy covers the CapTrack expandable area pattern
Assert ($gapPolicy -match 'expandable_area|expand.*collapse') 'gap policy covers expandable_area interactions'
Assert ($gapPolicy -match 'E3.*E4|E4.*E3|Center.*scope|Abteilung.*scope|Team.*scope|Center.*context|Abteilung.*context|Team.*context') 'gap policy references CapTrack scoped roles'

# Mockup lifecycle policy covers the MB_SSO boundary
Assert ($mlPolicy -match 'MB_SSO') 'lifecycle policy explicitly names MB_SSO'
Assert ($mlPolicy -match '[Ll]ogin.*platform_boundary|platform_boundary.*login') 'lifecycle policy marks login as platform_boundary'

# ──────────────────────────────────────────────────────────────
# [7] Security: no production data in any CapTrack fixture
# ──────────────────────────────────────────────────────────────
Write-Host "`n[7] Security: no sensitive data in fixtures"
$allFixtures = Get-ChildItem -LiteralPath $FixtureDir -File | ForEach-Object { [string](Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8) }
$allContent = $allFixtures -join "`n"
Assert ($allContent -notmatch 'password\s*[:=]\s*\S') 'no password assignments in fixtures'
Assert ($allContent -notmatch 'token\s*[:=]\s*[A-Za-z0-9+/]{20}') 'no token values in fixtures'
Assert ($allContent -notmatch '\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b') 'no email addresses in fixtures'
Assert ($allContent -notmatch 'secret|credential') 'no secret/credential mentions in fixtures'

# ──────────────────────────────────────────────────────────────
# Summary
# ──────────────────────────────────────────────────────────────
Write-Host "`n========================================"
if ($fail -eq 0) {
    Write-Host "  PASS: $pass   FAIL: $fail — all CapTrack regression checks passed" -ForegroundColor Green
} else {
    Write-Host "  PASS: $pass   FAIL: $fail — CapTrack regression failed" -ForegroundColor Red
}
Write-Host "========================================`n"

exit ($fail -gt 0 ? 1 : 0)
