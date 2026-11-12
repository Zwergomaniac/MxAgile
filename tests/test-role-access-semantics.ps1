<#
.SYNOPSIS
    Role/Access Semantics Tests

.DESCRIPTION
    Verifies that structured access dimensions are defined in the test-contract schema
    and that the vocabulary is organization-neutral.

    P1 REV-014 hardening: structured access semantics for VISIBLE/NAVIGABLE/READ/WRITE/MANAGE.

    Tests:
      - test-contract schema defines access_dimensions
      - access_dimensions vocabulary: VISIBLE, NAVIGABLE, READ, WRITE, MANAGE, PLATFORM_OWNED
      - access_dimensions is optional (backward compatible)
      - intake policy defines STRUCTURED ACCESS SEMANTICS
      - fixtures demonstrate: READ, WRITE, NAVIGABLE without WRITE
      - no real project role names in schema or fixtures
#>

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$TestsDir = $PSScriptRoot
$RepoRoot = Split-Path -Parent $TestsDir
$PassCount = 0
$FailCount = 0
$FailDetails = @()

function Assert-True {
    param([string]$TestName, [bool]$Condition, [string]$Message = '')
    if ($Condition) {
        Write-Host "  PASS: $TestName" -ForegroundColor Green
        $script:PassCount++
    } else {
        Write-Host "  FAIL: $TestName -- $Message" -ForegroundColor Red
        $script:FailCount++
        $script:FailDetails += "[$TestName] $Message"
    }
}
function Assert-FileContains {
    param([string]$TestName, [string]$FilePath, [string]$Pattern)
    $content = Get-Content -LiteralPath $FilePath -Raw -ErrorAction SilentlyContinue
    if ($null -eq $content) { Assert-True $TestName $false "File not found: $FilePath" }
    else { Assert-True $TestName ($content -match $Pattern) "Pattern '$Pattern' not found in $FilePath" }
}
function Assert-FileNotContains {
    param([string]$TestName, [string]$FilePath, [string]$Pattern)
    if (-not (Test-Path -LiteralPath $FilePath)) { Assert-True $TestName $false "File not found: $FilePath"; return }
    $content = [System.IO.File]::ReadAllText($FilePath)
    Assert-True $TestName ($content -notmatch $Pattern) "Forbidden pattern '$Pattern' found in $FilePath"
}
function Assert-FileExists {
    param([string]$TestName, [string]$FilePath)
    Assert-True $TestName (Test-Path -LiteralPath $FilePath) "File not found: $FilePath"
}

$TcSchema     = Join-Path $RepoRoot '.mxagile/schemas/test-contract.schema.json'
$IntakePolicy = Join-Path $RepoRoot '.mxagile/policies/design-contract-intake.md'
$RoleIdentityPolicy = Join-Path $RepoRoot '.mxagile/policies/implementation-control.md'
$ImplementationAgent = Join-Path $RepoRoot '.mxagile/agents/implementation-agent.md'
$UiAgent = Join-Path $RepoRoot '.mxagile/agents/ui-agent.md'
$AcceptanceAgent = Join-Path $RepoRoot '.mxagile/agents/acceptance-agent.md'
$MocketeerAgent = Join-Path $RepoRoot '.mxagile/agents/mocketeer-agent.md'
$MaintainerAgent = Join-Path $RepoRoot '.mxagile/agents/maintainer.md'
$BrownfieldSkill = Join-Path $RepoRoot '.mxagile/skills/brownfield-adoption.md'
$MocketeerGuide = Join-Path $RepoRoot 'products/MxMocketeer/skills/mocketeer-mockup-generation/SKILL.md'
$MocketeerPrompt = Join-Path $RepoRoot 'products/MxMocketeer/system-prompt.md'
$FixAccess    = Join-Path $RepoRoot 'tests/fixtures/role-access-semantics/fixture-access-dimensions.yaml'

# ─────────────────────────────────────────────────────────────────────────────
# SCHEMA: access_dimensions defined
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "SCHEMA: access_dimensions in test-contract proof_point" -ForegroundColor Cyan

