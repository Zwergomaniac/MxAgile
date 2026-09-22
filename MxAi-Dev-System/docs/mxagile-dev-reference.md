# mxagile-dev — Developer CLI Reference

Thin maintainer dispatch layer for common MxAgile development operations.
Wraps canonical scripts so you don't have to browse `scripts/` or remember paths.

**Entry point:** `MxAi-Dev-System/mxagile-dev.ps1`

---

## Quick Start

```powershell
# Show help
mxagile-dev

# Run all tests
mxagile-dev test all

# List test workspaces
mxagile-dev workspace list

# Create a test workspace from a project template
mxagile-dev workspace create brownfield_migration_captrack

# Classify a project
mxagile-dev project detect .testing-brownfield_migration_captrack

# Show project diagnostics
mxagile-dev project status .testing-brownfield_migration_captrack

# Show migration diagnostic status
mxagile-dev migration status .testing-brownfield_migration_captrack

# Install MxAgile into a Mendix project
mxagile-dev install core /path/to/mendix-project
```

---

## Command Reference

### test

| Command | Delegates to | Notes |
|---|---|---|
| `test list` | (built-in) | Discovers `tests/test-*.ps1` by convention |
| `test run <suite>` | `tests/test-<suite>.ps1` | Also accepts: `smoke`, `installer`, `all` |
| `test all` | `tests/run-all-tests.ps1` | All unit suites; uses `powershell` (PS5.1) per CI convention |

Suite names map directly to test filenames: `test run migration-crash-safety` runs `tests/test-migration-crash-safety.ps1`.

The `installer` suite runs `tests/run-installer-tests.ps1 -Test All -SkipMercedesIntegration`.

### workspace

| Command | Delegates to | Notes |
|---|---|---|
| `workspace list` | (built-in) | Enumerates `.testing-*` dirs at repo root |
| `workspace create <template>` | `scripts/create-test-workcopy.ps1` | Pass `-Force` to overwrite |
| `workspace reset <workspace>` | `scripts/create-test-workcopy.ps1 -Force` | Assumes template name = workspace name |
| `workspace remove <workspace>` | `Remove-Item` (safety-checked) | Only `.testing-*` dirs under repo root |

Available templates are under `project-templates/`:
- `brownfield_migration_captrack`
- `brownfield_spec`
- `brownfield_unspecced`
- `greenfield`

**Safety:** `workspace remove` and `workspace reset` are guarded by two checks:
1. The resolved path must be a direct child of the repo root.
2. The leaf directory name must start with `.testing-`.

Paths that fail either check are rejected with exit code 3.

### project

| Command | Delegates to | Notes |
|---|---|---|
| `project detect [path]` | `scripts/detect-project-type.ps1` | Path defaults to `$PWD` |
| `project status [path]` | `scripts/detect-project-type.ps1` + direct reads | Aggregated diagnostics; read-only |

`project status` shows: Mendix `.mpr` filename, project classification, `lifecycle.yaml` presence, migration state, and brownfield baseline presence.

### install

| Command | Delegates to | Notes |
|---|---|---|
| `install core <path>` | `install-mxagile.ps1` | Public bootstrap; DFC preflight is preserved |
| `install mercedes <path>` | `install-mxagile-mercedes.ps1` | Public bootstrap + Mercedes Company Layer |

Both commands delegate to the **public bootstrap scripts**, which handle distribution acquisition and legacy DFC-AI detection/migration routing through the canonical preflight. The CLI does not call `scripts/install-core.ps1` directly.

### migration

| Command | Delegates to | Notes |
|---|---|---|
| `migration status [path]` | `scripts/detect-project-type.ps1` + direct reads | Diagnostic only; read-only |

Shows: classification, `state.yaml` content, migration README, brownfield baseline, and `.dfc-ai/` presence.

---

## Exit Codes

| Code | Meaning |
|---|---|
| `0` | Success |
| `1` | Underlying canonical script failed (propagated) |
| `2` | CLI usage error: unknown command, missing argument, path not found |
| `3` | Safety violation: destructive operation rejected (non-workspace path) |

---

## Repository Root Discovery

`mxagile-dev.ps1` uses `$PSScriptRoot` (the script's own directory) as the repo root
and validates it by checking for two marker files:

- `tests/run-all-tests.ps1`
- `scripts/detect-project-type.ps1`

This means the CLI can be invoked from any working directory using an absolute path
and will still locate canonical scripts correctly. It will not mistake a test workspace
for the framework repository.

---

## Design Invariants

- **No duplicated logic.** The CLI never reimplements what a canonical script does.
- **Canonical scripts are authoritative.** If a script changes, the CLI delegates to
  the updated script without modification.
- **Public bootstrap is preserved.** `install core` and `install mercedes` use the
  public bootstrap scripts, preserving DFC-AI detection and migration preflight.
- **Workspace safety.** Destructive commands validate `.testing-*` prefix and repo-root
  containment before any removal.

---

## Adding a New Command (Future)

1. Identify the canonical script to delegate to.
2. Add a function `Invoke-<Group>Command` or extend an existing switch block in `mxagile-dev.ps1`.
3. Delegate: `& powershell -NoProfile -File $canonicalScript @args; exit $LASTEXITCODE`.
4. Add tests to `tests/test-mxagile-dev-cli.ps1`.
5. Update this reference.

Do not copy script logic into the CLI. One-line delegation is always the correct pattern.
