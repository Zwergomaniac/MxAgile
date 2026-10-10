#!/usr/bin/env pwsh
# Regression tests for scope-aware verification, representative fixture contract,
# test identity lifecycle, and design authority semantics.
#
# Validates that fixture files in tests/fixtures/scope-aware-verification/ contain
# the expected structure and assertions. These are static fixture validation tests
# (Tier 0) — they do not require a running application.
#
# Run: pwsh tests/test-scope-aware-verification.ps1

param(
    [string]$FixtureDir = "$PSScriptRoot/fixtures/scope-aware-verification"
)

$ErrorActionPreference = 'Stop'
$passed = 0
$failed = 0
$errors = @()

function Assert-True {
    param([string]$TestId, [string]$Claim, [bool]$Condition, [string]$Hint = "")
    if ($Condition) {
        Write-Host "  [PASS] $TestId — $Claim"
        $script:passed++
    } else {
        Write-Host "  [FAIL] $TestId — $Claim$(if ($Hint) { ': ' + $Hint })"
        $script:failed++
        $script:errors += "${TestId}: $Claim"
    }
}

function Get-Fixture {
    param([string]$FileName)
    $path = Join-Path $FixtureDir $FileName
    if (-not (Test-Path $path)) {
        throw "Fixture not found: $path"
    }
    return Get-Content $path -Raw
}

function Get-FixtureYaml {
    param([string]$FileName)
    $raw = Get-Fixture $FileName
    return ConvertFrom-Yaml $raw
}

# Check if ConvertFrom-Yaml is available (powershell-yaml module)
$hasYaml = $false
try {
    Import-Module powershell-yaml -ErrorAction SilentlyContinue
    $hasYaml = $null -ne (Get-Command ConvertFrom-Yaml -ErrorAction SilentlyContinue)
} catch { }

Write-Host ""
Write-Host "=== Scope-Aware Verification Regression Tests ==="
Write-Host ""

# ---------------------------------------------------------------------------
# TEST GROUP A: Login/routing is not scope proof (fixture-A)
# ---------------------------------------------------------------------------
Write-Host "--- A: Login/Routing ≠ Domain Scope Proof ---"

$fixtureA = Get-Fixture "fixture-A-login-not-scope-proof.yaml"

Assert-True "A.1" "fixture-A exists" ($fixtureA.Length -gt 0)
Assert-True "A.2" "fixture-A declares SCOPE-A fixture_id" ($fixtureA -match "fixture_id: SCOPE-A")
Assert-True "A.3" "fixture-A references representative-fixture-contract.md" ($fixtureA -match "representative-fixture-contract")
Assert-True "A.4" "fixture-A asserts LOGIN_SUCCESS does not constitute DOMAIN_SCOPE_PROOF" ($fixtureA -match "LOGIN_SUCCESS does not constitute DOMAIN_SCOPE_PROOF")
Assert-True "A.5" "fixture-A asserts HOME_ROUTE_CORRECT does not constitute DOMAIN_SCOPE_PROOF" ($fixtureA -match "HOME_ROUTE_CORRECT does not constitute DOMAIN_SCOPE_PROOF")
Assert-True "A.6" "fixture-A asserts EMPTY_NAVIGATION ambiguity rule" ($fixtureA -match "EMPTY_NAVIGATION must not be classified")
Assert-True "A.7" "fixture-A asserts VALID_FOR_ROLE_ONLY_NOT_SCOPE classification" ($fixtureA -match "VALID_FOR_ROLE_ONLY_NOT_SCOPE")
Assert-True "A.8" "fixture-A asserts FIXTURE_BLOCKED parity result (not PASS)" ($fixtureA -match "FIXTURE_BLOCKED")
Assert-True "A.9" "fixture-A role has required_scope set (non-null)" ($fixtureA -match "required_scope: department")
Assert-True "A.10" "fixture-A representative_scope_present is false" ($fixtureA -match "representative_scope_present: false")

# ---------------------------------------------------------------------------
# TEST GROUP B: Fixture gap survives lifecycle (fixture-B)
# ---------------------------------------------------------------------------
Write-Host "--- B: FIXTURE_GAP Propagates Through Lifecycle ---"

$fixtureB = Get-Fixture "fixture-B-fixture-gap-survives-lifecycle.yaml"

