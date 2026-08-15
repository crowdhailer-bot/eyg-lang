# hashi

A hashiwokakero puzzle you cannot click on.

The board is on the right and nothing on it responds to a pointer. The only way
to build a bridge is to run a program, and there are two ways to do that: a
structural shell, where a person writes the program, and an agent, where a model
writes it from English. Both run the same programs against the same six effects
and the same board.

It is a demonstration of embedding EYG. The game is
[giacomocavalieri/hashi](https://github.com/giacomocavalieri/hashi), unchanged
except for one addition; everything about running programs against it is this
package.

## The six effects

`src/hashi/harness.gleam` is the whole of what a program can reach.

| Effect         | Takes                  | Answers                                          |
| -------------- | ---------------------- | ------------------------------------------------ |
| `ListIslands`  | `{}`                   | every island, with the bridges it needs           |
| `ListBridges`  | `{}`                   | every bridge built so far                         |
| `AddBridge`    | `{start, end}`         | `Ok` or why not: `BadStart`, `BadEnd`, `Full`     |
| `Undo`         | `{}`                   | whether there was a move to take back             |
| `Redo`         | `{}`                   | whether there was a move to put back              |
| `ShareOutcome` | the text to post       | `Ok` or why the post did not happen               |

There is no `Fetch`, no `Print` and no clipboard. Sharing needs the network, so
the platform makes that request; a program can ask for its result to be posted
and cannot ask for anything else to be sent anywhere.

## Development

The game is a path dependency on a clone of the original project. Get it first,
and see [`notes.md`](./notes.md) for the one change it needs:

```sh
git clone https://github.com/giacomocavalieri/hashi ../../../hashi
```

Then:

```sh
gleam test --runtime bun    # the harness, the game, the workspace, the app
bun install
bun run dev                 # http://localhost:5174
```

The agent side needs an Ollama Cloud or Mistral model and your own API token,
entered in the page. Both are kept in this tab's session storage and are gone
when it closes. Ollama calls go through the dev server's proxy because Ollama
Cloud does not allow browser CORS requests; Mistral is called directly.

## Screenshots and recordings

```sh
bun run bin/screenshots.mjs tmp/screenshots
bun run bin/record.mjs tmp/videos
```

Both need the dev server up. See `.agents/skills/browser/SKILL.md` in the parent
repository for why these two are JavaScript when everything else is EYG.

## What is where

| Path                     | What it is                                                      |
| ------------------------ | --------------------------------------------------------------- |
| `src/hashi/harness.gleam`| the six effects, their types and how values cross the boundary   |
| `src/hashi/game.gleam`   | the original project's board, in the shape the harness describes |
| `src/hashi/platform.gleam`| carrying the effects out                                        |
| `src/hashi/share.gleam`  | the conversation with spotless.run and Bluesky                   |
| `src/hashi/context.gleam`| reading the workspace module                                     |
| `src/hashi/shell.gleam`  | which key builds which piece of tree                             |
| `src/hashi/state.gleam`  | one workspace, two ways into it                                  |
| `eyg/context.eyg`        | the workspace: a readme for the model, functions for both        |
