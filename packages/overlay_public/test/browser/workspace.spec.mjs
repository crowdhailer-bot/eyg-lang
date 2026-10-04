import { test, expect } from '@playwright/test';
import { agent, file } from './agent.mjs';

test('agent effects create versions, preserve active previews and expose history/diff', async ({ page }) => {
  const overlay = await agent(page);
  const save = html => `perform Artifact({name: "map", bundle: [${file('index.html', 'text/html', html)}]})`;
  const show = (item, x, width) => `perform Show({item: ${item}, origin: {x: ${x}, y: 0}, size: {x: ${width}, y: 1000}})`;

  await overlay.run(`let _ = ${save('<h1>First</h1><button onclick="this.textContent=\'clicked\'">Click me</button>')}
${show('Artifact("map")', 0, 1000)}`);
  const preview = page.frameLocator('iframe.artifact-preview').frameLocator('iframe');
  await expect(preview.getByRole('heading')).toHaveText('First');
  await preview.getByRole('button').click();

  // Moving a panel keeps the running preview.
  await overlay.run(show('Artifact("map")', 0, 500));
  await expect(preview.getByRole('button')).toHaveText('clicked');
  await expect(page.locator('.artifact-panel')).toHaveAttribute('style', /width:50\.0%/);

  const result = await overlay.run(`let _ = ${save('<h1>Second</h1>')}
let _ = ${show('History("map")', 500, 250)}
${show('Diff({name: "map", from: 1, to: 2})', 750, 250)}`);
  expect(result.content).toBe('Ok({})');
  await expect(preview.getByRole('heading')).toHaveText('Second');
  await expect(page.getByText('Changed index.html')).toBeVisible();

  await page.getByRole('button', { name: 'Open v1', exact: true }).click();
  const pinned = page.frameLocator('iframe.artifact-preview[title="map · v1"]').frameLocator('iframe');
  await expect(pinned.getByRole('heading')).toHaveText('First');
  await page.getByRole('button', { name: 'Close map', exact: true }).click();
  await expect(pinned.getByRole('heading')).toHaveText('First');
});
