#!/usr/bin/env bash
set -euo pipefail

: "${MENDIX_BOOTSTRAP_USERNAME:?MENDIX_BOOTSTRAP_USERNAME must be set by the isolated runner}"
: "${MENDIX_BOOTSTRAP_PASSWORD:?MENDIX_BOOTSTRAP_PASSWORD must be set by the isolated runner}"
: "${PLAYWRIGHT_BASE_URL:?PLAYWRIGHT_BASE_URL must be set by the isolated runner}"

# Konfigurierbare Rollenliste des Demo-User-Switchers (Komma-getrennt).
# Default sind die CapTrack-Referenzrollen; andere Projekte setzen die Variable.
IFS=',' read -r -a DEMO_SWITCHER_ROLES <<< "${DEMO_SWITCHER_ROLES:-demo_administrator,demo_user,demo_NewSSOUser}"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
umask 077

# Uebergibt das auszuwertende Skript ueber eine Datei mit restriktiven Rechten
# statt als Kommandozeilenargument. Grund: ein Argument landet im Klartext in
# der Prozessliste (z.B. `ps aux`); eine 0600-Datei im eigenen temporaeren
# Verzeichnis nicht. Secrets werden zusaetzlich base64-kodiert und im Browser
# per atob() dekodiert, damit Sonderzeichen im Passwort den JS-Stringkontext
# nicht aufbrechen koennen (kein String-Interpolations-Risiko).
run_eval_from_stdin() {
  local script_file
  script_file="$(mktemp "$TMP_DIR/eval.XXXXXX.js")"
  cat > "$script_file"
  playwright-cli eval --file "$script_file"
}

b64() { printf '%s' "$1" | base64 | tr -d '\n'; }

USERNAME_B64="$(b64 "$MENDIX_BOOTSTRAP_USERNAME")"
PASSWORD_B64="$(b64 "$MENDIX_BOOTSTRAP_PASSWORD")"

playwright-cli open "$PLAYWRIGHT_BASE_URL"
playwright-cli eval "() => new Promise(resolve => setTimeout(resolve, 2500))"

login_ready="$(playwright-cli eval "() => document.querySelector('#usernameInput') !== null")"
[[ "$login_ready" == *true* ]] || { echo 'FAIL: login page did not load' >&2; exit 1; }

run_eval_from_stdin <<EOF
() => {
  const el = document.querySelector('#usernameInput');
  if (!el) throw new Error('username input not found');
  el.value = atob('${USERNAME_B64}');
  el.dispatchEvent(new Event('input', {bubbles: true}));
}
EOF

run_eval_from_stdin <<EOF
() => {
  const el = document.querySelector('#passwordInput');
  if (!el) throw new Error('password input not found');
  el.value = atob('${PASSWORD_B64}');
  el.dispatchEvent(new Event('input', {bubbles: true}));
}
EOF

playwright-cli eval "() => { const button = document.querySelector('#loginButton'); if (!button) throw new Error('login button not found'); button.click(); }"
playwright-cli eval "() => new Promise(resolve => setTimeout(resolve, 3500))"

login_complete="$(playwright-cli eval "() => document.querySelector('#loginButton') === null")"
[[ "$login_complete" == *true* ]] || { echo 'FAIL: bootstrap login did not complete' >&2; exit 1; }

# JS-Array-Literal aus der konfigurierbaren Rollenliste bauen (einfache
# Escapierung fuer eingebettete Anfuehrungszeichen in Rollennamen).
roles_js="["
for role in "${DEMO_SWITCHER_ROLES[@]}"; do
  escaped_role="$(printf '%s' "$role" | sed "s/'/\\\\'/g")"
  roles_js+="'${escaped_role}',"
done
roles_js+="]"

switcher_ready="$(playwright-cli eval "() => { const text = document.body.innerText; return (${roles_js}).every(label => text.includes(label)); }")"
[[ "$switcher_ready" == *true* ]] || { echo 'FAIL: demo user switcher is incomplete' >&2; exit 1; }

playwright-cli screenshot
playwright-cli close
printf 'PASS: demo user switcher is visible after dynamic bootstrap login\n'
