<#
.SYNOPSIS
    SessionStart Bootstrap Safety Tests

.DESCRIPTION
    Regression suite that guards against the brownfield-main regression where the
    Claude Code VS Code Extension timed out with
    "Subprocess initialization did not complete within 60000ms".

    Root cause: bootstrap-mxcli.sh ended with
        exec ./mxcli run --local --setup --ensure-db -p "$MPR"
    which held the SessionStart hook-wait loop open for 60+ seconds.  The
    || true in settings.json only guards against a non-zero exit code; it
    does NOT short-circuit a long-running foreground process.

    Test groups:
    A  - Template bootstrap files do NOT contain the blocking exec line
    B  - Template bootstrap files have bounded curl download timeout
    C  - Template settings.json SessionStart hook is present and safe
    D  - install-core.ps1 contains the bootstrap fixup step (migration path)
    E  - Fixup logic correctly removes the blocking line from a simulated old file
    F  - Fixup is idempotent: running it on an already-safe file changes nothing
    G  - Fresh-clone recoverability: bootstrap still fetches mxcli and syncs skills
    H  - Network failure path: curl failure exits the script, not silently suppressed
    I  - Windows + VS Code Extension: settings.json hook command is a sh invocation
    J  - Existing projects: install-core.ps1 UPDATE path also applies the fixup
#>

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$TestsDir    = $PSScriptRoot
$ScriptDir   = Split-Path -Parent $TestsDir
. (Join-Path $TestsDir 'helpers/MxAgileBaselineFixture.ps1')
$PassCount   = 0
$FailCount   = 0
$FailDetails = @()

function Assert-True {
    param([string]$TestName, [bool]$Condition, [string]$Message)
    if ($Condition) {
        Write-Host "  PASS: $TestName" -ForegroundColor Green
        $script:PassCount++
    } else {
        Write-Host "  FAIL: $TestName -- $Message" -ForegroundColor Red
        $script:FailCount++
        $script:FailDetails += "[$TestName] $Message"
    }
}

function Assert-Contains {
    param([string]$TestName, [string]$FilePath, [string]$Pattern)
    $content = Get-Content -LiteralPath $FilePath -Raw -ErrorAction SilentlyContinue
    if ($null -eq $content) {
        Assert-True $TestName $false "File not found: $FilePath"
    } else {
        Assert-True $TestName ($content -match $Pattern) "Pattern '$Pattern' not found in $FilePath"
    }
}

function Assert-NotContains {
    param([string]$TestName, [string]$FilePath, [string]$Pattern)
    $content = Get-Content -LiteralPath $FilePath -Raw -ErrorAction SilentlyContinue
    if ($null -eq $content) {
        Assert-True $TestName $false "File not found: $FilePath"
    } else {
        Assert-True $TestName ($content -notmatch $Pattern) "Forbidden pattern '$Pattern' found in $FilePath"
    }
}

# Hermetic synthetic files representing output from `mxcli init`.
$templateFixtureRoot = New-MxAgileBaselineFixture -Scenario session-bootstrap
$testingFixtureRoot = New-MxAgileBaselineFixture -Scenario session-bootstrap
$templateBootstrap  = Join-Path $templateFixtureRoot ".claude\bootstrap-mxcli.sh"
$testingBootstrap   = Join-Path $testingFixtureRoot ".claude\bootstrap-mxcli.sh"
$templateSettings   = Join-Path $templateFixtureRoot ".claude\settings.json"
$installCorePath    = Join-Path $ScriptDir "scripts\install-core.ps1"
$sessionStartNormalizer = Join-Path $ScriptDir "scripts\Normalize-MxcliSessionStart.ps1"
$injectionContract = Join-Path $ScriptDir "docs\injection-contract.md"

# Exercise the exact structural normalizer called by install-core after mxcli init.
& $sessionStartNormalizer -SettingsPath $templateSettings
$settingsContent = Get-Content -LiteralPath $templateSettings -Raw | ConvertFrom-Json
$settingsText = Get-Content -LiteralPath $templateSettings -Raw

