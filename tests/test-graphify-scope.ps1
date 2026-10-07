#Requires -Version 7
# Tier 0 static / synthetic regression tests for the Graphify targeted-scope contract.
# No graphify binary, no network, no LLM calls.  All tests use in-memory fixtures.
#
# Tests A–J encode the TARGETED TECHNICAL STRUCTURAL ENRICHMENT operating contract
# derived from the FULL_REPO vs TARGETED A/B comparison.

try {

    $ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path $MyInvocation.MyCommand.Path -Parent }
    $RepoRoot  = Join-Path $ScriptDir '..'

    function Assert-Condition {
        param ($Condition, $Message)
        if (-not $Condition) { throw "Assertion Failed: $Message" }
    }

    # ── Test A: Fresh-clone — Graphify absent → normal MxAgile config present ─────
    Write-Host "[TEST A] Fresh-clone: MxAgile config exists and has enrichment_provider: none"
    $configPath = Join-Path $RepoRoot '.mxagile' 'config.yaml'
    Assert-Condition (Test-Path $configPath) ".mxagile/config.yaml not found — required for MxAgile to operate"
    $configContent = Get-Content $configPath -Raw
    Assert-Condition ($configContent -match 'enrichment_provider') "enrichment_provider key missing from .mxagile/config.yaml"
    Assert-Condition ($configContent -match 'enrichment_provider\s*:\s*none') "enrichment_provider must default to 'none' — Graphify must be disabled by default"
    Write-Host "[PASS A] enrichment_provider: none confirmed — Graphify disabled by default"

    # ── Test B: Graphify disabled → provider.py must detect and fail-safe ──────────
    Write-Host "[TEST B] graphify_provider.py has _is_enabled() that checks enrichment_provider"
    $providerPath = Join-Path $RepoRoot 'scripts' 'graphify_provider.py'
    Assert-Condition (Test-Path $providerPath) "scripts/graphify_provider.py not found"
    $providerContent = Get-Content $providerPath -Raw
    Assert-Condition ($providerContent -match '_is_enabled') "_is_enabled() method not found in graphify_provider.py"
    Assert-Condition ($providerContent -match "enrichment_provider.*graphify") "enrichment_provider check not found in _is_enabled()"
    Assert-Condition ($providerContent -match "Graphify not enabled") "fail-safe return for disabled state not found in build()"
    Write-Host "[PASS B] _is_enabled() guard and fail-safe return confirmed"

    # ── Test C: .graphifyignore committed at repo root ─────────────────────────────
    Write-Host "[TEST C] .graphifyignore exists at repo root"
    $ignorePath = Join-Path $RepoRoot '.graphifyignore'
    Assert-Condition (Test-Path $ignorePath) ".graphifyignore not found at repo root — targeted scope not committed"
    $ignoreContent = Get-Content $ignorePath -Raw
    Assert-Condition ($ignoreContent.Length -gt 0) ".graphifyignore is empty — scope definition missing"
    Write-Host "[PASS C] .graphifyignore exists and is non-empty"

    # ── Test D: Noise paths are excluded from targeted scope ──────────────────────
    Write-Host "[TEST D] .graphifyignore excludes known noise surfaces"
    Assert-Condition ($ignoreContent -match '\.mxagile/schemas/') ".mxagile/schemas/ not excluded — JSON Schema noise will pollute graph"
    Assert-Condition ($ignoreContent -match '\.mxagile/agents/') ".mxagile/agents/ not excluded — markdown noise"
    Assert-Condition ($ignoreContent -match '\.mxagile/skills/') ".mxagile/skills/ not excluded — markdown noise"
    Assert-Condition ($ignoreContent -match '\.mxagile/policies/') ".mxagile/policies/ not excluded — markdown noise"
    Assert-Condition ($ignoreContent -match 'docs/') "docs/ not excluded — narrative markdown noise"
    Assert-Condition ($ignoreContent -match 'planning/') "planning/ not excluded — canonical YAML belongs in native graph only"
    Assert-Condition ($ignoreContent -match 'graphify-out') "graphify-out* not excluded — self-indexing contamination risk"
    Write-Host "[PASS D] All required noise surfaces excluded from .graphifyignore"

    # ── Test E: Technical code surfaces are NOT excluded ──────────────────────────
    Write-Host "[TEST E] scripts/ and tests/ are not excluded by .graphifyignore"
    # .graphifyignore must not contain lines that would exclude scripts/ or tests/
    # Parse meaningful exclusion lines (non-comment, non-blank)
    $exclusionLines = $ignoreContent -split "`n" |
        Where-Object { $_ -notmatch '^\s*#' -and $_.Trim() -ne '' }
    $scriptsExcluded = $exclusionLines | Where-Object {
        $line = $_.Trim()
        $line -eq 'scripts/' -or $line -eq 'scripts' -or $line -eq '/scripts/' -or $line -eq '/scripts'
    }
    $testsExcluded = $exclusionLines | Where-Object {
        $line = $_.Trim()
        $line -eq 'tests/' -or $line -eq 'tests' -or $line -eq '/tests/' -or $line -eq '/tests'
    }
    Assert-Condition ($null -eq $scriptsExcluded -or @($scriptsExcluded).Count -eq 0) "scripts/ is excluded from .graphifyignore — this removes the primary code surface"
    Assert-Condition ($null -eq $testsExcluded  -or @($testsExcluded).Count  -eq 0) "tests/ is excluded from .graphifyignore — removes test code surface"
    Write-Host "[PASS E] scripts/ and tests/ are not excluded — code surfaces preserved"

    # ── Test F: graphify-out/ remains untracked (gitignored) ──────────────────────
    Write-Host "[TEST F] graphify-out/ is gitignored"
    $gitignorePath = Join-Path $RepoRoot '.gitignore'
    Assert-Condition (Test-Path $gitignorePath) ".gitignore not found at repo root"
    $gitignoreContent = Get-Content $gitignorePath -Raw
    Assert-Condition ($gitignoreContent -match 'graphify-out') "graphify-out not found in .gitignore — generated graphs could be committed accidentally"
    Write-Host "[PASS F] graphify-out/ is gitignored"

    # ── Test G: Default config has Graphify disabled ───────────────────────────────
    Write-Host "[TEST G] Default config has graphify.enabled: false"
    Assert-Condition ($configContent -match 'enabled\s*:\s*false') "graphify.enabled: false not found in .mxagile/config.yaml"
    Write-Host "[PASS G] graphify.enabled: false confirmed"

    # ── Test H: Scope fingerprint mechanism is implemented in graphify_provider.py ─
    Write-Host "[TEST H] Scope fingerprint safety mechanism is implemented"
    Assert-Condition ($providerContent -match '_compute_scope_fingerprint') "_compute_scope_fingerprint() not found in graphify_provider.py"
    Assert-Condition ($providerContent -match '_read_stored_scope_fingerprint') "_read_stored_scope_fingerprint() not found"
    Assert-Condition ($providerContent -match '_write_scope_fingerprint') "_write_scope_fingerprint() not found"
    Assert-Condition ($providerContent -match 'scope_fingerprint') "scope_fingerprint not referenced in build() body"
    Assert-Condition ($providerContent -match 'shutil.rmtree') "shutil.rmtree not found — graphify-out wipe logic missing from build()"
    Write-Host "[PASS H] Scope fingerprint mechanism implemented (compute, read, write, wipe)"

    # ── Test I: Native Artifact Graph config is independent of Graphify state ──────
    Write-Host "[TEST I] Native Artifact Graph config does not depend on Graphify"
    # The schema for graphify-state.yaml must not be required for native graph startup
    $nativeGraphPath = Join-Path $RepoRoot 'scripts' 'resolve_impact.py'
    if (Test-Path $nativeGraphPath) {
        $nativeContent = Get-Content $nativeGraphPath -Raw
        Assert-Condition (-not ($nativeContent -match 'graphify_provider' -and $nativeContent -match 'import.*graphify')) `
            "resolve_impact.py imports graphify_provider — native graph must not depend on optional enrichment"
    }
    # Config must have enrichment_provider: none (already checked in A/G, double-confirm here)
    Assert-Condition ($configContent -match 'enrichment_provider\s*:\s*none') "enrichment_provider must be 'none' — native graph must be independent"
    Write-Host "[PASS I] Native Artifact Graph independence from Graphify confirmed"

    # ── Test J: scope_fingerprint field exists in graphify-state schema ────────────
    Write-Host "[TEST J] graphify-state.schema.json includes scope_fingerprint field"
    $schemaPath = Join-Path $RepoRoot '.mxagile' 'schemas' 'graphify-state.schema.json'
    Assert-Condition (Test-Path $schemaPath) ".mxagile/schemas/graphify-state.schema.json not found"
    $schemaContent = Get-Content $schemaPath -Raw
    Assert-Condition ($schemaContent -match 'scope_fingerprint') "scope_fingerprint not declared in graphify-state.schema.json — schema lags implementation"
    Assert-Condition ($schemaContent -match 'SHA-256') "scope_fingerprint description missing SHA-256 mention — contract underdocumented"
    Write-Host "[PASS J] scope_fingerprint field present in graphify-state schema"

} catch {
    Write-Error "A test failed: $_"
    exit 1
} finally {
    # Tier 0: no temp directories created, nothing to clean up
}

Write-Host ""
Write-Host "[OK] All 10 tests in test-graphify-scope.ps1 passed (A–J)."
exit 0
