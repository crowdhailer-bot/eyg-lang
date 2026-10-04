import { render, useKeyboard, usePaste, useRenderer } from "@opentui/solid";
import { createMemo, createSignal, For, onCleanup, onMount, Show } from "solid-js";
import type { ScrollBoxRenderable, TextareaRenderable } from "@opentui/core";
import { colors, codeChunks, highlight, syntaxStyle } from "../highlight";
import { complete, type Completion } from "../completion";
import type { EffectRecord, RuntimeEvent, RuntimeRequest } from "../protocol";
import type { StructuralView } from "../protocol";
import { createHostClipboard, type HostClipboardService } from "@opentui/core";
import { Structure } from "./structure";
import { RuntimeProcess } from "../runtime-process";

export type Entry = { id: number; source: string; output: string; results: { text: string; error: boolean }[]; effects: EffectRecord[]; fetches: string[]; duration?: number; expanded: boolean; busy: boolean; role?: "user" | "assistant" | "tool"; name?: string; codeExpanded?: boolean; outputExpanded?: boolean };
export interface RuntimePort {
  postMessage(request: RuntimeRequest): void;
  terminate(): unknown;
  onmessage: ((event: MessageEvent<RuntimeEvent>) => void) | null;
  onerror: ((event: ErrorEvent) => void) | null;
}

function Code(props: { source: string }) {
  return <text><For each={codeChunks(props.source)}>{chunk => <span style={{ fg: chunk.color }}>{chunk.text}</span>}</For></text>;
}