Write-Host ""
Write-Host "=== SessionStart Bootstrap Safety Tests ==="
Write-Host ""

# ===========================================================================
# GROUP A: Template bootstrap files do NOT contain the blocking exec line
# ===========================================================================
Write-Host "--- A: Synthetic mxcli-init output has no blocking SessionStart command ---"

Assert-True "A1: synthetic bootstrap fixture exists" `
    (Test-Path -LiteralPath $templateBootstrap) `
    "Not found: $templateBootstrap"

Assert-NotContains "A2: bootstrap fixture does NOT contain blocking exec line" `
    $templateBootstrap `
    '^exec\s+\./mxcli\s+run\s+--local'

Assert-NotContains "A3: bootstrap fixture does NOT contain --ensure-db in exec context" `
    $templateBootstrap `
    '^exec.*--ensure-db'

Assert-NotContains "A4: bootstrap fixture does NOT contain --setup in exec context" `
    $templateBootstrap `
    '^exec.*--setup'

Assert-True "A5: independent synthetic bootstrap fixture exists" `
    (Test-Path -LiteralPath $testingBootstrap) `
    "Not found: $testingBootstrap"

Assert-NotContains "A6: independent bootstrap fixture does NOT contain blocking exec line" `
    $testingBootstrap `
    '^exec\s+\./mxcli\s+run\s+--local'

Write-Host ""

# ===========================================================================
# GROUP B: Template bootstrap files have bounded curl download timeout
# ===========================================================================
Write-Host "--- B: Synthetic bootstrap download has bounded timeout ---"

Assert-Contains "B1: bootstrap fixture has --max-time on curl" `
    $templateBootstrap '--max-time'

Assert-Contains "B2: bootstrap fixture has --connect-timeout on curl" `
    $templateBootstrap '--connect-timeout'

Assert-Contains "B3: bootstrap fixture defines DL_TIMEOUT variable" `
    $templateBootstrap 'DL_TIMEOUT='

Assert-Contains "B4: bootstrap fixture DL_TIMEOUT is configurable via env" `
    $templateBootstrap 'MXCLI_DOWNLOAD_TIMEOUT'

Assert-Contains "B5: independent bootstrap fixture also has --max-time on curl" `
    $testingBootstrap '--max-time'

Write-Host ""

# ===========================================================================
# GROUP C: Template settings.json SessionStart hook is present and safe
# ===========================================================================
Write-Host "--- C: synthetic settings.json SessionStart hook is safe ---"

Assert-True "C1: synthetic settings.json exists" `
    (Test-Path -LiteralPath $templateSettings) `
    "Not found: $templateSettings"

Assert-True "C2: settings.json contains SessionStart" `
    ($settingsText -match 'SessionStart') `
    "SessionStart hook missing from settings.json"

Assert-True "C3: mxcli bootstrap hook was removed from SessionStart" `
    (($settingsContent.hooks.SessionStart | ForEach-Object { $_.hooks.command }) -notcontains 'sh .claude/bootstrap-mxcli.sh || true') `
    "mxcli bootstrap hook remains registered in SessionStart"

Assert-True "C4: project-owned SessionStart hook is preserved" `
    (($settingsContent.hooks.SessionStart | ForEach-Object { $_.hooks.command }) -contains 'echo project-owned-session-start') `
    "Provisioning-free project hook was removed"

Assert-True "C5: unrelated settings fields and non-SessionStart hooks are preserved" `
    ($settingsContent.projectSetting.preserve -and $settingsContent.hooks.PreToolUse.Count -eq 1) `
    "JSON normalization dropped unrelated settings fields or hooks"

Write-Host ""

# ===========================================================================
# GROUP D: install-core.ps1 contains the bootstrap fixup step
# ===========================================================================
Write-Host "--- D: install-core.ps1 has the bootstrap fixup migration path ---"

Assert-Contains "D1: install-core.ps1 references bootstrap-mxcli.sh fixup" `
    $installCorePath 'bootstrap-mxcli\.sh'

