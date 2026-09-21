import { chromium } from 'playwright';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { spawnSync } from 'node:child_process';
import assert from 'node:assert/strict';
import { serve } from '../server.mjs';

const server = await serve(0),
  origin = 'http://127.0.0.1:' + server.address().port;
const browser = await chromium.launch({ headless: true });
await mkdir('artifacts/raw', { recursive: true });
const pause = (page, ms = 1400) => page.waitForTimeout(ms);
async function ask(page, prompt) {
  const count = await page.locator('#eyg-phantom .message.assistant').count();
  const input = page.getByRole('textbox', { name: 'Message Phantom' });
  await input.click();
  await input.pressSequentially(prompt, { delay: 40 });
  await pause(page, 500);
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
async function injectionCard(page) {
  const bundle = await readFile('dist/phantom.js', 'utf8');
  await page.evaluate((bundle) => {
    const host = document.createElement('div');
    host.id = 'recording-injection';
    host.dataset.phantomOwned = '';
    host.style.cssText = 'position:fixed;left:30px;top:28px;width:450px;z-index:2147483647';
    const shadow = host.attachShadow({ mode: 'open' });
    shadow.innerHTML =
      '<style>*{box-sizing:border-box}section{background:#192c22;color:#e4ecd9;border:1px solid #58704b;border-radius:16px;padding:26px;font:13px/1.7 system-ui;box-shadow:0 20px 60px #12231935}small{font:10px monospace;letter-spacing:1px;color:#aebf99}h1{font:30px Georgia;margin:14px 0}p{color:#b8c9a5}pre{background:#102117;color:#d5e4c4;padding:17px;border-radius:8px;font:11px/1.8 monospace;white-space:pre-wrap;overflow-wrap:anywhere}button{padding:11px 16px;border:0;border-radius:7px;background:#d3e4b1;color:#294029;font:600 12px system-ui;cursor:pointer}</style><section><small>PHANTOM / LIVE SITE WALKTHROUGH</small><h1>One script. Your page.</h1><p>Run this injection recipe from the browser console. The button below runs this exact code.</p><pre></pre><button>Run injection ↗</button><p style="font-size:10px;margin-bottom:0">Live website · mock agent · real EYG interpreter</p></section>';
    shadow.querySelector('p').textContent =
      'Open DevTools → Sources → Snippets. Paste the built phantom.js bundle and run it. This recorder inserts that same local bundle below.';
    shadow.querySelector('pre').textContent =
      '// Local bundle: dist/phantom.js\n// ' +
      Math.round(bundle.length / 1024) +
      ' KB · parser + interpreter + assistant\n\n' +
      "const script = document.createElement('script');\nscript.textContent = bundle;\ndocument.head.append(script);";
    shadow.querySelector('button').addEventListener('click', () => {
      const script = document.createElement('script');
      script.textContent = bundle;
      document.head.append(script);
      if (window.Phantom) host.remove();
      else shadow.querySelector('p').textContent = 'The page blocked script injection.';
    });
    document.body.append(host);
  }, bundle);
  await pause(page, 2600);
  await page.getByRole('button', { name: 'Run injection' }).click();
  await page.getByRole('textbox', { name: 'Message Phantom' }).waitFor({ timeout: 15000 });
}
try {
  for (const name of process.argv[2] ? [process.argv[2]] : ['di', 'sj']) {
    const context = await browser.newContext({
      viewport: { width: 1920, height: 1080 },
      recordVideo: { dir: 'artifacts/raw', size: { width: 1920, height: 1080 } },
      locale: 'sv-SE',
    });
    const page = await context.newPage();
    const url = 'https://www.' + name + '.se/';
    const response = await page.goto(url, { waitUntil: 'domcontentloaded' });
    assert.equal(response.status(), 200);
    await pause(page, 2400);
    if (name === 'di') {
      await page.getByRole('button', { name: 'Inställningar', exact: true }).click();
      await page.getByRole('button', { name: /Neka allt:/ }).click();
      await page.locator('.live-box__index-graph').scrollIntoViewIfNeeded();
      await page.evaluate(() => scrollBy(0, 160));
    } else {
      await page.getByRole('button', { name: 'Endast nödvändiga cookies' }).click();
      await page.getByRole('link', { name: 'Sök resa', exact: true }).click();
      for (const [label, city] of [
        ['Från', 'Stockholm'],
        ['Till', 'Göteborg'],
      ]) {
        const input = page.getByRole('combobox', { name: label, exact: true });
        await input.fill(city);
        await pause(page, 1200);
        await input.press('ArrowDown');
        await input.press('Enter');
      }
      await page.getByRole('button', { name: 'Sök resa', exact: true }).click();
      await page.getByRole('button', { name: /Avgår/ }).first().waitFor();
      await page.getByRole('button', { name: /Avgår/ }).first().scrollIntoViewIfNeeded();
    }
    await pause(page);
    await injectionCard(page);
    await page
      .getByRole('button', { name: name === 'di' ? 'Dock left' : 'Dock right', exact: true })
      .click();
    await pause(page);
    await page.screenshot({ path: 'artifacts/' + name + '-live-before.png' });
    if (name === 'di') {
      const graph = page.locator('.live-box__index-graph');
      const before = await graph.boundingBox();
      const plotBefore = await graph.locator('svg').boundingBox();
      await ask(page, 'Make the graph bigger');
      assert.ok((await graph.boundingBox()).height > before.height);
      assert.ok((await graph.locator('svg').boundingBox()).height > plotBefore.height);
      await graph.scrollIntoViewIfNeeded();
      await page.locator('#eyg-phantom .code').last().locator('summary').click();
      await pause(page, 1800);
      await page.locator('#eyg-phantom .code').last().locator('summary').click();
      await ask(page, 'Add a subtle hover effect to the graph');
      await graph.hover();
      await pause(page);
      await ask(page, 'Add a focus mode button');
      await page.getByRole('button', { name: 'Toggle focus mode', exact: true }).click();
      await pause(page);
      await page.getByRole('button', { name: 'Toggle focus mode', exact: true }).click();
    } else {
      await ask(page, 'Shortlist the two cheapest direct trains');
      assert.equal(await page.locator('[data-eyg-shortlist=true]').count(), 2);
      await page
        .locator('[data-eyg-shortlist=true]')
        .first()
        .evaluate((node) => node.scrollIntoView({ block: 'center' }));
      const card = page.locator('#eyg-phantom .run').last();
      await card.locator('.effect-details summary').click();
      await pause(page, 1800);
      await card.locator('.effect-details summary').click();
      await card.locator('.code summary').click();
      await pause(page, 1800);
      await card.locator('.code summary').click();
      await ask(page, 'Add a button to toggle my shortlist');
      await page.getByRole('button', { name: 'Toggle my shortlist', exact: true }).click();
      await pause(page);
      await page.getByRole('button', { name: 'Toggle my shortlist', exact: true }).click();
    }
    if (name === 'sj')
      await page
        .locator('[data-eyg-shortlist=true]')
        .first()
        .evaluate((node) => node.scrollIntoView({ block: 'center' }));
    await pause(page, 2200);
    await page.screenshot({ path: 'artifacts/' + name + '-live-after.png' });
    await writeFile(
      'artifacts/' + name + '-live-transcript.txt',
      'Recorded ' +
        new Date().toISOString() +
        '\n' +
        page.url() +
        '\n\n' +
        (await page.locator('#eyg-phantom .feed').innerText()),
    );
    const video = page.video();
    await context.close();
    const converted = spawnSync(
      'ffmpeg',
      [
        '-y',
        '-i',
        await video.path(),
        '-vf',
        'scale=1600:900',
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
        'artifacts/' + name + '-live.mp4',
      ],
      { stdio: 'pipe' },
    );
    if (converted.status !== 0) throw new Error(converted.stderr.toString());
    console.log('Recorded and verified artifacts/' + name + '-live.mp4');
  }
} finally {
  await browser.close();
  await new Promise((resolve) => server.close(resolve));
}
