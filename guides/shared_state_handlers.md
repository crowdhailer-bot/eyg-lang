---
name: Shared state handlers
description: One state protocol for several named operations.
---

# Shared state

Several independently installed handlers do not automatically share changing
state. A useful representation is one `State` operation with tagged commands:

```eyg
handle State((command, resume, state) -> {
  match command {
    Get(_) -> { resume(state)(state) }
    Set(next) -> { resume(next)(next) }
  }
}, (_) -> {
  let _ = perform State(Set(42))
  let value = perform State(Get({}))
  let finish = (state) -> { {state, value} }
  finish
})(0)
```

Commands must share one compatible reply type. If `Get` and `Set` have different
reply types, use a tagged reply protocol, or make every command return the new
state. The complete [`shared_state_handlers.eyg`](./examples/shared_state_handlers.eyg)
uses a common integer reply for `Get`, `Increment`, and `Decrement`.

Run `eyg eval guides/examples/shared_state_handlers.eyg` from the repository root.
It returns `{state: 1, value: [0, 2, 1]}` in the
[checked recording](../packages/tracing/recordings/ordered-effects.mp4).

Named operations can translate into that protocol. Their native continuations
stay in their adapters: the `State` handler already receives its own continuation,
which returns to the adapter under the reinstated `State` delimiter.

## Why one deferred counter works but the naive shared counter fails

The original failure combines two distinct issues:

1. Deep resumption reinstalls the original handler, so another handler placed
   around `resume` does not replace its captured state.
2. A returned closure does not retain ambient handlers. Invoking it outside
   their scope can leave its operations unhandled.

[`stateful_original.eyg`](./examples/stateful_original.eyg) and
[`escaping_handler.eyg`](./examples/escaping_handler.eyg) are regression inputs
for these failures. Use [state-passing answers](./stateful_effect_handlers.md)
instead of assuming closures capture handlers.

## Returning functions from state

The testing API needs heterogeneous native replies, so it returns a **tagged
expectation function**, not a tagged native reply. The matching adapter extracts
the function and calls it under `mask State`. This removes the private state
handler from the callback's context and avoids a recursive effect signature.

The production runner additionally masks the enclosing computer mocks, allowing
assertions to use surrounding effects without consuming subject expectations.
See [masking](./masking_effects.md) and [ordered tests](./ordered_effect_tests.md).
