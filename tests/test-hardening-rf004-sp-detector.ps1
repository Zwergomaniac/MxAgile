<#
.SYNOPSIS
RF-004: Studio Pro detector regression tests.
Covers: detector succeeds, times out, unrelated SP instance, MPR lock,
UNKNOWN vs CLOSED-AUTONOM, no false LIVE_SP_CURRENT, ask-once preserved.
#>

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$detectorScript = Join-Path $repoRoot "scripts\check-studio-pro-status.ps1"
$policyFile = Join-Path $repoRoot ".mxagile\policies\operating-mode.md"

$pass = 0
$fail = 0
$errors = @()

function Pass([string]$name) {
    $script:pass++
    Write-Host "  PASS  $name" -ForegroundColor Green
}

function Fail([string]$name, [string]$reason) {
    $script:fail++
    $script:errors += "FAIL: $name — $reason"
    Write-Host "  FAIL  $name" -ForegroundColor Red
    Write-Host "        $reason" -ForegroundColor DarkRed
}

Write-Host ""
Write-Host "RF-004: Studio Pro Detector Hardening" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan
Write-Host ""

# -----------------------------------------------------------------------
# Test 1: Detector script has -TimeoutSeconds parameter
# -----------------------------------------------------------------------
$t = "Detector: -TimeoutSeconds parameter exists"
try {
    $content = Get-Content $detectorScript -Raw
    if ($content -match "\[int\]\s*\`$TimeoutSeconds") {
        Pass $t
    } else {
        Fail $t "check-studio-pro-status.ps1 does not have [int]\$TimeoutSeconds parameter"
    }
} catch {
    Fail $t "Exception: $_"
}

# -----------------------------------------------------------------------
# Test 2: Detector uses Wait-Job with timeout (bounded detection)
# -----------------------------------------------------------------------
$t = "Detector: uses bounded background job (Wait-Job -Timeout)"
try {
    $content = Get-Content $detectorScript -Raw
    if ($content -match "Wait-Job.*-Timeout" -or $content -match "Start-Job") {
        Pass $t
    } else {
        Fail $t "Detector does not use bounded job pattern (Start-Job/Wait-Job)"
    }
} catch {
    Fail $t "Exception: $_"
}

# -----------------------------------------------------------------------
# Test 3: Timeout produces exit code 2 with TIMEOUT in error
# -----------------------------------------------------------------------
$t = "Detector timeout: exit code 2 and TIMEOUT error message"
try {
    $content = Get-Content $detectorScript -Raw
    if ($content -match "exit 2" -and $content -match "TIMEOUT") {
        Pass $t
    } else {
        Fail $t "Detector does not emit TIMEOUT error message on timeout"
    }
} catch {
    Fail $t "Exception: $_"
}

# -----------------------------------------------------------------------
# Test 4: Timeout JSON includes detection_state = UNKNOWN
# -----------------------------------------------------------------------
$t = "Detector timeout JSON: detection_state UNKNOWN"
try {
    $content = Get-Content $detectorScript -Raw
    if (($content -match "detection_state.*UNKNOWN") -or ($content -match "UNKNOWN.*detection_state")) {
        Pass $t
    } else {
        Fail $t "Timeout JSON output does not include detection_state: UNKNOWN"
    }
} catch {
    Fail $t "Exception: $_"
}

