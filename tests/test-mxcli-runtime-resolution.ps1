$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$TestsDir = $PSScriptRoot
$ScriptDir = Split-Path -Parent $TestsDir
$Resolver = Join-Path $ScriptDir 'scripts/Resolve-MxAgileMxcli.ps1'
$InstallCore = Join-Path $ScriptDir 'scripts/install-core.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("mxagile-mxcli-resolution-" + [guid]::NewGuid().ToString('N'))
$projectRoot = Join-Path $tempRoot 'project'
$pathRoot = Join-Path $tempRoot 'path'
$previousPath = $env:PATH
$passCount = 0
$failCount = 0

function Assert-True {
    param([string]$Name, [bool]$Condition)
    if ($Condition) {
        Write-Host "  PASS: $Name" -ForegroundColor Green
        $script:passCount++
    } else {
        Write-Host "  FAIL: $Name" -ForegroundColor Red
        $script:failCount++
    }
}

function New-FakeBinary {
    param([string]$Path, [string]$Content)
    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    Set-Content -LiteralPath $Path -Value $Content -Encoding ASCII
}

try {
    New-Item -ItemType Directory -Path $projectRoot, $pathRoot -Force | Out-Null
    $binaryName = if ([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
        [System.Runtime.InteropServices.OSPlatform]::Windows
    )) { 'mxcli.exe' } else { 'mxcli' }
    $pathBinary = Join-Path $pathRoot $binaryName
    $localBinary = Join-Path $projectRoot $binaryName
    $env:PATH = "$pathRoot$([System.IO.Path]::PathSeparator)$previousPath"
    New-FakeBinary -Path $pathBinary -Content 'PATH-BINARY-MUST-NOT-RUN'
    New-FakeBinary -Path $localBinary -Content 'PROJECT-BINARY-MUST-NOT-RUN'

    $resolved = (& $Resolver -ProjectRoot $projectRoot | ConvertFrom-Json)
    Assert-True 'T1 selects project-local binary ahead of PATH' (
        $resolved.source -eq 'PROJECT_LOCAL' -and
        [System.IO.Path]::GetFullPath($resolved.path) -eq [System.IO.Path]::GetFullPath($localBinary)
    )

    $declaredLocal = (& $Resolver -ProjectRoot $projectRoot -ConfiguredPath './mxcli' | ConvertFrom-Json)
    Assert-True 'Project-declared ./mxcli resolves to the local Windows executable' (
        $declaredLocal.source -eq 'PROJECT_DECLARED' -and
        [System.IO.Path]::GetFullPath($declaredLocal.path) -eq [System.IO.Path]::GetFullPath($localBinary)
    )

    Remove-Item -LiteralPath $localBinary -Force
    $missingBinaryBlocked = $false
    try {
        $null = & $Resolver -ProjectRoot $projectRoot
    } catch {
        $missingBinaryBlocked = $_.Exception.Message -match 'Project-local mxcli was not found'
    }
    Assert-True 'T2 missing project binary blocks instead of silently choosing PATH' $missingBinaryBlocked

    $fallback = (& $Resolver -ProjectRoot $projectRoot -AllowPathFallback | ConvertFrom-Json)
    Assert-True 'Explicit PATH fallback is identified and returns the PATH binary' (
        $fallback.source -eq 'PATH_EXPLICIT_FALLBACK' -and
        [System.IO.Path]::GetFullPath($fallback.path) -eq [System.IO.Path]::GetFullPath($pathBinary)
    )

    $configuredPath = Join-Path $projectRoot 'declared/tool.exe'
    New-FakeBinary -Path $configuredPath -Content 'DECLARED-BINARY-MUST-NOT-RUN'
    $declared = (& $Resolver -ProjectRoot $projectRoot -ConfiguredPath 'declared/tool.exe' | ConvertFrom-Json)
    Assert-True 'Declared project binary is selected ahead of PATH' (
        $declared.source -eq 'PROJECT_DECLARED' -and
        [System.IO.Path]::GetFullPath($declared.path) -eq [System.IO.Path]::GetFullPath($configuredPath)
    )

    $missingDeclaredBlocked = $false
    try {
        $null = & $Resolver -ProjectRoot $projectRoot -ConfiguredPath 'declared/missing.exe'
    } catch {
        $missingDeclaredBlocked = $_.Exception.Message -match 'PATH fallback is not permitted'
    }
    Assert-True 'Missing declared binary blocks without PATH substitution' $missingDeclaredBlocked

    $installerText = Get-Content -LiteralPath $InstallCore -Raw
    Assert-True 'Fresh install/update distributes the resolver into .mxagile/tools' (
        $installerText -match 'Resolve-MxAgileMxcli\.ps1' -and
        $installerText -match '\.mxagile/tools/Resolve-MxAgileMxcli\.ps1'
    )

    $conflictPolicy = Join-Path $ScriptDir '.mxagile/policies/tool-instruction-conflict.md'
    $profilePolicy = Join-Path $ScriptDir '.mxagile/policies/local-runtime-profile.md'
    Assert-True 'Conflict policy ranks project contracts and external skills' (
        (Get-Content -LiteralPath $conflictPolicy -Raw) -match 'project-owned configuration' -and
        (Get-Content -LiteralPath $conflictPolicy -Raw) -match 'External or tool-provided skills'
    )
    Assert-True 'Runtime profile requires exact binary version and command-specific help' (
        (Get-Content -LiteralPath $profilePolicy -Raw) -match 'absolute path and exact version' -and
        (Get-Content -LiteralPath $profilePolicy -Raw) -match 'command-specific `--help`'
    )
    $conflictText = Get-Content -LiteralPath $conflictPolicy -Raw
    Assert-True 'Unsupported syntax blocks instead of switching to a PATH binary' (
        $conflictText -match 'TOOL_CAPABILITY_GAP' -and
        $conflictText -match 'Do not substitute another PATH binary'
    )
    Assert-True 'Concord skills require current-session capability evidence' (
        $conflictText -match 'Concord / MCP' -and
        $conflictText -match 'active-session capability probe'
    )

    $generatedUiAgent = Join-Path $ScriptDir '.claude/agents/mxagile-ui-agent.md'
    $generatedAcceptanceAgent = Join-Path $ScriptDir '.claude/agents/mxagile-acceptance-agent.md'
    $generatedQualityGate = Join-Path $ScriptDir '.claude/skills/mxagile-quality-gate/SKILL.md'
    $generatedTestSkill = Join-Path $ScriptDir '.claude/skills/mxagile-test-generate/SKILL.md'
    $generatedSystemCheck = Join-Path $ScriptDir '.claude/skills/mxagile-system-check/SKILL.md'
    $generatedVisualSkill = Join-Path $ScriptDir '.claude/skills/mxagile-visual-verification/SKILL.md'
    Assert-True 'UI projection routes through project tool and identity contracts' (
        (Get-Content -LiteralPath $generatedUiAgent -Raw) -match 'tool-instruction-conflict\.md' -and
        (Get-Content -LiteralPath $generatedUiAgent -Raw) -match 'test-identity-lifecycle\.md'
    )
    Assert-True 'Acceptance projection routes through the tool conflict contract' (
        (Get-Content -LiteralPath $generatedAcceptanceAgent -Raw) -match 'tool-instruction-conflict\.md'
    )
    Assert-True 'Quality-gate and test-generation skills receive the resolver contract' (
        (Get-Content -LiteralPath $generatedQualityGate -Raw) -match 'tool-instruction-conflict\.md' -and
        (Get-Content -LiteralPath $generatedTestSkill -Raw) -match 'local-runtime-profile\.md'
    )
    Assert-True 'Quality gate resolves DB type and name before runtime start' (
        (Get-Content -LiteralPath $generatedQualityGate -Raw) -match 'local_runtime' -and
        (Get-Content -LiteralPath $generatedQualityGate -Raw) -match 'db_type' -and
        (Get-Content -LiteralPath $generatedQualityGate -Raw) -match 'db_name'
    )
    Assert-True 'System-check version probe uses the resolved absolute binary' (
        (Get-Content -LiteralPath $generatedSystemCheck -Raw) -match '\$mxcliPath --version' -and
        (Get-Content -LiteralPath $generatedSystemCheck -Raw) -match 'tool-instruction-conflict\.md'
    )
    Assert-True 'Generated UI agent requires fresh-full whole-screen runtime reconciliation' (
        (Get-Content -LiteralPath $generatedUiAgent -Raw) -match 'Fresh-Full-Abgleich' -and
        (Get-Content -LiteralPath $generatedUiAgent -Raw) -match 'Whole-Screen'
    )
    Assert-True 'Generated visual skill routes to canonical URL/origin contract' (
        (Get-Content -LiteralPath $generatedVisualSkill -Raw) -match 'Canonical Browser Target' -and
        (Get-Content -LiteralPath $generatedVisualSkill -Raw) -match 'allowedOrigins'
    )
} finally {
    $env:PATH = $previousPath
    if (Test-Path -LiteralPath $tempRoot -PathType Container) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}

Write-Host "RESULTS: $passCount passed, $failCount failed"
if ($failCount -gt 0) { exit 1 }