[CmdletBinding()]
param(
    [string]$ProjectRoot = (Get-Location).Path,
    [string]$ConfiguredPath,
    [switch]$AllowPathFallback
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
$binaryName = if ($isWindows) { 'mxcli.exe' } else { 'mxcli' }

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

[pscustomobject]@{
    path   = $selectedPath
    source = $source
} | ConvertTo-Json -Compress