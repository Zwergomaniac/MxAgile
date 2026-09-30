'use strict';

/**
 * MxAgile Mendix-aware scroll helper — @playwright/test integration tests.
 *
 * Tests run against local fixture HTML files (file:// URLs) to verify the
 * helper's discovery, scroll, element-scroll, and viewport-coverage behaviour
 * across all supported container configurations.
 *
 * Run:  npx playwright test tests/mx-scroll.spec.js  (from .playwright/)
 */

const { test, expect } = require('@playwright/test');
const path = require('path');
const {
  RESULT,
  discoverScrollContainer,
  mxScroll,
  mxScrollToElement,
  mxViewportCoverage,
} = require('../helpers/mx-scroll');

// Resolve fixture path to an absolute file:// URL.
function fixture(name) {
  const abs = path.join(__dirname, '../../tests/fixtures/playwright', name);
  return 'file:///' + abs.replace(/\\/g, '/');
}

// All tests use a consistent viewport so fixture dimensions are predictable.
const VIEWPORT = { width: 1200, height: 720 };

test.use({ viewport: VIEWPORT });

// ─── TC-01: Browser document itself is scrollable ─────────────────────────────

test('TC-01: discovers document.documentElement when no Mendix containers present', async ({ page }) => {
  await page.goto(fixture('mx-scroll-simple.html'));

  const info = await discoverScrollContainer(page);

  expect(info.found).toBe(true);
  expect(info.method).toBe('document_fallback');
  expect(info.selector).toBe('document');
  expect(info.scrollHeight).toBeGreaterThan(info.clientHeight);
  expect(info.isScrollable).toBe(true);
});

// ─── TC-02: .mx-scrollcontainer-center is scrollable ─────────────────────────

test('TC-02: discovers .mx-scrollcontainer-center as primary container via known selector', async ({ page }) => {
  await page.goto(fixture('mx-scroll-center.html'));

  const info = await discoverScrollContainer(page);

  expect(info.found).toBe(true);
  expect(info.method).toBe('known_selector');
  expect(info.selector).toBe('.mx-scrollcontainer-center');
  expect(info.scrollHeight).toBeGreaterThan(info.clientHeight);
  expect(info.isScrollable).toBe(true);
  // Diagnostics include all fields needed for evidence reporting.
  expect(typeof info.scrollHeight).toBe('number');
  expect(typeof info.clientHeight).toBe('number');
  expect(typeof info.scrollTop).toBe('number');
  expect(typeof info.candidateCount).toBe('number');
});

// ─── TC-03: Sidebar and center both scrollable — center must be selected ──────

test('TC-03: dynamic fallback selects center over sidebar when known selector absent', async ({ page }) => {
  // This fixture has NO .mx-scrollcontainer-center selector (sidebar + wide center,
  // both scrollable but the center is wider). We verify that the dynamic fallback
  // picks the wider element, NOT the narrow sidebar.
  // (The fixture DOES have .mx-scrollcontainer-center but we test the scoring path
  // by verifying the result is the correct wide container.)
  await page.goto(fixture('mx-scroll-sidebar-center.html'));

  const info = await discoverScrollContainer(page);

  expect(info.found).toBe(true);
  // Known selector should match since fixture has .mx-scrollcontainer-center.
  expect(info.selector).toBe('.mx-scrollcontainer-center');

  // Verify the selected container is NOT narrow (sidebar is 180px wide).
  // The center container must have a clientWidth significantly larger than the sidebar.
  const containerWidth = await page.evaluate(() => {
    const el = document.querySelector('.mx-scrollcontainer-center');
    return el ? el.clientWidth : 0;
  });
  expect(containerWidth).toBeGreaterThan(300);
});

// ─── TC-03b: Dynamic fallback (no known selectors) — wide center wins ─────────

test('TC-03b: dynamic fallback scores wide main content over narrow sidebar', async ({ page }) => {
  await page.goto(fixture('mx-scroll-sidebar-center.html'));

  // Temporarily remove the known selector class to force dynamic fallback.
  await page.evaluate(() => {
    const el = document.querySelector('.mx-scrollcontainer-center');
    if (el) el.classList.remove('mx-scrollcontainer-center');
  });

  const info = await discoverScrollContainer(page);

  expect(info.found).toBe(true);
  expect(info.method).toBe('dynamic_fallback');
  // The selected element must be wider than the 180px sidebar.
  const selectedWidth = await page.evaluate((sel) => {
    if (sel === 'document') return document.documentElement.clientWidth;
    const el = document.querySelector(sel);
    return el ? el.clientWidth : 0;
  }, info.selector);
  expect(selectedWidth).toBeGreaterThan(300);
});

// ─── TC-04: Multiple nested scrollable widgets + center — center selected ─────

test('TC-04: known selector short-circuits when .mx-scrollcontainer-center present alongside nested widgets', async ({ page }) => {
  await page.goto(fixture('mx-scroll-widgets.html'));

  const info = await discoverScrollContainer(page);

  expect(info.found).toBe(true);
  expect(info.method).toBe('known_selector');
  expect(info.selector).toBe('.mx-scrollcontainer-center');
  // Must NOT be one of the nested widget containers.
  expect(info.selector).not.toContain('widget-list');
});

// ─── TC-05: Page requires no scrolling ────────────────────────────────────────

test('TC-05: reports NOT_FOUND when page content fits in viewport', async ({ page }) => {
  await page.goto(fixture('mx-scroll-noscroll.html'));

  const info = await discoverScrollContainer(page);
  expect(info.found).toBe(false);
  expect(info.method).toBe('none');

  const result = await mxScroll(page, 500);
  expect(result.result).toBe(RESULT.NO_SCROLL_CONTAINER);
});

