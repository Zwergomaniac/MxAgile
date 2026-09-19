#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-0.1.15}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_PATH="${ROOT_DIR}/.playwright/cli.config.json"

find_command() {
  local candidate
  for candidate in "$@"; do
    if command -v "$candidate" >/dev/null 2>&1; then
      command -v "$candidate"
      return 0
    fi
  done
  return 1
}

NODE="$(find_command node nodejs || true)"
NPM="$(find_command npm npm.cmd || true)"
[[ -n "$NODE" ]] || { echo 'Node.js was not found. Install Node.js 22+ or open the project devcontainer.' >&2; exit 1; }
[[ -n "$NPM" ]] || { echo 'npm was not found. Install npm with Node.js or open the project devcontainer.' >&2; exit 1; }

PLAYWRIGHT="$(find_command playwright-cli playwright-cli.cmd || true)"
if [[ -z "$PLAYWRIGHT" ]]; then
  "$NPM" install --global "@playwright/cli@${VERSION}"
  PLAYWRIGHT="$(find_command playwright-cli playwright-cli.cmd || true)"
fi
[[ -n "$PLAYWRIGHT" ]] || { echo 'playwright-cli is still not available after installation.' >&2; exit 1; }

NPM_ROOT="$("$NPM" root --global)"
CORE="${NPM_ROOT}/@playwright/cli/node_modules/playwright-core/cli.js"
[[ -f "$CORE" ]] || { echo "Bundled playwright-core was not found at ${CORE}." >&2; exit 1; }
"$NODE" "$CORE" install chromium chromium-headless-shell

if [[ -f "$CONFIG_PATH" ]] && grep -q '"executablePath"' "$CONFIG_PATH"; then
  if [[ ! -e /usr/local/bin/mx-headless-shell ]]; then
    sed -i '/"executablePath"/d' "$CONFIG_PATH"
  fi
fi

printf 'playwright-cli ready: %s\n' "$PLAYWRIGHT"
printf 'playwright-core ready: %s\n' "$CORE"
printf 'Chromium browser binaries ready.\n'