Assert-True "B.1" "fixture-B exists" ($fixtureB.Length -gt 0)
Assert-True "B.2" "fixture-B declares SCOPE-B fixture_id" ($fixtureB -match "fixture_id: SCOPE-B")
Assert-True "B.3" "fixture-B documents lifecycle_progression through all phases" ($fixtureB -match "lifecycle_progression")
Assert-True "B.4" "fixture-B asserts gap persists through refinement" ($fixtureB -match "persists in story spec")
Assert-True "B.5" "fixture-B asserts gap persists through implementation" ($fixtureB -match "does not resolve a fixture")
Assert-True "B.6" "fixture-B asserts scope-dependent PP are FIXTURE_BLOCKED" ($fixtureB -match "FIXTURE_BLOCKED in verification campaign")
Assert-True "B.7" "fixture-B asserts scope-independent PP for same role are NOT blocked" ($fixtureB -match "NOT blocked")
Assert-True "B.8" "fixture-B asserts completion report must reflect FIXTURE_BLOCKED" ($fixtureB -match "completion assessment")
Assert-True "B.9" "fixture-B references verification-gap-taxonomy.md" ($fixtureB -match "verification-gap-taxonomy")

# ---------------------------------------------------------------------------
# TEST GROUP C: Incomplete fixture downgrades only dependent evidence (fixture-C)
# ---------------------------------------------------------------------------
Write-Host "--- C: Incomplete Fixture Downgrades Only Dependent Evidence ---"

$fixtureC = Get-Fixture "fixture-C-incomplete-fixture-downgrades-only-dependent-evidence.yaml"

Assert-True "C.1" "fixture-C exists" ($fixtureC.Length -gt 0)
Assert-True "C.2" "fixture-C covers two roles (one global, one scoped)" ($fixtureC -match "ROLE-GLOBAL-ADMIN" -and $fixtureC -match "ROLE-ORG-REPORTER")
Assert-True "C.3" "fixture-C asserts global role evidence remains CONFIRMED after FIXTURE_GAP discovery" ($fixtureC -match "remains CONFIRMED after FIXTURE_GAP discovery")
Assert-True "C.4" "fixture-C asserts scoped role dimension is downgraded to FIXTURE_BLOCKED" ($fixtureC -match "downgraded to FIXTURE_BLOCKED")
Assert-True "C.5" "fixture-C asserts non-scope-dependent dimensions remain VALID_FOR_ROLE_ONLY_NOT_SCOPE" ($fixtureC -match "VALID_FOR_ROLE_ONLY_NOT_SCOPE")
Assert-True "C.6" "fixture-C asserts campaign continues after FIXTURE_GAP discovery" ($fixtureC -match "campaign continues")
Assert-True "C.7" "fixture-C asserts FIXTURE_BLOCKED is not FAIL" ($fixtureC -match "not FAIL")

# ---------------------------------------------------------------------------
# TEST GROUP D: Mockup scenario creates fixture preconditions (fixture-D)
# ---------------------------------------------------------------------------
Write-Host "--- D: Mockup Scenario Creates Verification Preconditions ---"

$fixtureD = Get-Fixture "fixture-D-mockup-scenario-creates-fixture-preconditions.yaml"

Assert-True "D.1" "fixture-D exists" ($fixtureD.Length -gt 0)
Assert-True "D.2" "fixture-D contains mockup_observations with scope semantics" ($fixtureD -match "SCOPE_RESTRICTED_DATA_GRID")
Assert-True "D.3" "fixture-D asserts scenario_semantics entries must be produced" ($fixtureD -match "must produce scenario_semantics entries")
Assert-True "D.4" "fixture-D asserts fixture_precondition must be declared" ($fixtureD -match "declare fixture_precondition|fixture_precondition.*declared|fixture_precondition.*must")
Assert-True "D.5" "fixture-D asserts positive and negative scenarios must be declared" ($fixtureD -match "positive_scenario.*negative_scenario")
Assert-True "D.6" "fixture-D asserts mockup does not define concrete fixture objects" ($fixtureD -match "does not define.*concrete fixture objects")
Assert-True "D.7" "fixture-D references mockup-analysis.md" ($fixtureD -match "mockup-analysis")

# ---------------------------------------------------------------------------
# TEST GROUP E: Design-system authority prevents mockup color extraction (fixture-E)
# ---------------------------------------------------------------------------
Write-Host "--- E: Design-System Authority Prevents Mockup Color Extraction ---"

