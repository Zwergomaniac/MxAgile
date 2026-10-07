<#
.SYNOPSIS
    Mendix Scroll Helper Policy Tests: MxAgile-Aware Playwright Scrolling

.DESCRIPTION
    Validates that the MxAgile framework contains a canonical Mendix-aware scroll abstraction
    that correctly addresses the real-world finding: standard browser-level scrolling
    (window.scrollTo, document.body.scrollTop) does not move Mendix application content
    because Mendix/Atlas hosts content in an independently scrollable layout container.

    Test cases:
    A. Helper file exists and is in the correct canonical location
    B. Known Mendix selector .mx-scrollcontainer-center is handled
    C. All required RESULT codes are defined
    D. Discovery returns diagnostics sufficient for evidence reporting
    E. Positional scroll verifies actual position (detects SCROLL_NOT_EFFECTIVE)
    F. window.scrollTo is NOT used as the primary scroll mechanism
    G. Element-based scrolling (scrollIntoView) is supported
    H. Viewport coverage generates stops from runtime dimensions, not hardcoded values
    I. Shell helper exists for playwright-cli .test.sh scripts
    J. Skill documentation exists and covers the required behavioral contract
    K. Spec file and fixture files exist for framework regression coverage
    L. Discovery result codes and their meaning are clearly named
    M. No project-specific hardcoded selectors, heights, or logic leaked into Core
    N. Evidence safety rule documented — SCROLL_NOT_EFFECTIVE prevents false PASS
    O. mxcli capability findings documented accurately
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

$ScrollHelper = Join-Path $ScriptDir '.playwright\helpers\mx-scroll.js'
$ShellHelper  = Join-Path $ScriptDir '.playwright\helpers\mx-scroll-shell.sh'
$Skill        = Join-Path $ScriptDir '.mxagile\skills\visual-verification.md'
$SpecFile     = Join-Path $ScriptDir '.playwright\tests\mx-scroll.spec.js'

