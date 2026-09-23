# Platform Portability

Canonical contract for MxAgile installer/setup portability across Windows, Linux, macOS,
and headless/cloud-compute environments.

---

## Architecture Decision

**PowerShell Core (`pwsh`) is the canonical implementation technology on all platforms.**

Rationale:
- Single implementation language — no semantic drift by design
- All installation semantics (project-state detection, INSTALL vs UPDATE, DFC-AI migration,
  project-knowledge preservation, Core ownership, Company Layer handling, provenance,
  artifact canonicalization, platform projection generation, non-interactive execution,
  reconciliation handoff, validation, rollback/failure behavior) reside in one codebase
- PS Core 7+ is mature, available on Ubuntu via snap/apt/download, GitHub Actions, containers

A thin shell shim `install-mxagile.sh` enables zero-friction Linux/cloud entry WITHOUT
creating a parallel implementation. The shim has zero MxAgile semantic knowledge — it only
discovers pwsh and delegates to `mxagile-setup.ps1`.

### What is explicitly NOT done

Do NOT create a parallel Bash or Python implementation of the installer semantics.
Parallel implementations drift semantically. The shell shim is NOT a reimplementation.

---

## Platform Support Matrix

| Platform              | Entry Point                         | Runtime requirement      |
|---|---|---|
| Windows (developer)   | `mxagile-setup.ps1` directly        | PowerShell 5.1+ or pwsh  |
| Linux / macOS         | `bash install-mxagile.sh`           | pwsh (auto-installed if absent) |
| Cloud / headless      | `bash install-mxagile.sh`           | pwsh in container/snap   |
| CI / automation       | `pwsh mxagile-setup.ps1 -NonInteractive` | pwsh                |

---

## Shell Shim Contract (`install-mxagile.sh`)

The shell shim MUST:
1. Detect `pwsh` on PATH and at common install locations
2. If absent: print clear install instructions for the detected OS and exit 1
3. If present: `exec pwsh -NoProfile -ExecutionPolicy Bypass -File mxagile-setup.ps1 "$@"`
4. Forward all arguments unchanged — no argument interpretation

The shell shim MUST NOT:
- Implement any MxAgile setup logic
- Make any decisions about INSTALL vs UPDATE
- Read or write any project files
- Know about DFC-AI, migration, Company Layers, provenance, or lifecycle state

---

## Portability Contract for PS Scripts

All PS scripts in the MxAgile installer/setup chain MUST comply with these patterns:

### 1. Platform detection

Use the cross-platform .NET API, not `$IsWindows` alone (absent in PS 5.1):

```powershell
$isWindowsPlatform = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
    [System.Runtime.InteropServices.OSPlatform]::Windows)
```

### 2. mxcli binary name

```powershell
$mxcliName = if ($isWindowsPlatform) { 'mxcli.exe' } else { 'mxcli' }
$mxcliExe  = Join-Path $ProjectRoot $mxcliName
```

Never hardcode `mxcli.exe`.

### 3. mxcli download asset name

```powershell
$isMac     = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
                 [System.Runtime.InteropServices.OSPlatform]::OSX)
$AssetName = if ($isWindowsPlatform) { 'mxcli-windows-amd64.exe' }
             elseif ($isMac)         { 'mxcli-darwin-amd64' }
             else                    { 'mxcli-linux-amd64' }
```

After download on non-Windows: `chmod +x $TargetExe`.

### 4. Temp directory

```powershell
$tempBase = [System.IO.Path]::GetTempPath()   # cross-platform: C:\Temp\ on Win, /tmp/ on Linux
```

Never use `$env:TEMP` directly — it is absent on Linux.

### 5. Multi-level path construction

On Linux/PS Core, backslash in a Join-Path child argument is NOT a separator — it is a
literal character and creates wrong paths. Use nested Join-Path or `[System.IO.Path]::Combine()`:

```powershell
# WRONG on Linux:
Join-Path $root "planning\tasks"

# CORRECT (works on PS 5.1 + PS Core on all platforms):
Join-Path (Join-Path $root "planning") "tasks"
# OR:
[System.IO.Path]::Combine($root, "planning", "tasks")
```

