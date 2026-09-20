<#
.SYNOPSIS
Fetches and installs an external MxAgile Company Layer.

.DESCRIPTION
Clones a Git repository to a temporary location below the target project,
validates layer.json, determines the resolved Git revision, copies the Layer
payload without Git metadata to .mxagile/layers/<layer-id>, writes provenance,
and cleans up the temporary clone.
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$RepositoryUrl,

    [ValidateNotNullOrEmpty()]
    [string]$Ref = "main",

    [string]$ProjectRoot = (Get-Location).Path
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

if (-not (Test-Path -LiteralPath $ProjectRoot -PathType Container)) {
    throw "Project root does not exist: $ProjectRoot"
}

$ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)

$LayersDir = Join-Path $ProjectRoot ".mxagile\layers"
$StateDir  = Join-Path $ProjectRoot ".mxagile\state"
$TempDir   = Join-Path $ProjectRoot ".mxagile\tmp_layer"

function Remove-TempLayerDirectory {
    if (Test-Path -LiteralPath $TempDir) {
        Remove-Item `
            -LiteralPath $TempDir `
            -Recurse `
            -Force
    }
}

Write-Host ""
Write-Host "Fetching Company Layer"
Write-Host "Repository : $RepositoryUrl"
Write-Host "Ref        : $Ref"
Write-Host "Project    : $ProjectRoot"
Write-Host ""

try {
    # -----------------------------------------------------------------
    # Prepare
    # -----------------------------------------------------------------

    New-Item `
        -ItemType Directory `
        -Path $LayersDir `
        -Force |
        Out-Null

    New-Item `
        -ItemType Directory `
        -Path $StateDir `
        -Force |
        Out-Null

    Remove-TempLayerDirectory

    # -----------------------------------------------------------------
    # Git availability
    # -----------------------------------------------------------------

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw "Git is not available in PATH."
    }

    # -----------------------------------------------------------------
    # Clone
    # -----------------------------------------------------------------

    Write-Host "Cloning Company Layer..."

    & git clone `
        --depth 1 `
        --branch $Ref `
        -- `
        $RepositoryUrl `
        $TempDir

    if ($LASTEXITCODE -ne 0) {
        throw "git clone failed with exit code $LASTEXITCODE."
    }

    # -----------------------------------------------------------------
    # Validate manifest
    # -----------------------------------------------------------------

    $LayerManifestPath = Join-Path $TempDir "layer.json"

    if (-not (Test-Path -LiteralPath $LayerManifestPath -PathType Leaf)) {
        throw "Company Layer repository does not contain layer.json."
    }

    try {
        $LayerManifest =
            Get-Content `
                -LiteralPath $LayerManifestPath `
                -Raw |
            ConvertFrom-Json
    }
    catch {
        throw "Unable to parse layer.json: $($_.Exception.Message)"
    }

    $LayerId   = [string]$LayerManifest.id
    $LayerName = [string]$LayerManifest.name

    if ([string]:: {
        throw "layer.json does not define a valid 'id'."
    }

    if ([string]:: {
        throw "layer.json does not define a valid 'name'."
    }

    # -----------------------------------------------------------------
    # Resolve commit
    # -----------------------------------------------------------------

    Push-Location $TempDir

    try {
        $ResolvedRevision = (& git rev-parse HEAD).Trim()

        if ($LASTEXITCODE -ne 0 -or
            [string]:: {

            throw "Unable to determine resolved Git revision."
        }
    }
    finally {
        Pop-Location
    }

    # -----------------------------------------------------------------
    # Destination
    # -----------------------------------------------------------------

    $DestinationDir = Join-Path $LayersDir $LayerId

    if (Test-Path -LiteralPath $DestinationDir) {
        Write-Host "Replacing installed Layer '$LayerId'..."

        Remove-Item `
            -LiteralPath $DestinationDir `
            -Recurse `
            -Force
    }

    New-Item `
        -ItemType Directory `
        -Path $DestinationDir `
        -Force |
        Out-Null

    # -----------------------------------------------------------------
    # Copy payload without .git
    # -----------------------------------------------------------------

    Get-ChildItem `
        -LiteralPath $TempDir `
        -Force |
        Where-Object { $_.Name -ne ".git" } |
        Copy-Item `
            -Destination $DestinationDir `
            -Recurse `
            -Force

    # -----------------------------------------------------------------
    # Provenance
    # -----------------------------------------------------------------

    $Provenance = [ordered]@{
        layer_id          = $LayerId
        layer_name        = $LayerName
        source            = $RepositoryUrl
        requested_ref     = $Ref
        resolved_revision = $ResolvedRevision
    }

    $ProvenancePath = Join-Path $DestinationDir "provenance.json"

    $Provenance |
        ConvertTo-Json |
        Set-Content `
            -LiteralPath $ProvenancePath `
            -Encoding utf8

    # -----------------------------------------------------------------
    # Agent-readable state manifest
    # -----------------------------------------------------------------

    $ManifestPath = Join-Path $StateDir "manifest.$LayerId.md"

    $Manifest = @"
# Layer: $LayerName ($LayerId)

Source: $RepositoryUrl

Requested ref: $Ref

Resolved revision: $ResolvedRevision
"@

    Set-Content `
        -LiteralPath $ManifestPath `
        -Value $Manifest `
        -Encoding utf8

    # -----------------------------------------------------------------
    # Validate installed state
    # -----------------------------------------------------------------

    if (Test-Path -LiteralPath (Join-Path $DestinationDir ".git")) {
        throw "Installed Layer unexpectedly contains nested .git metadata."
    }

    Write-Host ""
    Write-Host "Layer '$LayerName' installed successfully." -ForegroundColor Green
    Write-Host "Location:"
    Write-Host "  $DestinationDir"
    Write-Host "Revision:"
    Write-Host "  $ResolvedRevision"
}
catch {
    throw "Company Layer installation failed: $($_.Exception.Message)"
}
finally {
    Remove-TempLayerDirectory
}