param (
    [string]$TargetDir
)

# ============================================================# mxcli Stable Updater / Installer
# - Sucht neuesten stabilen GitHub Release
# - Ignoriert Nightly / Pre-Releases / Drafts
# - Laedt Windows x64 (amd64)
# - Zielordner kann ausgewaehlt werden
# - Vorhandene mxcli.exe wird ersetzt
# ============================================================

$ErrorActionPreference = "Stop"

$Repo = "mendixlabs/mxcli"
$AssetName = "mxcli-windows-amd64.exe"

Write-Host ""
Write-Host "=== mxcli Stable Installer ===" -ForegroundColor Cyan
Write-Host "Repository: $Repo"
Write-Host ""

# ------------------------------------------------------------
# 1. Zielpfad auswaehlen
# ------------------------------------------------------------

if ([string]::IsNullOrEmpty($TargetDir)) {
    Add-Type -AssemblyName System.Windows.Forms
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = "Zielordner fuer mxcli auswaehlen"
    $dialog.ShowNewFolderButton = $true

    if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
        Write-Host "Abgebrochen." -ForegroundColor Yellow
        exit 0
    }
    $TargetDir = $dialog.SelectedPath
}
else {
    Write-Host "Zielverzeichnis via -TargetDir Parameter: $TargetDir" -ForegroundColor Cyan
}

$TargetExe = Join-Path $TargetDir "mxcli.exe"

Write-Host "Ziel: $TargetExe" -ForegroundColor Gray
Write-Host ""

# ------------------------------------------------------------
# 2. GitHub Releases laden
# ------------------------------------------------------------

Write-Host "Suche neuesten stabilen mxcli Release..." -ForegroundColor Cyan

$headers = @{
    "Accept"     = "application/vnd.github+json"
    "User-Agent" = "mxcli-powershell-installer"
}

$releases = Invoke-RestMethod `
    -Uri "https://api.github.com/repos/$Repo/releases" `
    -Headers $headers

# Nur stabile Releases:
# - kein Draft
# - kein Pre-Release
# - kein nightly Tag
$release = $releases |
    Where-Object {
        -not $_.draft -and
        -not $_.prerelease -and
        $_.tag_name -notmatch "(?i)nightly"
    } |
    Select-Object -First 1

if (-not $release) {
    throw "Kein stabiler mxcli Release gefunden."
}

Write-Host "Gefunden: $($release.tag_name)" -ForegroundColor Green
Write-Host "Release:   $($release.name)"
Write-Host ""

# ------------------------------------------------------------
# 3. Windows x64 Asset suchen
# ------------------------------------------------------------

$asset = $release.assets |
    Where-Object { $_.name -eq $AssetName } |
    Select-Object -First 1

if (-not $asset) {
    Write-Host "Verfuegbare Assets:" -ForegroundColor Yellow
    $release.assets | ForEach-Object {
        Write-Host "  - $($_.name)"
    }

    throw "Asset '$AssetName' wurde im Release $($release.tag_name) nicht gefunden."
}

Write-Host "Asset: $($asset.name)"
Write-Host ""

# ------------------------------------------------------------
# 4. Download
# ------------------------------------------------------------

$tempFile = Join-Path $env:TEMP "mxcli-$($release.tag_name)-windows-amd64.exe"

Write-Host "Lade mxcli herunter..." -ForegroundColor Cyan

Invoke-WebRequest `
    -Uri $asset.browser_download_url `
    -OutFile $tempFile `
    -UseBasicParsing

if (-not (Test-Path $tempFile)) {
    throw "Download fehlgeschlagen."
}

# ------------------------------------------------------------
# 5. Bestehende Version anzeigen
# ------------------------------------------------------------

if (Test-Path $TargetExe) {
    Write-Host ""
    Write-Host "Vorhandene Installation gefunden:" -ForegroundColor Yellow

    try {
        $oldVersion = & $TargetExe --version 2>$null
        Write-Host "  $oldVersion"
    }
    catch {
        Write-Host "  Version konnte nicht ermittelt werden."
    }

    Write-Host "Ersetze vorhandene mxcli.exe..."
}

# ------------------------------------------------------------
# 6. Installieren
# ------------------------------------------------------------

Copy-Item `
    -Path $tempFile `
    -Destination $TargetExe `
    -Force

Remove-Item $tempFile -Force -ErrorAction SilentlyContinue

# ------------------------------------------------------------
# 7. Installation pruefen
# ------------------------------------------------------------

Write-Host ""
Write-Host "Installation abgeschlossen." -ForegroundColor Green
Write-Host ""

try {
    $installedVersion = & $TargetExe --version

    Write-Host "Installierte Version:" -ForegroundColor Cyan
    Write-Host "  $installedVersion"
}
catch {
    Write-Warning "mxcli.exe wurde installiert, konnte aber nicht gestartet werden."
}

Write-Host ""
Write-Host "Pfad:"
Write-Host "  $TargetExe" -ForegroundColor Gray
Write-Host ""