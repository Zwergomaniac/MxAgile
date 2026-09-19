# scripts/mxagile-clarify.ps1

param (
    [string]$ProjectRoot = (Get-Location).Path
)

Write-Host "Starting MxAgile clarification scan..."

$scanPaths = @(
    (Join-Path $ProjectRoot "requirements"),
    (Join-Path $ProjectRoot "specs")
)

$keywords = @(
    "DECISION REQUIRED",
    "ASSUMPTION",
    "TODO",
    "TBD"
)

$foundIssues = @()

foreach ($path in $scanPaths) {
    if (Test-Path $path) {
        $files = Get-ChildItem -Path $path -Filter *.md -Recurse
        foreach ($file in $files) {
            $lines = Get-Content -Path $file.FullName
            for ($i = 0; $i -lt $lines.Length; $i++) {
                foreach ($keyword in $keywords) {
                    if ($lines[$i] -match $keyword) {
                        $foundIssues += [pscustomobject]@{
                            File = $file.FullName
                            Line = $i + 1
                            Text = $lines[$i].Trim()
                            Keyword = $keyword
                        }
                    }
                }
            }
        }
    }
}

if ($foundIssues.Count -gt 0) {
    Write-Host "Found $($foundIssues.Count) potential ambiguities or open points:`n"
    $foundIssues | Format-Table

    Write-Host "`nNext Steps:"
    Write-Host " - Manually review the files listed above."
    Write-Host " - Future versions of this script will provide an interactive Q&A session to resolve these points."
    # TODO: Implement interactive clarification using Read-Host.
    # TODO: Implement logic to update the source files with the provided answers.
} else {
    Write-Host "Scan complete. No open points with keywords found."
}
