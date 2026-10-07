#Requires -Version 7
<#
.SYNOPSIS
    Phase 6 Transformation Spec Executor — applies a Transformation Spec to an HTML mockup file.

.DESCRIPTION
    Implements the Phase 6 execution logic from mocketeer-agent.md.
    This is the ONLY authorized path for targeted HTML file mutation driven by a
    mocketeer-transformation-spec. It enforces all fail-closed checks, applies operations
    scoped to target elements only, validates preservation, updates the Design Contract,
    and writes the result to OutputFile (or in-place if OutputFile is omitted).

    On any failure the source file is left unchanged and exit code 1 is returned.
    On success exit code 0 is returned and the output file is written.

.PARAMETER HtmlFile
    Path to the source HTML file containing the Design Contract.

.PARAMETER SpecFile
    Path to the JSON file containing the transformation_spec (or an M365 handoff wrapper
    with a transformation_spec property).

.PARAMETER OutputFile
    Output path for the transformed HTML. If omitted, the source file is updated in-place.

.PARAMETER DryRun
    Validate and simulate only — do not write any file.
#>
param(
    [Parameter(Mandatory)][string]$HtmlFile,
    [Parameter(Mandatory)][string]$SpecFile,
    [string]$OutputFile,
    [switch]$DryRun
)

# Explicit error handling — do not rely on $ErrorActionPreference propagation
$ErrorActionPreference = 'Continue'

# ─── Helpers ─────────────────────────────────────────────────────────────────

function Fail {
    param([string]$Code, [string]$Message)
    [Console]::Error.WriteLine("[$Code] $Message")
    exit 1
}

function Find-ClosingTagEnd {
    # Returns the index AFTER the matching closing tag, or -1 if not found.
    param([string]$Html, [string]$TagName, [int]$AfterOpen)
    $closeStr = "</$TagName>"
    $openPat  = [regex]("(?i)<" + [regex]::Escape($TagName) + "(?=[>\s])")
    $depth = 1
    $pos   = $AfterOpen

    while ($depth -gt 0 -and $pos -lt $Html.Length) {
        $nextCloseIdx = $Html.IndexOf($closeStr, $pos, [System.StringComparison]::OrdinalIgnoreCase)
        if ($nextCloseIdx -lt 0) { return -1 }

        $nextOpenMatch = $openPat.Match($Html, $pos)

        if ($nextOpenMatch.Success -and $nextOpenMatch.Index -lt $nextCloseIdx) {
            $depth++
            $pos = $nextOpenMatch.Index + $nextOpenMatch.Length
        } else {
            $depth--
            if ($depth -eq 0) {
                return $nextCloseIdx + $closeStr.Length
            }
            $pos = $nextCloseIdx + $closeStr.Length
        }
    }
    return -1
}

function Find-ElementsByComponent {
    # Returns array of {StartIdx, EndIdx, Content, ScreenId, TagName} for all
    # elements matching [data-mx-component='ComponentName'].
    param([string]$Html, [string]$ComponentName)
    $blocks  = [System.Collections.Generic.List[object]]::new()
    $escaped = [regex]::Escape($ComponentName)
    $openPat = [regex]("(?i)<(\w+)(?=[^>]*\bdata-mx-component=['""]" + $escaped + "['""])[^>]*>")
    $searchFrom = 0

    while ($true) {
        $m = $openPat.Match($Html, $searchFrom)
        if (-not $m.Success) { break }

        $tagName   = $m.Groups[1].Value
        $elemStart = $m.Index
        $afterOpen = $m.Index + $m.Length

        $screenId = $null
        if ($m.Value -match 'data-mx-screen="([^"]+)"')  { $screenId = $Matches[1] }
        elseif ($m.Value -match "data-mx-screen='([^']+)'") { $screenId = $Matches[1] }

        $elemEnd = Find-ClosingTagEnd -Html $Html -TagName $tagName -AfterOpen $afterOpen
        if ($elemEnd -lt 0) {
            Write-Warning "Unclosed <$tagName> element with data-mx-component='$ComponentName' at pos $elemStart — skipping"
            $searchFrom = $afterOpen
            continue
        }

        $blocks.Add([PSCustomObject]@{
            StartIdx = $elemStart
            EndIdx   = $elemEnd
            Content  = $Html.Substring($elemStart, $elemEnd - $elemStart)
            ScreenId = $screenId
            TagName  = $tagName
        })
        $searchFrom = $elemEnd
    }
    return $blocks
}

