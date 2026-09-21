import { chromium } from 'playwright';
import { mkdir, writeFile } from 'node:fs/promises';

await mkdir('artifacts', { recursive: true });
const browser = await chromium.launch({ headless: true });
const results = [];
try {
  for (const url of ['https://www.di.se/', 'https://www.sj.se/']) {
    const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
    try {
      const response = await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 30_000 });
      await page.waitForTimeout(2500);
      if (url.includes('sj.se')) {
        await page
          .getByRole('button', { name: 'Endast nödvändiga cookies' })
          .click({ timeout: 5000 })
          .catch(() => {});
        await page
          .getByRole('link', { name: 'Sök resa', exact: true })
          .click({ timeout: 5000 })
          .catch(() => {});
        await page.waitForTimeout(3000);
        await page.getByRole('combobox', { name: 'Från', exact: true }).fill('Stockholm');
        await page.waitForTimeout(1200);
        await page.getByRole('combobox', { name: 'Från', exact: true }).press('ArrowDown');
        await page.getByRole('combobox', { name: 'Från', exact: true }).press('Enter');
        await page.getByRole('combobox', { name: 'Till', exact: true }).fill('Göteborg');
        await page.waitForTimeout(1200);
        await page.getByRole('combobox', { name: 'Till', exact: true }).press('ArrowDown');
        await page.getByRole('combobox', { name: 'Till', exact: true }).press('Enter');
        await page.getByRole('button', { name: 'Sök resa', exact: true }).click();
        await page.waitForTimeout(5000);
      } else {
        await page
          .getByRole('button', { name: 'Inställningar', exact: true })
          .click({ timeout: 5000 })
          .catch(() => {});
        await page
          .getByRole('button', { name: /Neka allt:/ })
          .click({ timeout: 5000 })
          .catch(() => {});
      }
      const result = {
        url,
        status: response?.status(),
        title: await page.title(),
        text: (await page.locator('body').innerText()).slice(0, 1800),
        graphs: await page.locator('svg, canvas, [class*="chart"], [class*="graph"]').count(),
      };
      results.push(result);
      await page.screenshot({ path: `artifacts/live-${new URL(url).hostname}.png` });
      console.log(JSON.stringify(result, null, 2));
      console.log(await page.locator('body').ariaSnapshot());
      if (url.includes('di.se'))
        console.log(
          'CHART DOM',
          await page.locator('.live-box__index-graph').evaluate((node) =>
            Array.from(node.querySelectorAll('*'))
              .slice(0, 12)
              .map((child) => ({
                tag: child.tagName,
                style: child.getAttribute('style'),
                width: child.getAttribute('width'),
                height: child.getAttribute('height'),
                box: {
                  width: child.getBoundingClientRect().width,
                  height: child.getBoundingClientRect().height,
                },
              })),
          ),
        );
      console.log(
        'CANDIDATES',
        await page
          .locator(
            '[class*="chart"], [class*="graph"], [class*="journey"], [class*="departure"], [class*="result"]',
          )
          .evaluateAll((nodes) =>
            nodes
              .filter((n) => n.getBoundingClientRect().width > 200)
              .slice(0, 25)
              .map((n) => ({
                tag: n.tagName,
                class: n.className,
                id: n.id,
                text: n.innerText?.slice(0, 600),
                width: n.getBoundingClientRect().width,
                height: n.getBoundingClientRect().height,
              })),
          ),
      );
      await page.addScriptTag({ path: 'dist/phantom.js' });
      await page.evaluate(() => window.Phantom.dock('left'));
      await page
        .getByRole('textbox', { name: 'Message Phantom' })
        .fill(
          url.includes('di.se')
            ? 'Make the graph bigger'
            : 'Shortlist the two cheapest direct trains',
        );
      await page.getByRole('button', { name: 'Send message', exact: true }).click();
      await page.waitForTimeout(2500);
      console.log('PHANTOM', await page.locator('#eyg-phantom .feed').innerText());
      await page.screenshot({ path: 'artifacts/live-injected-' + new URL(url).hostname + '.png' });
    } catch (error) {
      results.push({ url, error: error.message });
      console.log(url, error.message);
    }
    await page.close();
  }
} finally {
  await browser.close();
}
await writeFile(
  'artifacts/live-check.json',
  JSON.stringify({ checkedAt: new Date().toISOString(), results }, null, 2) + '\n',
);
