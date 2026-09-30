# TodoMVC, scripted in EYG

[TodoMVC](https://todomvc.com) in Lustre, with a console beside it where the list is
changed by running EYG, typed by a person or written by an agent. Programs can read,
create, rename and complete tasks, and query them with the `@standard` package from the hub.
Only the page can delete a task.

The walk through is [`guides/embedding_todomvc.md`](../../guides/embedding_todomvc.md).

```sh
bun install
bun run dev    # http://127.0.0.1:5192/, proxies the hub and Ollama
gleam test
```

## Files

- `src/todomvc/tasks.gleam` the list, shared by the page and by programs.
- `src/todomvc/effect.gleam` the task effects and their types.
- `src/todomvc/run.gleam` runs code against the list in an `eyg_embed` shell, with packages from the hub cache.
- `src/todomvc/app.gleam` the page, loading the hub with `cache.load` and the agent from `eyg_embed`.
- `library.eyg` helpers in scope as `todos`, and the readme the agent is given.
- `bin/record.mjs` records `media/`, with the model replaced by a fixed script.
- `bin/tour.mjs` records `media/tour.webm`, a two minute tour of the shell and the agent.
