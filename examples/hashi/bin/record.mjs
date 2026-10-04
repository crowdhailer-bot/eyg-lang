// Record the page being played, once from the shell and once by the agent.
// The agent's model is replaced by a fixed script served in place of Ollama's
// /api/chat, so the recording is repeatable and needs no model running.
//
//   bun run dev   # in another terminal
//   bun run bin/record.mjs
import { chromium } from "playwright";
import { readFileSync, renameSync, mkdirSync } from "node:fs";

const base = "http://127.0.0.1:5191/";
const size = { width: 1440, height: 900 };
const solver = readFileSync(new URL("../solver.eyg", import.meta.url), "utf8");
mkdirSync("media", { recursive: true });

async function session(name, seed, act) {
  const browser = await chromium.launch();
  const context = await browser.newContext({
    viewport: size,
    recordVideo: { dir: "media/raw", size },
  });
  const page = await context.newPage();
  await act(page, `${base}?seed=${seed}`);
  await page.screenshot({ path: `media/${name}.png` });
  const video = page.video();
  await context.close();
  renameSync(await video.path(), `media/${name}.webm`);
  await browser.close();
}

async function run(page, code, { typed = true } = {}) {
  const input = page.getByLabel("EYG code");
  await input.fill("");
  if (typed) await input.pressSequentially(code, { delay: 35 });
  else await input.fill(code);
  await page.waitForTimeout(600);
  await page.getByRole("button", { name: "Run" }).click();
  await page.waitForTimeout(1800);
}

if (!process.env.ONLY_AGENT) await session("shell", 1, async (page, url) => {
  await page.goto(url);
  await page.waitForTimeout(1500);
  await run(page, "hashi.with_target(6)");
  await run(
    page,
    `let big = hashi.with_target(6)
hashi.each(big, (island) -> {
  hashi.each(hashi.neighbours(island), (other) -> {
    let _ = hashi.connect(island, other)
    hashi.connect(island, other)
  })
})`,
  );
  await run(page, solver, { typed: false });
  await run(page, "solve({})");
  await page.waitForTimeout(2500);
});

const call = (code) => ({ message: { role: "assistant", content: "", tool_calls: [{ function: { name: "run", arguments: { code } } }] } });
const say = (content) => ({ message: { role: "assistant", content } });
const script = [
  call("hashi.islands({})"),
  call(`let middle = {x: 3, y: 3}
perform AddBridge({form: middle, to: {x: 5, y: 3}})`),
  call(`let middle = {x: 3, y: 3}
let _ = hashi.connect(middle, {x: 5, y: 3})
let _ = hashi.connect(middle, {x: 5, y: 3})
let _ = hashi.connect(middle, {x: 3, y: 1})
hashi.connect(middle, {x: 3, y: 1})`),
  call(solver.replace(/^\/\/.*\n/gm, "") + "\nsolve({})"),
  say("The puzzle is solved. I placed the doubles the middle island forced, then played every remaining forced bridge."),
];

await session("agent", 3, async (page, url) => {
  let turn = 0;
  await page.route("**/api/chat", async (route) => {
    const reply = script[Math.min(turn++, script.length - 1)];
    await new Promise((resolve) => setTimeout(resolve, 1200));
    await route.fulfill({ status: 200, contentType: "application/x-ndjson", body: JSON.stringify(reply) + "\n" });
  });
  await page.goto(url);
  await page.waitForTimeout(1500);
  await page.getByRole("button", { name: "Agent" }).click();
  await page.waitForTimeout(800);
  await page.getByLabel("Message").pressSequentially("Please solve the puzzle.", { delay: 50 });
  await page.getByRole("button", { name: "Send" }).click();
  await page.getByText("The puzzle is solved.").waitFor({ timeout: 60000 }).catch(async (error) => {
    await page.screenshot({ path: "media/raw/failed.png" });
    throw error;
  });
  await page.waitForTimeout(3000);
});
