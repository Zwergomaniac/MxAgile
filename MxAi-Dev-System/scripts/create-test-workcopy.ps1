param (
    [Parameter(Mandatory=$true)]
    [string]$TemplateName,
    [Parameter(Mandatory=$true)]
    [string]$TestDirName
)

$ErrorActionPreference = "Stop"

# Use the environment variable for workspace root if available, or hardcoded based on prompt
$WorkspaceRoot = "D:\Mendix\Mx AI Template for new projects\MxAi-Dev-System"

$SourcePath = Join-Path $WorkspaceRoot "project-templates\$TemplateName"
$DestPath = Join-Path $WorkspaceRoot ".testing-$TestDirName"

# Validate Source
if (-not (Test-Path -LiteralPath $SourcePath -PathType Container)) {
    Write-Error "Source template not found: $SourcePath"
    exit 1
}

# Validate Dest parent
$DestParent = Split-Path -LiteralPath $DestPath -Parent
if (-not (Test-Path -LiteralPath $DestParent -PathType Container)) {
    Write-Error "Destination parent directory does not exist: $DestParent"
    exit 1
}

# Validate Dest does not exist
if (Test-Path -LiteralPath $DestPath) {
    Write-Error "Destination directory already exists: $DestPath"
    exit 1
}

# Copy
try {
    Copy-Item -LiteralPath $SourcePath -Destination $DestPath -Recurse
    Write-Host "Successfully created test workcopy from '$TemplateName' to '$DestPath'"
} catch {
    Write-Error "Failed to copy: $_"
    exit 1
}