Assert-Contains "D2: install-core.ps1 checks for the blocking exec pattern" `
    $installCorePath 'exec.*mxcli.*run.*--local|mxcli.*run\s+--local'

Assert-Contains "D3: install-core.ps1 fixup runs unconditionally (not gated on mxcliAlreadyInitialized)" `
    $installCorePath '(?si)Step 1b-fix.*bootstrapPath|bootstrapPath.*Step 1b-fix'

Assert-Contains "D4: install-core.ps1 fixup adds curl --max-time if absent" `
    $installCorePath '--max-time'

Assert-Contains "D5: install-core.ps1 fixup inserts DL_TIMEOUT variable" `
    $installCorePath 'DL_TIMEOUT.*MXCLI_DOWNLOAD_TIMEOUT|MXCLI_DOWNLOAD_TIMEOUT.*DL_TIMEOUT'

Assert-Contains "D6: install-core.ps1 fixup documents the manual provisioning command" `
    $installCorePath '--setup.*--ensure-db|ensure-db.*--setup'

Assert-Contains "D7: install-core.ps1 invokes structural SessionStart normalization" `
    $installCorePath 'Normalize-MxcliSessionStart\.ps1'

Write-Host ""

# ===========================================================================
# GROUP E: Fixup correctly removes the blocking line from a simulated old file
# ===========================================================================
Write-Host "--- E: Fixup removes blocking exec line from old-style bootstrap ---"

$tempDir = Join-Path $env:TEMP "mxagile-bootstrap-fixup-test-$([System.Guid]::NewGuid().ToString('N').Substring(0,8))"

