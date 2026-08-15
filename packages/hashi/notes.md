# Notes

Everything here is something a reader would otherwise have to work out from the
code, or a place where this package depends on something it does not control.

## The original project

The game is [giacomocavalieri/hashi][hashi], cloned next to this repository at
`../../../hashi` and depended on by path. `shared/hashi` generates and checks
puzzles; `frontend/hashi_grid` holds the board a player is working on and draws
it. None of that is written twice here.

[hashi]: https://github.com/giacomocavalieri/hashi

### The one change made to it

`frontend/src/frontend/hashi_grid.gleam` gained a public `add_bridge` and a
`BridgeError` to go with it, on a branch called `eyg-embedding`:

```gleam
pub type BridgeError { BadStart BadEnd Full }

pub fn add_bridge(model, start, end) -> Result(Model, BridgeError)
```

The project connects islands through pointer messages — press one, press the
other — and a move that breaks the rules quietly does nothing, which is right
for a finger on a screen and no use to a program. `add_bridge` is the same move
with the reason it was refused. It calls the project's own `can_connect` and
`connect_islands`, so no rule is reimplemented; it only reports.

Nothing else was touched. `is_complete`, `step_back`, `step_forward`,
`current_solution` and `view` were already public and are used as they are.

### It is not sent upstream

The project's README asks that LLM tools are not used to write issues or pull
requests to it. Nothing here has been or will be sent there. The change lives on
a local branch of the clone, and this note is where it is recorded.

### What that means for building this

`gleam build` needs the clone. From this directory:

```sh
git clone https://github.com/giacomocavalieri/hashi ../../../hashi
(cd ../../../hashi && git checkout -b eyg-embedding)
```

then apply the `add_bridge` addition above. The board's stylesheet is imported
straight out of the clone by `main.css`, so it has to be there for the page to
look right as well as to compile.

## Sharing a finished board

`ShareOutcome` is device-code OAuth against spotless.run, then a post written to
the account's own repository on Bluesky. Every request and every answer in that
flow is a pure function in `hashi/share.gleam` with a test.

**It cannot work yet.** spotless.run has no `bluesky` party, so the first
request answers 404 and the program is told so. Adding one is not a small job
either: atproto's OAuth wants DPoP-bound tokens, pushed authorization requests
and the account's own server resolved before any of it, and spotless's device
flow hands out plain bearer tokens. The flow here is written against the shape
spotless already has, so when a party exists the only thing to revisit is
whether the token needs binding.

The account's server is assumed to be `bsky.social`. An account on another
server needs its host, which is only knowable once spotless says where the
account lives.

## Reading it as an agent, and as a person

`eyg/context.eyg` is the workspace both sides share. It is a module with a
`readme`, which is the convention for a context: the readme is what the model is
told, and the fields of the module are what it can call.

It uses nothing but builtins — no `import`, no package reference — because a
module that referenced a package would have to fetch it, and the harness here
has no `Fetch`. That is why the shell can offer `picture` and `connect` in its
autocomplete before the page has talked to anything.

The page hands the source in rather than fetching it: `index.html` imports it
with vite's `?raw` and passes it to `main`. Tests read it off disk.

## Things that would be worth doing next

- The chat panel renders the conversation without djot in this application, and
  with it in `overlay_public`. The djot rendering is in
  `overlay/web/components/chat` and both use it, so this is already shared; what
  is not shared is the surrounding page.
- `morph`'s picker decides with the value it was last rendered with, so typing a
  name and pressing enter in the same frame loses the last character. The
  screenshot driver types with a delay to work around it. It would be better
  fixed in `morph`.
- The shell runs one program at a time. Nothing needs more, but the plumbing in
  `state` carries a list of running programs, so more would not be a rewrite.
