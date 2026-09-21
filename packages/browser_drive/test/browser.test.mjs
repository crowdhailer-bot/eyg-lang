import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { chromium } from 'playwright';
import { readFile } from 'node:fs/promises';
import { serve } from '../server.mjs';

let browser, server, origin;
before(async () => {
  server = await serve(0);
  origin = 'http://127.0.0.1:' + server.address().port;
  browser = await chromium.launch({ headless: true });
});
after(async () => {
  await browser?.close();
  await new Promise((resolve) => server?.close(resolve));
});
async function pageFor(name = 'di') {
  const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
  await page.goto(origin + '/demo/' + name + '.html');
  await page.evaluate(async () => {
    window.api = await import('/dist/eyg.js');
  });
  return page;
}
async function inject(page) {
  await page.getByRole('button', { name: 'Inject Phantom' }).click();
  await page.getByRole('button', { name: 'Run injection' }).click();
  await page.getByRole('textbox', { name: 'Message Phantom' }).waitFor();
}
async function chat(page, prompt) {
  const count = await page.locator('#eyg-phantom .message.assistant').count();
  await page.getByRole('textbox', { name: 'Message Phantom' }).fill(prompt);
  await page.getByRole('button', { name: 'Send message' }).click();
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
}

test('gallery assets and links work at the root URL on desktop and mobile', async () => {
  const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
  const failures = [];
  page.on('response', (response) => {
    if (response.status() >= 400) failures.push(response.url());
  });
  await page.goto(origin);
  assert.equal(
    await page.locator('.cards').evaluate((node) => getComputedStyle(node).display),
    'grid',
  );
  assert.equal(
    new URL(
      await page.getByRole('link', { name: 'Try the demo' }).first().getAttribute('href'),
      await page.evaluate(() => document.baseURI),
    ).pathname,
    '/demo/di.html',
  );
  await page.setViewportSize({ width: 390, height: 844 });
  assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth));
  assert.deepEqual(failures, []);
  const syntax = await readFile('../../guides/syntax.md', 'utf8');
  const prompt = await page.evaluate(async () =>
    (await import('/dist/eyg.js')).systemPrompt({ site: 'test' }),
  );
  assert.ok(prompt.endsWith(syntax));
  assert.match(prompt, /SetAttribute/);
  await page.close();
});

