[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$configPath = Join-Path $projectRoot '.mcp.json'
if (-not (Test-Path $configPath -PathType Leaf)) { throw "MCP configuration not found: $configPath" }

$config = Get-Content $configPath -Raw | ConvertFrom-Json
$server = $config.mcpServers.'concord-v2-mcp'
if (-not $server) { throw "MCP server 'concord-v2-mcp' is missing from $configPath" }

foreach ($property in $server.env.PSObject.Properties) {
    Set-Item "Env:$($property.Name)" ([string]$property.Value)
}

& $server.command @($server.args)
exit $LASTEXITCODE
