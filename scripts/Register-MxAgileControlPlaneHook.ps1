[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$SettingsPath,

    [switch]$Remove
)

# Structured PreToolUse registration of the MxAgile control-plane adapter in Claude settings.
# Ownership: only hook entries whose command contains $Marker are FRAMEWORK_OWNED_GENERATED;
# every other entry is preserved untouched. Unparseable settings are UNKNOWN and never rewritten.

$ErrorActionPreference = 'Stop'
$Marker = '.mxagile/tools/control-plane/enforcement.py'
$Matcher = 'Write|Edit|MultiEdit|NotebookEdit|Bash|Task|Agent|mcp__.*'
# Exit 2 makes Claude block the call when the adapter itself cannot run (fail-closed).
$Command = 'python -B "$CLAUDE_PROJECT_DIR/.mxagile/tools/control-plane/enforcement.py" || exit 2'

function Write-Status { param([string]$Status, [string]$Detail) [ordered]@{ status = $Status; settings = $SettingsPath; detail = $Detail } | ConvertTo-Json -Compress }

function Test-OwnedGroup {
    param([object]$Group)
    $hooks = $Group.PSObject.Properties['hooks']
    if (-not $hooks -or $hooks.Value -isnot [System.Array]) { return $false }
    $owned = @($hooks.Value | Where-Object { $_.PSObject.Properties['command'] -and ([string]$_.command).Contains($Marker) })
    return $owned.Count -gt 0
}

$settings = $null
if (Test-Path -LiteralPath $SettingsPath -PathType Leaf) {
    $original = [System.IO.File]::ReadAllText($SettingsPath)
    try { $settings = ConvertFrom-Json -InputObject $original -ErrorAction Stop } catch {
        Write-Status 'UNKNOWN_OWNERSHIP' 'settings.json is not valid JSON; not modified.'; exit 3
    }
    if ($settings -isnot [System.Management.Automation.PSCustomObject]) {
        Write-Status 'UNKNOWN_OWNERSHIP' 'settings.json is not a JSON object; not modified.'; exit 3
    }
} elseif ($Remove) {
    Write-Status 'NOT_REGISTERED' 'settings.json absent.'; exit 0
} else {
    $settings = [pscustomobject]@{}
    $original = $null
}

$hooksProperty = $settings.PSObject.Properties['hooks']
if ($hooksProperty -and $hooksProperty.Value -isnot [System.Management.Automation.PSCustomObject]) {
    Write-Status 'UNKNOWN_OWNERSHIP' 'hooks is not an object; not modified.'; exit 3
}
if (-not $hooksProperty) {
    if ($Remove) { Write-Status 'NOT_REGISTERED' 'no hooks.'; exit 0 }
    $settings | Add-Member -NotePropertyName hooks -NotePropertyValue ([pscustomobject]@{})
    $hooksProperty = $settings.PSObject.Properties['hooks']
}
$preTool = $hooksProperty.Value.PSObject.Properties['PreToolUse']
if ($preTool -and $preTool.Value -isnot [System.Array]) {
    Write-Status 'UNKNOWN_OWNERSHIP' 'PreToolUse is not an array; not modified.'; exit 3
}
$foreign = @(if ($preTool) { $preTool.Value | Where-Object { -not (Test-OwnedGroup $_) } })
$ownedBefore = @(if ($preTool) { $preTool.Value | Where-Object { Test-OwnedGroup $_ } })
foreach ($group in $ownedBefore) {
    if (@($group.hooks | Where-Object { -not ($_.PSObject.Properties['command'] -and ([string]$_.command).Contains($Marker)) }).Count -gt 0) {
        Write-Status 'UNKNOWN_OWNERSHIP' 'a PreToolUse group mixes the MxAgile adapter with foreign hooks; not modified.'; exit 3
    }
}

if ($Remove) {
    if ($ownedBefore.Count -eq 0) { Write-Status 'NOT_REGISTERED' 'no MxAgile entry.'; exit 0 }
    if ($foreign.Count -gt 0) { $preTool.Value = $foreign } else { $hooksProperty.Value.PSObject.Properties.Remove('PreToolUse') }
    $status = 'REMOVED'
} else {
    $group = [pscustomobject]@{ matcher = $Matcher; hooks = @([pscustomobject]@{ type = 'command'; command = $Command; timeout = 60 }) }
    $desired = @($group) + $foreign
    if ($preTool) { $preTool.Value = $desired } else { $hooksProperty.Value | Add-Member -NotePropertyName PreToolUse -NotePropertyValue $desired }
    $status = if ($ownedBefore.Count -eq 0) { 'REGISTERED' } else { 'CURRENT' }
}

$json = (ConvertTo-Json -InputObject $settings -Depth 100) + [Environment]::NewLine
if ($null -ne $original -and $json -eq $original) { Write-Status $status 'unchanged'; exit 0 }
if ($status -eq 'CURRENT') { $status = 'UPDATED' }
$directory = Split-Path -Parent $SettingsPath
if (-not (Test-Path -LiteralPath $directory)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
$temporary = "$SettingsPath.$([guid]::NewGuid().ToString('N')).tmp"
[System.IO.File]::WriteAllText($temporary, $json, [System.Text.UTF8Encoding]::new($false))
Move-Item -LiteralPath $temporary -Destination $SettingsPath -Force
Write-Status $status "MxAgile entry first; $($foreign.Count) foreign PreToolUse group(s) preserved."
exit 0
