#Requires -Version 7
# Core Regression Tests — Tier 0 static fixture validation
# Validates generic MxAgile framework behavior against synthetic Core fixtures.
#
# Framework behaviors under test (using synthetic DemoApp fixtures):
#   - Platform boundary classification (SSO/auth screens excluded from fachliche scope)
#   - Role coverage with scope hierarchy and COVERAGE_GAP detection
#   - GAP classification routing (INTERACTION / ROLE / PLATFORM_BOUNDARY)
#   - Revision lifecycle invariants (active_target, role preservation)
#   - Framework policy alignment (generic concepts, not project-specific terms)
#
# Run from repository root:  pwsh tests/test-core-regression.ps1

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

$FixtureDir = Join-Path $RepoRoot 'tests/fixtures/core-regression'
Write-Host "`nCore Regression Tests — $RepoRoot" -ForegroundColor Cyan

# ──────────────────────────────────────────────────────────────
# [1] Synthetic fixture files exist
# ──────────────────────────────────────────────────────────────
Write-Host "`n[1] Synthetic fixture files exist"
$fixtures = @(
    'tests/fixtures/core-regression/platform-boundaries.yaml',
    'tests/fixtures/core-regression/role-coverage.yaml',
    'tests/fixtures/core-regression/gap-records.yaml',
    'tests/fixtures/core-regression/revision-lifecycle.yaml'
)
foreach ($f in $fixtures) {
    Assert (Test-Path (Join-Path $RepoRoot $f)) "Fixture exists: $f"
}

# ──────────────────────────────────────────────────────────────
# [2] Platform boundary fixture: SSO provider correctly classified
# ──────────────────────────────────────────────────────────────
Write-Host "`n[2] Platform boundary: SSO provider classification"
$pb = ReadFile (Join-Path $FixtureDir 'platform-boundaries.yaml')
Assert ($pb -match 'PLATFORM-SSO-PROVIDER') 'fixture defines SSO platform boundary'
Assert ($pb -match 'SSO_PROVIDER') 'fixture names SSO provider'
Assert ($pb -match 'EXCLUDE_FROM_UI_PARITY') 'SSO boundary excludes UI parity'
Assert ($pb -match 'DO_NOT_MODIFY') 'SSO boundary is DO_NOT_MODIFY'
Assert ($pb -match 'SCREEN-LOGIN') 'login screen is excluded'
Assert ($pb -match 'SCREEN-DEMO-ROLE-SWITCHER') 'demo role switcher is excluded'
Assert ($pb -match 'test-only mechanism') 'demo role switcher documented as test-only'
Assert ($pb -match 'NOT productive login|not productive login') 'demo role switcher is not productive login'

# Business rule: login/auth screens are NOT fachliche requirements
Assert ($pb -match 'REQ-NNN.*MUST NOT|must not.*REQ-NNN') 'excluded screens must not generate REQ-NNN'

# ──────────────────────────────────────────────────────────────
# [3] Role coverage fixture: multi-scope roles + COVERAGE_GAP detection
# ──────────────────────────────────────────────────────────────
Write-Host "`n[3] Role coverage: multi-scope roles and COVERAGE_GAP"
$rc = ReadFile (Join-Path $FixtureDir 'role-coverage.yaml')

# Scope hierarchy present
Assert ($rc -match 'required_scope: app') 'Admin role has app scope'
Assert ($rc -match 'required_scope: org') 'Org roles have org scope'
Assert ($rc -match 'required_scope: department') 'Dept roles have department scope'
Assert ($rc -match 'required_scope: team') 'Team roles have team scope'

# COVERAGE_GAP detection
Assert ($rc -match 'COVERAGE_GAP') 'fixture documents team COVERAGE_GAP'
Assert ($rc -match 'ROLE-TEAM-ENTRY') 'TeamEntry in fixture'
Assert ($rc -match 'ROLE_GAP.*not.*infrastructure|ROLE_GAP, not an infrastructure gap') 'team gap is ROLE_GAP not infrastructure gap'
Assert ($rc -match 'overall_status: COVERAGE_GAP') 'overall status is COVERAGE_GAP when team roles missing'

