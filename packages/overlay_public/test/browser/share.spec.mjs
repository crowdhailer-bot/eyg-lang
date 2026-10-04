import { test, expect } from '@playwright/test';
import { agent, file } from './agent.mjs';

test('a person shares the version of an artifact they are looking at', async ({ page }) => {
  const shared = [];
  const ids = ['0d6f7c8e-1111-4222-8333-944445555666', '1e7a8d9f-2222-4333-8444-a55556666777'];
  await page.route('**/artifacts', async route => {
    shared.push(route.request().postDataJSON());
    const body = { id: ids[shared.length - 1], secret: `secret-${shared.length}` };
    await route.fulfill({ status: 201, contentType: 'application/json', body: JSON.stringify(body) });
  });
  const overlay = await agent(page);
  await overlay.show([file('index.html', 'text/html', '<h1>Departures</h1>')], 'departures');
  // An artifact is only kept in the session until it is shared.
  expect(shared).toEqual([]);

  await page.getByRole('button', { name: 'share' }).click();
  const link = page.getByRole('link', { name: 'shared ↗' });
  await expect(link).toHaveAttribute('href', `/artifact/${ids[0]}`);
  expect(shared).toEqual([{ name: 'departures', files: [{ path: 'index.html', media_type: 'text/html', content: Buffer.from('<h1>Departures</h1>').toString('base64') }] }]);

  // A new version has not been shared.
  await overlay.run(`perform Artifact({name: "departures", bundle: [${file('index.html', 'text/html', '<h1>Later</h1>')}]})`);
  await expect(page.getByRole('button', { name: 'share' })).toBeVisible();

  // Sharing it names the earlier share, so the earlier page links to the newer version.
  await page.getByRole('button', { name: 'share' }).click();
  await expect(link).toHaveAttribute('href', `/artifact/${ids[1]}`);
  expect(shared[1].previous).toEqual({ id: ids[0], secret: 'secret-1' });
});

test('a failed share can be retried', async ({ page }) => {
  await page.route('**/artifacts', route => route.fulfill({ status: 422, contentType: 'application/json', body: JSON.stringify({ reason: 'A bundle may contain at most 128 files and 2 MiB' }) }));
  const overlay = await agent(page);
  await overlay.show([file('index.html', 'text/html', '<h1>Departures</h1>')], 'departures');
  await page.getByRole('button', { name: 'share' }).click();
  await expect(page.getByRole('button', { name: 'retry share' })).toHaveAttribute('title', 'A bundle may contain at most 128 files and 2 MiB');
});
