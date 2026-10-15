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
