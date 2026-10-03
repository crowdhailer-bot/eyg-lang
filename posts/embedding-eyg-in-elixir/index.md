---
title: Embedding EYG in an Elixir program
date: 2026-10-03
---

# Embedding EYG in an Elixir program

This post puts an EYG script box on the home page of a Phoenix application.
Scripts typed into it manage a supervisor of counters, and they can do nothing else.
Every program that parses is type checked as you type, enter runs it.

<video src="demo.mp4" controls width="100%"></video>

The code is in [`examples/phoenix_counters`](../../examples/phoenix_counters).
The same application in Erlang is described in [Embedding EYG in an Erlang program](../embedding-eyg-in-erlang/index.md).

## Depending on EYG

The EYG parser, type checker and interpreter are written in Gleam.
[`eyg_beam`](../../packages/eyg_beam) wraps them for Erlang and Elixir hosts, and its Makefile bundles them, with their Gleam dependencies, into one OTP application.
Mix builds a path dependency with a Makefile using `make`, so the dependency is one line.

```elixir
# mix.exs
{:eyg_beam, path: "../../packages/eyg_beam"}
```

Building it needs `gleam` on the path.
From Elixir, `eyg_beam` is an Erlang module.

```elixir
iex> :eyg_beam.check("perform Add(1)", [{"Add", {:integer, :integer}}], %{})
{:ok, "Integer"}
```

## Counters

The counters are ordinary Elixir.
A `Registry` names them and a `DynamicSupervisor` starts them.

```elixir
def start_counter(name) do
  case DynamicSupervisor.start_child(@supervisor, {Counter, name: name, via: via(name)}) do
    {:ok, _pid} -> :ok
    {:error, {:already_started, _pid}} -> {:error, :already_started}
  end
end
```

`set_tick_rate/2`, `get_value/1` and `shutdown/1` look up the counter by name and return `{:error, :not_found}` if there is none.

## Effects

An effect is a label, the type of the value a script lifts to the host and the type of the reply.
EYG types and values are plain terms, `:string` is a type and `{:string, "apples"}` is a value.

```elixir
@unit {:record, :empty}

def effects do
  reply = :eyg_beam.result_type(@unit, :string)

  [
    {"StartCounter", {:string, reply}},
    {"SetTickRate", {:eyg_beam.record_type([{"name", :string}, {"seconds", :integer}]), reply}},
    {"GetValue", {:string, :eyg_beam.result_type(:integer, :string)}},
    {"Shutdown", {:string, reply}}
  ]
end
```

Pattern matching on the label and lifted value makes the implementation one clause per effect.

```elixir
def handle("StartCounter", {:string, name}), do: reply(name, Counters.start_counter(name))

def handle("SetTickRate", {:record, %{"name" => {:string, name}, "seconds" => {:integer, seconds}}}),
  do: reply(name, Counters.set_tick_rate(name, seconds))

def handle("GetValue", {:string, name}), do: reply(name, Counters.get_value(name))
def handle("Shutdown", {:string, name}), do: reply(name, Counters.shutdown(name))

defp reply(_name, :ok), do: {:tagged, "Ok", {:record, %{}}}
defp reply(_name, {:ok, value}), do: {:tagged, "Ok", {:integer, value}}
defp reply(name, {:error, reason}), do: {:tagged, "Error", {:string, message(name, reason)}}
```

## Checking and running

`PhoenixCounters.Counters.Eyg` passes the effects to `eyg_beam`.
`@standard` is loaded once when the application starts.

```elixir
def check(source), do: :eyg_beam.check(source, Effects.effects(), packages())

def run(source) do
  case :eyg_beam.run(source, Effects.effects(), packages(), &Effects.handle/2) do
    {:ok, value} -> {:ok, :eyg_beam.inspect(value)}
    {:error, message} -> {:error, message}
  end
end
```

`run` type checks before it runs anything.
A script with a mistake in its last line does not perform the effects in its first.

## The script box

The LiveView handles two events from one form.
`phx-change` checks the script, `phx-submit` runs it.

```elixir
def handle_event("check", %{"source" => source}, socket) do
  {:noreply, assign(socket, check: check(source))}
end

# Only programs that parse are type checked, an unfinished program has no errors yet.
defp check(source) do
  case Eyg.parse(source) do
    :ok -> Eyg.check(source)
    {:error, _} -> nil
  end
end
```

Skipping programs that do not parse keeps the page quiet while you type.
Once the brackets close, a type error is shown under the box straight away.

```
error: type mismatch given: Integer expected: String
hint: check the expression matches the expected type

 1 | perform StartCounter(1)
     ^^^^^^^^^^^^^^^^^^^^^^^
```

A successful run is added to a list under the box and the box is cleared with `push_event`.
The table of counters re-renders every half second, so the values tick while you watch.

## Highlighting

The EYG VS Code extension has a TextMate grammar, and [shiki](https://shiki.style) highlights code with TextMate grammars in the browser.
The grammar is imported straight from the extension in this repository, so the box always matches the editor.

```js
import {createHighlighterCore} from "shiki/core"
import {createJavaScriptRegexEngine} from "shiki/engine/javascript"
import githubDark from "shiki/themes/github-dark.mjs"
import grammar from "../../../../packages/vscode-eyg/syntaxes/eyg.tmLanguage.json"

const highlighter = createHighlighterCore({
  langs: [grammar],
  themes: [githubDark],
  engine: createJavaScriptRegexEngine(),
})
```

The script box is a hook on a textarea with transparent text over a `<pre>` of highlighted tokens.
The JavaScript regex engine avoids loading WebAssembly, so esbuild bundles it like any other package.
The hook also turns enter into a submit, shift and enter still adds a new line.

```js
this.input.addEventListener("keydown", event => {
  if (event.key === "Enter" && !event.shiftKey) {
    event.preventDefault()
    this.input.form.requestSubmit()
  }
})
```

The container has `phx-update="ignore"`, LiveView never patches the textarea while someone is typing in it.

## Scripts in the video

A single effect.

```eyg
perform StartCounter("apples")
```

Several effects, using the result of the last.

```eyg
let _ = perform StartCounter("pears")
let _ = perform SetTickRate({name: "pears", seconds: 1})
perform GetValue("pears")
```

The standard library performing effects for every name in a list.

```eyg
let names = ["plums", "figs", "limes", "kiwis"]
@standard.list.map(names, (name) -> {
  let _ = perform StartCounter(name)
  perform SetTickRate({name: name, seconds: 2})
})
```

## What the host still trusts

Scripts run in the LiveView process.
Type checking guarantees which effects a script performs, it does not limit how long a script runs, so a recursive script can loop until the LiveView is killed.

## Try it

```sh
git clone https://github.com/crowdhailer/eyg-lang
cd eyg-lang/examples/phoenix_counters
(cd assets && bun install)
mix setup
mix phx.server
```
