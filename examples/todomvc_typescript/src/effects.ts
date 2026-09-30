// The effects an EYG program can perform on the list, and what they do.
// Programs can read, create and change tasks. Deleting is left to the page.
import type { Effects, Handlers } from "../../../packages/embed_js/dist/eyg.mjs";
import type { Tasks } from "./tasks";

const task = { record: { id: "integer", title: "string", completed: "boolean" } } as const;
const found = { result: { ok: "unit", error: { union: { NotFound: "unit" } } } } as const;

export const effects: Effects = {
  ListTasks: { lift: "unit", lower: { list: task } },
  CreateTask: { lift: "string", lower: "integer" },
  RenameTask: { lift: { record: { id: "integer", title: "string" } }, lower: found },
  SetCompleted: { lift: { record: { id: "integer", completed: "boolean" } }, lower: found },
};

const outcome = (ok: boolean) => (ok ? { $: "Ok" } : { $: "Error", value: { $: "NotFound" } });

export function handlers(tasks: Tasks): Handlers {
  return {
    ListTasks: () => tasks.items.map((task) => ({ ...task })),
    CreateTask: (title: string) => tasks.create(title),
    RenameTask: ({ id, title }: { id: number; title: string }) => outcome(tasks.rename(id, title)),
    SetCompleted: ({ id, completed }: { id: number; completed: boolean }) =>
      outcome(tasks.setCompleted(id, completed)),
  };
}
