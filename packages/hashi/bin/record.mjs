// The two recordings: a whole game played through the shell, and a whole game
// played by an agent.
//
// See `.agents/skills/browser/SKILL.md` for why this is JavaScript when
// everything else here is EYG.
//
//     bun run bin/record.mjs [outdir]
//
// The shell recording needs the dev server up: `bun run dev`.
// The agent recording needs it started against the model in this file:
//
//     HASHI_LLM=http://localhost:8787 bun run dev
//
// `bin/record.mjs` starts that model itself, on 8787.

import { mkdir, rename, rm } from "node:fs/promises";
import { chromium } from "playwright";

const outdir = process.argv[2] ?? "tmp/videos";
const url = process.env.HASHI_URL ?? "http://localhost:5174/";
const viewport = { width: 1440, height: 900 };

// The board these recordings are of. Naming it means the videos are the same
// every time; the numbers below are its answer.
const day = 19950;
const moves = [
  [[0, 5], [3, 5]],
  [[0, 5], [3, 5]],
  [[0, 5], [0, 0]],
  [[0, 5], [0, 7]],
  [[3, 5], [3, 0]],
  [[3, 5], [5, 5]],
  [[0, 7], [2, 7]],
  [[2, 7], [7, 7]],
  [[2, 7], [7, 7]],
  [[7, 7], [7, 4]],
];

await mkdir(outdir, { recursive: true });

// THE SHELL -------------------------------------------------------------------

async function recordShell(browser) {
  const dir = `${outdir}/.shell`;
  const context = await browser.newContext({
    viewport,
    recordVideo: { dir, size: viewport },
  });
  const page = await context.newPage();
  await page.goto(`${url}?day=${day}`);
  await page.waitForSelector(".shell-editor");
  await page.waitForTimeout(1200);

  const key = async (k, wait = 130) => {
    await page.keyboard.press(k);
    await page.waitForTimeout(wait);
  };
  // The picker decides with the value it was last rendered with, so a name and
  // the enter that finishes it cannot arrive in the same frame.
  const name = async (text) => {
    await page.keyboard.type(text, { delay: 55 });
    await page.waitForTimeout(220);
    await key("Enter");
  };
  const run = async () => {
    await page.waitForTimeout(400);
    await key("Control+Enter", 900);
  };

  const call = async (fn) => {
    await key("v");
    await name(fn);
  };
  const point = async ([x, y]) => {
    await key("Space");
    await key("r");
    await name("x, y");
    await key("n");
    await name(String(x));
    await key("Space");
    await key("n");
    await name(String(y));
  };

  // Look at the board first. A picture of it reads better than two lists.
  await call("picture");
  await key("c");
  await key("R");
  await run();
  await page.waitForTimeout(1400);

  // Which islands are worth starting from.
  await call("twos");
  await key("c");
  await key("R");
  await run();
  await page.waitForTimeout(900);

  for (const [from, to] of moves) {
    await call("connect");
    await key("c");
    await key("a");
    await key("c");
    await point(from);
    await point(to);
    await run();
  }

  // And the board again, finished.
  await page.waitForTimeout(800);
  await call("picture");
  await key("c");
  await key("R");
  await run();
  await page.waitForTimeout(2500);

  const solved = await page.locator(".board-status.solved").count();
  console.log(solved ? "shell: solved" : "shell: NOT SOLVED");

  const video = page.video();
  await context.close();
  const from = await video.path();
  await rename(from, `${outdir}/shell.webm`);
  await rm(dir, { recursive: true, force: true });
  console.log(`${outdir}/shell.webm`);
}

// THE AGENT -------------------------------------------------------------------

