import { test, expect } from '@playwright/test';
import { agent, file } from './agent.mjs';

test('bundles scripts, nested CSS imports, images and inline style URLs', async ({ page }) => {
  const overlay = await agent(page);
  const inner = await overlay.show([
    file('index.html', 'text/html', '<link rel="stylesheet" href="css/main.css"><img id="image" src="image.svg"><div id="styled" style="background-image:url(image.svg)">hello</div><script src="js/main.js"></script>'),
    file('js/main.js', 'text/javascript', 'document.body.dataset.executed="yes"'),
    file('css/main.css', 'text/css', '@import "nested.css"; body {background-image:url(../image.svg)}'),
    file('css/nested.css', 'text/css', 'body {color:rgb(12, 34, 56)}'),
    file('image.svg', 'image/svg+xml', '<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"><rect width="10" height="10" fill="red"/></svg>'),
  ]);
  await expect(inner.locator('body')).toHaveAttribute('data-executed', 'yes');
  await expect(inner.locator('body')).toHaveCSS('color', 'rgb(12, 34, 56)');
  await expect.poll(() => inner.locator('#image').evaluate(img => img.naturalWidth)).toBe(10);
  expect(await inner.locator('#styled').evaluate(el => getComputedStyle(el).backgroundImage)).toContain('data:image/svg+xml');
});

test('opaque origin blocks storage, cookies, parent and top DOM access', async ({ page }) => {
  const overlay = await agent(page);
  await page.evaluate(() => {
    document.cookie = 'artifact_test=secret; SameSite=Lax';
    localStorage.setItem('artifact_test', 'secret');
    sessionStorage.setItem('artifact_test', 'secret');
  });
  const inner = await overlay.show([file('index.html', 'text/html', `<body><script>
    const attempts = {
      cookie: () => document.cookie,
      local: () => localStorage.getItem('artifact_test'),
      session: () => sessionStorage.getItem('artifact_test'),
      indexed: () => indexedDB.open('test'),
      parent: () => parent.document.body,
      top: () => top.document.body
    };
    for (const [name, attempt] of Object.entries(attempts)) {
      try { attempt(); document.body.dataset[name] = 'accessible'; }
      catch { document.body.dataset[name] = 'blocked'; }
    }
  </script>`)]);
  for (const key of ['cookie', 'local', 'session', 'indexed', 'parent', 'top']) {
    await expect(inner.locator('body')).toHaveAttribute(`data-${key}`, 'blocked');
  }
});

async function recordLeaks(page) {
  const requests = [];
  await page.route('**/artifact-leak?*', route => {
    requests.push(route.request().url());
    return route.fulfill({ status: 204, body: '' });
  });
  return requests;
}

test('additional CSP and meta removal cannot permit network requests', async ({ page }) => {
  const requests = await recordLeaks(page);
  const overlay = await agent(page);
  const leak = new URL('/artifact-leak', page.url()).href;
  const inner = await overlay.show([file('index.html', 'text/html', `<meta http-equiv="Content-Security-Policy" content="default-src * 'unsafe-inline'; connect-src *; img-src *"><body>
    <script>
      document.querySelectorAll('meta').forEach(m => m.remove());
      fetch('${leak}?fetch').catch(() => document.body.dataset.fetch='blocked');
      const img = new Image(); img.src='${leak}?image';
    </script>`)]);
  await expect(inner.locator('body')).toHaveAttribute('data-fetch', 'blocked');
  await page.waitForTimeout(300);
  expect(requests).toEqual([]);
});

for (const navigation of ['script', 'meta', 'link', 'form']) {
  test(`wrapper blocks ${navigation} navigation before a request`, async ({ page }) => {
    const requests = await recordLeaks(page);
    const overlay = await agent(page);
    const url = new URL('/artifact-leak?navigation', page.url()).href;
    const html = {
      script: `<script>location.href='${url}'</script>`,
      meta: `<meta http-equiv="refresh" content="0;url=${url}">`,
      link: `<a href="${url}">Navigate</a>`,
      form: `<form action="${url}"><button>Navigate</button></form>`,
    }[navigation];
    const inner = await overlay.show([file('index.html', 'text/html', html)]);
    if (navigation === 'link') await inner.getByText('Navigate').click();
    if (navigation === 'form') await inner.getByText('Navigate').click();
    await page.waitForTimeout(500);
    expect(requests).toEqual([]);
    expect(page.url()).toContain('/overlay/');
  });
}

test('wrapper attribute escaping prevents artifact markup breaking out', async ({ page }) => {
  const overlay = await agent(page);
  await overlay.show([file('index.html', 'text/html', `"><script>parent.document.body.dataset.escaped='yes'</script><iframe srcdoc="<p>nested</p>"></iframe>`)]);
  await expect(page.locator('body')).not.toHaveAttribute('data-escaped');
  const wrapper = page.frameLocator('iframe.artifact-preview');
  await expect(wrapper.locator('body > iframe')).toHaveCount(1);
  await expect(wrapper.locator('script')).toHaveCount(0);
});

test('preparation rejects missing files without requesting application URLs', async ({ page }) => {
  const requests = [];
  await page.route('**/secret.png', route => {
    requests.push(route.request().url());
    return route.fulfill({ status: 204, body: '' });
  });
  const overlay = await agent(page);
  const inner = await overlay.show([file('index.html', 'text/html', '<img src="secret.png">')]);
  await expect(inner.locator('body')).toContainText('Unable to prepare artifact');
  await expect(inner.locator('pre')).toHaveText('Missing bundle file: secret.png');
  expect(requests).toEqual([]);
});

test('the document keeps head content and attributes of the entrypoint', async ({ page }) => {
  const overlay = await agent(page);
  const inner = await overlay.show([
    file('index.html', 'text/html', '<!doctype html><html lang="en" class="dark"><head><title>Kept</title><link rel="icon" href="favicon.ico"><base href="https://example.com/"><style>@import url(theme.css);</style></head><body><p>Body</p></body></html>'),
    file('theme.css', 'text/css', 'p { color: rgb(1, 2, 3) }'),
  ]);
  await expect(inner.locator('p')).toHaveCSS('color', 'rgb(1, 2, 3)');
  await expect(inner.locator('html')).toHaveAttribute('lang', 'en');
  await expect(inner.locator('html')).toHaveClass('dark');
  await expect(inner.locator('title')).toHaveJSProperty('text', 'Kept');
  await expect(inner.locator('link, base')).toHaveCount(0);
});
