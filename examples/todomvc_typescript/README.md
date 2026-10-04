# TodoMVC in TypeScript, scripted in EYG

The same list, library and agent as [`todomvc_lustre`](../todomvc_lustre), with the page,
the effects and the agent written in TypeScript. EYG is reached through `eyg.mjs`, the
bundle built by [`packages/embed_js`](../../packages/embed_js): describe effects as data,
answer them with functions, exchange plain values.

The walk through is [`guides/embedding_typescript.md`](../../guides/embedding_typescript.md).

```sh
bun install
bun run dev     # builds eyg.mjs, http://127.0.0.1:5193/
bun run check   # tsc
bun run test
```

## Files

- `src/effects.ts` the task effects, their types and their handlers.
- `src/agent.ts` the agent, against the model's HTTP API, with one `run` tool.
- `src/main.ts` the page.
- `bin/record.mjs` records `media/`, with the model replaced by a fixed script.
