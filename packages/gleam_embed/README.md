# eyg_embed

Everything a host needs to give people and agents an [EYG](https://eyg.run) shell.

- `eyg/embed/run` run a program to its end, answering effects with a handler and references with a resolver.
- `eyg/embed/shell` check each piece of code against the host's effects before it runs, and keep its variables and their types.
- `eyg/embed/agent` an agent whose only tool runs code, over `overlay_llm`.
- `eyg/embed/json` values and effect types as plain JSON, for hosts in other languages.
- `eyg/embed/browser` `fetch` and `hash` for JavaScript hosts, in the shape `eyg_hub` takes them.

```gleam
let assert Ok(shell) =
  shell.new([#("Add", #(t.Integer, t.Integer))])
  |> shell.with_module("lib", library_source)

let shell.Run(shell:, state:, outcome:) =
  shell.run(shell, "lib.double(3)", 0, fn(total, label, lift) {
    let assert #("Add", v.Integer(n)) = #(label, lift)
    Ok(#(total + n, v.Integer(total + n)))
  })
```

Packages from a hub are loaded with `eyg_hub`'s `cache.load` and given to the shell with `shell.with_references`.
The examples in `examples/` are built on this package, see the guides that go with them.

Until their fixes are released, `eyg_ir`, `eyg_analysis` and `overlay_llm` are path dependencies,
so this package cannot be published yet.
