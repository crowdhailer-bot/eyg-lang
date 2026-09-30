// TodoMVC in TypeScript, with a console where the list is changed by running
// EYG, typed by a person or written by an agent.
import "todomvc-app-css/index.css";
import "../../todomvc_lustre/main.css";
import library from "../../todomvc_lustre/library.eyg?raw";
import guide from "../../../guides/syntax.md?raw";
import { createShell, type Run, type Shell } from "../../../packages/embed_js/dist/eyg.mjs";
import { Agent, systemPrompt, type Settings } from "./agent";
import { effects, handlers } from "./effects";
import { Tasks } from "./tasks";

type Entry =
  | { kind: "ran"; byModel: boolean; code: string; output: string; ok: boolean }
  | { kind: "said"; byModel: boolean; text: string }
  | { kind: "problem"; text: string };

const tasks = new Tasks([
  "Buy milk #shopping",
  "Call the plumber about the boiler",
  "Buy bread #shopping",
  "Write the EYG post #work",
  "Renew passport",
]);
const settings: Settings = { service: "ollama", address: location.origin, model: "qwen3", key: "" };
const state = {
  mode: "shell" as "shell" | "agent",
  filter: "all" as "all" | "active" | "completed",
  transcript: [] as Entry[],
  thinking: false,
  loading: "Loading @standard from the hub" as string | undefined,
};

const shell: Promise<Shell> = createShell({ effects, hub: location.origin, modules: { todos: library } });
let agent: Agent;
shell.then(
  (shell) => {
    state.loading = undefined;
    agent = new Agent(settings, systemPrompt(shell.text("todos"), guide));
    render();
  },
  (error) => {
    state.loading = String(error);
    render();
  },
);

/** What a person, or the model, is told about a run. */
function report(run: Run) {
  return run.error ?? run.display ?? "{}";
}

async function runCode(code: string, byModel: boolean) {
  const run = (await shell).run(code, handlers(tasks));
  state.transcript.push({ kind: "ran", byModel, code, output: report(run), ok: !run.error });
  render();
  return run;
}

async function ask(text: string) {
  const current = await shell;
  state.transcript.push({ kind: "said", byModel: false, text });
  state.thinking = true;
  render();
  try {
    const answer = await agent.ask(text, (code) => {
      const run = current.run(code, handlers(tasks));
      state.transcript.push({ kind: "ran", byModel: true, code, output: report(run), ok: !run.error });
      render();
      return report(run);
    });
    state.transcript.push({ kind: "said", byModel: true, text: answer });
  } catch (error) {
    state.transcript.push({ kind: "problem", text: String(error) });
  }
  state.thinking = false;
  render();
}

// VIEW ------------------------------------------------------------------------

function h<K extends keyof HTMLElementTagNameMap>(
  tag: K,
  props: Partial<HTMLElementTagNameMap[K]> & Record<string, unknown> = {},
  ...children: (Node | string | null)[]
) {
  const element = document.createElement(tag);
  for (const [key, value] of Object.entries(props)) {
    if (key.startsWith("on")) element.addEventListener(key.slice(2), value as EventListener);
    else if (key.startsWith("aria") || key === "for") element.setAttribute(key.replace("aria", "aria-").toLowerCase(), String(value));
    else (element as any)[key] = value;
  }
  for (const child of children) if (child !== null) element.append(child);
  return element;
}

const app = document.querySelector("#app")!;
let code = `let {list} = @standard\nlist.map(todos.tagged("#shopping"), (task) -> { task.title })`;
let prompt = "";

function render() {
  const focused = document.activeElement?.getAttribute("aria-label");
  app.replaceChildren(h("div", { className: "page" }, consoleView(), todoView()));
  if (focused) (app.querySelector(`[aria-label="${focused}"]`) as HTMLElement | null)?.focus();
}

function consoleView() {
  const tab = (mode: typeof state.mode, label: string) =>
    h("button", { className: "tab", ariaPressed: String(state.mode === mode), onclick: () => ((state.mode = mode), render()) }, label);
  const entries = state.loading
    ? [h("li", { className: "problem" }, state.loading)]
    : [...state.transcript].reverse().map(entryView);
  return h(
    "section",
    { className: "console" },
    h("header", { className: "tabs" }, tab("shell", "Shell"), tab("agent", "Agent")),
    h("ol", { className: "transcript" }, ...entries),
    state.mode === "shell" ? shellInput() : chatInput(),
  );
}

function entryView(entry: Entry) {
  switch (entry.kind) {
    case "ran":
      return h(
        "li",
        { className: `run${entry.ok ? "" : " failed"}${entry.byModel ? " by-model" : ""}` },
        h("pre", { className: "code" }, entry.code),
        h("pre", { className: "output" }, entry.output),
      );
    case "said":
      return h("li", { className: `said${entry.byModel ? " by-model" : ""}` }, entry.text);
    case "problem":
      return h("li", { className: "problem" }, entry.text);
  }
}

function onCtrlEnter(submit: () => void) {
  return (event: KeyboardEvent) => {
    if (event.key === "Enter" && (event.ctrlKey || event.metaKey)) {
      event.preventDefault();
      submit();
    }
  };
}

function shellInput() {
  const submit = () => runCode(code, false).then((run) => {
    if (!run.error) code = "";
    render();
  });
  return h(
    "form",
    { className: "input", onsubmit: (event: Event) => (event.preventDefault(), submit()) },
    h("textarea", {
      className: "code",
      ariaLabel: "EYG code",
      spellcheck: false,
      rows: 6,
      value: code,
      oninput: (event: Event) => (code = (event.target as HTMLTextAreaElement).value),
      onkeydown: onCtrlEnter(submit),
    }),
    h("button", { type: "submit", disabled: Boolean(state.loading) }, "Run"),
  );
}

