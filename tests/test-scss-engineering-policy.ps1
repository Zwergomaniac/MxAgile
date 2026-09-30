<#
.SYNOPSIS
    SCSS Engineering Policy Tests: MxAgile Canonical SCSS Contract

.DESCRIPTION
    Validates that the MxAgile framework contains a canonical SCSS engineering contract
    that prevents the primary failure mode: agents appending implementation SCSS directly
    to main.scss because it already exists and is easy to find.

    The contract must establish:
    A. Policy file exists in canonical location
    B. Source ownership validation (protected vs project-owned)
    C. main.scss as composition root (not implementation destination)
    D. SCSS concern classification
    E. Decision rule (partial vs main.scss)
    F. File granularity guidance
    G. Naming conventions (preferred and prohibited names)
    H. Existing main.scss: do not automatically refactor
    I. Parity/mockup fixes follow the same contract
    J. Agent integration: implementation-agent references policy
    K. Agent integration: ui-agent references policy
#>

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$TestsDir   = $PSScriptRoot
$ScriptDir  = Split-Path -Parent $TestsDir
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

function Assert-FileNotContains {
    param([string]$TestName, [string]$FilePath, [string]$Pattern)
    $content = Get-Content -LiteralPath $FilePath -Raw -ErrorAction SilentlyContinue
    if ($null -eq $content) {
        Assert-True $TestName $false "File not found: $FilePath"
    } else {
        Assert-True $TestName ($content -notmatch $Pattern) "Forbidden pattern '$Pattern' found in $FilePath"
    }
}

