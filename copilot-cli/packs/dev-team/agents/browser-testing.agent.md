---
name: browser-testing
description: >-
  Reusable Playwright patterns for browser-based QA — navigation, form
  interaction, screenshots, waiting strategies, data extraction, and CAPTCHA/auth
  handoff. Use when you need to interact with a running app through a real browser.
model: claude-haiku-4.5
metadata:
  tier: small
---

# browser-testing — Playwright QA patterns

Reusable patterns for browser-based testing and visual verification using Playwright. Chromium is available through Copilot CLI's shell.

## Prerequisites

```bash
npx playwright install chromium
```

## Playwright patterns

| Category | Description |
|----------|-------------|
| Navigation | `goto`, `waitForSelector`, `waitForNavigation` with network-idle |
| Form interaction | `fill`, `selectOption`, `check`, `setInputFiles`, submit |
| Click actions | Click by selector/text, double-click, right-click, hover |
| Screenshots | Full page, viewport, element, and clipped-region captures |
| Waiting strategies | Selector appear/disappear, text match, network response |
| Data extraction | `textContent`, `getAttribute`, `inputValue`, `count`, `isVisible` |
| Script template | Full boilerplate with error capture and console logging |
| Error handling | Common timeout, connection, and protocol errors with resolutions |
| CAPTCHA/auth handoff | Detect walls, report to user, resume from `storageState` |

Full code examples, the script template, and the error-handling table live in `~/.copilot/dev-team/knowledge/skills/browser-testing/references/playwright-patterns.md`.

## Script template

```javascript
const { chromium } = require('playwright');

(async () => {
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({ viewport: { width: 1280, height: 720 } });
  const page = await context.newPage();
  page.on('console', (m) => console.log('[console]', m.type(), m.text()));

  try {
    await page.goto('URL', { waitUntil: 'networkidle', timeout: 30000 });
    // ...actions...
    await page.screenshot({ path: 'SCREENSHOT_PATH', fullPage: true });
  } catch (err) {
    console.error('Browser error:', err.message);
  } finally {
    await browser.close();
  }
})();
```

## Visual verification guidelines

When interpreting screenshots, describe:

1. **Layout** — is the structure correct? Any overlapping elements, broken grids, or overflow?
2. **Content** — is the expected text/data visible? Any placeholder text or missing images?
3. **State** — are interactive elements in the right state (buttons enabled/disabled, forms populated)?
4. **Responsiveness** — at the given viewport, does the layout adapt correctly?
5. **Errors** — any visible error messages, 404 pages, or captured console errors?

Compare observations against acceptance criteria when available; flag discrepancies as findings.

## CAPTCHA / auth handoff

On a CAPTCHA or auth wall, report that manual intervention is needed and have the human complete the challenge in their browser. Persist the authenticated session with Playwright's `storageState` and resume from it on the next run.
