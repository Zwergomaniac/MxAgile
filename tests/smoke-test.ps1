# tests/smoke-test.ps1

$PSScriptRoot = Split-Path -Path $MyInvocation.MyCommand.Path -Parent
$scriptDir = Join-Path $PSScriptRoot "..\scripts"

$scripts = @(
    "install-mxcli.ps1",
    "generate-mxagile-platform-skills.ps1",
    "mxagile-clarify.ps1",
    "mxagile-reconcile.ps1",
    "mxagile-tasks.ps1",
    "reset-testing-instance.ps1",
    "run-docker-isolated.ps1"
)

$results = @()
$failureCount = 0

foreach ($scriptName in $scripts) {
    $scriptPath = Join-Path $scriptDir $scriptName
    $status = "Not Found"
    $details = ""

    if (Test-Path $scriptPath) {
        $content = Get-Content $scriptPath -Raw
        if ($content -match "\[CmdletBinding\(\)\]") {
            $status = "Pass"
            $details = "[CmdletBinding()] found."
        } else {
            $status = "Fail"
            $details = "Script is missing [CmdletBinding()]."
            $failureCount++
        }
    } else {
        $status = "Fail"
        $details = "Script file not found."
        $failureCount++
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

# Exit with a non-zero code if any failures were detected
if ($failureCount -gt 0) {
    Write-Error "$failureCount smoke test check(s) failed."
    exit 1
} else {
    Write-Host "✅ All smoke test checks passed."
    exit 0
}