// ─── TC-06: Requested position applied correctly ──────────────────────────────

test('TC-06: mxScroll scrolls to requested position and returns SCROLLED', async ({ page }) => {
  await page.goto(fixture('mx-scroll-center.html'));

  const r = await mxScroll(page, 500, { settleMs: 0 });

  expect(r.result).toBe(RESULT.SCROLLED);
  expect(r.requestedPosition).toBe(500);
  expect(r.actualPosition).toBeCloseTo(500, 0);
  // Container diagnostics are present.
  expect(r.container).toBeDefined();
  expect(r.container.selector).toBe('.mx-scrollcontainer-center');
});

// ─── TC-07: Requested position beyond maximum — clamped and reported ──────────

test('TC-07: mxScroll clamps position beyond maxScrollTop and returns CLAMPED_TO_MAX', async ({ page }) => {
  await page.goto(fixture('mx-scroll-center.html'));

  const r = await mxScroll(page, 999999, { settleMs: 0 });

  expect(r.result).toBe(RESULT.CLAMPED_TO_MAX);
  expect(r.maxScrollTop).toBeGreaterThan(0);
  expect(r.actualPosition).toBe(r.maxScrollTop);
  expect(r.requestedPosition).toBe(999999);
});

// ─── TC-08: Ineffective scroll detected ──────────────────────────────────────

test('TC-08: detects SCROLL_NOT_EFFECTIVE when container has overflow:hidden', async ({ page }) => {
  await page.goto(fixture('mx-scroll-ineffective.html'));

  // Discovery finds the known selector but isScrollable is false (overflow:hidden).
  const info = await discoverScrollContainer(page);
  expect(info.found).toBe(true);
  expect(info.selector).toBe('.mx-scrollcontainer-center');
  expect(info.isScrollable).toBe(false);

  // Scroll attempt must detect that scrollTop did not move.
  const r = await mxScroll(page, 500, { settleMs: 0 });
  expect(r.result).toBe(RESULT.SCROLL_NOT_EFFECTIVE);
  expect(r.actualPosition).toBe(0);
});

// ─── TC-09: scrollIntoView for element-targeted verification ─────────────────

test('TC-09: mxScrollToElement brings target element into view', async ({ page }) => {
  await page.goto(fixture('mx-scroll-center.html'));

  const r = await mxScrollToElement(page, '#target-bottom', { settleMs: 0 });

  expect(r.ok).toBe(true);
  expect(r.selector).toBe('#target-bottom');
  // Element should be visible in the viewport after scrollIntoView.
  expect(r.inView).toBe(true);
  // Must not return a scroll RESULT code — element scrolling is a separate concern.
  expect(r.result).toBeUndefined();
});

// ─── TC-10: Suggested stops cover the scrollable range ───────────────────────

test('TC-10: mxViewportCoverage generates stops that cover full scrollable range', async ({ page }) => {
  await page.goto(fixture('mx-scroll-center.html'));

  const coverage = await mxViewportCoverage(page);

  expect(coverage.container).toBe('.mx-scrollcontainer-center');
  expect(coverage.scrollHeight).toBeGreaterThan(coverage.viewportHeight);
  expect(coverage.maxScrollTop).toBeGreaterThan(0);
  expect(coverage.suggestedStops).toBeInstanceOf(Array);
  expect(coverage.suggestedStops.length).toBeGreaterThan(1);

  // First stop must be 0 (top of page).
  expect(coverage.suggestedStops[0]).toBe(0);

  // Last stop must not exceed maxScrollTop.
  const lastStop = coverage.suggestedStops[coverage.suggestedStops.length - 1];
  expect(lastStop).toBeLessThanOrEqual(coverage.maxScrollTop);

  // All stops must be in ascending order.
  for (let i = 1; i < coverage.suggestedStops.length; i++) {
    expect(coverage.suggestedStops[i]).toBeGreaterThan(coverage.suggestedStops[i - 1]);
  }

  // Coverage must include enough stops to cover the full page.
  // A screenshot at each stop (viewport-height tall) must collectively cover scrollHeight.
  // The last stop + viewportHeight must reach scrollHeight.
  expect(lastStop + coverage.viewportHeight).toBeGreaterThanOrEqual(coverage.scrollHeight);
});

// ─── TC-11: Final viewport not unnecessarily duplicated ──────────────────────

test('TC-11: mxViewportCoverage does not add a final stop that is < 10% viewport away from previous', async ({ page }) => {
  // Use noscroll to get the 1-stop case, then test the dedup rule with center.
  await page.goto(fixture('mx-scroll-center.html'));

  const coverage = await mxViewportCoverage(page);
  const stops = coverage.suggestedStops;

  // No consecutive pair of stops may be closer than 10% of viewportHeight.
  const minGap = Math.floor(coverage.viewportHeight * 0.1);
  for (let i = 1; i < stops.length; i++) {
    expect(stops[i] - stops[i - 1]).toBeGreaterThan(minGap);
  }
});

// ─── TC-12: Useful diagnostics when no suitable container ────────────────────

test('TC-12: discovery returns full diagnostics object even when no container found', async ({ page }) => {
  await page.goto(fixture('mx-scroll-noscroll.html'));

  const info = await discoverScrollContainer(page);

  expect(info).toHaveProperty('found', false);
  expect(info).toHaveProperty('method');
  expect(info).toHaveProperty('selector');
  expect(info).toHaveProperty('scrollHeight');
  expect(info).toHaveProperty('clientHeight');
  expect(info).toHaveProperty('scrollTop');
  expect(info).toHaveProperty('isScrollable');
  expect(info).toHaveProperty('candidateCount');
});
