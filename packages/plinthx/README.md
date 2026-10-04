# Plinthx

Local host bindings for the Gleam terminal experiments. Node, Bun and ECMAScript
bindings live here; OpenTUI bindings live in `gleam_opentui`, and browser
bindings belong in Plinth; application state, effect handling, rendering policy and
scheduling belong in the consuming Gleam packages.

Follow the [Plinth README at ba246f2](https://github.com/CrowdHailer/plinth/blob/ba246f26ff05ef933a5e1664def8d59ffbde317d/README.md),
the upstream HEAD checked on 2026-10-04:

- Place bindings by the API's defining specification: Web APIs in
  `plinth/browser`, ECMAScript in `plinthx/javascript`, Node APIs in
  `plinthx/node`, Bun APIs in `plinthx/bun`.
- Fetch a global with `get()` (or `get_name()` for multiple globals), through
  `globalThis`, checking its native type. Return `Result(object, Nil)` when
  lookup cannot throw, or `Result(object, String)` when it can.
- Return the native object and pass the receiver first to methods. Preserve
  native mutation and lifetime semantics.
- Return `Result` for fallible calls and missing optional values. Construct
  errors with `Result$Error`; convert thrown values with `String(error)`.
- Avoid legacy named/indexed window lookup and higher-level abstractions.

Bindings deliberately expose only the APIs exercised by these experiments.
They do not change the existing bindings inside third-party dependencies.
