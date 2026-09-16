import { test, expect } from '@playwright/test';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { agent, file } from './agent.mjs';

const departures = file('index.html', 'text/html', `<!doctype html><html><head><style>
  body { font-family: sans-serif; margin: 16px; }
  li[hidden] { display: none; }
</style></head><body>
  <h1>Departures</h1>
  <label>Route <input id="route" placeholder="Filter routes"></label>
  <ul><li>214 Highgate Village</li><li>C2 Parliament Hill</li><li>88 Clapham Common</li></ul>
  <label><input type="checkbox" id="live"> Live</label>
  <select id="stop"><option value="n">Northbound</option><option value="s">Southbound</option></select>
  <button id="refresh" disabled>Refresh</button>
  <p id="status">Idle</p>
  <script>
    document.getElementById('route').addEventListener('input', event => {
      for (const item of document.querySelectorAll('li')) item.hidden = !item.textContent.includes(event.target.value);
    });
    document.getElementById('live').addEventListener('change', event => {
      document.getElementById('refresh').disabled = !event.target.checked;
    });
    document.getElementById('refresh').addEventListener('click', () => {
      document.getElementById('status').textContent = 'Refreshed ' + document.getElementById('stop').value;
    });
  </script>
</body></html>`);

// Results are pretty printed, compare them on one line.
const flat = text => text.replace(/\s*\n\s*/g, ' ').replaceAll('( ', '(').replaceAll(' )', ')');

const puppet = (locator, action, timeout = 2000) =>
  `perform Puppet({page: Artifact("test"), locator: [${locator}], action: ${action}, timeout: ${timeout}})`;

test('an agent fills, checks, selects and clicks inside an artifact', async ({ page }) => {
  const overlay = await agent(page);
  const inner = await overlay.show([departures]);
  const result = await overlay.run(`let _ = ${puppet('Placeholder("filter")', 'Fill("C2")')}
let _ = ${puppet('Role({role: "listitem", name: ""})', 'Expect(ToHaveCount(3))')}
let _ = ${puppet('Label("live")', 'SetChecked(True({}))')}
let _ = ${puppet('Css("#stop")', 'SelectOption("Southbound")')}
let _ = ${puppet('Role({role: "button", name: "refresh"})', 'Click({})')}
let _ = ${puppet('Css("#status")', 'Expect(ToHaveText("Refreshed s"))')}
let visible = ${puppet('Text("Highgate")', 'IsVisible({})')}
let texts = ${puppet('Css("li"), HasText("Hill")', 'AllTextContents({})')}
{visible, texts, heading: ${puppet('Role({role: "heading", name: ""})', 'TextContent({})')}}`);
  const content = flat(result.content);
  expect(content).toContain('heading: Ok(Text("Departures"))');
  expect(content).toContain('texts: Ok(Texts(["C2 Parliament Hill"]))');
  expect(content).toContain('visible: Ok(Flag(False({})))');
  await expect(inner.locator('#status')).toHaveText('Refreshed s');
  await expect(inner.locator('#route')).toHaveValue('C2');
});

test('failed actions return reasons to the agent', async ({ page }) => {
  const overlay = await agent(page);
  await overlay.show([departures]);
  const result = await overlay.run(`let strict = ${puppet('Css("li")', 'Click({})')}
let missing = ${puppet('Css("#missing")', 'TextContent({})', 200)}
let disabled = ${puppet('Css("#refresh")', 'Click({})', 200)}
let expectation = ${puppet('Css("#status")', 'Expect(ToHaveText("Done"))', 200)}
let hidden = perform Puppet({page: Artifact("other"), locator: [], action: Count({}), timeout: 200})
{strict, missing, disabled, expectation, hidden}`);
  const content = flat(result.content);
  expect(content).toContain('strict: Error("css=\\"li\\" matched 3 elements');
  expect(content).toContain('missing: Error("Timeout 200ms: css=\\"#missing\\" matched no elements")');
  expect(content).toContain('disabled: Error("Timeout 200ms: css=\\"#refresh\\" is disabled")');
  expect(content).toContain('expectation: Error("Timeout 200ms: expected css=\\"#status\\" to have text \\"Done\\", found \\"Idle\\"")');
  expect(content).toContain('hidden: Error("other is not shown, use Show before Puppet")');
});

