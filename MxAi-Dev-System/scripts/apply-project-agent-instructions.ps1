<#
.SYNOPSIS
Applies project-specific agent instructions to platform entry points.

.DESCRIPTION
Uses AGENT.md from the target project as the project instruction source.

Existing mxcli-generated AGENTS.md and CLAUDE.md content is preserved outside
the managed MxAgile block.

GitHub Copilot instructions are written below the supplied ProjectRoot.
#>

[CmdletBinding()]
param (
    [string]$ProjectRoot = (Get-Location).Path
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

if (-not (Test-Path -LiteralPath $ProjectRoot -PathType Container)) {
    throw "Project root does not exist: $ProjectRoot"
}

$ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)

$SourcePath = Join-Path $ProjectRoot "AGENT.md"
$AgentsPath = Join-Path $ProjectRoot "AGENTS.md"
$ClaudePath = Join-Path $ProjectRoot "CLAUDE.md"

$GitHubDirectory = Join-Path $ProjectRoot ".github"
$CopilotPath = Join-Path $GitHubDirectory "copilot-instructions.md"

$GitIgnorePath = Join-Path $ProjectRoot ".gitignore"

$StartMarker = "<!-- BEGIN PROJECT AGENT INSTRUCTIONS -->"
$EndMarker   = "<!-- END PROJECT AGENT INSTRUCTIONS -->"

# ---------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------

function Remove-ManagedBlock {
    param(
        [AllowEmptyString()]
        [string]$Content
    )

    if ([string]:: {
        return ""
    }

    $pattern =
        '(?s)<!-- BEGIN PROJECT AGENT INSTRUCTIONS -->.*?<!-- END PROJECT AGENT INSTRUCTIONS -->\s*'

    return [regex]::Replace($Content, $pattern, "")
}

function Ensure-Directory {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        New-Item `
            -ItemType Directory `
            -Path $Path `
            -Force |
            Out-Null
    }
}

function Add-GitIgnoreEntry {
    param(
        [Parameter(Mandatory)]
        [string]$Entry
    )

    $content = if (Test-Path -LiteralPath $GitIgnorePath -PathType Leaf) {
        Get-Content -LiteralPath $GitIgnorePath -Raw
    }
    else {
        ""
    }

    $existing = @(
        $content -split "`r?`n" |
        ForEach-Object { $_.Trim() }
    )

    if ($existing -notcontains $Entry) {
        $prefix =
            if ($content -and -not $content.EndsWith("`n")) {
                "`n"
            }
            else {
                ""
            }

        [System.IO.File]::AppendAllText(
            $GitIgnorePath,
            "$prefix$Entry`n",
            [System.Text.UTF8Encoding]::new($false)
        )
    }
}

# ---------------------------------------------------------------------
# Validate required project files
# ---------------------------------------------------------------------

foreach ($requiredPath in @($SourcePath, $AgentsPath, $ClaudePath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw @"
Required project file does not exist:

  $requiredPath

Ensure mxcli init and the MxAgile project skeleton have been initialized first.
"@
    }
}

# ---------------------------------------------------------------------
# Ensure output directories
# ---------------------------------------------------------------------

Ensure-Directory -Path $GitHubDirectory

# ---------------------------------------------------------------------
# Read project instructions and existing projections
# ---------------------------------------------------------------------

$ProjectInstructions = Get-Content `
    -LiteralPath $SourcePath `
    -Raw

$AgentsReference = Remove-ManagedBlock (
    Get-Content -LiteralPath $AgentsPath -Raw
)

$ClaudeReference = Remove-ManagedBlock (
    Get-Content -LiteralPath $ClaudePath -Raw
)

$CopilotReference =
    if (Test-Path -LiteralPath $CopilotPath -PathType Leaf) {
        Remove-ManagedBlock (
            Get-Content -LiteralPath $CopilotPath -Raw
        )
    }
    else {
        ""
    }

$AgentsBlock = @"
$StartMarker
$ProjectInstructions
$EndMarker

"@

$ClaudeBlock = @"
$StartMarker
@AGENT.md
$EndMarker

"@

$Utf8WithoutBom = [System.Text.UTF8Encoding]::new($false)

# ---------------------------------------------------------------------
# Write projections
# ---------------------------------------------------------------------

[System.IO.File]::WriteAllText(
    $AgentsPath,
    ($AgentsBlock + $AgentsReference),
    $Utf8WithoutBom
)

[System.IO.File]::WriteAllText(
    $ClaudePath,
    ($ClaudeBlock + $ClaudeReference),
    $Utf8WithoutBom
)

[System.IO.File]::WriteAllText(
    $CopilotPath,
    ($AgentsBlock + $CopilotReference),
    $Utf8WithoutBom
)

# ---------------------------------------------------------------------
# Local-state ignore rules
# ---------------------------------------------------------------------

Add-GitIgnoreEntry -Entry "/.env.mendix"
Add-GitIgnoreEntry -Entry "/.mxcli/catalog.db"
Add-GitIgnoreEntry -Entry "/sprints/generated/"
Add-GitIgnoreEntry -Entry "/planning/generated/"

Write-Host "Applied project instructions:"
Write-Host "  $AgentsPath"
Write-Host "  $ClaudePath"
Write-Host "  $CopilotPath"