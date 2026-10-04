import { expect, test } from "bun:test";
import { RuntimeProcess } from "../src/runtime-process";

test("repeated shutdown during pending hub discovery exits cleanly", async () => {
  let requests = 0;
  const server = Bun.serve({ port: 0, fetch() { requests++; return new Promise<Response>(() => {}); } });
  try {
    for (let index = 0; index < 8; index++) {
      const runtime = new RuntimeProcess({ EYG_ORIGIN: server.url.origin });
      try {
        const ready = new Promise<void>((resolve, reject) => {
          runtime.onmessage = event => { if (event.data.type === "ready") resolve(); };
          runtime.onerror = event => reject(new Error(event.message));
        });
        runtime.postMessage({ type: "initialize", args: [] });
        await ready;
        // Wait for the server to observe the request, keeping it unresolved.
        for (let spin = 0; requests <= index && spin < 100; spin++) await Bun.sleep(5);
        expect(requests).toBeGreaterThan(index);
        const started = performance.now();
        await runtime.terminate();
        expect(performance.now() - started).toBeLessThan(1000);
      } finally { await runtime.terminate(); }
    }
  } finally { server.stop(true); }
}, 15000);