# Security: no production credentials or personal data
Assert ($rc -notmatch '@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}') 'no email addresses in role fixture'
Assert ($rc -notmatch 'password|passwort|secret|token') 'no credentials in role fixture'

# ──────────────────────────────────────────────────────────────
# [4] GAP records fixture: classification and routing rules
# ──────────────────────────────────────────────────────────────
Write-Host "`n[4] GAP records: classification and routing rules"
$gaps = ReadFile (Join-Path $FixtureDir 'gap-records.yaml')
Assert ($gaps -match 'GAP-001-DASHBOARD-EXPAND') 'expandable_area gap present'
Assert ($gaps -match 'GAP-002-TEAM-ROLE') 'team role gap present'
Assert ($gaps -match 'GAP-003-PLATFORM-AUTH') 'platform boundary auth gap present'

# Critical classification rules
Assert ($gaps -match 'NOT.*REQ-NNN|does NOT create new REQ-NNN') 'INTERACTION_GAP does not create REQ-NNN'
Assert ($gaps -match 'NOT.*Mockup Refinement|not route to Mockup Refinement') 'ROLE_GAP does not route to Mockup Refinement'
Assert ($gaps -match 'REMOVE.*not.*ALIGN|repair is REMOVE not ALIGN') 'PLATFORM_BOUNDARY_GAP repair is REMOVE'
Assert ($gaps -match 'technical.*repair.*NOT.*fachliche|purely technical.*not.*Decision') 'technical repair not fachliche decision'

# Expandable area pattern
Assert ($gaps -match 'EFF-SECTION-EXPAND') 'expand effect referenced'
Assert ($gaps -match 'EFF-SECTION-COLLAPSE') 'collapse effect referenced'

# Security: no production data or credentials
Assert ($gaps -notmatch 'password|passwort|token|secret') 'no credentials in gap fixture'

# ──────────────────────────────────────────────────────────────
# [5] Revision lifecycle fixture: invariants
# ──────────────────────────────────────────────────────────────
Write-Host "`n[5] Revision lifecycle invariants"
$rl = ReadFile (Join-Path $FixtureDir 'revision-lifecycle.yaml')
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
Assert ($rl -match 'ROLE-TEAM-ENTRY') 'TeamEntry preserved in revision'
Assert ($rl -match 'ROLE-TEAM-REVIEWER') 'TeamReviewer preserved in revision'
Assert ($rl -match 'fachliche roles preserved') 'all roles preserved statement'
Assert ($rl -match 'SCREEN-LOGIN.*expected_superseded|expected_superseded.*SCREEN-LOGIN') 'SCREEN-LOGIN is expected_superseded, not unexpected_missing'

# Effects do not derive pages
Assert ($rl -match 'derived_page: false') 'platform boundary effects have derived_page: false'
Assert ($rl -match 'PLATFORM_BOUNDARY.*REQ-NNN|does NOT create fachliche REQ-NNN') 'platform boundary effect does not create REQ-NNN'

# ──────────────────────────────────────────────────────────────
# [6] Framework policy alignment: generic concepts present
# ──────────────────────────────────────────────────────────────
Write-Host "`n[6] Framework policy alignment: generic concepts"
$gapPolicy = ReadFile (Join-Path $RepoRoot '.mxagile/policies/gap-verification-repair.md')
$mlPolicy  = ReadFile (Join-Path $RepoRoot '.mxagile/policies/mockup-lifecycle.md')

# GAP policy covers expandable area interactions as a generic concept
Assert ($gapPolicy -match 'expandable_area|expand.*collapse') 'gap policy covers expandable_area interactions'

# GAP policy covers scoped-role concept (any scope hierarchy)
Assert ($gapPolicy -match 'scope|role.*scope|scoped.*role') 'gap policy addresses scoped roles generically'

