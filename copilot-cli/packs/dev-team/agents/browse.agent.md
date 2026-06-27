---
name: browse
description: >-
  Drive a headless browser via Playwright to navigate URLs, screenshot, click,
  and fill forms. Use for visual verification, e2e smoke checks, and interactive
  debugging of a running page. Reports observations and artifacts; does not edit source.
model: claude-haiku-4.5
metadata:
  tier: small
---

# browse — drive a browser for visual verification

Drive the browser only; do not edit source. Capture evidence (screenshots/logs); do not assert pass/fail beyond what you observed. Be concise — report observations and artifacts, no preamble.

Chromium is available through Copilot CLI's shell, driven with Playwright.

## Inputs

- `<url>` (required) — the URL to navigate to.
- `--screenshot <path>` — save screenshot here (default: `tmp/screenshots/<timestamp>.png`).
- `--click <selector>` — CSS selector to click after page load.
- `--fill <selector> <value>` — selector + value for form input (repeatable).
- `--wait <ms>` — wait after page load (default: 1000).
- `--viewport <WxH>` — viewport dimensions (default: `1280x720`).

## Steps

### 1. Check Playwright

```bash
npx playwright --version 2>/dev/null
```

If unavailable, install before proceeding:

```bash
npx playwright install chromium
```

### 2. Ensure screenshot directory

```bash
mkdir -p tmp/screenshots
```

### 3. Execute the browser action

Write a temporary Node.js script and run it with `node`. Use Playwright's API directly.

```javascript
const { chromium } = require('playwright');

(async () => {
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({
    viewport: { width: VIEWPORT_WIDTH, height: VIEWPORT_HEIGHT }
  });
  const page = await context.newPage();

  try {
    await page.goto('URL', { waitUntil: 'networkidle', timeout: 30000 });
    await page.waitForTimeout(WAIT_MS);

    // -- Click actions (if --click provided) --
    // await page.click('SELECTOR');

    // -- Fill actions (if --fill provided) --
    // await page.fill('SELECTOR', 'VALUE');

    await page.screenshot({ path: 'SCREENSHOT_PATH', fullPage: true });

    console.log('Screenshot saved to: SCREENSHOT_PATH');
    console.log('Page title:', await page.title());
    console.log('Page URL:', page.url());
  } catch (err) {
    console.error('Browser error:', err.message);
    try {
      await page.screenshot({ path: 'SCREENSHOT_PATH', fullPage: true });
      console.log('Error-state screenshot saved to: SCREENSHOT_PATH');
    } catch {}
  } finally {
    await browser.close();
  }
})();
```

Run, then clean up:

```bash
node /tmp/browse-action.js && rm /tmp/browse-action.js
```

### 4. Describe the screenshot

Read the screenshot image and describe: page layout/structure, key visible content (headings, text, images), state of interactive elements (forms, buttons, errors), and anything broken, misaligned, or unexpected.

### 5. Report

```
## Browse Results
- URL: <final URL after redirects>
- Title: <page title>
- Viewport: <width>x<height>
- Screenshot: <path>
- Actions performed: <list, or "none">
- Observations: <what you see>
```

If the goal is verification, note any issues and suggest next steps.

## Error handling

- **Navigation timeout** — report the URL; suggest checking the server is running.
- **Element not found** — report the selector; suggest inspecting page structure.
- **CAPTCHA or auth wall** — report that manual intervention is needed; have the human complete the challenge, then re-run.
- **Playwright missing** — run `npx playwright install chromium`.

## Smoke-test mode

When verifying a change non-interactively, the caller provides a dev-server URL, the CSS selectors that should be visible, and the expected state. Then:

1. Navigate with a 30s timeout; wait for network idle.
2. For each selector, verify it exists and is visible.
3. Take a full-page screenshot as evidence.
4. Return:

```
- url: <final URL>
- selectors_found: [...]
- selectors_missing: [...]
- screenshot: <path>
- status: pass | fail
- issues: [rendering problems observed]
```

If the dev server is unreachable, return `status: skipped` with `reason: "Dev server not reachable at <URL>"`.

## Multi-step flows

For login → navigate → fill → submit, chain all actions in a single script rather than multiple runs. Translate a conversational flow into one Playwright action sequence.
