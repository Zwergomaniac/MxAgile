#Requires -Version 7
# MxAgile Encoding Safety + Project Name Materialization — Tier 0 static validation
# Validates that the managed-file pipeline uses explicit UTF-8 I/O (no host-default
# Get-Content calls), that project-name materialization is implemented, and that
# system-check covers template/encoding/legacy-reference detection.
# Run from repository root:  pwsh tests/test-encoding-safety.ps1

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

Write-Host "`nEncoding Safety + Project Name Materialization — $RepoRoot" -ForegroundColor Cyan

# ──────────────────────────────────────────────────────────────
# A  apply-project-agent-instructions.ps1: encoding read paths
# ──────────────────────────────────────────────────────────────
Write-Host "`n[A] apply-project-agent-instructions.ps1: explicit UTF-8 reads"
$apply = Get-Content (Join-Path $RepoRoot 'scripts\apply-project-agent-instructions.ps1') -Raw -Encoding UTF8
Assert ($apply -match 'Utf8WithoutBom') 'A1: UTF-8 NoBOM encoding object defined'
Assert ($apply -match 'ReadAllText') 'A2: uses ReadAllText for file reads (not Get-Content -Raw without encoding)'
Assert ($apply -notmatch 'Get-Content -LiteralPath \$FilePath -Raw|Get-Content -LiteralPath \$SourcePath -Raw|Get-Content -LiteralPath \$GitIgnorePath -Raw') 'A3: no bare Get-Content -Raw calls remaining in read paths'
Assert ($apply -match 'WriteAllText.*Utf8WithoutBom') 'A4: uses WriteAllText with Utf8WithoutBom for writes'
Assert ($apply -match 'UTF8Encoding.*false|new\(\$false\)') 'A5: UTF-8 NoBOM instantiated with BOM=false'

# ──────────────────────────────────────────────────────────────
# B  apply-project-agent-instructions.ps1: project name materialization
# ──────────────────────────────────────────────────────────────
Write-Host "`n[B] apply-project-agent-instructions.ps1: project name materialization"
Assert ($apply -match 'Read-ProjectName|ReadProjectName') 'B1: Read-ProjectName function defined'
Assert ($apply -match 'Materialize-ProjectName|MaterializeProjectName') 'B2: Materialize-ProjectName function defined'
Assert ($apply -match 'mxagile-project\.yaml') 'B3: reads mxagile-project.yaml for project name'
Assert ($apply -match '\[PROJEKTNAME\]') 'B4: handles [PROJEKTNAME] placeholder detection'
Assert ($apply -match "skillssource.*AGENTS\.md|AGENTS\.md.*skillssource") 'B5: materializes skillssource/AGENTS.md'
Assert ($apply -match 'projekt\.md') 'B6: materializes projekt.md'
Assert ($apply -match '\.Replace\(') 'B7: uses literal string Replace (not regex) for safe substitution'

# ──────────────────────────────────────────────────────────────
# C  mxagile-init.ps1: mxagile-project.yaml template includes name placeholder
# ──────────────────────────────────────────────────────────────
Write-Host "`n[C] mxagile-init.ps1: mxagile-project.yaml includes name field"
$init = Get-Content (Join-Path $RepoRoot 'scripts\mxagile-init.ps1') -Raw -Encoding UTF8
Assert ($init -match "name:.*\[PROJEKTNAME\]|name.*PROJEKTNAME") 'C1: mxagile-project.yaml template includes name: "[PROJEKTNAME]"'
Assert ($init -match 'UTF8Encoding.*false|WriteAllText.*UTF8Encoding') 'C2: mxagile-project.yaml written with UTF-8 NoBOM'

# ──────────────────────────────────────────────────────────────
# D  install-core.ps1: materializes project name from .mpr filename
# ──────────────────────────────────────────────────────────────
Write-Host "`n[D] install-core.ps1: project name from .mpr"
$ic = Get-Content (Join-Path $RepoRoot 'scripts\install-core.ps1') -Raw -Encoding UTF8
Assert ($ic -match 'mprProjectName|GetFileNameWithoutExtension') 'D1: extracts project name from .mpr filename'
Assert ($ic -match 'PROJEKTNAME.*mprProjectName|mprProjectName.*PROJEKTNAME|Replace.*PROJEKTNAME') 'D2: materializes [PROJEKTNAME] in mxagile-project.yaml'
Assert ($ic -match 'mxagile-project\.yaml') 'D3: reads/writes mxagile-project.yaml'

# ──────────────────────────────────────────────────────────────
# E  mxagile-project.schema.json: name property defined
# ──────────────────────────────────────────────────────────────
Write-Host "`n[E] mxagile-project.schema.json: name property"
$schema = Get-Content (Join-Path $RepoRoot '.mxagile\schemas\mxagile-project.schema.json') -Raw -Encoding UTF8
Assert ($schema -match '"name"') 'E1: schema defines name property'
Assert ($schema -match '"type":\s*"string"') 'E2: name is string type'
Assert ($schema -match 'display name|materialized|PROJEKTNAME') 'E3: schema documents materialization purpose'

# ──────────────────────────────────────────────────────────────
# F  system-check.md: template health section
# ──────────────────────────────────────────────────────────────
Write-Host "`n[F] system-check.md: project template health section"
$sc = Get-Content (Join-Path $RepoRoot '.mxagile\skills\system-check.md') -Raw -Encoding UTF8
Assert ($sc -match '## L\.\s*Project Template Health') 'F1: has Section L: Project Template Health'
Assert ($sc -match 'UNRESOLVED_TEMPLATE_VALUE') 'F2: defines UNRESOLVED_TEMPLATE_VALUE status'
Assert ($sc -match 'PROJECT_AUTHORING_REQUIRED') 'F3: defines PROJECT_AUTHORING_REQUIRED status'
Assert ($sc -match 'LEGACY_REFERENCE') 'F4: defines LEGACY_REFERENCE status'
Assert ($sc -match 'ENCODING_CORRUPTION_SUSPECTED') 'F5: defines ENCODING_CORRUPTION_SUSPECTED status'
Assert ($sc -match '\.dfc-ai/') 'F6: detects .dfc-ai legacy path references'
Assert ($sc -match 'mojibake|CP1252|Ã¤|Ã¶|encoding.*corruption|corruption.*encoding') 'F7: identifies mojibake/encoding corruption patterns'
Assert ($sc -match 'project_template_health') 'F8: machine-readable YAML has project_template_health block'
Assert ($sc -match 'Do not.*auto.*repair|Do not attempt.*repair|not.*attempt.*repair') 'F9: does not attempt automatic mojibake repair'

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