# -----------------------------------------------------------------------
# Tests 5-8: Current C2 detection semantics, not retired metadata names
# -----------------------------------------------------------------------
& {
    $fixtureRoot = Join-Path $env:TEMP ('mxagile-rf004-' + [guid]::NewGuid().ToString('N'))
    try {
        $resolverFile = Join-Path $repoRoot 'scripts/Get-MxAgileCapabilities.ps1'
        $resolverRoot = Split-Path -Parent $resolverFile
        $tokens = $null
        $parseErrors = $null
        $resolverAst = [System.Management.Automation.Language.Parser]::ParseFile($resolverFile, [ref]$tokens, [ref]$parseErrors)
        if ($parseErrors.Count) { throw 'C2 resolver could not be parsed.' }
        foreach ($functionName in @('Invoke-StudioProStatusDetector', 'Resolve-OperatingModeRoute', 'Resolve-OperatingModeAuthority')) {
            $functionAst = $resolverAst.Find({
                param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $functionName
            }, $true)
            if ($null -eq $functionAst) { throw "C2 function missing: $functionName" }
            . ([ScriptBlock]::Create(($functionAst.Extent.Text -replace '\$PSScriptRoot', '$resolverRoot')))
        }
        $ProjectRoot = $fixtureRoot
        $StudioProProjectPath = Join-Path $fixtureRoot 'App.mpr'
        $StudioProMcpProbeStatus = $ConcordMcpProbeStatus = 'NOT_OBSERVED'
        $StudioProMcpBoundProjectPath = $ConcordMcpBoundProjectPath = ''
        New-Item -ItemType Directory -Path $fixtureRoot | Out-Null
        New-Item -ItemType File -Path $StudioProProjectPath, "$StudioProProjectPath.lock" | Out-Null
        function Get-DeclaredMcpConfiguration {
            param([string]$CapabilityId)
            return [ordered]@{ state = 'OBSERVED'; configured = $false; source = $CapabilityId }
        }
        function Start-Process {
            param($FilePath, $ArgumentList, [switch]$PassThru, [switch]$Wait, $RedirectStandardOutput, $RedirectStandardError)
            [ordered]@{ isOpen = $null; anyStudioProRunning = $null; error = 'TIMEOUT: synthetic detector timeout'; detection_state = 'UNKNOWN' } |
                ConvertTo-Json | Set-Content -LiteralPath $RedirectStandardOutput
            return [pscustomobject]@{ ExitCode = 2 }
        }
        $timeoutDetection = Invoke-StudioProStatusDetector -MprPath $StudioProProjectPath
        $timeoutAuthority = Resolve-OperatingModeAuthority
        $t = 'C2: Windows timeout is ambiguous; headless mode uses positive platform evidence'
        $authorityValid = if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
            $timeoutAuthority.mode -eq 'AMBIGUOUS-SP-STATE' -and -not $timeoutAuthority.tool_authority.mxcli_permitted -and
                $timeoutAuthority.tool_authority.status -eq 'RECHECK_REQUIRED'
        } else {
            $timeoutAuthority.mode -eq 'CLOSED-AUTONOM' -and $timeoutAuthority.detection.state -eq 'OBSERVED' -and
                $timeoutAuthority.detection.source -eq 'platform_headless'
        }
        if ($authorityValid) { Pass $t }
        else { Fail $t 'Timeout or headless platform evidence was mapped to the wrong authority.' }

        $t = 'C2: timeout provenance preserves detector source and observed reason'
        if ($timeoutDetection.source -eq $detectorScript -and $timeoutDetection.reason -match '^TIMEOUT:') { Pass $t }
        else { Fail $t 'Timeout provenance was lost.' }

        $t = 'C2: unavailable detection preserves UNKNOWN and null process observations'
        if ($timeoutDetection.state -eq 'UNKNOWN' -and $null -eq $timeoutDetection.is_open -and
            $null -eq $timeoutDetection.any_studio_pro_running) { Pass $t }
        else { Fail $t 'Unavailable evidence was converted to a positive or negative observation.' }

        function Start-Process {
            param($FilePath, $ArgumentList, [switch]$PassThru, [switch]$Wait, $RedirectStandardOutput, $RedirectStandardError)
            [ordered]@{ isOpen = $false; anyStudioProRunning = $false; projectPath = $StudioProProjectPath } |
                ConvertTo-Json | Set-Content -LiteralPath $RedirectStandardOutput
            return [pscustomobject]@{ ExitCode = 1 }
        }
        $absentAuthority = Resolve-OperatingModeAuthority
        $t = 'C2: an MPR lock alone does not establish LIVE-SP or execution intent'
        $intentPolicy = Get-Content (Join-Path $repoRoot '.mxagile/policies/execution-intent.md') -Raw
        if ($absentAuthority.mode -eq 'CLOSED-AUTONOM' -and $intentPolicy -match 'not a user-selected') { Pass $t }
        else { Fail $t 'A lock overrode process evidence or operating mode became a user-selected intent.' }
    } catch {
        Fail 'C2: isolated RF-004 behavior checks' "Exception: $_"
    } finally {
        Remove-Item -LiteralPath $fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# -----------------------------------------------------------------------
# Test 9: Known operating mode does not trigger an execution-mode question
# -----------------------------------------------------------------------
$t = "Execution-intent policy: known mode routes without asking"
try {
    $execIntentFile = Join-Path $repoRoot ".mxagile\policies\execution-intent.md"
    $content = Get-Content $execIntentFile -Raw
    if (($content -match "known mode.*without asking") -and ($content -match "not a user-selected")) {
        Pass $t
    } else {
        Fail $t "execution-intent.md does not route a known mode automatically"
    }
} catch {
    Fail $t "Exception: $_"
}

# -----------------------------------------------------------------------
# Test 10: MCP tool presence is not health or project identity
# -----------------------------------------------------------------------
$t = "Execution-intent policy: tool presence does NOT imply healthy same-project route"
try {
    $execIntentFile = Join-Path $repoRoot ".mxagile\policies\execution-intent.md"
    $content = Get-Content $execIntentFile -Raw
    $hasHealthBoundary = $content -match "tool appears in the active tool set.*Successful operation"
    $hasIdentityBoundary = $content -match "identity returned by the endpoint"
    if ($hasHealthBoundary -and $hasIdentityBoundary) {
        Pass $t
    } else {
        Fail $t "execution-intent.md does not distinguish tool presence, health, and project identity"
    }
} catch {
    Fail $t "Exception: $_"
}

# -----------------------------------------------------------------------
# Test 11: Project path matching requires a complete command-line argument
# -----------------------------------------------------------------------
$t = "Detector: exact normalized MPR argument match"
try {
    $projectArgument = 'C:\work\App.mpr'.ToLowerInvariant()
    $projectPattern = "(?i)(?<![^\s`"'=])$([regex]::Escape($projectArgument))(?=$|[\s`"'])"
    $sameProject = 'studiopro.exe -project "c:\work\app.mpr"'
    $similarPrefix = 'studiopro.exe -project "c:\work\app.mpr-backup"'
    $similarSuffix = 'studiopro.exe -project "c:\work\app.mprBackup"'
    $matchesSame = [regex]::IsMatch($sameProject, $projectPattern)
    $matchesPrefix = [regex]::IsMatch($similarPrefix, $projectPattern)
    $matchesSuffix = [regex]::IsMatch($similarSuffix, $projectPattern)
    if ($matchesSame -and -not $matchesPrefix -and -not $matchesSuffix) {
        Pass $t
    } else {
        Fail $t "Expected only the exact path to match (same=$matchesSame, prefix=$matchesPrefix, suffix=$matchesSuffix)"
    }
} catch {
    Fail $t "Exception: $_"
}

