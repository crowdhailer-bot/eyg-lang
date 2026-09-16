// Record the Overlay artifacts demo, see README.md.
//
// Model replies are scripted by mock_ollama.mjs. Everything else is real:
// Overlay runs the EYG programs, fetches live data and shares to a hub.
import { chromium } from '@playwright/test';
import { spawn, spawnSync } from 'node:child_process';
import { mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { prompts, serve } from './mock_ollama.mjs';

const root = resolve(import.meta.dirname, '..');
const hub = process.env.EYG_HUB ?? 'http://127.0.0.1:8080';
const port = process.env.OVERLAY_PORT ?? '5380';
const ollamaPort = Number(process.env.OLLAMA_PORT ?? '11434');
const video = process.env.VIDEO !== '0';
// Videos are kept in recordings/, frames, stills and cards are made in recordings/work/.
const out = resolve(root, 'recordings');
const work = resolve(out, 'work');
const frames = resolve(work, 'frames');
const viewport = { width: 1600, height: 900 };
const scale = 1.2;
const pause = ms => new Promise(done => setTimeout(done, ms));

rmSync(frames, { recursive: true, force: true });
mkdirSync(frames, { recursive: true });

const shared = spawnSync('eyg', ['share', 'demo/studio.eyg'], { cwd: root, env: { ...process.env, EYG_ORIGIN: hub }, encoding: 'utf8' });
if (shared.status !== 0) throw new Error(`Sharing the studio context failed: ${shared.stderr}${shared.stdout}`);
const reference = shared.stdout.trim().split('\n').pop();
console.log('studio context', reference);

const results = [];
const mock = serve({ port: ollamaPort, onToolResult: message => results.push(message.content) });

const vite = spawn('bun', ['--bun', 'run', 'dev', '--', '--host', '127.0.0.1', '--port', port, '--strictPort'], {
  cwd: root,
  env: { ...process.env, EYG_HUB: hub, OLLAMA_ORIGIN: `http://127.0.0.1:${ollamaPort}` },
});
await new Promise((ready, failed) => {
  vite.stdout.on('data', chunk => String(chunk).includes('ready in') && ready());
  vite.on('exit', code => failed(new Error(`vite exited with ${code}`)));
});

const browser = await chromium.launch();
const context = await browser.newContext({ viewport, deviceScaleFactor: scale });
await context.addInitScript(() => {
  if (window !== window.top) return;
  sessionStorage.setItem('overlay.llm.provider', 'ollama');
  sessionStorage.setItem('overlay.llm.model', 'scripted-demo');
  sessionStorage.setItem('overlay.llm.api_key', 'not-used');
});

// Frames from every page the demo visits, in order.
const timeline = [];
async function capture(page) {
  if (!video) return async () => {};
  const session = await context.newCDPSession(page);
  session.on('Page.screencastFrame', ({ data, metadata, sessionId }) => {
    const file = `${String(timeline.length).padStart(6, '0')}.jpg`;
    writeFileSync(resolve(frames, file), Buffer.from(data, 'base64'));
    timeline.push({ file, time: metadata.timestamp });
    session.send('Page.screencastFrameAck', { sessionId }).catch(() => {});
  });
  await session.send('Page.startScreencast', { format: 'jpeg', quality: 94, maxWidth: 1920, maxHeight: 1080, everyNthFrame: 1 });
  return () => session.send('Page.stopScreencast').catch(() => {});
}

// A pointer and captions are drawn into the page, a headless browser shows neither.
const stage = font => {
  if (document.getElementById('demo-stage')) return;
  const style = document.createElement('style');
  style.id = 'demo-stage';
  style.textContent = `
    @font-face { font-family: DemoInter; src: url(data:font/woff2;base64,${font}); font-weight: 100 900; }
    #demo-cursor { position: fixed; left: 0; top: 0; z-index: 2147483647; width: 26px; height: 26px; pointer-events: none; transition: transform 0.7s cubic-bezier(0.3, 0.7, 0.2, 1); filter: drop-shadow(0 2px 3px rgba(0,0,0,.35)); }
    #demo-cursor.press svg { transform: scale(0.85); }
    #demo-cursor svg { transition: transform 0.12s ease; transform-origin: 4px 4px; }
    #demo-caption { position: fixed; left: 50%; top: 12px; z-index: 2147483646; transform: translate(-50%, -12px); max-width: 760px; padding: 12px 20px; border-radius: 999px; background: rgba(12, 13, 18, 0.88); color: #fff; font: 600 17px/1.3 DemoInter, system-ui, sans-serif; letter-spacing: -0.01em; box-shadow: 0 12px 32px -12px rgba(0,0,0,.5); opacity: 0; transition: opacity 0.45s ease, transform 0.45s ease; pointer-events: none; white-space: nowrap; }
    #demo-caption.show { opacity: 1; transform: translate(-50%, 0); }
    #demo-caption b { color: #b3a8ff; font-weight: 650; }
    #demo-heartbeat { position: fixed; left: 0; bottom: 0; z-index: 2147483647; width: 1px; height: 1px; pointer-events: none; animation: demo-beat 1s steps(5) infinite; }
    @keyframes demo-beat { from { background: rgba(128, 128, 128, 0.01); } to { background: rgba(128, 128, 128, 0.03); } }
  `;
  document.head.append(style);
  const cursor = document.createElement('div');
  cursor.id = 'demo-cursor';
  cursor.innerHTML = `<svg viewBox='0 0 24 24' width='26' height='26'><path d='M4 3l15 7.5-6.2 1.6L10 18.5z' fill='#111' stroke='#fff' stroke-width='1.5' stroke-linejoin='round'/></svg>`;
  cursor.style.transform = `translate(${innerWidth * 0.62}px, ${innerHeight * 0.7}px)`;
  document.body.append(cursor);
  // Repaints a few times a second, so gaps between frames are only ever a busy page.
  const heartbeat = document.createElement('div');
  heartbeat.id = 'demo-heartbeat';
  document.body.append(heartbeat);
  const caption = document.createElement('div');
  caption.id = 'demo-caption';
  // Captions sit over the artifact workspace when there is one.
  if (document.querySelector('.layout')) caption.style.left = `calc(30rem + (100vw - 30rem) / 2)`;
  document.body.append(caption);
};

// Each caption stays up long enough to read, even when the agent is quicker.
let captioned = 0;
async function caption(page, html) {
  const wait = captioned + 2800 - Date.now();
  if (wait > 0) await pause(wait);
  captioned = Date.now();
  await page.evaluate(html => {
    const caption = document.getElementById('demo-caption');
    caption.classList.remove('show');
    setTimeout(() => {
      caption.innerHTML = html;
      if (html) caption.classList.add('show');
    }, html && caption.innerHTML ? 450 : 0);
  }, html);
}

// Points at the part of an element inside `within`, a scrolling container can hide the rest.
async function point(page, locator, within) {
  const box = await locator.boundingBox();
  const area = within ? await within.boundingBox() : box;
  const top = Math.max(box.y, area.y);
  const bottom = Math.min(box.y + box.height, area.y + area.height);
  const x = box.x + Math.min(box.width / 2, 40);
  const y = top < bottom ? (top + bottom) / 2 : box.y + box.height / 2;
  await page.evaluate(([x, y]) => { document.getElementById('demo-cursor').style.transform = `translate(${x}px, ${y}px)`; }, [x, y]);
  await page.mouse.move(x, y, { steps: 12 });
  await pause(750);
}

async function click(page, locator) {
  await point(page, locator);
  await page.evaluate(() => document.getElementById('demo-cursor').classList.add('press'));
  await pause(120);
  await locator.click();
  await page.evaluate(() => document.getElementById('demo-cursor').classList.remove('press'));
}

// Clicks an element in the chat while it scrolls, `click` would wait for it to settle.
async function tap(page, locator) {
  await point(page, locator, page.locator('.messages'));
  await page.evaluate(() => document.getElementById('demo-cursor').classList.add('press'));
  await pause(120);
  await locator.dispatchEvent('click');
  await page.evaluate(() => document.getElementById('demo-cursor').classList.remove('press'));
}

// Send a prompt and wait for the agent's turn to end.
// `during` directs the scene while the agent works, it can wait for tool results.
async function ask(page, prompt, { expected = [], during = async () => {} } = {}) {
  const input = page.locator('textarea');
  await click(page, input);
  await input.pressSequentially(prompt, { delay: 32 });
  await pause(500);
  const count = results.length;
  await input.press('Enter');
  await page.waitForFunction(() => document.querySelector('.layout')?.dataset.agentStatus !== 'waiting');
  const replied = async n => { while (results.length - count < n) await pause(100); };
  await Promise.all([
    during({ replied }),
    page.waitForFunction(() => document.querySelector('.layout')?.dataset.agentStatus === 'waiting', null, { timeout: 240_000 }),
  ]);
  const replies = results.slice(count);
  console.log('turn', JSON.stringify(prompt), replies.map(reply => reply.slice(0, 160)));
  expected.forEach((text, index) => {
    if (!replies[index]?.includes(text)) throw new Error(`Unexpected tool result for ${prompt}: ${replies[index]}`);
  });
  const failure = await page.locator('.failure-message').allTextContents();
  if (failure.some(text => text.trim())) throw new Error(failure.join('\n'));
}

// A still of the page without the pointer and caption.
async function still(page, file) {
  await page.evaluate(() => { for (const id of ['demo-cursor', 'demo-caption']) document.getElementById(id).style.visibility = 'hidden'; });
  await page.screenshot({ path: resolve(work, file) });
  await page.evaluate(() => { for (const id of ['demo-cursor', 'demo-caption']) document.getElementById(id).style.visibility = ''; });
}

// Title and end cards, a framed still from the session beside the text.
async function card(file, { title, subtitle, still }) {
  const page = await context.newPage();
  const inter = readFileSync(resolve(root, 'node_modules/.cache/demo-inter.woff2')).toString('base64');
  const image = readFileSync(resolve(work, still)).toString('base64');
  await page.setContent(`<html><head><style>
    @font-face { font-family: Inter; src: url(data:font/woff2;base64,${inter}); font-weight: 100 900; }
    html, body { margin: 0; height: 100%; overflow: hidden; }
    body { position: relative; display: flex; align-items: center; background: radial-gradient(900px 480px at 15% 0%, rgba(122,104,255,.22), transparent 65%), radial-gradient(700px 420px at 100% 100%, rgba(40,200,230,.12), transparent 60%), #08090c; color: #f3f4f7; font-family: Inter, sans-serif; }
    img { position: absolute; left: 790px; top: 50%; width: 1060px; border-radius: 16px; transform: translateY(-50%) perspective(2200px) rotateY(-18deg) rotateX(4deg); box-shadow: 0 60px 120px -40px rgba(0,0,0,.9), 0 0 0 1px rgba(255,255,255,.1); }
    main { position: relative; z-index: 1; margin-left: 110px; width: 600px; }
    p { margin: 0 0 20px; color: #9aa0ad; font-size: 15px; font-weight: 600; letter-spacing: .14em; text-transform: uppercase; }
    h1 { margin: 0; font-size: 64px; line-height: 1.02; font-weight: 700; letter-spacing: -0.045em; }
    h2 { margin: 26px 0 0; color: #b9bdc8; font-size: 21px; line-height: 1.45; font-weight: 450; letter-spacing: -0.01em; }
  </style></head><body><img src='data:image/png;base64,${image}'><main><p>EYG · Overlay</p><h1>${title}</h1><h2>${subtitle}</h2></main></body></html>`);
  await page.waitForTimeout(400);
  await page.screenshot({ path: resolve(work, file) });
  await page.close();
}

let failed = false;
try {
  const font = spawnSync('curl', ['-sfL', '-o', resolve(root, 'node_modules/.cache/demo-inter.woff2'), '--create-dirs', 'https://cdn.jsdelivr.net/npm/@fontsource-variable/inter@5/files/inter-latin-wght-normal.woff2']);
  if (font.status !== 0) throw new Error('Unable to download Inter for the captions and cards');
  const inter = readFileSync(resolve(root, 'node_modules/.cache/demo-inter.woff2')).toString('base64');

  const page = await context.newPage();
  page.on('pageerror', error => console.log('page error', error.message));
  await page.goto(`http://127.0.0.1:${port}/overlay/?reference=${reference}`);
  await page.locator('.context.ready').waitFor({ timeout: 60_000 });
  await page.evaluate(stage, inter);
  const stop = await capture(page);
  await pause(1000);

  await caption(page, 'An agent writes <b>EYG programs</b> to fetch live data');
  await ask(page, prompts[0], {
    expected: ['version:', 'departures:'],
    during: async ({ replied }) => {
      const code = page.locator('.message.code', { hasText: 'Live departures for the four bus stops' });
      await code.waitFor();
      await caption(page, 'Every program is <b>type checked</b>, effects included, before it runs');
      await tap(page, code);
      await pause(3400);
      await tap(page, code);
      await replied(1);
      await caption(page, 'Artifacts run <b>sandboxed</b>: no network, storage or access to Overlay');
      await page.waitForFunction(() => document.querySelectorAll('.message.code').length === 2);
      await caption(page, 'It checks its own work with a <b>Playwright</b> style EYG library');
    },
  });
  await point(page, page.locator('.tool-images img').first());
  await pause(2400);
  if (!video) await page.screenshot({ path: resolve(work, 'rehearsal-1.png') });

  await caption(page, 'A context module gives the agent a <b>design system</b>');
  await ask(page, prompts[1], {
    expected: ['weather:'],
    during: async ({ replied }) => {
      await replied(1);
      await caption(page, 'Layouts are <b>pure EYG functions</b> over a shared canvas');
    },
  });
  await pause(3000);
  await still(page, 'still-workspace.png');
  if (!video) await page.screenshot({ path: resolve(work, 'rehearsal-2.png') });

  await caption(page, 'Agents can <b>drive a running artifact</b>, every action is shown');
  await ask(page, prompts[2], { expected: ['routes:'] });
  await pause(2600);
  await still(page, 'still-light.png');
  if (!video) await page.screenshot({ path: resolve(work, 'rehearsal-3.png') });

  await caption(page, 'Sharing is <b>a person’s choice</b>: one click, one public link');
  const panel = page.locator('.artifact-panel').filter({ has: page.locator('.artifact-heading span', { hasText: /^departures$/ }) });
  await click(page, panel.getByRole('button', { name: 'share' }));
  const link = panel.getByRole('link', { name: 'shared ↗' });
  await link.waitFor();
  await pause(1100);
  const opened = context.waitForEvent('page');
  await click(page, link);
  const sharedPage = await opened;
  await sharedPage.waitForLoadState('domcontentloaded');
  await sharedPage.frameLocator('iframe').locator('[data-arrival]').first().waitFor();
  await sharedPage.evaluate(stage, inter);
  await stop();
  const stopShared = await capture(sharedPage);
  await pause(400);
  await caption(sharedPage, 'Shared artifacts are served <b>sandboxed</b> from the hub');
  await pause(4600);
  if (!video) await sharedPage.screenshot({ path: resolve(work, 'rehearsal-4.png') });
  await stopShared();

  await card('title.png', {
    still: 'still-workspace.png',
    title: 'Agents that build, check and share artifacts',
    subtitle: 'Scripted model replies. Real EYG programs, live TfL and Open-Meteo data, sandboxed previews and a hub to share them.',
  });
  await card('end.png', {
    still: 'still-light.png',
    title: 'Safe scripting for agents',
    subtitle: 'Every effect is explicit. Artifacts run sandboxed. Sharing is always a person’s choice.<br><br>eyg.run',
  });
} catch (error) {
  failed = true;
  console.error(error);
} finally {
  await browser.close();
  vite.kill();
  mock.stop(true);
}

if (video && !failed) {
  // Screencast frames arrive when the page changes, hold each until the next.
  // The page repaints several times a second, so a longer gap is the page busy
  // preparing artifacts rather than a pause in the demo, those gaps are shortened.
  const durations = timeline.map((frame, index) => {
    const next = timeline[index + 1]?.time ?? frame.time + 1;
    return Math.min(Math.max(0.001, next - frame.time), 0.35);
  });
  const list = timeline.map((frame, index) => `file '${frame.file}'\nduration ${durations[index].toFixed(4)}`);
  list.push(`file '${timeline[timeline.length - 1].file}'`);
  writeFileSync(resolve(frames, 'frames.txt'), list.join('\n'));
  const duration = durations.reduce((total, seconds) => total + seconds, 0);
  const ffmpeg = args => {
    const run = spawnSync(process.env.FFMPEG ?? 'ffmpeg', ['-y', '-loglevel', 'error', ...args], { cwd: work, stdio: 'inherit' });
    if (run.status !== 0) throw new Error(`ffmpeg failed: ${args.join(' ')}`);
  };
  const encode = ['-c:v', 'libx264', '-preset', 'slow', '-crf', '16', '-pix_fmt', 'yuv420p', '-r', '30'];
  ffmpeg(['-f', 'concat', '-safe', '0', '-i', 'frames/frames.txt', '-vf', 'scale=1920:1080:flags=lanczos', ...encode, 'main.mp4']);
  ffmpeg(['-loop', '1', '-t', '4', '-i', 'title.png', '-vf', 'scale=1920:1080', ...encode, 'title.mp4']);
  ffmpeg(['-loop', '1', '-t', '4.5', '-i', 'end.png', '-vf', 'scale=1920:1080', ...encode, 'end.mp4']);
  const fade = 0.7;
  ffmpeg([
    '-i', 'title.mp4', '-i', 'main.mp4', '-i', 'end.mp4',
    '-filter_complex', `[0][1]xfade=transition=fade:duration=${fade}:offset=${4 - fade}[a];[a][2]xfade=transition=fade:duration=${fade}:offset=${(4 - fade + duration - fade).toFixed(3)},format=yuv420p[v]`,
    '-map', '[v]', ...encode, '-movflags', '+faststart', resolve(out, 'overlay-artifacts.mp4'),
  ]);
  console.log('video', resolve(out, 'overlay-artifacts.mp4'), `${(4 + duration + 4.5 - 2 * fade).toFixed(1)}s`);
}
process.exit(failed ? 1 : 0);
