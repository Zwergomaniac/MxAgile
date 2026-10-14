<#
.SYNOPSIS
RF-003: ctx_index is the authoring tool — verifies no ctx_store references exist in
Framework policies, skills, templates, docs, or generated projections.
#>

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

$pass = 0
$fail = 0
$errors = @()

function Pass([string]$name) {
    $script:pass++
    Write-Host "  PASS  $name" -ForegroundColor Green
}

function Fail([string]$name, [string]$reason) {
    $script:fail++
    $script:errors += "FAIL: $name — $reason"
    Write-Host "  FAIL  $name" -ForegroundColor Red
    Write-Host "        $reason" -ForegroundColor DarkRed
}

Write-Host ""
Write-Host "RF-003: ctx_index Is the Authoring Tool" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Directories to check for ctx_store usage (excluding tests which may reference it for explanation)
$searchDirs = @(
    (Join-Path $repoRoot ".mxagile")
    (Join-Path $repoRoot "scripts")
    (Join-Path $repoRoot ".claude\skills")
    (Join-Path $repoRoot ".agents\skills")
)
# docs/ is checked separately (summary docs may explain ctx_store for documentation purposes)
$docDir = Join-Path $repoRoot "docs"

$extensions = @("*.md", "*.yaml", "*.yml", "*.ps1", "*.json")

# -----------------------------------------------------------------------
# Test 1: No ctx_store authoring instructions in framework policy/config directories
# -----------------------------------------------------------------------
$t = "No ctx_store authoring instructions in framework files"
$found = @()

foreach ($dir in $searchDirs) {
    if (-not (Test-Path $dir)) { continue }
    foreach ($ext in $extensions) {
        $files = Get-ChildItem -Path $dir -Filter $ext -Recurse -File -ErrorAction SilentlyContinue
        foreach ($file in $files) {
            $fileContent = Get-Content $file.FullName -Raw -ErrorAction SilentlyContinue
            if ($fileContent -match "\bctx_store\b") {
                # Allow explanatory mentions (e.g. "Do NOT use ctx_store", "not ctx_store", "no ctx_store")
                # Flag only instructional usage (e.g. "use ctx_store to", "ctx_store <content>")
                $lines = $fileContent -split "`n"
                foreach ($line in $lines) {
                    if ($line -match "\bctx_store\b" -and
                        $line -notmatch "NOT use|do not use|instead of|incorrect|wrong|not ctx_store|no ctx_store") {
                        $found += "$($file.FullName): $line"
                    }
                }
            }
        }
    }
}

# In docs/ directory, only flag instructional usage (not "ctx_store does not exist" explanations)
if (Test-Path $docDir) {
    foreach ($ext in $extensions) {
        $files = Get-ChildItem -Path $docDir -Filter $ext -Recurse -File -ErrorAction SilentlyContinue
        foreach ($file in $files) {
            $fileContent = Get-Content $file.FullName -Raw -ErrorAction SilentlyContinue
            if ($fileContent -match "\bctx_store\b") {
                $lines = $fileContent -split "`n"
                foreach ($line in $lines) {
                    # In docs, only flag lines that instruct USE of ctx_store (not explanatory/negative mentions)
                    if ($line -match "\bctx_store\b" -and
                        $line -match "use ctx_store|run ctx_store|call ctx_store|ctx_store to store|via ctx_store" -and
                        $line -notmatch "NOT use|do not use|instead of|incorrect|wrong|no ctx_store|not ctx_store") {
                        $found += "$($file.FullName): $line"
                    }
                }
            }
        }
    }
}

if ($found.Count -eq 0) {
    Pass $t
} else {
    Fail $t "Found $($found.Count) instructional ctx_store reference(s):`n    $($found -join "`n    ")"
}

# -----------------------------------------------------------------------
# Test 2: context-mode.yaml defines ctx_index as the authoring tool
# -----------------------------------------------------------------------
$t = "context-mode.yaml: ctx_index defined as authoring tool"
$integrationFile = Join-Path $repoRoot ".mxagile\integrations\context-mode.yaml"
try {
    $content = Get-Content $integrationFile -Raw
    if ($content -match "authoring_tool" -and $content -match "\bctx_index\b") {
        Pass $t
    } else {
        Fail $t "context-mode.yaml does not define ctx_index as authoring tool"
    }
} catch {
    Fail $t "Could not read integration file: $_"
}

# -----------------------------------------------------------------------
# Test 3: mcp_tools.available in context-mode.yaml includes ctx_index
# -----------------------------------------------------------------------
$t = "context-mode.yaml: mcp_tools.available includes ctx_index"
try {
    $content = Get-Content $integrationFile -Raw
    if ($content -match "id: ctx_index") {
        Pass $t
    } else {
        Fail $t "mcp_tools.available does not include ctx_index entry"
    }
} catch {
    Fail $t "Could not read integration file: $_"
}

# -----------------------------------------------------------------------
# Test 4: ctx_index marked with mxagile_use: externalize_warm_context
# -----------------------------------------------------------------------
$t = "ctx_index has mxagile_use: externalize_warm_context"
try {
    $content = Get-Content $integrationFile -Raw
    if ($content -match "externalize_warm_context") {
        Pass $t
    } else {
        Fail $t "ctx_index does not have mxagile_use: externalize_warm_context"
    }
} catch {
    Fail $t "Could not read integration file: $_"
}

# -----------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------
Write-Host ""
Write-Host "Results: $pass passed, $fail failed" -ForegroundColor $(if ($fail -eq 0) { "Green" } else { "Red" })
if ($errors.Count -gt 0) {
    Write-Host ""
    foreach ($e in $errors) { Write-Host "  $e" -ForegroundColor Red }
}
Write-Host ""

exit $fail