$FixturesDir  = Join-Path $ScriptDir 'tests\fixtures\playwright'

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST A: Helper file exists in canonical location" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Assert-True "A.1 .playwright/helpers/mx-scroll.js exists" (Test-Path $ScrollHelper) "File not found: $ScrollHelper"
Assert-True "A.2 .playwright/helpers/mx-scroll-shell.sh exists" (Test-Path $ShellHelper) "File not found: $ShellHelper"
Assert-True "A.3 .playwright/helpers/ directory is under .playwright/" (
    $ScrollHelper -like '*\.playwright\helpers\*'
) "Helper not in .playwright/helpers/"

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST B: Known Mendix selector .mx-scrollcontainer-center is handled" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Assert-FileContains "B.1 mx-scroll.js handles .mx-scrollcontainer-center" $ScrollHelper '\.mx-scrollcontainer-center'
Assert-FileContains "B.2 mx-scroll.js places .mx-scrollcontainer-center first in priority order" $ScrollHelper "KNOWN_MENDIX_SELECTORS"
Assert-FileContains "B.3 mx-scroll-shell.sh handles .mx-scrollcontainer-center" $ShellHelper '\.mx-scrollcontainer-center'
Assert-FileContains "B.4 skill documents .mx-scrollcontainer-center as primary Atlas container" $Skill '\.mx-scrollcontainer-center'

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST C: All required RESULT codes are defined" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Assert-FileContains "C.1 RESULT.SCROLLED defined"             $ScrollHelper 'SCROLLED'
Assert-FileContains "C.2 RESULT.ALREADY_AT_POSITION defined"  $ScrollHelper 'ALREADY_AT_POSITION'
Assert-FileContains "C.3 RESULT.CLAMPED_TO_MAX defined"       $ScrollHelper 'CLAMPED_TO_MAX'
Assert-FileContains "C.4 RESULT.NO_SCROLL_CONTAINER defined"  $ScrollHelper 'NO_SCROLL_CONTAINER'
Assert-FileContains "C.5 RESULT.SCROLL_NOT_EFFECTIVE defined" $ScrollHelper 'SCROLL_NOT_EFFECTIVE'
Assert-FileContains "C.6 RESULT exported from module"         $ScrollHelper 'module\.exports'

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST D: Discovery returns diagnostics sufficient for evidence reporting" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Assert-FileContains "D.1 discoverScrollContainer is defined" $ScrollHelper 'discoverScrollContainer'
Assert-FileContains "D.2 discovery returns scrollHeight"     $ScrollHelper 'scrollHeight'
Assert-FileContains "D.3 discovery returns clientHeight"     $ScrollHelper 'clientHeight'
Assert-FileContains "D.4 discovery returns scrollTop"        $ScrollHelper 'scrollTop'
Assert-FileContains "D.5 discovery returns method field"     $ScrollHelper 'method:'
Assert-FileContains "D.6 discovery returns candidateCount"   $ScrollHelper 'candidateCount'
Assert-FileContains "D.7 discovery returns isScrollable"     $ScrollHelper 'isScrollable'
Assert-FileContains "D.8 discovery exported from module"     $ScrollHelper 'module\.exports[\s\S]{1,500}discoverScrollContainer'

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST E: Positional scroll verifies actual position (SCROLL_NOT_EFFECTIVE detection)" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Assert-FileContains "E.1 mxScroll is defined" $ScrollHelper 'mxScroll'
Assert-FileContains "E.2 mxScroll reads scrollTop after setting it" $ScrollHelper 'after.*scrollTop|scrollTop.*after'
Assert-FileContains "E.3 SCROLL_NOT_EFFECTIVE returned when scroll did not take effect" $ScrollHelper 'SCROLL_NOT_EFFECTIVE'
Assert-FileContains "E.4 mxScroll checks |after - clamped| for effectiveness" $ScrollHelper 'clamped'
Assert-FileContains "E.5 mxScroll exported from module" $ScrollHelper 'module\.exports[\s\S]{1,500}mxScroll'

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST F: window.scrollTo is NOT used as the primary scroll mechanism" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Assert-FileNotContains "F.1 mx-scroll.js does not call window.scrollTo" $ScrollHelper 'window\.scrollTo\s*\('
Assert-FileNotContains "F.2 mx-scroll.js does not assign document.body.scrollTop" $ScrollHelper 'document\.body\.scrollTop\s*='
Assert-FileNotContains "F.3 mx-scroll-shell.sh does not call window.scrollTo" $ShellHelper 'window\.scrollTo\s*\('
Assert-FileContains "F.4 skill explicitly warns against window.scrollTo" $Skill 'window\.scrollTo'
Assert-FileContains "F.5 skill labels window.scrollTo as WRONG" $Skill 'WRONG|Incorrect Assumption|incorrect assumption'

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST G: Element-based scrolling (scrollIntoView) is supported" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Assert-FileContains "G.1 mxScrollToElement is defined" $ScrollHelper 'mxScrollToElement'
Assert-FileContains "G.2 scrollIntoView is used in mxScrollToElement" $ScrollHelper 'scrollIntoView'
Assert-FileContains "G.3 mxScrollToElement exported from module" $ScrollHelper 'module\.exports[\s\S]{1,500}mxScrollToElement'
Assert-FileContains "G.4 shell helper mx_element_scroll is defined" $ShellHelper 'mx_element_scroll'
Assert-FileContains "G.5 skill distinguishes positional vs element scrolling" $Skill 'POSITIONAL SCROLL|Positional scroll|positional.*scroll|When to Use Each'

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST H: Viewport coverage generates stops from runtime dimensions" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Assert-FileContains "H.1 mxViewportCoverage is defined" $ScrollHelper 'mxViewportCoverage'
Assert-FileContains "H.2 mxViewportCoverage uses scrollHeight from runtime" $ScrollHelper 'scrollHeight'
Assert-FileContains "H.3 mxViewportCoverage uses clientHeight from runtime" $ScrollHelper 'clientHeight'
Assert-FileContains "H.4 mxViewportCoverage returns suggestedStops array" $ScrollHelper 'suggestedStops'
Assert-FileContains "H.5 mxViewportCoverage exported from module" $ScrollHelper 'module\.exports[\s\S]{1,500}mxViewportCoverage'
Assert-FileContains "H.6 shell helper mx_viewport_coverage is defined" $ShellHelper 'mx_viewport_coverage'
Assert-FileContains "H.7 skill shows mxViewportCoverage usage example" $Skill 'mxViewportCoverage'

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST I: Shell helper exists for playwright-cli .test.sh scripts" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Assert-FileContains "I.1 mx_scroll function defined in shell helper" $ShellHelper 'mx_scroll\(\)'
Assert-FileContains "I.2 mx_scroll_discover function defined" $ShellHelper 'mx_scroll_discover\(\)'
Assert-FileContains "I.3 shell helper sources playwright-cli eval" $ShellHelper 'playwright-cli eval'
Assert-FileContains "I.4 shell helper documents how to source it" $ShellHelper 'source.*mx-scroll-shell'
Assert-FileContains "I.5 MX_SCROLL_SETTLE_MS is configurable" $ShellHelper 'MX_SCROLL_SETTLE_MS'

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST J: Skill documentation covers the required behavioral contract" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Assert-FileContains "J.1 skill covers Mendix scrolling behavior section" $Skill 'Mendix Scrolling Behavior|Mendix scrolling'
Assert-FileContains "J.2 skill explains Atlas layout container" $Skill 'Atlas'
Assert-FileContains "J.3 skill shows canonical helper usage example" $Skill 'discoverScrollContainer'
Assert-FileContains "J.4 skill documents discovery priority order" $Skill 'Priority|priority'
Assert-FileContains "J.5 skill documents evidence completeness rule" $Skill 'Evidence Completeness|evidence completeness'
Assert-FileContains "J.6 skill explains why fullPage:true does not work" $Skill 'fullPage'
Assert-FileContains "J.7 skill describes stabilization strategy" $Skill 'settleMs|stabiliz'

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST K: Spec file and fixture files exist for framework regression coverage" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Assert-True "K.1 .playwright/tests/mx-scroll.spec.js exists" (Test-Path $SpecFile) "Spec file not found"
Assert-True "K.2 fixture mx-scroll-simple.html exists"         (Test-Path (Join-Path $FixturesDir 'mx-scroll-simple.html')) "Fixture not found"
Assert-True "K.3 fixture mx-scroll-center.html exists"         (Test-Path (Join-Path $FixturesDir 'mx-scroll-center.html')) "Fixture not found"
Assert-True "K.4 fixture mx-scroll-sidebar-center.html exists" (Test-Path (Join-Path $FixturesDir 'mx-scroll-sidebar-center.html')) "Fixture not found"
Assert-True "K.5 fixture mx-scroll-widgets.html exists"        (Test-Path (Join-Path $FixturesDir 'mx-scroll-widgets.html')) "Fixture not found"
Assert-True "K.6 fixture mx-scroll-noscroll.html exists"       (Test-Path (Join-Path $FixturesDir 'mx-scroll-noscroll.html')) "Fixture not found"
Assert-True "K.7 fixture mx-scroll-ineffective.html exists"    (Test-Path (Join-Path $FixturesDir 'mx-scroll-ineffective.html')) "Fixture not found"

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST L: Discovery result codes are clearly named" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Assert-FileContains "L.1 RESULT object is frozen/const" $ScrollHelper 'Object\.freeze|const RESULT'
Assert-FileContains "L.2 RESULT exported as named export" $ScrollHelper 'RESULT'
Assert-FileContains "L.3 spec file asserts RESULT codes" $SpecFile 'RESULT\.'
Assert-FileContains "L.4 CLAMPED_TO_MAX in shell output" $ShellHelper 'CLAMPED_TO_MAX'

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST M: No project-specific logic leaked into MxAgile Core" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Assert-FileNotContains "M.1 mx-scroll.js does not mention CapTrack" $ScrollHelper 'CapTrack|captrack'
Assert-FileNotContains "M.2 mx-scroll-shell.sh does not mention CapTrack" $ShellHelper 'CapTrack|captrack'
Assert-FileNotContains "M.3 mx-scroll.js does not hardcode a page height like 5201" $ScrollHelper '5201'
Assert-FileNotContains "M.4 mx-scroll.js does not hardcode specific stop positions" $ScrollHelper '= 700|= 1400|= 2100'
Assert-FileNotContains "M.5 visual-verification.md does not reference CapTrack as owner" $Skill 'CapTrack is the canonical|owned by CapTrack'

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST N: Evidence safety rule — SCROLL_NOT_EFFECTIVE prevents false PASS" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Assert-FileContains "N.1 skill states SCROLL_NOT_EFFECTIVE must prevent PASS" $Skill 'SCROLL_NOT_EFFECTIVE'
Assert-FileContains "N.2 skill shows evidence safety code example" $Skill 'SCROLL_NOT_EFFECTIVE.*PASS|false.*PASS|false confidence'
Assert-FileContains "N.3 spec TC-08 tests SCROLL_NOT_EFFECTIVE detection" $SpecFile 'SCROLL_NOT_EFFECTIVE'
Assert-FileContains "N.4 mxScroll compares before vs after to detect no-op" $ScrollHelper 'before.*after|after.*before'

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST O: mxcli capability findings documented accurately" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Assert-FileContains "O.1 skill documents verified mxcli playwright commands" $Skill 'mxcli playwright'
Assert-FileContains "O.2 skill states no --full-page flag exists" $Skill 'full-page|full_page|fullPage'
Assert-FileContains "O.3 skill explains why fullPage:true does not solve nested containers" $Skill 'document.*scroll|nested.*scroll|document layer'
Assert-FileNotContains "O.4 skill does not claim a --full-page flag exists" $Skill '\-\-full-page flag.*available|\-\-full-page.*supported'

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=" * 60
$total = $PassCount + $FailCount
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