/// What the model says, in order. Each turn is some words and the programs it
/// wants run. Nothing downstream of this is a fake: the programs are parsed,
/// type checked and run against the real board.
const turns = [
  {
    text: "Let me look at the board first.",
    programs: ["picture({})"],
  },
  {
    text:
      "Two islands want four bridges each and they are in line, so that pair " +
      "takes a double. I will build outwards from them.",
    programs: [
      "connect({x: 0, y: 5}, {x: 3, y: 5})",
      "connect({x: 0, y: 5}, {x: 3, y: 5})",
      "connect({x: 0, y: 5}, {x: 0, y: 0})",
      "connect({x: 0, y: 5}, {x: 0, y: 7})",
    ],
  },
  {
    text: "Now the other four, and the bottom row.",
    programs: [
      "connect({x: 3, y: 5}, {x: 3, y: 0})",
      "connect({x: 3, y: 5}, {x: 5, y: 5})",
      "connect({x: 0, y: 7}, {x: 2, y: 7})",
      "connect({x: 2, y: 7}, {x: 7, y: 7})",
      "connect({x: 2, y: 7}, {x: 7, y: 7})",
      "connect({x: 7, y: 7}, {x: 7, y: 4})",
    ],
  },
  {
    text: "Every island has what it asked for.",
    programs: ["is_empty(unfinished({}))", "picture({})"],
  },
  { text: "That is the board solved.", programs: [] },
];

function line(content, tool_calls = []) {
  return JSON.stringify({ message: { content, tool_calls } }) + "\n";
}

/// An Ollama that always says the same thing. It answers in the streaming
/// shape the real one does — newline separated JSON, content in pieces — so
/// the page has no idea it is not talking to a model.
function fakeModel(port) {
  let turn = 0;
  return Bun.serve({
    port,
    async fetch(request) {
      if (!new URL(request.url).pathname.endsWith("/api/chat")) {
        return new Response("not found", { status: 404 });
      }
      const said = turns[Math.min(turn, turns.length - 1)];
      turn += 1;

      const stream = new ReadableStream({
        async start(controller) {
          const encoder = new TextEncoder();
          // Slowly enough to read. Playwright acts faster than anyone can
          // follow and a recording nobody can follow is no use.
          for (const word of said.text.split(" ")) {
            controller.enqueue(encoder.encode(line(word + " ")));
            await Bun.sleep(90);
          }
          await Bun.sleep(500);
          for (const code of said.programs) {
            controller.enqueue(
              encoder.encode(
                line("", [{ function: { name: "run", arguments: { code } } }]),
              ),
            );
            await Bun.sleep(400);
          }
          controller.close();
        },
      });
      return new Response(stream, {
        headers: { "content-type": "application/x-ndjson" },
      });
    },
  });
}

async function recordAgent(browser) {
  const dir = `${outdir}/.agent`;
  const context = await browser.newContext({
    viewport,
    recordVideo: { dir, size: viewport },
  });
  const page = await context.newPage();
  await page.goto(`${url}?day=${day}`);
  await page.waitForSelector(".shell-editor");
  await page.waitForTimeout(1000);

  await page.getByRole("button", { name: "Agent" }).click();
  await page.waitForTimeout(700);

  // Choose a model. The token is not looked at by the one answering here.
  // The panel opens itself when nothing is set up yet.
  if (!(await page.locator('select[name="provider"]').count())) {
    await page.locator(".provider-trigger").click();
    await page.waitForTimeout(400);
  }
  await page.selectOption('select[name="provider"]', "ollama");
  await page.waitForTimeout(400);
  await page.locator('input[name="api-token"]').fill("recording");
  await page.waitForTimeout(300);
  await page.getByRole("button", { name: "Use provider" }).click();
  await page.waitForTimeout(700);

  await page.locator("textarea").click();
  await page.keyboard.type("Solve this board.", { delay: 55 });
  await page.waitForTimeout(400);
  await page.getByRole("button", { name: "send" }).click();

  await page
    .locator(".board-status.solved")
    .waitFor({ timeout: 60_000 })
    .catch(() => {});
  await page.waitForTimeout(3000);

  const solved = await page.locator(".board-status.solved").count();
  console.log(solved ? "agent: solved" : "agent: NOT SOLVED");

  const video = page.video();
  await context.close();
  const from = await video.path();
  await rename(from, `${outdir}/agent.webm`);
  await rm(dir, { recursive: true, force: true });
  console.log(`${outdir}/agent.webm`);
}

// `bun run bin/record.mjs tmp/videos shell` records only one of them.
const only = process.argv[3];
const model = fakeModel(8787);
const browser = await chromium.launch();
try {
  if (only !== "agent") await recordShell(browser);
  if (only !== "shell") await recordAgent(browser);
} finally {
  await browser.close();
  model.stop();
}
