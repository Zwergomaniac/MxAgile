[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string]$ProjectRoot,

    [string]$CompanyLayerSource,

    [ValidateSet("Auto", "Git", "Local")]
    [string]$CompanyLayerSourceType = "Auto",

    [string]$CompanyLayerRef = "main"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

try {
    # =========================================================================
    # 1. Core Installation
    # =========================================================================

    Write-Host "---"
    Write-Host "Step 1: Core Installation" -ForegroundColor Cyan
    Write-Host "---"

    $ProjectRoot = Resolve-Path -LiteralPath $ProjectRoot
    if (-not (Test-Path -LiteralPath $ProjectRoot -PathType Container)) {
        throw "ProjectRoot directory not found: $ProjectRoot"
    }

    Write-Host "Project root: $ProjectRoot"

    # Preflight: Check for exactly one .mpr file
    $mprFiles = @(Get-ChildItem -Path $ProjectRoot -Filter "*.mpr" -File)
    if ($mprFiles.Count -ne 1) {
        throw "Expected exactly one .mpr file in the project root, but found $($mprFiles.Count). Please specify a valid Mendix project directory."
    }
    Write-Host "✔️ Project preflight check passed (found $($mprFiles.Name))"

    # Step 1a: MxAgile directory scaffold — also installs mxcli.exe
    $initScript = Join-Path $PSScriptRoot "mxagile-init.ps1"
    if (-not (Test-Path -LiteralPath $initScript)) {
        throw "mxagile-init.ps1 not found in script directory."
    }
    Write-Host "Calling mxagile-init.ps1..."
    & $initScript -ProjectRoot $ProjectRoot
    Write-Host "✔️ mxagile-init.ps1 executed."

    # Step 1b: mxcli init --all-tools
    # Must run AFTER mxcli.exe is installed (by mxagile-init.ps1 above) and
    # BEFORE MxAgile managed-block injection, because mxcli init overwrites CLAUDE.md and AGENTS.md.
    $mxcliExe = Join-Path $ProjectRoot "mxcli.exe"
    if (-not (Test-Path -LiteralPath $mxcliExe -PathType Leaf)) {
        throw "mxcli.exe not found after mxagile-init.ps1 — mxcli installation may have failed."
    }
    Write-Host "Running mxcli init --all-tools..."
    & $mxcliExe init --all-tools $ProjectRoot
    if ($LASTEXITCODE -ne 0) { throw "mxcli init --all-tools failed with exit code $LASTEXITCODE." }
    Write-Host "✔️ mxcli init --all-tools completed."

    # Step 1c: Copy canonical .mxagile/ payload (skills, agents, policies, lifecycle.yaml, etc.)
    # The canonical source is at $PSScriptRoot/../.mxagile/ (the framework dev tree).
    $canonicalSource = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".." ".mxagile"))
    if (-not (Test-Path -LiteralPath $canonicalSource -PathType Container)) {
        throw "Canonical .mxagile/ source not found at: $canonicalSource"
    }
    Write-Host "Installing canonical MxAgile payload from: $canonicalSource"
    $destMxAgile = Join-Path $ProjectRoot ".mxagile"
    # Exclude 'layers' — dev-tree or project-specific Company Layer content; installed separately.
    # Exclude 'state'  — PROJECT/RUNTIME state; must never be distributed from the framework dev
    #                    repository. The empty state/ scaffold is created by mxagile-init.ps1.
    #                    Company Layer manifests exist only when that layer is actually installed.
    Get-ChildItem -LiteralPath $canonicalSource -Exclude "layers", "state" | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $destMxAgile -Recurse -Force
    }
    # Ensure state/ exists as an empty project-owned directory (mxagile-init.ps1 creates it
    # before this step, but guard here so the contract holds even if init order changes).
    $destState = Join-Path $destMxAgile "state"
    if (-not (Test-Path -LiteralPath $destState -PathType Container)) {
        New-Item -ItemType Directory -Path $destState -Force | Out-Null
    }
    Write-Host "✔️ Canonical MxAgile payload installed."


    # Distribute update-mxcli.ps1
    $sourceMxCliScript = Join-Path $PSScriptRoot "install-mxcli.ps1"
    $destMxCliScript = Join-Path $ProjectRoot "update-mxcli.ps1"

    if (Test-Path -LiteralPath $sourceMxCliScript) {
        Copy-Item -LiteralPath $sourceMxCliScript -Destination $destMxCliScript -Force
        Write-Host "✔️ Distributed update-mxcli.ps1 to project."
    } else {
        Write-Warning "install-mxcli.ps1 not found, cannot distribute updater script."
    }


    # Call setup-agent-system.ps1
    $setupScript = Join-Path $PSScriptRoot "setup-agent-system.ps1"
    if (-not (Test-Path -LiteralPath $setupScript)) {
        throw "setup-agent-system.ps1 not found in script directory."
    }
    Write-Host "Calling setup-agent-system.ps1..."
    & $setupScript -ProjectRoot $ProjectRoot
    Write-Host "✔️ setup-agent-system.ps1 executed."


    # =========================================================================
    # 2. Company Layer Installation (Optional)
    # =========================================================================
    if ($CompanyLayerSource) {
        Write-Host "---"
        Write-Host "Step 2: Company Layer Installation" -ForegroundColor Cyan
        Write-Host "---"

        $layerId = $null
        $layerName = $null
        $destinationDir = $null

        # Auto-detect source type
        $resolvedSourceType = $CompanyLayerSourceType
        if ($resolvedSourceType -eq "Auto") {
            if (Test-Path -LiteralPath $CompanyLayerSource -PathType Container) {
                $resolvedSourceType = "Local"
            } else {
                $resolvedSourceType = "Git"
            }
            Write-Host "Auto-detected source type: $resolvedSourceType"
        }

        if ($resolvedSourceType -eq "Git") {
            # --- GIT SOURCE ---
            $fetchScript = Join-Path $PSScriptRoot "fetch-layer.ps1"
            if (-not (Test-Path -LiteralPath $fetchScript)) {
                throw "fetch-layer.ps1 not found in script directory."
            }
            Write-Host "Calling fetch-layer.ps1..."
            & $fetchScript -RepositoryUrl $CompanyLayerSource -Ref $CompanyLayerRef -ProjectRoot $ProjectRoot
            Write-Host "✔️ fetch-layer.ps1 executed."

            # For validation, we need to read the layer.json from the temp dir, which fetch-layer doesn't expose
            # We will rely on the output of fetch-layer.ps1 for success and find the layer afterwards for validation
            $layersDir = Join-Path $ProjectRoot ".mxagile\layers"
            # This is a bit brittle, we assume fetch-layer succeeded and there's only one layer.
            $installedLayer = Get-ChildItem -Path $layersDir | Select-Object -First 1
            if($installedLayer) {
                $layerId = $installedLayer.Name
                $destinationDir = $installedLayer.FullName
            }

        } elseif ($resolvedSourceType -eq "Local") {
            # --- LOCAL SOURCE ---
            Write-Host "Installing from local source: $CompanyLayerSource"
            $sourcePath = Resolve-Path -LiteralPath $CompanyLayerSource

            # 1. Validation
            if (-not (Test-Path -LiteralPath $sourcePath -PathType Container)) {
                throw "Local source directory not found: $sourcePath"
            }

            # 2. Safety
            $layersBaseDir = Resolve-Path -LiteralPath (Join-Path $ProjectRoot ".mxagile\layers")
            if ($sourcePath.ToString() -eq $layersBaseDir.ToString() -or $sourcePath.ToString().StartsWith($($layersBaseDir.ToString() + "\\"))) {
                throw "Safety error: The source directory cannot be the same as or inside the destination layers directory."
            }

            # 3. Manifest
            $manifestPath = Join-Path $sourcePath "layer.json"
            if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
                throw "layer.json not found in the source directory."
            }
            $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
            $layerId = $manifest.id
            $layerName = $manifest.name
            if ([string]::IsNullOrWhiteSpace($layerId)) {
                throw "layer.json is missing a valid 'id'."
            }
            Write-Host "Found Layer '$layerName' with ID '$layerId'."

            # 4. Destination
            $destinationDir = Join-Path $ProjectRoot ".mxagile\layers\$layerId"

            # 5. Copy
            if (Test-Path -LiteralPath $destinationDir) {
                Write-Host "Removing existing layer directory..."
                Remove-Item -LiteralPath $destinationDir -Recurse -Force
            }
            Write-Host "Copying layer contents to $destinationDir..."
            New-Item -Path $destinationDir -ItemType Directory -Force | Out-Null
            Copy-Item -Path "$sourcePath\\*" -Destination $destinationDir -Recurse -Force -Exclude ".git"

            # 6. Provenance
            $provenancePath = Join-Path $destinationDir "provenance.json"
            $provenance = @{
                source_type = "Local"
                source = $sourcePath
            }
            $provenance | ConvertTo-Json | Set-Content -LiteralPath $provenancePath -Encoding UTF8
            Write-Host "✔️ Provenance file created."

            # 7. Validation
            if (Test-Path -LiteralPath (Join-Path $destinationDir ".git")) {
                throw "Validation failed: .git directory was found in the installed layer."
            }
            Write-Host "✔️ Installation integrity verified (no .git directory)."
        }

        # --- Final Validation ---
        if (-not $destinationDir) {
             throw "Could not determine layer destination directory for validation."
        }
        $provenanceFile = Join-Path $destinationDir "provenance.json"
        if (-not (Test-Path -LiteralPath $destinationDir -PathType Container)) {
            throw "Final validation failed: Layer directory '$destinationDir' does not exist."
        }
        if (-not (Test-Path -LiteralPath $provenanceFile -PathType Leaf)) {
            throw "Final validation failed: Provenance file '$provenanceFile' does not exist."
        }
        Write-Host "✔️ Final validation passed for layer '$layerId'."
    }

    Write-Host ""
    Write-Host "✅ Core installation complete." -ForegroundColor Green

    Write-Host ""
    Write-Host "────────────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host "MxAgile Recommended Validation:" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Start a NEW agent session in this project and enter:" -ForegroundColor White
    Write-Host ""
    Write-Host "  Run the MxAgile system check and output the complete diagnostic report." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  (New session required: the check must verify discovery from the" -ForegroundColor DarkGray
    Write-Host "   installed repository, not from this installation session.)" -ForegroundColor DarkGray
    Write-Host "────────────────────────────────────────────────────────" -ForegroundColor DarkGray

    exit 0

} catch {
    Write-Host ""
    Write-Host "❌ Installation failed!" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
