#!/usr/bin/env bash
# mx-scroll-shell.sh — MxAgile Mendix-aware scroll helpers for playwright-cli .test.sh scripts.
#
# Source this file at the top of any verify-*.test.sh script that needs to scroll
# Mendix application content:
#
#   source "$(dirname "$0")/../.playwright/helpers/mx-scroll-shell.sh"
#
# All functions use playwright-cli eval to run JS in the browser context.
# playwright-cli must be open (playwright-cli open <url>) before calling these.
#
# The key insight: standard browser-level scrolling (window.scrollTo, document.body.scrollTop)
# does not move Mendix application content. Mendix places content in a nested scrollable
# container such as .mx-scrollcontainer-center. Setting scrollTop on the browser document
# executes without error but leaves the visible viewport unchanged — producing repeated
# screenshots of the same page section.

# ─── Configuration ─────────────────────────────────────────────────────────────

# Milliseconds to wait after each scroll for dynamic content (charts, grids) to render.
# Override in the calling script: MX_SCROLL_SETTLE_MS=500
: "${MX_SCROLL_SETTLE_MS:=300}"

# ─── mx_scroll_discover ─────────────────────────────────────────────────────────
#
# Discover the primary Mendix scroll container and print diagnostics to stdout.
# Output is a colon-separated line:  METHOD:SELECTOR:SCROLL_HEIGHT:CLIENT_HEIGHT:SCROLL_TOP
# or the literal string:             NOT_FOUND
#
# Example output:
#   known_selector:.mx-scrollcontainer-center:5201:720:0
#
mx_scroll_discover() {
  playwright-cli eval "$(cat <<'JSFN'
() => {
  const known = [
    '.mx-scrollcontainer-center',
    '.mx-scrollcontainer-main',
    '.mx-page-content',
  ];
  for (const sel of known) {
    const el = document.querySelector(sel);
    if (el) {
      const oy = getComputedStyle(el).overflowY;
      const scrollable = (oy === 'auto' || oy === 'scroll') && el.scrollHeight > el.clientHeight;
      return ['known_selector', sel, el.scrollHeight, el.clientHeight, el.scrollTop, scrollable ? '1' : '0'].join(':');
    }
  }
  const candidates = [];
  for (const el of document.querySelectorAll('*')) {
    const oy = getComputedStyle(el).overflowY;
    if ((oy === 'auto' || oy === 'scroll') && el.scrollHeight > el.clientHeight) {
      candidates.push({ el, score: (el.scrollHeight - el.clientHeight) * el.clientWidth });
    }
  }
  if (candidates.length > 0) {
    candidates.sort((a, b) => b.score - a.score);
    const best = candidates[0];
    const id  = best.el.id ? '#' + best.el.id : '';
    const cls = Array.from(best.el.classList).slice(0, 3).map(c => '.' + c).join('');
    const diagSel = best.el.tagName.toLowerCase() + id + cls;
    return ['dynamic_fallback', diagSel || 'unknown', best.el.scrollHeight, best.el.clientHeight, best.el.scrollTop, '1'].join(':');
  }
  const doc = document.documentElement;
  if (doc.scrollHeight > doc.clientHeight) {
    return ['document_fallback', 'document', doc.scrollHeight, doc.clientHeight, doc.scrollTop, '1'].join(':');
  }
  return 'NOT_FOUND';
}
JSFN
)"
}

# ─── mx_scroll ──────────────────────────────────────────────────────────────────
#
# Scroll the primary Mendix scroll container to a deterministic position.
#
# Usage:   mx_scroll <position_px>
# Returns: exit 0 on success (SCROLLED, ALREADY_AT_POSITION, CLAMPED_TO_MAX)
#          exit 1 on failure (SCROLL_NOT_EFFECTIVE, NO_SCROLL_CONTAINER)
#
# Prints one of:
#   SCROLLED:<actual_pos>
#   ALREADY_AT_POSITION:<pos>
#   CLAMPED_TO_MAX:<max>
#   NO_SCROLL_CONTAINER
#   SCROLL_NOT_EFFECTIVE:<expected>:<actual>
#
mx_scroll() {
  local position="${1:?mx_scroll requires a position argument}"

  local result
  result="$(playwright-cli eval "$(cat <<JSFN
() => {
  const pos = ${position};
  const known = [
    '.mx-scrollcontainer-center',
    '.mx-scrollcontainer-main',
    '.mx-page-content',
  ];

  let el = null;

  for (const sel of known) {
    const found = document.querySelector(sel);
    if (found) { el = found; break; }
  }

  if (!el) {
    // Dynamic fallback
    const candidates = [];
    for (const candidate of document.querySelectorAll('*')) {
      const oy = getComputedStyle(candidate).overflowY;
      if ((oy === 'auto' || oy === 'scroll') && candidate.scrollHeight > candidate.clientHeight) {
        candidates.push({ el: candidate, score: (candidate.scrollHeight - candidate.clientHeight) * candidate.clientWidth });
      }
    }
    if (candidates.length > 0) {
      candidates.sort((a, b) => b.score - a.score);
      el = candidates[0].el;
    }
  }

  if (!el) {
    const doc = document.documentElement;
    if (doc.scrollHeight > doc.clientHeight) {
      el = doc;
    }
  }

  if (!el) return 'NO_SCROLL_CONTAINER';

  const maxScrollTop = Math.max(0, el.scrollHeight - el.clientHeight);
  const clamped      = Math.max(0, Math.min(pos, maxScrollTop));
  const wasClamped   = pos > 0 && clamped < pos;
  const before       = el.scrollTop;

  el.scrollTop = clamped;

  const after = el.scrollTop;

  if (wasClamped)                    return 'CLAMPED_TO_MAX:' + after;
  if (Math.abs(after - clamped) > 1) return 'SCROLL_NOT_EFFECTIVE:' + clamped + ':' + after;
  if (Math.abs(after - before)  < 1) return 'ALREADY_AT_POSITION:' + after;
  return 'SCROLLED:' + after;
}
JSFN
)")"

  echo "$result"

  # Wait for rendering to stabilize
  playwright-cli eval "() => new Promise(resolve => setTimeout(resolve, ${MX_SCROLL_SETTLE_MS}))"

  case "$result" in
    SCROLL_NOT_EFFECTIVE*|NO_SCROLL_CONTAINER) return 1 ;;
    *)                                         return 0 ;;
  esac
}