function Replace-InTextNodes {
    # Replaces $Find with $Replace only within text nodes (between > and <),
    # leaving HTML tags and attribute values untouched.
    param([string]$ElementHtml, [string]$Find, [string]$Replace)
    return [regex]::Replace($ElementHtml, '(?<=>)([^<]+)(?=<)', {
        param($m)
        $m.Value.Replace($Find, $Replace)
    })
}

function Get-TextContent {
    # Returns all text node content concatenated from an HTML element string.
    param([string]$Html)
    $parts = [regex]::Matches($Html, '(?<=>)([^<]+)(?=<)') |
             ForEach-Object { $_.Value.Trim() } |
             Where-Object { $_ -ne '' }
    return $parts -join ' '
}

function Get-StableIds {
    # Extracts all data-mx-* attribute values from HTML (these are stable IDs).
    param([string]$Html)
    $ids = [regex]::Matches($Html, '\bdata-mx-[\w-]+="([^"]+)"') |
           ForEach-Object { $_.Groups[1].Value }
    return ($ids | Sort-Object -Unique)
}

function Get-DesignContract {
    # Extracts and parses the Design Contract JSON from <script id="mocketeer-spec">.
    param([string]$Html)
    if ($Html -match '(?s)<script[^>]+id="mocketeer-spec"[^>]*>(.*?)</script>') {
        $json = $Matches[1].Trim()
        try { return $json | ConvertFrom-Json -Depth 30 }
        catch { return $null }
    }
    return $null
}

function Set-DesignContract {
    # Replaces the Design Contract JSON in the HTML with the updated contract object.
    param([string]$Html, [object]$Contract)
    $newJson = $Contract | ConvertTo-Json -Depth 30
    return [regex]::Replace($Html, '(?s)(<script[^>]+id="mocketeer-spec"[^>]*>)(.*?)(</script>)', {
        param($m)
        $m.Groups[1].Value + "`n" + $newJson + "`n" + $m.Groups[3].Value
    })
}

function Parse-AttributeSelector {
    # Parses [attr='value'] or [attr="value"] CSS attribute selectors.
    # Returns @{Attribute; Value} or $null if unsupported syntax.
    param([string]$Selector)
    if ($Selector -match "^\[([a-z][a-z0-9-]+)=['""]([^'""]+)['""]\]$") {
        return @{ Attribute = $Matches[1]; Value = $Matches[2] }
    }
    return $null
}

# ─── Input validation ─────────────────────────────────────────────────────────

if (-not (Test-Path $HtmlFile)) { Fail 'FAIL_FILE_NOT_FOUND' "HTML file not found: $HtmlFile" }
if (-not (Test-Path $SpecFile))  { Fail 'FAIL_FILE_NOT_FOUND' "Spec file not found: $SpecFile"  }

$originalHtml = $null
try { $originalHtml = [System.IO.File]::ReadAllText($HtmlFile, [System.Text.Encoding]::UTF8) }
catch { Fail 'FAIL_FILE_NOT_FOUND' "Cannot read HTML file: $_" }

$specJson = $null
try { $specJson = [System.IO.File]::ReadAllText($SpecFile, [System.Text.Encoding]::UTF8) }
catch { Fail 'FAIL_FILE_NOT_FOUND' "Cannot read spec file: $_" }

$specRoot = $null
try { $specRoot = $specJson | ConvertFrom-Json -Depth 30 }
catch { Fail 'FAIL_INVALID_SPEC' "Spec file is not valid JSON: $_" }

# Support both direct spec and M365 handoff wrapper
$spec = $null
if ($null -ne $specRoot.transformation_spec) {
    $spec = $specRoot.transformation_spec
} else {
    $spec = $specRoot
}

