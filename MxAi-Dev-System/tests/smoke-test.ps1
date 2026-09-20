# tests/smoke-test.ps1

$scriptDir = Join-Path (Get-Location).Path "scripts"
$scripts = @(
    "install-mxcli.ps1",
    "generate-dfc-platform-skills.ps1",
    "mxagile-clarify.ps1",
    "mxagile-reconcile.ps1",
    "mxagile-tasks.ps1",
    "reset-testing-instance.ps1",
    "run-docker-isolated.ps1"
)

$results = @()

foreach ($scriptName in $scripts) {
    $scriptPath = Join-Path $scriptDir $scriptName
    $status = "Not Found"
    $details = ""

    if (Test-Path $scriptPath) {
        # Check if it has -Help parameter
        $content = Get-Content $scriptPath -Raw
        if ($content -match "\-Help" -or $content -match "\[CmdletBinding\(\)\]") {
            try {
                # Attempt to run safely with -Help
                $proc = Start-Process pwsh -ArgumentList "-File", "`"$scriptPath`"", "-Help" -NoNewWindow -PassThru -Wait -RedirectStandardError "err.txt"
                if ($proc.ExitCode -eq 0) {
                    $status = "Pass"
                } else {
                    $status = "Fail"
                    $details = "Exit Code: $($proc.ExitCode)"
                }
            } catch {
                $status = "Fail"
                $details = "Exception: $($_.Exception.Message)"
            }
        } else {
            # Not safe to run without -Help, just verify existence
            $status = "Pass (Existence Verified, Execution Skipped)"
        }
    }

    $results += [PSCustomObject]@{
        Script = $scriptName
        Status = $status
        Details = $details
    }
}

# Print Summary
Write-Host "`nSmoke Test Summary:" -ForegroundColor Cyan
$results | Format-Table -AutoSize