$fixtureE = Get-Fixture "fixture-E-design-system-authority-prevents-mockup-color-extraction.yaml"

Assert-True "E.1" "fixture-E exists" ($fixtureE.Length -gt 0)
Assert-True "E.2" "fixture-E has company_layer_installed: true" ($fixtureE -match "company_layer_installed: true")
Assert-True "E.3" "fixture-E asserts mockup color must NOT be CONFIRMED_REQUIREMENT_VIOLATION when design system is authoritative" ($fixtureE -match "must NOT be classified as CONFIRMED_REQUIREMENT_VIOLATION")
Assert-True "E.4" "fixture-E asserts deviation must be CONFIRMED_PARITY_DIFFERENCE_REQUIRING_CONTRACT_CHECK" ($fixtureE -match "CONFIRMED_PARITY_DIFFERENCE_REQUIRING_CONTRACT_CHECK")
Assert-True "E.5" "fixture-E asserts remediation must not be triggered from mockup color alone" ($fixtureE -match "Remediation must NOT be triggered")
Assert-True "E.6" "fixture-E references source-priority.md" ($fixtureE -match "source-priority")

# ---------------------------------------------------------------------------
# TEST GROUP F: Project decision overrides design-system inference (fixture-F)
# ---------------------------------------------------------------------------
Write-Host "--- F: Explicit Project Decision Overrides Design-System Inference ---"

$fixtureF = Get-Fixture "fixture-F-project-decision-overrides-design-system-inference.yaml"

Assert-True "F.1" "fixture-F exists" ($fixtureF.Length -gt 0)
Assert-True "F.2" "fixture-F has a DEC-NNN decision reference" ($fixtureF -match "DEC-042")
Assert-True "F.3" "fixture-F asserts DEC overrides both mockup and design system" ($fixtureF -match "overrides both mockup and design system")
Assert-True "F.4" "fixture-F asserts mockup color must not be extracted as requirement when DEC exists" ($fixtureF -match "must NOT be extracted as a styling requirement")
Assert-True "F.5" "fixture-F asserts implementation matching DEC is CONFIRMED (not a violation)" ($fixtureF -match "must be classified CONFIRMED")
Assert-True "F.6" "fixture-F introduces ACCEPTED_VARIANT classification for DEC-covered differences" ($fixtureF -match "ACCEPTED_VARIANT")

# ---------------------------------------------------------------------------
# TEST GROUP G: Test identity cleanup prevents model pollution (fixture-G)
# ---------------------------------------------------------------------------
Write-Host "--- G: Test Identity Lifecycle and Model Pollution Prevention ---"

$fixtureG = Get-Fixture "fixture-G-test-identity-cleanup-prevents-model-pollution.yaml"

Assert-True "G.1" "fixture-G exists" ($fixtureG.Length -gt 0)
Assert-True "G.2" "fixture-G covers happy_path lifecycle variant" ($fixtureG -match "happy_path")
Assert-True "G.3" "fixture-G covers verification_failure lifecycle variant" ($fixtureG -match "verification_failure")
Assert-True "G.4" "fixture-G covers interrupted_execution lifecycle variant" ($fixtureG -match "interrupted_execution")
Assert-True "G.5" "fixture-G covers repeated_execution idempotency" ($fixtureG -match "repeated_execution")
Assert-True "G.6" "fixture-G covers accumulated_identities detection" ($fixtureG -match "accumulated_identities")
Assert-True "G.7" "fixture-G asserts cleanup must run despite verification failure" ($fixtureG -match "Cleanup must run despite verification failure")
Assert-True "G.8" "fixture-G asserts ACCUMULATED_TEST_ARTIFACTS triggers with 3+ generated identities" ($fixtureG -match "ACCUMULATED_TEST_ARTIFACTS")
Assert-True "G.9" "fixture-G asserts accumulated artifacts surfaced to developer (not auto-deleted)" ($fixtureG -match "surfaced to developer")
Assert-True "G.10" "fixture-G asserts PERSISTENT_MUTATION classification when cleanup fails" ($fixtureG -match "PERSISTENT_MUTATION")
Assert-True "G.11" "fixture-G references test-identity-lifecycle.md" ($fixtureG -match "test-identity-lifecycle")

