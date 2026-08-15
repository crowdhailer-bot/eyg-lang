---
name: Building an embedded runtime
description: How to give an application its own EYG runtime, so that a person or an agent can program it and reach nothing else.
---

# Building an embedded runtime

There is a version of "make it programmable" that most applications stop at: a
list of commands, each with a name and some arguments, and a dispatcher. It
works until somebody wants to do two things in a row, and then three, and then
one of them only if the first one worked. At that point the list of commands is
a programming language with none of the parts that make one worth having.

An embedded runtime is the other version. The application decides what exists —
the effects, and only those — and a real language decides everything else:
sequencing, branching, naming a value, folding over a list. This guide builds
one, end to end, small enough to read in a sitting.

The worked example is a hashiwokakero puzzle. The board is drawn but nothing on
it is clickable: the only way to build a bridge is to run a program.
[The source is in the repository](https://github.com/CrowdHailer/eyg-lang/tree/main/packages/hashi).

## What you decide, and what you get

You decide the *harness*: a list of effects with a name and two types each,
what a program can lift into an effect and what it gets back. That is the whole
of the boundary. Everything else — parsing, type checking, evaluation, pausing a
program half way through an effect and resuming it when the answer arrives —
comes with the language.

The game's harness is six effects:

| Effect         | Takes            | Answers                                      |
| -------------- | ---------------- | -------------------------------------------- |
| `ListIslands`  | `{}`             | every island, with the bridges it needs       |
| `ListBridges`  | `{}`             | every bridge built so far                     |
| `AddBridge`    | `{start, end}`   | `Ok` or `BadStart`, `BadEnd`, `Full`          |
| `Undo`         | `{}`             | whether there was a move to take back         |
| `Redo`         | `{}`             | whether there was a move to put back          |
| `ShareOutcome` | the text to post | `Ok` or why the post did not happen           |

There is no `Fetch` in that list, no `Print`, no clipboard, no file system. Not
because they were forgotten: because a program running in this page has no
business with any of them. `ShareOutcome` does reach the network, and the point
of it being an effect rather than a fetch is that the program says *what* it
wants — this result, shared — and the platform decides *where* that goes.

## One: describe the effects

An effect is a name, the type of what goes in, the type of what comes back, and
a function that turns the EYG value a program lifted into something your
language can hold.

```gleam
import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/cast
import touch_grass/interface.{Interface}

pub type Effect {
  ListIslands
  ListBridges
  AddBridge(start: Position, end: Position)
  ShareOutcome(text: String)
  Undo
  Redo
}

pub fn effects() {
  [
    Interface(
      name: "ListIslands",
      lift_type: t.unit,
      lower_type: t.List(island()),
      decode: cast.as_unit(_, ListIslands),
    ),
    Interface(
      name: "AddBridge",
      lift_type: span(),
      lower_type: t.result(t.unit, bridge_error()),
      decode: span_decode,
    ),
    // ...
  ]
}
```

The types are worth care. They are not decoration: they are what the type
checker uses to reject a program before it runs, and what the model is shown so
it does not have to guess.

`AddBridge` answering `Result({}, BadStart | BadEnd | Full)` rather than a
boolean is the difference between "that did not work" and "there is no island
where you started". Both a person and a model do better with the second.

Casting is the only place values cross the boundary:

```gleam
pub fn position_decode(value) {
  use x <- result.try(cast.field("x", cast.as_integer, value))
  use y <- result.try(cast.field("y", cast.as_integer, value))
  Ok(#(x, y))
}
```

and back the other way:

```gleam
pub fn position_encode(position: Position) {
  let #(x, y) = position
  v.Record(dict.from_list([#("x", v.Integer(x)), #("y", v.Integer(y))]))
}
```

## Two: carry them out

The harness says what exists. Something else has to do it. The shape that works
is a function from the application's state and an effect to the new state and
what is to be done:

```gleam
pub fn handle(host: Host, label: String, lift) -> #(Host, Handling) {
  case harness.cast(label, lift) {
    Error(reason) -> #(host, Unknown(reason))
    Ok(effect) -> perform(host, effect)
  }
}

fn perform(host: Host, effect) {
  case effect {
    harness.ListIslands -> #(
      host,
      immediately(harness.islands_encode(game.islands(host.game))),
    )
    harness.AddBridge(start:, end:) -> {
      let #(board, outcome) = game.add_bridge(host.game, start, end)
      #(
        Host(..host, game: board),
        immediately(harness.add_bridge_encode(outcome)),
      )
    }
    harness.ShareOutcome(text) -> #(host, Working(post(host.origin, text)))
  }
}
```

Three things about that shape are worth saying out loud.

*The state goes through.* The board is an argument and a result, not something
in a mutable box on the side. Running a program is a function of the board, which
is why a test can play a whole game and check what came out.

*Most effects are immediate.* Five of these six are answers about a puzzle
sitting in memory. `immediately` wraps a value the program resumes with at once,
so a program that reads the board and builds ten bridges runs to the end without
ever leaving the page.

*One is not.* `ShareOutcome` has to talk to a server, and the program is
suspended while that happens. The runtime hands you the continuation and takes it
back when the answer arrives; nothing about the program is written differently
because of it.

## Three: write the workspace

You could stop there. A model given six effects and their types can write
`perform AddBridge({start: ..., end: ...})` all day.

It should not have to. Applications have a way of being talked about — in this
one, islands and neighbours and how many bridges an island still needs — and
that vocabulary is worth writing down once, in the language, rather than
reconstructed from raw effects in every conversation.

A *context* is a module with a `readme`, which is what the model is told, and
the functions the readme describes:

```eyg
// The six effects, wrapped so they read like the game.
let islands = (_) -> { perform ListIslands({}) }
let connect = (start, end) -> { perform AddBridge({start, end}) }

// And the things you actually want.
let with_target = (target) -> {
  filter(islands({}), (island) -> { !equal(island.target, target) })
}
let twos = (_) -> { with_target(2) }

let readme = "# Hashiwokakero
...
A `2` with only one neighbour has to spend both of its ends on that neighbour.
Look for those first.
"

{readme, skills, islands, connect, twos, with_target, ...}
```

Two properties of this file matter more than what is in it.

It *references nothing*. No `import`, no package reference, only builtins. So
reading it needs no network — which is the only way a page whose harness has no
`Fetch` can have a library at all. It is part of the page, handed in at startup:

```html
<script type="module">
  import { main } from "/src/hashi.gleam";
  import context from "/eyg/context.eyg?raw";
  main(context);
</script>
```

And it is *the same library for both sides*. The shell binds it and so does
the agent, because it is one value in one scope:

```gleam
pub fn load(source: String) -> Result(Context, String) {
  use tree <- result.try(parser.all_from_string(source))
  use value <- result.try(expression.execute(ir.map_annotation(tree, ...), []))
  use fields <- result.try(as_record(value))
  Ok(Context(readme: ..., scope: dict.to_list(fields), types: types(tree)))
}
```

`types` is worth the extra ten lines. The module is a record, so inferring it
once gives a row of every name in it with its type. Split that row back into a
list and it is a scope the type checker can work in — which is how the shell can
say a program is wrong before it runs, and why its autocomplete shows
`connect: ({x: Integer, y: Integer}) -> ...` rather than just a name.

## Four: run a program

Running is the same whoever wrote the program.

```gleam
pub fn run(ctx: Context(host), source) -> #(Context(host), Call) {
  let Environment(scope:, ..) = ctx.environment
  expression.execute(source, scope)
  |> loop(ctx)
}
```

`loop` is the interesting part, and it is short:

```gleam
fn loop(return, ctx) {
  case return {
    Ok(value) -> #(ctx, Successful(value))
    Error(#(break.UnhandledEffect(label, lift), _, env, k)) -> {
      let #(host, handling) = ctx.environment.handler(ctx.environment.host, label, lift)
      case handling {
        Stopped(reason) -> #(ctx, Aborted(reason))
        Unknown(reason) -> #(ctx, Exception(reason))
        // finished already: carry straight on
        Working(system.Done(value)) -> loop(expression.resume(value, env, k), ctx)
        // not finished: hold the continuation and hand the work out
        Working(effect) -> #(remember(ctx, effect), Handling(id, env, k))
      }
    }
    Error(#(reason, _, _, _)) -> #(ctx, Exception(reason))
  }
}
```

A program that performs an effect the runtime does not know about does not
crash: it stops with `UnhandledEffect` and the label, and the application decides
what that means. In this game it means the program tried to reach outside the
game, and that is what gets reported.

> A bug worth repeating so you do not write it: an effect that finishes
> immediately must resume the continuation, not return its value. Returning it
> makes that value the answer of the whole program and quietly throws away
> everything after it. It is invisible until a program performs an effect
> somewhere other than its last line.

## Five: two ways in, one workspace

The application ends up with a shell and an agent. It would be easy to give them
a runtime each, and wrong: a bridge built by one has to be there when the other
looks.

So there is one environment, one board, one module cache and one run of task
numbers. Both sides take that workspace, run in it, and put back what it became:

```gleam
fn run(state: State) {
  let ctx = agent.workspace(state.agent)
  let #(ctx, call) = tools.run(ctx, buffer.source(state.shell.buffer))
  settle(state, ctx, [#(shell_task, call)])
}
```

That is two tests, and they are the two that hold the design up:

```gleam
pub fn the_shell_sees_what_the_agent_did_test() {
  let state = model_says(started(), "Joining those two.", [
    #("a", "connect({x: 0, y: 0}, {x: 2, y: 0})"),
  ])
  let state = shell_runs(state, "picture({})")
  assert shell.Returned("2-2\n...\n2.2\n") == last_outcome(state)
}
```

## Six: tell the model where it is

The system prompt is built, not written. Half of it is true of any agent; the
rest is the environment describing itself — its briefing, then its effects with
their types:

```gleam
pub fn system_prompt(environment: Environment(host)) -> String {
  "You are an expert automation assistant.
...
"
  <> environment.briefing
  <> "

This environment has the following effects

"
  <> string.join(
    list.map(environment.effects, fn(effect) {
      let #(name, #(lift, lower)) = effect
      "- " <> name <> "(" <> t_debug.mono(lift) <> ") -> " <> t_debug.mono(lower)
    }),
    "\n",
  )
}
```

Nothing in that function knows what the effects are. Point it at a browser and
it describes a browser; point it at this game and it describes six effects and a
hashiwokakero board. The briefing is the context module's readme, so the thing
the model is told and the library it is given cannot drift apart — they are the
same file.

## What you end up with

A page where nothing is clickable and everything is programmable. A person
writes a program in the shell; a model writes the same program from a sentence
of English; the board is the same board; and neither of them can reach anything
the harness did not name.

The whole of what a program can do is a list you can read in twenty seconds, and
you wrote it.

## Testing it

Test at the boundary, with real programs:

```gleam
pub fn a_bridge_cannot_cross_another_test() {
  let ctx = workspace(crossroads())
  let #(ctx, value) = answer(ctx, "connect({x: 1, y: 0}, {x: 1, y: 2})")
  assert v.ok(v.unit()) == value
  let #(_, value) = answer(ctx, "connect({x: 0, y: 1}, {x: 2, y: 1})")
  assert v.error(v.Tagged("BadEnd", v.unit())) == value
}
```

That test parses EYG, type checks it, runs it, performs the effects against a
real board and reads the answer back. It is not a mock of anything. The agent
gets tested the same way, with the completions written out instead of asked for:
everything downstream of what the model said is the real thing, which is where
the bugs are.

## The pieces

```sh
gleam add eyg_analysis eyg_interpreter eyg_parser touch_grass
```

- `eyg_parser` — text to tree
- `eyg_analysis` — inference, and the context a program is checked in
- `eyg_interpreter` — evaluation, and the continuation when a program pauses
- `touch_grass` — the `Interface` type, and effect definitions worth reusing
- `morph` — the structural editor, if you want a shell as well as an agent
- `overlay_web` — the agent: conversation, tool calls, provider setup

See also [Embedding EYG in Gleam programs](/guides/embedding-eyg-in-gleam-programs)
for the smaller version of this: a configuration file and a couple of effects,
with no browser anywhere near it.
