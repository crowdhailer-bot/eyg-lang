import { chromium } from 'playwright';
import { mkdir, writeFile } from 'node:fs/promises';
import { spawnSync } from 'node:child_process';
import assert from 'node:assert/strict';
import { serve } from '../server.mjs';

const server = await serve(0),
  origin = 'http://127.0.0.1:' + server.address().port;
const browser = await chromium.launch({ headless: true });
await mkdir('artifacts/raw', { recursive: true });
const pause = (page, ms = 1200) => page.waitForTimeout(ms);
async function chat(page, prompt) {
  const count = await page.locator('#eyg-phantom .message.assistant').count();
  const input = page.getByRole('textbox', { name: 'Message Phantom' });
  await input.click();
  await input.pressSequentially(prompt, { delay: 42 });
  await pause(page, 600);
  await page.getByRole('button', { name: 'Send message', exact: true }).click();
  await page.waitForFunction(
    (n) =>
      document.querySelector('#eyg-phantom').shadowRoot.querySelectorAll('.message.assistant')
        .length > n,
    count,
  );
  assert.equal(
    await page.locator('#eyg-phantom .run-error').count(),
    0,
    await page.locator('#eyg-phantom .feed').innerText(),
  );
  await pause(page);
}
try {
  const gallery = await browser.newPage({ viewport: { width: 1440, height: 1100 } });
  await gallery.goto(origin);
  await gallery.screenshot({ path: 'artifacts/gallery.png', fullPage: true });
  await gallery.setViewportSize({ width: 390, height: 844 });
  await gallery.screenshot({ path: 'artifacts/gallery-mobile.png', fullPage: true });
  await gallery.close();
  for (const name of process.argv.includes('--screenshots-only') ? [] : ['di', 'sj']) {
    const context = await browser.newContext({
      viewport: { width: 1440, height: 1000 },
      recordVideo: { dir: 'artifacts/raw', size: { width: 1440, height: 1000 } },
      reducedMotion: 'reduce',
    });
    const page = await context.newPage();
    await page.goto(origin + '/demo/' + name + '.html');
    await pause(page);
    await page.getByRole('button', { name: 'Inject Phantom' }).click();
    await pause(page, 2200);
    await page.getByRole('button', { name: 'Run injection' }).click();
    await pause(page, 1400);
    await page.screenshot({ path: 'artifacts/' + name + '-before.png' });
    if (name === 'di') {
      await chat(page, 'Make the graph bigger');
      assert.ok((await page.locator('#stockholm-chart').boundingBox()).height >= 390);
      await page.locator('#eyg-phantom .code').last().locator('summary').click();
      await pause(page, 1600);
      await page.locator('#eyg-phantom .code').last().locator('summary').click();
      await chat(page, 'Add a subtle hover effect to the graph');
      await page.locator('#stockholm-chart').hover();
      await pause(page, 1600);
      await chat(page, 'Add a focus mode button');
      await page.screenshot({ path: 'artifacts/di-after.png' });
      await page.getByRole('button', { name: 'Toggle focus mode', exact: true }).click();
      await pause(page, 1000);
      await page.getByRole('button', { name: 'Toggle focus mode', exact: true }).click();
      await pause(page, 1200);
    } else {
      await chat(page, 'Shortlist the two cheapest direct trains');
      assert.equal(await page.locator('[data-eyg-shortlist=true]').count(), 2);
      const card = page.locator('#eyg-phantom .run').last();
      await card.locator('.effect-details summary').click();
      await pause(page, 1800);
      await card.locator('.effect-details summary').click();
      await card.locator('.code summary').click();
      await pause(page, 1800);
      await card.locator('.code summary').click();
      await chat(page, 'Add a button to toggle my shortlist');
      await page.screenshot({ path: 'artifacts/sj-after.png' });
      await page.getByRole('button', { name: 'Toggle my shortlist', exact: true }).click();
      await pause(page, 1000);
      await page.getByRole('button', { name: 'Toggle my shortlist', exact: true }).click();
      await pause(page, 1200);
    }
    await page.getByRole('button', { name: 'Dock left', exact: true }).click();
    await pause(page, 900);
    await page.getByRole('button', { name: 'Float panel', exact: true }).click();
    const grip = await page.locator('#eyg-phantom .brand').boundingBox();
    await page.mouse.move(grip.x + 20, grip.y + 15);
    await page.mouse.down();
    await page.mouse.move(1000, 150, { steps: 30 });
    await page.mouse.up();
    await pause(page);
    await page.getByRole('button', { name: 'Dock right', exact: true }).click();
    await pause(page, 1600);
    await writeFile(
      'artifacts/' + name + '-transcript.txt',
      await page.locator('#eyg-phantom .feed').innerText(),
    );
    const video = page.video();
    await context.close();
    const raw = await video.path();
    const converted = spawnSync(
      'ffmpeg',
      [
        '-y',
        '-i',
        raw,
        '-c:v',
        'libx264',
        '-preset',
        'fast',
        '-crf',
        '23',
        '-pix_fmt',
        'yuv420p',
        '-movflags',
        '+faststart',
        'artifacts/' + name + '-demo.mp4',
      ],
      { stdio: 'pipe' },
    );
    if (converted.status !== 0) throw new Error(converted.stderr.toString());
    console.log('Recorded artifacts/' + name + '-demo.mp4');
  }
} finally {
  await browser.close();
  await new Promise((resolve) => server.close(resolve));
}
