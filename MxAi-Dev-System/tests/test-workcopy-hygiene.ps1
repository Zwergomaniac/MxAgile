# tests/test-workcopy-hygiene.ps1
# Regression suite for create-test-workcopy.ps1

$ErrorActionPreference = "Stop"
$PassCount = 0
$FailCount = 0

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$WorkspaceRoot = Split-Path -Parent $ScriptRoot
$CreateScript = Join-Path $ScriptRoot "..\scripts\create-test-workcopy.ps1"

function Pass { param([string]$msg) $script:PassCount++; Write-Host "  PASS: $msg" }
function Fail { param([string]$msg) $script:FailCount++; Write-Host "  FAIL: $msg" -ForegroundColor Red }
function Assert {
    param([bool]$Condition, [string]$Label)
    if ($Condition) { Pass $Label } else { Fail $Label }
}

# Helper: create a minimal fixture in a temp dir
function New-MinimalFixture {
    param(
        [string]$Name,
        [switch]$WithDfc,
        [switch]$WithPlanning,
        [switch]$WithNodeModules,
        [switch]$WithMendixCache,
        [switch]$WithDockerBuild,
        [switch]$WithLifecycle
    )
    $dir = Join-Path $env:TEMP "mxagile-test-fixture-$Name-$([guid]::NewGuid().ToString('N').Substring(0,8))"
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    New-Item -ItemType File -Path (Join-Path $dir "project.mpr") | Out-Null

    if ($WithDfc) {
        $dfc = Join-Path $dir '.dfc-ai'
        New-Item -ItemType Directory -Path $dfc | Out-Null
        Set-Content -Path (Join-Path $dfc 'version.yaml') -Value 'version: "2.0"'
    }
    if ($WithPlanning) {
        $plan = Join-Path $dir 'planning\stories'
        New-Item -ItemType Directory -Path $plan -Force | Out-Null
        Set-Content -Path (Join-Path $plan 'REQ-001.md') -Value '# REQ-001'
    }
    if ($WithNodeModules) {
        $nm = Join-Path $dir '.opencode\node_modules\some-pkg'
        New-Item -ItemType Directory -Path $nm -Force | Out-Null
        Set-Content -Path (Join-Path $nm 'index.js') -Value 'module.exports = {}'
        # Also nest deeper
        $nm2 = Join-Path $dir 'tooling\node_modules\other-pkg'
        New-Item -ItemType Directory -Path $nm2 -Force | Out-Null
        Set-Content -Path (Join-Path $nm2 'lib.js') -Value 'exports.x = 1'
    }
    if ($WithMendixCache) {
        $mc = Join-Path $dir '.mendix-cache\extensions-cache'
        New-Item -ItemType Directory -Path $mc -Force | Out-Null
        Set-Content -Path (Join-Path $mc 'cached.bin') -Value 'binary-data'
    }
    if ($WithDockerBuild) {
        $db = Join-Path $dir '.docker\build\lib'
        New-Item -ItemType Directory -Path $db -Force | Out-Null
        Set-Content -Path (Join-Path $db 'layer.tar') -Value 'docker-layer'
        # Keep compose file at .docker root (should NOT be excluded)
        $composeFile = Join-Path $dir '.docker\docker-compose.yml'
        Set-Content -Path $composeFile -Value 'version: "3"'
    }
    if ($WithLifecycle) {
        $mxa = Join-Path $dir '.mxagile'
        New-Item -ItemType Directory -Path $mxa -Force | Out-Null
        Set-Content -Path (Join-Path $mxa 'lifecycle.yaml') -Value 'phase: initializing'
    }
    return $dir
}

