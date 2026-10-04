---
title: Embedding EYG in an Elixir program
date: 2026-10-03
---

# Embedding EYG in an Elixir program

This post puts an EYG script box on the home page of a Phoenix application.
Scripts typed into it manage a supervisor of counters, and they can do nothing else.
Every program that parses is type checked as you type, enter runs it.

<video src="../../examples/phoenix_counters/video/phoenix-counters.mp4" controls width="100%"></video>

The code is in [`examples/phoenix_counters`](../../examples/phoenix_counters).
It follows the design of the Erlang example, described in [Embedding EYG in an Erlang program](../embedding-eyg-in-erlang/index.md).

## Building EYG for Elixir

The EYG parser, type checker, interpreter and hub client are Gleam packages in this repository.
They are not published for Erlang, so Mix cannot fetch them.
Instead a small Gleam project lists them, in its own directory because Gleam would also compile the Elixir files in `test`.

```toml
# gleam/gleam.toml
name = "phoenix_counters_eyg"
target = "erlang"

[dependencies]
eyg_analysis = { path = "../../../packages/gleam_analysis" }
eyg_hub = { path = "../../../packages/gleam_hub" }
eyg_interpreter = { path = "../../../packages/gleam_interpreter" }
eyg_ir = { path = "../../../packages/gleam_ir" }
eyg_parser = { path = "../../../packages/gleam_parser" }
gleam_crypto = ">= 1.6.0 and < 2.0.0"
gleam_httpc = ">= 5.0.0 and < 6.0.0"
```

A compiler defined in `mix.exs` builds it and copies the modules into the application, before the Elixir compiler runs.

```elixir
compilers: [:gleam_libraries, :phoenix_live_view] ++ Mix.compilers()
```

From Elixir a Gleam module is an Erlang module, `eyg/hub/cache` is `:eyg@hub@cache`.

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
@type_ :eyg@analysis@type_@isomorphic
@unit {:record, :empty}

def types do
  reply = @type_.result(@unit, :string)

  [
    {"StartCounter", {:string, reply}},
    {"SetTickRate", {@type_.record([{"name", :string}, {"seconds", :integer}]), reply}},
    {"GetValue", {:string, @type_.result(:integer, :string)}},
    {"Shutdown", {:string, reply}}
  ]
end
```

Pattern matching on the label and lifted value makes the implementation one clause per effect.

```elixir
def handle("StartCounter", {:string, name}), do: reply(name, Counters.start_counter(name))

def handle("SetTickRate", {:record, %{"name" => {:string, name}, "seconds" => {:integer, seconds}}}),
  do: reply(name, Counters.set_tick_rate(name, seconds))

defp reply(_name, :ok), do: {:tagged, "Ok", {:record, %{}}}
defp reply(_name, {:ok, value}), do: {:tagged, "Ok", {:integer, value}}
defp reply(name, {:error, reason}), do: {:tagged, "Error", {:string, message(name, reason)}}
```

## Checking and running

`PhoenixCounters.Counters.Eyg` has `check/2` and `run/2`.
Both take the source and a package cache and return `{result, cache}`.
Each parses the script, loads the packages it refers to, and type checks it against exactly the counter effects.

```elixir
context = @infer.with_effects(@infer.pure(), Effects.types())
analysis = @cache.infer_sync(@infer.check(context, tree), cache)
```

`run` only executes a script that checks, so a mistake on its last line stops the effects on its first.
While it runs, references are answered from the cache and effects go to `Effects.handle/2`.

```elixir
case @cache.static_loop(step, cache, &@expression.resume/3) do
  {:error, {{:unhandled_effect, label, lift}, _span, env, k}} ->
    reply = Effects.handle(label, lift)
    run_step(@expression.resume(reply, env, k), source, cache)
  ...
end
```

## Packages are loaded by reference

Scripts can use any package on the hub, nothing is preloaded.
`PhoenixCounters.Counters.Packages` lists the references in a parsed script and loads only those, with their dependencies, using `eyg_hub`'s cache.
It supplies HTTP and hashing and drives the cache's actions until none are left, then checks every downloaded module.
A script with no references, or whose packages are cached, makes no requests.

## A process owns the cache

`PhoenixCounters.Scripts` is a `GenServer` in the supervision tree.
Every check and run goes through it, and it keeps the cache that comes back, even when the result is an error.

```elixir
def handle_call({:run, source}, _from, cache) do
  {result, cache} = Eyg.run(source, cache)
  {:reply, result, cache}
end
```

The first script that uses `@standard` fetches it, later ones do not.
The LiveView only ever receives results, the cache stays in the process that owns it.

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
    :ok -> Scripts.check(source)
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

Scripts run in the `PhoenixCounters.Scripts` process, one at a time.
Type checking guarantees which effects a script performs, it does not limit how long a script runs, so a recursive script can loop until that process is killed.

## Try it

```sh
git clone https://github.com/crowdhailer/eyg-lang
cd eyg-lang/examples/phoenix_counters
(cd assets && bun install)
mix setup
mix phx.server
```
