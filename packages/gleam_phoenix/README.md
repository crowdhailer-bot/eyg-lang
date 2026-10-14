# Phoenix LiveView bindings

Native bindings for the pinned Phoenix 1.8.15, LiveView 1.2.12 and Phoenix HTML
4.3.0 clients. Gleam supplies hook lifecycle and event callbacks; the FFI only
marshals native hook objects and calls the client library.

`hook(mounted)` receives the native hook and returns a cleanup function invoked
when it is destroyed. `element` and `handle_event` expose the existing LiveView
hook API. `new_socket`, `connect` and `disconnect` own the native client.

```sh
bun install
gleam build --warnings-as-errors
```

The [Phoenix example](../../examples/phoenix_counters/) runs these bindings in a
real browser. Its Gleam walkthrough checks keyboard submission, clearing and
highlighting as well as the server's typed EYG effects.