if ($null -eq $spec) { Fail 'FAIL_INVALID_SPEC' "No transformation_spec found in spec file" }

# Required field checks
foreach ($field in @('spec_id', 'change_class', 'source_revision', 'target_revision', 'operations')) {
    if ($null -eq $spec.PSObject.Properties[$field]) {
        Fail 'FAIL_INVALID_SPEC' "Missing required field in transformation_spec: $field"
    }
}
if ($spec.operations.Count -eq 0) { Fail 'FAIL_INVALID_SPEC' "operations[] must not be empty" }

# Phase 6 only handles LOCAL_EDIT or CROSS_CUTTING_EDIT
if ($spec.change_class -notin @('LOCAL_EDIT', 'CROSS_CUTTING_EDIT')) {
    Fail 'FAIL_INVALID_CHANGE_CLASS' "Phase 6 handles only LOCAL_EDIT or CROSS_CUTTING_EDIT; got: $($spec.change_class)"
}

# Verify source revision matches Design Contract
$contract = Get-DesignContract -Html $originalHtml
if ($null -eq $contract) { Fail 'FAIL_INVALID_SPEC' "No parseable Design Contract (mocketeer-spec) found in HTML file" }

if ([int]$contract.mockup.revision -ne [int]$spec.source_revision) {
    Fail 'FAIL_REVISION_MISMATCH' "HTML Design Contract revision is $($contract.mockup.revision); spec source_revision is $($spec.source_revision)"
}

$originalStableIds = Get-StableIds -Html $originalHtml

Write-Host "Spec     : $($spec.spec_id)"
Write-Host "Class    : $($spec.change_class)"
Write-Host "Revision : $($spec.source_revision) -> $($spec.target_revision)"
Write-Host "Intent   : $($spec.intent)"

# ─── Process operations ───────────────────────────────────────────────────────

$workingHtml      = $originalHtml
$changedScreenIds = [System.Collections.Generic.List[string]]::new()
$totalTargets     = 0
$totalChanged     = 0