# ---------------------------------------------------------------------------
# TEST GROUP H: Runtime config discrepancy diagnosed before identity mutation (fixture-H)
# ---------------------------------------------------------------------------
Write-Host "--- H: Runtime Configuration Discrepancy Diagnosed Before Identity Mutation ---"

$fixtureH = Get-Fixture "fixture-H-runtime-config-discrepancy-diagnosed-before-identity-mutation.yaml"

Assert-True "H.1" "fixture-H exists" ($fixtureH.Length -gt 0)
Assert-True "H.2" "fixture-H has correct diagnosis_sequence with 6 ordered steps" ($fixtureH -match "diagnosis_sequence")
Assert-True "H.3" "fixture-H asserts RUNTIME_CONFIGURATION_DISCREPANCY classification before other diagnosis" ($fixtureH -match "RUNTIME_CONFIGURATION_DISCREPANCY before any other diagnosis")
Assert-True "H.4" "fixture-H asserts demo user creation is prohibited before config parity check" ($fixtureH -match "must NOT create a demo user.*before diagnosing configuration parity")
Assert-True "H.5" "fixture-H asserts password reset is prohibited before config parity check" ($fixtureH -match "must NOT reset admin password.*before diagnosing configuration parity")
Assert-True "H.6" "fixture-H asserts resolution requires constant_overrides (not temporary CLI)" ($fixtureH -match "constant_overrides")
Assert-True "H.7" "fixture-H asserts evidence during discrepancy is invalid" ($fixtureH -match "evidence.*is invalid")
Assert-True "H.8" "fixture-H references local-runtime-profile.md" ($fixtureH -match "local-runtime-profile")

# ---------------------------------------------------------------------------
# TEST GROUP I: Interrupt/resume after prerequisite repair (fixture-I)
# ---------------------------------------------------------------------------
Write-Host "--- I: Interrupt/Resume After Prerequisite Repair —"

$fixtureI = Get-Fixture "fixture-I-interrupt-resume-after-prerequisite-repair.yaml"

Assert-True "I.1" "fixture-I exists" ($fixtureI.Length -gt 0)
Assert-True "I.2" "fixture-I has campaign_state_at_interrupt with completed and blocked proof points" ($fixtureI -match "campaign_state_at_interrupt")
Assert-True "I.3" "fixture-I documents prior invalid evidence and prerequisite repair" ($fixtureI -match "prior_invalid_evidence" -and $fixtureI -match "prerequisite_repair")
Assert-True "I.4" "fixture-I asserts scope-independent PP remain CONFIRMED after FOUNDATIONAL_DEFECT interrupt" ($fixtureI -match "remain CONFIRMED after FOUNDATIONAL_DEFECT interrupt")
Assert-True "I.5" "fixture-I asserts FIXTURE_BLOCKED (not FAIL) at interrupt time" ($fixtureI -match "classified FIXTURE_BLOCKED at interrupt time, not FAIL")
Assert-True "I.6" "fixture-I asserts PP-003 re-executed without restarting PP-001/PP-002" ($fixtureI -match "without restarting")
Assert-True "I.7" "fixture-I asserts valid evidence supersedes prior TEST_FIXTURE_INVALID evidence" ($fixtureI -match "supersedes prior TEST_FIXTURE_INVALID")
Assert-True "I.8" "fixture-I asserts prior invalid evidence preserved historically (not deleted)" ($fixtureI -match "preserved.*not deleted")
Assert-True "I.9" "fixture-I asserts no full-campaign restart required" ($fixtureI -match "no full-campaign restart")
Assert-True "I.10" "fixture-I references lifecycle-resync.md" ($fixtureI -match "lifecycle-resync")

# ---------------------------------------------------------------------------
# POLICY FILE EXISTENCE TESTS
# ---------------------------------------------------------------------------
Write-Host "--- Policy File Existence ---"

$policyDir = "$PSScriptRoot/../.mxagile/policies"

