<#
.SYNOPSIS
Mirrors Mendix Epics board data into local, generated read-only snapshots.

.DESCRIPTION
Reads statuses, epics, and stories using the Mendix Epics API. It never sends
POST, PATCH, PUT, or DELETE requests and does not update the Mendix board.
#>

[CmdletBinding()]
param(
    [string]$EnvironmentFile = (Join-Path (Split-Path -Parent $PSScriptRoot) '.env.mendix'),
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'sprints\generated'),
    [ValidateRange(1, 100)]
    [int]$PageSize = 100
)

$ErrorActionPreference = 'Stop'

function Get-EnvironmentValues {
    param([string]$Path)

    if (-not (Test-Path -Path $Path -PathType Leaf)) {
        throw "Configuration file '$Path' does not exist. Copy .env.mendix.example to .env.mendix first."
    }

    $values = @{}
    foreach ($line in Get-Content -Path $Path) {
        if ($line -match '^\s*(#|$)') {
            continue
        }

        if ($line -notmatch '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$') {
            throw "Invalid configuration line in '$Path': $line"
        }

        $values[$matches[1]] = $matches[2].Trim('"', "'")
    }

    return $values
}

function Get-ResponseItems {
    param($Response)

    if ($null -eq $Response) {
        return @()
    }

    if ($null -ne $Response.data) {
        return @($Response.data)
    }

    foreach ($propertyName in @('stories', 'epics', 'statuses', 'tasks', 'labels')) {
        if ($null -ne $Response.$propertyName) {
            return @($Response.$propertyName)
        }
    }

    return @($Response)
}

function Get-PaginatedItems {
    param(
        [string]$Endpoint,
        [hashtable]$Headers,
        [int]$Limit
    )

    $items = [System.Collections.Generic.List[object]]::new()
    $offset = 0

    do {
        $separator = if ($Endpoint.Contains('?')) { '&' } else { '?' }
        $response = Invoke-RestMethod -Method Get -Uri "$Endpoint$separator`limit=$Limit&offset=$offset" -Headers $Headers
        $page = @(Get-ResponseItems -Response $response)
        foreach ($item in $page) {
            $items.Add($item)
        }
        $offset += $page.Count
    } while ($page.Count -eq $Limit)

    return @($items)
}

function ConvertTo-CellText {
    param($Value)

    if ($null -eq $Value) {
        return ''
    }

    return ([string]$Value).Replace('|', '\|').Replace("`r", ' ').Replace("`n", ' ').Trim()
}

function Get-ContentFingerprint {
    param($Story)

    $source = [ordered]@{
        storyId = $Story.storyId
        title = $Story.title
        descriptionPlain = $Story.descriptionPlain
        storyLevel = $Story.storyLevel
        status = if ($null -ne $Story.status) { $Story.status } else { $Story.storyStatus }
        storyPoints = $Story.storyPoints
        tasks = @($Story.tasks | Sort-Object sortId, title | ForEach-Object {
            [ordered]@{ title = $_.title; isDone = $_.isDone; sortId = $_.sortId }
        })
    }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes(($source | ConvertTo-Json -Depth 10 -Compress))
    return ([System.Security.Cryptography.SHA256]::HashData($bytes) | ForEach-Object ToString x2) -join ''
}

$environment = Get-EnvironmentValues -Path $EnvironmentFile
$personalAccessToken = $environment['MENDIX_PAT']
$applicationId = $environment['MENDIX_APP_ID']

if ([string]::IsNullOrWhiteSpace($personalAccessToken) -or [string]::IsNullOrWhiteSpace($applicationId)) {
    throw "MENDIX_PAT and MENDIX_APP_ID must both be set in '$EnvironmentFile'."
}

$apiBaseUrl = "https://epics-api.mendix.com/v1/projects/$applicationId"
$headers = @{ Authorization = "MxToken $personalAccessToken" }

$statuses = @(Get-ResponseItems -Response (Invoke-RestMethod -Method Get -Uri "$apiBaseUrl/statuses" -Headers $headers))
$epics = Get-PaginatedItems -Endpoint "$apiBaseUrl/epics" -Headers $headers -Limit $PageSize
$stories = Get-PaginatedItems -Endpoint "$apiBaseUrl/stories" -Headers $headers -Limit $PageSize

foreach ($story in $stories) {
    $story | Add-Member -NotePropertyName tasks -NotePropertyValue @() -Force
    if ([int]$story.numberOfTasks -gt 0) {
        $encodedStoryId = [Uri]::EscapeDataString([string]$story.storyId)
        $story.tasks = @(Get-ResponseItems -Response (Invoke-RestMethod -Method Get -Uri "$apiBaseUrl/stories/$encodedStoryId/tasks" -Headers $headers))
    }
    $story | Add-Member -NotePropertyName sourceFingerprint -NotePropertyValue (Get-ContentFingerprint -Story $story) -Force
}

New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$generatedAt = (Get-Date).ToUniversalTime().ToString('o')
$snapshot = [ordered]@{
    generatedAtUtc = $generatedAt
    source = 'Mendix Epics API (read-only)'
    applicationId = $applicationId
    statuses = $statuses
    epics = $epics
    stories = $stories
}

$jsonPath = Join-Path $OutputDirectory 'epics-snapshot.json'
$markdownPath = Join-Path $OutputDirectory 'epics-stories.md'
$snapshot | ConvertTo-Json -Depth 20 | Set-Content -Path $jsonPath -Encoding utf8

$markdown = [System.Text.StringBuilder]::new()
[void]$markdown.AppendLine('<!-- Generated by scripts/sync-epics-stories.ps1. Do not edit manually. -->')
[void]$markdown.AppendLine('# Mendix Epics Story Snapshot')
[void]$markdown.AppendLine()
[void]$markdown.AppendLine("Generated (UTC): $generatedAt")
[void]$markdown.AppendLine()
[void]$markdown.AppendLine('| Story | Title | Level | Status | Points | Tasks |')
[void]$markdown.AppendLine('|---|---|---|---|---:|---:|')
foreach ($story in $stories | Sort-Object storyId, title) {
    $storyId = ConvertTo-CellText $story.storyId
    $title = ConvertTo-CellText $story.title
    $level = ConvertTo-CellText $story.storyLevel
    $status = ConvertTo-CellText $(if ($null -ne $story.status) { $story.status } else { $story.storyStatus })
    $points = ConvertTo-CellText $story.storyPoints
    $taskCount = ConvertTo-CellText $story.numberOfTasks
    [void]$markdown.AppendLine("| $storyId | $title | $level | $status | $points | $taskCount |")
}

$storiesWithTasks = @($stories | Where-Object { $_.tasks.Count -gt 0 } | Sort-Object storyId, title)
if ($storiesWithTasks.Count -gt 0) {
    [void]$markdown.AppendLine()
    [void]$markdown.AppendLine('## Tasks')
    foreach ($story in $storiesWithTasks) {
        [void]$markdown.AppendLine()
        [void]$markdown.AppendLine("### $(ConvertTo-CellText $story.storyId) - $(ConvertTo-CellText $story.title)")
        foreach ($task in $story.tasks | Sort-Object sortId, title) {
            $checkbox = if ($task.isDone) { 'x' } else { ' ' }
            [void]$markdown.AppendLine("- [$checkbox] $(ConvertTo-CellText $task.title)")
        }
    }
}

$markdown.ToString() | Set-Content -Path $markdownPath -Encoding utf8
$taskCount = @($stories | ForEach-Object { $_.tasks }).Count
Write-Host "Synchronized $($stories.Count) stories, $($epics.Count) epics, and $taskCount tasks to '$OutputDirectory'."