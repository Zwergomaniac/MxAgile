# scripts/mxagile-build-trace-index.ps1
# Builds a traceability index from project artifacts without external dependencies.

param (
    [string]$ProjectRoot = (Get-Location).Path
)
$ProjectRoot = (Resolve-Path -Path $ProjectRoot).Path

# Helper function to parse simple Key: Value pairs from a file.
function Parse-ArtifactFile($filePath) {
    $data = @{}
    $content = Get-Content -Path $filePath -Raw

    # Regex to find lines starting with Key: Value
    $regex = '(?m)^([a-zA-Z_\-]+):\s*(.*)$'
    $matches = $content | Select-String -Pattern $regex -AllMatches

    foreach ($match in $matches.Matches) {
        $key = $match.Groups[1].Value.Trim()
        $value = $match.Groups[2].Value.Trim()
        
        # Simple handling for list-like values (e.g., requirements, specs)
        if ($data.ContainsKey($key)) {
            if ($data[$key] -is [array]) {
                $data[$key] += $value
            } else {
                $data[$key] = @($data[$key], $value)
            }
        } else {
            $data[$key] = $value
        }
    }
    return $data
}

Write-Host "Building MxAgile traceability index (dependency-free)..."

$index = @{
    requirements = @{}
    specs = @{}
    waves = @{}
    tasks = @{}
}

# Define artifact locations
$artifactLocations = @(
    @{ Name = "requirements"; Path = "requirements"; Filter = "*.req" },
    @{ Name = "specs"; Path = "specs"; Filter = "*.spec" },
    @{ Name = "waves"; Path = "waves"; Filter = "*.wave" }
    # tasks can be added here if they adopt the same format
)

# --- Parse all artifacts ---
foreach ($location in $artifactLocations) {
    $artifactPath = Join-Path $ProjectRoot $location.Path
    if (-not (Test-Path $artifactPath)) { continue }

    $files = Get-ChildItem -Path $artifactPath -Filter $location.Filter -Recurse
    foreach ($file in $files) {
        $data = Parse-ArtifactFile -filePath $file.FullName
        $id = $data.ID # Standardized on 'ID' as the key

        if ($id) {
            $entry = @{ 
                path = $file.FullName.Replace($ProjectRoot + "\", "") # Store relative path
            }
            # Add all other parsed data to the entry
            $data.GetEnumerator() | Where-Object { $_.Name -ne 'ID' } | ForEach-Object {
                $entry[$_.Name] = $_.Value
            }
            $index.($location.Name)[$id] = $entry
        }
    }
}

# --- Save Index File ---
$stateDir = Join-Path $ProjectRoot ".mxagile/state"
if (-not (Test-Path $stateDir)) {
    New-Item -ItemType Directory -Path $stateDir | Out-Null
}
$outputFile = Join-Path $stateDir "trace-index.json"

$index | ConvertTo-Json -Depth 5 | Set-Content -Path $outputFile

Write-Host "Traceability index created successfully at: $outputFile"