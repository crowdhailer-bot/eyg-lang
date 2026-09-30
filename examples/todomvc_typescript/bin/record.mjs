// Record the TypeScript list being changed from the shell, and by the agent.
// The agent's model is replaced by a fixed script served in place of Ollama's
// /api/chat, so the recording is repeatable and needs no model running.
//
//   bun run dev   # in another terminal
//   bun run bin/record.mjs
import { chromium } from "playwright";
import { renameSync, mkdirSync } from "node:fs";

const base = "http://127.0.0.1:5193/";
const size = { width: 1440, height: 900 };
mkdirSync("media", { recursive: true });

async function session(name, act) {
  const browser = await chromium.launch();
  const context = await browser.newContext({ viewport: size, recordVideo: { dir: "media/raw", size } });
  const page = await context.newPage();
  await page.goto(base);
  // The shell starts once @standard has been loaded from the hub.
  await page.waitForFunction(() => document.querySelector(".console button[type=submit]")?.disabled === false);
  await page.waitForTimeout(1000);
  await act(page);
  await page.screenshot({ path: `media/${name}.png` });
  const video = page.video();
  await context.close();
  renameSync(await video.path(), `media/${name}.webm`);
  await browser.close();
}

async function run(page, code) {
  const input = page.getByLabel("EYG code");
  await input.fill("");
  await input.pressSequentially(code, { delay: 25 });
  await page.waitForTimeout(500);
  await page.getByRole("button", { name: "Run" }).click();
  await page.waitForTimeout(1800);
}

export const queries = [
  `let {list} = @standard
list.map(todos.tagged("#shopping"), (task) -> { task.title })`,
  `let {list} = @standard
let tags = list.fold(list.flat_map(todos.all({}), todos.tags), [], (tag, seen) -> {
  match list.contains(seen, tag) {
    True(_) -> { seen }
    False(_) -> { [tag, ..seen] }
  }
})
list.map(tags, (tag) -> { {tag, count: list.length(todos.tagged(tag))} })`,
  `let {list, string} = @standard
list.map(todos.matching("plumber"), (task) -> { todos.rename(task, string.append("Urgent: ", task.title)) })`,
  `@standard.list.map(todos.tagged("#shopping"), todos.complete)`,
];

if (!process.env.ONLY_AGENT)
  await session("shell", async (page) => {
    for (const query of queries) await run(page, query);
    await page.waitForTimeout(2000);
  });

const call = (code) => ({ message: { role: "assistant", content: "", tool_calls: [{ function: { name: "run", arguments: { code } } }] } });
const say = (content) => ({ message: { role: "assistant", content } });
const script = [
  call(`let {list} = @standard
list.map(todos.all({}), (task) -> { {id: task.id, title: task.title, completed: task.completed} })`),
  call(`let {list} = @standard
let _ = list.map(todos.tagged("#shopping"), todos.complete)
list.map(["Pack passport #travel", "Book a taxi to the airport #travel", "Check in online #travel"], todos.add)`),
  say("I've ticked off milk and bread, and added three #travel tasks for Friday: packing your passport, booking a taxi and checking in."),
];

await session("agent", async (page) => {
  let turn = 0;
  await page.route("**/api/chat", async (route) => {
    const reply = script[Math.min(turn++, script.length - 1)];
    await new Promise((resolve) => setTimeout(resolve, 1200));
    await route.fulfill({ status: 200, contentType: "application/x-ndjson", body: JSON.stringify(reply) + "\n" });
  });
  await page.getByRole("button", { name: "Agent" }).click();
  await page.waitForTimeout(800);
  await page.getByLabel("Message").pressSequentially("I've bought everything on the shopping list. Add what I need to do for my flight on Friday.", { delay: 30 });
  await page.getByRole("button", { name: "Send" }).click();
  await page.getByText("ticked off milk and bread").waitFor({ timeout: 60000 }).catch(async (error) => {
    await page.screenshot({ path: "media/raw/failed.png" });
    throw error;
  });
  await page.waitForTimeout(3000);
});
