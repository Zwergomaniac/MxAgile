# Visual Verification

Canonical MxAgile skill for Playwright-based visual and parity verification of Mendix applications.

Covers: scroll container discovery, systematic viewport coverage, evidence completeness, and
integration with the 7-dimension parity contract (`policies/ui-parity.md`).

---

## Mendix Scrolling Behavior

Mendix/Atlas applications do NOT scroll the browser document. Application content is hosted in
an independently scrollable layout container nested inside the page DOM. The primary content
container is typically:

```
.mx-scrollcontainer-center
```

This container has its own `overflow-y: auto` style and an independent `scrollTop` property.
The browser document (`document.documentElement`) has `overflow: hidden` — it does not scroll.

### Incorrect Assumption

Standard browser-level scrolling **executes without error** but does NOT move the visible
Mendix application content:

```javascript
// WRONG — does not move Mendix content:
window.scrollTo(0, 1000);
document.documentElement.scrollTop = 1000;
document.body.scrollTop = 1000;
```

The dangerous failure mode: JavaScript evaluates successfully, no exception is thrown, but the
visual viewport remains at the same position. Every subsequent `fullPage: false` screenshot
captures **the same section of the page**. A visual PASS based on these screenshots provides
**false confidence** — only the first viewport was inspected.

---

## Canonical Helper

The MxAgile Mendix-aware scroll helper lives at:

```
.playwright/helpers/mx-scroll.js      ← for @playwright/test spec files
.playwright/helpers/mx-scroll-shell.sh ← for playwright-cli .test.sh scripts
```

### Usage in @playwright/test specs

```javascript
const {
  RESULT,
  discoverScrollContainer,
  mxScroll,
  mxScrollToElement,
  mxViewportCoverage,
} = require('../helpers/mx-scroll');

test('visual: full page coverage', async ({ page }) => {
  await page.goto(appUrl);

  // 1. Discover the effective scroll container.
  const info = await discoverScrollContainer(page);
  // info: { found, method, selector, scrollHeight, clientHeight, scrollTop, isScrollable, candidateCount }

  // 2. Get runtime-derived screenshot stops.
  const coverage = await mxViewportCoverage(page);
  // coverage: { container, scrollHeight, viewportHeight, maxScrollTop, suggestedStops }

  // 3. Screenshot at each stop.
  for (const stop of coverage.suggestedStops) {
    const r = await mxScroll(page, stop);
    expect(r.result).not.toBe(RESULT.SCROLL_NOT_EFFECTIVE);
    expect(r.result).not.toBe(RESULT.NO_SCROLL_CONTAINER);
    await page.screenshot({ path: `.concord/screenshots/app/Page_${stop}.png`, fullPage: false });
  }
});
```

### Usage in playwright-cli .test.sh scripts

```bash
source "$(dirname "$0")/../.playwright/helpers/mx-scroll-shell.sh"

playwright-cli open "$PLAYWRIGHT_BASE_URL"

# Get stops from runtime dimensions
stops="$(mx_viewport_coverage)"

for stop in $stops; do
  result="$(mx_scroll "$stop")" || { echo "FAIL: scroll not effective at $stop" >&2; exit 1; }
  playwright-cli screenshot
done

playwright-cli close
```

---

## Scroll Container Discovery

`discoverScrollContainer(page)` uses the following priority order:

1. **Known Mendix selector** — checks these CSS selectors in order:
   - `.mx-scrollcontainer-center` ← primary Atlas layout container
   - `.mx-scrollcontainer-main`
   - `.mx-page-content`

2. **Dynamic fallback** — if no known selector matches, scans ALL elements for:
   ```
   computed overflow-y === 'auto' OR 'scroll'
   AND scrollHeight > clientHeight
   ```
   Selects the candidate with the highest score:
   ```
   score = (scrollHeight - clientHeight) × clientWidth
   ```
   This formula biases toward the wide main-content column (high `clientWidth`) over
   narrow sidebars and small scrollable list widgets.

