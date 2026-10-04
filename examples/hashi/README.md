# Hashi, played in EYG

The [hashi](https://github.com/giacomocavalieri/hashi) puzzle, with the board on the right
and on the left a console where the game is played by running EYG, typed by a person or
written by an agent. Pressing on the board does nothing.

The game is the original project, used unchanged as a git dependency.
The walk through is [`guides/embedding_hashi.md`](../../guides/embedding_hashi.md).

## Running it

Requires Gleam 1.18.1 or later for Git dependencies in subdirectories, Bun,
and the EYG CLI to fetch the original stylesheet.

```sh
eyg script bin/fetch_style.eyg   # the original stylesheet, into vendor/
bun install
bun run dev                      # http://127.0.0.1:5191/?seed=1
gleam test
```

The agent talks to Ollama through the dev server's `/api` proxy, or to Mistral with a key.

## Files

- `src/hashi/effect.gleam` the effects a program can perform, and their types.
- `src/hashi/board.gleam` carries the effects out with the original project's public API.
- `src/hashi/play.gleam` runs code against the board in an `eyg_embed` shell, keeping variables between runs.
- `src/hashi/app.gleam` the page, with the agent from `eyg_embed`.
- `library.eyg` helpers in scope as `hashi`, and the readme the agent is given.
- `solver.eyg` plays every forced bridge, paste it into the shell.
- `bin/record.mjs` records `media/`, with the model replaced by a fixed script.
