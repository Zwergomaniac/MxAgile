[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$SettingsPath
)

$ErrorActionPreference = 'Stop'

function Get-Property {
    param([object]$Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    return $Object.PSObject.Properties[$Name]
}

function Get-CommandDisposition {
    param([string]$Command)

    if ($Command -match '(?i)\.claude/bootstrap-mxcli\.sh') {
        if ($Command -match '(?i)^\s*(?:(?:exec|command)\s+)*(?:sh|bash)\s+["'']?\.claude/bootstrap-mxcli\.sh["'']?(?:\s*\|\|\s*true)?\s*$') {
            return 'REMOVE'
        }
        return 'AMBIGUOUS'
    }

    $mentionsMxcli = $Command -match '(?i)(?:\bmxcli(?:\.exe)?\b|\$\{?MXCLI\}?)'
    $runsLocally = $Command -match '(?is)\brun\b.*(?:--local\b|--setup\b|--ensure-db\b)|(?:--local\b|--setup\b|--ensure-db\b).*\brun\b'
    if (-not ($mentionsMxcli -and $runsLocally)) { return 'KEEP' }

    $directCommand = $Command -match '(?is)^\s*(?:(?:exec|command)\s+)*(?:(?:[A-Za-z_][A-Za-z0-9_]*=(?:"[^"]*"|''[^'']*''|\S+)\s+)*)(?:(?:\./)?mxcli(?:\.exe)?|["'']?\$\{?MXCLI\}?["'']?)\s+run\b(?<args>.*)$'
    if ($directCommand) {
        $arguments = [regex]::Match($Command, '(?is)\s+run\b(?<args>.*)$').Groups['args'].Value
        if ($arguments -match '[|;&<>`]') { return 'AMBIGUOUS' }
        if ($Command -match '(?i)\$\{?MXCLI\}?') {
            if ($Command -notmatch '(?im)^\s*(?:export\s+)?MXCLI\s*=\s*["'']?(?:\./)?mxcli(?:\.exe)?["'']?\s*;?\s*$') { return 'AMBIGUOUS' }
        }
        return 'REMOVE'
    }

    if ($Command -match '[|<>`]') { return 'AMBIGUOUS' }
    $runLines = 0
    foreach ($line in ($Command -split '[;\r\n]+')) {
        $part = $line.Trim()
        if (-not $part) { continue }
        if ($part -match '(?i)^(?:if\s+\[\[?.*\]\]?\s*(?:;\s*then)?|then|else|fi|do|done|\{|\}|:)\s*$') { continue }
        if ($part -match '^(?i:export\s+)?MXCLI\s*=\s*["'']?(?:\./)?mxcli(?:\.exe)?["'']?$') { continue }
        if ($part -match '^(?i:exec\s+)?["'']?\$\{?MXCLI\}?["'']?\s+run\b.*$' -and $part -notmatch '[|&<>`]') {
            if ($Command -notmatch '(?im)^\s*(?:export\s+)?MXCLI\s*=\s*["'']?(?:\./)?mxcli(?:\.exe)?["'']?\s*;?\s*$') { return 'AMBIGUOUS' }
            $runLines++
            continue
        }
        if ($part -match '^(?i:if\s+\[\s+-[a-z]\s+[^]]+\]\s*(?:;\s*then)?)$') { continue }
        return 'AMBIGUOUS'
    }
    if ($runLines -eq 1) { return 'REMOVE' }
    return 'AMBIGUOUS'
}

function Normalize-HookNode {
    param([object]$Node, [ref]$RemovedCount)

    if ($null -eq $Node) {
        throw 'SessionStart contains a null hook/group entry; settings.json was not changed.'
    }
    if ($Node -is [System.Array]) {
        $kept = [System.Collections.Generic.List[object]]::new()
        foreach ($item in $Node) {
            $normalized = Normalize-HookNode -Node $item -RemovedCount $RemovedCount
            if ($null -ne $normalized) { $kept.Add($normalized) }
        }
        return ,$kept.ToArray()
    }

    if ($Node -is [System.Management.Automation.PSCustomObject]) {
        $typeProperty = Get-Property -Object $Node -Name 'type'
        if ($typeProperty -and $typeProperty.Value -eq 'command') {
            $commandProperty = Get-Property -Object $Node -Name 'command'
            if (-not $commandProperty -or $commandProperty.Value -isnot [string]) {
                throw 'SessionStart contains a command hook without a string command; settings.json was not changed.'
            }
            $disposition = Get-CommandDisposition -Command $commandProperty.Value
            if ($disposition -eq 'AMBIGUOUS') {
                throw 'SessionStart contains a provisioning-like hook with unclear or mixed ownership; settings.json was not changed.'
            }
            if ($disposition -eq 'REMOVE') {
                $RemovedCount.Value++
                return $null
            }
        }

        $nestedHooks = Get-Property -Object $Node -Name 'hooks'
        if ($nestedHooks) {
            if ($nestedHooks.Value -isnot [System.Array] -and
                $nestedHooks.Value -isnot [System.Management.Automation.PSCustomObject]) {
                throw 'SessionStart contains a hook group with an invalid hooks value; settings.json was not changed.'
            }
            $nestedHooks.Value = Normalize-HookNode -Node $nestedHooks.Value -RemovedCount $RemovedCount
        }
        return $Node
    }
    throw 'SessionStart contains an unexpected JSON hook/group value; settings.json was not changed.'
}

if (-not (Test-Path -LiteralPath $SettingsPath -PathType Leaf)) {
    Write-Host '[OK] Claude settings.json not present; no SessionStart hook normalization needed.'
    exit 0
}

$original = [System.IO.File]::ReadAllText($SettingsPath)
try {
    $settings = ConvertFrom-Json -InputObject $original -ErrorAction Stop
} catch {
    throw "Cannot safely normalize invalid JSON at '$SettingsPath': $($_.Exception.Message)"
}
if ($settings -isnot [System.Management.Automation.PSCustomObject]) {
    throw "Cannot safely normalize non-object Claude settings JSON at '$SettingsPath'."
}

$hooksProperty = Get-Property -Object $settings -Name 'hooks'
if ($hooksProperty -and $hooksProperty.Value -isnot [System.Management.Automation.PSCustomObject]) {
    throw "Cannot safely normalize non-object hooks registration at '$SettingsPath'."
}
$sessionStartProperty = if ($hooksProperty) { Get-Property -Object $hooksProperty.Value -Name 'SessionStart' } else { $null }
if (-not $sessionStartProperty) {
    Write-Host '[OK] No Claude SessionStart hook registration found.'
    exit 0
}
if ($sessionStartProperty.Value -isnot [System.Array]) {
    throw "Cannot safely normalize non-array SessionStart registration at '$SettingsPath'."
}

$removedCount = 0
$normalized = Normalize-HookNode -Node $sessionStartProperty.Value -RemovedCount ([ref]$removedCount)
if ($removedCount -eq 0) {
    Write-Host '[OK] SessionStart hook registration is provisioning-free; no change needed.'
    exit 0
}

$sessionStartProperty.Value = $normalized
$json = ConvertTo-Json -InputObject $settings -Depth 100
[System.IO.File]::WriteAllText($SettingsPath, $json + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
Write-Host "[FIX] Removed $removedCount mxcli-owned provisioning/bootstrap SessionStart hook(s); preserved all other JSON fields and hooks."