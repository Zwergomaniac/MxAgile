<#
.SYNOPSIS
Applies project-specific instructions after mxcli init.

.DESCRIPTION
Preserves the mxcli-generated reference in AGENTS.md and CLAUDE.md while adding
a managed project-instruction block from AGENT.md. It also generates the native
GitHub Copilot instruction file from AGENT.md.
#>

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $projectRoot 'AGENT.md'
$agentsPath = Join-Path $projectRoot 'AGENTS.md'
$claudePath = Join-Path $projectRoot 'CLAUDE.md'
$copilotPath = Join-Path $projectRoot '.github\copilot-instructions.md'
$gitIgnorePath = Join-Path $projectRoot '.gitignore'
$startMarker = '<!-- BEGIN PROJECT AGENT INSTRUCTIONS -->'
$endMarker = '<!-- END PROJECT AGENT INSTRUCTIONS -->'

foreach ($requiredPath in @($sourcePath, $agentsPath, $claudePath)) {
    if (-not (Test-Path -Path $requiredPath -PathType Leaf)) {
        throw "Required file '$requiredPath' does not exist. Run 'mxcli init' before this script."
    }
}

function Remove-ManagedBlock {
    param([string]$Content)

    $pattern = '(?s)<!-- BEGIN PROJECT AGENT INSTRUCTIONS -->.*?<!-- END PROJECT AGENT INSTRUCTIONS -->\s*'
    return [regex]::Replace($Content, $pattern, '')
}

function Add-GitIgnoreEntry {
    param([string]$Entry)

    $content = if (Test-Path -Path $gitIgnorePath -PathType Leaf) {
        Get-Content -Path $gitIgnorePath -Raw
    } else {
        ''
    }

    # Split instead of a regex anchor: "$" does not match before CRLF, so an anchored
    # test re-appends an already present entry on every run.
    $existing = $content -split "`r?`n" | ForEach-Object { $_.Trim() }
    if ($existing -notcontains $Entry) {
        $prefix = if ($content -and -not $content.EndsWith("`n")) { "`n" } else { '' }
        [System.IO.File]::AppendAllText($gitIgnorePath, "$prefix$Entry`n", [System.Text.UTF8Encoding]::new($false))
    }
}

$projectInstructions = Get-Content -Path $sourcePath -Raw
$agentsReference = Remove-ManagedBlock (Get-Content -Path $agentsPath -Raw)
$claudeReference = Remove-ManagedBlock (Get-Content -Path $claudePath -Raw)
$copilotReference = if (Test-Path -Path $copilotPath -PathType Leaf) {
    Remove-ManagedBlock (Get-Content -Path $copilotPath -Raw)
} else {
    ''
}

$agentsBlock = @"
$startMarker
$projectInstructions
$endMarker

"@

$claudeBlock = @"
$startMarker
@AGENT.md
$endMarker

"@

$utf8WithoutBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($agentsPath, ($agentsBlock + $agentsReference), $utf8WithoutBom)
[System.IO.File]::WriteAllText($claudePath, ($claudeBlock + $claudeReference), $utf8WithoutBom)
# Copilot resolves no @-includes, so AGENT.md is inlined here as well.
[System.IO.File]::WriteAllText($copilotPath, ($agentsBlock + $copilotReference), $utf8WithoutBom)
Add-GitIgnoreEntry -Entry '/.env.mendix'
Add-GitIgnoreEntry -Entry '/.mxcli/catalog.db'
Add-GitIgnoreEntry -Entry '/sprints/generated/'
Add-GitIgnoreEntry -Entry '/planning/generated/'

Write-Host 'Applied project instructions while preserving mxcli references.'