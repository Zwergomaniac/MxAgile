function New-MxAgileBaselineFixture {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('greenfield', 'migration-in-progress', 'session-bootstrap')]
        [string]$Scenario
    )

    $fixtureRoot = Join-Path $env:TEMP "mxagile-baseline-$Scenario-$([guid]::NewGuid().ToString('N'))"
    try {
      New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null
      [System.IO.File]::WriteAllText((Join-Path $fixtureRoot 'App.mpr'), '', [System.Text.UTF8Encoding]::new($false))

      switch ($Scenario) {
        'greenfield' {
            [System.IO.File]::WriteAllText((Join-Path $fixtureRoot 'AGENT.md'), "# Synthetic project instructions`n", [System.Text.UTF8Encoding]::new($false))
        [System.IO.File]::WriteAllText((Join-Path $fixtureRoot 'AGENTS.md'), "# Synthetic agent entrypoint`n", [System.Text.UTF8Encoding]::new($false))
        [System.IO.File]::WriteAllText((Join-Path $fixtureRoot 'CLAUDE.md'), "# Synthetic Claude entrypoint`n", [System.Text.UTF8Encoding]::new($false))
            foreach ($directory in @('.github', 'skillssource')) {
                New-Item -ItemType Directory -Path (Join-Path $fixtureRoot $directory) -Force | Out-Null
            }
            [System.IO.File]::WriteAllText((Join-Path $fixtureRoot '.github/copilot-instructions.md'), "# Synthetic Copilot entrypoint`n", [System.Text.UTF8Encoding]::new($false))
            [System.IO.File]::WriteAllText((Join-Path $fixtureRoot 'skillssource/AGENTS.md'), "# Synthetic project knowledge`n", [System.Text.UTF8Encoding]::new($false))
        }
        'migration-in-progress' {
            $migrationDirectory = Join-Path $fixtureRoot '.mxagile/migration'
            New-Item -ItemType Directory -Path $migrationDirectory -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $migrationDirectory 'state.yaml'), "status: in_progress`n", [System.Text.UTF8Encoding]::new($false))
            $dfcDirectory = Join-Path $fixtureRoot '.dfc-ai'
            New-Item -ItemType Directory -Path $dfcDirectory -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $dfcDirectory 'version.yaml'), "version: '1.0'`n", [System.Text.UTF8Encoding]::new($false))
        }
        'session-bootstrap' {
            $claudeDirectory = Join-Path $fixtureRoot '.claude'
            New-Item -ItemType Directory -Path $claudeDirectory -Force | Out-Null
            $bootstrap = @'
#!/bin/sh
set -e
MPR="App.mpr"
TAG="${MXCLI_TAG:-nightly}"
DL_TIMEOUT="${MXCLI_DOWNLOAD_TIMEOUT:-30}"
if [ ! -x ./mxcli ]; then
  url="https://example.invalid/${TAG}/mxcli"
  if ! curl -fsSL --max-time "$DL_TIMEOUT" --connect-timeout 10 -o ./mxcli "$url"; then
    echo "ERROR: Could not download mxcli. Fetch it manually and retry."
    exit 1
  fi
  chmod +x ./mxcli
fi
./mxcli init --sync-skills . || true
# Runtime provisioning is intentionally run explicitly, not from SessionStart.
# ./mxcli run --local --setup --ensure-db -p "$MPR"
'@
            [System.IO.File]::WriteAllText((Join-Path $claudeDirectory 'bootstrap-mxcli.sh'), $bootstrap + "`n", [System.Text.UTF8Encoding]::new($false))
            $settings = @'
{
  "projectSetting": { "preserve": true },
  "hooks": {
    "SessionStart": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "sh .claude/bootstrap-mxcli.sh || true",
            "timeout": 60000,
            "mxcliGenerated": true
          },
          {
            "type": "command",
            "command": "echo project-owned-session-start"
          }
        ]
      }
    ],
    "PreToolUse": [{ "hooks": [{ "type": "command", "command": "echo pre-tool" }] }]
  }
}
'@
            [System.IO.File]::WriteAllText((Join-Path $claudeDirectory 'settings.json'), $settings + "`n", [System.Text.UTF8Encoding]::new($false))
        }
      }

      return $fixtureRoot
    } catch {
      Remove-Item -LiteralPath $fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
      throw "FIXTURE_SETUP_FAILED: unable to create '$Scenario' baseline fixture at '$fixtureRoot': $($_.Exception.Message)"
    }
}

function Remove-MxAgileBaselineFixture {
    param([Parameter(Mandatory)][string]$Path)

    $tempRoot = [System.IO.Path]::GetFullPath($env:TEMP).TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    $fixturePath = [System.IO.Path]::GetFullPath($Path)
    if ($fixturePath.StartsWith($tempRoot, [System.StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path -Leaf $fixturePath).StartsWith('mxagile-baseline-', [System.StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $fixturePath -Recurse -Force -ErrorAction SilentlyContinue
    }
}