export function App(props: { args: string[]; port: RuntimePort; cwd?: string }) {
  const renderer = useRenderer();
  const style = syntaxStyle();
  const [ready, setReady] = createSignal(false);
  const [busy, setBusy] = createSignal(false);
  const [entries, setEntries] = createSignal<Entry[]>([]);
  const [packages, setPackages] = createSignal<string[]>([]);
  const [source, setSource] = createSignal("");
  const [status, setStatus] = createSignal("Starting EYG…");
  const [prompt, setPrompt] = createSignal<string>();
  const [choices, setChoices] = createSignal<Completion[]>([]);
  const [choice, setChoice] = createSignal(0);
  const [help, setHelp] = createSignal(false);
  const [model, setModel] = createSignal("");
  const [structuralMode, setStructuralMode] = createSignal(false);
  const [structure, setStructure] = createSignal<StructuralView>();
  const overlayMode = props.args[0] === "overlay";
  let editor!: TextareaRenderable;
  let scroll!: ScrollBoxRenderable;
  let sequence = 0;
  let completionRevision = 0;
  let promptDraft = "";
  let textDraft = "";
  let importedDraft: string | undefined;
  let clipboardText = "";
  let clipboard: HostClipboardService | undefined;
  let enteringStructure = false;
  const cwd = props.cwd ?? process.cwd();
  const directory = cwd.split("/").filter(Boolean).at(-1) ?? cwd;
  const update = (id: number, patch: (entry: Entry) => Partial<Entry>) => setEntries(list => list.map(entry => entry.id === id ? { ...entry, ...patch(entry) } : entry));
  function receive(event: RuntimeEvent) {
    switch (event.type) {
      case "structure": {
        enteringStructure = false;
        const wasInput = structure()?.input;
        setStructure(event.view); setStatus(event.view.message ?? (prompt() !== undefined ? "Waiting for input" : busy() ? "Running…" : "Ready"));
        if (structuralMode() && prompt() === undefined) {
          if (event.view.input && (!wasInput || wasInput.label !== event.view.input.label)) {
            editor.setText(event.view.input.value); editor.focus();
            if (event.view.input.kind === "text") editor.selectAll();
          } else if (!event.view.input) { editor.clear(); editor.blur(); }
          changed();
        }
        break;
      }
      case "clipboard":
        clipboardText = event.text; renderer.copyToClipboardOSC52(event.text);
        clipboard ??= createHostClipboard();
        void clipboard.writeText(event.text); break;
      case "ready": setReady(true); setPackages(event.packages); setStatus("Ready"); break;
      case "overlay-ready": setReady(true); setModel(event.model); setStatus("Ready"); break;
      case "assistant":
        if (!entries().some(entry => entry.id === event.id)) setEntries(list => [...list, { id: event.id, source: "", output: event.text, results: [], effects: [], fetches: [], expanded: false, busy: false, role: "assistant" }]);
        else update(event.id, entry => ({ output: entry.output + event.text }));
        break;
      case "tool": setEntries(list => [...list, { id: event.id, source: event.code, output: "", results: [], effects: [], fetches: [], expanded: false, busy: true, role: "tool", name: event.name, codeExpanded: false }]); break;
      case "tool-result": update(event.id, () => ({ results: [{ text: event.text, error: event.error }], busy: false, duration: event.duration })); break;
      case "packages": setPackages(event.packages); break;
      case "output": update(event.id, entry => ({ output: entry.output + event.text })); break;
      case "fetch": update(event.id, entry => ({ fetches: [...entry.fetches, event.url] })); break;
      case "effect": update(event.id, entry => ({ effects: [...entry.effects, event.effect] })); break;
      case "prompt":
        promptDraft = editor.plainText; editor.clear();
        editor.focus();
        setPrompt(event.text || "Input requested"); setStatus("Waiting for input"); break;
      case "complete":
        update(event.id, () => ({ results: event.results, duration: event.duration, busy: false }));
        setBusy(false); setPrompt(undefined); setStatus(event.pending ? "Continue the expression…" : "Ready"); break;
      case "error":
        if (enteringStructure) { enteringStructure = false; importedDraft = undefined; setStructuralMode(false); editor.setText(textDraft); editor.focus(); }
        if (!event.id) { setStatus(event.message); break; }
        if (event.id) update(event.id, () => ({ results: [{ text: event.message, error: true }], busy: false }));
        setEntries(list => list.map(entry => entry.busy ? { ...entry, busy: false } : entry));
        setBusy(false); setStatus(event.message); break;
    }
  }
  onMount(() => {
    props.port.onmessage = event => receive(event.data);
    props.port.onerror = event => { setBusy(false); setStatus(event.message); };
    props.port.postMessage({ type: "initialize", args: props.args });
    editor.focus();
  });
  onCleanup(() => { ++completionRevision; props.port.terminate(); style.destroy(); void clipboard?.dispose(); });

  function changed() {
    const revision = ++completionRevision;
    // OpenTUI emits content and cursor changes during the same edit. Sample
    // after both have settled so completion never uses the previous cursor.
    queueMicrotask(async () => {
      if (!editor || revision !== completionRevision) return;
      const value = editor.plainText;
      if (!overlayMode && value !== source()) highlight(editor, style);
      setSource(value);
      // cursorCharacterOffset points at the last character when at EOF;
      // completion needs the insertion position, including the end of buffer.
      const index = editor.editBuffer.getTextRange(0, editor.cursorOffset).length;
      const input = structuralMode() ? structure()?.input : undefined;
      let found: Completion[];
      if (input?.kind === "file") {
        found = (await complete('import "' + value, 8 + index, packages(), cwd)).map(item => ({ ...item, from: item.from - 8, to: item.to - 8 }));
      } else if (input) {
        const hints: [string, string][] = input.kind === "package" ? packages().map(name => [name, "hub package"]) : input.hints;
        found = hints.filter(([name]) => name.includes(value)).slice(0, 30).map(([name, detail]) => ({ label: name, detail, insert: name, from: 0, to: value.length }));
      } else found = structuralMode() ? [] : await complete(value, index, packages(), cwd);
      if (revision !== completionRevision) return;
      setChoices(found); setChoice(0);
    });
  }
  function accept() {
    const selected = choices()[choice()];
    if (!selected) return;
    const value = editor.plainText;
    const next = value.slice(0, selected.from) + selected.insert + value.slice(selected.to);
    editor.replaceText(next);
    const lines = next.slice(0, selected.from + selected.insert.length).split("\n");
    editor.setCursor(lines.length - 1, Bun.stringWidth(lines.at(-1)!));
    setChoices([]);
  }
  function submit() {
    let text = editor.plainText;
    if (prompt() !== undefined) {
      props.port.postMessage({ type: "answer", text });
      setPrompt(undefined); editor.setText(promptDraft); promptDraft = ""; setStatus("Running…"); return;
    }
    if (structuralMode() && structure()?.input) {
      props.port.postMessage({ type: "structure", action: "answer", text }); return;
    }
    if (structuralMode()) text = structure()?.source ?? "";
    if (!ready() || busy() || !text.trim()) return;
    if (text.trim() === "/exit") { renderer.destroy(); return; }
    const id = ++sequence;
    scroll.stickyScroll = true;
    scroll.scrollTo(scroll.scrollHeight);
    setEntries(list => [...list, { id, source: text, output: "", results: [], effects: [], fetches: [], expanded: false, busy: true, role: overlayMode ? "user" : undefined }]);
    setBusy(true); setStatus("Running…"); setChoices([]); editor.clear();
    props.port.postMessage({ type: "evaluate", id, source: text, ...(structuralMode() ? { structural: true } : {}) });
  }
  function switchMode() {
    if (overlayMode || busy() || prompt() !== undefined || !ready()) return;
    setChoices([]);
    if (structuralMode()) {
      setStructuralMode(false); editor.setText(textDraft); editor.focus();
    } else {
      textDraft = editor.plainText; setStructuralMode(true); editor.clear(); editor.blur();
      enteringStructure = true;
      const source = importedDraft === textDraft ? undefined : textDraft;
      importedDraft = textDraft;
      props.port.postMessage({ type: "structure", action: "enter", source });
    }
  }
  async function pasteStructure() {
    clipboard ??= createHostClipboard();
    const result = await clipboard.read({ preferredTypes: ["text/plain"] });
    const text = result.status === "read" ? new TextDecoder().decode(result.representation.bytes) : clipboardText;
    if (text) props.port.postMessage({ type: "structure", action: "paste", text });
    else setStatus("Clipboard unavailable. Paste EYG or DAG JSON using your terminal paste shortcut.");
  }
  usePaste(event => {
    if (structuralMode() && !structure()?.input && prompt() === undefined) {
      event.preventDefault(); props.port.postMessage({ type: "structure", action: "paste", text: new TextDecoder().decode(event.bytes) });
    }
  });
  function reveal(id: string) {
    scroll.stickyScroll = false;
    renderer.once("frame", () => scroll.scrollChildIntoView(id));
    renderer.requestRender();
  }
  function toggle(id: number) {
    update(id, entry => ({ expanded: !entry.expanded }));
    reveal(entries().find(entry => entry.id === id)?.expanded ? `details-${id}` : `effects-${id}`);
  }
  function toggleCode(id: number) {
    update(id, entry => ({ codeExpanded: !entry.codeExpanded }));
    reveal(`code-${id}`);
  }
  useKeyboard(key => {
    if (key.ctrl && key.name === "c") { key.preventDefault(); renderer.destroy(); return; }
    if (key.name === "f1") { key.preventDefault(); setHelp(value => !value); return; }
    if (key.name === "f2") { key.preventDefault(); switchMode(); return; }
    if (key.ctrl && key.name === "e") {
      key.preventDefault(); const last = entries().findLast(entry => entry.effects.length || entry.fetches.length); if (last) toggle(last.id); return;
    }
    if (key.ctrl && key.name === "o") {
      key.preventDefault(); const last = entries().findLast(entry => entry.role === "tool");
      if (last) toggleCode(last.id); return;
    }
    if (key.name === "pageup" || key.name === "pagedown") {
      key.preventDefault(); scroll.scrollBy(key.name === "pageup" ? -12 : 12); return;
    }
    if (structuralMode() && prompt() === undefined) {
      if (key.name === "escape") {
        key.preventDefault();
        if (structure()?.input) props.port.postMessage({ type: "structure", action: "cancel" });
        else switchMode();
        return;
      }
      if (!structure()?.input) {
        key.preventDefault();
        if (busy()) return;
        if (key.name === "return") { submit(); return; }
        const command = key.name === "space" ? " " : key.sequence.length === 1 ? key.sequence : key.shift ? key.name.toUpperCase() : key.name;
        if (command === "Y") { void pasteStructure(); return; }
        props.port.postMessage({ type: "structure", action: "key", key: command }); return;
      }
    }
    if (choices().length) {
      if (key.name === "tab") { key.preventDefault(); accept(); return; }
      if (key.name === "up" || key.name === "down") {
        key.preventDefault(); setChoice(index => (index + (key.name === "up" ? -1 : 1) + choices().length) % choices().length); return;
      }
      if (key.name === "escape") { key.preventDefault(); setChoices([]); }
    }
  });
  const inputHeight = createMemo(() => Math.min(9, Math.max(2, source().split("\n").length + 1)));

  return <box flexDirection="column" width="100%" height="100%" backgroundColor={colors.bg} paddingX={2}>
    <box height={3} flexDirection="row" alignItems="center" justifyContent="space-between" flexShrink={0}>
      <text fg={colors.text}><b>eyg</b><span style={{ fg: colors.muted }}> / </span><span style={{ fg: colors.accent }}>{overlayMode ? "overlay" : "repl"}</span></text>
      <text fg={colors.muted}>{directory}  ·  {overlayMode ? model() : `${packages().length} packages`}</text>
    </box>
    <scrollbox ref={scroll} flexGrow={1} minHeight={0} stickyScroll stickyStart="bottom" scrollbarOptions={{ visible: false }}>
      <Show when={entries().length === 0}>
        <box paddingTop={3} paddingBottom={3} paddingX={2} gap={1}>
          <text fg={colors.text}><b>Eat Your Greens</b></text>
          <text fg={colors.muted}>{overlayMode ? "An agent with tools you can inspect." : "An expression. A useful result."}</text>
          <text fg={colors.muted}>{overlayMode ? "Ask a question or describe a task to get started." : "Try @standard.integer.add(20, 22)"}</text>
        </box>
      </Show>
      <For each={entries()}>{entry => <box flexDirection="column" marginBottom={1}>
        <Show when={entry.role !== "assistant"}>
          <box backgroundColor={colors.panel} paddingX={2} paddingY={1}>
            <Show when={entry.role === "tool"} fallback={overlayMode ? <text fg={colors.text}>{entry.source}</text> : <Code source={entry.source} />}>
              <text id={`code-${entry.id}`} fg={colors.blue} onMouseDown={() => toggleCode(entry.id)}>{entry.codeExpanded ? "▾" : "▸"} {entry.name}  <span style={{ fg: colors.muted }}>{entry.busy ? "running" : `${Math.round(entry.duration ?? 0)} ms`} · code</span></text>
              <Show when={entry.codeExpanded}><Code source={entry.source} /></Show>
            </Show>
          </box>
        </Show>
        <box paddingX={2} paddingY={1} gap={1}>
          <Show when={entry.role === "assistant"}>
            <markdown content={entry.output} syntaxStyle={style} fg={colors.text} conceal streaming={busy()} />
          </Show>
          <Show when={entry.role !== "assistant" && entry.output && (entry.role !== "tool" || !entry.results.length)}><text fg={colors.muted}>{entry.output.trimEnd()}</text></Show>
          <For each={entry.results}>{result => <box>
            <text fg={result.error ? colors.red : colors.accent}>{entry.role === "tool" && !entry.outputExpanded ? result.text.split("\n").slice(0, 8).join("\n") : result.text}</text>
            <Show when={entry.role === "tool" && result.text.split("\n").length > 8}>
              <text fg={colors.muted} onMouseDown={() => { update(entry.id, item => ({ outputExpanded: !item.outputExpanded })); reveal(`code-${entry.id}`); }}>{entry.outputExpanded ? "▾ Collapse output" : `▸ Show all ${result.text.split("\n").length} lines`}</text>
            </Show>
          </box>}</For>
          <Show when={entry.busy}><text fg={colors.muted}>● Running…</text></Show>
          <Show when={entry.effects.length || entry.fetches.length}>
            <text id={`effects-${entry.id}`} fg={colors.muted} onMouseDown={() => toggle(entry.id)}>{entry.expanded ? "▾" : "▸"} {entry.effects.length} effects{entry.fetches.length ? ` · ${entry.fetches.length} hub requests` : ""}  <span style={{ fg: colors.muted }}>{entry.duration === undefined ? "" : `${Math.round(entry.duration)} ms`}</span></text>
            <Show when={entry.expanded}>
              <box id={`details-${entry.id}`} gap={1}>
              <For each={entry.fetches}>{url => <text fg={colors.blue}>↓ {url}</text>}</For>
              <For each={entry.effects}>{effect => <box paddingLeft={2}>
                <text fg={colors.orange}>{effect.label}<span style={{ fg: colors.text }}>({effect.input})</span></text>
                <text fg={colors.muted}>↳ {effect.decision ? `${effect.decision} · ` : ""}{effect.output}</text>
              </box>}</For>
              </box>
            </Show>
          </Show>
        </box>
      </box>}</For>
    </scrollbox>
    <Show when={help()}><box backgroundColor={colors.panel} paddingX={2} paddingY={1}>
      <text fg={colors.text}>Enter run · Shift+Enter newline · Tab complete · Ctrl+E effects · Ctrl+O code · PgUp/PgDn scroll</text>
      <text fg={colors.muted}>/scope bindings · /type expression · /help · /exit · Ctrl+C quit · F1 close help</text>
      <Show when={!overlayMode}><text fg={colors.muted}>F2 text/structure · arrows navigate · Space vacant · a select parent · i edit · d delete · z/Z undo/redo</text>
        <text fg={colors.muted}>n integer · s string · b binary · v variable · f function · c/C/w call · e/E let · l/L list · r/R record</text>
        <text fg={colors.muted}>g field · o overwrite · t tag · m match · p/h effects · j builtin · @/# reference · q/Q file · x spread</text>
        <text fg={colors.muted}>y/Y copy/paste · k fold · &lt;/&gt; insert before/after · Enter evaluate · Escape dismiss / text</text></Show>
    </box></Show>
    <Show when={structuralMode() && structure()}>{view => <Structure view={view()} focus={path => props.port.postMessage({ type: "structure", action: "focus", path })} />}</Show>
    <Show when={choices().length && !busy()}><box backgroundColor={colors.panel} paddingX={2} paddingY={1}>
      <For each={choices().slice(Math.max(0, choice() - 5), Math.max(0, choice() - 5) + 6)}>{item =>
        <text fg={item === choices()[choice()] ? colors.accent : colors.muted}>{item === choices()[choice()] ? "› " : "  "}{item.label}  <span style={{ fg: colors.muted }}>{item.detail}</span></text>
      }</For>
    </box></Show>
    <box backgroundColor={colors.panel} border={["left"]} borderColor={colors.accent} paddingLeft={2} paddingRight={2} paddingTop={1} flexShrink={0}>
      <Show when={prompt() !== undefined}><text fg={colors.orange}>{prompt()}</text></Show>
      <Show when={structuralMode() && structure()?.input}><text fg={colors.blue}>{structure()!.input!.label} · Enter confirm · Escape cancel</text></Show>
      <textarea ref={editor} visible={!structuralMode() || !!structure()?.input || prompt() !== undefined} height={inputHeight()} focused={!structuralMode() || !!structure()?.input || prompt() !== undefined} syntaxStyle={style} textColor={colors.text} backgroundColor={colors.panel}
        focusedBackgroundColor={colors.panel} cursorColor={colors.accent} wrapMode="word"
        placeholder={busy() && prompt() === undefined ? "You can draft while this runs…" : overlayMode ? "Ask anything…" : "Write EYG…"}
        onContentChange={changed} onCursorChange={changed} onSubmit={submit}
        keyBindings={[{ name: "return", action: "submit" }, { name: "return", shift: true, action: "newline" }, { name: "return", meta: true, action: "newline" }]} />
      <box height={1} justifyContent="space-between" flexDirection="row">
        <text fg={colors.accent}>{overlayMode ? "Overlay" : structuralMode() ? "Structure" : "Text"}<span style={{ fg: colors.muted }}>  {overlayMode ? model() : "EYG"}</span></text>
        <text fg={colors.muted}>{overlayMode ? "enter send  ·  shift+enter newline" : structuralMode() ? "enter run  ·  f2 text" : "enter run  ·  tab complete  ·  f2 structure"}</text>
      </box>
    </box>
    <box height={2} paddingTop={1} flexDirection="row" justifyContent="space-between" flexShrink={0}>
      <text fg={colors.muted}>{status()}</text><text fg={colors.muted}>{overlayMode ? "ctrl+o code  ·  " : ""}ctrl+e effects  ·  f1 help</text>
    </box>
  </box>;
}

export async function start(args: string[]) {
  const worker = new RuntimeProcess();
  await render(() => <App args={args} port={worker} />, { exitOnCtrlC: false, targetFps: 60 });
}