test('real parser/interpreter: values, context, effects, handlers and errors', async () => {
  const page = await pageFor();
  const result = await page.evaluate(async () => {
    const trace = [];
    const value = await api.runEyg(
      'let x = perform Double(context.number)\n{answer: !int_add(x, 2), names: ["a", "b"]}',
      {
        context: { number: 20 },
        effects: { Double: (n) => n * 2 },
        onEffect: (e) => trace.push(e.status),
      },
    );
    const errors = [];
    for (const code of [
      'perform Fetch("https://example.com")',
      'import "./secret.eyg"',
      'let x =',
      'window',
      'perform toString({})',
    ]) {
      try {
        await api.runEyg(code);
        errors.push('unexpected success');
      } catch (error) {
        errors.push(error.message);
      }
    }
    return { value, trace, errors };
  });
  assert.deepEqual(result.value, { answer: 42, names: ['a', 'b'] });
  assert.deepEqual(result.trace, ['running', 'done']);
  assert.ok(result.errors.every((error) => error !== 'unexpected success'));
  assert.match(result.errors[0], /not allowed/);
  await page.close();
});
test('execution budgets and cancellation leave the page responsive', async () => {
  const page = await pageFor();
  const errors = await page.evaluate(async () => {
    const errors = [];
    for (const code of [
      'let forever = !fix((self, x) -> { self(x) }) forever({})',
      'let many = !fix((self, n) -> { let _ = perform Tick(n) self(!int_add(n, 1)) }) many(0)',
    ]) {
      try {
        await api.runEyg(code, { effects: { Tick: () => ({}) } });
      } catch (e) {
        errors.push(e.message);
      }
    }
    const controller = new AbortController();
    const promise = api.runEyg('perform Pause({})', {
      effects: { Pause: () => new Promise(() => {}) },
      signal: controller.signal,
    });
    setTimeout(() => controller.abort(), 30);
    try {
      await promise;
    } catch (e) {
      errors.push(e.message);
    }
    try {
      await api.runEyg('perform Pause({})', {
        effects: { Pause: () => new Promise(() => {}) },
        timeout: 40,
      });
    } catch (e) {
      errors.push(e.message);
    }
    return errors;
  });
  assert.match(errors[0], /instruction limit/);
  assert.match(errors[1], /effect limit/);
  assert.match(errors[2], /cancelled/);
  assert.match(errors[3], /time limit/);
  await page.close();
});
test('capabilities reject resource CSS and executable attributes; failed writes roll back', async () => {
  const page = await pageFor();
  const result = await page.evaluate(async () => {
    const harness = api.createBrowserHarness();
    const nodes = harness.effects.GetElements('#stockholm-chart');
    const errors = [];
    for (const css of [
      '@import "https://example.com/a.css";',
      'body {background-image:url(https://example.com)}',
      'body {color:var(--secret)}',
      'body {position:fixed}',
      'body {color: red; & div {position: fixed}}',
      'body{color:r\\65 d}',
    ]) {
      harness.begin();
      try {
        harness.effects.WriteCSS(css);
        errors.push('unexpected success');
      } catch (error) {
        errors.push(error.message);
      } finally {
        harness.rollback();
      }
    }
    harness.begin();
    try {
      harness.effects.SetAttribute({ id: nodes[0].id, name: 'onclick', value: 'alert(1)' });
    } catch (error) {
      errors.push(error.message);
    }
    harness.rollback();
    let round = 0;
    await api.runAgent({
      messages: [{ role: 'user', content: 'test' }],
      harness,
      complete: async () =>
        ++round === 1
          ? {
              type: 'tool_call',
              name: 'run_eyg',
              arguments: {
                code: 'let _ = perform WriteCSS("#stockholm-chart { min-height: 999px; }") perform Forbidden({})',
              },
            }
          : { type: 'message', content: 'failed safely' },
    });
    const result = {
      errors,
      height: document.querySelector('#stockholm-chart').getBoundingClientRect().height,
      canUndo: harness.canUndo,
    };
    harness.destroy();
    return result;
  });
  assert.ok(result.errors.every((error) => error !== 'unexpected success'));
  assert.equal(result.errors.length, 7);
  assert.ok(result.height < 999);
  assert.equal(result.canUndo, false);
  await page.close();
});
test('DI chat enlarges, hovers, adds a working toggle, and cleans up', async () => {
  const page = await pageFor();
  const before = await page.locator('#stockholm-chart').boundingBox();
  const plotBefore = await page.locator('#stockholm-chart svg').boundingBox();
  await inject(page);
  await chat(page, 'Make the graph bigger');
  assert.ok((await page.locator('#stockholm-chart').boundingBox()).height > before.height);
  assert.ok((await page.locator('#stockholm-chart svg').boundingBox()).height > plotBefore.height);
  assert.equal(await page.locator('#eyg-phantom .code[open]').count(), 0);
  await chat(page, 'Add a hover effect');
  await page.locator('#stockholm-chart').hover();
  await page.waitForTimeout(300);
  assert.notEqual(
    await page.locator('#stockholm-chart').evaluate((node) => getComputedStyle(node).transform),
    'none',
  );
  await chat(page, 'Add a focus mode button');
  const toggle = page.getByRole('button', { name: 'Toggle focus mode', exact: true });
  await toggle.click();
  assert.equal(await toggle.getAttribute('aria-pressed'), 'false');
  assert.ok((await page.locator('#stockholm-chart').boundingBox()).height < 390);
  await toggle.click();
  assert.ok((await page.locator('#stockholm-chart').boundingBox()).height >= 390);
  await page.getByRole('button', { name: 'Undo change ↶', exact: true }).click();
  assert.equal(await toggle.count(), 0);
  await page.getByRole('button', { name: 'Close and undo changes' }).click();
  assert.equal(await page.locator('[data-phantom-owned]').count(), 0);
  assert.equal(
    await page.locator('#stockholm-chart').evaluate((node) => node.getBoundingClientRect().height),
    before.height,
  );
  await page.close();
});
test('SJ ranks visible direct fares, collapses a long trace, and preserves undo', async () => {
  const page = await pageFor('sj');
  await inject(page);
  await chat(page, 'Shortlist the two cheapest direct trains');
  assert.deepEqual(
    await page.locator('[data-eyg-shortlist=true]').evaluateAll((nodes) => nodes.map((n) => n.id)),
    ['train-2', 'train-4'],
    await page.locator('#eyg-phantom .feed').innerText(),
  );
  assert.equal(await page.locator('#eyg-phantom .effect.done').count(), 8);
  const effects = page.locator('#eyg-phantom .run').last().locator('.effect-details');
  assert.equal(await effects.getAttribute('open'), null);
  await effects.locator('summary').click();
  assert.notEqual(await effects.getAttribute('open'), null);
  await page.locator('#eyg-phantom .run').last().locator('.code summary').click();
  assert.match(
    await page.locator('#eyg-phantom .run').last().locator('pre').innerText(),
    /SetAttribute/,
  );
  await page.getByRole('button', { name: 'Undo change ↶', exact: true }).click();
  assert.equal(await page.locator('[data-eyg-shortlist]').count(), 0);
  await page.close();
});
test('SJ handles Swedish live-site fare labels and unlabelled departure cards', async () => {
  const page = await pageFor('sj');
  await page.evaluate(() => {
    const list = document.querySelector('[aria-label="Available departures"]');
    list.replaceChildren();
    for (const [price, changes] of [
      [475, 0],
      [405, 0],
      [335, 0],
      [245, 0],
      [100, 2],
    ]) {
      const button = document.createElement('button');
      const title = document.createElement('h3');
      title.textContent = '18:16–21:47';
      const detail = document.createElement('p');
      detail.textContent =
        'pris från ' + price + ' svenska kronor, Restid 3 timmar, ' + changes + ' byten';
      button.append(title, detail);
      list.append(button);
    }
  });
  await inject(page);
  await chat(page, 'Shortlist the two cheapest direct trains');
  const selected = await page.locator('[data-eyg-shortlist=true]').allTextContents();
  assert.equal(selected.length, 2);
  assert.ok(selected.some((text) => text.includes('335 svenska kronor')));
  assert.ok(selected.some((text) => text.includes('245 svenska kronor')));
  await page.close();
});

