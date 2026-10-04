import * as bridge from "../build/dev/javascript/overlay_terminal/tui/bridge.mjs";
import * as shell from "../build/dev/javascript/eyg_cli/eyg/cli/shell.mjs";
import { inspect } from "../build/dev/javascript/eyg_interpreter/eyg/interpreter/simple_debug.mjs";
import { toList, Ok, Error as GleamError } from "../build/dev/javascript/loam/gleam.mjs";
import type { State$ } from "../build/dev/javascript/loam/loam/execute.mjs";
import type { RuntimeEvent } from "./protocol";
import type { StructuralAction, StructuralView } from "./protocol";
import * as structural from "../build/dev/javascript/overlay_terminal/tui/structural.mjs";
import * as buffer from "../build/dev/javascript/morph/morph/buffer.mjs";
import { Resolved, UserInput, type UserInput$ } from "../build/dev/javascript/morph/morph/manipulation.mjs";
import { project, projectionText } from "./projection";
import { reference_to_string } from "../build/dev/javascript/eyg_ir/eyg/ir/tree.mjs";
import { drive, type DriverIO } from "./driver";

export class ReplRuntime {
  private scope: Parameters<typeof shell.handle>[1] = toList([]);
  private defs: Parameters<typeof shell.handle>[2] = toList([]);
  private state!: State$;
  private pending = "";
  private id = 0;
  private io: DriverIO;
  private editor?: buffer.Buffer$;
  private editing?: { input: UserInput$; label: string; kind: "text" | "file" | "package" };
  private previous: buffer.Buffer$[] = [];
  private after?: buffer.Buffer$;
  private referenceTypes: Parameters<typeof structural.reanalyse>[2] = toList([]);
  private referenceLoads = new Set<string>();
  private structuralFetches: string[] = [];
  constructor(private emit: (event: RuntimeEvent) => void, prompt: DriverIO["prompt"]) {
    this.io = {
      output: (text, error) => emit({ type: "output", id: this.id, text, error }),
      fetch: url => emit({ type: "fetch", id: this.id, url }),
      prompt,
    };
  }
  async initialize(args: string[]) {
    const result = await drive(bridge.initialize(toList(args)), this.io);
    if (result instanceof GleamError) throw new Error(result[0]);
    if (!(result instanceof Ok)) throw new Error("Invalid initialization result");
    [this.scope, this.state] = result[0];
    this.emit({ type: "ready", packages: [...bridge.cache_names(this.state)] });
  }
  async packages() {
    const snapshot = this.state;
    const [state, names] = await drive(bridge.packages(snapshot), { ...this.io, fetch() {} });
    // Discovery can finish after a run. Never replace that run's newer cache.
    if (this.state === snapshot) this.state = state;
    this.emit({ type: "packages", packages: [...names] });
  }
  structure(action: StructuralAction) {
    let message: string | undefined;
    if (action.action === "enter" && (action.source !== undefined || !this.editor)) {
      const parsed = structural.parse(action.source ?? "", this.scope, this.state);
      if (parsed instanceof GleamError) { this.emit({ type: "error", id: 0, message: parsed[0] }); return; }
      if (parsed instanceof Ok) this.editor = parsed[0]; this.editing = undefined;
    }
    this.editor ??= structural.empty(this.scope, this.state);
    const apply = (result: ReturnType<typeof structural.parse>) => {
      if (result instanceof Ok) { this.editor = result[0]; this.editing = undefined; }
      else if (result instanceof GleamError) message = result[0];
    };
    switch (action.action) {
      case "cancel": this.editing = undefined; break;
      case "answer":
        if (this.editing) apply(structural.answer(this.editing.input, action.text, this.scope, this.state));
        break;
      case "paste": apply(structural.paste(this.editor, action.text, this.scope, this.state)); break;
      case "focus": {
        const next = buffer.focus_at(this.editor, toList(action.path));
        if (next instanceof Ok) this.editor = next[0];
        break;
      }
      case "key": {
        if (action.key === "y") {
          const copied = buffer.copy_source(this.editor);
          if (copied instanceof Ok) { this.emit({ type: "clipboard", text: copied[0] }); message = "Copied expression"; }
          else message = "Select an expression to copy";
          break;
        }
        if (action.key === "u") { message = "The signing popup is a placeholder in the web workspace."; break; }
        const moved = structural.navigate(this.editor, action.key);
        if (moved instanceof Ok) { this.editor = moved[0]; break; }
        if (action.key === "up" && this.previous.length && !this.after) {
          this.after = this.editor; this.editor = this.previous.at(-1)!; break;
        }
        if (action.key === "down" && this.after) { this.editor = this.after; this.after = undefined; break; }
        const operation = structural.operation(this.editor, action.key, this.state);
        if (!(operation instanceof Ok)) { message = `Cannot apply ${action.key} at this selection`; break; }
        const [label, next] = operation[0];
        if (next instanceof Resolved) this.editor = structural.resolve(next[0], this.scope, this.state);
        if (next instanceof UserInput) this.editing = { input: next[0], label, kind: action.key === "q" || action.key === "Q" ? "file" : action.key === "@" ? "package" : "text" };
        break;
      }
    }
    this.emitStructure(message);
  }
  private emitStructure(message?: string) {
    if (!this.editor) return;
    this.editor = structural.reanalyse(this.editor, this.scope, this.referenceTypes);
    const [type, errors] = structural.type_info(this.editor);
    const view: StructuralView = { lines: project([structural.view(this.editor)]), source: projectionText(project(structural.display(this.editor))), type, errors: [...errors], message };
    if (this.editing) {
      const [value, hints] = structural.input_details(this.editing.input);
      view.input = { label: this.editing.label, kind: this.editing.kind, value, hints: [...hints] };
    }
    this.emit({ type: "structure", view });
    for (const reference of structural.references(this.editor)) {
      const key = reference_to_string(reference);
      if (this.referenceLoads.has(key)) continue;
      this.referenceLoads.add(key);
      const snapshot = this.state;
      void drive(structural.load_reference(reference, snapshot), { ...this.io, output() {}, fetch: url => this.structuralFetches.push(url) }).then(([type, state]) => {
        if (this.state === snapshot) this.state = state;
        if (type instanceof Ok) this.referenceTypes = toList([[reference, type[0]], ...this.referenceTypes]);
        this.emitStructure(type instanceof Ok ? undefined : `Unable to load ${key}`);
      }).catch(error => this.emitStructure(`Unable to load ${key}: ${error.message}`));
    }
  }
  async evaluate(id: number, source: string, fromStructure = false) {
    this.id = id;
    const started = performance.now();
    if (fromStructure) {
      for (const url of this.structuralFetches.splice(0)) this.emit({ type: "fetch", id, url });
    }
    const code = this.pending ? this.pending + "\n" + source : source;
    const observe: Parameters<typeof shell.handle_observed>[4] = (label, input, output) => {
      this.emit({ type: "effect", id, effect: { label, input: inspect(input), output: inspect(output) } }); return undefined;
    };
    const effect = fromStructure && this.editor
      ? shell.handle_source_observed(structural.executable(this.editor), this.scope, this.defs, this.state, observe)
      : shell.handle_observed(code, this.scope, this.defs, this.state, observe);
    const [results, next] = await drive(effect, this.io);
    [this.pending, this.scope, this.defs, this.state] = next;
    this.emit({ type: "complete", id, results: [...results].map(result => ({ text: result instanceof Ok || result instanceof GleamError ? result[0] : "Invalid evaluation result", error: !(result instanceof Ok) })), pending: this.pending, duration: performance.now() - started });
    if (fromStructure && this.editor && ![...results].some(result => result instanceof GleamError)) {
      this.previous.push(this.editor); this.after = undefined;
      this.editor = structural.empty(this.scope, this.state); this.editing = undefined;
      this.emitStructure();
    }
  }
}