test('screenshots are returned as images and shown with the tool result', async ({ page }) => {
  const overlay = await agent(page);
  await overlay.show([departures]);
  const result = await overlay.run(`let shot = ${puppet('', 'Screenshot({})', 5000)}
match shot {
  Ok(reply) -> {
    match reply {
      Image(png) -> { !int_compare(!binary_size(png), 1000) }
      | (_) -> { !never(perform Abort("not an image")) }
    }
  }
  Error(reason) -> { !never(perform Abort(reason)) }
}`);
  expect(result.content).toBe('Gt({})');
  expect(result.images).toHaveLength(1);
  const png = Buffer.from(result.images[0], 'base64');
  expect(png.subarray(1, 4).toString()).toBe('PNG');
  await expect(page.locator('.tool-images img')).toHaveCount(1);
});

test('an artifact cannot drive the puppet of another artifact', async ({ page }) => {
  const overlay = await agent(page);
  const target = await overlay.show([file('index.html', 'text/html', '<body><button onclick="this.textContent=\'pressed\'">Target</button></body>')], 'target');
  await overlay.run('perform Show({item: Artifact("target"), origin: {x: 0, y: 0}, size: {x: 500, y: 1000}})');
  await overlay.run(`let _ = perform Artifact({name: "attacker", bundle: [${file('index.html', 'text/html', `<body><script>
    const sibling = [...Array(parent.parent.frames.length).keys()].map(i => parent.parent.frames[i]).find(frame => frame !== parent);
    const channel = new MessageChannel();
    channel.port1.onmessage = () => { document.body.dataset.reply = 'received'; };
    sibling[0].postMessage({ id: 'attack', request: { locator: [{ type: 'css', value: 'button' }], action: { type: 'click' }, timeout: 100 } }, '*', [channel.port2]);
    document.body.dataset.sent = 'yes';
  </script></body>`)}]})
perform Show({item: Artifact("attacker"), origin: {x: 500, y: 0}, size: {x: 500, y: 1000}})`);
  const attacker = page.frameLocator('iframe.artifact-preview[title="attacker"]').frameLocator('iframe');
  await expect(attacker.locator('body')).toHaveAttribute('data-sent', 'yes');
  await page.waitForTimeout(500);
  await expect(target.getByRole('button')).toHaveText('Target');
  await expect(attacker.locator('body')).not.toHaveAttribute('data-reply');
});

test('the EYG playwright library checks and drives an artifact', async ({ page }) => {
  const library = readFileSync(resolve('../../eyg_packages/playwright/index.eyg'), 'utf8');
  const overlay = await agent(page);
  const inner = await overlay.show([departures]);
  const result = await overlay.run(`let playwright = (_) -> {
${library}
}
let pw = playwright({})
let board = pw.page("test")
let _ = pw.fill(pw.get_by_placeholder(board, "filter"), "88")
let _ = pw.expect(pw.first(pw.locator(board, "li"))).to_be_hidden({})
let _ = pw.check(pw.get_by_label(board, "live"))
let _ = pw.click(pw.get_by_role(board, "button", "refresh"))
let _ = pw.expect(pw.locator(board, "#status")).to_have_text("Refreshed n")
let png = pw.screenshot(pw.get_by_role(board, "list", ""))
{routes: pw.all_text_contents(pw.locator(board, "li:not([hidden])")), image: !int_compare(!binary_size(png), 100)}`);
  expect(flat(result.content)).toBe('{image: Gt({}), routes: ["88 Clapham Common"]}');
  expect(result.images).toHaveLength(1);
  await expect(inner.locator('#status')).toHaveText('Refreshed n');
});
