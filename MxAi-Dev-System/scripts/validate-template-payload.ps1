<#
.SYNOPSIS
    Validates the distributable payload of the Mendix AI project template.

.DESCRIPTION
    Framework-root maintenance tool. Not part of the payload itself — the
    workspace rule in .github/copilot-instructions.md forbids putting
    maintainer-only tools into the payload.

    Runs a series of checks against the payload directory and prints OK or
    FEHLER per check, with the offending path where applicable. Exits with
    code 1 if any check fails, 0 otherwise.

    Checks:
      1. Frontmatter contract via a consumer dry run: copies the payload
         (without .env.mendix) into a disposable temp directory, runs
         scripts/generate-dfc-platform-skills.ps1 there, and verifies that
         every generated SKILL.md and every Claude agent .md file starts
         with '---' on line 1. This is the exact test that would have
         caught the "header before frontmatter" defect, because the payload
         itself never ships the generated artifacts.
      2. No .env.mendix in the payload (only .env.mendix.example is allowed).
      3. Payload .gitignore has no merged/concatenated lines, no duplicate
         entries, and ends with a trailing newline.
      4. No absolute machine paths in the payload (C:\Users\, D:\Mendix\,
         /home/, and similar patterns).
      5. No leftover concrete project/story-ID prefixes where a
         {STORYPREFIX} placeholder is expected.

.PARAMETER PayloadPath
    Path to the payload directory to validate. Defaults to
    "extract to root project vx.x" next to this script's framework root.

.EXAMPLE
    ./scripts/validate-template-payload.ps1
    ./scripts/validate-template-payload.ps1 -PayloadPath "extract to root project v3"
#>
[CmdletBinding()]
param(
    [string]$PayloadPath = (Join-Path $PSScriptRoot '..\extract to root project vx.x')
)

$ErrorActionPreference = 'Stop'
$PayloadPath = (Resolve-Path $PayloadPath).Path
$script:FailureCount = 0

function Write-Ok {
    param([string]$Message)
    Write-Host "OK      $Message" -ForegroundColor Green
}

function Write-Fail {
    param([string]$Message, [string]$Path)
    $script:FailureCount++
    if ($Path) {
        Write-Host "FEHLER  $Message : $Path" -ForegroundColor Red
    } else {
        Write-Host "FEHLER  $Message" -ForegroundColor Red
    }
}

Write-Host "Payload-Validator"
Write-Host "================="
Write-Host "Payload: $PayloadPath"
Write-Host ""

# --- Check 1: Frontmatter contract via consumer dry run ---------------------
Write-Host "--- Check 1: Frontmatter-Contract (Konsumenten-Trockenlauf) ---"

