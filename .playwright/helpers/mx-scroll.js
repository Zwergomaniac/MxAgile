'use strict';

/**
 * MxAgile Mendix-aware scroll helper for @playwright/test.
 *
 * Standard browser-level scrolling (window.scrollTo, document.body.scrollTop) does not move
 * Mendix application content. Mendix/Atlas places the primary page content in an independently
 * scrollable layout container — typically .mx-scrollcontainer-center. Setting scrollTop on the
 * browser document succeeds without error but leaves the visible viewport unchanged.
 *
 * Usage in a @playwright/test spec:
 *   const { discoverScrollContainer, mxScroll, mxScrollToElement, mxViewportCoverage, RESULT } = require('../helpers/mx-scroll');
 */

// ─── Result codes ─────────────────────────────────────────────────────────────

const RESULT = Object.freeze({
  SCROLLED:             'SCROLLED',
  ALREADY_AT_POSITION:  'ALREADY_AT_POSITION',
  CLAMPED_TO_MAX:       'CLAMPED_TO_MAX',
  NO_SCROLL_CONTAINER:  'NO_SCROLL_CONTAINER',
  SCROLL_NOT_EFFECTIVE: 'SCROLL_NOT_EFFECTIVE',
});

// ─── Known Mendix primary-content selectors (checked in order) ────────────────

const KNOWN_MENDIX_SELECTORS = [
  '.mx-scrollcontainer-center',
  '.mx-scrollcontainer-main',
  '.mx-page-content',
];

const DEFAULT_SETTLE_MS = 300;

// ─── Discovery ────────────────────────────────────────────────────────────────

/**
 * Discover the primary Mendix application scroll container.
 *
 * Priority:
 *   1. Known Mendix selectors (.mx-scrollcontainer-center, etc.)
 *   2. Dynamic fallback: element with overflow-y auto|scroll and the largest
 *      scrollable area (scrollHeight - clientHeight) × clientWidth, which
 *      biases toward the wide main-content column rather than narrow sidebars.
 *   3. document.documentElement if the page document itself scrolls.
 *   4. Not found — page requires no scrolling.
 *
 * Returns a serializable diagnostics object:
 *   { found, method, selector, scrollHeight, clientHeight, scrollTop, isScrollable, candidateCount }
 */
async function discoverScrollContainer(page) {
  return page.evaluate(() => {
    const knownSelectors = [
      '.mx-scrollcontainer-center',
      '.mx-scrollcontainer-main',
      '.mx-page-content',
    ];

    for (const sel of knownSelectors) {
      const el = document.querySelector(sel);
      if (el) {
        const oy = getComputedStyle(el).overflowY;
        return {
          found: true,
          method: 'known_selector',
          selector: sel,
          scrollHeight: el.scrollHeight,
          clientHeight: el.clientHeight,
          scrollTop: el.scrollTop,
          isScrollable: (oy === 'auto' || oy === 'scroll') && el.scrollHeight > el.clientHeight,
          candidateCount: 1,
        };
      }
    }

    // Dynamic fallback: inspect all elements for actual scrollability.
    const candidates = [];
    for (const el of document.querySelectorAll('*')) {
      const oy = getComputedStyle(el).overflowY;
      if ((oy === 'auto' || oy === 'scroll') && el.scrollHeight > el.clientHeight) {
        candidates.push({
          el,
          // Bias toward the largest-area main-content column, not narrow sidebars.
          score: (el.scrollHeight - el.clientHeight) * el.clientWidth,
        });
      }
    }

    if (candidates.length > 0) {
      candidates.sort((a, b) => b.score - a.score);
      const best = candidates[0];
      const id    = best.el.id ? '#' + best.el.id : '';
      const cls   = Array.from(best.el.classList).slice(0, 3).map(c => '.' + c).join('');
      const diagSel = best.el.tagName.toLowerCase() + id + cls || 'unknown';
      return {
        found: true,
        method: 'dynamic_fallback',
        selector: diagSel,
        scrollHeight: best.el.scrollHeight,
        clientHeight: best.el.clientHeight,
        scrollTop: best.el.scrollTop,
        isScrollable: true,
        candidateCount: candidates.length,
      };
    }

    // Last resort: document element
    const doc = document.documentElement;
    if (doc.scrollHeight > doc.clientHeight) {
      return {
        found: true,
        method: 'document_fallback',
        selector: 'document',
        scrollHeight: doc.scrollHeight,
        clientHeight: doc.clientHeight,
        scrollTop: doc.scrollTop,
        isScrollable: true,
        candidateCount: 0,
      };
    }

    return {
      found: false,
      method: 'none',
      selector: null,
      scrollHeight: 0,
      clientHeight: 0,
      scrollTop: 0,
      isScrollable: false,
      candidateCount: 0,
    };
  });
}

