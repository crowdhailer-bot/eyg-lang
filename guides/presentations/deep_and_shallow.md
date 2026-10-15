---
name: Handler design in EYG
description: A short presentation outline, with shallow handlers last.
---

# Handler design in EYG

1. **Deep scope.** Resuming restores the matching delimiter; callbacks execute
   outside it. A closure captures variables, not its creation-time handlers.
2. **State passing.** Return `State -> Result` and apply the next state after
   resumption. Use one protocol when several operations share state.
3. **Masking.** `mask E(body)` skips one enclosing `E` handler. It separates
   internal effect signatures from user callbacks, while allowing other effects.
4. **Purity.** `!pure(f)` requires and guards one effect-free application.
   The runtime boundary matters even when checking is disabled.
5. **Testing.** An ordered list contains assertion functions. A private queue
   returns the next function; masks bypass the queue and enclosing mocks while
   the assertion runs. Its native result goes straight to the native resumption.
6. **Shallow scope.** Raw continuations omit the matching delimiter. Separate
   normal-return and operation callbacks allow independent body and answer types.
   The caller owns reinstallation and completion when stepping explicitly.

For examples and executable specifications, follow the
[handler reading path](../handlers.md). The guides are the source of truth;
this outline intentionally does not duplicate their implementations.
