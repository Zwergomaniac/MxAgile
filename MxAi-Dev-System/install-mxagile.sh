#!/usr/bin/env bash
# install-mxagile.sh — MxAgile setup entry point for Linux / macOS / cloud-compute.
#
# This script is a thin invocation shim ONLY. It has zero MxAgile semantic knowledge.
# ALL installation semantics (project-state detection, INSTALL vs UPDATE, DFC-AI migration,
# project-knowledge preservation, provenance, Company Layers, reconciliation) live in
# mxagile-setup.ps1 (PowerShell Core).
#
# Usage:
#   bash install-mxagile.sh [options passed through to mxagile-setup.ps1]
#
#   Common options (forwarded unchanged to mxagile-setup.ps1):
#     -ProjectRoot <path>           Target Mendix project (default: current directory)
#     -DistributionSource <url|dir> MxAgile distribution Git URL or local path
#     -DistributionRef <ref>        Git branch/tag (default: main)
#     -NonInteractive               Skip confirmation prompt (CI/automation)
#
#   Example — fresh install from GitHub:
#     bash install-mxagile.sh -DistributionSource "https://github.com/your-org/mxagile.git"
#
#   Example — CI/headless (non-interactive):
#     bash install-mxagile.sh -NonInteractive -DistributionSource "https://..."
#
# Requirements:
#   - pwsh (PowerShell Core 7+)  — installed automatically if missing (with user confirmation)
#   - git                        — required only when acquiring distribution from a Git URL

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PS_SETUP="$SCRIPT_DIR/mxagile-setup.ps1"

# ---------------------------------------------------------------------------
# Locate pwsh
# ---------------------------------------------------------------------------
PWSH=""

for candidate in pwsh pwsh-lts; do
    if command -v "$candidate" > /dev/null 2>&1; then
        PWSH="$candidate"
        break
    fi
done

if [ -z "$PWSH" ]; then
    for fixed_path in /usr/bin/pwsh /usr/local/bin/pwsh /snap/bin/pwsh /opt/microsoft/powershell/7/pwsh; do
        if [ -x "$fixed_path" ]; then
            PWSH="$fixed_path"
            break
        fi
    done
fi

# ---------------------------------------------------------------------------
# If pwsh not found: print install instructions and exit
# ---------------------------------------------------------------------------
if [ -z "$PWSH" ]; then
    echo ""
    echo "=================================================================="
    echo "  MxAgile setup requires PowerShell Core (pwsh)"
    echo "=================================================================="
    echo ""
    echo "  pwsh was not found on PATH or at common install locations."
    echo "  Install it, then re-run this script."
    echo ""

    if [ -f /etc/debian_version ] || grep -qi ubuntu /etc/os-release 2>/dev/null; then
        echo "  Ubuntu / Debian:"
        echo "    sudo snap install powershell --classic"
        echo "    # OR (package-based):"
        echo "    # https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-linux"
    elif [ -f /etc/fedora-release ] || [ -f /etc/redhat-release ]; then
        echo "  Fedora / RHEL / CentOS:"
        echo "    # https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-linux"
    elif [ "$(uname)" = "Darwin" ]; then
        echo "  macOS:"
        echo "    brew install --cask powershell"
    else
        echo "  See: https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-linux"
    fi

    echo ""
    echo "  After installing pwsh, re-run:"
    echo "    bash install-mxagile.sh $*"
    echo "=================================================================="
    echo ""
    exit 1
fi

# ---------------------------------------------------------------------------
# Verify the PS setup script exists
# ---------------------------------------------------------------------------
if [ ! -f "$PS_SETUP" ]; then
    echo "ERROR: mxagile-setup.ps1 not found at: $PS_SETUP" >&2
    echo "       Ensure install-mxagile.sh is in the same directory as mxagile-setup.ps1." >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Delegate ALL work to mxagile-setup.ps1 — forward all arguments unchanged.
# exec replaces this shell process; the exit code from pwsh propagates directly.
# ---------------------------------------------------------------------------
exec "$PWSH" -NoProfile -ExecutionPolicy Bypass -File "$PS_SETUP" "$@"
