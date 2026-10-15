---
name: Embedding EYG in Gleam programs
description: Run scripts against explicit host handlers and module resolvers.
---

# Embedding EYG in Gleam programs

The JavaScript package `eyg_embed` provides one host loop for expressions,
blocks and asynchronous effects. In this checkout its source is
[packages/gleam_embed](../packages/gleam_embed/). Use a local Gleam dependency:

```toml
eyg_embed = { path = "../gleam_embed" }
```

The path is relative to the consuming package. The [BEAM embedding SDK](./embedding_erlang.md)
serves Erlang and Elixir hosts.

## Host loop

`run.expression(source, scope, state, handler, resolver)` returns the final host
state and either an EYG value or a failure. The handler receives its state, an
effect label and the lifted request; it returns updated state and the reply.
A refusal stops execution. Interpreter errors also stop, without host dispatch.

```gleam
import eyg/embed/run
import eyg/interpreter/value as v
import eyg/parser

pub fn example() {
  let assert Ok(source) = parser.all_from_string(
    "let _ = perform Log(\"Hello, host\") !int_add(40, 2)",
  )
  let handle = fn(messages, label, lift) {
    case label, lift {
      "Log", v.String(message) -> Ok(#([message, ..messages], v.unit()))
      _, _ -> Error("unsupported host operation")
    }
  }
  run.expression(source, [], [], handle, run.no_references)
}
```

The result is `#(["Hello, host"], Ok(v.Integer(42)))`.
The [executable example](../packages/gleam_embed/dev/host_loop.gleam) checks it:

```sh
cd packages/gleam_embed
gleam run --runtime node -m host_loop
gleam test --runtime node
```

`run.block` also returns final variables and an optional value: a trailing
`let` defines a binding without returning a value. The `expression_async` and
`block_async` variants await each host reply before continuing.

## Types and references

The raw loop does not type check. Check user code before exposing effects;
host handlers must validate requests and supply replies of the declared type.
Use `infer.with_effects` with `infer.check_with_references` when all module
types are available, and reject any `infer.all_errors` before running.

`infer.with_variable(context, name, type_)` and `with_variables` supply
host binding types; put their runtime values in the interpreter scope too.
Generic types instantiate at each use. New bindings shadow older ones;
the first occurrence in a supplied list takes precedence.

The resolver receives an IR reference and supplies its evaluated module value.
The host owns this cache and its lifetime; the loop does not fetch modules or
retain a global cache. Mutable package names need an explicit freshness policy.
Use pinned references for reproducible scripts. The embedding guides for
[Erlang](./embedding_erlang.md), [Elixir](./embedding_elixir.md),
[Ash](./embedding_ash.md) and [Pi](./embedding_pi.md) show concrete cache owners.

## Retained shell

Use `shell.new(effects)` and `shell.run(session, code, state, handler)` for
user-written code. Each run parses and checks the whole block before executing;
successful runs retain bindings and their generic types. A trailing `let` has no
returned value. `run_async` awaits a host handler that returns a promise.

`with_value` supplies a trusted value and its type. `with_module` evaluates a
pure library, whose exported functions may later perform the host's effects.
`with_references` supplies module values and types together.

Parse or type failures keep both the old shell and host state. A runtime stop
keeps the old bindings, while host effects already performed remain visible.
The host owns those mutations and any transaction policy.

From packages/gleam_embed, run `gleam run --runtime node -m host_shell`.
The [example](../packages/gleam_embed/dev/host_shell.gleam) retains an integer and
generic identity function, returns 6, rejects an unavailable operation before
changing the counter, then successfully uses the retained function on a string.
The [checked recording](../packages/tracing/recordings/embedding-shell.mp4)
executes it. Recreate it from packages/tracing with
`gleam run -m tracing/embedding_shell_demo`.

The [JSON boundary](./embedding_json.md) exchanges plain data and describes
closed effect signatures for hosts outside Gleam.
