// The same agent as the Lustre example, written against the model's HTTP API
// directly. It has one tool, `run`, and the page decides what running means.

export interface Settings {
  service: "ollama" | "mistral";
  address: string;
  model: string;
  key: string;
}

type Call = { id?: string; function: { name: string; arguments: unknown } };

type Message =
  | { role: "system" | "user"; content: string }
  | { role: "assistant"; content: string; tool_calls?: Call[] }
  | { role: "tool"; content: string; tool_call_id?: string };

/** A request should never need this many round trips. */
const maxSteps = 20;

const tool = {
  type: "function",
  function: {
    name: "run",
    description:
      "Run an EYG program against the todo list. Variables defined with a final let are kept for later runs.",
    parameters: { type: "object", properties: { code: { type: "string" } }, required: ["code"] },
  },
};

export function systemPrompt(readme: string, guide: string) {
  return `You manage the user's todo list by writing EYG programs and running them with the run tool.
The run tool is the only way to see or change the tasks. Do not guess what tasks exist, look.
Prefer one program that makes several changes over many small runs.
Reply to the user in one or two plain sentences, do not include code in your reply.

# The todo list

${readme}

# EYG

${guide}`;
}

export class Agent {
  history: Message[] = [];

  constructor(
    private settings: Settings,
    private system: string,
  ) {}

  /** Answer a message, running code with `run` as often as the model asks. */
  async ask(text: string, run: (code: string) => string): Promise<string> {
    this.history.push({ role: "user", content: text });
    for (let step = 0; step < maxSteps; step++) {
      const reply = await this.complete();
      this.history.push(reply);
      if (!reply.tool_calls?.length) return reply.content;
      for (const call of reply.tool_calls) {
        const { code } = parseArguments(call.function.arguments);
        const content = call.function.name === "run" && code !== undefined
          ? run(code)
          : "Unknown tool, the only tool is run.";
        this.history.push({ role: "tool", content, tool_call_id: call.id });
      }
    }
    throw new Error(`Stopped after ${maxSteps} steps.`);
  }

  async complete(): Promise<Extract<Message, { role: "assistant" }>> {
    const messages = [{ role: "system", content: this.system }, ...this.history];
    const { service, address, model, key } = this.settings;
    const mistral = service === "mistral";
    const response = await fetch(mistral ? "https://api.mistral.ai/v1/chat/completions" : `${address}/api/chat`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        ...(key ? { authorization: `Bearer ${key}` } : {}),
      },
      body: JSON.stringify({ model, messages, tools: [tool], stream: false }),
    });
    if (!response.ok) throw new Error(`model answered ${response.status}`);
    const body = await response.json();
    const message = mistral ? body.choices[0].message : body.message;
    return { role: "assistant", content: message.content ?? "", tool_calls: message.tool_calls };
  }
}

// Ollama sends arguments as an object, Mistral as a JSON string.
function parseArguments(raw: unknown): { code?: string } {
  const value = typeof raw === "string" ? JSON.parse(raw) : raw;
  return typeof value === "object" && value !== null ? (value as { code?: string }) : {};
}
