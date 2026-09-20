$sourceDir = "planning/stories"
$targetDir = "requirements"

if (-not (Test-Path -LiteralPath $sourceDir)) {
    Write-Host "Source directory $sourceDir does not exist. Exiting."
    exit
}

$files = Get-ChildItem -Path "$sourceDir/*.md"
foreach ($file in $files) {
    try {
        Move-Item -LiteralPath $file.FullName -Destination $targetDir -ErrorAction Stop
        Write-Host "Moved $($file.Name) to $targetDir"
    }
    catch {
        Write-Error "Failed to move $($file.Name): $_"
    }
}
