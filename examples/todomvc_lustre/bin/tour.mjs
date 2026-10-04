// A two minute tour of the console: type errors, a program with no library, a
// query with @standard, an effect the page does not offer, then the agent.
//
// The hub's answers are held back three seconds so the loading state can be
// seen, locally it takes about one. The agent's model is a fixed script served
// in place of Ollama's /api/chat.
//
//   bun run dev   # in another terminal
//   bun run bin/tour.mjs
import { chromium } from "playwright";
import { mkdirSync, renameSync } from "node:fs";

const size = { width: 1440, height: 900 };
mkdirSync("media/raw", { recursive: true });

const browser = await chromium.launch();
const context = await browser.newContext({ viewport: size, recordVideo: { dir: "media/raw", size } });
const page = await context.newPage();
const started = Date.now();
const pause = (ms) => page.waitForTimeout(ms);

async function run(code) {
  const input = page.getByLabel("EYG code");
  await input.fill("");
  await input.pressSequentially(code, { delay: 40 });
  await pause(900);
  await page.getByRole("button", { name: "Run" }).click();
}

// Loading, slowed down.
await page.route(/\/(packages|modules)\//, async (route) => {
  await new Promise((resolve) => setTimeout(resolve, 3000));
  await route.continue();
});
await page.goto("http://127.0.0.1:5192/");
await page.waitForFunction(() => document.querySelector(".console button[type=submit]")?.disabled === false, null, {
  timeout: 60000,
});
await pause(2500);

await pause(3000);
await run(`perform SetCompleted({id: "1", completed: True({})})`);
await pause(5000);

await pause(3000);
await run(`!list_fold(["Pack passport #travel", "Book a taxi #travel"], [], (title, ids) -> {
  [perform CreateTask(title), ..ids]
})`);
await pause(5000);

await pause(3000);
await run(`let {list} = @standard
let tags = list.fold(list.flat_map(todos.all({}), todos.tags), [], (tag, seen) -> {
  match list.contains(seen, tag) {
    True(_) -> { seen }
    False(_) -> { [tag, ..seen] }
  }
})
list.map(tags, (tag) -> { {tag, count: list.length(todos.tagged(tag))} })`);
await pause(5500);

await pause(2500);
await run(`let {list, string} = @standard
list.map(todos.tagged("#travel"), (task) -> {
  todos.rename(task, string.append("Urgent: ", task.title))
})`);
await pause(5000);

await pause(3000);
await run(`perform ReadFile({path: "/etc/passwd", offset: 0, limit: 1000})`);
await pause(5500);

// The agent.
const call = (code) => ({
  message: { role: "assistant", content: "", tool_calls: [{ function: { name: "run", arguments: { code } } }] },
});
const say = (content) => ({ message: { role: "assistant", content } });
const script = [
  call(`let {list} = @standard
list.map(todos.complete, todos.tagged("#shopping"))`),
  call(`let {list} = @standard
let _ = list.map(todos.tagged("#shopping"), todos.complete)
todos.add("Renew the car insurance #admin")`),
  say("Done: milk and bread are ticked off, and renewing the car insurance is on your #admin list."),
];
let turn = 0;
await page.route("**/api/chat", async (route) => {
  const reply = script[Math.min(turn++, script.length - 1)];
  await new Promise((resolve) => setTimeout(resolve, 2500));
  await route.fulfill({ status: 200, contentType: "application/x-ndjson", body: JSON.stringify(reply) + "\n" });
});

await page.getByRole("button", { name: "Agent" }).click();
await pause(3500);
await page
  .getByLabel("Message")
  .pressSequentially("I've done all the shopping. Add a task to renew the car insurance #admin.", { delay: 40 });
await pause(800);
await page.getByRole("button", { name: "Send" }).click();
await page.locator(".run.by-model.failed").waitFor({ timeout: 30000 });
await page.getByText("renewing the car insurance").waitFor({ timeout: 30000 });
await pause(4500);
await pause(6000);

await page.screenshot({ path: "media/tour.png" });
const video = page.video();
await context.close();
renameSync(await video.path(), "media/tour.webm");
await browser.close();
console.log(`recorded ${Math.round((Date.now() - started) / 1000)} seconds`);
