<##
.SYNOPSIS
Runs the Mendix app in a disposable MPR-v2 copy for Docker and Playwright testing.

.DESCRIPTION
Keeps the canonical working copy untouched. The copy is created from HEAD under
.concord/scratch, and the Docker pre-build consistency check is skipped because it
materializes the project's MPR-v2 checkout.
##>

[CmdletBinding()]
param(
    [int]$PortOffset = 10,
    [switch]$Fresh
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$projectName = '*.mpr'
$scratchRoot = Join-Path $projectRoot '.concord\scratch'
$runId = (Get-Date).ToString('yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
$runRoot = Join-Path $scratchRoot "docker-mpr-v2-run-$runId"
$seedPath = Join-Path $runRoot 'mdlsource\docker-test-bootstrap-user.mdl'
$credentialPath = Join-Path $scratchRoot 'docker-test-credentials.json'
# MXCLI_PATH erlaubt eine Installation ausserhalb des PATH; sonst gilt der PATH-Eintrag.
$mxcli = if ($env:MXCLI_PATH -and (Test-Path $env:MXCLI_PATH)) {
    $env:MXCLI_PATH
} else {
    (Get-Command mxcli -ErrorAction Stop).Source
}
$composeProject = $null
$composePath = $null

function Remove-IsolatedStack {
    if ($composeProject -and $composePath -and (Test-Path $composePath)) {
        & docker compose -p $composeProject -f $composePath down --volumes --remove-orphans | Out-Host
    }
}

trap {
    Remove-IsolatedStack
    break
}

if (Get-Process studiopro -ErrorAction SilentlyContinue) {
    throw 'Studio Pro must be closed before starting the isolated Docker test.'
}

$projectSource = @(Get-ChildItem $projectRoot -File -Filter $projectName)
if ($projectSource.Count -ne 1) {
    throw "Expected exactly one .mpr file in '$projectRoot'."
}

New-Item -ItemType Directory -Force $scratchRoot | Out-Null
New-Item -ItemType Directory -Force $runRoot | Out-Null

git archive HEAD | tar -xf - -C $runRoot

$projectPath = Join-Path $runRoot $projectSource[0].Name
if (-not (Test-Path $projectPath -PathType Leaf)) {
    throw "The committed project model '$($projectSource[0].Name)' was not found in the isolated copy."
}

$beforeBytes = (Get-Item $projectPath).Length
$beforeUnits = @(Get-ChildItem (Join-Path $runRoot 'mprcontents') -Recurse -File -Filter '*.mxunit').Count
$testUser = @{ username = "mx_test_admin_$([guid]::NewGuid().ToString('N').Substring(0, 12))"; role = 'Administrator' }
$randomPart = ([Convert]::ToHexString([Security.Cryptography.RandomNumberGenerator]::GetBytes(24))).ToLowerInvariant()
$testUser.password = "A${randomPart}z9!"
$seedContent = @"
/**
 * Temporary administrator login user for the isolated Docker and browser smoke test.
 * The application-side demo-user switcher is tested after this login.
 */
CREATE DEMO USER '$($testUser.username)' PASSWORD '$($testUser.password)' ($($testUser.role));
"@
Set-Content -Path $seedPath -Value $seedContent -Encoding utf8
& $mxcli check $seedPath -p $projectPath --references
if ($LASTEXITCODE -ne 0) { throw 'The temporary Docker test-user seed did not pass MDL validation.' }
& $mxcli exec $seedPath -p $projectPath
if ($LASTEXITCODE -ne 0) { throw 'The temporary Docker test-user seed could not be executed.' }
@{ user = $testUser } | ConvertTo-Json | Set-Content -Path $credentialPath -Encoding utf8

& $mxcli docker build -p $projectPath --skip-check
if ($LASTEXITCODE -ne 0) { throw 'The isolated PAD build failed.' }
& $mxcli docker init -p $projectPath --force --port-offset $PortOffset
if ($LASTEXITCODE -ne 0) { throw 'The isolated Docker stack could not be initialized.' }

$composePath = Join-Path $runRoot '.docker\docker-compose.yml'
$composeContent = Get-Content $composePath -Raw
$composeContent = $composeContent -replace '(?m)^\s*test: \["CMD-SHELL", "code=.*"\]', '      test: ["CMD", "curl", "-f", "http://localhost:8090/probes/ready"]'
Set-Content -Path $composePath -Value $composeContent -Encoding utf8

$composeProject = "mx-test-$runId".ToLowerInvariant()
$requestedOffset = $PortOffset
while ($true) {
    $appPort = 8080 + $requestedOffset
    $adminPort = 8090 + $requestedOffset
    $dbPort = 5432 + $requestedOffset
    $portsInUse = @($appPort, $adminPort, $dbPort) | Where-Object {
        Test-NetConnection -ComputerName localhost -Port $_ -InformationLevel Quiet
    }
    if (-not $portsInUse) { break }
    Write-Host "Ports $($portsInUse -join ', ') are already in use; trying the next offset."
    $requestedOffset++
    if ($requestedOffset -gt $PortOffset + 100) { throw 'Could not find a free application port.' }
}
if ($requestedOffset -ne $PortOffset) {
    & $mxcli docker init -p $projectPath --force --port-offset $requestedOffset
    if ($LASTEXITCODE -ne 0) { throw 'The isolated Docker stack could not be reinitialized with a free port.' }
    $composeContent = Get-Content $composePath -Raw
    $composeContent = $composeContent -replace '(?m)^\s*test: \["CMD-SHELL", "code=.*"\]', '      test: ["CMD", "curl", "-f", "http://localhost:8090/probes/ready"]'
    Set-Content -Path $composePath -Value $composeContent -Encoding utf8
}
$effectivePortOffset = $requestedOffset
$composeArguments = @('-p', $composeProject, '-f', $composePath, 'up', '-d', '--wait')
if ($Fresh) {
    & docker compose @('-p', $composeProject, '-f', $composePath, 'down', '--volumes', '--remove-orphans')
}
& docker compose @composeArguments
if ($LASTEXITCODE -ne 0) { throw 'The isolated Docker stack did not become ready.' }

$env:MENDIX_BOOTSTRAP_USERNAME = $testUser.username
$env:MENDIX_BOOTSTRAP_PASSWORD = $testUser.password
$env:PLAYWRIGHT_BASE_URL = "http://localhost:$($effectivePortOffset + 8080)"
$testScript = Join-Path $projectRoot 'tests\verify-demo-user-switcher.test.sh'
$gitBash = @(
    (Join-Path $env:ProgramFiles 'Git\bin\bash.exe'),
    (Join-Path $env:ProgramFiles 'Git\usr\bin\bash.exe'),
    (Join-Path $env:LOCALAPPDATA 'Programs\Git\bin\bash.exe')
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($gitBash) {
    $unixProjectRoot = (& $gitBash -lc "cd '$projectRoot' && pwd").Trim()
    & $gitBash -lc "cd '$unixProjectRoot' && ./tests/verify-demo-user-switcher.test.sh"
} else {
    & $mxcli playwright verify $testScript --base-url $env:PLAYWRIGHT_BASE_URL --verbose
}
if ($LASTEXITCODE -ne 0) { throw 'The demo-user switcher Playwright test failed.' }

Write-Host "Isolated Docker project: $projectPath"
Write-Host "Application URL: http://localhost:$($effectivePortOffset + 8080)"
Write-Host "Before: MPR $beforeBytes bytes; mxunit files $beforeUnits"
Write-Host "Notice: Docker's standard pre-build consistency check is intentionally overridden with --skip-check for MPR-v2 safety."

$exitCode = 0
$afterBytes = (Get-Item $projectPath).Length
$afterUnits = @(Get-ChildItem (Join-Path $runRoot 'mprcontents') -Recurse -File -Filter '*.mxunit' -ErrorAction SilentlyContinue).Count
Write-Host "After: MPR $afterBytes bytes; mxunit files $afterUnits"

if ($afterBytes -gt 5MB -or $afterUnits -eq 0) {
    Write-Error 'The disposable Docker copy was materialized or lost its MPR-v2 contents. The canonical checkout was not changed.'
    exit 2
}

Remove-IsolatedStack
exit $exitCode