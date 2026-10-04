import { fileURLToPath } from "node:url";
import type { RuntimeEvent, RuntimeRequest } from "./protocol";

/** Keep evaluation outside the renderer, including native runtime failures.
 * Bun 1.3.14 can segfault when terminating a Worker with in-flight fetches:
 * https://github.com/oven-sh/bun/issues/38519
 * A subprocess can also be stopped immediately during infinite EYG evaluation.
 */
export class RuntimeProcess extends EventTarget {
  onmessage: ((event: MessageEvent<RuntimeEvent>) => void) | null = null;
  onerror: ((event: ErrorEvent) => void) | null = null;
  private stopped = false;
  private child: Bun.Subprocess<"ignore", "ignore", "pipe">;
  private stopOnExit = () => { void this.terminate(); };

  constructor(env: Record<string, string | undefined> = {}) {
    super();
    this.child = Bun.spawn([process.execPath, fileURLToPath(new URL("./worker.ts", import.meta.url))], {
      cwd: process.cwd(), env: { ...process.env, ...env },
      stdin: "ignore", stdout: "ignore", stderr: "pipe", serialization: "json",
      ipc: message => {
        if (this.stopped) return;
        const event = new MessageEvent<RuntimeEvent>("message", { data: message });
        this.onmessage?.(event); this.dispatchEvent(event);
      },
    });
    process.once("exit", this.stopOnExit);
    void Promise.all([this.child.exited, new Response(this.child.stderr).text()]).then(([code, stderr]) => {
      process.removeListener("exit", this.stopOnExit);
      if (this.stopped) return;
      const event = new ErrorEvent("error", { message: stderr.trim() || `EYG runtime exited (${code})` });
      this.onerror?.(event); this.dispatchEvent(event);
    });
  }
  postMessage(request: RuntimeRequest) {
    if (!this.stopped) this.child.send(request);
  }
  terminate() {
    if (!this.stopped) { this.stopped = true; this.child.kill(); }
    return this.child.exited;
  }
}
