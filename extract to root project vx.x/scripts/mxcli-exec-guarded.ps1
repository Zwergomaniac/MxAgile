<#
.SYNOPSIS
Guarded wrapper around 'mxcli exec' that checks DFC-AI gate status before running.

.DESCRIPTION
Kein Commit-Hook, keine persistente Override-Flag. Diese Datei liest den Gate-Status
der betroffenen Wave aus .concord/scratch/process-state.yaml (abgeleitet aus dem
Dateinamen-Praefix, z.B. w4b-01-...mdl -> Wave W4b) und fragt bei jedem Aufruf mit
nicht bestandenen/fehlenden Gates erneut interaktiv nach - nichts wird gemerkt oder
automatisch fuer kuenftige Aufrufe uebernommen. Das erzwingt eine bewusste
Entscheidung pro Aufruf statt eines einmalig gesetzten Bypasses.

.PARAMETER Script
Pfad zur .mdl-Datei, die ausgefuehrt werden soll.

.PARAMETER Project
Pfad zur .mpr-Projektdatei (wie bei 'mxcli exec -p').

.EXAMPLE
./scripts/mxcli-exec-guarded.ps1 mdlsource/w4b-01-undo-model.mdl -p Project.mpr
#>

[CmdletBinding(PositionalBinding = $false)]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Script,

    [Alias('p')]
    [string]$Project,

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RemainingArgs
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$stateFile = Join-Path $projectRoot '.concord/scratch/process-state.yaml'

function Get-WaveKeyFromFileName {
    param([string]$FileName)
    $base = [System.IO.Path]::GetFileNameWithoutExtension($FileName)
    if ($base -match '^(w\d+[a-z]?)-') {
        $prefix = $Matches[1]
        return 'W' + $prefix.Substring(1)
    }
    return $null
}

function Get-GateStatus {
    param([string]$StateFilePath, [string]$WaveKey)

    if (-not (Test-Path -Path $StateFilePath -PathType Leaf)) {
        return [pscustomobject]@{ Found = $false; Refinement = $null; Ready = $null }
    }

    $raw = Get-Content -Path $StateFilePath -Raw
    $pattern = "(?m)^\s{2}$([regex]::Escape($WaveKey)):\s*\r?\n((?:^\s{4,}.*\r?\n?)*)"
    $m = [regex]::Match($raw, $pattern)
    if (-not $m.Success) {
        return [pscustomobject]@{ Found = $false; Refinement = $null; Ready = $null }
    }

    $block = $m.Groups[1].Value
    $refinement = $null
    $ready = $null
    if ($block -match 'gate_to_refinement:\s*(\S+)') { $refinement = $Matches[1] }
    if ($block -match 'gate_to_ready:\s*(\S+)') { $ready = $Matches[1] }
    return [pscustomobject]@{ Found = $true; Refinement = $refinement; Ready = $ready }
}

function Get-AllWaveGateSummaries {
    param([string]$StateFilePath)

    if (-not (Test-Path -Path $StateFilePath -PathType Leaf)) { return @() }

    $raw = Get-Content -Path $StateFilePath -Raw
    $wavesSection = [regex]::Match($raw, '(?m)^waves:\s*\r?\n((?:^(?!\S).*\r?\n?)*)')
    if (-not $wavesSection.Success) { return @() }

    $body = $wavesSection.Groups[1].Value
    $entries = [regex]::Matches($body, '(?m)^\s{2}(\S+):\s*\r?\n((?:^\s{4,}.*\r?\n?)*)')
    $result = @()
    foreach ($entry in $entries) {
        $wave = $entry.Groups[1].Value
        $block = $entry.Groups[2].Value
        $phase = if ($block -match 'phase:\s*(\S+)') { $Matches[1] } else { '-' }
        $refinement = if ($block -match 'gate_to_refinement:\s*(\S+)') { $Matches[1] } else { '-' }
        $ready = if ($block -match 'gate_to_ready:\s*(\S+)') { $Matches[1] } else { '-' }
        $quality = if ($block -match 'quality_gate:\s*(\S+)') { $Matches[1] } else { '-' }
        $result += [pscustomobject]@{
            Wave       = $wave
            Phase      = $phase
            Refinement = $refinement
            Ready      = $ready
            Quality    = $quality
        }
    }
    return $result
}

