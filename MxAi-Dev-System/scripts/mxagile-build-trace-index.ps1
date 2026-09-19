# scripts/mxagile-build-trace-index.ps1

param (
    [string]$ProjectRoot = (Get-Location).Path
)

#Requires -Modules powershell-yaml

Write-Host "Building MxAgile traceability index..."

$index = @{
    requirements = @{}
    specs = @{}
    tasks = @{}
}

# --- Parse Requirements ---
$reqFiles = Get-ChildItem -Path (Join-Path $ProjectRoot "requirements") -Filter *.md -Recurse
foreach ($file in $reqFiles) {
    $content = Get-Content -Path $file.FullName -Raw
    $yamlPart = ($content -split '---')[1]
    $data = ConvertFrom-Yaml -Yaml $yamlPart
    if ($data.req_id) {
        $index.requirements[$data.req_id] = @{ 
            path = $file.FullName 
        }
    }
}

# --- Parse Specs ---
$specFiles = Get-ChildItem -Path (Join-Path $ProjectRoot "specs") -Filter *.md -Recurse
foreach ($file in $specFiles) {
    $content = Get-Content -Path $file.FullName -Raw
    $yamlPart = ($content -split '---')[1]
    $data = ConvertFrom-Yaml -Yaml $yamlPart
    if ($data.spec_id) {
        $index.specs[$data.spec_id] = @{ 
            path = $file.FullName
            requirements = $data.requirements
        }
    }
}

# --- Parse Tasks ---
$taskFiles = Get-ChildItem -Path (Join-Path $ProjectRoot "planning/tasks") -Filter *.yaml -Recurse
foreach ($file in $taskFiles) {
    $data = ConvertFrom-Yaml -Input (Get-Content -Path $file.FullName -Raw)
    if ($data.task_id) {
        $index.tasks[$data.task_id] = @{ 
            path = $file.FullName
            spec_id = $data.spec_id
            requirements = $data.req
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

Write-Host "Traceability index created at: $outputFile"
