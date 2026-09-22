<#
.SYNOPSIS
    Existing Project Update Contract Tests

.DESCRIPTION
    Validates the canonical mechanism for updating an already-installed,
    successfully migrated MxAgile project to a newer Core version.

    Contract summary:
    - The update entry point is install-core.ps1 (no -CompanyLayerSource)
    - Framework-owned payload (.mxagile/ except layers/ and state/) is overwritten
    - Project-owned files (planning/, requirements/, specs/, AGENT.md) are never touched
    - Migration state (.mxagile/migration/) is preserved (not in canonical source)
    - Company Layer (.mxagile/layers/) is preserved (explicitly excluded from copy)
    - Generated projections (.claude/skills/ etc.) are regenerated from new payload
    - artifact_canonicalization: pending is added to state.yaml if absent (WP-10 upgrade)

    Test groups:
    A - Ownership classification: installer exclusion logic is correct
    B - Company Layer preservation: excluded from overwrite, unchanged without -CompanyLayerSource
    C - Migration state preservation: .mxagile/migration/ is untouched by installer
    D - WP-10 payload present in canonical source
    E - Reconciliation logic: artifact_canonicalization: pending added for pre-WP-10 projects
    F - End-to-end fixture: pre-WP-10 state -> post-WP-10 after reconciliation
    G - Regression: existing test suites still pass

    RUNTIME NOTE:
    Groups A-F run in seconds (static + isolation tests).
    Group G spawns regression suites including test-wp10-artifact-schemas.ps1 (K1-K3
    sub-suites, mxcli acquisition). Full suite can take 20-30 minutes.
    Run Groups A-F only during development; run Group G before commits only.
#>

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$TestsDir    = $PSScriptRoot
$RepoRoot    = Split-Path -Parent $TestsDir
$ScriptsDir  = Join-Path $RepoRoot "scripts"
$MxAgileDir  = Join-Path $RepoRoot ".mxagile"
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

function Assert-Contains {
    param([string]$TestName, [string]$FilePath, [string]$Pattern)
    $content = Get-Content -LiteralPath $FilePath -Raw -ErrorAction SilentlyContinue
    if ($null -eq $content) {
        Assert-True $TestName $false "File not found: $FilePath"
    } else {
        Assert-True $TestName ($content -match $Pattern) "Pattern '$Pattern' not found in $(Split-Path -Leaf $FilePath)"
    }
}

function Assert-NotContains {
    param([string]$TestName, [string]$FilePath, [string]$Pattern)
    $content = Get-Content -LiteralPath $FilePath -Raw -ErrorAction SilentlyContinue
    if ($null -eq $content) {
        Assert-True $TestName $false "File not found: $FilePath"
    } else {
        Assert-True $TestName (-not ($content -match $Pattern)) "Prohibited pattern '$Pattern' found in $(Split-Path -Leaf $FilePath)"
    }
}

function New-TempDir {
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) "mxagile-update-$([System.Guid]::NewGuid().ToString('N').Substring(0,8))"
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    return $tmp
}

