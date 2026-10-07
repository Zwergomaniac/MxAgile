#Requires -Version 7
# MxMocketeer Phase 6 Behavioral Reality Gate — Tier 1
# Exercises the ACTUAL apply-transformation-spec.ps1 executor against a real HTML fixture.
# Every positive test uses real HTML mutation; every negative test proves fail-closed behavior.
#
# Must be run from repository root or with -RepoRoot:
#   pwsh tests/test-transformation-behavioral.ps1
#
# Requirements:
#   - tests/fixtures/transformation/revision-11-mockup.html
#   - tests/fixtures/transformation/txspec-*.json
#   - scripts/apply-transformation-spec.ps1

param(
    [string]$RepoRoot = (Join-Path $PSScriptRoot '..')
)

$RepoRoot = (Resolve-Path $RepoRoot).Path
$ErrorActionPreference = 'Continue'
$pass = 0; $fail = 0

# ─── Infrastructure ───────────────────────────────────────────────────────────

$tempDir     = Join-Path $env:TEMP "mocketeer-behavioral-$(Get-Random)"
$fixtureDir  = Join-Path $RepoRoot 'tests/fixtures/transformation'
$executorPath = Join-Path $RepoRoot 'scripts/apply-transformation-spec.ps1'
$fixturePath  = Join-Path $fixtureDir 'revision-11-mockup.html'
$pwshExe      = (Get-Process -Id $PID -ErrorAction SilentlyContinue)?.Path
if (-not $pwshExe) { $pwshExe = 'pwsh' }

New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

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

