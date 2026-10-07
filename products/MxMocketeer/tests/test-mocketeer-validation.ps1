#Requires -Version 7
# MxMocketeer static validation — Tier 0
# Validates required files, system prompt size, golden mockup structure and JSON,
# company-neutral content, and knowledge file completeness.
# Run from repository root:  pwsh products/MxMocketeer/tests/test-mocketeer-validation.ps1

param(
    [string]$ProductRoot = (Join-Path $PSScriptRoot '..')
)

$ProductRoot = (Resolve-Path $ProductRoot).Path
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

Write-Host "`nMxMocketeer Validation — $ProductRoot" -ForegroundColor Cyan

# ──────────────────────────────────────────────────────────────
# 1  Required files
# ──────────────────────────────────────────────────────────────
Write-Host "`n[1] Required files exist"
$required = @(
    'README.md',
    'system-prompt.md',
    'suggested-prompts.md',
    'agent-builder-setup.md',
    'knowledge/design-contract.txt',
    'knowledge/discovery-assessment.txt',
    'knowledge/mendix-design-guide.txt',
    'knowledge/mxagile-handoff.txt',
    'knowledge/golden-mockuphtml.txt',
    'tests/preservation-acceptance.md'
)
foreach ($rel in $required) {
    $p = Join-Path $ProductRoot $rel
    Assert (Test-Path $p) "Exists: $rel"
}

# ──────────────────────────────────────────────────────────────
# 2  System prompt character count
# ──────────────────────────────────────────────────────────────
Write-Host "`n[2] System prompt within M365 character limit (8 000)"
$promptPath = Join-Path $ProductRoot 'system-prompt.md'
if (Test-Path $promptPath) {
    $chars = (Get-Content $promptPath -Raw -Encoding UTF8).Length
    Write-Host "    Character count: $chars"
    Assert ($chars -le 8000) "System prompt <= 8 000 characters" "actual: $chars"
}

# ──────────────────────────────────────────────────────────────
# 3  Golden mockup HTML structure (in .txt file)
# ──────────────────────────────────────────────────────────────
Write-Host "`n[3] Golden mockup HTML structure (knowledge/golden-mockuphtml.txt)"
$gmPath = Join-Path $ProductRoot 'knowledge/golden-mockuphtml.txt'
if (Test-Path $gmPath) {
    $html = Get-Content $gmPath -Raw -Encoding UTF8

    # Complete HTML document
    Assert ($html -match '(?i)<!doctype html>')                 'Contains <!doctype html>'
    Assert ($html -match '(?i)<html')                           'Contains <html> element'
    Assert ($html -match '(?i)<head')                           'Contains <head> element'
    Assert ($html -match '(?i)<body')                           'Contains <body> element'

    # Embedded CSS
    Assert ($html -match '(?i)<style')                          'Contains embedded <style>'

    # Embedded JavaScript
    Assert ($html -match '(?i)<script')                         'Contains embedded <script>'
    Assert ($html -notmatch 'src="https?://')                   'No external script src (self-contained)'
    Assert ($html -notmatch 'href="https?://')                  'No external stylesheet href (self-contained)'

    # Design Contract
    Assert ($html -match 'MXMOCKETEER DESIGN CONTRACT')         'Contains MXMOCKETEER DESIGN CONTRACT comment'
    Assert ($html -match 'Contract-Version: 1')                 'Contract-Version: 1 present'
    Assert ($html -match 'id="mocketeer-spec"')                 'id="mocketeer-spec" present'

    # Contract fields
    Assert ($html -match '"schema_version"')                    'schema_version in JSON'
    Assert ($html -match '"revision"')                          'revision in JSON'
    Assert ($html -match '"previous_revision"')                 'previous_revision in JSON'
    Assert ($html -match '"change_scope"')                      'change_scope in JSON'
    Assert ($html -match '"requirements"')                      'requirements in JSON'
    Assert ($html -match '"decisions"')                         'decisions in JSON'
    Assert ($html -match '"roles"')                             'roles in JSON'
    Assert ($html -match '"screens"')                           'screens in JSON'
    Assert ($html -match '"flows"')                             'flows in JSON'
    Assert ($html -match '"traceability"')                      'traceability in JSON'

    # Traceability attributes
    Assert ($html -match 'data-mx-req')                         'data-mx-req traceability attribute used'
    Assert ($html -match 'data-mx-screen')                      'data-mx-screen traceability attribute used'
    Assert ($html -match 'data-mx-role')                        'data-mx-role traceability attribute used'

    # Human-readable spec footer
    Assert ($html -match 'spec-footer')                         'spec-footer details element present'
}