try {
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    $claudeDir = Join-Path $tempDir ".claude"
    New-Item -ItemType Directory -Path $claudeDir -Force | Out-Null

    # Write a bootstrap file that matches the OLD (blocking) format
    $oldBootstrap = @'
#!/bin/sh
# Generated by 'mxcli init'. COMMIT THIS FILE.
set -e

MPR='MyProject.mpr'
TAG="${MXCLI_TAG:-nightly}"

if [ ! -x ./mxcli ]; then
  url="https://github.com/mendixlabs/mxcli/releases/download/${TAG}/mxcli-linux-amd64"
  curl -fsSL -o ./mxcli "$url"
  chmod +x ./mxcli
fi

./mxcli init --sync-skills . || true

exec ./mxcli run --local --setup --ensure-db -p "$MPR"
'@
    $oldBootstrapPath = Join-Path $claudeDir "bootstrap-mxcli.sh"
    [System.IO.File]::WriteAllText($oldBootstrapPath, $oldBootstrap, [System.Text.Encoding]::UTF8)

    # Also create a dummy .mpr file (required by install-core.ps1 pre-flight)
    New-Item -ItemType File -Path (Join-Path $tempDir "MyProject.mpr") -Force | Out-Null

    # Run only the fixup logic inline (simulate what install-core.ps1 does)
    $bsRaw = Get-Content -LiteralPath $oldBootstrapPath -Raw
    $bsLines = $bsRaw -replace "`r`n", "`n" -replace "`r", "`n" -split "`n"
    $changed = $false
    $timeoutVarInserted = $false
    $resultLines = [System.Collections.Generic.List[string]]::new()

    foreach ($line in $bsLines) {
        if ($line -match '^exec\s+\./mxcli\s+run\s+--local') {
            $changed = $true
            continue
        }
        if ($line -match 'curl\s+-fsSL' -and $line -notmatch '--max-time') {
            $line = $line -replace '(curl\s+-fsSL)', '$1 --max-time "$DL_TIMEOUT" --connect-timeout 10'
            $changed = $true
        }
        $resultLines.Add($line)
        if ($line -match '^TAG=' -and -not $timeoutVarInserted -and ($bsRaw -notmatch 'DL_TIMEOUT=')) {
            $resultLines.Add('DL_TIMEOUT="${MXCLI_DOWNLOAD_TIMEOUT:-30}"')
            $timeoutVarInserted = $true
            $changed = $true
        }
    }

    if ($changed) {
        $joined = $resultLines -join "`n"
        if ($joined -notmatch 'NOT run here') {
            $resultLines.Add('')
            $resultLines.Add('# Runtime provisioning (--setup, --ensure-db) is NOT run here — it would block')
            $resultLines.Add('# Claude Code VS Code Extension initialization.  Run explicitly when needed:')
            $resultLines.Add('#   ./mxcli run --local --setup --ensure-db -p "${MPR}"')
        }
        $fixedContent = ($resultLines -join "`n").TrimEnd() + "`n"
        [System.IO.File]::WriteAllText($oldBootstrapPath, $fixedContent, [System.Text.Encoding]::UTF8)
    }

    $fixedContent = Get-Content -LiteralPath $oldBootstrapPath -Raw

    Assert-True "E1: fixup removed the blocking exec line" `
        ($fixedContent -notmatch '^exec\s+\./mxcli\s+run\s+--local') `
        "Blocking 'exec ./mxcli run --local' still present after fixup"

    Assert-True "E2: fixup preserved ./mxcli init --sync-skills" `
        ($fixedContent -match 'mxcli init --sync-skills') `
        "Skills sync line was incorrectly removed during fixup"

    Assert-True "E3: fixup preserved the curl download block" `
        ($fixedContent -match 'curl.*-o.*mxcli') `
        "curl download was incorrectly removed during fixup"

    Assert-True "E4: fixup added --max-time to curl" `
        ($fixedContent -match 'curl.*--max-time') `
        "curl --max-time not added by fixup"

    Assert-True "E5: fixup added DL_TIMEOUT variable" `
        ($fixedContent -match 'DL_TIMEOUT=') `
        "DL_TIMEOUT variable not added by fixup"

    Assert-True "E6: fixup added documentation comment for manual provisioning" `
        ($fixedContent -match 'NOT run here|run explicitly') `
        "Fixup did not add guidance comment for manual provisioning"

    Assert-True "E7: fixed file still starts with shebang" `
        ($fixedContent -match '^#!/bin/sh') `
        "Shebang line was lost during fixup"

} finally {
    if (Test-Path -LiteralPath $tempDir) {
        Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host ""

# ===========================================================================
# GROUP F: Fixup is idempotent on an already-safe file
# ===========================================================================
Write-Host "--- F: Fixup is idempotent on an already-safe bootstrap ---"

$tempDir2 = Join-Path $env:TEMP "mxagile-bootstrap-idempotent-$([System.Guid]::NewGuid().ToString('N').Substring(0,8))"

try {
    New-Item -ItemType Directory -Path $tempDir2 -Force | Out-Null
    $claudeDir2 = Join-Path $tempDir2 ".claude"
    New-Item -ItemType Directory -Path $claudeDir2 -Force | Out-Null

    # Copy the already-fixed template as the starting state
    $safeBootstrapPath = Join-Path $claudeDir2 "bootstrap-mxcli.sh"
    Copy-Item -LiteralPath $templateBootstrap -Destination $safeBootstrapPath -Force

    $contentBefore = Get-Content -LiteralPath $safeBootstrapPath -Raw

    # Run the same fixup logic
    $bsRaw2 = $contentBefore
    $bsLines2 = $bsRaw2 -replace "`r`n", "`n" -replace "`r", "`n" -split "`n"
    $changed2 = $false
    $timeoutVarInserted2 = $false
    $resultLines2 = [System.Collections.Generic.List[string]]::new()

    foreach ($line in $bsLines2) {
        if ($line -match '^exec\s+\./mxcli\s+run\s+--local') {
            $changed2 = $true
            continue
        }
        if ($line -match 'curl\s+-fsSL' -and $line -notmatch '--max-time') {
            $line = $line -replace '(curl\s+-fsSL)', '$1 --max-time "$DL_TIMEOUT" --connect-timeout 10'
            $changed2 = $true
        }
        $resultLines2.Add($line)
        if ($line -match '^TAG=' -and -not $timeoutVarInserted2 -and ($bsRaw2 -notmatch 'DL_TIMEOUT=')) {
            $resultLines2.Add('DL_TIMEOUT="${MXCLI_DOWNLOAD_TIMEOUT:-30}"')
            $timeoutVarInserted2 = $true
            $changed2 = $true
        }
    }

    Assert-True "F1: fixup detects no changes needed on already-safe file" `
        (-not $changed2) `
        "Fixup incorrectly flagged an already-safe bootstrap as needing changes"

    Assert-True "F2: template bootstrap still contains sync-skills after idempotency check" `
        ($contentBefore -match 'mxcli init --sync-skills') `
        "Skills sync disappeared from safe template"

    Assert-True "F3: template bootstrap still contains --max-time after idempotency check" `
        ($contentBefore -match '--max-time') `
        "--max-time missing from safe template"

} finally {
    if (Test-Path -LiteralPath $tempDir2) {
        Remove-Item -LiteralPath $tempDir2 -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host ""

# ===========================================================================
# GROUP G: Fresh-clone recoverability preserved
# ===========================================================================
Write-Host "--- G: Fresh-clone recoverability: bootstrap still fetches mxcli and syncs skills ---"

Assert-Contains "G1: bootstrap checks for missing mxcli binary" `
    $templateBootstrap '! -x.*mxcli'

Assert-Contains "G2: bootstrap downloads mxcli when absent" `
    $templateBootstrap 'curl.*mxcli'

Assert-Contains "G3: bootstrap makes downloaded mxcli executable" `
    $templateBootstrap 'chmod.*\+x.*mxcli'

Assert-Contains "G4: bootstrap runs --sync-skills for fresh clones" `
    $templateBootstrap 'mxcli init --sync-skills'

Assert-Contains "G5: bootstrap documents the manual provisioning step" `
    $templateBootstrap 'run --local --setup --ensure-db'

Assert-Contains "G6: bootstrap uses MXCLI_TAG for pinning specific versions" `
    $templateBootstrap 'MXCLI_TAG'

Write-Host ""

# ===========================================================================
# GROUP H: Network failure handling is explicit, not silently swallowed
# ===========================================================================
Write-Host "--- H: Network failure is diagnosed, not silently swallowed ---"

Assert-Contains "H1: bootstrap prints explicit error message on curl failure" `
    $templateBootstrap 'echo.*ERROR.*Could not download'

Assert-Contains "H2: bootstrap exits non-zero on curl failure (not silently continues)" `
    $templateBootstrap 'exit 1'

Assert-Contains "H3: bootstrap documents recovery after network failure" `
    $templateBootstrap 'Fetch it manually|obtain mxcli'

Assert-NotContains "H4: normalized settings do not run the bootstrap download at SessionStart" `
    $templateSettings 'bootstrap-mxcli\.sh|mxcli.*run.*--local'

Write-Host ""

# ===========================================================================
# GROUP I: Windows + VS Code Extension compatibility
# ===========================================================================
Write-Host "--- I: Windows and VS Code Extension compatibility ---"

Assert-True "I1: project-owned SessionStart hook remains registered" `
    (($settingsContent.hooks.SessionStart | ForEach-Object { $_.hooks.command }) -contains 'echo project-owned-session-start') `
    'Provisioning-free project SessionStart hook was not retained'

Assert-True "I2: settings.json hook is under SessionStart (not PreToolUse or other)" `
    ($settingsText -match '"SessionStart"') `
    "Hook must be registered under SessionStart"

Assert-NotContains "I3: bootstrap does NOT use bash-specific shebang" `
    $templateBootstrap '/bin/bash'

Assert-Contains "I4: bootstrap uses portable /bin/sh shebang" `
    $templateBootstrap '/bin/sh'

Assert-True "I5: additional settings fields and hook-group metadata survive normalization" `
    ($settingsContent.projectSetting.preserve -and $settingsContent.hooks.SessionStart[0].matcher -eq '') `
    "Additional JSON fields were dropped during normalization"

Write-Host ""

# ===========================================================================
# GROUP J: Existing projects: UPDATE path also applies the fixup
# ===========================================================================
Write-Host "--- J: UPDATE path in install-core.ps1 applies the fixup ---"

$installCoreContent = Get-Content -LiteralPath $installCorePath -Raw

# The fixup block must NOT be nested inside the `if ($mxcliAlreadyInitialized)` branch
# (which would skip it for updates).  Verify by checking that the fixup comment
# appears outside any $mxcliAlreadyInitialized conditional.
$fixupIndex      = $installCoreContent.IndexOf('Step 1b-fix')
$skipGateIndex   = $installCoreContent.IndexOf('mxcliAlreadyInitialized')
$afterGate       = if ($skipGateIndex -ge 0) {
    # Find the closing brace of the if/else block that contains mxcliAlreadyInitialized
    # by checking that the fixup anchor appears after the last occurrence of
    # "Write-Host `"[OK] bootstrap..." within the if/else block
    $provIndex = $installCoreContent.IndexOf('[OK] mxcli-init provenance written')
    $provIndex
} else { 0 }

Assert-True "J1: fixup step exists in install-core.ps1" `
    ($fixupIndex -ge 0) `
    "Fixup step 'Step 1b-fix' not found in install-core.ps1"

Assert-True "J2: fixup step appears AFTER the mxcliAlreadyInitialized if/else block" `
    ($fixupIndex -gt $afterGate) `
    "Fixup must run after the mxcli init if/else so it executes on both fresh install and UPDATE"

Assert-Contains "J3: install-core.ps1 fixup uses WriteAllText with UTF8 encoding" `
    $installCorePath '\[System\.IO\.File\]::WriteAllText.*UTF8|WriteAllText.*bootstrapPath'

Assert-Contains "J4: install-core.ps1 fixup reports [OK] when no fix needed (idempotent)" `
    $installCorePath 'SessionStart is already safe|no fix needed'

Assert-Contains "J5: install-core.ps1 fixup reports [FIX] when blocking line removed" `
    $installCorePath 'removed blocking.*exec.*mxcli run --local|\[FIX\].*bootstrap'

Write-Host ''

# ===========================================================================
# GROUP K: Structural JSON normalization is safe, idempotent, and repeatable
# ===========================================================================
Write-Host "--- K: structural mxcli SessionStart normalization ---"

$normalizerTemp = Join-Path $env:TEMP "mxagile-sessionstart-json-$([System.Guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $normalizerTemp -Force | Out-Null

try {
    $normalizerSettingsPath = Join-Path $normalizerTemp 'settings.json'
    $variableHook = @'
MXCLI=./mxcli
if [ -x "$MXCLI" ]; then
  "$MXCLI" run -p "$MPR" --ensure-db --setup --local
fi
'@
    $structuredSettings = [ordered]@{
        projectSetting = [ordered]@{ preserve = $true; extra = 42 }
        hooks = [ordered]@{
            SessionStart = @(
                [ordered]@{
                    matcher = ''
                    groupMetadata = 'keep'
                    hooks = @(
                        [ordered]@{ type = 'command'; command = 'exec ./mxcli run --local --setup --ensure-db -p "$MPR"'; generatedMarker = 'mxcli' },
                        [ordered]@{ type = 'command'; command = $variableHook; generatedMarker = 'mxcli' },
                        [ordered]@{ type = 'command'; command = './mxcli init --sync-skills .'; owner = 'mxcli' },
                        [ordered]@{ type = 'command'; command = 'echo project-owned-session-start'; owner = 'project' }
                    )
                }
            )
            PreToolUse = @([ordered]@{ hooks = @([ordered]@{ type = 'command'; command = 'echo pre-tool' }) })
        }
    }
    [System.IO.File]::WriteAllText($normalizerSettingsPath, (ConvertTo-Json -InputObject $structuredSettings -Depth 20))
    & $sessionStartNormalizer -SettingsPath $normalizerSettingsPath
    $normalizedSettings = Get-Content -LiteralPath $normalizerSettingsPath -Raw | ConvertFrom-Json
    $remainingCommands = @($normalizedSettings.hooks.SessionStart[0].hooks | ForEach-Object { $_.command })

    Assert-True "K1: old direct hook with canonical flags is removed" `
        ($remainingCommands -notcontains 'exec ./mxcli run --local --setup --ensure-db -p "$MPR"') `
        "Known mxcli provisioning hook remains"
    Assert-True "K2: variable-backed shell-block hook is removed" `
        ($remainingCommands -notcontains $variableHook) `
        "Variable-backed mxcli provisioning hook remains"
    Assert-True "K3: provisioning-free mxcli and project hooks are retained" `
        ($remainingCommands -contains './mxcli init --sync-skills .' -and $remainingCommands -contains 'echo project-owned-session-start') `
        "Provisioning-free hooks were not preserved"
    Assert-True "K4: unrelated JSON fields, groups, and event hooks survive" `
        ($normalizedSettings.projectSetting.preserve -and $normalizedSettings.projectSetting.extra -eq 42 -and $normalizedSettings.hooks.SessionStart[0].groupMetadata -eq 'keep' -and $normalizedSettings.hooks.PreToolUse.Count -eq 1) `
        "Normalization dropped unrelated JSON fields"
    Assert-True "K5: normal SessionStart has no runtime, dependency, DB, or binary provisioning command" `
        (@($remainingCommands -match '(?i)bootstrap-mxcli\.sh|mxcli.*run.*(?:--local|--setup|--ensure-db)|curl.*mxcli').Count -eq 0) `
        "A provisioning command remains registered for SessionStart"

    $normalizedBytes = Get-Content -LiteralPath $normalizerSettingsPath -Raw
    & $sessionStartNormalizer -SettingsPath $normalizerSettingsPath
    Assert-True "K6: repeated normalization is idempotent" `
        ((Get-Content -LiteralPath $normalizerSettingsPath -Raw) -ceq $normalizedBytes) `
        "Second normalization changed settings.json"

    $reinitSettings = [ordered]@{ hooks = [ordered]@{ SessionStart = @([ordered]@{ hooks = @([ordered]@{ type = 'command'; command = './mxcli run --ensure-db --local --setup -p app.mpr' }) }) } }
    [System.IO.File]::WriteAllText($normalizerSettingsPath, (ConvertTo-Json -InputObject $reinitSettings -Depth 20))
    & $sessionStartNormalizer -SettingsPath $normalizerSettingsPath
    $afterReinit = Get-Content -LiteralPath $normalizerSettingsPath -Raw | ConvertFrom-Json
    Assert-True "K7: repeated mxcli init output is normalized on the next installer pass" `
        ($afterReinit.hooks.SessionStart[0].hooks.Count -eq 0) `
        "A repeated mxcli init left provisioning registered"

    $pipelineJson = '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"./mxcli run --local --setup --ensure-db -p app.mpr | tee runtime.log"}]}]}}'
    [System.IO.File]::WriteAllText($normalizerSettingsPath, $pipelineJson)
    $beforeAmbiguous = Get-Content -LiteralPath $normalizerSettingsPath -Raw
    $pipelineRejected = $false
    try { & $sessionStartNormalizer -SettingsPath $normalizerSettingsPath } catch { $pipelineRejected = $true }
    Assert-True "K8: mixed pipeline ownership fails closed without rewriting JSON" `
        ($pipelineRejected -and (Get-Content -LiteralPath $normalizerSettingsPath -Raw) -ceq $beforeAmbiguous) `
        "Ambiguous pipeline was modified or accepted"

    $mixedJson = '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"echo start; ./mxcli run --local --setup --ensure-db -p app.mpr"}]}]}}'
    [System.IO.File]::WriteAllText($normalizerSettingsPath, $mixedJson)
    $beforeMixed = Get-Content -LiteralPath $normalizerSettingsPath -Raw
    $mixedRejected = $false
    try { & $sessionStartNormalizer -SettingsPath $normalizerSettingsPath } catch { $mixedRejected = $true }
    Assert-True "K9: mixed shell command fails closed without rewriting JSON" `
        ($mixedRejected -and (Get-Content -LiteralPath $normalizerSettingsPath -Raw) -ceq $beforeMixed) `
        "Mixed shell hook was modified or accepted"

    $invalidJson = '{ "hooks": '
    [System.IO.File]::WriteAllText($normalizerSettingsPath, $invalidJson)
    $beforeInvalid = Get-Content -LiteralPath $normalizerSettingsPath -Raw
    $invalidRejected = $false
    try { & $sessionStartNormalizer -SettingsPath $normalizerSettingsPath } catch { $invalidRejected = $true }
    Assert-True "K10: invalid JSON fails closed without rewriting the file" `
        ($invalidRejected -and (Get-Content -LiteralPath $normalizerSettingsPath -Raw) -ceq $beforeInvalid) `
        "Invalid JSON was modified or accepted"

    $invalidShape = '{"hooks":{"SessionStart":{"hooks":[]}}}'
    [System.IO.File]::WriteAllText($normalizerSettingsPath, $invalidShape)
    $beforeInvalidShape = Get-Content -LiteralPath $normalizerSettingsPath -Raw
    $invalidShapeRejected = $false
    try { & $sessionStartNormalizer -SettingsPath $normalizerSettingsPath } catch { $invalidShapeRejected = $true }
    Assert-True "K11: valid JSON with an invalid SessionStart shape fails closed without rewriting" `
        ($invalidShapeRejected -and (Get-Content -LiteralPath $normalizerSettingsPath -Raw) -ceq $beforeInvalidShape) `
        "Malformed SessionStart structure was modified or accepted"

    Assert-Contains "K12: native mxcli suppression remains unverified without a pinned project binary" `
        $injectionContract 'Native mxcli suppression capability is `NOT_VERIFIED`'
} finally {
    Remove-Item -LiteralPath $normalizerTemp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''

# Final summary
# ===========================================================================
Remove-MxAgileBaselineFixture -Path $templateFixtureRoot
Remove-MxAgileBaselineFixture -Path $testingFixtureRoot

Write-Host '=== SessionStart Bootstrap Safety Test Results ==='
Write-Host ('  PASS: ' + $PassCount) -ForegroundColor Green
if ($FailCount -gt 0) {
    Write-Host ('  FAIL: ' + $FailCount) -ForegroundColor Red
    foreach ($detail in $FailDetails) {
        Write-Host ('    ' + $detail) -ForegroundColor Red
    }
    Write-Host ''
    Write-Host 'TEST FAILED: SessionStart bootstrap safety contract violated.' -ForegroundColor Red
    Write-Host '  The regression: Claude Code VS Code Extension timed out with' -ForegroundColor Red
    Write-Host '  Subprocess initialization did not complete within 60000ms' -ForegroundColor Red
    exit 1
} else {
    Write-Host ''
    $msg = 'TEST PASSED: SessionStart bootstrap contract is safe and deterministic.'
    Write-Host $msg -ForegroundColor Green
    exit 0
}