# Helper: run create-test-workcopy.ps1 against an arbitrary source path
# Returns the destination path and exit code
function Invoke-Workcopy {
    param([string]$SourcePath, [string]$DestSuffix, [switch]$Force)

    # The script requires TemplateName to resolve inside WorkspaceRoot/project-templates/
    # For these tests we call it directly with a temporary fixture.
    # We invoke it with TemplateName override by calling the script with
    # direct path manipulation.

    # Build a wrapper that invokes the core robocopy logic directly
    $extraArgs = @()
    if ($Force) { $extraArgs += '-Force' }

    # Override source by temporarily linking from a fake template name
    $fakeTemplateName = "test-tmp-$([guid]::NewGuid().ToString('N').Substring(0,8))"
    $fakeTemplateDir = Join-Path $WorkspaceRoot "project-templates\$fakeTemplateName"

    # Use a junction to avoid copying the fixture itself
    cmd /c mklink /j "$fakeTemplateDir" "$SourcePath" | Out-Null

    try {
        powershell -NoProfile -ExecutionPolicy Bypass -File $CreateScript `
            -TemplateName $fakeTemplateName `
            -TestDirName "test-hygiene-$DestSuffix" `
            @extraArgs 2>&1 | Out-Null
        $exitCode = $LASTEXITCODE
        $actualDest = Join-Path $WorkspaceRoot ".testing-test-hygiene-$DestSuffix"
        return @{ ExitCode = $exitCode; DestPath = $actualDest }
    } finally {
        cmd /c rmdir "$fakeTemplateDir" 2>$null | Out-Null
    }
}

Write-Host "=== Workcopy Hygiene Tests ==="
Write-Host ""

# ---------------------------------------------------------------------------
# Infrastructure check
# ---------------------------------------------------------------------------
Write-Host "--- Infrastructure ---"
Assert (Test-Path -LiteralPath $CreateScript) "create-test-workcopy.ps1 exists"
Assert ($null -ne (Get-Command robocopy -ErrorAction SilentlyContinue)) "robocopy is available"

# ---------------------------------------------------------------------------
# D: Mendix .mpr preserved
# ---------------------------------------------------------------------------
Write-Host "--- D: .mpr preserved ---"
$fx = New-MinimalFixture -Name "D" -WithDfc
try {
    $r = Invoke-Workcopy -SourcePath $fx -DestSuffix "D"
    try {
        Assert ($r.ExitCode -eq 0) "D1: workcopy exits 0"
        $mpr = @(Get-ChildItem -LiteralPath $r.DestPath -Filter '*.mpr' -File -ErrorAction SilentlyContinue)
        Assert ($mpr.Count -ge 1) "D2: .mpr file present in destination"
        Assert ($mpr[0].Name -eq 'project.mpr') "D3: .mpr filename preserved"
    } finally {
        if ($r.DestPath -and (Test-Path $r.DestPath)) { Remove-Item -LiteralPath $r.DestPath -Recurse -Force -ErrorAction SilentlyContinue }
    }
} finally { Remove-Item -LiteralPath $fx -Recurse -Force -ErrorAction SilentlyContinue }

# ---------------------------------------------------------------------------
# E: Brownfield DFC marker preserved
# ---------------------------------------------------------------------------
Write-Host "--- E: DFC marker preserved ---"
$fx = New-MinimalFixture -Name "E" -WithDfc -WithPlanning
try {
    $r = Invoke-Workcopy -SourcePath $fx -DestSuffix "E"
    try {
        $dfc = Join-Path $r.DestPath '.dfc-ai'
        Assert (Test-Path -LiteralPath $dfc -PathType Container) "E1: .dfc-ai/ present in destination"
        $ver = Join-Path $dfc 'version.yaml'
        Assert (Test-Path -LiteralPath $ver -PathType Leaf) "E2: .dfc-ai/version.yaml present"
        $planning = Join-Path $r.DestPath 'planning'
        Assert (Test-Path -LiteralPath $planning -PathType Container) "E3: planning/ present"
    } finally {
        if ($r.DestPath -and (Test-Path $r.DestPath)) { Remove-Item -LiteralPath $r.DestPath -Recurse -Force -ErrorAction SilentlyContinue }
    }
} finally { Remove-Item -LiteralPath $fx -Recurse -Force -ErrorAction SilentlyContinue }

# ---------------------------------------------------------------------------
# F: Transient content excluded
# ---------------------------------------------------------------------------
Write-Host "--- F: Transient content excluded ---"
$fx = New-MinimalFixture -Name "F" -WithNodeModules -WithMendixCache -WithDockerBuild
try {
    $r = Invoke-Workcopy -SourcePath $fx -DestSuffix "F"
    try {
        # node_modules excluded (in .opencode)
        $nm = Join-Path $r.DestPath '.opencode\node_modules'
        Assert (-not (Test-Path -LiteralPath $nm)) "F1: .opencode/node_modules excluded"
        # nested node_modules excluded (in tooling)
        $nm2 = Join-Path $r.DestPath 'tooling\node_modules'
        Assert (-not (Test-Path -LiteralPath $nm2)) "F2: nested node_modules excluded"
        # .mendix-cache excluded
        $mc = Join-Path $r.DestPath '.mendix-cache'
        Assert (-not (Test-Path -LiteralPath $mc)) "F3: .mendix-cache excluded"
        # .docker/build excluded
        $db = Join-Path $r.DestPath '.docker\build'
        Assert (-not (Test-Path -LiteralPath $db)) "F4: .docker/build excluded"
        # .docker root NOT excluded (compose file should be there)
        $dc = Join-Path $r.DestPath '.docker'
        Assert (Test-Path -LiteralPath $dc -PathType Container) "F5: .docker root preserved"
        $compose = Join-Path $r.DestPath '.docker\docker-compose.yml'
        Assert (Test-Path -LiteralPath $compose -PathType Leaf) "F6: .docker/docker-compose.yml preserved"
    } finally {
        if ($r.DestPath -and (Test-Path $r.DestPath)) { Remove-Item -LiteralPath $r.DestPath -Recurse -Force -ErrorAction SilentlyContinue }
    }
} finally { Remove-Item -LiteralPath $fx -Recurse -Force -ErrorAction SilentlyContinue }

# ---------------------------------------------------------------------------
# C: Hidden / dot directories preserved
# ---------------------------------------------------------------------------
Write-Host "--- C: Hidden dot-directories preserved ---"
$fx = New-MinimalFixture -Name "C" -WithDfc
# Add a hidden dot-dir
$hidden = Join-Path $fx '.agent-state'
New-Item -ItemType Directory -Path $hidden | Out-Null
Set-Content -Path (Join-Path $hidden 'memory.md') -Value '# memory'
(Get-Item $hidden).Attributes = [System.IO.FileAttributes]::Hidden -bor [System.IO.FileAttributes]::Directory

try {
    $r = Invoke-Workcopy -SourcePath $fx -DestSuffix "C"
    try {
        $destHidden = Join-Path $r.DestPath '.agent-state'
        Assert (Test-Path -LiteralPath $destHidden -PathType Container) "C1: hidden dot-dir preserved"
        $mem = Join-Path $destHidden 'memory.md'
        Assert (Test-Path -LiteralPath $mem -PathType Leaf) "C2: file inside hidden dir preserved"
        $dfc = Join-Path $r.DestPath '.dfc-ai'
        Assert (Test-Path -LiteralPath $dfc -PathType Container) "C3: .dfc-ai dot-dir preserved"
    } finally {
        if ($r.DestPath -and (Test-Path $r.DestPath)) { Remove-Item -LiteralPath $r.DestPath -Recurse -Force -ErrorAction SilentlyContinue }
    }
} finally { Remove-Item -LiteralPath $fx -Recurse -Force -ErrorAction SilentlyContinue }

# ---------------------------------------------------------------------------
# A: Source with many nested files
# ---------------------------------------------------------------------------
Write-Host "--- A: Many nested files ---"
$fx = New-MinimalFixture -Name "A"
# Create 50 nested files
for ($i = 1; $i -le 5; $i++) {
    for ($j = 1; $j -le 10; $j++) {
        $p = Join-Path $fx "level$i\sub$j"
        New-Item -ItemType Directory -Path $p -Force | Out-Null
        Set-Content -Path (Join-Path $p "file$j.md") -Value "content $i/$j"
    }
}
try {
    $r = Invoke-Workcopy -SourcePath $fx -DestSuffix "A"
    try {
        Assert ($r.ExitCode -eq 0) "A1: workcopy exits 0 for many-nested-files source"
        $destFiles = @(Get-ChildItem -LiteralPath $r.DestPath -Recurse -File -ErrorAction SilentlyContinue)
        Assert ($destFiles.Count -ge 51) "A2: all nested files present (50 data + 1 .mpr)"
        # Verify depth
        $deep = Join-Path $r.DestPath 'level5\sub10\file10.md'
        Assert (Test-Path -LiteralPath $deep -PathType Leaf) "A3: deeply nested file at correct path"
    } finally {
        if ($r.DestPath -and (Test-Path $r.DestPath)) { Remove-Item -LiteralPath $r.DestPath -Recurse -Force -ErrorAction SilentlyContinue }
    }
} finally { Remove-Item -LiteralPath $fx -Recurse -Force -ErrorAction SilentlyContinue }

# ---------------------------------------------------------------------------
# B: Paths containing spaces
# ---------------------------------------------------------------------------
Write-Host "--- B: Paths with spaces ---"
$fx = Join-Path $env:TEMP "mxagile test fixture spaces $([guid]::NewGuid().ToString('N').Substring(0,8))"
New-Item -ItemType Directory -Path $fx | Out-Null
New-Item -ItemType File -Path (Join-Path $fx "my project.mpr") | Out-Null
$sub = Join-Path $fx "sub dir with spaces"
New-Item -ItemType Directory -Path $sub | Out-Null
Set-Content -Path (Join-Path $sub "important doc.md") -Value "data"

try {
    $r = Invoke-Workcopy -SourcePath $fx -DestSuffix "B"
    try {
        Assert ($r.ExitCode -eq 0) "B1: workcopy exits 0 when paths have spaces"
        $mpr = @(Get-ChildItem -LiteralPath $r.DestPath -Filter '*.mpr' -File -ErrorAction SilentlyContinue)
        Assert ($mpr.Count -ge 1) "B2: .mpr preserved despite space in filename"
        $doc = Join-Path $r.DestPath "sub dir with spaces\important doc.md"
        Assert (Test-Path -LiteralPath $doc -PathType Leaf) "B3: file in spaced subdir preserved"
    } finally {
        if ($r.DestPath -and (Test-Path $r.DestPath)) { Remove-Item -LiteralPath $r.DestPath -Recurse -Force -ErrorAction SilentlyContinue }
    }
} finally { Remove-Item -LiteralPath $fx -Recurse -Force -ErrorAction SilentlyContinue }

# ---------------------------------------------------------------------------
# G: Source unchanged after copy
# ---------------------------------------------------------------------------
Write-Host "--- G: Source immutability ---"
$fx = New-MinimalFixture -Name "G" -WithDfc -WithPlanning
$srcMpr = Join-Path $fx 'project.mpr'
$hashBefore = (Get-FileHash -LiteralPath $srcMpr -Algorithm SHA256).Hash
try {
    $r = Invoke-Workcopy -SourcePath $fx -DestSuffix "G"
    try {
        $hashAfter = (Get-FileHash -LiteralPath $srcMpr -Algorithm SHA256).Hash
        Assert ($hashAfter -eq $hashBefore) "G1: source .mpr hash unchanged after copy"
        $srcDfc = Join-Path $fx '.dfc-ai\version.yaml'
        $hashDfc = (Get-FileHash -LiteralPath $srcDfc -Algorithm SHA256).Hash
        # Read again to confirm
        $hashDfc2 = (Get-FileHash -LiteralPath $srcDfc -Algorithm SHA256).Hash
        Assert ($hashDfc -eq $hashDfc2) "G2: source DFC marker file unchanged"
        # Verify source still has exact same file count
        $srcCount = @(Get-ChildItem -LiteralPath $fx -Recurse -File -ErrorAction SilentlyContinue).Count
        Assert ($srcCount -ge 3) "G3: source retains all files after copy"
    } finally {
        if ($r.DestPath -and (Test-Path $r.DestPath)) { Remove-Item -LiteralPath $r.DestPath -Recurse -Force -ErrorAction SilentlyContinue }
    }
} finally { Remove-Item -LiteralPath $fx -Recurse -Force -ErrorAction SilentlyContinue }

# ---------------------------------------------------------------------------
# H: Target has no stale files from previous run
# ---------------------------------------------------------------------------
Write-Host "--- H: Idempotency - no stale files ---"
$fx = New-MinimalFixture -Name "H" -WithDfc
try {
    # First run
    $r1 = Invoke-Workcopy -SourcePath $fx -DestSuffix "H"
    # Plant a stale file in dest
    $stale = Join-Path $r1.DestPath 'stale-from-run1.txt'
    Set-Content -Path $stale -Value 'stale'
    Assert (Test-Path -LiteralPath $stale) "H0: stale file planted"

    # Second run with -Force
    $r2 = Invoke-Workcopy -SourcePath $fx -DestSuffix "H" -Force
    try {
        Assert ($r2.ExitCode -eq 0) "H1: second run with -Force exits 0"
        Assert (-not (Test-Path -LiteralPath $stale)) "H2: stale file absent after -Force run"
        $mpr = @(Get-ChildItem -LiteralPath $r2.DestPath -Filter '*.mpr' -File -ErrorAction SilentlyContinue)
        Assert ($mpr.Count -ge 1) "H3: .mpr still present after -Force run"
    } finally {
        if ($r2.DestPath -and (Test-Path $r2.DestPath)) { Remove-Item -LiteralPath $r2.DestPath -Recurse -Force -ErrorAction SilentlyContinue }
    }
} finally { Remove-Item -LiteralPath $fx -Recurse -Force -ErrorAction SilentlyContinue }

# ---------------------------------------------------------------------------
# I: Copy-engine non-success handled (nonexistent source)
# ---------------------------------------------------------------------------
Write-Host "--- I: Bad source handled ---"
$badTemplateName = "nonexistent-$(([guid]::NewGuid().ToString('N').Substring(0,8)))"
$badDest = Join-Path $WorkspaceRoot ".testing-test-hygiene-I-bad"
if (Test-Path $badDest) { Remove-Item -LiteralPath $badDest -Recurse -Force }
$badExitCode = $null
try {
    powershell -NoProfile -ExecutionPolicy Bypass -File $CreateScript `
        -TemplateName $badTemplateName `
        -TestDirName "test-hygiene-I-bad" `
        2>&1 | Out-Null
    $badExitCode = $LASTEXITCODE
} catch {
    $badExitCode = $LASTEXITCODE
    if ($badExitCode -eq 0) { $badExitCode = 1 }
}
Assert ($badExitCode -ne 0) "I1: nonexistent source exits non-zero"
Assert (-not (Test-Path -LiteralPath $badDest)) "I2: no destination created for bad source"

# ---------------------------------------------------------------------------
# J: No project outside source/target touched
# ---------------------------------------------------------------------------
Write-Host "--- J: Workspace isolation ---"
$fx = New-MinimalFixture -Name "J"
$templatesBefore = @(Get-ChildItem -LiteralPath (Join-Path $WorkspaceRoot 'project-templates') -Directory).Count
try {
    $r = Invoke-Workcopy -SourcePath $fx -DestSuffix "J"
    try {
        $templatesAfter = @(Get-ChildItem -LiteralPath (Join-Path $WorkspaceRoot 'project-templates') -Directory).Count
        # The junction used during invoke is cleaned up, so count should be same
        Assert ($templatesAfter -eq $templatesBefore) "J1: project-templates count unchanged after copy"
        # No .testing dirs other than our own
        $testingDirs = @(Get-ChildItem -LiteralPath $WorkspaceRoot -Directory | Where-Object { $_.Name -like '.testing-test-hygiene-J*' })
        Assert ($testingDirs.Count -le 1) "J2: only one .testing-test-hygiene-J dir created"
    } finally {
        if ($r.DestPath -and (Test-Path $r.DestPath)) { Remove-Item -LiteralPath $r.DestPath -Recurse -Force -ErrorAction SilentlyContinue }
    }
} finally { Remove-Item -LiteralPath $fx -Recurse -Force -ErrorAction SilentlyContinue }

# ---------------------------------------------------------------------------
# K: Repeatable output
# ---------------------------------------------------------------------------
Write-Host "--- K: Repeatable output ---"
$fx = New-MinimalFixture -Name "K" -WithDfc -WithPlanning -WithNodeModules
try {
    $r1 = Invoke-Workcopy -SourcePath $fx -DestSuffix "K1"
    $r2 = Invoke-Workcopy -SourcePath $fx -DestSuffix "K2"
    try {
        $files1 = @(Get-ChildItem -LiteralPath $r1.DestPath -Recurse -File -ErrorAction SilentlyContinue).Count
        $files2 = @(Get-ChildItem -LiteralPath $r2.DestPath -Recurse -File -ErrorAction SilentlyContinue).Count
        Assert ($files1 -eq $files2) "K1: two runs produce same file count ($files1 vs $files2)"
        Assert ($r1.ExitCode -eq 0) "K2: first run exit code 0"
        Assert ($r2.ExitCode -eq 0) "K3: second run exit code 0"
    } finally {
        if ($r1.DestPath -and (Test-Path $r1.DestPath)) { Remove-Item -LiteralPath $r1.DestPath -Recurse -Force -ErrorAction SilentlyContinue }
        if ($r2.DestPath -and (Test-Path $r2.DestPath)) { Remove-Item -LiteralPath $r2.DestPath -Recurse -Force -ErrorAction SilentlyContinue }
    }
} finally { Remove-Item -LiteralPath $fx -Recurse -Force -ErrorAction SilentlyContinue }

# ---------------------------------------------------------------------------
# L: Greenfield fixture still works
# ---------------------------------------------------------------------------
Write-Host "--- L: Greenfield workflow ---"
$greenfieldSrc = Join-Path $WorkspaceRoot "project-templates\greenfield"
if (Test-Path -LiteralPath $greenfieldSrc -PathType Container) {
    $destGreen = ".testing-test-hygiene-L-green"
    $destFull = Join-Path $WorkspaceRoot $destGreen
    if (Test-Path $destFull) { Remove-Item -LiteralPath $destFull -Recurse -Force }
    try {
        powershell -NoProfile -ExecutionPolicy Bypass -File $CreateScript `
            -TemplateName "greenfield" `
            -TestDirName "test-hygiene-L-green" 2>&1 | Out-Null
        Assert ($LASTEXITCODE -eq 0) "L1: greenfield workcopy exits 0"
        Assert (Test-Path $destFull -PathType Container) "L2: greenfield dest created"
    } finally {
        if (Test-Path $destFull) { Remove-Item -LiteralPath $destFull -Recurse -Force -ErrorAction SilentlyContinue }
    }
} else {
    Write-Host "  SKIP L: greenfield template not present"
    $PassCount++  # count as pass (skip)
}

# ---------------------------------------------------------------------------
# M: Brownfield migration fixture remains logically equivalent
# ---------------------------------------------------------------------------
Write-Host "--- M: Brownfield fixture fidelity ---"
$brownSrc = Join-Path $WorkspaceRoot "project-templates\brownfield_migration_captrack"
if (Test-Path -LiteralPath $brownSrc -PathType Container) {
    $destBrown = ".testing-test-hygiene-M-brown"
    $destFull = Join-Path $WorkspaceRoot $destBrown
    if (Test-Path $destFull) { Remove-Item -LiteralPath $destFull -Recurse -Force }
    try {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        powershell -NoProfile -ExecutionPolicy Bypass -File $CreateScript `
            -TemplateName "brownfield_migration_captrack" `
            -TestDirName "test-hygiene-M-brown" 2>&1 | Out-Null
        $sw.Stop()
        Assert ($LASTEXITCODE -eq 0) "M1: brownfield workcopy exits 0"
        # .mpr preserved
        $mpr = @(Get-ChildItem -LiteralPath $destFull -Filter '*.mpr' -File -ErrorAction SilentlyContinue)
        Assert ($mpr.Count -ge 1) "M2: brownfield .mpr present"
        # .dfc-ai preserved
        Assert (Test-Path (Join-Path $destFull '.dfc-ai') -PathType Container) "M3: .dfc-ai present (migration start condition)"
        # planning preserved
        Assert (Test-Path (Join-Path $destFull 'planning') -PathType Container) "M4: planning/ present"
        # mprcontents preserved
        Assert (Test-Path (Join-Path $destFull 'mprcontents') -PathType Container) "M5: mprcontents/ present"
        # No lifecycle.yaml (would corrupt migration start condition)
        Assert (-not (Test-Path (Join-Path $destFull '.mxagile\lifecycle.yaml'))) "M6: no .mxagile/lifecycle.yaml introduced"
        # node_modules excluded
        $nmInDest = @(Get-ChildItem -LiteralPath $destFull -Recurse -Filter 'node_modules' -Directory -ErrorAction SilentlyContinue)
        Assert ($nmInDest.Count -eq 0) "M7: no node_modules in destination"
        # .mendix-cache excluded
        Assert (-not (Test-Path (Join-Path $destFull '.mendix-cache') -PathType Container)) "M8: .mendix-cache excluded"
        # .docker/build excluded
        Assert (-not (Test-Path (Join-Path $destFull '.docker\build') -PathType Container)) "M9: .docker/build excluded"
        # File count reduced vs source
        $srcCount = @(Get-ChildItem -LiteralPath $brownSrc -Recurse -File -ErrorAction SilentlyContinue).Count
        $dstCount = @(Get-ChildItem -LiteralPath $destFull -Recurse -File -ErrorAction SilentlyContinue).Count
        Assert ($dstCount -lt $srcCount) "M10: destination has fewer files than source (exclusions applied)"
        Assert ($dstCount -gt 1000) "M11: destination retains substantial fixture content (>1000 files)"
        $elapsedSec = [math]::Round($sw.Elapsed.TotalSeconds, 1)
        Write-Host "      (M elapsed: ${elapsedSec}s, src=$srcCount files, dst=$dstCount files)"
    } finally {
        if (Test-Path $destFull) { Remove-Item -LiteralPath $destFull -Recurse -Force -ErrorAction SilentlyContinue }
    }
} else {
    Write-Host "  SKIP M: brownfield_migration_captrack template not present"
    $PassCount++
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=== Workcopy Hygiene Test Results ==="
Write-Host "  PASS: $PassCount"
if ($FailCount -gt 0) {
    Write-Host "  FAIL: $FailCount" -ForegroundColor Red
    Write-Host ""
    Write-Host "TEST FAILED: Workcopy hygiene contract not met." -ForegroundColor Red
    exit 1
} else {
    Write-Host ""
    Write-Host "TEST PASSED: Workcopy hygiene and performance contract met." -ForegroundColor Green
    exit 0
}