// ─── Positional scroll ────────────────────────────────────────────────────────

/**
 * Scroll the primary Mendix content container to a deterministic position.
 *
 * @param {import('@playwright/test').Page} page
 * @param {number} position  - Target scrollTop in pixels.
 * @param {object} [options]
 * @param {number} [options.settleMs=300]    - Milliseconds to wait after scroll for rendering.
 * @param {object} [options.container=null]  - Pre-discovered container info (avoids re-discovery).
 *
 * Returns:
 *   { result, requestedPosition, actualPosition, maxScrollTop?, container, error? }
 *
 * Result codes:
 *   SCROLLED             — scroll succeeded and position changed as expected.
 *   ALREADY_AT_POSITION  — container was already at the requested position.
 *   CLAMPED_TO_MAX       — requested position exceeded scrollable range; clamped.
 *   NO_SCROLL_CONTAINER  — no scrollable container found.
 *   SCROLL_NOT_EFFECTIVE — setting scrollTop did not move the container
 *                          (e.g., overflow:hidden or browser restriction).
 *
 * Callers MUST check result !== SCROLL_NOT_EFFECTIVE and result !== NO_SCROLL_CONTAINER
 * before treating a screenshot as evidence of a new viewport section.
 */
async function mxScroll(page, position, options = {}) {
  const { settleMs = DEFAULT_SETTLE_MS, container = null } = options;

  const info = container || await discoverScrollContainer(page);

  if (!info.found) {
    return {
      result: RESULT.NO_SCROLL_CONTAINER,
      requestedPosition: position,
      actualPosition: 0,
      container: info,
    };
  }

  // All scroll logic executes inside a single synchronous browser evaluate so we can
  // check the actual resulting scrollTop before returning.
  const scrollResult = await page.evaluate(({ method, sel, pos }) => {
    let el;
    if (method === 'document_fallback') {
      el = document.documentElement;
    } else if (method === 'dynamic_fallback') {
      // Re-run scoring to find the same element without storing a DOM reference.
      const candidates = [];
      for (const candidate of document.querySelectorAll('*')) {
        const oy = getComputedStyle(candidate).overflowY;
        if ((oy === 'auto' || oy === 'scroll') && candidate.scrollHeight > candidate.clientHeight) {
          candidates.push({
            el: candidate,
            score: (candidate.scrollHeight - candidate.clientHeight) * candidate.clientWidth,
          });
        }
      }
      if (!candidates.length) return { ok: false, error: 'no_dynamic_candidates', before: 0, after: 0, maxScrollTop: 0, clamped: pos };
      candidates.sort((a, b) => b.score - a.score);
      el = candidates[0].el;
    } else {
      el = document.querySelector(sel);
    }

    if (!el) return { ok: false, error: 'element_not_found', before: 0, after: 0, maxScrollTop: 0, clamped: pos };

    const maxScrollTop = Math.max(0, el.scrollHeight - el.clientHeight);
    const clamped      = Math.max(0, Math.min(pos, maxScrollTop));
    const wasClamped   = pos > 0 && clamped < pos;
    const before       = el.scrollTop;

    el.scrollTop = clamped;

    const after = el.scrollTop;
    return { ok: true, before, after, clamped, wasClamped, maxScrollTop };
  }, { method: info.method, sel: info.selector, pos: position });

  if (!scrollResult.ok) {
    return {
      result: RESULT.NO_SCROLL_CONTAINER,
      requestedPosition: position,
      actualPosition: scrollResult.after,
      container: info,
      error: scrollResult.error,
    };
  }

  // Wait for rendering to stabilize before caller takes a screenshot.
  if (settleMs > 0) await page.waitForTimeout(settleMs);

  const { before, after, clamped, wasClamped, maxScrollTop } = scrollResult;

  if (wasClamped) {
    return {
      result: RESULT.CLAMPED_TO_MAX,
      requestedPosition: position,
      actualPosition: after,
      maxScrollTop,
      container: info,
    };
  }

  // Detect ineffective scroll: scrollTop did not reach the expected position.
  // Tolerance of 1px accommodates sub-pixel rounding.
  if (Math.abs(after - clamped) > 1) {
    return {
      result: RESULT.SCROLL_NOT_EFFECTIVE,
      requestedPosition: position,
      expectedPosition: clamped,
      actualPosition: after,
      maxScrollTop,
      container: info,
    };
  }

  if (Math.abs(after - before) < 1) {
    return {
      result: RESULT.ALREADY_AT_POSITION,
      requestedPosition: position,
      actualPosition: after,
      container: info,
    };
  }

  return {
    result: RESULT.SCROLLED,
    requestedPosition: position,
    actualPosition: after,
    container: info,
  };
}

