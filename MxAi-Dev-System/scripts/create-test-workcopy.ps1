[CmdletBinding(SupportsShouldProcess = $true)]
param (
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string]$TemplateName,

    [Parameter(Position = 1)]
    [string]$TestDirName,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

# Default TestDirName to TemplateName if not provided
if ([string]::IsNullOrEmpty($TestDirName)) {
    $TestDirName = $TemplateName
}

# Dynamically determine the workspace root
$WorkspaceRoot = Split-Path -Parent $PSScriptRoot

$SourcePath = Join-Path -Path $WorkspaceRoot -ChildPath "project-templates\$TemplateName"
$DestPath = Join-Path -Path $WorkspaceRoot -ChildPath ".testing-$TestDirName"

# Validate Source
if (-not (Test-Path -LiteralPath $SourcePath -PathType Container)) {
    Write-Error "Source template not found: $SourcePath"
    exit 1
}

# Handle destination existence
if (Test-Path -LiteralPath $DestPath) {
    if ($Force) {
        # Additional safety checks
        $resolvedDest = (Resolve-Path -LiteralPath $DestPath).Path
        $resolvedRoot = (Resolve-Path -LiteralPath $WorkspaceRoot).Path
        if (-not $resolvedDest.StartsWith($resolvedRoot)) {
            Write-Error "CRITICAL: Destination '$DestPath' is outside the workspace root. Aborting for safety."
            exit 1
        }
        if (-not (Split-Path -Leaf $resolvedDest).StartsWith(".testing-")) {
             Write-Error "CRITICAL: Destination leaf name does not start with '.testing-'. Aborting for safety."
             exit 1
        }

        if ($PSCmdlet.ShouldProcess($DestPath, "Remove existing directory")) {
            Remove-Item -LiteralPath $DestPath -Recurse -Force
        }
    } else {
        Write-Error "Destination directory '$DestPath' already exists. Use -Force to overwrite."
        exit 1
    }
}

# Create the new workcopy
if ($PSCmdlet.ShouldProcess($DestPath, "Create test workcopy from template '$TemplateName'")) {
    Copy-Item -LiteralPath $SourcePath -Destination $DestPath -Recurse
    Write-Host "Successfully created test workcopy from '$TemplateName' to '$DestPath'"
}
