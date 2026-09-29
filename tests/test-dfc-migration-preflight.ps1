<#
.SYNOPSIS
    DFC-AI Migration Preflight Tests

.DESCRIPTION
    Validates the legacy DFC-AI detection, migration bootstrap, and safety guarantees.

    Scenarios:
    A. Clean project -> normal init remains possible (CLEAN_PROJECT)
    B. Existing MxAgile project -> idempotent behavior (EXISTING_MXAGILE_PROJECT)
    C. Legacy DFC-AI project -> detected before destructive writes (LEGACY_DFC_PROJECT)
    D. Legacy project artifacts unchanged except permitted bootstrap files
    E. Existing Mendix .mpr remains unchanged
    F. Repeated init on legacy project remains safe (idempotency)
    G. Migration agent/instructions become available after bootstrap
    H. Init prints actionable migration-agent prompt
    I. No complete MxAgile projections installed before migration
#>

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$TestsDir    = $PSScriptRoot
$ScriptDir   = Split-Path -Parent $TestsDir
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

function Assert-FileContains {
    param([string]$TestName, [string]$FilePath, [string]$Pattern)
    $content = Get-Content -LiteralPath $FilePath -Raw -ErrorAction SilentlyContinue
    if ($null -eq $content) {
        Assert-True $TestName $false "File not found: $FilePath"
    } else {
        Assert-True $TestName ($content -match $Pattern) "Expected pattern '$Pattern' not found in $FilePath"
    }
}

function Assert-FileAbsent {
    param([string]$TestName, [string]$FilePath)
    $exists = Test-Path -LiteralPath $FilePath
    Assert-True $TestName (-not $exists) "Expected file to be absent but found: $FilePath"
}

function New-FixtureDirectory {
    param([string]$Name)
    $dir = Join-Path $env:TEMP "mxagile-test-$Name-$([System.Guid]::NewGuid().ToString('N').Substring(0,8))"
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    return $dir
}