$Policy             = Join-Path $ScriptDir '.mxagile\policies\scss-engineering.md'
$ImplAgent          = Join-Path $ScriptDir '.mxagile\agents\implementation-agent.md'
$UiAgent            = Join-Path $ScriptDir '.mxagile\agents\ui-agent.md'

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST A: Policy file exists in canonical location" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Assert-True "A.1 .mxagile/policies/scss-engineering.md exists" (Test-Path $Policy) "File not found: $Policy"
Assert-True "A.2 Policy is inside .mxagile/policies/" ($Policy -like '*\.mxagile\policies\*') "Policy not in .mxagile/policies/"

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST B: Source ownership validation — protected vs project-owned" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Assert-FileContains "B.1 Policy names protected sources section" $Policy 'Protected Sources|Protected.*Modify'
Assert-FileContains "B.2 Policy names atlas_core as protected" $Policy 'atlas_core'
Assert-FileContains "B.3 Policy names atlas_web_content as protected" $Policy 'atlas_web_content'
Assert-FileContains "B.4 Policy names Marketplace modules as protected" $Policy 'Marketplace'
Assert-FileContains "B.5 Policy names project-owned source section" $Policy 'Project-Owned Sources|Project.Owned'
Assert-FileContains "B.6 Policy names themesource/{ProjectModule} as safe" $Policy 'themesource/\{ProjectModule\}|themesource.*ProjectModule'
Assert-FileContains "B.7 Policy names custom-variables.scss as safe" $Policy 'custom-variables\.scss'
Assert-FileContains "B.8 Policy warns that a writable file does not imply permission to modify" $Policy 'writable.*NOT|does NOT authorize|NOT.*authorize'

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST C: main.scss as composition root — not implementation destination" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Assert-FileContains "C.1 Policy declares main.scss as composition root" $Policy 'main\.scss.*[Cc]omposition [Rr]oot|[Cc]omposition [Rr]oot.*main\.scss'
Assert-FileContains "C.2 Policy lists @import/@use/@forward as valid main.scss content" $Policy '@import.*@use|@use.*@forward|@import.*@forward'
Assert-FileContains "C.3 Policy prohibits page-specific selectors in main.scss" $Policy 'overview-page|customer-form'
Assert-FileContains "C.4 Policy prohibits component selectors in main.scss" $Policy 'kpi-card|status-badge'
Assert-FileContains "C.5 Policy names the primary failure mode explicitly" $Policy 'primary failure mode|appending implementation directly'
Assert-FileNotContains "C.6 Policy does not contradict its own rule by encouraging main.scss usage" $Policy 'main\.scss is the recommended|write all styles to main\.scss'

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST D: SCSS concern classification" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Assert-FileContains "D.1 Policy defines component concern type" $Policy '[Cc]omponent'
Assert-FileContains "D.2 Policy defines page concern type" $Policy '[Pp]age.level|[Pp]age-level'
Assert-FileContains "D.3 Policy defines layout concern type" $Policy '[Ll]ayout'
Assert-FileContains "D.4 Policy defines feature concern type" $Policy '[Ff]eature'
Assert-FileContains "D.5 Policy defines responsive concern type" $Policy '[Rr]esponsive'
Assert-FileContains "D.6 Policy gives example partial location for component concern" $Policy 'scss/components'
Assert-FileContains "D.7 Policy notes existing project structure takes precedence" $Policy 'existing.*partial|project.*existing|stable.*UI.*ownership'

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST E: Decision rule — partial vs main.scss" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Assert-FileContains "E.1 Policy gives ordered decision rule" $Policy 'Decision Rule|Apply in order'
Assert-FileContains "E.2 Rule step 1: extend existing partial" $Policy '[Ee]xist.*partial.*extend|[Ee]xtend.*exist.*partial'
Assert-FileContains "E.3 Rule step 2: create focused partial for new concern" $Policy 'new coherent concern|[Cc]reate.*focused partial'
Assert-FileContains "E.4 Rule step 3: main.scss only for trivial bootstrap content" $Policy 'trivial.*bootstrap|genuinely.*bootstrap'
Assert-FileContains "E.5 Policy prohibits partials for a single CSS declaration" $Policy 'single CSS declaration'

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST F: File granularity guidance" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Assert-FileContains "F.1 Policy shows too-coarse example" $Policy '[Tt]oo coarse|avoid.*3000|3000 lines'
Assert-FileContains "F.2 Policy shows too-fine example" $Policy '[Tt]oo fine|card-border|card-shadow'
Assert-FileContains "F.3 Policy gives grouping principle" $Policy 'stable UI ownership|change together'

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST G: Naming conventions" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Assert-FileContains "G.1 Policy gives preferred naming examples" $Policy '_overview\.scss|_kpi-card\.scss'
Assert-FileContains "G.2 Policy names _fix.scss as prohibited" $Policy '_fix\.scss'
Assert-FileContains "G.3 Policy names _parity-fix.scss as prohibited" $Policy '_parity-fix\.scss'
Assert-FileContains "G.4 Policy names _temp.scss as prohibited" $Policy '_temp\.scss'
Assert-FileContains "G.5 Policy states names describe UI not agent session" $Policy 'agent session|history of who'

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST H: Existing main.scss — do not automatically refactor" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Assert-FileContains "H.1 Policy explicitly says do not automatically refactor existing main.scss" $Policy 'NOT automatically.*refactor|not.*automatically.*refactor|Do NOT automatically'
Assert-FileContains "H.2 Policy permits scoped extraction of current concern" $Policy 'Extracting the affected.*partial|scoped'
Assert-FileContains "H.3 Policy says broad cleanup is a dedicated task" $Policy 'dedicated refactoring task|dedicated.*task'

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST I: Parity and mockup fixes follow same contract" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Assert-FileContains "I.1 Policy covers parity/mockup remediation" $Policy '[Pp]arity.*[Rr]emediation|[Mm]ockup.*[Rr]emediation'
Assert-FileContains "I.2 Policy shows anti-pattern (direct main.scss append for parity fix)" $Policy '[Aa]nti.pattern'
Assert-FileContains "I.3 Policy shows correct pattern for parity fix" $Policy '[Cc]orrect|extend existing partial'
Assert-FileContains "I.4 Policy states parity fixes ARE production UI implementation" $Policy 'production UI implementation'

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST J: Agent integration — implementation-agent references policy" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Assert-FileContains "J.1 implementation-agent.md lists scss-engineering.md in Policies" $ImplAgent 'scss-engineering\.md'
Assert-FileContains "J.2 implementation-agent.md has SCSS-Implementierung section" $ImplAgent 'SCSS-Implementierung'
Assert-FileContains "J.3 implementation-agent.md mentions composition root rule" $ImplAgent '[Kk]ompositions.[Rr]oot|[Cc]omposition.Root'
Assert-FileContains "J.4 implementation-agent.md lists forbidden partial names" $ImplAgent '_fix\.scss|_parity-fix\.scss|_temp\.scss'
Assert-FileContains "J.5 implementation-agent.md references scss-engineering.md in TECHNISCHE ARBEIT table" $ImplAgent 'scss-engineering\.md.*TECHNISCHE|TECHNISCHE.*scss-engineering\.md|SCSS.*scss-engineering\.md'

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST K: Agent integration — ui-agent references policy" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Assert-FileContains "K.1 ui-agent.md lists scss-engineering.md in Policies" $UiAgent 'scss-engineering\.md'
Assert-FileContains "K.2 ui-agent.md concern-classification note in VISUAL dimension" $UiAgent 'scss-engineering\.md.*[Vv]isual|[Vv]isual.*scss-engineering\.md|SCSS-Ursache|scss.*concern'

# ---------------------------------------------------------------------------
Write-Host ""
$total = $PassCount + $FailCount
Write-Host "=" * 60
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
