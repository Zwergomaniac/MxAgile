<#
.SYNOPSIS
    UI Element Selection Tests: Intent-Driven Widget Selection Contract

.DESCRIPTION
    Validates that MxAgile canonical guidance enforces intent-driven UI element selection,
    prevents automatic default widget mappings, and requires documented fit rationale.

    Test cases:
    A. Collection/list does not automatically select Data Grid 2
    B. Attribute does not automatically select Text Box
    C. Read-only attribute does not automatically render as disabled input
    D. Genuinely tabular sortable/filterable requirement may select Data Grid 2
    E. Responsive card/list requirement evaluates non-grid alternatives
    F. UI inventory distinguishes pattern from candidate widget
    G. Widget candidate remains non-authoritative until Refinement
    H. Selected widget requires fit rationale
    I. High-fidelity UI-driven spec includes live verification plan
    J. Company Layer components are considered where applicable
    K. Custom widget is not selected before simpler valid options are assessed
    L. Runtime evidence can invalidate prior candidate selection
    M. Requirement/Spec/Task traceability survives widget reconsideration
    N. Display/edit semantics remain role-correct
    O. Accessibility criteria affect widget selection
    P. Performance criteria affect widget selection
    Q. Default Mendix styling is not accepted where visual contract differs
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

$UiSelPol   = Join-Path $ScriptDir ".mxagile/policies/ui-element-selection.md"
$PageSchema = Join-Path $ScriptDir ".mxagile/schemas/page.schema.json"
$UiAgent    = Join-Path $ScriptDir ".mxagile/agents/ui-agent.md"
$GateReady  = Join-Path $ScriptDir ".mxagile/skills/gate-to-ready.md"

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST A: Collection/list does not automatically select Data Grid 2" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Assert-FileContains "A.1 ui-element-selection.md explicitly states Data Grid 2 is not the default" $UiSelPol 'Data Grid 2 Is Not the Default'
Assert-FileContains "A.2 policy lists forbidden selection reasons (multiple objects exist)" $UiSelPol 'Multiple objects exist'
Assert-FileContains "A.3 policy lists alternatives to Data Grid 2" $UiSelPol 'List View'
Assert-FileContains "A.4 ui-agent.md warns against Data Grid 2 as automatic choice" $UiAgent 'Data Grid 2'

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST B: Attribute does not automatically select Text Box" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Assert-FileContains "B.1 ui-element-selection.md states attribute does not imply Text Box" $UiSelPol 'entity attribute does NOT imply'
Assert-FileContains "B.2 policy distinguishes display from input semantics" $UiSelPol 'Display.*Input'
Assert-FileContains "B.3 page schema has display_mode field" $PageSchema 'display_mode'

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST C: Read-only attribute does not automatically render as disabled input" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Assert-FileContains "C.1 ui-element-selection.md defines read-only display contract" $UiSelPol 'Read-Only Display'
Assert-FileContains "C.2 policy states disabled input is not an automatic fallback" $UiSelPol 'disabled.*input'
Assert-FileContains "C.3 policy requires justification for disabled input" $UiSelPol 'Disabled Input Anti-Pattern'
Assert-FileContains "C.4 policy lists display-only widget patterns" $UiSelPol 'Dynamic Text'

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST D: Genuinely tabular requirement may select Data Grid 2" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Assert-FileContains "D.1 policy documents valid fit signals for Data Grid 2" $UiSelPol 'Valid fit signals for Data Grid 2'
Assert-FileContains "D.2 policy includes column-based comparison as fit signal" $UiSelPol 'Column-based comparison'
Assert-FileContains "D.3 policy does not prohibit Data Grid 2" $UiSelPol 'Do not prohibit Data Grid 2'

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST E: Responsive card/list requirement evaluates non-grid alternatives" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Assert-FileContains "E.1 policy Data Grid 2 fit check asks about mobile/narrow-width behavior" $UiSelPol 'mobile'
Assert-FileContains "E.2 policy lists responsive_record_list as a UI pattern" $UiSelPol 'responsive_record_list'
Assert-FileContains "E.3 policy lists card_collection as a UI pattern" $UiSelPol 'card_collection'
Assert-FileContains "E.4 alternatives section includes List View" $UiSelPol 'List View'

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST F: UI inventory distinguishes pattern from candidate widget" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Assert-FileContains "F.1 page schema has ui_pattern field" $PageSchema 'ui_pattern'
Assert-FileContains "F.2 page schema has widget_candidate field separate from ui_pattern" $PageSchema 'widget_candidate'
Assert-FileContains "F.3 ui_pattern description says not yet a Mendix widget" $PageSchema 'pattern is not yet'
Assert-FileContains "F.4 ui-element-selection.md separates pattern from widget" $UiSelPol 'Separate UI Pattern from Mendix Widget'

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST G: Widget candidate is non-authoritative until Refinement" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Assert-FileContains "G.1 page schema has candidate_confidence field" $PageSchema 'candidate_confidence'
Assert-FileContains "G.2 candidate_confidence has preliminary level" $PageSchema '"preliminary"'
Assert-FileContains "G.3 policy states preliminary candidates are hypotheses" $UiSelPol 'Widget Suggestions Are Hypotheses'
Assert-FileContains "G.4 gate-to-ready requires assessed confidence before passing" $GateReady 'candidate_confidence'
Assert-FileContains "G.5 gate-to-ready blocks preliminary confidence for ui_driven" $GateReady 'preliminary.*Blocker'

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST H: Selected widget requires fit rationale" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Assert-FileContains "H.1 page schema has fit_rationale field" $PageSchema 'fit_rationale'
Assert-FileContains "H.2 fit_rationale required when confidence is assessed" $PageSchema 'candidate_confidence is assessed'
Assert-FileContains "H.3 gate-to-ready requires fit_rationale for assessed confidence" $GateReady 'fit_rationale'
Assert-FileContains "H.4 ui-element-selection.md defines fit criteria" $UiSelPol 'Data Grid 2 Fit Check'

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST I: High-fidelity spec includes live verification plan" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Assert-FileContains "I.1 ui-element-selection.md requires live widget-fit validation" $UiSelPol 'Live Widget-Fit Validation'
Assert-FileContains "I.2 candidate_confidence has validated level for browser evidence" $PageSchema '"validated"'
Assert-FileContains "I.3 validated requires browser evidence from Verify mode" $UiSelPol 'browser evidence from UI-Agent Verify'
Assert-FileContains "I.4 assessed vs validated distinction exists in schema description" $PageSchema 'validated=confirmed in running browser'

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST J: Company Layer components are considered where applicable" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Assert-FileContains "J.1 ui-element-selection.md defines Company Layer First principle" $UiSelPol 'Company Layer.*Design System First'
Assert-FileContains "J.2 selection order places Company Layer above raw standard widget" $UiSelPol 'Company Layer component'
Assert-FileContains "J.3 ui-agent.md references Company Layer in selection step" $UiAgent 'Company Layer'
Assert-FileContains "J.4 gate-to-ready requires Company Layer constraints checked" $GateReady 'Company Layer'

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST K: Custom widget not selected before simpler options assessed" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Assert-FileContains "K.1 ui-element-selection.md defines escalation ladder" $UiSelPol 'Widget Escalation Ladder'
Assert-FileContains "K.2 escalation ladder places custom widget last" $UiSelPol 'Custom widget.*document'
Assert-FileContains "K.3 policy prohibits jumping directly to custom widget" $UiSelPol 'Custom Widget Conditions'
Assert-FileContains "K.4 policy warns against opposite failure mode" $UiSelPol 'opposite failure mode'

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST L: Runtime evidence can invalidate prior candidate selection" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Assert-FileContains "L.1 ui-element-selection.md covers implementation reconsideration" $UiSelPol 'previous widget suggestion is not immutable'
Assert-FileContains "L.2 policy allows widget replacement when justified" $UiSelPol 'Replace the widget when justified'
Assert-FileContains "L.3 candidate_confidence validated requires running-app evidence" $PageSchema 'running browser'

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST M: Requirement/Spec/Task traceability survives widget reconsideration" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Assert-FileContains "M.1 ui-element-selection.md states reconsideration preserves evidence" $UiSelPol 'preserve evidence'
Assert-FileContains "M.2 gate-to-ready checklist has req traceability per item" $GateReady 'req:'

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST N: Display/edit semantics remain role-correct" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Assert-FileContains "N.1 ui-element-selection.md covers role-dependent display/edit" $UiSelPol 'Role-Dependent'
Assert-FileContains "N.2 policy states editable roles get input, read-only roles get display" $UiSelPol 'Editable roles'
Assert-FileContains "N.3 page schema has display_mode enum with display and input values" $PageSchema '"display"'

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST O: Accessibility criteria affect widget selection" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Assert-FileContains "O.1 ui-element-selection.md covers accessibility" $UiSelPol 'Accessibility and Semantics'
Assert-FileContains "O.2 policy warns against input controls for display-only content" $UiSelPol 'input controls for display-only content'
Assert-FileContains "O.3 policy covers keyboard navigation" $UiSelPol 'Keyboard navigation'

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST P: Performance criteria affect widget selection" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Assert-FileContains "P.1 ui-element-selection.md covers performance and scale" $UiSelPol 'Performance and Scale'
Assert-FileContains "P.2 policy covers virtualization in Data Grid 2 fit check" $UiSelPol 'virtualization'
Assert-FileContains "P.3 policy states performance rationale must be documented" $UiSelPol 'Performance rationale must be documented'

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST Q: Default Mendix styling not accepted where visual contract differs" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Assert-FileContains "Q.1 ui-element-selection.md states default widget is not visual acceptance" $UiSelPol 'not sufficient'
Assert-FileContains "Q.2 policy requires visual contract satisfaction beyond compilation" $UiSelPol 'compiles'
Assert-FileContains "Q.3 gate-to-ready has live verification requirement for ui_driven" $GateReady 'layout_reference'

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
