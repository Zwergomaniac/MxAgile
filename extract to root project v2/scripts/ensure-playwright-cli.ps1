[CmdletBinding()]
param(
    [string]$Version = '0.1.15',
    [string]$ConfigPath = (Join-Path (Split-Path -Parent $PSScriptRoot) '.playwright\cli.config.json')
)

$ErrorActionPreference = 'Stop'

function Find-CommandPath([string[]]$Names) {
    foreach ($name in $Names) {
        $command = Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($command) { return $command.Source }
    }
    return $null
}

$node = Find-CommandPath @('node', 'nodejs')
$npm = Find-CommandPath @('npm.cmd', 'npm')
if (-not $node) { throw 'Node.js was not found. Install Node.js 22+ or open the project devcontainer.' }
if (-not $npm) { throw 'npm was not found. Install npm with Node.js or open the project devcontainer.' }

$playwright = Find-CommandPath @('playwright-cli', 'playwright-cli.cmd')
if (-not $playwright) {
    & $npm install --global "@playwright/cli@$Version"
    if ($LASTEXITCODE -ne 0) { throw 'Could not install @playwright/cli.' }
    $playwright = Find-CommandPath @('playwright-cli', 'playwright-cli.cmd')
}
if (-not $playwright) { throw 'playwright-cli is still not available after installation.' }

$bashCandidates = @(
    (Join-Path $env:ProgramFiles 'Git\bin\bash.exe'),
    (Join-Path $env:ProgramFiles 'Git\usr\bin\bash.exe'),
    (Join-Path $env:LOCALAPPDATA 'Programs\Git\bin\bash.exe')
)
$bashPath = $bashCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($bashPath) {
    $env:PATH = "$(Split-Path -Parent $bashPath);$env:PATH"
} elseif (-not (Find-CommandPath @('bash'))) {
    throw 'Bash was not found. Install Git for Windows or open the project devcontainer.'
}

$npmRoot = (& $npm root --global).Trim()
$core = Join-Path $npmRoot "@playwright\cli\node_modules\playwright-core\cli.js"
if (-not (Test-Path $core)) { throw "Bundled playwright-core was not found at '$core'." }

$browserCandidates = @(
    (Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe'),
    (Join-Path ${env:ProgramFiles(x86)} 'Google\Chrome\Application\chrome.exe'),
    (Join-Path $env:LOCALAPPDATA 'Google\Chrome\Application\chrome.exe'),
    (Join-Path $env:ProgramFiles 'Microsoft\Edge\Application\msedge.exe')
)
$browserPath = $browserCandidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $browserPath) {
    & $node $core install chromium chromium-headless-shell
    if ($LASTEXITCODE -ne 0) {
        throw 'Could not install Chromium and no local Chrome/Edge executable was found. Check the TLS certificate chain or open the project devcontainer.'
    }
}

if (Test-Path $ConfigPath) {
    $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
    if ($config.browser.launchOptions.PSObject.Properties.Name -contains 'executablePath') {
        $path = [string]$config.browser.launchOptions.executablePath
        if (-not (Test-Path $path)) {
            $config.browser.launchOptions.PSObject.Properties.Remove('executablePath')
        }
    }
    if ($browserPath) {
        if ($config.browser.launchOptions.PSObject.Properties.Name -contains 'executablePath') {
            $config.browser.launchOptions.executablePath = $browserPath
        } else {
            $config.browser.launchOptions | Add-Member -NotePropertyName executablePath -NotePropertyValue $browserPath
        }
    }
    $config | ConvertTo-Json -Depth 10 | Set-Content $ConfigPath -Encoding utf8
}

Write-Output "playwright-cli ready: $playwright"
Write-Output "playwright-core ready: $core"
Write-Output 'Chromium browser binaries ready.'
