function Remove-TestTempDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$ExpectedPrefix,
        [ValidateRange(1, 20)][int]$Attempts = 20
    )

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $separators = [char[]]@([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd($separators)
    $parent = [System.IO.Path]::GetDirectoryName($fullPath).TrimEnd($separators)
    $leaf = [System.IO.Path]::GetFileName($fullPath)
    $guidPattern = '(?:[0-9a-fA-F]{32}|[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})'
    $expectedLeafPattern = '^' + [regex]::Escape($ExpectedPrefix) + $guidPattern + '$'

    if (-not $parent.Equals($tempRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
        $leaf -notmatch $expectedLeafPattern) {
        throw "Refusing to clean an unexpected test temp path: $fullPath"
    }

    $lastError = $null
    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        try {
            if (Test-Path -LiteralPath $fullPath -PathType Container) {
                Remove-Item -LiteralPath $fullPath -Recurse -Force -ErrorAction Stop
            }
            if (-not (Test-Path -LiteralPath $fullPath)) { return }
            $lastError = 'The suite-owned temp root still exists after removal.'
        } catch {
            $lastError = $_.Exception.Message
        }

        if ($attempt -lt $Attempts) { Start-Sleep -Milliseconds (100 * [math]::Min($attempt, 5)) }
    }

    if (-not (Test-Path -LiteralPath $fullPath -PathType Container)) { return }
    try {
        $remaining = @(Get-ChildItem -LiteralPath $fullPath -Force -Recurse -ErrorAction Stop)
    } catch {
        throw "Could not verify remaining test artifacts under '$fullPath': $($_.Exception.Message)"
    }
    if ($remaining.Count -gt 0) {
        $paths = ($remaining | Select-Object -First 5 -ExpandProperty FullName) -join ', '
        throw "Test temp cleanup left artifacts after $Attempts attempts: $paths. Last error: $lastError"
    }

    try {
        Remove-Item -LiteralPath $fullPath -Force -ErrorAction Stop
    } catch {
        if (Test-Path -LiteralPath $fullPath) {
            Write-Warning "The suite-owned temp root remains empty after $Attempts cleanup attempts: $fullPath"
        }
    }
}