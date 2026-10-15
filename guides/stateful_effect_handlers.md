---
name: Stateful effect handlers
description: Thread state explicitly through deep effect resumptions.
---

# Stateful effect handlers

A handler's answer can be a function of state. The operation callback returns
a function that resumes the computation and passes its next state:

```eyg
let run = handle Increment((_, resume) -> {
  (count) -> { resume({})(!int_add(count, 1)) }
}, (_) -> {
  let _ = perform Increment({})
  let finish = (count) -> { count }
  finish
})
run(0)
```

This returns 1. Keep the continuation call in tail position to reuse continuation
storage. [increment_counter.eyg](./examples/increment_counter.eyg) extracts this
pattern as a reusable function; [stateful_handler.eyg](./examples/stateful_handler.eyg)
uses it three times.

Deferred answers must only pass state: returned closures capture variables,
not ambient handlers. [stateful_eager_counter.eyg](./examples/stateful_eager_counter.eyg)
runs the subject's effects before returning its state function.
Independent counters can return nested answers, as
[composed_stateful_handlers.eyg](./examples/composed_stateful_handlers.eyg) shows;
the initial-state application order follows the nesting order.
Use [one shared command protocol](./shared_state_handlers.md) when several
operations must change the same state.

The two self-contained workload fixtures measure one counter and interleaved
counters. Their fold input comes from the host so workload recursion cannot
distort the handler measurement. The interpreter and compiled JavaScript tests
check the returned states and maximum continuation/capture sizes.

[stateful_original.eyg](./examples/stateful_original.eyg) preserves the original
invalid composition for diagnosis: its type requires a recursive answer and its
evaluation eventually performs Increment outside a handler. The intended net
count there is 1. [Deep handler scope](./deep_effect_handlers.md) explains why.

The [checked recording](../packages/tracing/recordings/deep-handlers.mp4) runs the
three-operation counter alongside the deep-handler scope examples.