Single-level paths are always safe: `Join-Path $root ".mxagile"` ✓

### 6. Glob-style file copy

```powershell
# WRONG on Linux:
Copy-Item -Path "$dir\*" -Destination $dest -Recurse -Force

# CORRECT:
Copy-Item -Path (Join-Path $dir '*') -Destination $dest -Recurse -Force
```

### 7. Direct-launch detection (Windows only)

Parent-process inspection for `explorer.exe` is Windows-only:

```powershell
$isDirectLaunch = $false
if ($isWindowsPlatform) {
    try {
        $parentName = (Get-Process -Id $PID -ErrorAction Stop).Parent.ProcessName
        $isDirectLaunch = $parentName -in @('explorer', 'OpenWith')
    } catch { }
}
```

On Linux/cloud: `$isDirectLaunch` is always false — headless/non-interactive behavior
is the correct default.

### 8. Python command

On Linux, prefer `python3` over `python`:

```powershell
$PythonCommand = Get-Command python3 -ErrorAction SilentlyContinue
if (-not $PythonCommand) {
    $PythonCommand = Get-Command python -ErrorAction SilentlyContinue
}
```

### 9. Interactive confirmation (`ReadKey`)

`[System.Console]::ReadKey()` is already wrapped in try/catch in the existing scripts.
This is correct — headless sessions silently skip the pause. No change required.
The `-NonInteractive` flag should be passed in all CI/cloud invocations.

### 10. Write-Host / colors

`Write-Host -ForegroundColor` works cross-platform in PS Core. No change required.

---

## Windows-Specific Assumptions Audit (Current State → Required Fix)

| Location | Pattern | Issue | Fix |
|---|---|---|---|
| `mxagile-setup.ps1:97` | `Get-Process ... explorer` | Windows-only parent detection | Guard with `$isWindowsPlatform` |
| `mxagile-setup.ps1:192,229` | `$env:TEMP` | Absent on Linux | `[System.IO.Path]::GetTempPath()` |
| `install-mxcli.ps1:47` | `mxcli-windows-amd64.exe` | Windows-only asset | Platform detection (§3 above) |
| `install-mxcli.ps1:64` | `mxcli.exe` | Windows-only name | Platform detection (§2 above) |
| `install-mxcli.ps1:165` | `$env:TEMP` | Absent on Linux | `[System.IO.Path]::GetTempPath()` |
| `install-mxcli.ps1` | No chmod after download | Binary not executable on Linux | `chmod +x` on non-Windows |
| `install-core.ps1:172` | `mxcli.exe` | Windows-only name | Platform detection (§2 above) |
| `install-core.ps1:276` | `"$dir\*"` in Copy-Item | Backslash glob fails on Linux | `Join-Path $dir '*'` |
| `install-core.ps1:454` | `"$path\\*"` in Copy-Item | Same | `Join-Path "$path" '*'` |
| `mxagile-init.ps1:67` | `mxcli.exe` | Windows-only name | Platform detection (§2 above) |
| `mxagile-init.ps1:109` | `"planning\tasks"` in Join-Path | Multi-level backslash | Nested Join-Path |
| `mxagile-init.ps1:33` | `Get-Command python` | `python3` preferred on Linux | Try python3 first (§8 above) |

---

## Cloud / Headless Specifics

In headless environments:
- `$isDirectLaunch` is always `false` — no explorer parent
- Interactive ReadKey silently no-ops — correct behavior
- `-NonInteractive` is the recommended flag for automation
- No TTY is required — all output via Write-Host
- `pwsh` may need to be pre-installed in the container or installed by a CI step

Recommended container setup:
```dockerfile
RUN apt-get install -y wget && \
    wget -q "https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/packages-microsoft-prod.deb" && \
    dpkg -i packages-microsoft-prod.deb && \
    apt-get update && apt-get install -y powershell
```

Or via snap: `snap install powershell --classic`