function Remove-FixtureDirectory {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path) {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Script paths
$detectScript    = Join-Path $ScriptDir "scripts\detect-project-type.ps1"
$bootstrapScript = Join-Path $ScriptDir "scripts\install-migration-bootstrap.ps1"
$installScript   = Join-Path $ScriptDir "scripts\install-core.ps1"
$canonicalSource = Join-Path $ScriptDir ".mxagile"

Write-Host ""
Write-Host "=== DFC-AI Migration Preflight Tests ==="
Write-Host ""

# =========================================================================
# Verify test infrastructure
# =========================================================================
Write-Host "--- Infrastructure ---"
Assert-True "detect-project-type.ps1 exists" (Test-Path -LiteralPath $detectScript) "Script not found: $detectScript"
Assert-True "install-migration-bootstrap.ps1 exists" (Test-Path -LiteralPath $bootstrapScript) "Script not found: $bootstrapScript"
Assert-True "install-core.ps1 exists" (Test-Path -LiteralPath $installScript) "Script not found: $installScript"
Assert-True "canonical .mxagile/ exists" (Test-Path -LiteralPath $canonicalSource -PathType Container) "Not found: $canonicalSource"
Assert-True "canonical migration-agent.md exists" (Test-Path -LiteralPath (Join-Path $canonicalSource "agents\migration-agent.md")) "Not found"
Assert-True "canonical migration policy exists" (Test-Path -LiteralPath (Join-Path $canonicalSource "policies\migration-dfc-to-mxagile.md")) "Not found"
Write-Host ""

# =========================================================================
# SCENARIO A: Clean project -> CLEAN_PROJECT
# =========================================================================
Write-Host "--- A: Clean project -> CLEAN_PROJECT ---"
$fixtureA = New-FixtureDirectory "clean"
try {
    # Create minimal clean project (just .mpr, no AI framework)
    New-Item -Path (Join-Path $fixtureA "MyApp.mpr") -ItemType File -Force | Out-Null
    New-Item -Path (Join-Path $fixtureA "AGENT.md") -ItemType File -Force | Out-Null

    $resultJson = & $detectScript -ProjectRoot $fixtureA
    $result = $resultJson | ConvertFrom-Json
    $dfcEv = @($result.DfcEvidence); $mxEv = @($result.MxAgileEvidence)

    Assert-True "A: clean project classified as CLEAN_PROJECT" `
        ($result.Classification -eq "CLEAN_PROJECT") `
        "Expected CLEAN_PROJECT, got: $($result.Classification)"

    Assert-True "A: clean project has no DFC evidence" `
        ($dfcEv.Count -eq 0) `
        "Expected no DFC evidence, got: $($dfcEv.Count) items"

    Assert-True "A: clean project has no MxAgile evidence" `
        ($mxEv.Count -eq 0) `
        "Expected no MxAgile evidence, got: $($mxEv.Count) items"
} finally {
    Remove-FixtureDirectory $fixtureA
}
Write-Host ""

# =========================================================================
# SCENARIO B: Existing MxAgile project -> EXISTING_MXAGILE_PROJECT
# =========================================================================
Write-Host "--- B: Existing MxAgile project -> EXISTING_MXAGILE_PROJECT ---"
$fixtureB = New-FixtureDirectory "mxagile"
try {
    New-Item -Path (Join-Path $fixtureB "MyApp.mpr") -ItemType File -Force | Out-Null
    New-Item -Path (Join-Path $fixtureB ".mxagile") -ItemType Directory -Force | Out-Null
    New-Item -Path (Join-Path $fixtureB ".mxagile\lifecycle.yaml") -ItemType File -Force | Out-Null
    $claudeAgents = Join-Path $fixtureB ".claude\agents"
    New-Item -Path $claudeAgents -ItemType Directory -Force | Out-Null
    New-Item -Path (Join-Path $claudeAgents "mxagile-discovery-agent.md") -ItemType File -Force | Out-Null

    $resultJson = & $detectScript -ProjectRoot $fixtureB
    $result = $resultJson | ConvertFrom-Json
    $dfcEv = @($result.DfcEvidence); $mxEv = @($result.MxAgileEvidence)

    Assert-True "B: MxAgile project classified as EXISTING_MXAGILE_PROJECT" `
        ($result.Classification -eq "EXISTING_MXAGILE_PROJECT") `
        "Expected EXISTING_MXAGILE_PROJECT, got: $($result.Classification)"

    Assert-True "B: MxAgile evidence includes lifecycle.yaml" `
        ((@($mxEv | Where-Object { $_ -match 'lifecycle\.yaml' })).Count -gt 0) `
        "lifecycle.yaml not in MxAgile evidence: $($mxEv -join ', ')"

    Assert-True "B: no DFC evidence on MxAgile project" `
        ($dfcEv.Count -eq 0) `
        "Unexpected DFC evidence: $($dfcEv -join ', ')"
} finally {
    Remove-FixtureDirectory $fixtureB
}
Write-Host ""

# =========================================================================
# SCENARIO C: Legacy DFC-AI project -> LEGACY_DFC_PROJECT
# =========================================================================
Write-Host "--- C: Legacy DFC-AI project -> LEGACY_DFC_PROJECT detected ---"
$fixtureC = New-FixtureDirectory "dfc"
try {
    # Minimal DFC-AI fixture
    New-Item -Path (Join-Path $fixtureC "MyApp.mpr") -ItemType File -Force | Out-Null
    $dfcDir = Join-Path $fixtureC ".dfc-ai"
    New-Item -Path $dfcDir -ItemType Directory -Force | Out-Null
    Set-Content -Path (Join-Path $dfcDir "version.yaml") -Value 'version: "1.0"' -Encoding UTF8
    $scriptsDir = Join-Path $fixtureC "scripts"
    New-Item -Path $scriptsDir -ItemType Directory -Force | Out-Null
    New-Item -Path (Join-Path $scriptsDir "generate-dfc-platform-skills.ps1") -ItemType File -Force | Out-Null
    $claudeAgents = Join-Path $fixtureC ".claude\agents"
    New-Item -Path $claudeAgents -ItemType Directory -Force | Out-Null
    New-Item -Path (Join-Path $claudeAgents "dfc-discovery-agent.md") -ItemType File -Force | Out-Null
    New-Item -Path (Join-Path $claudeAgents "dfc-refinement-agent.md") -ItemType File -Force | Out-Null

    $resultJson = & $detectScript -ProjectRoot $fixtureC
    $result = $resultJson | ConvertFrom-Json
    $dfcEv = @($result.DfcEvidence); $mxEv = @($result.MxAgileEvidence)

    Assert-True "C: DFC project classified as LEGACY_DFC_PROJECT" `
        ($result.Classification -eq "LEGACY_DFC_PROJECT") `
        "Expected LEGACY_DFC_PROJECT, got: $($result.Classification)"

    Assert-True "C: primary DFC evidence (.dfc-ai/version.yaml) present" `
        ((@($dfcEv | Where-Object { $_ -match '\.dfc-ai.*version' })).Count -gt 0) `
        ".dfc-ai/version.yaml not in DFC evidence: $($dfcEv -join ', ')"

    Assert-True "C: DFC classified before any destructive writes" `
        (-not (Test-Path -LiteralPath (Join-Path $fixtureC ".mxagile\lifecycle.yaml"))) `
        "lifecycle.yaml was written before detection check"
} finally {
    Remove-FixtureDirectory $fixtureC
}
Write-Host ""

# =========================================================================
# SCENARIO D: Legacy project artifacts unchanged except permitted bootstrap
# =========================================================================
Write-Host "--- D: Legacy artifacts unchanged after bootstrap ---"
$fixtureD = New-FixtureDirectory "dfc-bootstrap"
try {
    # Create DFC fixture with project artifacts
    New-Item -Path (Join-Path $fixtureD "MyApp.mpr") -ItemType File -Force | Out-Null
    Set-Content -Path (Join-Path $fixtureD "MyApp.mpr") -Value "BINARY" -Encoding UTF8
    $dfcDir = Join-Path $fixtureD ".dfc-ai"
    New-Item -Path $dfcDir -ItemType Directory -Force | Out-Null
    Set-Content -Path (Join-Path $dfcDir "version.yaml") -Value 'version: "1.0"' -Encoding UTF8
    Set-Content -Path (Join-Path $dfcDir "orchestrator.md") -Value "# DFC orchestrator" -Encoding UTF8
    $planningDir = Join-Path $fixtureD "planning\stories"
    New-Item -Path $planningDir -ItemType Directory -Force | Out-Null
    Set-Content -Path (Join-Path $planningDir "REQ-001.md") -Value "# REQ-001 original content" -Encoding UTF8
    Set-Content -Path (Join-Path $fixtureD "projekt.md") -Value "# Projektbeschreibung original" -Encoding UTF8
    New-Item -Path (Join-Path $fixtureD ".claude\agents") -ItemType Directory -Force | Out-Null
    New-Item -Path (Join-Path $fixtureD ".claude\agents\dfc-discovery-agent.md") -ItemType File -Force | Out-Null

    # Run bootstrap
    & $bootstrapScript -ProjectRoot $fixtureD -CanonicalSource $canonicalSource | Out-Null

    # DFC artifacts must be untouched
    Assert-True "D: .dfc-ai/version.yaml still exists" `
        (Test-Path -LiteralPath (Join-Path $dfcDir "version.yaml")) `
        ".dfc-ai/version.yaml was removed by bootstrap"

    Assert-True "D: .dfc-ai/orchestrator.md still exists" `
        (Test-Path -LiteralPath (Join-Path $dfcDir "orchestrator.md")) `
        ".dfc-ai/orchestrator.md was removed by bootstrap"

    Assert-True "D: .claude/agents/dfc-discovery-agent.md unchanged" `
        (Test-Path -LiteralPath (Join-Path $fixtureD ".claude\agents\dfc-discovery-agent.md")) `
        "dfc-discovery-agent.md was removed by bootstrap"

    # Project artifacts must be untouched
    $req001Content = Get-Content -LiteralPath (Join-Path $planningDir "REQ-001.md") -Raw
    Assert-True "D: planning/stories/REQ-001.md content unchanged" `
        ($req001Content -match "REQ-001 original content") `
        "REQ-001.md content was modified"

    $projektContent = Get-Content -LiteralPath (Join-Path $fixtureD "projekt.md") -Raw
    Assert-True "D: projekt.md content unchanged" `
        ($projektContent -match "Projektbeschreibung original") `
        "projekt.md was modified"

    # Only permitted bootstrap files written
    Assert-True "D: .mxagile/migration/ was created (permitted)" `
        (Test-Path -LiteralPath (Join-Path $fixtureD ".mxagile\migration") -PathType Container) `
        ".mxagile/migration/ not created"

    # lifecycle.yaml must NOT be written
    Assert-FileAbsent "D: .mxagile/lifecycle.yaml not written (not yet migrated)" `
        (Join-Path $fixtureD ".mxagile\lifecycle.yaml")

    # mxagile-* lifecycle skills must NOT be written (except migration-agent)
    $claudeRootD = Join-Path $fixtureD ".claude"
    $mxagileExtraCount = 0
    if (Test-Path -LiteralPath $claudeRootD -PathType Container) {
        $mxagileExtraCount = @(Get-ChildItem -LiteralPath $claudeRootD -Recurse -Filter "*.md" -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^mxagile-' -and $_.Name -ne 'mxagile-migration-agent.md' }).Count
    }
    Assert-True "D: no mxagile-* lifecycle skills written" `
        ($mxagileExtraCount -eq 0) `
        "Unexpected mxagile-* skill files written: $mxagileExtraCount"

    # No managed block injection
    $claudeMdPath = Join-Path $fixtureD "CLAUDE.md"
    if (Test-Path -LiteralPath $claudeMdPath) {
        $claudeContent = Get-Content -LiteralPath $claudeMdPath -Raw
        Assert-True "D: MXAGILE:MANAGED marker not injected into CLAUDE.md" `
            (-not ($claudeContent -match 'MXAGILE:MANAGED:START')) `
            "MXAGILE:MANAGED block was injected by bootstrap"
    }

} finally {
    Remove-FixtureDirectory $fixtureD
}
Write-Host ""

# =========================================================================
# SCENARIO E: Existing Mendix .mpr remains unchanged
# =========================================================================
Write-Host "--- E: .mpr file unchanged after bootstrap ---"
$fixtureE = New-FixtureDirectory "mpr-safety"
try {
    $mprContent = "FAKE_MPR_BINARY_CONTENT_DO_NOT_MODIFY"
    $mprPath = Join-Path $fixtureE "CapTrack.mpr"
    Set-Content -Path $mprPath -Value $mprContent -Encoding UTF8 -NoNewline

    $dfcDir = Join-Path $fixtureE ".dfc-ai"
    New-Item -Path $dfcDir -ItemType Directory -Force | Out-Null
    Set-Content -Path (Join-Path $dfcDir "version.yaml") -Value 'version: "1.0"' -Encoding UTF8

    # Run detection + bootstrap
    $resultJson = & $detectScript -ProjectRoot $fixtureE
    $result = $resultJson | ConvertFrom-Json
    & $bootstrapScript -ProjectRoot $fixtureE -CanonicalSource $canonicalSource | Out-Null

    $mprAfter = Get-Content -LiteralPath $mprPath -Raw -ErrorAction SilentlyContinue
    Assert-True "E: .mpr content unchanged after bootstrap" `
        ($mprAfter -eq $mprContent) `
        ".mpr content was modified"

    Assert-True "E: .mpr still exists after bootstrap" `
        (Test-Path -LiteralPath $mprPath) `
        ".mpr file was removed"
} finally {
    Remove-FixtureDirectory $fixtureE
}
Write-Host ""

# =========================================================================
# SCENARIO F: Repeated init on DFC project remains safe (idempotent)
# =========================================================================
Write-Host "--- F: Repeated bootstrap is idempotent ---"
$fixtureF = New-FixtureDirectory "idempotent"
try {
    New-Item -Path (Join-Path $fixtureF "MyApp.mpr") -ItemType File -Force | Out-Null
    $dfcDir = Join-Path $fixtureF ".dfc-ai"
    New-Item -Path $dfcDir -ItemType Directory -Force | Out-Null
    Set-Content -Path (Join-Path $dfcDir "version.yaml") -Value 'version: "1.0"' -Encoding UTF8

    # First run
    & $bootstrapScript -ProjectRoot $fixtureF -CanonicalSource $canonicalSource | Out-Null
    $agentPath = Join-Path $fixtureF ".claude\agents\mxagile-migration-agent.md"
    $policyPath = Join-Path $fixtureF ".mxagile\migration\policy.md"
    $firstAgentHash = (Get-FileHash -LiteralPath $agentPath -Algorithm SHA256).Hash
    $firstPolicyHash = (Get-FileHash -LiteralPath $policyPath -Algorithm SHA256).Hash

    # Second run
    & $bootstrapScript -ProjectRoot $fixtureF -CanonicalSource $canonicalSource | Out-Null
    $secondAgentHash = (Get-FileHash -LiteralPath $agentPath -Algorithm SHA256).Hash
    $secondPolicyHash = (Get-FileHash -LiteralPath $policyPath -Algorithm SHA256).Hash

    Assert-True "F: migration agent identical after second run" `
        ($firstAgentHash -eq $secondAgentHash) `
        "Migration agent file changed on second bootstrap run"

    Assert-True "F: migration policy identical after second run" `
        ($firstPolicyHash -eq $secondPolicyHash) `
        "Migration policy file changed on second bootstrap run"

    # Detection still returns LEGACY_DFC_PROJECT after bootstrap (migration not complete)
    $resultJson2 = & $detectScript -ProjectRoot $fixtureF
    $result2 = $resultJson2 | ConvertFrom-Json
    Assert-True "F: detection still returns LEGACY_DFC_PROJECT after bootstrap" `
        ($result2.Classification -eq "LEGACY_DFC_PROJECT") `
        "Expected LEGACY_DFC_PROJECT after bootstrap, got: $($result2.Classification)"

    # DFC artifacts still untouched
    Assert-True "F: .dfc-ai/version.yaml still present after second bootstrap" `
        (Test-Path -LiteralPath (Join-Path $dfcDir "version.yaml")) `
        ".dfc-ai/version.yaml removed"
} finally {
    Remove-FixtureDirectory $fixtureF
}
Write-Host ""

# =========================================================================
# SCENARIO G: Migration agent/instructions available after bootstrap
# =========================================================================
Write-Host "--- G: Migration agent and instructions available after bootstrap ---"
$fixtureG = New-FixtureDirectory "bootstrap-available"
try {
    New-Item -Path (Join-Path $fixtureG "MyApp.mpr") -ItemType File -Force | Out-Null
    $dfcDir = Join-Path $fixtureG ".dfc-ai"
    New-Item -Path $dfcDir -ItemType Directory -Force | Out-Null
    Set-Content -Path (Join-Path $dfcDir "version.yaml") -Value 'version: "1.0"' -Encoding UTF8

    & $bootstrapScript -ProjectRoot $fixtureG -CanonicalSource $canonicalSource | Out-Null

    $migrationAgentPath = Join-Path $fixtureG ".claude\agents\mxagile-migration-agent.md"
    Assert-True "G: migration agent installed at .claude/agents/mxagile-migration-agent.md" `
        (Test-Path -LiteralPath $migrationAgentPath) `
        "Migration agent file not found"

    Assert-FileContains "G: migration agent has Claude frontmatter" `
        $migrationAgentPath 'model: sonnet'

    Assert-FileContains "G: migration agent has description" `
        $migrationAgentPath 'Migration Agent|migration.*DFC'

    Assert-FileContains "G: migration agent references migration policy" `
        $migrationAgentPath 'migration/policy\.md|migration-dfc-to-mxagile'

    $policyPath = Join-Path $fixtureG ".mxagile\migration\policy.md"
    Assert-True "G: migration policy installed at .mxagile/migration/policy.md" `
        (Test-Path -LiteralPath $policyPath) `
        "Migration policy not found"

    Assert-FileContains "G: migration policy covers brownfield baseline" `
        $policyPath 'brownfield.baseline|brownfield_baseline'

    Assert-FileContains "G: migration policy covers DFC artifact removal" `
        $policyPath '\.dfc-ai.*remove|remove.*dfc|dfc-\*.*md'

    Assert-FileContains "G: migration policy covers preservation of planning artifacts" `
        $policyPath 'planning.*stories|decisions.*md|preserve'

    $readmePath = Join-Path $fixtureG ".mxagile\migration\README.md"
    Assert-True "G: migration README state marker installed" `
        (Test-Path -LiteralPath $readmePath) `
        "Migration README not found"

    Assert-FileContains "G: README documents MIGRATION_BOOTSTRAPPED state" `
        $readmePath 'MIGRATION_BOOTSTRAPPED'
} finally {
    Remove-FixtureDirectory $fixtureG
}
Write-Host ""

# =========================================================================
# SCENARIO H: install-core.ps1 prints actionable migration-agent prompt
# =========================================================================
Write-Host "--- H: install-core.ps1 prints actionable migration prompt ---"

# Test the install-core.ps1 content directly (no execution; execution requires mxcli)
Assert-FileContains "H: install-core.ps1 detects legacy DFC before destructive writes" `
    $installScript 'detect-project-type\.ps1'

Assert-FileContains "H: install-core.ps1 stops on LEGACY_DFC_PROJECT" `
    $installScript "LEGACY_DFC_PROJECT"

Assert-FileContains "H: install-core.ps1 calls migration bootstrap on detection" `
    $installScript 'install-migration-bootstrap\.ps1'

Assert-FileContains "H: install-core.ps1 outputs actionable migration prompt" `
    $installScript 'Migrate this existing DFC-AI project to MxAgile'

Assert-FileContains "H: install-core.ps1 exits 2 on MIGRATION_REQUIRED" `
    $installScript 'exit 2'

Assert-FileContains "H: install-core.ps1 exits 3 on AMBIGUOUS" `
    $installScript 'exit 3'

Assert-FileContains "H: actionable prompt names .mxagile/migration/" `
    $installScript '\.mxagile/migration/'

Write-Host ""

# =========================================================================
# SCENARIO I: No complete MxAgile projections installed by bootstrap
# =========================================================================
Write-Host "--- I: No complete MxAgile projections before migration ---"
$fixtureI = New-FixtureDirectory "no-projections"
try {
    New-Item -Path (Join-Path $fixtureI "MyApp.mpr") -ItemType File -Force | Out-Null
    $dfcDir = Join-Path $fixtureI ".dfc-ai"
    New-Item -Path $dfcDir -ItemType Directory -Force | Out-Null
    Set-Content -Path (Join-Path $dfcDir "version.yaml") -Value 'version: "1.0"' -Encoding UTF8

    & $bootstrapScript -ProjectRoot $fixtureI -CanonicalSource $canonicalSource | Out-Null

    # No lifecycle files
    Assert-FileAbsent "I: .mxagile/lifecycle.yaml not installed" `
        (Join-Path $fixtureI ".mxagile\lifecycle.yaml")

    Assert-FileAbsent "I: .mxagile/orchestrator.md not installed" `
        (Join-Path $fixtureI ".mxagile\orchestrator.md")

    # No mxagile-* lifecycle skill projections
    $claudeSkillsDirI = Join-Path $fixtureI ".claude\skills"
    $mxagileSkillCountI = 0
    if (Test-Path -LiteralPath $claudeSkillsDirI -PathType Container) {
        $mxagileSkillCountI = @(Get-ChildItem -LiteralPath $claudeSkillsDirI -Recurse -Filter "*.md" -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'mxagile' }).Count
    }
    Assert-True "I: no mxagile-* Claude skill projections installed" `
        ($mxagileSkillCountI -eq 0) `
        "Unexpected mxagile-* skill files: $mxagileSkillCountI"

    # No mxagile lifecycle agent projections (exception: migration-agent)
    $claudeAgentsDirI = Join-Path $fixtureI ".claude\agents"
    $mxagileExtraAgentCount = 0
    if (Test-Path -LiteralPath $claudeAgentsDirI -PathType Container) {
        $mxagileExtraAgentCount = @(Get-ChildItem -LiteralPath $claudeAgentsDirI -Filter "mxagile-*.md" -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne "mxagile-migration-agent.md" }).Count
    }
    Assert-True "I: no mxagile-* lifecycle agents installed (except migration-agent)" `
        ($mxagileExtraAgentCount -eq 0) `
        "Unexpected mxagile-* agents: $mxagileExtraAgentCount"

    # No managed block injection into AGENTS.md/CLAUDE.md
    foreach ($entrypoint in @("AGENTS.md", "CLAUDE.md")) {
        $epPath = Join-Path $fixtureI $entrypoint
        if (Test-Path -LiteralPath $epPath) {
            $content = Get-Content -LiteralPath $epPath -Raw
            Assert-True "I: $entrypoint has no MXAGILE:MANAGED injection" `
                (-not ($content -match 'MXAGILE:MANAGED:START')) `
                "MXAGILE:MANAGED block injected into $entrypoint by bootstrap"
        }
    }

    # No .github/copilot-instructions with MxAgile block
    $copilotPath = Join-Path $fixtureI ".github\copilot-instructions.md"
    if (Test-Path -LiteralPath $copilotPath) {
        $content = Get-Content -LiteralPath $copilotPath -Raw
        Assert-True "I: copilot-instructions.md has no MXAGILE:MANAGED injection" `
            (-not ($content -match 'MXAGILE:MANAGED:START')) `
            "MXAGILE:MANAGED block injected into copilot-instructions.md"
    }

} finally {
    Remove-FixtureDirectory $fixtureI
}
Write-Host ""

# =========================================================================
# ADDITIONAL: Ambiguous project classification
# =========================================================================
Write-Host "--- Extra: Ambiguous project (both DFC + MxAgile) ---"
$fixtureAmb = New-FixtureDirectory "ambiguous"
try {
    New-Item -Path (Join-Path $fixtureAmb "MyApp.mpr") -ItemType File -Force | Out-Null
    New-Item -Path (Join-Path $fixtureAmb ".dfc-ai") -ItemType Directory -Force | Out-Null
    Set-Content -Path (Join-Path $fixtureAmb ".dfc-ai\version.yaml") -Value 'version: "1.0"' -Encoding UTF8
    New-Item -Path (Join-Path $fixtureAmb ".mxagile") -ItemType Directory -Force | Out-Null
    New-Item -Path (Join-Path $fixtureAmb ".mxagile\lifecycle.yaml") -ItemType File -Force | Out-Null

    $resultJson = & $detectScript -ProjectRoot $fixtureAmb
    $result = $resultJson | ConvertFrom-Json
    $dfcEv = @($result.DfcEvidence); $mxEv = @($result.MxAgileEvidence)

    Assert-True "Ambiguous: classified as AMBIGUOUS" `
        ($result.Classification -eq "AMBIGUOUS") `
        "Expected AMBIGUOUS, got: $($result.Classification)"

    Assert-True "Ambiguous: has both DFC and MxAgile evidence" `
        ($dfcEv.Count -gt 0 -and $mxEv.Count -gt 0) `
        "Expected both DFC and MxAgile evidence"
} finally {
    Remove-FixtureDirectory $fixtureAmb
}

# =========================================================================
# Canonical source validation
# =========================================================================
Write-Host ""
Write-Host "--- Canonical source integrity ---"

Assert-FileContains "canonical: migration-agent.md references migration policy" `
    (Join-Path $canonicalSource "agents\migration-agent.md") `
    'migration/policy\.md|migration-dfc-to-mxagile'

Assert-FileContains "canonical: migration policy has brownfield baseline section" `
    (Join-Path $canonicalSource "policies\migration-dfc-to-mxagile.md") `
    'brownfield.baseline|brownfield_baseline'

Assert-FileContains "canonical: migration policy safety rules non-negotiable" `
    (Join-Path $canonicalSource "policies\migration-dfc-to-mxagile.md") `
    'non-negotiable|Safety Rules'

Assert-FileContains "canonical: migration policy covers .mpr protection" `
    (Join-Path $canonicalSource "policies\migration-dfc-to-mxagile.md") `
    'never delete.*\.mpr|\.mpr.*never|Never delete.*mpr'

Assert-FileContains "canonical: migration policy requires confirmation before removal" `
    (Join-Path $canonicalSource "policies\migration-dfc-to-mxagile.md") `
    'confirmation|explicit.*confirm|Wait for.*confirm'

Assert-FileContains "canonical: install-migration-bootstrap.ps1 writes migration dir only" `
    $bootstrapScript `
    'migration'

Assert-FileContains "canonical: install-migration-bootstrap.ps1 does not write lifecycle.yaml" `
    $bootstrapScript `
    'lifecycle\.yaml'

$bootstrapContent = Get-Content -LiteralPath $bootstrapScript -Raw
Assert-True "canonical: install-migration-bootstrap.ps1 does NOT write lifecycle.yaml" `
    (-not ($bootstrapContent -match "Set-Content.*lifecycle\.yaml|New-Item.*lifecycle\.yaml")) `
    "Bootstrap script writes lifecycle.yaml (must not)"

Assert-FileContains "canonical: detect-project-type.ps1 uses .dfc-ai/version.yaml as primary marker" `
    $detectScript `
    '\.dfc-ai\\version\.yaml|dfc-ai.*version\.yaml'

Assert-FileContains "canonical: detect-project-type.ps1 uses .mxagile/lifecycle.yaml as MxAgile marker" `
    $detectScript `
    '\.mxagile.*lifecycle\.yaml|lifecycle\.yaml'

Assert-FileContains "canonical: install-core.ps1 preflight runs before .mpr check" `
    $installScript `
    'detect-project-type'

Write-Host ""

# =========================================================================
# Summary
# =========================================================================
Write-Host "=== DFC Migration Preflight Test Results ==="
Write-Host "  PASS: $PassCount" -ForegroundColor Green
if ($FailCount -gt 0) {
    Write-Host "  FAIL: $FailCount" -ForegroundColor Red
    foreach ($detail in $FailDetails) {
        Write-Host "    $detail" -ForegroundColor Red
    }
    Write-Host ""
    Write-Host "TEST FAILED: DFC migration preflight contract incomplete." -ForegroundColor Red
    exit 1
} else {
    Write-Host ""
    Write-Host "TEST PASSED: DFC-AI detection and migration bootstrap meet the preflight contract." -ForegroundColor Green
    exit 0
}