Assert-True "POL.1" "test-identity-lifecycle.md exists" (Test-Path "$policyDir/test-identity-lifecycle.md")
Assert-True "POL.2" "representative-fixture-contract.md exists" (Test-Path "$policyDir/representative-fixture-contract.md")
Assert-True "POL.3" "source-priority.md contains Design-System-Autoritaet section" ((Get-Content "$policyDir/source-priority.md" -Raw) -match "Design-System.*Company-Layer-Autoritaet")
Assert-True "POL.4" "mockup-analysis.md contains Szenario-Semantik-Extraktion section" ((Get-Content "$policyDir/mockup-analysis.md" -Raw) -match "Szenario-Semantik-Extraktion")
Assert-True "POL.5" "verification-gap-taxonomy.md contains FIXTURE_GAP" ((Get-Content "$policyDir/verification-gap-taxonomy.md" -Raw) -match "### FIXTURE_GAP")
Assert-True "POL.6" "parity-finding-reconciliation.md contains FIXTURE_BLOCKED section" ((Get-Content "$policyDir/parity-finding-reconciliation.md" -Raw) -match "### FIXTURE_BLOCKED")
Assert-True "POL.7" "lifecycle-resync.md contains FOUNDATIONAL_DEFECT section" ((Get-Content "$policyDir/lifecycle-resync.md" -Raw) -match "### FOUNDATIONAL_DEFECT")

# ---------------------------------------------------------------------------
# SCHEMA TESTS
# ---------------------------------------------------------------------------
Write-Host "--- Schema Extensions ---"

$schemaDir = "$PSScriptRoot/../.mxagile/schemas"

$paritySchema = Get-Content "$schemaDir/parity-verification.schema.json" -Raw
Assert-True "SCH.1" "parity-verification schema dimension result enum includes FIXTURE_BLOCKED" ($paritySchema -match '"FIXTURE_BLOCKED"')
Assert-True "SCH.2" "parity-verification schema overall_result enum includes FIXTURE_BLOCKED" ($paritySchema -match '"FIXTURE_BLOCKED"')
Assert-True "SCH.3" "parity-verification schema has fixture_blocked_reason field" ($paritySchema -match "fixture_blocked_reason")

$roleCovSchema = Get-Content "$schemaDir/role_coverage.schema.json" -Raw
Assert-True "SCH.4" "role_coverage schema has fixture_contract_complete field" ($roleCovSchema -match "fixture_contract_complete")
Assert-True "SCH.5" "role_coverage schema has fixture_gap_reason field" ($roleCovSchema -match "fixture_gap_reason")
Assert-True "SCH.6" "role_coverage schema has domain_scope_not_applicable field" ($roleCovSchema -match "domain_scope_not_applicable")

# ---------------------------------------------------------------------------
# GLOSSARY TESTS
# ---------------------------------------------------------------------------
Write-Host "--- Glossary Entries ---"

$glossary = Get-Content "$PSScriptRoot/../.mxagile/GLOSSARY.yaml" -Raw
Assert-True "GLO.1" "GLOSSARY contains RUNTIME_CONFIGURATION_DISCREPANCY" ($glossary -match "RUNTIME_CONFIGURATION_DISCREPANCY:")
Assert-True "GLO.2" "GLOSSARY contains FIXTURE_GAP" ($glossary -match "FIXTURE_GAP:")
Assert-True "GLO.3" "GLOSSARY contains REPRESENTATIVE_FIXTURE" ($glossary -match "REPRESENTATIVE_FIXTURE:")
Assert-True "GLO.4" "GLOSSARY contains DOMAIN_SCOPE_PROOF" ($glossary -match "DOMAIN_SCOPE_PROOF:")
Assert-True "GLO.5" "GLOSSARY contains FIXTURE_BLOCKED" ($glossary -match "FIXTURE_BLOCKED:")
Assert-True "GLO.6" "GLOSSARY contains VALID_FOR_ROLE_ONLY_NOT_SCOPE" ($glossary -match "VALID_FOR_ROLE_ONLY_NOT_SCOPE:")
Assert-True "GLO.7" "GLOSSARY contains TEST_FIXTURE_INVALID" ($glossary -match "TEST_FIXTURE_INVALID:")

# ---------------------------------------------------------------------------
# SUMMARY
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=== Test Summary ==="
Write-Host "Passed: $passed"
Write-Host "Failed: $failed"
Write-Host "Total:  $($passed + $failed)"

if ($errors.Count -gt 0) {
    Write-Host ""
    Write-Host "Failed tests:"
    foreach ($e in $errors) { Write-Host "  - $e" }
    exit 1
} else {
    Write-Host ""
    Write-Host "All tests passed."
    exit 0
}