3. **Document fallback** — if no scrollable elements are found, checks whether
   `document.documentElement` itself scrolls.

4. **Not found** — page fits in viewport; no scrolling needed.

### Discovery Diagnostics

The returned object always includes:

| Field | Description |
|---|---|
| `found` | Whether a scroll container was identified |
| `method` | `known_selector` \| `dynamic_fallback` \| `document_fallback` \| `none` |
| `selector` | CSS selector of the identified container (or `'document'` for the document element) |
| `scrollHeight` | Total content height in pixels |
| `clientHeight` | Visible viewport height of the container |
| `scrollTop` | Current scroll position |
| `isScrollable` | Whether the container can actually be scrolled (overflow-y auto\|scroll AND content overflows) |
| `candidateCount` | Number of dynamic candidates inspected (diagnostic) |

---

## Scroll API — mxScroll

```javascript
const r = await mxScroll(page, position, { settleMs: 300, container: null });
```

| Parameter | Description |
|---|---|
| `page` | Playwright `Page` object |
| `position` | Target `scrollTop` in pixels |
| `settleMs` | Milliseconds to wait after scroll for rendering to stabilize (default: 300) |
| `container` | Pre-discovered container info (skips re-discovery) |

### Result Codes

| Code | Meaning |
|---|---|
| `SCROLLED` | Scroll succeeded; position changed as expected |
| `ALREADY_AT_POSITION` | Container was already at the requested position |
| `CLAMPED_TO_MAX` | Requested position exceeded scrollable range; actual = maxScrollTop |
| `NO_SCROLL_CONTAINER` | No scrollable container found |
| `SCROLL_NOT_EFFECTIVE` | `scrollTop` was set but did not change (e.g., `overflow: hidden`) |

**Evidence safety rule:** a screenshot taken after `SCROLL_NOT_EFFECTIVE` or
`NO_SCROLL_CONTAINER` MUST NOT be treated as a distinct page section. The verification
MUST fail or skip rather than recording a false PASS.

---

## Element Targeting — mxScrollToElement

For cases where a specific UI element is the target rather than a systematic scroll position:

```javascript
const r = await mxScrollToElement(page, '#target-button', { settleMs: 300 });
// r: { ok, selector, inView, top, bottom }
```

Uses `element.scrollIntoView({ behavior: 'instant', block: 'start' })` internally.

### When to Use Each Approach

| Approach | When to use |
|---|---|
| `mxScroll(page, position)` | Systematic viewport-by-viewport page coverage |
| `mxScrollToElement(page, selector)` | Targeted component verification (ensure a specific element is visible) |

Do not substitute one for the other universally. Positional scrolling is the right tool for
comprehensive visual evidence. Element scrolling is the right tool for targeted state triggers
(e.g., scroll to a button and click it, or scroll to a form section before capturing its state).

---

## Viewport Coverage — mxViewportCoverage

```javascript
const coverage = await mxViewportCoverage(page, { overlapFraction: 0.1 });
```

Returns:

```javascript
{
  container: '.mx-scrollcontainer-center',
  scrollHeight: 5201,
  viewportHeight: 720,
  maxScrollTop: 4481,
  suggestedStops: [0, 648, 1296, 1944, 2592, 3240, 3888, 4481]
}
```

Stop calculation rules:
- Stops are spaced at `floor(viewportHeight × (1 - overlapFraction))` apart (default 90% step).
- A 10% overlap between adjacent screenshots prevents content at viewport edges from being missed.
- The final stop at `maxScrollTop` is included only if it is more than `floor(viewportHeight × overlapFraction)` away from the previous stop, avoiding a near-duplicate bottom screenshot.
- Stops are always calculated from **actual runtime dimensions** — never hardcoded.

---

## Visual Stabilization

Mendix pages may render dynamic content (charts, grids, lazy-loaded components) asynchronously
after a scroll event. The `settleMs` parameter (default 300ms) provides a configurable delay
between the scroll operation and the screenshot.

