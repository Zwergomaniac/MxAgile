# Mendix Epics API — Skill Reference

Use this API to manage stories, epics, tasks, labels, and statuses in the Mendix Developer Portal (Epics board).

## Authentication

```bash
# Load credentials from .env.mendix
source .env.mendix

# Header format:
Authorization: MxToken $MENDIX_PAT
```

- Generate PAT at: https://user-settings.mendix.com/ → Developer Settings → Personal Access Tokens
- Required scopes: `mx:epics:read` (GET), `mx:epics:write` (all operations)
- App-ID: UUID from Developer Portal URL (`https://sprintr.home.mendix.com/link/project/{APP_ID}`)

## Base URL

```
https://epics-api.mendix.com/v1
```

## Quick Reference

### Statuses

```bash
# Get all board statuses
curl -s -H "Authorization: MxToken $MENDIX_PAT" \
  "https://epics-api.mendix.com/v1/projects/$MENDIX_APP_ID/statuses"
```

### Stories

```bash
# List stories (paginated: limit max 100, offset)
curl -s -H "Authorization: MxToken $MENDIX_PAT" \
  "https://epics-api.mendix.com/v1/projects/$MENDIX_APP_ID/stories?limit=50&offset=0"

# Get single story by readable ID (e.g. "TEST-1")
curl -s -H "Authorization: MxToken $MENDIX_PAT" \
  "https://epics-api.mendix.com/v1/projects/$MENDIX_APP_ID/stories/TEST-1"

# Create stories (batch, max 50)
curl -s -X POST -H "Authorization: MxToken $MENDIX_PAT" \
  -H "Content-Type: application/json" \
  -d '[
    {
      "title": "Implement login page",
      "description": "Add login form with SSO support",
      "storyType": "Feature",
      "storyPoints": 5,
      "storyLevel": "Backlog"
    }
  ]' \
  "https://epics-api.mendix.com/v1/projects/$MENDIX_APP_ID/stories"

# Update a story
curl -s -X PATCH -H "Authorization: MxToken $MENDIX_PAT" \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Updated title",
    "storyLevel": "Active",
    "storyStatus": "In Progress"
  }' \
  "https://epics-api.mendix.com/v1/projects/$MENDIX_APP_ID/stories/TEST-1"
```

### Epics

```bash
# List epics
curl -s -H "Authorization: MxToken $MENDIX_PAT" \
  "https://epics-api.mendix.com/v1/projects/$MENDIX_APP_ID/epics?limit=50"

# Create epic
curl -s -X POST -H "Authorization: MxToken $MENDIX_PAT" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Sprint 1 - Foundation",
    "objective": "Core module setup and tenant management",
    "labels": ["MVP", "Phase-1"]
  }' \
  "https://epics-api.mendix.com/v1/projects/$MENDIX_APP_ID/epics"

# Update epic
curl -s -X PATCH -H "Authorization: MxToken $MENDIX_PAT" \
  -H "Content-Type: application/json" \
  -d '{"name": "Updated Epic Name", "objective": "New objective"}' \
  "https://epics-api.mendix.com/v1/projects/$MENDIX_APP_ID/epics/{epicUUID}"

# Delete epic
curl -s -X DELETE -H "Authorization: MxToken $MENDIX_PAT" \
  "https://epics-api.mendix.com/v1/projects/$MENDIX_APP_ID/epics/{epicUUID}"
```

### Tasks

```bash
# Get tasks for a story
curl -s -H "Authorization: MxToken $MENDIX_PAT" \
  "https://epics-api.mendix.com/v1/projects/$MENDIX_APP_ID/stories/TEST-1/tasks"

# Create tasks (batch, max 50)
curl -s -X POST -H "Authorization: MxToken $MENDIX_PAT" \
  -H "Content-Type: application/json" \
  -d '[
    {"title": "Design UI mockup", "isDone": false},
    {"title": "Write acceptance criteria", "isDone": false}
  ]' \
  "https://epics-api.mendix.com/v1/projects/$MENDIX_APP_ID/stories/TEST-1/tasks"
```

### Labels

```bash
# Get all labels
curl -s -H "Authorization: MxToken $MENDIX_PAT" \
  "https://epics-api.mendix.com/v1/projects/$MENDIX_APP_ID/labels"
```

## Data Types

### Story

| Field | Type | Notes |
|-------|------|-------|
| `uuid` | UUID | Internal ID |
| `storyId` | String | Readable ID (e.g. "TEST-1") |
| `title` | String | Max 200 chars, required |
| `description` | String | Plain text or HTML |
| `storyType` | Enum | `"Feature"` or `"Bug"` |
| `storyLevel` | Enum | `"Active"`, `"NextSprint"`, `"InRefinement"`, `"Backlog"` |
| `storyPoints` | Integer | Effort estimation |
| `status` | String | Board column (from GET statuses) |
| `numberOfTasks` | Integer | Task count |

### Epic

| Field | Type | Notes |
|-------|------|-------|
| `epicId` | String | Readable ID (e.g. "EPI-TEST-1") |
| `name` | String | Required for create |
| `objective` | String | Epic description/goal |
| `labels` | String[] | Label names |
| `numberOfStories` | Integer | Story count |
| `numberOfStoryPoints` | Integer | Total points |

### Task

| Field | Type | Notes |
|-------|------|-------|
| `title` | String | Task description |
| `isDone` | Boolean | Completion status |
| `sortId` | Integer | Order within story |

## Pagination

All list endpoints support `limit` (1-100, default 20) and `offset` (0-based).

Response includes `links` array:
```json
{
  "data": [...],
  "links": [
    {"rel": "first", "hRef": "...?limit=20&offset=0"},
    {"rel": "next", "hRef": "...?limit=20&offset=20"},
    {"rel": "last", "hRef": "...?limit=20&offset=80"}
  ]
}
```

## Constraints

- Max 50 items per batch create (stories or tasks)
- Story title max 200 characters
- Story title is required and cannot be empty
- Moving to "Active" level requires an active sprint in the project
- Story status is required when level is "Active"

## Error Format

```json
{
  "status": 400,
  "title": "Bad Request",
  "detail": "Descriptive error message"
}
```

HTTP codes: 200 (OK), 204 (patch/delete success), 207 (partial batch success), 400, 401, 404.

## Integration Pattern: Sprint Sync

To sync local sprint files with Mendix Epics:

```bash
# 1. Create epic per sprint
# 2. Create stories in batch (max 50 per call)
# 3. Set storyLevel based on sprint assignment:
#    - Current sprint → "Active"
#    - Next sprint → "NextSprint"  
#    - Future → "InRefinement"
#    - Unassigned → "Backlog"
```

## OpenAPI Spec

Full spec available at: https://github.com/mendix/docs/blob/main/static/openapi-spec/epics.yaml