# Mockup lifecycle policy covers platform boundary for auth screens
Assert ($mlPolicy -match 'platform_boundary') 'lifecycle policy uses platform_boundary classification'
Assert ($mlPolicy -match '[Ll]ogin.*platform_boundary|platform_boundary.*login') 'lifecycle policy marks login as platform_boundary'

# ──────────────────────────────────────────────────────────────
# [7] Security: no production data in any Core regression fixture
# ──────────────────────────────────────────────────────────────
Write-Host "`n[7] Security: no sensitive data in fixtures"
$allFixtures = Get-ChildItem -LiteralPath $FixtureDir -File | ForEach-Object { [string](Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8) }
$allContent = $allFixtures -join "`n"
Assert ($allContent -notmatch 'password\s*[:=]\s*\S') 'no password assignments in fixtures'
Assert ($allContent -notmatch 'token\s*[:=]\s*[A-Za-z0-9+/]{20}') 'no token values in fixtures'
Assert ($allContent -notmatch '\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b') 'no email addresses in fixtures'
Assert ($allContent -notmatch 'secret|credential') 'no secret/credential mentions in fixtures'

# ──────────────────────────────────────────────────────────────
# [8] Purity: synthetic fixtures contain no real project names
# ──────────────────────────────────────────────────────────────
Write-Host "`n[8] Purity: no real project names in synthetic fixtures"
$bannedInFixtures = @('CapTrack', 'captrack', 'KidsCompass', 'kidscompass', 'Mercedes', 'mercedes', 'mercedes-benz', 'MB_SSO', 'MB_UI', 'MBUI')
foreach ($term in $bannedInFixtures) {
    Assert ($allContent -notmatch [regex]::Escape($term)) "No '$term' in synthetic Core fixtures"
}

# ──────────────────────────────────────────────────────────────
# [9] Namespace guard: no MB_ company prefix in canonical .mxagile/ sources
# Any MB_<identifier> in .mxagile/ sources is a Company Layer namespace leak.
# Exception: lines whose sole purpose is a negative/banned assertion.
# ──────────────────────────────────────────────────────────────
Write-Host "`n[9] Namespace guard: MB_ prefix absent from canonical .mxagile/ sources"
$mxagileSourceFiles = Get-ChildItem -Recurse -File (Join-Path $RepoRoot '.mxagile') |
    Where-Object { $_.FullName -notlike '*\.mxagile\state\*' -and $_.FullName -notlike '*\.mxagile\layers\*' }
$namespaceLeaks = [System.Collections.Generic.List[string]]::new()
foreach ($f in $mxagileSourceFiles) {
    $lines = Get-Content -LiteralPath $f.FullName -ErrorAction SilentlyContinue
    $lineNum = 0
    foreach ($line in $lines) {
        $lineNum++
        if ($line -match 'MB_[A-Za-z]') {
            $rel = $f.FullName.Replace($RepoRoot, '').TrimStart('\/')
            $namespaceLeaks.Add("${rel}:${lineNum}: $line")
        }
    }
}
Assert ($namespaceLeaks.Count -eq 0) "No MB_ company namespace in canonical .mxagile/ sources ($($namespaceLeaks.Count) leak(s) found)"
if ($namespaceLeaks.Count -gt 0) {
    $namespaceLeaks | Select-Object -First 10 | ForEach-Object { Write-Host "  LEAK: $_" -ForegroundColor Red }
}

# ──────────────────────────────────────────────────────────────
# Summary
# ──────────────────────────────────────────────────────────────
Write-Host "`n========================================"
if ($fail -eq 0) {
    Write-Host "  PASS: $pass   FAIL: $fail — all Core regression checks passed" -ForegroundColor Green
} else {
    Write-Host "  PASS: $pass   FAIL: $fail — Core regression failed" -ForegroundColor Red
}
Write-Host "========================================`n"

exit ($fail -gt 0 ? 1 : 0)