foreach ($op in $spec.operations) {
    Write-Host ""
    Write-Host "Op $($op.op_id): $($op.operation) on '$($op.target_selector)'"

    foreach ($f in @('op_id', 'operation')) {
        if ($null -eq $op.PSObject.Properties[$f]) {
            Fail 'FAIL_INVALID_SPEC' "Operation missing field: $f"
        }
    }

    # ── Resolve targets ──────────────────────────────────────────────────────
    $elements = @()

    if ($op.target_selector) {
        $parsed = Parse-AttributeSelector -Selector $op.target_selector
        if ($null -eq $parsed) {
            Fail 'FAIL_INVALID_SPEC' "Unsupported target_selector syntax: '$($op.target_selector)'. Only [attr='value'] is supported."
        }
        if ($parsed.Attribute -eq 'data-mx-component') {
            $elements = Find-ElementsByComponent -Html $workingHtml -ComponentName $parsed.Value
        } else {
            Fail 'FAIL_INVALID_SPEC' "Unsupported selector attribute: '$($parsed.Attribute)'. Only data-mx-component is supported."
        }
    } else {
        Fail 'FAIL_INVALID_SPEC' "Operation $($op.op_id) has no target_selector"
    }

    # ── target_ids filter and validation ─────────────────────────────────────
    $targetIds = @($op.target_ids | Where-Object { $_ -and $_ -ne '' })
    if ($targetIds.Count -gt 0) {
        foreach ($tid in $targetIds) {
            $matched = $elements | Where-Object { $_.ScreenId -eq $tid }
            if ($null -eq $matched -or @($matched).Count -eq 0) {
                Fail 'FAIL_STABLE_ID_NOT_FOUND' "target_id '$tid' not found among matched elements for selector '$($op.target_selector)' (op $($op.op_id))"
            }
        }
        # Narrow to only the specified target_ids
        $elements = @($elements | Where-Object { $_.ScreenId -in $targetIds })
    }

    # ── Match constraints ─────────────────────────────────────────────────────
    $minCount = 1
    $maxCount = $null
    if ($null -ne $op.match_constraint) {
        if ($null -ne $op.match_constraint.min) { $minCount = [int]$op.match_constraint.min }
        if ($null -ne $op.match_constraint.max) { $maxCount = [int]$op.match_constraint.max }
    }

    if ($elements.Count -lt $minCount) {
        Fail 'FAIL_NO_TARGETS_FOUND' "Selector '$($op.target_selector)' matched $($elements.Count) element(s); min=$minCount (op $($op.op_id))"
    }
    if ($null -ne $maxCount -and $elements.Count -gt $maxCount) {
        Fail 'FAIL_UNEXPECTED_MATCH_COUNT' "Selector '$($op.target_selector)' matched $($elements.Count) element(s); max=$maxCount (op $($op.op_id))"
    }

    Write-Host "  Targets found: $($elements.Count) (min=$minCount, max=$(if ($maxCount) { $maxCount } else { 'none' }))"
    $totalTargets += $elements.Count

    # ── Precondition check ────────────────────────────────────────────────────
    if ($op.precondition) {
        foreach ($elem in $elements) {
            $textContent = Get-TextContent -Html $elem.Content
            if ($textContent -notlike "*$($op.precondition)*") {
                $screenLabel = if ($elem.ScreenId) { " screen=$($elem.ScreenId)" } else { '' }
                Fail 'FAIL_PRECONDITION_MISMATCH' "Precondition '$($op.precondition)' not found in text content of target element ($($elem.TagName)$screenLabel) for op $($op.op_id)"
            }
        }
        Write-Host "  Precondition '$($op.precondition)': OK at all $($elements.Count) target(s)"
    }

    # ── Apply transformations (end-to-start to preserve positions) ───────────
    $sortedElements = @($elements | Sort-Object StartIdx -Descending)
    foreach ($elem in $sortedElements) {
        $newContent = $elem.Content

        switch ($op.operation) {
            'TEXT_REPLACE' {
                $newContent = Replace-InTextNodes -ElementHtml $elem.Content -Find $op.precondition -Replace $op.replacement
            }
            'ATTRIBUTE_SET' {
                if (-not $op.PSObject.Properties['target_attribute']) {
                    Fail 'FAIL_INVALID_SPEC' "ATTRIBUTE_SET requires target_attribute field (op $($op.op_id))"
                }
                $attrPat = "(?<=\b" + [regex]::Escape($op.target_attribute) + "=['""])([^'""]+)(?=['""])"
                $newContent = [regex]::Replace($elem.Content, $attrPat, $op.replacement)
            }
            'ELEMENT_REMOVE' {
                $newContent = ''
            }
            default {
                Fail 'FAIL_INVALID_SPEC' "Unsupported operation type: '$($op.operation)' (op $($op.op_id))"
            }
        }

        $workingHtml = $workingHtml.Substring(0, $elem.StartIdx) + $newContent + $workingHtml.Substring($elem.EndIdx)

        if ($elem.ScreenId -and $elem.ScreenId -notin $changedScreenIds) {
            $changedScreenIds.Add($elem.ScreenId)
        }
        $totalChanged++
    }

    Write-Host "  Applied: $($elements.Count) element(s) modified"
}

# ─── Preservation validation ─────────────────────────────────────────────────

Write-Host ""
Write-Host "Preservation check..."

$newStableIds  = Get-StableIds -Html $workingHtml
$missingIds    = @($originalStableIds | Where-Object { $_ -notin $newStableIds })

if ($missingIds.Count -gt 0) {
    $rollbackNote = if ($spec.rollback_on_failure -eq $true) { ' — source file unchanged (rollback)' } else { '' }
    Fail 'FAIL_PRESERVATION' "Stable IDs missing after transformation$rollbackNote : $($missingIds -join ', ')"
}

$newContract = Get-DesignContract -Html $workingHtml
if ($null -eq $newContract) {
    Fail 'FAIL_PRESERVATION' "Design Contract is no longer valid JSON after transformation — source file unchanged (rollback)"
}

