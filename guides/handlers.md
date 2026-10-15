---
name: Learning effect handlers in EYG
description: Read deep handlers, state, masking, purity, and testing.
---

# Effect handlers: a reading path

1. [Deep handlers](./deep_effect_handlers.md): resumption, scope, and answer types.
2. [State passing](./stateful_effect_handlers.md) and
   [shared state](./shared_state_handlers.md): changing state with fixed handlers.
3. [Masking and purity](./masking_effects.md): separate internal handlers from
   callback effects, with matching checked and unchecked semantics.
4. [Writing tests](./writing_tests_with_aok.md) and
   [ordered expectations](./ordered_effect_tests.md): callbacks return native replies.

The [syntax guide](./syntax.md#effects) is the reference for the surface forms.
`examples/stateful_original.eyg` and `examples/escaping_handler.eyg` are intentional
failure regressions, not suggested implementations.
