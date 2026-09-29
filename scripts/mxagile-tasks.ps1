# scripts/mxagile-tasks.ps1

[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)]
    [string]$PlanFile
)

$ProjectRoot = (Get-Location).Path
Write-Host "🚀 Generating tasks for plan: $PlanFile"

# --- 1. Load Plan File ---
if (-not (Test-Path $PlanFile)) {
    Write-Error "Plan file not found: $PlanFile"
    return
}
# Read the whole file, split by semicolon
$mdlStatements = (Get-Content -Path $PlanFile -Raw) -split ';'

$tasksDir = Join-Path $ProjectRoot "planning/tasks"
if (-not (Test-Path $tasksDir)) {
    New-Item -ItemType Directory -Path $tasksDir | Out-Null
}

# --- 2. Parse Statements and Generate Tasks ---
$taskCounter = 1
foreach ($statement in $mdlStatements) {
    $trimmedStatement = $statement.Trim()
    if ($trimmedStatement.Length -eq 0) {
        continue
    }

    # Add the semicolon back
    $fullStatement = $trimmedStatement + ';'

    # Basic parsing with regex to find Type and Target
    $type = ""
    $target = ""
    if ($fullStatement -match 'CREATE (PERSISTENT ENTITY|ASSOCIATION) [^\s]+\"(.*?)\"') {
        $matches = $Matches
        $type = $matches[1].Trim()
        $target = $matches[2].Trim()
    } else {
        Write-Warning "Could not parse statement, using generic task name: $fullStatement"
        $type = "UNKNOWN"
        $target = "Task$taskCounter"
    }

    $taskId = "T-" + $taskCounter.ToString("000")
    $taskFileName = "$taskId`_$($type.Replace(' ','_'))`_$target.task"
    $taskFilePath = Join-Path $tasksDir $taskFileName

    $taskContent = @"
ID: $taskId
SourcePlan: $($PlanFile.Split('\')[-1])
Type: $type
Target: $target
Status: Pending
MDL:
$fullStatement
"@

    $taskContent | Set-Content -Path $taskFilePath
    Write-Host "- Generated task: $taskFileName"
    $taskCounter++
}

Write-Host "✅ Task generation complete."