# ─── mx_element_scroll ──────────────────────────────────────────────────────────
#
# Scroll a specific element into view using scrollIntoView().
#
# Use for targeted component verification (e.g. scroll to a known form field).
# Use mx_scroll for systematic viewport-by-viewport page coverage instead.
#
# Usage:   mx_element_scroll '.mx-name-btnSave'
# Returns: exit 0 if element found and scrolled; exit 1 if element not found.
#
mx_element_scroll() {
  local selector="${1:?mx_element_scroll requires a CSS selector}"

  local result
  result="$(playwright-cli eval "$(cat <<JSFN
() => {
  const el = document.querySelector('${selector//\'/\\\'}');
  if (!el) return 'NOT_FOUND';
  el.scrollIntoView({ behavior: 'instant', block: 'start' });
  const rect = el.getBoundingClientRect();
  const inView = rect.top >= 0 && rect.bottom <= window.innerHeight;
  return 'IN_VIEW:' + (inView ? '1' : '0') + ':' + Math.round(rect.top);
}
JSFN
)")"

  echo "$result"

  playwright-cli eval "() => new Promise(resolve => setTimeout(resolve, ${MX_SCROLL_SETTLE_MS}))"

  case "$result" in
    NOT_FOUND) return 1 ;;
    *)         return 0 ;;
  esac
}

# ─── mx_viewport_coverage ───────────────────────────────────────────────────────
#
# Print suggested scroll stops for full-page screenshot coverage.
# Output is a space-separated list of scrollTop values derived from runtime dimensions.
#
# Usage:   stops="$(mx_viewport_coverage)"
# Then:    for stop in $stops; do mx_scroll "$stop" && playwright-cli screenshot; done
#
mx_viewport_coverage() {
  playwright-cli eval "$(cat <<'JSFN'
() => {
  const known = [
    '.mx-scrollcontainer-center',
    '.mx-scrollcontainer-main',
    '.mx-page-content',
  ];

  let el = null;
  for (const sel of known) {
    const found = document.querySelector(sel);
    if (found) { el = found; break; }
  }
  if (!el) {
    const candidates = [];
    for (const candidate of document.querySelectorAll('*')) {
      const oy = getComputedStyle(candidate).overflowY;
      if ((oy === 'auto' || oy === 'scroll') && candidate.scrollHeight > candidate.clientHeight) {
        candidates.push({ el: candidate, score: (candidate.scrollHeight - candidate.clientHeight) * candidate.clientWidth });
      }
    }
    if (candidates.length > 0) {
      candidates.sort((a, b) => b.score - a.score);
      el = candidates[0].el;
    }
  }
  if (!el) {
    const doc = document.documentElement;
    if (doc.scrollHeight > doc.clientHeight) el = doc;
  }
  if (!el || el.scrollHeight <= el.clientHeight) return '0';

  const viewportH  = el.clientHeight;
  const maxScrollTop = el.scrollHeight - viewportH;
  const stepSize   = Math.floor(viewportH * 0.9);
  const minGap     = Math.floor(viewportH * 0.1);

  const stops = [];
  let pos = 0;
  while (pos < maxScrollTop) {
    stops.push(pos);
    pos += stepSize;
  }
  const lastStop = stops[stops.length - 1] || 0;
  if (maxScrollTop - lastStop > minGap) stops.push(maxScrollTop);

  return stops.join(' ');
}
JSFN
)"
}
