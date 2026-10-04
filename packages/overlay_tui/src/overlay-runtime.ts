import * as overlay from "../build/dev/javascript/eyg_cli/eyg/cli/overlay.mjs";
import * as config from "../build/dev/javascript/eyg_cli/eyg/cli/internal/config.mjs";
import { parse, Overlay } from "../build/dev/javascript/eyg_cli/eyg/cli/args.mjs";
import * as chat from "../build/dev/javascript/overlay_llm/overlay/llm/chat.mjs";
import { type Call$, Call$Call$function, FunctionCall$FunctionCall$arguments } from "../build/dev/javascript/overlay_llm/overlay/llm/tool.mjs";
import { cast_tool_call, Run } from "../build/dev/javascript/overlay/overlay/agent.mjs";
import { fields_to_json } from "../build/dev/javascript/oas_generator_utils/oas/generator/utils.mjs";
import { to_string } from "../build/dev/javascript/gleam_json/gleam/json.mjs";
import { toList, Ok, Error as GleamError, type List, type Result } from "../build/dev/javascript/loam/gleam.mjs";
import type { State$ } from "../build/dev/javascript/loam/loam/execute.mjs";
import { Done } from "../build/dev/javascript/loam/loam/system.mjs";
import type { RuntimeEvent } from "./protocol";
import { drive, type DriverIO } from "./driver";

function unwrap<T>(result: Result<T, unknown>): T {
  if (result instanceof Ok) return result[0];
  throw new Error(result instanceof GleamError ? String(result[0]) : "Invalid result");
}

export class OverlayRuntime {
  private session!: overlay.Session$;
  private runtime!: State$;
  private history: List<chat.Message$<Call$>> = toList([]);
  private activeId = 0;
  private sequence = 0;
  private io: DriverIO;
  constructor(private emit: (event: RuntimeEvent) => void, prompt: DriverIO["prompt"]) {
    this.io = {
      output: (text, error) => emit({ type: "output", id: this.activeId, text, error }),
      fetch: url => emit({ type: "fetch", id: this.activeId, url }),
      prompt,
    };
  }
  async initialize(args: string[]) {
    const command = parse(toList(args));
    if (!(command instanceof Overlay)) throw new Error("Expected an overlay config");
    const settings = unwrap(await drive(config.load(), this.io));
    [this.session, this.runtime] = unwrap(await drive(overlay.initialize(command.input, settings), this.io));
    this.emit({ type: "overlay-ready", model: this.session.llm.model });
  }
  async evaluate(id: number, source: string) {
    const started = performance.now();
    this.activeId = id;
    if (/^\/export(?:\s|$)/.test(source)) {
      await drive(overlay.export$(this.session, this.history, source.slice(7).trim()), this.io);
    } else {
      this.history = toList([new chat.UserMessage(source, toList([])), ...this.history]);
      while (true) {
        const assistantId = --this.sequence;
        this.activeId = assistantId;
        const completion = unwrap(await drive(overlay.completion(this.session, toList([...this.history].reverse()), text => {
          if (text) this.emit({ type: "assistant", id: assistantId, text });
          return new Done(undefined);
        }), this.io));
        this.history = toList([chat.from_completion(completion), ...this.history]);
        const calls = [...completion.tool_calls];
        if (!calls.length) break;
        for (const call of calls) {
          const toolId = --this.sequence;
          this.activeId = toolId;
          const start = performance.now();
          const func = Call$Call$function(call);
          const args = FunctionCall$FunctionCall$arguments(func);
          const decoded = cast_tool_call(func.name, args);
          const code = decoded instanceof Ok && decoded[0] instanceof Run ? decoded[0][0] : to_string(fields_to_json(args));
          this.emit({ type: "tool", id: toolId, name: func.name, code });
          const [result, runtime] = await drive(overlay.call_observed(this.session, func, this.runtime, (label, input, decision, output) => {
            this.emit({ type: "effect", id: toolId, effect: { label, input, decision, output } });
            return undefined;
          }), this.io);
          this.runtime = runtime;
          this.history = toList([overlay.result_to_message(call.id, result), ...this.history]);
          const text = result instanceof Ok ? result[0].text : result instanceof GleamError ? result[0] : "Invalid tool result";
          this.emit({ type: "tool-result", id: toolId, text, error: !(result instanceof Ok), duration: performance.now() - start });
        }
      }
    }
    this.emit({ type: "complete", id, results: [], pending: "", duration: performance.now() - started });
  }
}