Assert-FileContains "test-contract schema has access_dimensions" $TcSchema "access_dimensions"
Assert-FileContains "access_dimensions has VISIBLE" $TcSchema '"VISIBLE"'
Assert-FileContains "access_dimensions has NAVIGABLE" $TcSchema '"NAVIGABLE"'
Assert-FileContains "access_dimensions has READ" $TcSchema '"READ"'
Assert-FileContains "access_dimensions has WRITE" $TcSchema '"WRITE"'
Assert-FileContains "access_dimensions has MANAGE" $TcSchema '"MANAGE"'
Assert-FileContains "access_dimensions has PLATFORM_OWNED" $TcSchema '"PLATFORM_OWNED"'
Assert-FileContains "access_dimensions is backward compatible (optional)" $TcSchema "Backward compatible"

# ─────────────────────────────────────────────────────────────────────────────
# POLICY: STRUCTURED ACCESS SEMANTICS in intake policy
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "POLICY: STRUCTURED ACCESS SEMANTICS in design-contract-intake" -ForegroundColor Cyan

Assert-FileContains "intake policy has STRUCTURED ACCESS SEMANTICS section" $IntakePolicy "STRUCTURED ACCESS SEMANTICS"
Assert-FileContains "intake policy defines VISIBLE" $IntakePolicy "VISIBLE"
Assert-FileContains "intake policy defines NAVIGABLE" $IntakePolicy "NAVIGABLE"
Assert-FileContains "intake policy defines PLATFORM_OWNED" $IntakePolicy "PLATFORM_OWNED"
Assert-FileContains "intake policy: access_dimensions is optional" $IntakePolicy "access_dimensions.*OPTIONAL|OPTIONAL.*access_dimensions"
Assert-FileContains "intake policy: organization-neutral" $IntakePolicy "organization-neutral|organisation-neutral"
Assert-FileContains "intake policy: NAVIGABLE without WRITE" $IntakePolicy "NAVIGABLE.*without.*WRITE|NAVIGABLE.*no.*mutation"

# ─────────────────────────────────────────────────────────────────────────────
# PURITY: no real project roles in schema or fixtures
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "PURITY: no real project role names in schema" -ForegroundColor Cyan

Assert-FileNotContains "schema does not contain Example Project roles" $TcSchema "SITE_MANAGER|AppAdmin|CeKo|Eintragung"
Assert-FileNotContains "schema does not contain Mercedes roles" $TcSchema "MB_|Mercedes"

# ─────────────────────────────────────────────────────────────────────────────
# FIXTURE: access dimensions scenarios
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "FIXTURE: access dimensions scenarios" -ForegroundColor Cyan

Assert-FileExists "access dimensions fixture exists" $FixAccess
$fixAccessContent = Get-Content -LiteralPath $FixAccess -Raw -ErrorAction SilentlyContinue
Assert-True "fixture has ROLE-A READ only" ($fixAccessContent -match "access_dimensions: \[READ\]|ROLE-A.*READ")
Assert-True "fixture has ROLE-B READ+WRITE" ($fixAccessContent -match "READ.*WRITE|WRITE.*READ")
Assert-True "fixture has ROLE-C VISIBLE+NAVIGABLE without WRITE" ($fixAccessContent -match "VISIBLE.*NAVIGABLE|NAVIGABLE.*VISIBLE")
Assert-True "fixture: ROLE-C has no WRITE" ($fixAccessContent -match "no mutation authority|zonder.*mutation")
Assert-True "fixture has PLATFORM_OWNED example" ($fixAccessContent -match "PLATFORM_OWNED")
Assert-True "fixture: backward compatibility documented" ($fixAccessContent -match "backward_compatibility")
Assert-True "fixture: organization neutrality documented" ($fixAccessContent -match "organization_neutrality")
Assert-True "fixture uses generic ROLE-A not real project roles" ($fixAccessContent -match "ROLE-A")
Assert-FileNotContains "fixture does not contain real project roles" $FixAccess "SITE_MANAGER|AppAdmin|CeKo|Company Layer"

