[CmdletBinding()]
param(
    [string]$ProjectRoot = (Get-Location).Path,
    [string]$ConfiguredPath,
    [switch]$AllowPathFallback,
    [switch]$ResolveRecipe,
    [string]$ProjectMpr,
    [string]$OperatingModeResolutionJson,
    [ValidateSet('verification', 'implementation', 'development')]
    [string]$Purpose = 'verification',
    [string]$RequestedBackend,
    [string]$DbNameOverride,
    [switch]$Detach,
    [string]$RuntimeOverridesJson = '{}',
    [string]$RequiredChecksJson = '{}'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
if (-not (Test-Path -LiteralPath $ProjectRoot -PathType Container)) {
    throw "Project root does not exist: $ProjectRoot"
}

$platformIsWindows = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
    [System.Runtime.InteropServices.OSPlatform]::Windows
)
$binaryName = if ($platformIsWindows) { 'mxcli.exe' } else { 'mxcli' }

function Resolve-ProjectPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $resolvedPath = if ([System.IO.Path]::IsPathRooted($Path)) {
        [System.IO.Path]::GetFullPath($Path)
    } else {
        [System.IO.Path]::GetFullPath((Join-Path $ProjectRoot $Path))
    }

    if (-not (Test-Path -LiteralPath $resolvedPath -PathType Leaf) -and
        $platformIsWindows -and [string]::IsNullOrEmpty([System.IO.Path]::GetExtension($resolvedPath))) {
        $withExtension = "$resolvedPath.exe"
        if (Test-Path -LiteralPath $withExtension -PathType Leaf) {
            $resolvedPath = $withExtension
        }
    }

    return $resolvedPath
}

$selectedPath = $null
$source = $null

if (-not [string]::IsNullOrWhiteSpace($ConfiguredPath)) {
    $selectedPath = Resolve-ProjectPath -Path $ConfiguredPath
    if (-not (Test-Path -LiteralPath $selectedPath -PathType Leaf)) {
        throw "Configured mxcli binary was not found: $selectedPath. PATH fallback is not permitted for a missing declared binary."
    }
    $source = 'PROJECT_DECLARED'
} else {
    $projectBinary = Join-Path $ProjectRoot $binaryName
    if (Test-Path -LiteralPath $projectBinary -PathType Leaf) {
        $selectedPath = [System.IO.Path]::GetFullPath($projectBinary)
        $source = 'PROJECT_LOCAL'
    } elseif ($AllowPathFallback) {
        $pathCommand = Get-Command -Name $binaryName -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($null -eq $pathCommand -or [string]::IsNullOrWhiteSpace($pathCommand.Source)) {
            throw "PATH fallback was explicitly allowed, but $binaryName was not found on PATH."
        }
        $selectedPath = [System.IO.Path]::GetFullPath($pathCommand.Source)
        $source = 'PATH_EXPLICIT_FALLBACK'
    } else {
        throw "Project-local mxcli was not found at $projectBinary. Use the canonical installer or an explicitly declared PATH fallback; do not guess another binary."
    }
}

if (-not $ResolveRecipe) {
    [pscustomobject]@{
        path   = $selectedPath
        source = $source
    } | ConvertTo-Json -Compress
    return
}

function Write-BlockedRecipe {
    param([string]$Code, [string]$Reason, [string]$State = 'BLOCKED')
    [ordered]@{
        schema_version = 1
        status = $State
        blockers = @(@{ code = $Code; reason = $Reason })
        recipe = $null
    } | ConvertTo-Json -Compress -Depth 10
}

if ([string]::IsNullOrWhiteSpace($OperatingModeResolutionJson)) {
    Write-BlockedRecipe 'OPERATING_MODE_UNOBSERVED' 'Pass the current structured C2 operating-mode result; this resolver does not detect Studio Pro.' 'AMBIGUOUS'
    return
}

try {
    $operatingModeResolution = $OperatingModeResolutionJson | ConvertFrom-Json -ErrorAction Stop
    $runtimeOverrides = $RuntimeOverridesJson | ConvertFrom-Json -ErrorAction Stop
    $requiredChecks = $RequiredChecksJson | ConvertFrom-Json -ErrorAction Stop
} catch {
    Write-BlockedRecipe 'RESOLVER_INPUT_INVALID' 'C2 or runtime override input is not valid JSON.'
    return
}

if ([string]::IsNullOrWhiteSpace($ProjectMpr)) {
    try {
        $mprFiles = @(Get-ChildItem -LiteralPath $ProjectRoot -File -Filter '*.mpr' -ErrorAction Stop)
    } catch {
        Write-BlockedRecipe 'PROJECT_MPR_ENUMERATION_FAILED' 'Could not enumerate the project-root .mpr files.' 'AMBIGUOUS'
        return
    }
    if ($mprFiles.Count -eq 1) {
        $ProjectMpr = $mprFiles[0].FullName
    }
}

$versionOutput = ''
$helpOutput = ''
try {
    $versionOutput = (& $selectedPath --version 2>&1 | Out-String).Trim()
    $versionExitCode = $LASTEXITCODE
    $helpOutput = (& $selectedPath help run 2>&1 | Out-String).Trim()
    $helpExitCode = $LASTEXITCODE
    if ($versionExitCode -ne 0) { $versionOutput = '' }
    if ($helpExitCode -ne 0) { $helpOutput = '' }
} catch {
    Write-BlockedRecipe 'MXCLI_CAPABILITY_PROBE_FAILED' 'The selected binary could not complete its read-only version/help probes.'
    return
}

$python = Get-Command -Name python -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
$recipeComposer = Join-Path $PSScriptRoot 'mxcli_runtime_recipe.py'
if ($null -eq $python -or -not (Test-Path -LiteralPath $recipeComposer -PathType Leaf)) {
    Write-BlockedRecipe 'RECIPE_COMPOSER_UNAVAILABLE' 'Python or the distributed recipe composer is unavailable.'
    return
}

$requestPath = Join-Path ([System.IO.Path]::GetTempPath()) ("mxagile-runtime-recipe-" + [guid]::NewGuid().ToString('N') + '.json')
try {
    $request = [ordered]@{
        project_root = $ProjectRoot
        project_mpr = $ProjectMpr
        binary = @{ path = $selectedPath; source = $source }
        version_output = $versionOutput
        help_command = @('help', 'run')
        help_output = $helpOutput
        operating_mode_resolution = $operatingModeResolution
        purpose = $Purpose
        requested_backend = $RequestedBackend
        db_name_override = $DbNameOverride
        detach = $Detach.IsPresent
        runtime_overrides = $runtimeOverrides
        required_checks = if ($requiredChecks -and $requiredChecks.PSObject.Properties.Count -gt 0) {
            $requiredChecks
        } else {
            @{ readiness = @('APPLICATION_REACHABLE') }
        }
    }
    $request | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $requestPath -Encoding UTF8
    $result = & $python.Source $recipeComposer --request-file $requestPath 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-BlockedRecipe 'RECIPE_COMPOSER_FAILED' 'The recipe composer rejected its request.'
        return
    }
    ($result | Out-String).Trim()
} catch {
    Write-BlockedRecipe 'RECIPE_COMPOSER_FAILED' 'The recipe could not be composed from current binary evidence.'
} finally {
    Remove-Item -LiteralPath $requestPath -Force -ErrorAction SilentlyContinue
}