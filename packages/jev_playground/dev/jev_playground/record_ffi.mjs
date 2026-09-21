import { chromium } from "playwright";
import { execFileSync } from "node:child_process";
import { mkdirSync, renameSync, rmSync } from "node:fs";

const size = { width: 1280, height: 720 };

export async function screenshot(url, path, wait) {
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: size });
  page.on("console", (message) => console.error("console", message.type(), message.text().slice(0, 500)));
  page.on("pageerror", (error) => console.error("pageerror", error.message.slice(0, 500), (error.stack || "").slice(0, 3000)));
  await page.goto(url);
  await page.waitForTimeout(wait);
  await page.screenshot({ path });
  const text = await page.innerText("body");
  await browser.close();
  return text;
}

// The host is short of memory and the renderer is sometimes killed, so retry.
export async function record(url, output, timeout) {
  for (let attempt = 1; ; attempt++) {
    try {
      return await record_once(url, output, timeout);
    } catch (error) {
      console.error("recording attempt", attempt, "failed:", error.message);
      if (attempt >= 3) return "failed: " + error.message;
    }
  }
}

// Record the page until the status shows finished or failed, then encode an mp4.
async function record_once(url, output, timeout) {
  const directory = output + ".frames";
  rmSync(directory, { recursive: true, force: true });
  mkdirSync(directory, { recursive: true });
  const browser = await chromium.launch();
  const context = await browser.newContext({
    viewport: size,
    recordVideo: { dir: directory, size },
  });
  const page = await context.newPage();
  await page.goto(url);
  let status = "timeout";
  try {
    await page.waitForSelector(".status.finished, .status.failed", { timeout });
    status = (await page.innerText(".status")).trim();
  } catch (error) {
    await browser.close();
    throw error;
  }
  await page.waitForTimeout(2500);
  const video = page.video();
  await context.close();
  await browser.close();
  const webm = await video.path();
  execFileSync("ffmpeg", ["-y", "-loglevel", "error", "-i", webm, "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "23", "-movflags", "+faststart", output]);
  rmSync(directory, { recursive: true, force: true });
  return status;
}

// Run the page until finished then evaluate an expression, useful when debugging the view.
export async function inspect(url, expression, timeout) {
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: size });
  page.on("console", (message) => console.error("console", message.type(), message.text().slice(0, 300)));
  page.on("pageerror", (error) => console.error("pageerror", error.message.slice(0, 300)));
  page.on("crash", () => console.error("crash event"));
  await page.goto(url);
  await page.waitForSelector(".status.finished, .status.failed", { timeout });
  await page.waitForTimeout(3000);
  const result = await page.evaluate(expression);
  await browser.close();
  return JSON.stringify(result, null, 1);
}

// Print the step and status every two seconds, to see where time goes.
export async function sample(url, seconds) {
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: size });
  page.on("pageerror", (error) => console.error("pageerror", error.message));
  page.on("console", (message) => console.error("console", message.text()));
  const start = Date.now();
  await page.goto(url);
  await page.evaluate(() => {
    new PerformanceObserver((list) => {
      for (const entry of list.getEntries()) console.log("longtask " + Math.round(entry.duration));
    }).observe({ type: "longtask", buffered: true });
  });
  const lines = [];
  while (Date.now() - start < seconds * 1000) {
    const state = await page.evaluate(() => {
      const chips = [...document.querySelectorAll(".chip")].map((c) => c.innerText.replace("\n", " "));
      const status = document.querySelector(".status");
      return chips.join(" | ") + " | " + (status ? status.innerText : "");
    });
    lines.push(Math.round((Date.now() - start) / 1000) + "s " + state);
    await page.waitForTimeout(2000);
  }
  await browser.close();
  return lines.join("\n");
}