# ──────────────────────────────────────────────────────────────
# 4  JSON is valid and structurally complete
# ──────────────────────────────────────────────────────────────
Write-Host "`n[4] Golden mockup embedded JSON"
if (Test-Path $gmPath) {
    $html = Get-Content $gmPath -Raw -Encoding UTF8
    if ($html -match '(?s)<script[^>]*id="mocketeer-spec"[^>]*>(.*?)</script>') {
        $json = $Matches[1].Trim()
        try {
            $c = $json | ConvertFrom-Json -ErrorAction Stop
            Assert $true 'JSON parses without error'

            Assert ($null -ne $c.schema_version)       'schema_version present'
            Assert ($null -ne $c.mockup)                'mockup object present'
            Assert ($null -ne $c.mockup.id)             'mockup.id present'
            Assert ($c.mockup.revision -ge 1)           'mockup.revision >= 1'
            Assert ($null -ne $c.roles)                 'roles array present'
            Assert ($c.roles.Count -ge 2)               "at least 2 roles ($($c.roles.Count) found)"
            Assert ($null -ne $c.requirements)          'requirements array present'
            Assert ($c.requirements.Count -ge 1)        "at least 1 requirement ($($c.requirements.Count) found)"
            Assert ($null -ne $c.decisions)             'decisions array present'
            Assert ($c.decisions.Count -ge 1)           "at least 1 decision ($($c.decisions.Count) found)"
            Assert ($null -ne $c.screens)               'screens array present'
            Assert ($c.screens.Count -ge 1)             "at least 1 screen ($($c.screens.Count) found)"
            Assert ($null -ne $c.flows)                 'flows array present'
            Assert ($null -ne $c.traceability)          'traceability array present'

            # Every role must have can[] and cannot[]
            foreach ($role in $c.roles) {
                Assert ($null -ne $role.can)    "Role $($role.id) has can[]"
                Assert ($null -ne $role.cannot) "Role $($role.id) has cannot[]"
            }

            # Unique IDs (requirements, decisions, roles, screens, flows)
            $allIds = @()
            $allIds += @($c.requirements | ForEach-Object { $_.id })
            $allIds += @($c.decisions    | ForEach-Object { $_.id })
            $allIds += @($c.roles        | ForEach-Object { $_.id })
            $allIds += @($c.screens      | ForEach-Object { $_.id })
            $allIds += @($c.flows        | ForEach-Object { $_.id })
            $dupes = $allIds | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name }
            Assert ($dupes.Count -eq 0) "No duplicate IDs across requirements/decisions/roles/screens/flows" ($dupes -join ', ')

            # Traceability references must resolve
            $reqIds  = @($c.requirements | ForEach-Object { $_.id })
            $decIds  = @($c.decisions    | ForEach-Object { $_.id })
            $roleIds = @($c.roles        | ForEach-Object { $_.id })
            foreach ($tr in $c.traceability) {
                if ($tr.requirement_ref) {
                    Assert ($reqIds -contains $tr.requirement_ref) `
                        "Traceability.requirement_ref $($tr.requirement_ref) resolves"
                }
                foreach ($d in $tr.decision_refs) {
                    Assert ($decIds -contains $d) "Traceability.decision_ref $d resolves"
                }
                foreach ($r in $tr.role_refs) {
                    Assert ($roleIds -contains $r) "Traceability.role_ref $r resolves"
                }
            }

            # Decision affected_requirements must resolve
            foreach ($dec in $c.decisions) {
                foreach ($ref in $dec.affected_requirements) {
                    Assert ($reqIds -contains $ref) "DEC $($dec.id).affected_requirements $ref resolves"
                }
            }

        } catch {
            Assert $false "JSON parses without error" "$_"
        }
    } else {
        Assert $false 'mocketeer-spec script block found in golden mockup'
    }
}

# ──────────────────────────────────────────────────────────────
# 5  No company-specific content in product files
# ──────────────────────────────────────────────────────────────
Write-Host "`n[5] No company-specific content"
$banned = @(
    'Mercedes', 'mercedes', 'Daimler', 'daimler',
    'MBUI', 'MB_UI', 'MB_SSO', 'MBTech',
    'CapTrack', 'KidsCompass',
    'mbrepo', 'mercedes-benz'
)
$testsDir = Join-Path $ProductRoot 'tests'
$allProductFiles = Get-ChildItem $ProductRoot -Recurse -File |
    Where-Object { -not $_.FullName.StartsWith($testsDir) }  # exclude test scripts (they reference terms as test strings)
foreach ($term in $banned) {
    $hits = $allProductFiles | Where-Object {
        (Get-Content $_.FullName -Raw -Encoding UTF8 -ErrorAction SilentlyContinue) -match [regex]::Escape($term)
    } | ForEach-Object { $_.Name }
    Assert ($hits.Count -eq 0) "No '$term' in product files" ($hits -join ', ')
}

# ──────────────────────────────────────────────────────────────
# 6  Knowledge files non-empty
# ──────────────────────────────────────────────────────────────
Write-Host "`n[6] Knowledge files non-empty"
$knowledgeFiles = @(
    'knowledge/design-contract.txt',
    'knowledge/discovery-assessment.txt',
    'knowledge/mendix-design-guide.txt',
    'knowledge/mxagile-handoff.txt',
    'knowledge/golden-mockuphtml.txt'
)
foreach ($rel in $knowledgeFiles) {
    $p = Join-Path $ProductRoot $rel
    if (Test-Path $p) {
        $len = (Get-Content $p -Raw -Encoding UTF8).Length
        Assert ($len -gt 100) "Non-empty: $rel" "$len chars"
    }
}

# ──────────────────────────────────────────────────────────────
# 7  System prompt safety margin
# ──────────────────────────────────────────────────────────────
Write-Host "`n[7] System prompt safety margin (>= 100 chars remaining)"
if (Test-Path $promptPath) {
    $remaining = 8000 - $chars
    Write-Host "    Remaining margin: $remaining characters"
    Assert ($remaining -ge 100) "System prompt has >= 100 chars safety margin" "remaining: $remaining"
    Assert ($remaining -le 7900) "System prompt not suspiciously empty" "remaining: $remaining"
}

# ──────────────────────────────────────────────────────────────
# 8  System prompt discipline — behavior split
# ──────────────────────────────────────────────────────────────
Write-Host "`n[8] System prompt discipline — key invariants present, taxonomy not duplicated"
$promptContent = if (Test-Path $promptPath) { Get-Content $promptPath -Raw -Encoding UTF8 } else { '' }

# Critical invariants must be in system prompt
Assert ($promptContent -match 'prototype_readiness|prototype.*readiness') 'System prompt mentions prototype_readiness'
Assert ($promptContent -match 'development_handoff_readiness|handoff.*readiness') 'System prompt mentions development_handoff_readiness'
Assert ($promptContent -match 'never invent|Never invent|do not invent') 'System prompt contains "never invent" invariant'
Assert ($promptContent -match 'Guided Interview|guided.*interview|adaptive.*interview') 'System prompt mentions guided interview'
Assert ($promptContent -match 'HANDOFF_READY|handoff.*ready') 'System prompt references HANDOFF_READY'

# Detailed taxonomy must NOT be duplicated — it lives in knowledge
$dimensionIds = @('DIM-PURPOSE_SCOPE','DIM-ROLES_CAPABILITIES','DIM-DATA_SEMANTICS','DIM-SECURITY_PRIVACY')
$dimInPrompt = $dimensionIds | Where-Object { $promptContent -match $_ } | Measure-Object | Select-Object -ExpandProperty Count
Assert ($dimInPrompt -eq 0) 'Detailed dimension IDs not duplicated in system prompt'

# ──────────────────────────────────────────────────────────────
# 9  design-contract.txt assessment schema
# ──────────────────────────────────────────────────────────────
Write-Host "`n[9] design-contract.txt assessment schema"
$dcPath = Join-Path $ProductRoot 'knowledge/design-contract.txt'
$dc = if (Test-Path $dcPath) { Get-Content $dcPath -Raw -Encoding UTF8 } else { '' }

Assert ($dc -match 'assessment') 'design-contract.txt defines assessment block'
Assert ($dc -match 'prototype_readiness') 'assessment contains prototype_readiness'
Assert ($dc -match 'development_handoff_readiness') 'assessment contains development_handoff_readiness'
Assert ($dc -match 'PROTOTYPE_READY') 'defines PROTOTYPE_READY readiness value'
Assert ($dc -match 'HANDOFF_READY') 'defines HANDOFF_READY readiness value'
Assert ($dc -match 'REFINEMENT_REQUIRED') 'defines REFINEMENT_REQUIRED readiness value'
Assert ($dc -match 'BLOCKED') 'defines BLOCKED readiness value'
Assert ($dc -match 'DIM-') 'defines dimension IDs'
Assert ($dc -match 'UNEXPLORED') 'defines UNEXPLORED dimension status'
Assert ($dc -match 'PARTIAL') 'defines PARTIAL dimension status'
Assert ($dc -match 'SUFFICIENT') 'defines SUFFICIENT dimension status'
Assert ($dc -match 'CONFLICTING') 'defines CONFLICTING dimension status'
Assert ($dc -match '"gaps"') 'assessment defines gaps array'
Assert ($dc -match 'GAP-') 'gap IDs use GAP- prefix pattern'
Assert ($dc -match 'blocking') 'gap has blocking field'
Assert ($dc -match 'blocks_handoff') 'gap has blocks_handoff field'
Assert ($dc -match 'next_exploration_areas') 'assessment has next_exploration_areas'
Assert ($dc -match 'backward-compatible optional') 'assessment documented as backward-compatible optional'
Assert ($dc -match 'CANNOT UPDATE.*CANNOT READ|CAN READ.*CAN UPDATE|inference') 'states operation inference prohibition'

# ──────────────────────────────────────────────────────────────
# 10  discovery-assessment.txt content
# ──────────────────────────────────────────────────────────────
Write-Host "`n[10] discovery-assessment.txt content"
$daPath = Join-Path $ProductRoot 'knowledge/discovery-assessment.txt'
$da = if (Test-Path $daPath) { Get-Content $daPath -Raw -Encoding UTF8 } else { '' }

Assert ($da -match 'PROTOTYPE_READINESS|PROTOTYPE_READY') 'defines prototype readiness'
Assert ($da -match 'DEVELOPMENT_HANDOFF_READINESS|HANDOFF_READY') 'defines handoff readiness'
Assert ($da -match 'Handoff Readiness Requirements') 'defines handoff readiness requirements'
Assert ($da -match 'Adaptive Interview|adaptive.*interview') 'defines adaptive interview strategy'
Assert ($da -match 'Unknown.*Open Answer|I don.*t know') 'handles unknown answers'
Assert ($da -match 'business language|business.*question') 'requires business-language questions'
Assert ($da -match 'blocking.*gap|blocks_handoff') 'defines blocking gap semantics'
Assert ($da -match 'SECURITY_UNCLEAR|PRIVACY_UNCLEAR') 'addresses security/privacy gaps'
Assert ($da -match 'READ.*UPDATE.*independently|independently.*derived') 'operation independence rule'
Assert ($da -match 'User-Facing Maturity Summary|maturity.*summary') 'defines user-facing summary'
Assert ($da -match 'Assessment Is Not the Interview') 'separates assessment from interview'
Assert ($da -match 'Provenance|provenance') 'addresses provenance recording'
Assert ($da -match 'Iteration Model|iteration.*model') 'defines iterative lifecycle'
Assert ($da -match 'overall.*percentage|percentage.*score|false.*quantitative' -or
        $da -match 'Not.*percent|no.*percent') 'avoids deceptive percentage scores'

# ──────────────────────────────────────────────────────────────
# 11  Golden mockup assessment block validation
# ──────────────────────────────────────────────────────────────
Write-Host "`n[11] Golden mockup assessment block"
if (Test-Path $gmPath) {
    $html2 = Get-Content $gmPath -Raw -Encoding UTF8
    if ($html2 -match '(?s)<script[^>]*id="mocketeer-spec"[^>]*>(.*?)</script>') {
        try {
            $c2 = $Matches[1].Trim() | ConvertFrom-Json -ErrorAction Stop

            Assert ($null -ne $c2.assessment) 'golden mockup has assessment block'
            Assert ($c2.assessment.prototype_readiness -eq 'PROTOTYPE_READY') 'golden mockup prototype_readiness is PROTOTYPE_READY'
            Assert ($c2.assessment.development_handoff_readiness -ne 'HANDOFF_READY') 'golden mockup dev handoff not prematurely HANDOFF_READY'
            Assert ($c2.assessment.development_handoff_readiness -match 'REFINEMENT_REQUIRED|BLOCKED') 'golden mockup shows appropriate partial maturity'
            Assert ($null -ne $c2.assessment.dimensions) 'assessment has dimensions array'
            Assert ($c2.assessment.dimensions.Count -ge 6) "assessment has >= 6 dimensions ($($c2.assessment.dimensions.Count) found)"
            Assert ($null -ne $c2.assessment.gaps) 'assessment has gaps array'
            Assert ($c2.assessment.gaps.Count -ge 1) "at least 1 gap ($($c2.assessment.gaps.Count) found)"
            Assert ($null -ne $c2.assessment.blocking_gaps) 'assessment has blocking_gaps'
            Assert ($null -ne $c2.assessment.next_exploration_areas) 'assessment has next_exploration_areas'

            # Gap IDs must be unique
            $gapIds = @($c2.assessment.gaps | ForEach-Object { $_.id })
            $dupGaps = $gapIds | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name }
            Assert ($dupGaps.Count -eq 0) 'No duplicate gap IDs' ($dupGaps -join ', ')

            # blocking_gaps must reference existing gap IDs
            foreach ($bgRef in $c2.assessment.blocking_gaps) {
                Assert ($gapIds -contains $bgRef) "blocking_gap $bgRef references existing gap"
            }

            # At least one blocking gap
            Assert ($c2.assessment.blocking_gaps.Count -ge 1) 'At least one blocking gap present'

            # At least one non-blocking gap (so we can test both coexisting)
            $nonBlockingGaps = $c2.assessment.gaps | Where-Object { $_.blocking -eq $false -or $_.blocks_handoff -eq $false }
            Assert ($nonBlockingGaps.Count -ge 1) 'At least one non-blocking gap (coexists with blocking)'

            # Dimension statuses include at least one PARTIAL or UNEXPLORED (showing honest partial state)
            $partialDims = $c2.assessment.dimensions | Where-Object { $_.status -in @('PARTIAL','UNEXPLORED') }
            Assert ($partialDims.Count -ge 1) "At least one PARTIAL or UNEXPLORED dimension (honest maturity)"

            # No UNEXPLORED falsely equated to RESOLVED — check resolution_state
            $unresolvedGaps = $c2.assessment.gaps | Where-Object { $_.resolution_state -eq 'OPEN' }
            Assert ($unresolvedGaps.Count -ge 1) 'At least one OPEN gap remains (prototype-in-progress)'

            # assessed_revision must match mockup.revision
            Assert ($c2.assessment.assessed_revision -eq $c2.mockup.revision) 'assessed_revision matches mockup.revision'

            # Third role (ROLE-DEPTMGR) demonstrates operation-aware capability uncertainty
            $deptMgr = $c2.roles | Where-Object { $_.id -eq 'ROLE-DEPTMGR' }
            Assert ($null -ne $deptMgr) 'Golden mockup includes a role with uncertain data scope'
            Assert ($deptMgr.status -match 'ASSUMPTION_REQUIRES_APPROVAL|OPEN') 'Uncertain role has appropriate status'

        } catch {
            Assert $false 'Golden mockup assessment block JSON valid' "$_"
        }
    }
}

# ──────────────────────────────────────────────────────────────
# 12  mxagile-handoff.txt maturity integration
# ──────────────────────────────────────────────────────────────
Write-Host "`n[12] mxagile-handoff.txt maturity integration"
$mhPath = Join-Path $ProductRoot 'knowledge/mxagile-handoff.txt'
$mh = if (Test-Path $mhPath) { Get-Content $mhPath -Raw -Encoding UTF8 } else { '' }

Assert ($mh -match 'HANDOFF_READY.*not.*bypass|not.*bypass.*HANDOFF_READY|gates remain.*authoritative') 'states HANDOFF_READY does not bypass MxAgile gates'
Assert ($mh -match 'REFINEMENT_REQUIRED') 'references REFINEMENT_REQUIRED intake'
Assert ($mh -match 'gap.*provenance|provenance.*gap|gap_ref') 'addresses gap provenance'
Assert ($mh -match 'later revision|revision.*reconcil|reconcil') 'addresses revision reconciliation'
Assert ($mh -match 'beautiful.*prototype.*not.*automatically|prototype.*not.*development-ready') 'states prototype is not automatically development-ready'

# ──────────────────────────────────────────────────────────────
# 13  Impact-based security priority and prompt safety margin
# ──────────────────────────────────────────────────────────────
Write-Host "`n[13] Impact-based security priority and prompt safety margin"

# A: material impact language present
Assert ($da -match 'materially affect') 'A: material-impact language present in security priority rule'

# B: non-material/out-of-scope security gaps not automatically HIGH
Assert ($da -match 'Not automatically HIGH|not automatically HIGH') 'B: non-material security gaps not automatically HIGH'

# C: category alone does not determine blocks_handoff
Assert ($da -match 'Category alone|category alone') 'C: category alone does not determine blocks_handoff'

# E: system prompt maintainability target <= 7400 (report; non-blocking)
$sp2 = Get-Content $promptPath -Raw -Encoding UTF8
$spLen2 = $sp2.Length
$maintTarget = 7400
Write-Host "    System prompt length: $spLen2 chars (maintainability target: ≤$maintTarget)"
if ($spLen2 -le $maintTarget) {
    Write-Host "  PASS  E: system prompt within maintainability target ($spLen2 ≤ $maintTarget)" -ForegroundColor Green
    $script:pass++
} else {
    Write-Host "  WARN  E: system prompt $spLen2 exceeds maintainability target $maintTarget (still within 8000 hard limit)" -ForegroundColor Yellow
    $script:pass++
}

# F: critical invariants remain in system prompt after compression
Assert ($sp2 -match 'does NOT automatically mean HANDOFF_READY') 'F: visually-complete ≠ HANDOFF_READY preserved in prompt'
Assert ($sp2 -match 'business-language') 'F: business-language requirement preserved in prompt'
Assert ($sp2 -match 'OPEN/UNKNOWN') 'F: OPEN/UNKNOWN recording invariant preserved in prompt'
Assert ($sp2 -match 'never invent an answer') 'F: never-invent-answer invariant preserved in prompt'
Assert ($sp2 -match 'readiness rules') 'F: HANDOFF_READY readiness-rules reference preserved in prompt'

# G: detailed methodology remains in Knowledge (not removed by prompt compression)
Assert ($da -match 'Handoff Readiness Requirements') 'G: handoff readiness requirements checklist in Knowledge'
Assert ($da -match 'DIM-PURPOSE_SCOPE') 'G: dimension IDs remain in Knowledge'
Assert ($da -match 'Adaptive Interview Strategy') 'G: adaptive interview strategy in Knowledge'
Assert ($da -match 'Risk-Based Exploration') 'G: risk-based exploration guidance in Knowledge'

# ──────────────────────────────────────────────────────────────
# 14  Product boundary — MxMocketeer is a KG producer, not a consumer
# ──────────────────────────────────────────────────────────────
Write-Host "`n[14] Product boundary — MxMocketeer is a KG producer, not a consumer"

$spBound  = if (Test-Path $promptPath) { Get-Content $promptPath -Raw -Encoding UTF8 } else { '' }
$mhBound  = if (Test-Path $mhPath) { Get-Content $mhPath -Raw -Encoding UTF8 } else { '' }
$setupPath = Join-Path $ProductRoot 'agent-builder-setup.md'
$setupBound = if (Test-Path $setupPath) { Get-Content $setupPath -Raw -Encoding UTF8 } else { '' }

# System prompt must contain producer-side graph output guidance
Assert ($spBound -match 'graph-ready|graph-indexable|Graph-Ready') `
    'System prompt: graph-ready output guidance present (producer boundary)'

# System prompt must NOT reference KG consumer operations
Assert ($spBound -notmatch 'neighbors\(\)') `
    'System prompt: neighbors() absent (KG consumer operations not in M365 prompt)'
Assert ($spBound -notmatch 'paths\(\)') `
    'System prompt: paths() absent (KG consumer operations not in M365 prompt)'
Assert ($spBound -notmatch 'affected\(\)') `
    'System prompt: affected() absent (KG consumer operations not in M365 prompt)'
Assert ($spBound -notmatch 'graph freshness|graph.*stale|stale.*graph') `
    'System prompt: graph freshness not referenced (KG consumer boundary)'
Assert ($spBound -notmatch 'provider.*none|provider.*graphify') `
    'System prompt: graph provider not referenced (KG consumer boundary)'

# mxagile-handoff.txt must NOT instruct MxMocketeer to call graph operations
Assert ($mhBound -notmatch 'affected\(FLOW-NNN\)') `
    'mxagile-handoff: direct affected(FLOW-NNN) call removed (downstream pipeline responsibility)'
Assert ($mhBound -notmatch 'graph status\(\)|status\(\) returns current') `
    'mxagile-handoff: graph status() consumer call absent'
Assert ($mhBound -notmatch 'build_artifact_index') `
    'mxagile-handoff: build_artifact_index call absent (downstream pipeline responsibility)'

# M365 package must NOT include knowledge-graph.txt as an upload file
Assert ($setupBound -notmatch '^\d+\.\s.*knowledge-graph\.txt') `
    'M365 package: knowledge-graph.txt not in numbered upload list'

# ──────────────────────────────────────────────────────────────
# 15  Transformation spec capability — edit classification present
# ──────────────────────────────────────────────────────────────
Write-Host "`n[15] Transformation spec capability"

$rtPath  = Join-Path $ProductRoot 'knowledge/refinement-transformations.txt'
$rtFile  = if (Test-Path $rtPath) { Get-Content $rtPath -Raw -Encoding UTF8 } else { '' }
$abPath  = Join-Path $ProductRoot 'agent-builder-setup.md'
$abFile  = if (Test-Path $abPath) { Get-Content $abPath -Raw -Encoding UTF8 } else { '' }

# New knowledge file exists and is non-empty
Assert (Test-Path $rtPath)          'knowledge/refinement-transformations.txt exists'
Assert ($rtFile.Length -gt 500)     'refinement-transformations.txt non-trivial content'

# Agent builder setup references the new file
Assert ($abFile -match 'refinement-transformations\.txt') 'agent-builder-setup.md references refinement-transformations.txt'
Assert ($abFile -match 'seven|7')                         'agent-builder-setup.md updated to seven knowledge files'

# All four edit classes defined
foreach ($class in @('LOCAL_EDIT', 'CROSS_CUTTING_EDIT', 'STRUCTURAL_REFACTOR', 'FULL_REGENERATION')) {
    Assert ($rtFile -match $class) "Edit class $class defined in refinement-transformations.txt"
}

# System prompt references the classification
Assert ($sp2 -match 'LOCAL_EDIT')                     'System prompt references LOCAL_EDIT classification'
Assert ($sp2 -match 'CROSS_CUTTING_EDIT')             'System prompt references CROSS_CUTTING_EDIT classification'
Assert ($sp2 -match 'Refinement Transformations')     'System prompt references knowledge "Refinement Transformations"'
Assert ($sp2 -match 'Transformation Spec')            'System prompt references Transformation Spec'

# Key safety invariant present in system prompt
Assert ($sp2 -match 'no unsafe reconstruction|unsafe reconstruction|do NOT attempt unsafe') 'System prompt: unsafe reconstruction prohibition present'

# Classification invariant: CROSS_CUTTING_EDIT must not become FULL_REGENERATION
Assert ($sp2 -match 'Never.*CROSS_CUTTING.*FULL_REGENERATION|CROSS_CUTTING.*FULL_REGENERATION.*numerous' -or
        $rtFile -match 'Never.*CROSS_CUTTING.*FULL_REGENERATION') 'CROSS_CUTTING_EDIT → FULL_REGENERATION misclassification prevented'

# Transformation Spec schema complete
Assert ($rtFile -match '"spec_id"')         'Transformation Spec defines spec_id field'
Assert ($rtFile -match '"change_class"')    'Transformation Spec defines change_class field'
Assert ($rtFile -match '"operations"')      'Transformation Spec defines operations array'
Assert ($rtFile -match '"precondition"')    'Transformation Spec defines precondition field'
Assert ($rtFile -match '"match_constraint"') 'Transformation Spec defines match_constraint'

# Handoff format defined (machine-readable for file-capable agent)
Assert ($rtFile -match 'Handoff Format|handoff.*format') 'Handoff Format section defined'
Assert ($rtFile -match 'mocketeer-transformation-spec') 'Handoff uses mocketeer-transformation-spec element'

# Preservation validation documented
Assert ($rtFile -match 'TARGET REGION|NON.TARGET REGION')  'Preservation target/non-target regions defined'
Assert ($rtFile -match 'VERIFIED.*VERIFIED_WITH_LEDGER|PARTIAL_EVIDENCE') 'Preservation result classes defined'

# StickyHeader fixture present as canonical cross-cutting case
Assert ($rtFile -match 'StickyHeader')     'StickyHeader year-change fixture present'

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