# ─────────────────────────────────────────────────────────────────────────────
# BACKWARD COMPATIBILITY: existing proof points valid without access_dimensions
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "BACKWARD COMPATIBILITY: access_dimensions optional" -ForegroundColor Cyan

Assert-FileContains "intake policy: absence of access_dimensions does not invalidate" $IntakePolicy "Backward compatible|backward.*compat"

# ─────────────────────────────────────────────────────────────────────────────
# MENDIX ROLE IDENTITY: system variable, not free-text or fuzzy matching
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "MENDIX ROLE IDENTITY: model-bound XPath reference" -ForegroundColor Cyan

Assert-FileContains "R1: policy uses the Mendix UserRole system variable" $RoleIdentityPolicy '\[%UserRole_Developer%\]'
Assert-FileContains "R1: policy uses the model association identity" $RoleIdentityPolicy 'System\.UserRoles/System\.UserRole\[id ='
Assert-FileContains "R1: policy rejects UserRole.Name comparisons" $RoleIdentityPolicy 'rather than comparing `System\.UserRole\.Name` to free text'
Assert-FileContains "R2: role rename requires model revalidation" $RoleIdentityPolicy 'After a User Role rename'
Assert-FileContains "R2: rename-aware refactoring is not assumed" $RoleIdentityPolicy 'does not, by itself, guarantee rename-aware refactoring'
Assert-FileContains "R3: wildcard and contains matching are forbidden" $RoleIdentityPolicy 'Never use wildcard, `contains\(\)`'
Assert-FileContains "role identity remains distinct from business capability" $RoleIdentityPolicy 'UserRole identity is not business capability'
Assert-FileContains "business scope and lifecycle rules are preserved" $RoleIdentityPolicy 'scope or lifecycle checks'

Assert-FileContains "Implementation Agent consumes the role policy" $ImplementationAgent 'policies/implementation-control\.md'
Assert-FileContains "Builder Kit route consumes the same role rule" $ImplementationAgent 'identity rule applies to Builder Kit output and every other implementation route'
Assert-FileContains "UI Agent consumes the role policy" $UiAgent 'policies/implementation-control\.md'
Assert-FileContains "Acceptance Agent consumes the role policy" $AcceptanceAgent 'policies/implementation-control\.md'
Assert-FileContains "Maintainer consumes the role policy for compatibility repairs" $MaintainerAgent 'policies/implementation-control\.md'
Assert-FileContains "Brownfield adoption preserves model-bound role identity" $BrownfieldSkill 'policies/implementation-control\.md'
Assert-FileContains "Mocketeer Agent preserves the implementation boundary" $MocketeerAgent 'policies/implementation-control\.md'
Assert-FileContains "Mocketeer Agent prominently identifies the UserRole handoff" $MocketeerAgent 'Wichtiger UserRole-Identity-Handoff'
Assert-FileContains "Mocketeer handoff names the Design Guide skill" $MocketeerAgent '.mxagile/skills/mocketeer-mockup-generation/SKILL\.md'
Assert-FileContains "Mocketeer handoff protects the prompt length limit" $MocketeerAgent '8,000-character hard limit and 100-character'
Assert-FileContains "Mocketeer design guidance rejects free-text role predicates" $MocketeerGuide 'not instructions to compare `System\.UserRole\.Name`'
Assert-FileContains "Mocketeer prompt points to the Mendix Design Guide skill" $MocketeerPrompt 'Role security: follow `mocketeer-mockup-generation`'

# ─────────────────────────────────────────────────────────────────────────────
# SUMMARY
# ─────────────────────────────────────────────────────────────────────────────
$total = $PassCount + $FailCount
Write-Host ""
Write-Host "=" * 70
Write-Host "RESULTS: $PassCount passed, $FailCount failed out of $total tests"
if ($FailCount -gt 0) {
    Write-Host ""
    Write-Host "FAILURES:" -ForegroundColor Red
    $FailDetails | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    exit 1
} else {
    Write-Host "All tests PASSED" -ForegroundColor Green
    exit 0
}
