import { ReplRuntime } from "./runtime";
import { OverlayRuntime } from "./overlay-runtime";
import type { RuntimeEvent, RuntimeRequest } from "./protocol";

const emit = (event: RuntimeEvent) => { process.send?.(event); };
let answer: ((text: string) => void) | undefined;
let activeId = 0;
const prompt = (text: string): Promise<string> => new Promise(resolve => {
  answer = resolve;
  emit({ type: "prompt", id: activeId, text });
});
let runtime: ReplRuntime | OverlayRuntime;
let queue = Promise.resolve();
process.on("disconnect", () => process.exit(0));
process.on("message", (request: RuntimeRequest) => {
  if (request.type === "answer") {
    answer?.(request.text);
    answer = undefined;
    return;
  }
  queue = queue.then(async () => {
    if (request.type === "initialize") {
      runtime = request.args[0] === "overlay" ? new OverlayRuntime(emit, prompt) : new ReplRuntime(emit, prompt);
      await runtime.initialize(request.args);
      // Package suggestions load independently; a slow hub must not hold up
      // local expressions that are ready to run.
      if (runtime instanceof ReplRuntime) void runtime.packages().catch(error => emit({ type: "error", id: 0, message: `Package discovery: ${error.message}` }));
    } else if (request.type === "structure") {
      activeId = 0;
      if (runtime instanceof ReplRuntime) runtime.structure(request);
    } else {
      activeId = request.id;
      if (runtime instanceof ReplRuntime) await runtime.evaluate(request.id, request.source, request.structural);
      else await runtime.evaluate(request.id, request.source);
    }
  }).catch(error => emit({ type: "error", id: activeId, message: String(error?.message ?? error) }));
});
