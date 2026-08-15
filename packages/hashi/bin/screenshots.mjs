// Screenshots of the page, one per thing worth looking at.
//
// See `.agents/skills/browser/SKILL.md` for why this is JavaScript when
// everything else here is EYG.
//
//     bun run bin/screenshots.mjs [outdir]
//
// The dev server has to be up: `bun run dev`.

import { mkdir } from "node:fs/promises";
import { chromium } from "playwright";

const url = process.env.HASHI_URL ?? "http://localhost:5174/";
const outdir = process.argv[2] ?? "tmp/screenshots";
const viewport = { width: 1440, height: 900 };

await mkdir(outdir, { recursive: true });

const browser = await chromium.launch();
const page = await browser.newPage({ viewport });

async function shot(name) {
  await page.screenshot({ path: `${outdir}/${name}.png` });
  console.log(`${outdir}/${name}.png`);
}

await page.goto(url);
await page.waitForSelector(".hashi-grid");
await page.waitForTimeout(500);
await shot("01-shell");

// The keys the shell is driven by.
await page.getByRole("button", { name: "keys" }).click();
await page.waitForTimeout(200);
await shot("02-keys");
await page.getByRole("button", { name: "keys" }).click();

// Write `picture({})` and run it: `v` for a variable, then call it with `{}`.
const editor = page.locator(".shell-editor");
await editor.click();
await page.keyboard.press("v");
await page.waitForTimeout(200);
await shot("03-choosing-a-variable");

// Typed with a delay on purpose: the picker decides with the value it was
// last rendered with, so a keystroke and Enter in the same frame loses the
// last character.
await page.keyboard.type("picture", { delay: 60 });
await page.waitForTimeout(200);
await page.keyboard.press("Enter");
await page.waitForTimeout(200);
await editor.click();
await page.keyboard.press("c");
await page.waitForTimeout(200);
await page.keyboard.press("R");
await page.waitForTimeout(200);
await shot("04-a-program");

await page.getByRole("button", { name: "run" }).click();
await page.waitForTimeout(500);
await shot("05-the-board-as-text");

// The agent side.
await page.getByRole("button", { name: "Agent" }).click();
await page.waitForTimeout(300);
await shot("06-agent");

await page.getByRole("button", { name: /provider|choose/i }).first().click();
await page.waitForTimeout(300);
await shot("07-agent-provider");

await browser.close();