$preservedIds = @($originalStableIds | Where-Object { $_ -notin $changedScreenIds })
Write-Host "  Result   : VERIFIED"
Write-Host "  Preserved: $($preservedIds.Count) stable ID(s)"
Write-Host "  Changed  : $($changedScreenIds.Count) screen(s) — $($changedScreenIds -join ', ')"

# ─── Update Design Contract ───────────────────────────────────────────────────

Write-Host ""
Write-Host "Updating Design Contract..."

$updatedContract = Get-DesignContract -Html $workingHtml

# Revision metadata
$updatedContract.mockup.revision         = [int]$spec.target_revision
$updatedContract.mockup.previous_revision = [int]$spec.source_revision
$updatedContract.mockup.lifecycle_status = 'REFINED_TARGET'
$updatedContract.mockup.refinement_status = 'PROPOSED'
$updatedContract.mockup.active_target    = $false
$updatedContract.mockup.change_scope     = if ($spec.intent) { $spec.intent } else { "Transformation Spec $($spec.spec_id)" }

# Revision history entry
$histEntry = [PSCustomObject]@{
    revision       = [int]$spec.target_revision
    date           = (Get-Date -Format 'yyyy-MM-dd')
    status         = 'PROPOSED'
    change_summary = @("Transformation ($($spec.change_class)): $($spec.intent)")
    source_spec    = $spec.spec_id
}
$existing = if ($updatedContract.revision_history) { @($updatedContract.revision_history) } else { @() }
$updatedContract.revision_history = $existing + $histEntry

# Revision delta — only UI effects when business_flow_impact is not NONE
$effects = @()
if ($spec.business_flow_impact -and $spec.business_flow_impact -ne 'NONE') {
    foreach ($sid in $changedScreenIds) {
        $pageSuffix = $sid -replace '^SCREEN-', ''
        $effects += [PSCustomObject]@{
            type                 = 'UI'
            change               = 'UPDATE'
            required_action      = 'VERIFY'
            source_ids           = @($sid)
            downstream_artifacts = @("PAGE-$pageSuffix")
        }
    }
}
$updatedContract.revision_delta = [PSCustomObject]@{
    from_revision = [int]$spec.source_revision
    to_revision   = [int]$spec.target_revision
    affected_ids  = @($changedScreenIds)
    effects       = $effects
}

# Preservation block
$updatedContract.preservation = [PSCustomObject]@{
    result     = 'VERIFIED'
    checked_at = "revision:$($spec.target_revision)"
    preserved  = $preservedIds
    changed    = @($changedScreenIds)
    removed    = @()
}

# Embed transformation_spec for audit trail
if ($null -eq $updatedContract.PSObject.Properties['transformation_spec']) {
    $updatedContract | Add-Member -NotePropertyName 'transformation_spec' -NotePropertyValue $spec
} else {
    $updatedContract.transformation_spec = $spec
}

$finalHtml = Set-DesignContract -Html $workingHtml -Contract $updatedContract

Write-Host "  Revision : $($spec.source_revision) -> $($spec.target_revision)"
Write-Host "  Status   : REFINED_TARGET / PROPOSED / active_target=false"
Write-Host "  Flow effects: $(if ($effects.Count -eq 0) { 'none (business_flow_impact=NONE)' } else { $effects.Count })"

# ─── Write output ─────────────────────────────────────────────────────────────

if (-not $DryRun) {
    $outPath = if ($OutputFile) { $OutputFile } else { $HtmlFile }
    try {
        $outDir = Split-Path $outPath -Parent
        if ($outDir -and -not (Test-Path $outDir)) {
            New-Item -ItemType Directory -Path $outDir -Force | Out-Null
        }
        [System.IO.File]::WriteAllText($outPath, $finalHtml, [System.Text.Encoding]::UTF8)
        Write-Host ""
        Write-Host "Written  : $outPath"
    } catch {
        Fail 'FAIL_WRITE' "Cannot write output file '$outPath': $_"
    }
}

Write-Host ""
Write-Host "PASS: $($spec.spec_id) — $totalTargets target(s), $totalChanged changed, rev $($spec.source_revision)->$($spec.target_revision)"
exit 0