test('the agent rejects other tools, bounds turns, and exposes errors to its provider', async () => {
  const page = await pageFor();
  const result = await page.evaluate(async () => {
    const harness = api.createBrowserHarness();
    const messages = [{ role: 'user', content: 'test' }],
      errors = [];
    try {
      await api.runAgent({
        messages,
        harness,
        complete: async () => ({ type: 'tool_call', name: 'javascript', arguments: { code: '1' } }),
      });
    } catch (e) {
      errors.push(e.message);
    }
    let rounds = 0;
    try {
      await api.runAgent({
        messages,
        harness,
        complete: async () => {
          rounds++;
          return { type: 'tool_call', name: 'run_eyg', arguments: { code: 'perform Nope({})' } };
        },
      });
    } catch (e) {
      errors.push(e.message);
    }
    const trace = [];
    const abort = new AbortController();
    const task = api.runEyg('perform Wait({})', {
      signal: abort.signal,
      effects: { Wait: () => new Promise(() => {}) },
      onEffect: (event) => {
        trace.push(event.status);
        if (event.status === 'running') setTimeout(() => abort.abort(), 10);
      },
    });
    try {
      await task;
    } catch {}
    harness.destroy();
    return { errors, rounds, trace };
  });
  assert.equal(result.rounds, 8);
  assert.match(result.errors[0], /must return/);
  assert.match(result.errors[1], /eight turns/);
  assert.deepEqual(result.trace, ['running', 'error']);
  await page.close();
});
test('multiple host buttons stay synchronized across toggling, new runs and undo', async () => {
  const page = await pageFor();
  await page.evaluate(() => {
    window.harness = api.createBrowserHarness();
    harness.begin();
    harness.effects.WriteCSS('#stockholm-chart {min-height: 500px}');
    harness.commit();
    for (const label of ['First view', '<img src=x onerror=alert(1)>']) {
      harness.begin();
      harness.effects.InsertButton(label);
      harness.commit();
    }
  });
  const first = page.getByRole('button', { name: 'First view', exact: true });
  const second = page.getByRole('button', { name: '<img src=x onerror=alert(1)>', exact: true });
  await first.click();
  assert.equal(await second.getAttribute('aria-pressed'), 'false');
  assert.ok((await page.locator('#stockholm-chart').boundingBox()).height < 500);
  await page.evaluate(() => {
    harness.begin();
    harness.effects.WriteCSS('#stockholm-chart {color: green}');
    harness.commit();
  });
  assert.equal(await first.getAttribute('aria-pressed'), 'true');
  assert.equal(await second.getAttribute('aria-pressed'), 'true');
  await second.click();
  assert.equal(await first.getAttribute('aria-pressed'), 'false');
  await page.evaluate(() => harness.destroy());
  assert.equal(await page.locator('[data-phantom-owned]').count(), 0);
  await page.close();
});

test('injection is idempotent; docking, dragging, minimization and mobile fit', async () => {
  const page = await pageFor();
  await inject(page);
  await page.addScriptTag({ url: origin + '/dist/phantom.js' });
  assert.equal(await page.locator('#eyg-phantom').count(), 1);
  await page.getByRole('button', { name: 'Dock left', exact: true }).click();
  assert.equal((await page.locator('#eyg-phantom').boundingBox()).x, 12);
  await page.getByRole('button', { name: 'Float panel', exact: true }).click();
  const header = await page.locator('#eyg-phantom .brand').boundingBox();
  await page.mouse.move(header.x + 30, header.y + 10);
  await page.mouse.down();
  await page.mouse.move(200, 130);
  await page.mouse.up();
  const moved = await page.locator('#eyg-phantom').boundingBox();
  assert.ok(moved.x < 250);
  await page.getByRole('button', { name: 'Minimize', exact: true }).click();
  await page.getByRole('button', { name: 'Open Phantom', exact: true }).click();
  await page.setViewportSize({ width: 390, height: 844 });
  await page.waitForFunction(
    () => document.querySelector('#eyg-phantom').getBoundingClientRect().width < 390,
  );
  const mobile = await page.locator('#eyg-phantom').boundingBox();
  assert.ok(mobile.x >= 0 && mobile.x + mobile.width <= 390);
  assert.ok(mobile.height < 844);
  await page.close();
});