$generatorScript = Join-Path $PayloadPath 'scripts\generate-dfc-platform-skills.ps1'
if (-not (Test-Path $generatorScript)) {
    Write-Fail "Generator-Skript nicht gefunden" $generatorScript
} else {
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("dfc-payload-check-{0}" -f ([guid]::NewGuid().ToString('N')))
    try {
        New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

        # Copy payload into disposable directory, excluding .env.mendix.
        robocopy $PayloadPath $tempRoot /E /XF ".env.mendix" /NFL /NDL /NJH /NJS /NC /NS /NP | Out-Null

        $tempGenerator = Join-Path $tempRoot 'scripts\generate-dfc-platform-skills.ps1'
        if (-not (Test-Path $tempGenerator)) {
            Write-Fail "Generator-Skript fehlt nach dem Kopieren in den Trockenlauf" $tempGenerator
        } else {
            & $tempGenerator -ProjectRoot $tempRoot | Out-Null

            $generatedFiles = @()
            $generatedFiles += Get-ChildItem -Path (Join-Path $tempRoot '.claude\skills') -Filter 'SKILL.md' -Recurse -ErrorAction SilentlyContinue
            $generatedFiles += Get-ChildItem -Path (Join-Path $tempRoot '.github\skills') -Filter 'SKILL.md' -Recurse -ErrorAction SilentlyContinue
            $generatedFiles += Get-ChildItem -Path (Join-Path $tempRoot '.claude\agents') -Filter 'dfc-*.md' -ErrorAction SilentlyContinue

            if ($generatedFiles.Count -eq 0) {
                Write-Fail "Konsumenten-Trockenlauf hat keine generierten Skill-/Agentendateien erzeugt" $tempRoot
            } else {
                $frontmatterFailures = 0
                foreach ($file in $generatedFiles) {
                    $firstLine = (Get-Content -Path $file.FullName -TotalCount 1)
                    if ($firstLine -ne '---') {
                        $relative = $file.FullName.Substring($tempRoot.Length + 1)
                        Write-Fail "Zeile 1 ist nicht '---' (YAML-Frontmatter-Contract verletzt)" $relative
                        $frontmatterFailures++
                    }
                }
                if ($frontmatterFailures -eq 0) {
                    Write-Ok ("Frontmatter-Contract eingehalten ({0} generierte Dateien geprueft)" -f $generatedFiles.Count)
                }
            }
        }
    } finally {
        if (Test-Path $tempRoot) {
            Remove-Item -Path $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# --- Check 2: No .env.mendix in payload -------------------------------------
Write-Host ""
Write-Host "--- Check 2: Keine .env.mendix im Payload ---"

# Die Datei darf mitgeliefert werden, solange sie keine Werte traegt.
$envFile = Join-Path $PayloadPath '.env.mendix'
if (Test-Path $envFile) {
    $filled = Get-Content $envFile | Where-Object { $_ -match '^[A-Za-z_][A-Za-z0-9_]*=.+$' }
    if ($filled) {
        Write-Fail "Gesetzte Werte in .env.mendix ($($filled.Count) Schluessel) - Werte leeren oder Datei entfernen" $envFile
    } else {
        Write-Ok "`.env.mendix` vorhanden, aber ohne gesetzte Werte"
    }
} else {
    Write-Ok "Keine .env.mendix im Payload"
}

# --- Check 3: .gitignore hygiene --------------------------------------------
Write-Host ""
Write-Host "--- Check 3: .gitignore-Hygiene ---"

$gitignorePath = Join-Path $PayloadPath '.gitignore'
if (-not (Test-Path $gitignorePath)) {
    Write-Fail ".gitignore fehlt im Payload" $gitignorePath
} else {
    $rawBytes = [System.IO.File]::ReadAllText($gitignorePath)
    $lines = $rawBytes -split "`r?`n"

    # Trailing newline: raw content must end with a line break, i.e. the
    # split produces a final empty element.
    if ($rawBytes.Length -gt 0 -and $lines[-1] -ne '') {
        Write-Fail ".gitignore endet nicht mit einem Zeilenumbruch" $gitignorePath
    } else {
        Write-Ok ".gitignore endet mit Zeilenumbruch"
    }

    # Merged/concatenated lines: a non-comment, non-blank line containing
    # more than one path-like token separated by something other than a
    # single glob pattern is suspicious. Concretely: a line containing a
    # slash-separated second pattern glued to the first (e.g. "*.mpr.bak/.env.mendix")
    # where both halves are independently also valid standalone ignore entries.
    $contentLines = $lines | Where-Object { $_.Trim() -ne '' -and -not $_.Trim().StartsWith('#') }
    $mergedFound = $false
    foreach ($line in $contentLines) {
        $trimmed = $line.Trim()
        if ($trimmed -match '^\*\.[A-Za-z0-9]+\.[A-Za-z0-9]+/\.[A-Za-z0-9]+') {
            Write-Fail "Verdacht auf verschmolzene .gitignore-Zeile" $trimmed
            $mergedFound = $true
        }
    }
    if (-not $mergedFound) {
        Write-Ok "Keine verschmolzenen Zeilen erkannt"
    }

    # Duplicates: same trimmed entry appearing more than once.
    $duplicates = $contentLines | ForEach-Object { $_.Trim() } | Group-Object | Where-Object { $_.Count -gt 1 }
    if ($duplicates) {
        foreach ($dup in $duplicates) {
            Write-Fail "Doppelter .gitignore-Eintrag" $dup.Name
        }
    } else {
        Write-Ok "Keine doppelten .gitignore-Eintraege"
    }
}

# --- Check 4: No absolute machine paths -------------------------------------
Write-Host ""
Write-Host "--- Check 4: Keine absoluten Maschinenpfade ---"

$machinePathPattern = '[A-Za-z]:\\Users\\|D:\\Mendix\\|/home/[A-Za-z0-9_.-]+/'
$excludedDirs = @('.git')
$textExtensions = @('.md', '.yaml', '.yml', '.json', '.ps1', '.sh', '.mdl', '.txt')

$machinePathHits = @()
Get-ChildItem -Path $PayloadPath -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
    $relative = $_.FullName.Substring($PayloadPath.Length + 1)
    if ($excludedDirs | Where-Object { $relative -like "$_*" }) { return }
    if ($_.Extension -notin $textExtensions) { return }
    if ($_.Name -eq '.env.mendix') { return }

    $content = Get-Content -Path $_.FullName -Raw -ErrorAction SilentlyContinue
    if ($null -eq $content) { return }
    if ($content -match $machinePathPattern) {
        $machinePathHits += $relative
    }
}

if ($machinePathHits.Count -gt 0) {
    foreach ($hit in $machinePathHits) {
        Write-Fail "Absoluter Maschinenpfad gefunden" $hit
    }
} else {
    Write-Ok "Keine absoluten Maschinenpfade gefunden"
}

# --- Check 5: No leftover concrete project/story prefixes -------------------
Write-Host ""
Write-Host "--- Check 5: Keine Fremdprojekt-Platzhalterverletzungen ---"

# Known leftover prefix from a real consuming project (CapTrack) that must
# never leak into the neutral template layer. Extend this list if new
# concrete prefixes are discovered during a backport.
$knownLeftoverPrefixes = @('CAP-')

$placeholderHits = @()
Get-ChildItem -Path $PayloadPath -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
    $relative = $_.FullName.Substring($PayloadPath.Length + 1)
    if ($relative -like '.git*') { return }
    if ($_.Extension -notin $textExtensions) { return }
    if ($_.Name -eq '.env.mendix') { return }

    $content = Get-Content -Path $_.FullName -Raw -ErrorAction SilentlyContinue
    if ($null -eq $content) { return }
    foreach ($prefix in $knownLeftoverPrefixes) {
        if ($content -match [regex]::Escape($prefix)) {
            $placeholderHits += "$relative (Muster: $prefix)"
        }
    }
}

if ($placeholderHits.Count -gt 0) {
    foreach ($hit in $placeholderHits) {
        Write-Fail "Konkreter Story-Praefix statt {STORYPREFIX}-Platzhalter" $hit
    }
} else {
    Write-Ok "Keine bekannten Fremdprojekt-Praefixe gefunden"
}

# --- Summary ------------------------------------------------------------------
Write-Host ""
Write-Host "================="
if ($script:FailureCount -gt 0) {
    Write-Host ("{0} Pruefung(en) fehlgeschlagen." -f $script:FailureCount) -ForegroundColor Red
    exit 1
} else {
    Write-Host "Alle Pruefungen bestanden." -ForegroundColor Green
    exit 0
}
