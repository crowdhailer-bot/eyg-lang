import { expect, test } from "bun:test";
import { Agent } from "../src/agent";
import { handlers } from "../src/effects";
import { Tasks } from "../src/tasks";

test("effects create and change tasks", () => {
  const tasks = new Tasks(["a"]);
  const handle = handlers(tasks);
  expect(handle.CreateTask("b")).toBe(2);
  expect(handle.SetCompleted({ id: 1, completed: true })).toEqual({ $: "Ok" });
  expect(handle.RenameTask({ id: 9, title: "x" })).toEqual({ $: "Error", value: { $: "NotFound" } });
  expect(handle.ListTasks({})).toEqual([
    { id: 1, title: "a", completed: true },
    { id: 2, title: "b", completed: false },
  ]);
});

test("the agent runs code until the model answers", async () => {
  const replies = [
    { message: { content: "", tool_calls: [{ function: { name: "run", arguments: { code: "todos.all({})" } } }] } },
    { message: { content: "There is one task." } },
  ];
  const sent: any[] = [];
  globalThis.fetch = (async (_url: string, init: RequestInit) => {
    sent.push(JSON.parse(String(init.body)));
    return new Response(JSON.stringify(replies.shift()));
  }) as typeof fetch;
  const ran: string[] = [];
  const agent = new Agent({ service: "ollama", address: "http://model", model: "m", key: "" }, "system");
  const answer = await agent.ask("how many?", (code) => (ran.push(code), "[1]"));
  expect(answer).toBe("There is one task.");
  expect(ran).toEqual(["todos.all({})"]);
  expect(sent[1].messages.at(-1)).toEqual({ role: "tool", content: "[1]" });
  expect(sent[0].tools[0].function.name).toBe("run");
});
