# scripts/mxagile-tasks.ps1

param (
    [Parameter(Mandatory=$true)]
    [string]$PlanFile
)

$ProjectRoot = (Get-Location).Path
Write-Host "Generating tasks for plan: $PlanFile"

# --- 1. Load Plan and Task Template ---
if (-not (Test-Path $PlanFile)) {
    Write-Error "Plan file not found: $PlanFile"
    return
}
$planContent = Get-Content -Path $PlanFile

$taskTemplatePath = Join-Path $ProjectRoot ".mxagile/templates/generic/tasks/template.yaml"
if (-not (Test-Path $taskTemplatePath)) {
    Write-Error "Task template not found: $taskTemplatePath"
    return
}
$taskTemplate = Get-Content -Path $taskTemplatePath -Raw


# --- 2. Parse Plan and Generate Tasks (Agent Logic) ---
Write-Host "Parsing plan and generating tasks..."

# TODO: This is where the core agent logic will go.
# The agent will parse the markdown plan file and identify the discrete
# implementation steps (e.g., create entity, create page).
# For each step, it generates a task YAML file.

# --- Placeholder Example --- 
# As a placeholder, we will generate two example tasks manually.

$tasksDir = Join-Path $ProjectRoot "planning/tasks"
if (-not (Test-Path $tasksDir)) {
    New-Item -ItemType Directory -Path $tasksDir | Out-Null
}

# Example Task 1: Create Entity
$task1Content = $taskTemplate `
    -replace "task_id: TASK-000", "task_id: TASK-001" `
    -replace "spec_id: SPEC-000", "spec_id: SPEC-USER-LOGIN" `
    -replace "req: \[REQ-000\]", "req: [REQ-042]" `
    -replace "type: entity", "type: entity" `
    -replace 'action: "\[Short description of the task\]"', 'action: "Create NewEntity"'

$task1Content | Set-Content -Path (Join-Path $tasksDir "TASK-001.yaml")
Write-Host "Generated task: TASK-001.yaml"


# Example Task 2: Create Page
$task2Content = $taskTemplate `
    -replace "task_id: TASK-000", "task_id: TASK-002" `
    -replace "spec_id: SPEC-000", "spec_id: SPEC-USER-LOGIN" `
    -replace "req: \[REQ-000\]", "req: [REQ-042]" `
    -replace "type: entity", "type: page" `
    -replace 'action: "\[Short description of the task\]"', 'action: "Create NewEntity_Overview page"' `
    -replace "depends_on: \[\]", "depends_on: [TASK-001]"

$task2Content | Set-Content -Path (Join-Path $tasksDir "TASK-002.yaml")
Write-Host "Generated task: TASK-002.yaml"
# --- End Placeholder ---


Write-Host "Task generation complete."

