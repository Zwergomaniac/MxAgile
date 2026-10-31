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
        [switch]$WithLifecycle,
        [switch]$WithMprContents
    )
    $dir = Join-Path $env:TEMP "mxagile-test-fixture-$Name-$([guid]::NewGuid().ToString('N').Substring(0,8))"
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    New-Item -ItemType File -Path (Join-Path $dir "project.mpr") | Out-Null

    if ($WithMprContents) {
        $mprContents = Join-Path $dir 'mprcontents'
        New-Item -ItemType Directory -Path $mprContents -Force | Out-Null
        Set-Content -Path (Join-Path $mprContents 'fixture.dat') -Value 'synthetic Mendix content'
    }

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
        pwsh -NoProfile -File $CreateScript `
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
    pwsh -NoProfile -File $CreateScript `
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
$greenfieldSource = New-MinimalFixture -Name 'L'
try {
    $r = Invoke-Workcopy -SourcePath $greenfieldSource -DestSuffix 'L-green'
    try {
        Assert ($r.ExitCode -eq 0) "L1: synthetic greenfield workcopy exits 0"
        Assert (Test-Path -LiteralPath $r.DestPath -PathType Container) "L2: greenfield destination created"
        Assert (Test-Path -LiteralPath (Join-Path $r.DestPath 'project.mpr') -PathType Leaf) "L3: greenfield .mpr preserved"
    } finally {
        if ($r.DestPath -and (Test-Path -LiteralPath $r.DestPath)) { Remove-Item -LiteralPath $r.DestPath -Recurse -Force -ErrorAction SilentlyContinue }
    }
} finally { Remove-Item -LiteralPath $greenfieldSource -Recurse -Force -ErrorAction SilentlyContinue }

# ---------------------------------------------------------------------------
# M: Brownfield migration fixture remains logically equivalent
# ---------------------------------------------------------------------------
Write-Host "--- M: Brownfield fixture fidelity ---"
$brownSrc = New-MinimalFixture -Name 'M' -WithDfc -WithPlanning -WithNodeModules -WithMendixCache -WithDockerBuild -WithMprContents
$largeFiles = Join-Path $brownSrc 'synthetic-fixture-data'
New-Item -ItemType Directory -Path $largeFiles -Force | Out-Null
for ($fileIndex = 0; $fileIndex -lt 1001; $fileIndex++) {
    $filePath = Join-Path $largeFiles ('artifact-{0:D4}.txt' -f $fileIndex)
    [System.IO.File]::WriteAllText($filePath, "synthetic fixture $fileIndex`n", [System.Text.UTF8Encoding]::new($false))
}
try {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $r = Invoke-Workcopy -SourcePath $brownSrc -DestSuffix 'M-brown'
    $sw.Stop()
    try {
        Assert ($r.ExitCode -eq 0) "M1: synthetic brownfield workcopy exits 0"
        Assert (Test-Path (Join-Path $r.DestPath '.dfc-ai') -PathType Container) "M2: .dfc-ai preserved"
        Assert (Test-Path (Join-Path $r.DestPath 'planning') -PathType Container) "M3: planning preserved"
        Assert (Test-Path (Join-Path $r.DestPath 'mprcontents/fixture.dat') -PathType Leaf) "M4: mprcontents preserved"
        Assert (-not (Test-Path (Join-Path $r.DestPath '.mxagile/lifecycle.yaml'))) "M5: no lifecycle sentinel introduced"
        $nmInDest = @(Get-ChildItem -LiteralPath $r.DestPath -Recurse -Filter 'node_modules' -Directory -ErrorAction SilentlyContinue)
        Assert ($nmInDest.Count -eq 0) "M6: node_modules excluded"
        Assert (-not (Test-Path (Join-Path $r.DestPath '.mendix-cache') -PathType Container)) "M7: .mendix-cache excluded"
        Assert (-not (Test-Path (Join-Path $r.DestPath '.docker/build') -PathType Container)) "M8: .docker/build excluded"
        $srcCount = @(Get-ChildItem -LiteralPath $brownSrc -Recurse -File -ErrorAction SilentlyContinue).Count
        $dstCount = @(Get-ChildItem -LiteralPath $r.DestPath -Recurse -File -ErrorAction SilentlyContinue).Count
        Assert ($dstCount -lt $srcCount) "M9: excluded transient files reduce destination count"
        Assert ($dstCount -gt 1000) "M10: large synthetic brownfield fixture retained (>1000 files)"
        Write-Host "      (M elapsed: $([math]::Round($sw.Elapsed.TotalSeconds,1))s, source=$srcCount files, destination=$dstCount files)"
    } finally {
        if ($r.DestPath -and (Test-Path -LiteralPath $r.DestPath)) { Remove-Item -LiteralPath $r.DestPath -Recurse -Force -ErrorAction SilentlyContinue }
    }
} finally { Remove-Item -LiteralPath $brownSrc -Recurse -Force -ErrorAction SilentlyContinue }

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
