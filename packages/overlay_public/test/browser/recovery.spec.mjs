import { test, expect } from '@playwright/test';
import { agent, file } from './agent.mjs';

const document = text => [
  file('index.html', 'text/html', `<link rel="stylesheet" href="theme.css"><h1>${text}</h1>`),
  file('theme.css', 'text/css', 'h1 { color: rgb(12, 34, 56); }'),
];

test('refresh restores complete revisions, bundled assets and panel placement', async ({ page }) => {
  const overlay = await agent(page);
  await overlay.show(document('First version'), 'map');
  await overlay.show(document('Second version'), 'map');
  await overlay.run('let _ = perform Show({item: Artifact("map"), origin: {x: 0, y: 0}, size: {x: 500, y: 1000}}) perform Show({item: Revision({name: "map", version: 1}), origin: {x: 500, y: 0}, size: {x: 500, y: 1000}})');
  await expect(page.locator('.artifact-storage')).toHaveText('Saved in this tab');
  const placement = await page.locator('.artifact-panel').last().getAttribute('style');
  await page.reload();
  await expect(page.locator('.artifact-panel')).toHaveCount(2);
  const current = page.frameLocator('iframe.artifact-preview[title="map"]').frameLocator('iframe');
  const previous = page.frameLocator('iframe.artifact-preview').last().frameLocator('iframe');
  await expect(current.locator('h1')).toHaveText('Second version');
  await expect(previous.locator('h1')).toHaveText('First version');
  await expect(current.locator('h1')).toHaveCSS('color', 'rgb(12, 34, 56)');
  await expect(page.locator('.artifact-panel').last()).toHaveAttribute('style', placement);
  await page.getByRole('button', { name: 'Close map', exact: true }).click();
  await expect(page.locator('.artifact-storage')).toHaveText('Saved in this tab');
  await page.reload();
  await expect(page.locator('.artifact-panel')).toHaveCount(1);
  await expect(page.frameLocator('iframe.artifact-preview').frameLocator('iframe').locator('h1')).toHaveText('First version');
});

test('a full tab store keeps the live workspace and offers a retry', async ({ page }) => {
  await page.addInitScript(() => {
    if (window !== window.top) return;
    window.failArtifactSave = true;
    const set = Storage.prototype.setItem;
    Storage.prototype.setItem = function (key, value) {
      if (key === 'overlay.artifacts' && window.failArtifactSave) {
        throw new DOMException('The quota has been exceeded.', 'QuotaExceededError');
      }
      return set.call(this, key, value);
    };
  });
  const overlay = await agent(page);
  const inner = await overlay.show(document('Still here'));
  await expect(page.locator('.artifact-storage')).toContainText('Changes could not be saved');
  await expect(inner.locator('h1')).toHaveText('Still here');
  await page.evaluate(() => { window.failArtifactSave = false; });
  await page.getByRole('button', { name: 'Retry saving' }).click();
  await expect(page.locator('.artifact-storage')).toHaveText('Saved in this tab');
  await page.reload();
  await expect(page.frameLocator('iframe.artifact-preview').frameLocator('iframe').locator('h1')).toHaveText('Still here');
});


test('closed artifacts can be reopened without another model call', async ({ page }) => {
  let calls = 0;
  page.on('request', request => {
    if (request.url().endsWith('/api/chat')) calls++;
  });
  const overlay = await agent(page);
  await overlay.show(document('First version'), 'map');
  await overlay.show(document('Latest version'), 'map');
  await page.getByRole('button', { name: 'Close map', exact: true }).click();
  const library = page.getByRole('list', { name: 'Saved artifacts' });
  await expect(library).toContainText('2 versions');
  await expect(page.locator('.artifact-storage')).toHaveText('Saved in this tab');
  await page.reload();
  await expect(library).toBeVisible();
  const before = calls;
  await page.getByRole('button', { name: 'History of map' }).click();
  await expect(page.locator('.artifact-revision')).toHaveCount(2);
  await page.locator('.artifact-heading button[aria-label^="Close"]').click();
  await page.getByRole('button', { name: 'Open map', exact: true }).click();
  await expect(page.frameLocator('iframe.artifact-preview').frameLocator('iframe').locator('h1')).toHaveText('Latest version');
  expect(calls).toBe(before);
});
