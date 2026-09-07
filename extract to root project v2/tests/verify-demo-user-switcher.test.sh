#!/usr/bin/env bash
set -euo pipefail

: "${MENDIX_BOOTSTRAP_USERNAME:?MENDIX_BOOTSTRAP_USERNAME must be set by the isolated runner}"
: "${MENDIX_BOOTSTRAP_PASSWORD:?MENDIX_BOOTSTRAP_PASSWORD must be set by the isolated runner}"
: "${PLAYWRIGHT_BASE_URL:?PLAYWRIGHT_BASE_URL must be set by the isolated runner}"

playwright-cli open "$PLAYWRIGHT_BASE_URL"
playwright-cli eval "() => new Promise(resolve => setTimeout(resolve, 2500))"
login_ready="$(playwright-cli eval "() => document.querySelector('#usernameInput') !== null")"
[[ "$login_ready" == *true* ]] || { echo 'FAIL: login page did not load' >&2; exit 1; }
playwright-cli eval "() => { const el = document.querySelector('#usernameInput'); if (!el) throw new Error('username input not found'); el.value = '${MENDIX_BOOTSTRAP_USERNAME}'; el.dispatchEvent(new Event('input', {bubbles: true})); }"
playwright-cli eval "() => { const el = document.querySelector('#passwordInput'); if (!el) throw new Error('password input not found'); el.value = '${MENDIX_BOOTSTRAP_PASSWORD}'; el.dispatchEvent(new Event('input', {bubbles: true})); }"
playwright-cli eval "() => { const button = document.querySelector('#loginButton'); if (!button) throw new Error('login button not found'); button.click(); }"
playwright-cli eval "() => new Promise(resolve => setTimeout(resolve, 3500))"
login_complete="$(playwright-cli eval "() => document.querySelector('#loginButton') === null")"
[[ "$login_complete" == *true* ]] || { echo 'FAIL: bootstrap login did not complete' >&2; exit 1; }
switcher_ready="$(playwright-cli eval "() => { const text = document.body.innerText; return ['demo_administrator', 'demo_user', 'demo_NewSSOUser'].every(label => text.includes(label)); }")"
[[ "$switcher_ready" == *true* ]] || { echo 'FAIL: demo user switcher is incomplete' >&2; exit 1; }
playwright-cli screenshot
playwright-cli close
printf 'PASS: demo user switcher is visible after dynamic bootstrap login\n'
