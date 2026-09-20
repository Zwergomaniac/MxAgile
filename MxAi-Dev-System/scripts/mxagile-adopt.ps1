param(
    [Parameter(Mandatory=$true)]
    [string]$TargetDir
)

# Resolve target directory
$TargetDir = Resolve-Path $TargetDir
$TemplateDir = $PSScriptRoot | Split-Path

# Validate Mendix Project
$mprFiles = Get-ChildItem -Path $TargetDir -Filter *.mpr
if ($mprFiles.Count -eq 0) {
    Write-Host "Error: Target directory does not appear to be a Mendix project (.mpr file missing)." -ForegroundColor Red
    exit 1
}

# Setup Logging
$MxAgileDir = Join-Path $TargetDir ".mxagile"
$logFile = Join-Path $MxAgileDir "adoption.log"
function Write-Log($message) {
    if (-not (Test-Path $MxAgileDir)) {
        New-Item -ItemType Directory -Path $MxAgileDir | Out-Null
    }
    Add-Content -Path $logFile -Value $message
}
Write-Log "--- Adoption started on $(Get-Date) ---"

# Skeleton files
$itemsToCopy = @(".mxagile") 

$copiedItems = @()
$skippedItems = @()

foreach ($item in $itemsToCopy) {
    $sourceItem = Join-Path $TemplateDir $item
    $destItem = Join-Path $TargetDir $item

    $isMxAgile = ($item -eq ".mxagile")
    $exists = Test-Path -Path $destItem
    if ($exists -and -not $isMxAgile) {
        Write-Warning "Skipping $item, already exists in target project."
        Write-Log "Skipped: $item (already exists)"
        $skippedItems += $item
    } elseif ($item -eq ".mxagile") {
        if (Test-Path $destItem) {
            Write-Host "Skipping .mxagile"
        } else {
            New-Item -ItemType Directory -Path $destItem | Out-Null
        }
        $sourceChildren = Get-ChildItem -Path $sourceItem
        foreach ($child in $sourceChildren) {
            $destChild = Join-Path $destItem $child.Name
            if (Test-Path $destChild) {
                Write-Warning "Skipping $($child.Name), already exists."
                Write-Log "Skipped: $($child.Name) (already exists)"
            } else {
                Copy-Item -Path $child.FullName -Destination $destChild -Recurse
                Write-Host "Successfully copied $($child.Name)"
                Write-Log "Copied: $($child.Name)"
            }
        }
        $copiedItems += $item
    } else {
        Copy-Item -Path $sourceItem -Destination $destItem -Recurse
        Write-Host "Successfully copied $item"
        Write-Log "Copied: $item"
        $copiedItems += $item
    }
}

# Print Summary
Write-Host "`n--- Adoption Summary ---"
if ($copiedItems.Count -gt 0) {
    Write-Host "Successfully added:"
    $copiedItems | ForEach-Object { Write-Host " - $_" }
}
if ($skippedItems.Count -gt 0) {
    Write-Host "Skipped (already exist):"
    $skippedItems | ForEach-Object { Write-Host " - $_" }
}
Write-Host "Log file: $logFile"
Write-Host "------------------------"