Guidance:
- 300ms is sufficient for most static or near-static content.
- Increase to 500–800ms for pages with animated charts or data-loading components.
- Do NOT use a global 800ms delay for every test — this makes the full test suite unnecessarily slow.
- For pages with explicit readiness signals, use Playwright `waitForSelector` or `waitForLoadState` instead of a fixed delay.

```javascript
// Static content — 300ms default is fine
const r = await mxScroll(page, stop);
await page.screenshot(...);

// Chart page — increase settle time
const r = await mxScroll(page, stop, { settleMs: 800 });
await page.screenshot(...);

// Page with explicit readiness signal
const r = await mxScroll(page, stop, { settleMs: 0 });
await page.waitForSelector('.chart-rendered');
await page.screenshot(...);
```

---

## Evidence Completeness

A visual verification that covers a long page MUST detect and reject these failure modes:

### Repeated screenshots (all at same position)

```javascript
// BAD — may produce identical screenshots if scrolling is ineffective:
for (const stop of stops) {
  await page.evaluate(y => window.scrollTo(0, y), stop); // wrong — Mendix doesn't scroll this way
  await page.screenshot(...);
}

// GOOD — verifies that each scroll actually moved the viewport:
for (const stop of stops) {
  const r = await mxScroll(page, stop);
  if (r.result === RESULT.SCROLL_NOT_EFFECTIVE || r.result === RESULT.NO_SCROLL_CONTAINER) {
    throw new Error(`Scroll not effective at stop ${stop}: ${JSON.stringify(r)}`);
  }
  await page.screenshot({ path: `screenshot_${stop}.png`, fullPage: false });
}
```

### Include scroll position in evidence

When recording parity evidence, include the actual scroll position:

```yaml
visual:
  result: PASS
  evidence:
    - type: screenshot
      path: ".concord/screenshots/app/CustomerOverview_scroll0.png"
      description: "Visual viewport 1 (scrollTop=0)"
      scroll_position: 0
      passed: true
    - type: screenshot
      path: ".concord/screenshots/app/CustomerOverview_scroll648.png"
      description: "Visual viewport 2 (scrollTop=648)"
      scroll_position: 648
      passed: true
  scroll_coverage:
    container: ".mx-scrollcontainer-center"
    scroll_height: 5201
    viewport_height: 720
    stops_captured: 8
```

A parity PASS without `scroll_coverage` on a page where `scrollHeight > viewportHeight` is
treated as incomplete evidence.

---

## New Test Generation

When generating a new visual/parity test for a Mendix page that may be taller than the viewport:

1. Use `mxViewportCoverage(page)` to discover stops at runtime.
2. Use `mxScroll(page, stop)` for each stop — never `window.scrollTo`.
3. Assert that each scroll result is not `SCROLL_NOT_EFFECTIVE`.
4. Take a `fullPage: false` screenshot at each stop.
5. Include `scroll_position` in the evidence manifest.

Do NOT use `fullPage: true` as a substitute for multi-stop scrolling. Playwright's `fullPage`
attempts to scroll the browser document — on Mendix pages this captures duplicate content
from the non-scrolling document layer, not the actual application content.

---

## mxcli Playwright Capabilities (Verified)

`mxcli playwright verify` runs `.test.sh` scripts that use `playwright-cli` commands.
Verified available `playwright-cli` commands: `open`, `eval`, `eval --file`, `screenshot`, `close`.

There is NO `--full-page` flag in the current `mxcli playwright` or `playwright-cli` toolchain
that correctly handles Mendix nested scroll containers. Full-page screenshot support at the
`playwright-cli` level would require the browser to scroll `document.documentElement`, which
does not move Mendix application content. The MxAgile scroll helper is required for correct
multi-viewport coverage.

---

## Related Policies

- `policies/ui-parity.md` — 7-dimension parity contract, evidence requirements per dimension
- `policies/evidence-contract.md` — screenshot promotion, evidence manifest
- `policies/runtime-strategy.md` — Local First / Docker by need escalation model
- `policies/observe-before-mutate.md` — baseline capture before implementation changes
