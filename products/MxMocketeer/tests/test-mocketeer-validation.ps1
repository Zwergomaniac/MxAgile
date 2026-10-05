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