// ─── Element-based scroll ─────────────────────────────────────────────────────

/**
 * Scroll a specific element into view.
 *
 * Use this for targeted component verification where a precise scrollTop is not
 * needed — for example, scrolling to a form field or a specific grid row.
 *
 * For systematic viewport coverage of a long page, use mxScroll() with stops
 * from mxViewportCoverage() instead.
 *
 * @param {import('@playwright/test').Page} page
 * @param {string} selector  - CSS selector of the target element.
 * @param {object} [options]
 * @param {number}  [options.settleMs=300]   - Milliseconds to wait after scroll.
 * @param {string}  [options.block='start']  - Vertical alignment: 'start'|'center'|'end'|'nearest'.
 *
 * Returns: { ok, selector, inView, top, bottom }
 */
async function mxScrollToElement(page, selector, options = {}) {
  const { settleMs = DEFAULT_SETTLE_MS, block = 'start' } = options;

  const result = await page.evaluate(({ sel, block }) => {
    const el = document.querySelector(sel);
    if (!el) return { ok: false };
    el.scrollIntoView({ behavior: 'instant', block });
    const rect = el.getBoundingClientRect();
    return {
      ok: true,
      inView: rect.top >= 0 && rect.bottom <= window.innerHeight,
      top: rect.top,
      bottom: rect.bottom,
    };
  }, { sel: selector, block });

  if (settleMs > 0) await page.waitForTimeout(settleMs);

  return { ok: result.ok, selector, inView: result.inView ?? false, top: result.top, bottom: result.bottom };
}

// ─── Viewport coverage ────────────────────────────────────────────────────────

/**
 * Calculate screenshot stops for full visual coverage of a long Mendix page.
 *
 * Stops are derived from the ACTUAL runtime container dimensions, never hardcoded.
 * Each stop represents a scrollTop value from which a viewport-sized screenshot
 * captures a distinct section of the page.
 *
 * A 10% overlap between adjacent screenshots prevents content at viewport edges
 * from being missed. The final stop is omitted if it would be too close
 * (< 10% of viewport height) to the previous stop, avoiding a near-duplicate
 * screenshot at the very bottom.
 *
 * @param {import('@playwright/test').Page} page
 * @param {object} [options]
 * @param {number} [options.overlapFraction=0.1]  - Fractional viewport overlap (0–0.5).
 *
 * Returns:
 *   { container, scrollHeight, viewportHeight, maxScrollTop, suggestedStops }
 */
async function mxViewportCoverage(page, options = {}) {
  const { overlapFraction = 0.1 } = options;

  const info = await discoverScrollContainer(page);

  if (!info.found || !info.isScrollable || info.scrollHeight <= info.clientHeight) {
    return {
      container: info.selector ?? 'none',
      scrollHeight: info.scrollHeight,
      viewportHeight: info.clientHeight,
      maxScrollTop: 0,
      suggestedStops: [0],
    };
  }

  const viewportHeight = info.clientHeight;
  const scrollHeight   = info.scrollHeight;
  const maxScrollTop   = scrollHeight - viewportHeight;
  const stepSize       = Math.floor(viewportHeight * (1 - overlapFraction));
  const minGap         = Math.floor(viewportHeight * overlapFraction);

  const stops = [];
  let pos = 0;
  while (pos < maxScrollTop) {
    stops.push(pos);
    pos += stepSize;
  }

  // Add final stop at maxScrollTop unless it is already covered (< minGap away from last stop).
  const lastStop = stops[stops.length - 1] ?? 0;
  if (maxScrollTop - lastStop > minGap) {
    stops.push(maxScrollTop);
  }

  return {
    container: info.selector,
    scrollHeight,
    viewportHeight,
    maxScrollTop,
    suggestedStops: stops,
  };
}

// ─── Exports ──────────────────────────────────────────────────────────────────

module.exports = {
  RESULT,
  KNOWN_MENDIX_SELECTORS,
  DEFAULT_SETTLE_MS,
  discoverScrollContainer,
  mxScroll,
  mxScrollToElement,
  mxViewportCoverage,
};