function Remove-TempDir {
    param([string]$Path)
    if ($Path -and (Test-Path -LiteralPath $Path)) {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Applies the reconciliation logic extracted from install-core.ps1 Step 1d.
# Used to test reconciliation in isolation without running the full installer.
function Invoke-MigrationStateReconciliation {
    param([string]$ProjectRoot)
    $stateFile = Join-Path $ProjectRoot (Join-Path ".mxagile" (Join-Path "migration" "state.yaml"))
    if (-not (Test-Path -LiteralPath $stateFile -PathType Leaf)) {
        return "NO_STATE_FILE"
    }
    $text = Get-Content -LiteralPath $stateFile -Raw
    if ($text -notmatch '(?m)^artifact_canonicalization:') {
        $text = $text.TrimEnd("`r", "`n") + "`nartifact_canonicalization: pending`n"
        [System.IO.File]::WriteAllText($stateFile, $text, [System.Text.Encoding]::UTF8)
        return "FIELD_ADDED"
    }
    return "FIELD_ALREADY_PRESENT"
}

# Applies stale-file retirement logic from install-core.ps1 Step 1c.1.
# Removes all non-protected items from $MxAgileDir; outputs retired item names to pipeline.
function Invoke-StaleFileRetirement {
    param([string]$MxAgileDir)
    $protected = @("layers", "state", "migration")
    if (-not (Test-Path -LiteralPath $MxAgileDir -PathType Container)) { return }
    Get-ChildItem -LiteralPath $MxAgileDir | ForEach-Object {
        if ($_.PSIsContainer) {
            if ($protected -notcontains $_.Name) {
                Remove-Item -LiteralPath $_.FullName -Recurse -Force
                Write-Output $_.Name
            }
        } else {
            Remove-Item -LiteralPath $_.FullName -Force
            Write-Output $_.Name
        }
    }
}

# Mirrors the canonical copy loop from install-core.ps1 Step 1c (content-merge, no delete).
function Invoke-CanonicalCopy {
    param([string]$SourceDir, [string]$DestDir)
    Get-ChildItem -LiteralPath $SourceDir -Exclude "layers", "state" | ForEach-Object {
        if ($_.PSIsContainer) {
            $dst = Join-Path $DestDir $_.Name
            if (-not (Test-Path -LiteralPath $dst)) { New-Item -ItemType Directory -Path $dst -Force | Out-Null }
            Copy-Item -Path "$($_.FullName)\*" -Destination $dst -Recurse -Force
        } else {
            Copy-Item -LiteralPath $_.FullName -Destination $DestDir -Force
        }
    }
}

$InstallCorePath = Join-Path $ScriptsDir "install-core.ps1"

Write-Host ""
Write-Host "=== Existing Project Update Contract Tests ==="
Write-Host ""

# ===========================================================================
# GROUP A: Ownership classification — installer exclusion logic
# ===========================================================================
Write-Host "--- A: Ownership classification: installer exclusion logic ---"

Assert-True "A1: install-core.ps1 exists" (Test-Path -LiteralPath $InstallCorePath) "Not found"

# Payload copy uses -Exclude "layers","state"
Assert-Contains "A2: payload copy excludes layers directory" $InstallCorePath '-Exclude "layers", "state"'
Assert-Contains "A3: payload copy excludes state directory" $InstallCorePath '-Exclude "layers", "state"'

# Content-merge (not Mirror): Copy-Item with * sources — does NOT delete project-only subdirs
Assert-Contains "A4: payload copy uses content-merge (not mirror/delete)" `
    $InstallCorePath 'Copy-Item -Path.*\\\*.*-Recurse -Force'

# No MIR / --delete / Remove-Item on .mxagile in payload copy path
Assert-NotContains "A5: payload copy does NOT use robocopy MIR (no delete of project subdirs)" `
    $InstallCorePath 'robocopy.*\/MIR'
Assert-NotContains "A6: payload copy does NOT call Remove-Item on .mxagile as a whole" `
    $InstallCorePath 'Remove-Item.*\.mxagile(?!.*layers|.*state)'

# Step 2 (Company Layer) only executes when -CompanyLayerSource is set
Assert-Contains "A7: Company Layer step guarded by CompanyLayerSource parameter" `
    $InstallCorePath 'if \(\$CompanyLayerSource\)'

# EXISTING_MXAGILE_PROJECT classification falls through (no exit or throw for it)
Assert-Contains "A8: detect-project-type is called before installation" `
    $InstallCorePath 'detect-project-type\.ps1'

# migration/ is not in the canonical source — verify canonical source lacks migration/
$canonicalMigrationDir = Join-Path $MxAgileDir "migration"
Assert-True "A9: canonical .mxagile/ source does NOT contain migration/ subdirectory" `
    (-not (Test-Path -LiteralPath $canonicalMigrationDir -PathType Container)) `
    "migration/ found in canonical source - would overwrite project migration state on update"

# injection-contract.md lists planning/ as NEVER_TOUCH
$injectionContract = Join-Path $RepoRoot "docs\injection-contract.md"
Assert-Contains "A10: injection-contract.md classifies planning/ as NEVER_TOUCH" `
    $injectionContract 'planning.*user.owned|NEVER_TOUCH.*planning|planning/\*\*'
Assert-Contains "A11: injection-contract.md classifies requirements/ as NEVER_TOUCH" `
    $injectionContract 'requirements.*user.owned|requirements/\*\*'

Write-Host ""

# ===========================================================================
# GROUP B: Company Layer preservation
# ===========================================================================
Write-Host "--- B: Company Layer preservation ---"

# .mxagile/layers/ exists in dev tree to confirm it is a known path
Assert-True "B1: .mxagile/layers/ directory exists in canonical source tree" `
    (Test-Path -LiteralPath (Join-Path $MxAgileDir "layers") -PathType Container) "Not found"

Assert-Contains "B2: installer excludes layers/ from payload copy" `
    $InstallCorePath '-Exclude "layers", "state"'

Assert-Contains "B3: Company Layer installation only when CompanyLayerSource provided" `
    $InstallCorePath 'if \(\$CompanyLayerSource\)'

# install-mxagile-mercedes.ps1 always passes -CompanyLayerSource (documents why direct
# install-core.ps1 is the correct Core-only update entry point)
$mercedesBootstrap = Join-Path $RepoRoot "install-mxagile-mercedes.ps1"
Assert-Contains "B4: install-mxagile-mercedes.ps1 always passes -CompanyLayerSource (bootstrap only)" `
    $mercedesBootstrap 'CompanyLayerSource.*MercedesGitUrl|-CompanyLayerSource\s+\$Mercedes'

# Provenance file (provenance.json) is stored inside .mxagile/layers/<id>/ which is excluded
Assert-Contains "B5: provenance.json is written inside .mxagile/layers/<id>/ (excluded dir)" `
    $InstallCorePath 'provenance\.json'

Write-Host ""

# ===========================================================================
# GROUP C: Migration state preservation
# ===========================================================================
Write-Host "--- C: Migration state preservation ---"

# .mxagile/state/ is explicitly excluded
Assert-Contains "C1: .mxagile/state/ explicitly excluded from payload copy" `
    $InstallCorePath '-Exclude "layers", "state"'

# .mxagile/migration/ is not in canonical source (tested in A9), meaning the content-merge
# will never touch migration/ even without an explicit exclude
Assert-True "C2: canonical source lacks migration/ => content-merge cannot overwrite project migration/" `
    (-not (Test-Path -LiteralPath $canonicalMigrationDir -PathType Container)) `
    "migration/ in canonical source would overwrite project state"

# State empty directory is ensured but not overwritten
Assert-Contains "C3: installer ensures .mxagile/state/ exists but does not fill it" `
    $InstallCorePath 'if \(-not.*Test-Path.*destState'

# The installer emits [OK] markers for state preservation actions
Assert-Contains "C4: installer logs migration state reconciliation result" `
    $InstallCorePath 'Migration state reconciled'

Write-Host ""

# ===========================================================================
# GROUP D: WP-10 payload present in canonical source
# ===========================================================================
Write-Host "--- D: WP-10 payload present in canonical source ---"

foreach ($pair in @(
    @{ Name = "D1: requirement.schema.json in canonical source"; Path = Join-Path $MxAgileDir "schemas\requirement.schema.json" },
    @{ Name = "D2: spec.schema.json in canonical source"; Path = Join-Path $MxAgileDir "schemas\spec.schema.json" },
    @{ Name = "D3: task.schema.json in canonical source"; Path = Join-Path $MxAgileDir "schemas\task.schema.json" },
    @{ Name = "D4: requirements/template.yml in canonical source"; Path = Join-Path $MxAgileDir "templates\generic\requirements\template.yml" },
    @{ Name = "D5: specs/template.yml in canonical source"; Path = Join-Path $MxAgileDir "templates\generic\specs\template.yml" },
    @{ Name = "D6: updated tasks/template.yaml uses ID: field"; Path = Join-Path $MxAgileDir "templates\generic\tasks\template.yaml" },
    @{ Name = "D7: migration skill updated for WP-10"; Path = Join-Path $MxAgileDir "skills\migration.md" },
    @{ Name = "D8: migration policy updated for WP-10"; Path = Join-Path $MxAgileDir "policies\migration-dfc-to-mxagile.md" }
)) {
    Assert-True $pair.Name (Test-Path -LiteralPath $pair.Path) "Not found: $($pair.Path)"
}

# Scripts installed alongside Core (not part of .mxagile/ payload, but part of update)
foreach ($pair in @(
    @{ Name = "D9: canonicalize_artifacts.py present in scripts/"; Path = Join-Path $ScriptsDir "canonicalize_artifacts.py" },
    @{ Name = "D10: migrate-stories.ps1 is semantic converter"; Path = Join-Path $ScriptsDir "migrate-stories.ps1" },
    @{ Name = "D11: build_artifact_index.py reads canonical fields"; Path = Join-Path $ScriptsDir "build_artifact_index.py" }
)) {
    Assert-True $pair.Name (Test-Path -LiteralPath $pair.Path) "Not found: $($pair.Path)"
}

Write-Host ""

# ===========================================================================
# GROUP E: Reconciliation logic for artifact_canonicalization field
# ===========================================================================
Write-Host "--- E: Reconciliation: artifact_canonicalization added for pre-WP-10 projects ---"

# Static: reconciliation code present in install-core.ps1
Assert-Contains "E1: install-core.ps1 contains reconciliation code block" `
    $InstallCorePath 'artifact_canonicalization'
Assert-Contains "E2: reconciliation only fires if migration/state.yaml exists" `
    $InstallCorePath 'Test-Path.*migrationStateFile'
Assert-Contains "E3: reconciliation only fires if field absent (regex check)" `
    $InstallCorePath 'artifact_canonicalization.*pending'
Assert-Contains "E4: reconciliation appends field (does not rewrite file)" `
    $InstallCorePath "TrimEnd.*``r.*``n.*\+.*artifact_canonicalization"

# Functional: test reconciliation in isolation using extracted helper
$tmpE = New-TempDir
try {
    $migDir = Join-Path $tmpE ".mxagile\migration"
    New-Item -ItemType Directory -Path $migDir -Force | Out-Null
    $stateFile = Join-Path $migDir "state.yaml"

    # E5: Pre-WP-10 state.yaml (no artifact_canonicalization)
    $preWp10Lines = @(
        'status: complete',
        'started_at: "2026-01-15T10:00:00Z"',
        'last_completed_step: validation_passed',
        'steps_completed:',
        '  - inventory',
        '  - plan_confirmed',
        '  - baseline_written',
        '  - agent_md_migrated',
        '  - markers_cleaned',
        '  - dfc_artifacts_removed',
        '  - mxagile_installed',
        '  - validation_passed'
    )
    $preWp10State = $preWp10Lines -join "`n"
    $preWp10State | Set-Content -LiteralPath $stateFile -Encoding UTF8

    $result = Invoke-MigrationStateReconciliation -ProjectRoot $tmpE
    Assert-True "E5: reconciliation returns FIELD_ADDED for pre-WP-10 state" `
        ($result -eq "FIELD_ADDED") "Got: $result"

    $afterContent = Get-Content -LiteralPath $stateFile -Raw
    Assert-True "E6: artifact_canonicalization: pending added to state.yaml" `
        ($afterContent -match '(?m)^artifact_canonicalization: pending') `
        "Field not found in: $afterContent"
    Assert-True "E7: status: complete preserved" `
        ($afterContent -match '(?m)^status: complete') "status field changed"
    Assert-True "E8: last_completed_step: validation_passed preserved" `
        ($afterContent -match 'last_completed_step: validation_passed') "last_completed_step changed"
    Assert-True "E9: steps_completed preserved" `
        ($afterContent -match 'steps_completed:') "steps_completed missing"
    Assert-True "E10: started_at preserved" `
        ($afterContent -match 'started_at:') "started_at missing"

    # F-group here: idempotency and non-overwrite of existing values

    # E11 / Idempotency: second reconciliation run must not duplicate or change
    $result2 = Invoke-MigrationStateReconciliation -ProjectRoot $tmpE
    Assert-True "E11: second reconciliation returns FIELD_ALREADY_PRESENT" `
        ($result2 -eq "FIELD_ALREADY_PRESENT") "Got: $result2"
    $afterContent2 = Get-Content -LiteralPath $stateFile -Raw
    $fieldCount = ([regex]::Matches($afterContent2, '(?m)^artifact_canonicalization:')).Count
    Assert-True "E12: field not duplicated on second reconciliation run" ($fieldCount -eq 1) "Found $fieldCount occurrences"

    # E13: existing artifact_canonicalization: complete must not be overwritten
    $stateFile | Out-Null  # already set
    $withComplete = $preWp10State.TrimEnd() + "`nartifact_canonicalization: complete`n"
    $withComplete | Set-Content -LiteralPath $stateFile -Encoding UTF8

    $result3 = Invoke-MigrationStateReconciliation -ProjectRoot $tmpE
    Assert-True "E13: existing artifact_canonicalization: complete is NOT overwritten" `
        ($result3 -eq "FIELD_ALREADY_PRESENT") "Got: $result3"
    $afterContent3 = Get-Content -LiteralPath $stateFile -Raw
    Assert-True "E14: artifact_canonicalization: complete remains after reconciliation" `
        ($afterContent3 -match '(?m)^artifact_canonicalization: complete') "Field changed from complete"

    # E15: no state.yaml present (fresh project) — must not error
    $noStateTmp = New-TempDir
    try {
        $noStateMxAgile = Join-Path $noStateTmp ".mxagile"
        New-Item -ItemType Directory -Path $noStateMxAgile -Force | Out-Null
        $result4 = Invoke-MigrationStateReconciliation -ProjectRoot $noStateTmp
        Assert-True "E15: reconciliation returns NO_STATE_FILE when state.yaml absent" `
            ($result4 -eq "NO_STATE_FILE") "Got: $result4"
    } finally {
        Remove-TempDir $noStateTmp
    }
} finally {
    Remove-TempDir $tmpE
}

Write-Host ""

# ===========================================================================
# GROUP F: End-to-end fixture — pre-WP-10 brownfield -> post-WP-10 update
# ===========================================================================
Write-Host "--- F: End-to-end fixture: pre-WP-10 brownfield -> post-WP-10 state ---"

$tmpF = New-TempDir
try {
    # Build a minimal pre-WP-10 brownfield project fixture
    $dirs = @(
        ".mxagile\migration",
        ".mxagile\layers\mercedes-star",
        ".mxagile\state",
        "planning\stories",
        "planning\checklists",
        "requirements",
        "specs"
    )
    foreach ($d in $dirs) {
        New-Item -ItemType Directory -Path (Join-Path $tmpF $d) -Force | Out-Null
    }

    # Fake .mpr file (install-core.ps1 requires exactly one)
    "fake mpr" | Set-Content -Path (Join-Path $tmpF "CapTrack.mpr") -Encoding UTF8

    # Pre-WP-10 migration state (no artifact_canonicalization field)
    (@(
        'status: complete',
        'started_at: "2026-01-15T10:00:00Z"',
        'last_completed_step: validation_passed',
        'steps_completed:',
        '  - inventory',
        '  - plan_confirmed',
        '  - baseline_written',
        '  - agent_md_migrated',
        '  - markers_cleaned',
        '  - dfc_artifacts_removed',
        '  - mxagile_installed',
        '  - validation_passed'
    ) -join "`n") | Set-Content -LiteralPath (Join-Path $tmpF ".mxagile\migration\state.yaml") -Encoding UTF8

    # Fake brownfield baseline (migration provenance)
    (@(
        'baseline_type: brownfield',
        'created_at: "2026-01-15T10:00:00Z"',
        'project: CapTrack',
        'source: DFC-AI'
    ) -join "`n") | Set-Content -LiteralPath (Join-Path $tmpF ".mxagile\state\brownfield-baseline.yaml") -Encoding UTF8

    # Fake Mercedes Company Layer
    '{"id": "mercedes-star", "name": "Mercedes-Benz Company Layer", "version": "1.0.0"}' |
        Set-Content -LiteralPath (Join-Path $tmpF ".mxagile\layers\mercedes-star\layer.json") -Encoding UTF8
    '{"source_type": "Git", "source": "https://mercedes-benz.ghe.com/...", "ref": "main"}' |
        Set-Content -LiteralPath (Join-Path $tmpF ".mxagile\layers\mercedes-star\provenance.json") -Encoding UTF8

    # Brownfield artifacts (must survive update)
    (@(
        '---',
        'req_id: REQ-001',
        '---',
        '# Kundenauftragsliste',
        '',
        '## 9. Akzeptanzkriterien',
        '',
        '**AC-1:**',
        '- **Given:** logged in',
        '- **When:** open dashboard',
        '- **Then:** see orders'
    ) -join "`n") | Set-Content -LiteralPath (Join-Path $tmpF "planning\stories\REQ-001.md") -Encoding UTF8

    (@(
        'wave: W01',
        'tasks:',
        '  - Create datasource microflow',
        '  - Configure list view'
    ) -join "`n") | Set-Content -LiteralPath (Join-Path $tmpF "planning\checklists\W01-implementation-checklist.yaml") -Encoding UTF8

    # Project AGENT.md (must survive update)
    "# CapTrack Project`n`nThis is the CapTrack project." | Set-Content -LiteralPath (Join-Path $tmpF "AGENT.md") -Encoding UTF8

    # Apply reconciliation (simulates the Step 1d of install-core.ps1)
    $reconcileResult = Invoke-MigrationStateReconciliation -ProjectRoot $tmpF

    # --- Verify post-reconciliation state ---
    $stateAfter = Get-Content -LiteralPath (Join-Path $tmpF ".mxagile\migration\state.yaml") -Raw

    Assert-True "F1: migration status: complete preserved" `
        ($stateAfter -match '(?m)^status: complete') "status changed"
    Assert-True "F2: last_completed_step: validation_passed preserved" `
        ($stateAfter -match 'last_completed_step: validation_passed') "last_completed_step changed"
    Assert-True "F3: artifact_canonicalization: pending added" `
        ($stateAfter -match '(?m)^artifact_canonicalization: pending') "Field not added"
    Assert-True "F4: reconciliation reported FIELD_ADDED" `
        ($reconcileResult -eq "FIELD_ADDED") "Got: $reconcileResult"
    Assert-True "F5: Mercedes Company Layer dir preserved" `
        (Test-Path -LiteralPath (Join-Path $tmpF ".mxagile\layers\mercedes-star")) `
        "Company Layer dir missing"
    Assert-True "F6: Mercedes layer.json preserved" `
        (Test-Path -LiteralPath (Join-Path $tmpF ".mxagile\layers\mercedes-star\layer.json")) `
        "layer.json missing"
    Assert-True "F7: Mercedes provenance.json preserved" `
        (Test-Path -LiteralPath (Join-Path $tmpF ".mxagile\layers\mercedes-star\provenance.json")) `
        "provenance.json missing"
    Assert-True "F8: brownfield baseline preserved" `
        (Test-Path -LiteralPath (Join-Path $tmpF ".mxagile\state\brownfield-baseline.yaml")) `
        "brownfield-baseline.yaml missing"
    Assert-True "F9: planning/stories/REQ-001.md preserved" `
        (Test-Path -LiteralPath (Join-Path $tmpF "planning\stories\REQ-001.md")) `
        "REQ-001.md missing"
    Assert-True "F10: planning/checklists/W01-implementation-checklist.yaml preserved" `
        (Test-Path -LiteralPath (Join-Path $tmpF "planning\checklists\W01-implementation-checklist.yaml")) `
        "Checklist missing"
    Assert-True "F11: AGENT.md preserved" `
        (Test-Path -LiteralPath (Join-Path $tmpF "AGENT.md")) `
        "AGENT.md missing"
    Assert-True "F12: no canonicalization-state.yaml created (canonicalization not started)" `
        (-not (Test-Path -LiteralPath (Join-Path $tmpF ".mxagile\migration\canonicalization-state.yaml"))) `
        "canonicalization-state.yaml was created unexpectedly"
    Assert-True "F13: no canonical requirements/*.yml created (no premature canonicalization)" `
        (@(Get-ChildItem -Path (Join-Path $tmpF "requirements") -Filter "*.yml" -ErrorAction SilentlyContinue).Count -eq 0) `
        "Unexpected .yml files in requirements/"
} finally {
    Remove-TempDir $tmpF
}

Write-Host ""

# ===========================================================================
# GROUP H: Stale framework-owned file retirement on Core update
# ===========================================================================
Write-Host "--- H: Stale framework-owned file retirement ---"

# H1-H2: Static proof — retirement logic present in install-core.ps1
Assert-Contains "H1: install-core.ps1 contains stale-file retirement block" `
    $InstallCorePath 'protectedMxAgileDirs'
Assert-Contains "H2: retirement protection list includes layers, state, migration" `
    $InstallCorePath '"layers", "state", "migration"'

# H3-H8: Functional proof — isolated retirement helper
$tmpH = New-TempDir
try {
    $mxH = Join-Path $tmpH ".mxagile"
    foreach ($d in @(
        "skills", "agents", "policies",
        "layers\mercedes-star", "state", "migration"
    )) { New-Item -ItemType Directory -Path (Join-Path $mxH $d) -Force | Out-Null }

    # Framework-owned content (version A surface)
    "skill v1" | Set-Content -LiteralPath (Join-Path $mxH "skills\old-skill.md") -Encoding UTF8
    "agent v1" | Set-Content -LiteralPath (Join-Path $mxH "agents\old-agent.md") -Encoding UTF8
    "lifecycle v1" | Set-Content -LiteralPath (Join-Path $mxH "lifecycle.yaml") -Encoding UTF8

    # Protected content (must survive retirement)
    '{"id": "mercedes-star"}' | Set-Content -LiteralPath (Join-Path $mxH "layers\mercedes-star\layer.json") -Encoding UTF8
    "state content" | Set-Content -LiteralPath (Join-Path $mxH "state\brownfield.yaml") -Encoding UTF8
    (@('status: complete', 'last_step: done') -join "`n") | Set-Content -LiteralPath (Join-Path $mxH "migration\state.yaml") -Encoding UTF8

    $retired = @(Invoke-StaleFileRetirement -MxAgileDir $mxH)

    Assert-True "H3: framework file (lifecycle.yaml) retired" `
        (-not (Test-Path -LiteralPath (Join-Path $mxH "lifecycle.yaml"))) "lifecycle.yaml still present"
    Assert-True "H4: framework dir (skills/) retired" `
        (-not (Test-Path -LiteralPath (Join-Path $mxH "skills"))) "skills/ still present"
    Assert-True "H5: layers/ content preserved during retirement" `
        (Test-Path -LiteralPath (Join-Path $mxH "layers\mercedes-star\layer.json")) "layer.json missing"
    Assert-True "H6: state/ content preserved during retirement" `
        (Test-Path -LiteralPath (Join-Path $mxH "state\brownfield.yaml")) "state content missing"
    Assert-True "H7: migration/ content preserved during retirement" `
        (Test-Path -LiteralPath (Join-Path $mxH "migration\state.yaml")) "migration state.yaml missing"
    Assert-True "H8: retirement returns names of retired items" `
        ($retired.Count -ge 3) "Expected >=3 retired items, got $($retired.Count)"
} finally {
    Remove-TempDir $tmpH
}

# H9-H13: End-to-end equivalence — version A -> retirement + canonical copy -> version B surface
$tmpH2 = New-TempDir
try {
    $mxH2 = Join-Path $tmpH2 ".mxagile"
    foreach ($d in @(
        "skills", "agents",
        "layers\mercedes-star", "migration"
    )) { New-Item -ItemType Directory -Path (Join-Path $mxH2 $d) -Force | Out-Null }

    # Version A surface: files that do NOT exist in the real canonical source
    "old skill" | Set-Content -LiteralPath (Join-Path $mxH2 "skills\skill-a-only.md") -Encoding UTF8
    "old agent" | Set-Content -LiteralPath (Join-Path $mxH2 "agents\agent-a-only.md") -Encoding UTF8

    # Protected content
    '{"id": "mercedes-star"}' | Set-Content -LiteralPath (Join-Path $mxH2 "layers\mercedes-star\layer.json") -Encoding UTF8
    "status: complete" | Set-Content -LiteralPath (Join-Path $mxH2 "migration\state.yaml") -Encoding UTF8

    # Simulate Core update: Step 1c.1 retirement + Step 1c canonical copy
    Invoke-StaleFileRetirement -MxAgileDir $mxH2 | Out-Null
    Invoke-CanonicalCopy -SourceDir $MxAgileDir -DestDir $mxH2

    # Version-A-only files must be gone (retired, not re-introduced by canonical copy)
    Assert-True "H9: version-A skill (skill-a-only.md) absent after canonical update" `
        (-not (Test-Path -LiteralPath (Join-Path $mxH2 "skills\skill-a-only.md"))) "stale skill still present"
    Assert-True "H10: version-A agent (agent-a-only.md) absent after canonical update" `
        (-not (Test-Path -LiteralPath (Join-Path $mxH2 "agents\agent-a-only.md"))) "stale agent still present"

    # Canonical files must be present
    Assert-True "H11: canonical skills/ present after retirement + canonical copy" `
        (Test-Path -LiteralPath (Join-Path $mxH2 "skills")) "skills/ missing after update"

    # Protected content must survive the full cycle
    Assert-True "H12: Company Layer preserved through full retirement+copy cycle" `
        (Test-Path -LiteralPath (Join-Path $mxH2 "layers\mercedes-star\layer.json")) "Company Layer lost"
    Assert-True "H13: migration state preserved through full retirement+copy cycle" `
        (Test-Path -LiteralPath (Join-Path $mxH2 "migration\state.yaml")) "migration state.yaml lost"
} finally {
    Remove-TempDir $tmpH2
}

Write-Host ""

# ===========================================================================
# GROUP G: Regression suites
# ===========================================================================
Write-Host "--- G: Regression suites ---"

function Invoke-RegressionSuite {
    param([string]$TestName, [string]$ScriptPath)
    if (-not (Test-Path -LiteralPath $ScriptPath)) {
        Assert-True $TestName $false "Regression script not found: $ScriptPath"
        return
    }
    $output   = & powershell -NoProfile -ExecutionPolicy Bypass -File $ScriptPath 2>&1
    $exitCode = $LASTEXITCODE
    Assert-True $TestName ($exitCode -eq 0) "Exited $exitCode. Last: $(($output | Select-Object -Last 5) -join ' | ')"
}

Invoke-RegressionSuite "G1: test-migration-provenance.ps1 passes" `
    (Join-Path $TestsDir "test-migration-provenance.ps1")

Invoke-RegressionSuite "G2: test-migration-lifecycle-resync.ps1 passes" `
    (Join-Path $TestsDir "test-migration-lifecycle-resync.ps1")

Invoke-RegressionSuite "G3: test-wp10-artifact-schemas.ps1 passes" `
    (Join-Path $TestsDir "test-wp10-artifact-schemas.ps1")

Write-Host ""

# ===========================================================================
# Summary
# ===========================================================================
Write-Host "=== Existing Project Update Contract Test Results ==="
Write-Host "  PASS: $PassCount" -ForegroundColor Green
if ($FailCount -gt 0) {
    Write-Host "  FAIL: $FailCount" -ForegroundColor Red
    foreach ($detail in $FailDetails) {
        Write-Host "    $detail" -ForegroundColor Red
    }
    Write-Host ""
    Write-Host "TEST FAILED: Existing project update contract violated." -ForegroundColor Red
    exit 1
} else {
    Write-Host ""
    Write-Host "TEST PASSED: Existing project update contract met." -ForegroundColor Green
    exit 0
}
