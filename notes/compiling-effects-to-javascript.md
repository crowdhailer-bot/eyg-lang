---
name: Compiling effects to JavaScript
description: Trade-offs made in the evidence passing and generator backends of gleam_compiler.
date: 2026-09-15
---

The evidence and the yield are fields of one object shared by the runtime,
as in the C backend of Koka. JavaScript is single threaded, so passing the
evidence vector as an argument would only cost a parameter on every call.

No static evidence index. A canonical vector with an index known at compile
time needs a closed row at the perform and the vector at runtime to match it.
EYG rows at perform sites inside let bound functions are open, inference has
no `open` coercions to rebuild vectors, and a non-scoped resumption can run
under more handlers than its type mentions. Lookup is by label on an object,
engines cache the property access at each perform.

A call is only checked if the callee's row is not empty. Variables are
annotated with an opened type, so a call through a variable to a pure let
bound function is still checked. Checks are cheap but add join points.

The analysis annotates a lambda with a row closed after the fact, calls inside
its body can still carry the unclosed row. The generator backend decides a
function is a generator from its body, not its annotation.

Generators can not be copied, a resumption used a second time replays the
handled computation with the replies it received before. Replay is sound only
because EYG code is pure apart from effects.

Monadic state handlers, `(s) -> { resume(x)(s) }`, grow the JavaScript stack
with every operation in both backends.