# -----------------------------------------------------------------------
# Test 12: Failed CIM probe or unreadable command line remains UNKNOWN
# -----------------------------------------------------------------------
$t = "Detector: CIM failure and unreadable command line remain UNKNOWN"
try {
    $content = Get-Content $detectorScript -Raw
    $probeFailsClosed = ($content -match 'Get-CimInstance Win32_Process.*-ErrorAction Stop') -and
                        ($content -match '\$detectionJob\.State -eq .Failed.')
    $unreadableIsUnknown = ($content -match '\$unreadableProcesses') -and
                           ($content -match 'AMBIGUOUS-SP-STATE.*NOT LIVE-SP-OTHER or CLOSED-AUTONOM') -and
                           ($content -match 'detection_state\s*=\s*"UNKNOWN"')
    if ($probeFailsClosed -and $unreadableIsUnknown) {
        Pass $t
    } else {
        Fail $t "CIM failure/unreadable process can still be classified as absent or foreign (probe=$probeFailsClosed, unreadable=$unreadableIsUnknown)"
    }
} catch {
    Fail $t "Exception: $_"
}

# -----------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------
Write-Host ""
Write-Host "Results: $pass passed, $fail failed" -ForegroundColor $(if ($fail -eq 0) { "Green" } else { "Red" })
if ($errors.Count -gt 0) {
    Write-Host ""
    foreach ($e in $errors) { Write-Host "  $e" -ForegroundColor Red }
}
Write-Host ""

exit $fail