function Write-WaveOverview {
    param([string]$StateFilePath, [string]$CurrentWave)

    $summaries = Get-AllWaveGateSummaries -StateFilePath $StateFilePath
    if (-not $summaries -or $summaries.Count -eq 0) { return }

    Write-Host ''
    Write-Host '--- Wave-Uebersicht (informativ, nicht blockierend) ---' -ForegroundColor DarkGray
    $rows = $summaries | ForEach-Object {
        $marker = if ($_.Wave -eq $CurrentWave) { '-> ' } else { '   ' }
        '{0}{1,-6} phase={2,-12} gate_to_refinement={3,-12} gate_to_ready={4,-12} quality_gate={5}' -f `
            $marker, $_.Wave, $_.Phase, $_.Refinement, $_.Ready, $_.Quality
    }
    $rows | ForEach-Object { Write-Host $_ -ForegroundColor DarkGray }
    Write-Host 'Dient nur der eigenen Uebersicht ueber fruehere Waves; blockiert nichts.' -ForegroundColor DarkGray
    Write-Host ''
}

$waveKey = Get-WaveKeyFromFileName -FileName $Script
$needsConfirmation = $true

Write-WaveOverview -StateFilePath $stateFile -CurrentWave $waveKey

if (-not $waveKey) {
    Write-Warning "Konnte keine Wave aus dem Dateinamen '$Script' ableiten (erwartet z.B. w4b-01-...). Gate-Pruefung wird uebersprungen, Ausfuehrung geht ohne Nachfrage weiter."
    $needsConfirmation = $false
} else {
    $status = Get-GateStatus -StateFilePath $stateFile -WaveKey $waveKey

    if ($status.Found -and $status.Refinement -eq 'passed' -and $status.Ready -eq 'passed') {
        $needsConfirmation = $false
    } else {
        Write-Host ''
        Write-Host "=== Gate-Warnung fuer Wave $waveKey ===" -ForegroundColor Yellow
        if (-not $status.Found) {
            Write-Host "Diese Wave ist in process-state.yaml gar nicht erfasst (weder Discovery noch Refinement dokumentiert)." -ForegroundColor Yellow
        } else {
            Write-Host "gate_to_refinement: $($status.Refinement)" -ForegroundColor Yellow
            Write-Host "gate_to_ready:      $($status.Ready)" -ForegroundColor Yellow
        }
        Write-Host ''
        Write-Host 'Konsequenz, wenn du fortfaehrst: kein bestaetigter Mockup-/UI-Abgleich, keine' -ForegroundColor Yellow
        Write-Host 'aufgeloesten DECISION-REQUIRED-Punkte garantiert, Risiko spaeterer Nacharbeit.' -ForegroundColor Yellow
        Write-Host ''
    }
}

if ($needsConfirmation) {
    $answer = Read-Host "Trotzdem ausfuehren? Nur mit expliziter Entwicklerfreigabe (ja/nein)"
    if ($answer -notin @('ja', 'j', 'yes', 'y')) {
        Write-Host 'Abgebrochen. Keine Aenderung ausgefuehrt.' -ForegroundColor Red
        exit 1
    }
    Write-Host 'Fortfahren nach expliziter Freigabe.' -ForegroundColor Yellow
}

$wrapperArgs = @('exec', $Script)
if ($Project) { $wrapperArgs += @('-p', $Project) }
if ($RemainingArgs) { $wrapperArgs += $RemainingArgs }

$localWrapper = Join-Path $PSScriptRoot 'mxcli.ps1'
if (Test-Path -Path $localWrapper -PathType Leaf) {
    & $localWrapper @wrapperArgs
} else {
    & mxcli @wrapperArgs
}
exit $LASTEXITCODE