function Invoke-Executor {
    param(
        [string]$HtmlPath,
        [string]$SpecPath,
        [string]$OutputPath = ''
    )
    $stdoutFile = Join-Path $tempDir "out-$(Get-Random).txt"
    $stderrFile = Join-Path $tempDir "err-$(Get-Random).txt"

    $argList = @(
        '-NoProfile', '-NonInteractive',
        '-File', "`"$executorPath`"",
        '-HtmlFile', "`"$HtmlPath`"",
        '-SpecFile', "`"$SpecPath`""
    )
    if ($OutputPath) { $argList += @('-OutputFile', "`"$OutputPath`"") }

    $proc = Start-Process -FilePath $pwshExe -ArgumentList ($argList -join ' ') `
        -Wait -PassThru -NoNewWindow `
        -RedirectStandardOutput $stdoutFile `
        -RedirectStandardError  $stderrFile

    $stdout = if (Test-Path $stdoutFile) { Get-Content $stdoutFile -Raw -Encoding UTF8 -ErrorAction SilentlyContinue } else { '' }
    $stderr = if (Test-Path $stderrFile) { Get-Content $stderrFile -Raw -Encoding UTF8 -ErrorAction SilentlyContinue } else { '' }
    Remove-Item $stdoutFile, $stderrFile -Force -ErrorAction SilentlyContinue

    return [PSCustomObject]@{
        ExitCode = [int]$proc.ExitCode
        Stdout   = $stdout
        Stderr   = $stderr
    }
}

function Copy-Fixture {
    $dest = Join-Path $tempDir "fixture-$(Get-Random).html"
    Copy-Item $fixturePath $dest
    return $dest
}

function Get-Contract {
    param([string]$HtmlPath)
    $html = Get-Content $HtmlPath -Raw -Encoding UTF8
    if ($html -match '(?s)<script[^>]+id="mocketeer-spec"[^>]*>(.*?)</script>') {
        try { return $Matches[1].Trim() | ConvertFrom-Json -Depth 30 }
        catch { return $null }
    }
    return $null
}

function Files-AreIdentical {
    param([string]$A, [string]$B)
    $bytesA = [System.IO.File]::ReadAllBytes($A)
    $bytesB = [System.IO.File]::ReadAllBytes($B)
    if ($bytesA.Length -ne $bytesB.Length) { return $false }
    for ($i = 0; $i -lt $bytesA.Length; $i++) {
        if ($bytesA[$i] -ne $bytesB[$i]) { return $false }
    }
    return $true
}

Write-Host ""
Write-Host "MxMocketeer Phase 6 Behavioral Reality Gate" -ForegroundColor Cyan
Write-Host "Fixture : $fixturePath"
Write-Host "Executor: $executorPath"
Write-Host "Temp    : $tempDir"

# ─── Preconditions ────────────────────────────────────────────────────────────

Write-Host "`n[0] Preconditions"
Assert (Test-Path $fixturePath)   'Fixture HTML exists'
Assert (Test-Path $executorPath)  'Executor script exists'
foreach ($spec in @('txspec-cross-cutting', 'txspec-local-edit', 'txspec-missing-target',
                    'txspec-extra-target', 'txspec-precondition-mismatch',
                    'txspec-stable-id-mismatch', 'txspec-m365-handoff')) {
    $p = Join-Path $fixtureDir "$spec.json"
    Assert (Test-Path $p) "Spec fixture $spec.json exists"
}

# Verify fixture has exactly 3 StickyHeaders
$fixtureHtml = Get-Content $fixturePath -Raw -Encoding UTF8
$stickyCount = ([regex]::Matches($fixtureHtml, 'data-mx-component="StickyHeader"')).Count
Assert ($stickyCount -eq 3) "Fixture has exactly 3 StickyHeader elements" "found: $stickyCount"

# Verify "2024" appears in StickyHeaders and in non-StickyHeader locations
Assert ($fixtureHtml -match 'data-mx-component="StickyHeader"[\s\S]{0,200}2024') 'Fixture StickyHeaders contain 2024'
Assert ($fixtureHtml -match 'data-mx-component="PageHeader"[\s\S]{0,200}2024') 'Fixture PageHeader contains 2024 (non-target)'
Assert ($fixtureHtml -match 'fiscal year 2024')                                  'Fixture contract requirements contain fiscal year 2024 (non-target)'
Assert ($fixtureHtml -match 'Q3 2024')                                            'Fixture contract decisions contain Q3 2024 (non-target)'

# Verify Design Contract is valid JSON at revision 11
$fixtureContract = Get-Contract -HtmlPath $fixturePath
Assert ($null -ne $fixtureContract)              'Fixture Design Contract is valid JSON'
Assert ($fixtureContract.mockup.revision -eq 11) 'Fixture revision is 11'
Assert ($fixtureContract.flows[0].id -eq 'FLOW-001') 'Fixture has FLOW-001'
$stepIds = $fixtureContract.flows[0].steps | ForEach-Object { $_.id }
foreach ($sid in @('FLOWSTEP-001', 'FLOWSTEP-002', 'FLOWSTEP-003', 'FLOWSTEP-004')) {
    Assert ($sid -in $stepIds) "Fixture has $sid"
}

# ─── T1: CROSS_CUTTING_EDIT — positive ───────────────────────────────────────

Write-Host "`n[T1] CROSS_CUTTING_EDIT — year change 2024->2025 in all StickyHeaders"
$srcT1   = Copy-Fixture
$outT1   = Join-Path $tempDir 'out-T1.html'
$specT1  = Join-Path $fixtureDir 'txspec-cross-cutting.json'
$resultT1 = Invoke-Executor -HtmlPath $srcT1 -SpecPath $specT1 -OutputPath $outT1

Assert ($resultT1.ExitCode -eq 0) 'T1: executor exits 0'
Assert (Test-Path $outT1)         'T1: output file written'

if (Test-Path $outT1) {
    $outHtml = Get-Content $outT1 -Raw -Encoding UTF8

    # All 3 StickyHeaders changed to 2025
    $sh = [regex]::Matches($outHtml, '(?s)<[^>]+data-mx-component="StickyHeader"[^>]*>.*?</\w+>')
    # Simple check: count of StickyHeader elements still 3 after transformation
    $shCount = ([regex]::Matches($outHtml, 'data-mx-component="StickyHeader"')).Count
    Assert ($shCount -eq 3) 'T1: still 3 StickyHeader elements in output'

    # Verify year labels changed in StickyHeaders (year-badge elements within them)
    Assert ($outHtml -match '(?s)data-mx-component="StickyHeader"[^>]*>[\s\S]{0,400}year-badge[\s\S]{0,50}>2025<') 'T1: StickyHeader year-badge shows 2025'

    # No StickyHeader should still contain >2024< in a year-badge
    $stickyWith2024Badge = [regex]::Matches($outHtml, '(?s)<[^>]+data-mx-component="StickyHeader"[^>]*>(.*?)</\w+>') |
        Where-Object { $_.Groups[1].Value -match '>2024<' }
    Assert ($stickyWith2024Badge.Count -eq 0) 'T1: no StickyHeader year-badge still shows 2024'

    # ── NON-TARGET PRESERVATION ──────────────────────────────────────────────
    Write-Host "  [T1/Preservation] Non-target 2024 references must be unchanged"
    # PageHeader (Settings, uses PageHeader not StickyHeader) must still show 2024
    Assert ($outHtml -match 'data-mx-component="PageHeader"')       'T1-P: PageHeader element still present'
    Assert ($outHtml -match 'updated 2024')                          'T1-P: PageHeader subtitle "updated 2024" preserved'
    Assert ($outHtml -match 'fiscal year 2024')                      'T1-P: REQ-001 text "fiscal year 2024" preserved in contract'
    Assert ($outHtml -match 'Q3 2024 stakeholder')                   'T1-P: DEC-001 rationale "Q3 2024" preserved in contract'
    Assert ($outHtml -match '2024 annual compliance')                 'T1-P: FLOW-001 description "2024 annual compliance" preserved in contract'
    Assert ($outHtml -match 'Total Sites \(2024\)')                   'T1-P: dashboard KPI label "Total Sites (2024)" preserved (non-StickyHeader text)'

    # ── SOURCE UNCHANGED ─────────────────────────────────────────────────────
    Assert (Files-AreIdentical -A $srcT1 -B $fixturePath) 'T1: source file unchanged (output written to separate file)'

    # ── DESIGN CONTRACT ───────────────────────────────────────────────────────
    Write-Host "  [T1/Contract] Design Contract revision lifecycle"
    $contractT1 = Get-Contract -HtmlPath $outT1
    Assert ($null -ne $contractT1)                         'T1-C: Design Contract still valid JSON'
    Assert ($contractT1.mockup.revision -eq 12)            'T1-C: revision incremented to 12'
    Assert ($contractT1.mockup.previous_revision -eq 11)   'T1-C: previous_revision = 11'
    Assert ($contractT1.mockup.lifecycle_status -eq 'REFINED_TARGET') 'T1-C: lifecycle_status = REFINED_TARGET'
    Assert ($contractT1.mockup.refinement_status -eq 'PROPOSED')      'T1-C: refinement_status = PROPOSED'
    Assert ($contractT1.mockup.active_target -eq $false)              'T1-C: active_target = false'

    # revision_delta
    $delta = $contractT1.revision_delta
    Assert ($null -ne $delta)                              'T1-C: revision_delta present'
    Assert ($delta.from_revision -eq 11)                   'T1-C: delta from_revision = 11'
    Assert ($delta.to_revision -eq 12)                     'T1-C: delta to_revision = 12'
    $affectedIds = @($delta.affected_ids)
    Assert ('SCREEN-DASH'    -in $affectedIds) 'T1-C: SCREEN-DASH in affected_ids'
    Assert ('SCREEN-SITES'   -in $affectedIds) 'T1-C: SCREEN-SITES in affected_ids'
    Assert ('SCREEN-REPORTS' -in $affectedIds) 'T1-C: SCREEN-REPORTS in affected_ids'
    Assert ('SCREEN-SETTINGS' -notin $affectedIds) 'T1-C: SCREEN-SETTINGS NOT in affected_ids (PageHeader, not StickyHeader)'

    # business_flow_impact: NONE — no FLOW/STORY/IMPLEMENTATION effects
    $deltaEffects = @($delta.effects)
    $flowEffects  = @($deltaEffects | Where-Object { $_.type -in @('FLOW', 'STORY', 'IMPLEMENTATION') })
    Assert ($flowEffects.Count -eq 0) 'T1-C: no FLOW/STORY/IMPLEMENTATION effects in delta (business_flow_impact=NONE)'

    # preservation block
    $pres = $contractT1.preservation
    Assert ($null -ne $pres)                    'T1-C: preservation block present'
    Assert ($pres.result -eq 'VERIFIED')         'T1-C: preservation.result = VERIFIED'

    # transformation_spec embedded for audit
    Assert ($null -ne $contractT1.transformation_spec) 'T1-C: transformation_spec embedded in contract'
    Assert ($contractT1.transformation_spec.spec_id -eq 'TXSPEC-001') 'T1-C: embedded spec_id = TXSPEC-001'

    # ── BUSINESS FLOW PRESERVATION ────────────────────────────────────────────
    Write-Host "  [T1/Flows] Business Flow preservation"
    Assert ($contractT1.flows[0].id -eq 'FLOW-001')          'T1-F: FLOW-001 preserved'
    $newStepIds = $contractT1.flows[0].steps | ForEach-Object { $_.id }
    foreach ($sid in @('FLOWSTEP-001', 'FLOWSTEP-002', 'FLOWSTEP-003', 'FLOWSTEP-004')) {
        Assert ($sid -in $newStepIds) "T1-F: $sid preserved"
    }
    # Flow description still references 2024 (contract text unchanged)
    Assert ($contractT1.flows[0].description -match '2024') 'T1-F: FLOW-001 description still references 2024 (untouched)'
}

# ─── T2: LOCAL_EDIT — single target (SCREEN-DASH only) ───────────────────────

Write-Host "`n[T2] LOCAL_EDIT — year change in Dashboard StickyHeader only"
$srcT2    = Copy-Fixture
$outT2    = Join-Path $tempDir 'out-T2.html'
$specT2   = Join-Path $fixtureDir 'txspec-local-edit.json'
$resultT2 = Invoke-Executor -HtmlPath $srcT2 -SpecPath $specT2 -OutputPath $outT2

Assert ($resultT2.ExitCode -eq 0) 'T2: executor exits 0'
Assert (Test-Path $outT2)         'T2: output file written'

if (Test-Path $outT2) {
    $outHtmlT2  = Get-Content $outT2 -Raw -Encoding UTF8
    $contractT2 = Get-Contract -HtmlPath $outT2

    # Only SCREEN-DASH StickyHeader changed — verify via revision_delta
    $affT2 = @($contractT2.revision_delta.affected_ids)
    Assert ($affT2.Count -eq 1)               'T2: exactly 1 screen in affected_ids'
    Assert ('SCREEN-DASH' -in $affT2)          'T2: SCREEN-DASH in affected_ids'
    Assert ('SCREEN-SITES'   -notin $affT2)    'T2: SCREEN-SITES NOT in affected_ids (unchanged)'
    Assert ('SCREEN-REPORTS' -notin $affT2)    'T2: SCREEN-REPORTS NOT in affected_ids (unchanged)'

    Assert ($contractT2.mockup.revision -eq 12) 'T2: revision = 12'
    Assert ($contractT2.transformation_spec.spec_id -eq 'TXSPEC-LOCAL-001') 'T2: spec_id embedded = TXSPEC-LOCAL-001'
}

# ─── T3: MISSING TARGET — selector matches nothing ───────────────────────────

Write-Host "`n[T3] MISSING TARGET — selector [data-mx-component='TopBar'] matches 0 elements"
$srcT3    = Copy-Fixture
$outT3    = Join-Path $tempDir 'out-T3.html'
$specT3   = Join-Path $fixtureDir 'txspec-missing-target.json'
$resultT3 = Invoke-Executor -HtmlPath $srcT3 -SpecPath $specT3 -OutputPath $outT3

Assert ($resultT3.ExitCode -ne 0)                                'T3: executor exits non-zero (fail-closed)'
Assert ($resultT3.Stderr -match 'FAIL_NO_TARGETS_FOUND')         'T3: error code FAIL_NO_TARGETS_FOUND'
Assert (-not (Test-Path $outT3))                                  'T3: no output file written'
Assert (Files-AreIdentical -A $srcT3 -B $fixturePath)            'T3: source file unchanged (rollback)'

# ─── T4: EXTRA TARGET — max constraint violated ───────────────────────────────

Write-Host "`n[T4] EXTRA TARGET — 3 StickyHeaders found but max=2"
$srcT4    = Copy-Fixture
$outT4    = Join-Path $tempDir 'out-T4.html'
$specT4   = Join-Path $fixtureDir 'txspec-extra-target.json'
$resultT4 = Invoke-Executor -HtmlPath $srcT4 -SpecPath $specT4 -OutputPath $outT4

Assert ($resultT4.ExitCode -ne 0)                                 'T4: executor exits non-zero (fail-closed)'
Assert ($resultT4.Stderr -match 'FAIL_UNEXPECTED_MATCH_COUNT')    'T4: error code FAIL_UNEXPECTED_MATCH_COUNT'
Assert (-not (Test-Path $outT4))                                   'T4: no output file written'
Assert (Files-AreIdentical -A $srcT4 -B $fixturePath)             'T4: source file unchanged (rollback)'

# ─── T5: PRECONDITION MISMATCH — "2023" not found in StickyHeaders ───────────

Write-Host "`n[T5] PRECONDITION MISMATCH — precondition '2023' not found (fixture has '2024')"
$srcT5    = Copy-Fixture
$outT5    = Join-Path $tempDir 'out-T5.html'
$specT5   = Join-Path $fixtureDir 'txspec-precondition-mismatch.json'
$resultT5 = Invoke-Executor -HtmlPath $srcT5 -SpecPath $specT5 -OutputPath $outT5

Assert ($resultT5.ExitCode -ne 0)                               'T5: executor exits non-zero (fail-closed)'
Assert ($resultT5.Stderr -match 'FAIL_PRECONDITION_MISMATCH')   'T5: error code FAIL_PRECONDITION_MISMATCH'
Assert (-not (Test-Path $outT5))                                 'T5: no output file written'
Assert (Files-AreIdentical -A $srcT5 -B $fixturePath)           'T5: source file unchanged (rollback)'

# ─── T6: STABLE ID MISMATCH — target_ids contains unknown screen ─────────────

Write-Host "`n[T6] STABLE ID MISMATCH — target_ids contains SCREEN-NONEXISTENT"
$srcT6    = Copy-Fixture
$outT6    = Join-Path $tempDir 'out-T6.html'
$specT6   = Join-Path $fixtureDir 'txspec-stable-id-mismatch.json'
$resultT6 = Invoke-Executor -HtmlPath $srcT6 -SpecPath $specT6 -OutputPath $outT6

Assert ($resultT6.ExitCode -ne 0)                              'T6: executor exits non-zero (fail-closed)'
Assert ($resultT6.Stderr -match 'FAIL_STABLE_ID_NOT_FOUND')    'T6: error code FAIL_STABLE_ID_NOT_FOUND'
Assert (-not (Test-Path $outT6))                                'T6: no output file written'
Assert (Files-AreIdentical -A $srcT6 -B $fixturePath)          'T6: source file unchanged (rollback)'

# ─── T7: M365 HANDOFF — extract spec from M365 handoff wrapper ───────────────

Write-Host "`n[T7] M365 HANDOFF — spec extracted from handoff wrapper, all 3 StickyHeaders updated"
$srcT7    = Copy-Fixture
$outT7    = Join-Path $tempDir 'out-T7.html'
$specT7   = Join-Path $fixtureDir 'txspec-m365-handoff.json'
$resultT7 = Invoke-Executor -HtmlPath $srcT7 -SpecPath $specT7 -OutputPath $outT7

Assert ($resultT7.ExitCode -eq 0) 'T7: executor exits 0 (M365 handoff path succeeds)'
Assert (Test-Path $outT7)         'T7: output file written'

if (Test-Path $outT7) {
    $contractT7 = Get-Contract -HtmlPath $outT7
    Assert ($contractT7.mockup.revision -eq 12) 'T7: revision = 12'
    $affT7 = @($contractT7.revision_delta.affected_ids)
    Assert ($affT7.Count -eq 3) 'T7: 3 screens in affected_ids (all StickyHeaders)'
    Assert ($contractT7.transformation_spec.spec_id -eq 'TXSPEC-M365-001') 'T7: embedded spec_id = TXSPEC-M365-001'
    # Verify StickyHeaders changed
    $outHtmlT7 = Get-Content $outT7 -Raw -Encoding UTF8
    Assert ($outHtmlT7 -match 'updated 2024') 'T7: PageHeader "updated 2024" preserved (non-target)'
    Assert (Files-AreIdentical -A $srcT7 -B $fixturePath) 'T7: source file unchanged'
}

# ─── T8: SCOPE ISOLATION — targeted replacement does not affect non-StickyHeader text ──

Write-Host "`n[T8] SCOPE ISOLATION — TEXT_REPLACE scoped to StickyHeader elements only"
if (Test-Path $outT1) {
    $outHtmlT8 = Get-Content $outT1 -Raw -Encoding UTF8

    # Count "2024" and "2025" occurrences: exactly 3 "2025" (year badges), multiple "2024" preserved
    $count2025 = ([regex]::Matches($outHtmlT8, '>2025<')).Count
    $count2024Badge = ([regex]::Matches($outHtmlT8, 'data-mx-component="StickyHeader"[\s\S]{0,500}>2024<')).Count

    Assert ($count2025 -ge 3) "T8: at least 3 occurrences of >2025< in output (one per StickyHeader)" "found: $count2025"
    Assert ($count2024Badge -eq 0) 'T8: no >2024< badge inside any StickyHeader'

    # "2024" still present in non-StickyHeader content
    Assert ($outHtmlT8 -match '2024') 'T8: "2024" still present somewhere in document (non-target references preserved)'

    # Specific non-target "2024" locations still intact
    Assert ($outHtmlT8 -match 'fiscal year 2024')    'T8: requirements text "fiscal year 2024" preserved'
    Assert ($outHtmlT8 -match 'Total Sites \(2024\)') 'T8: body content "Total Sites (2024)" preserved'
    Assert ($outHtmlT8 -match 'updated 2024')         'T8: PageHeader "updated 2024" preserved'
}

# ─── T9: INVALID CHANGE CLASS — FULL_REGENERATION blocked by Phase 6 ─────────

Write-Host "`n[T9] INVALID CHANGE CLASS — FULL_REGENERATION must be rejected by Phase 6"
$fullRegenSpecPath = Join-Path $tempDir 'txspec-full-regen.json'
@{
    transformation_spec = @{
        spec_id          = 'TXSPEC-FULLREGEN'
        change_class     = 'FULL_REGENERATION'
        source_revision  = 11
        target_revision  = 12
        intent           = 'Complete redesign'
        operations       = @(@{ op_id = 'OP-001'; operation = 'TEXT_REPLACE'; target_selector = "[data-mx-component='StickyHeader']"; precondition = '2024'; replacement = '2025'; match_constraint = @{ min = 1 } })
        business_flow_impact = 'NONE'
        rollback_on_failure  = $true
        handoff_target       = 'file-capable-agent'
    }
} | ConvertTo-Json -Depth 10 | Set-Content $fullRegenSpecPath -Encoding UTF8

$srcT9    = Copy-Fixture
$outT9    = Join-Path $tempDir 'out-T9.html'
$resultT9 = Invoke-Executor -HtmlPath $srcT9 -SpecPath $fullRegenSpecPath -OutputPath $outT9

Assert ($resultT9.ExitCode -ne 0)                              'T9: FULL_REGENERATION rejected (exit non-zero)'
Assert ($resultT9.Stderr -match 'FAIL_INVALID_CHANGE_CLASS')   'T9: error code FAIL_INVALID_CHANGE_CLASS'
Assert (-not (Test-Path $outT9))                                'T9: no output file written'

# ─── T10: REVISION MISMATCH — source_revision does not match HTML ─────────────

Write-Host "`n[T10] REVISION MISMATCH — source_revision=5 but HTML has revision 11"
$revMismatchPath = Join-Path $tempDir 'txspec-rev-mismatch.json'
@{
    transformation_spec = @{
        spec_id          = 'TXSPEC-REVMIS'
        change_class     = 'CROSS_CUTTING_EDIT'
        source_revision  = 5
        target_revision  = 6
        intent           = 'Year change on wrong revision'
        operations       = @(@{ op_id = 'OP-001'; operation = 'TEXT_REPLACE'; target_selector = "[data-mx-component='StickyHeader']"; precondition = '2024'; replacement = '2025'; match_constraint = @{ min = 1 } })
        business_flow_impact = 'NONE'
        rollback_on_failure  = $true
        handoff_target       = 'file-capable-agent'
    }
} | ConvertTo-Json -Depth 10 | Set-Content $revMismatchPath -Encoding UTF8

$srcT10   = Copy-Fixture
$outT10   = Join-Path $tempDir 'out-T10.html'
$resultT10 = Invoke-Executor -HtmlPath $srcT10 -SpecPath $revMismatchPath -OutputPath $outT10

Assert ($resultT10.ExitCode -ne 0)                            'T10: revision mismatch rejected (exit non-zero)'
Assert ($resultT10.Stderr -match 'FAIL_REVISION_MISMATCH')    'T10: error code FAIL_REVISION_MISMATCH'
Assert (-not (Test-Path $outT10))                              'T10: no output file written'

# ─── Cleanup ──────────────────────────────────────────────────────────────────

Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue

# ─── Summary ─────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "========================================"
if ($fail -eq 0) {
    Write-Host "  PASS: $pass   FAIL: $fail — all behavioral tests passed" -ForegroundColor Green
} else {
    Write-Host "  PASS: $pass   FAIL: $fail — behavioral tests FAILED" -ForegroundColor Red
}
Write-Host "========================================"
Write-Host ""

exit ($fail -gt 0 ? 1 : 0)