function chatInput() {
  const field = (label: string, key: keyof Settings, extra: Record<string, unknown> = {}) =>
    h("input", {
      ariaLabel: label,
      value: settings[key],
      onchange: (event: Event) => {
        (settings as any)[key] = (event.target as HTMLInputElement).value;
        shell.then((shell) => (agent = new Agent(settings, systemPrompt(shell.text("todos"), guide))));
      },
      ...extra,
    });
  const submit = () => {
    if (state.thinking || !prompt.trim() || state.loading) return;
    const text = prompt.trim();
    prompt = "";
    ask(text);
  };
  return h(
    "div",
    { className: "input" },
    h(
      "div",
      { className: "settings" },
      h(
        "select",
        {
          ariaLabel: "Provider",
          onchange: (event: Event) => {
            settings.service = (event.target as HTMLSelectElement).value as Settings["service"];
            shell.then((shell) => (agent = new Agent(settings, systemPrompt(shell.text("todos"), guide))));
            render();
          },
        },
        h("option", { value: "ollama", selected: settings.service === "ollama" }, "Ollama"),
        h("option", { value: "mistral", selected: settings.service === "mistral" }, "Mistral"),
      ),
      field("Address", "address", { disabled: settings.service === "mistral" }),
      field("Model", "model"),
      field("API key", "key", { type: "password", placeholder: "API key" }),
    ),
    h(
      "form",
      { className: "prompt", onsubmit: (event: Event) => (event.preventDefault(), submit()) },
      h("textarea", {
        ariaLabel: "Message",
        placeholder: "Ask the agent to organise your tasks",
        rows: 3,
        value: prompt,
        oninput: (event: Event) => (prompt = (event.target as HTMLTextAreaElement).value),
        onkeydown: onCtrlEnter(submit),
      }),
      h("button", { type: "submit", disabled: state.thinking }, state.thinking ? "Thinking" : "Send"),
    ),
  );
}

let editing: { id: number; title: string } | undefined;

function todoView() {
  const left = tasks.items.filter((task) => !task.completed).length;
  const shown = tasks.items.filter((task) =>
    state.filter === "all" ? true : state.filter === "active" ? !task.completed : task.completed,
  );
  const filter = (name: typeof state.filter, label: string) =>
    h("li", {}, h("a", { href: `#/${name === "all" ? "" : name}`, className: state.filter === name ? "selected" : "", onclick: (event: Event) => (event.preventDefault(), (state.filter = name), render()) }, label));
  let title = "";
  return h(
    "div",
    { className: "app" },
    h(
      "section",
      { className: "todoapp" },
      h(
        "header",
        { className: "header" },
        h("h1", {}, "todos"),
        h(
          "form",
          { onsubmit: (event: Event) => (event.preventDefault(), title.trim() && tasks.create(title.trim()), render()) },
          h("input", { className: "new-todo", placeholder: "What needs to be done?", ariaLabel: "New todo", oninput: (event: Event) => (title = (event.target as HTMLInputElement).value) }),
        ),
      ),
      tasks.items.length === 0
        ? null
        : h(
            "main",
            { className: "main" },
            h(
              "div",
              { className: "toggle-all-container" },
              h("input", { className: "toggle-all", id: "toggle-all", type: "checkbox", checked: left === 0, onchange: (event: Event) => (tasks.completeAll((event.target as HTMLInputElement).checked), render()) }),
              h("label", { className: "toggle-all-label", for: "toggle-all" }, "Mark all as complete"),
            ),
            h("ul", { className: "todo-list" }, ...shown.map((task) => {
              const isEditing = editing?.id === task.id;
              return h(
                "li",
                { className: `${task.completed ? "completed" : ""} ${isEditing ? "editing" : ""}` },
                h(
                  "div",
                  { className: "view" },
                  h("input", { className: "toggle", type: "checkbox", checked: task.completed, onchange: (event: Event) => (tasks.setCompleted(task.id, (event.target as HTMLInputElement).checked), render()) }),
                  h("label", { ondblclick: () => ((editing = { id: task.id, title: task.title }), render()) }, task.title),
                  h("button", { className: "destroy", ariaLabel: `Delete ${task.title}`, onclick: () => (tasks.delete(task.id), render()) }),
                ),
                isEditing
                  ? h("input", {
                      className: "edit",
                      value: editing!.title,
                      oninput: (event: Event) => (editing!.title = (event.target as HTMLInputElement).value),
                      onkeydown: (event: KeyboardEvent) => {
                        if (event.key === "Escape") (editing = undefined), render();
                        if (event.key === "Enter") {
                          editing!.title.trim() ? tasks.rename(task.id, editing!.title.trim()) : tasks.delete(task.id);
                          editing = undefined;
                          render();
                        }
                      },
                    })
                  : null,
              );
            })),
          ),
      tasks.items.length === 0
        ? null
        : h(
            "footer",
            { className: "footer" },
            h("span", { className: "todo-count" }, h("strong", {}, String(left)), left === 1 ? " item left" : " items left"),
            h("ul", { className: "filters" }, filter("all", "All"), filter("active", "Active"), filter("completed", "Completed")),
            left === tasks.items.length ? null : h("button", { className: "clear-completed", onclick: () => (tasks.clearCompleted(), render()) }, "Clear completed"),
          ),
    ),
    h("p", { className: "info" }, "Double-click to edit a todo. The console can do the rest."),
  );
}

render();
