# Type information

How should type information be used to guide Jev's choices?

## What Jev is shown

Every request's state has:

- `program`, the whole program with the selection marked `«like this»`.
- `selection`, what is selected: its code, its type when known, and its role, for example
  "argument 2 of 4 to go, which has type (Integer, a, b, c) -> d" or "the value returned when the match is `Gt`".
- `type_errors`, each described in words, "expected Integer but found String".
- `libraries`, the functions of each opened library with their types.
- the options, each with a description that includes the type of a variable or builtin.

Types are shown without effect rows and with letters for type variables, `(Integer, a) -> List(a)`.
Raw types, with numbered variables and open effect rows, were long and did not help.

Types are used before Jev sees anything:

- The type filter only offers a value whose type fits the selected hole, or whose result fits when it is called.
  Records fit through their fields, as they are selected from, and unions fit anything, as they are matched on.
- A call is offered with the number of arguments its type takes, `call go(?, ?, ?, ?)`, capped at eight.
- After filling a hole with a value whose type is known and complete, the selection moves to the next hole.
  A value of unknown type stays selected, as it might be called or selected from.

## Resolving the types in scope

The types of variables in scope come from `infer.scope_at`, which returned the scope as it was when inference reached the node.
A parameter's type is often only learnt later, `count` in `(go, count) -> { match !int_compare(count, 0) {..} }` is an integer
because of the match that is inferred after the branches.
Every parameter in the fibonacci scaffold was shown as type `a`, `go` could not be called with four arguments, and the type filter let anything through.
`scope_at` now resolves each type with what inference learnt, and `fibonacci-scaffold` went from never solved to solved in 21 steps,
together with the next two fixes.

## Types of holes

`types` adds a `holes` list to the state, the type each hole must have in reading order, `["1 (selected): Integer", "2: List(a)"]`.

The `experiments` sweep ran the six scaffold evals three times with each variant, 252 runs
(`sweep -- experiments repeat=3`).
Cells are how many of three runs were solved and the median steps of those that were.

| Eval | holes | holes, types | whole program | whole program, types |
| --- | --- | --- | --- | --- |
| fibonacci-scaffold | 2/3, 32 | 2/3, 32 | 0/3 | 0/3 |
| list-functions-scaffold | 0/3 | 0/3 | 2/3, 24 | 3/3, 19 |
| greeting-scaffold | 3/3, 3 | 3/3, 3 | 3/3, 4 | 3/3, 4 |
| user-record-scaffold | 3/3, 4 | 3/3, 4 | 3/3, 4 | 3/3, 4 |
| total-scaffold | 3/3, 8 | 3/3, 8 | 0/3 | 0/3 |
| describe-scaffold | 3/3, 3 | 3/3, 3 | 3/3, 3 | 3/3, 3 |
| solved | 14 of 18 | 14 of 18 | 11 of 18 | 12 of 18 |
| input tokens | 2,126,000 | 2,175,000 | 2,842,000 | 2,426,000 |

Listing the holes' types made no difference in hole mode, where the selection description already gives the selected hole's type
and the other holes are filled later.
In whole program mode it solved one more run with 15% fewer tokens, as the selection is often not a hole there.
The type information that mattered was already in the state: once the types in scope were resolved,
the selected hole's role and type and the type of each offered variable were enough.

## Effects

Every node's effect row is known after inference, `contextual.Analysis` keeps the type and the effect of each node.
None of the evals perform effects, as their checkers call the program without handlers, so showing effects was not measured.
The state already lists the effects the environment can handle with their types, used by the github demo.
A `performs` list, like `holes`, would name each node whose effect row is not empty with the effects it may perform,
so that Jev can see where a `Log` or `Fetch` still needs handling.
It needs an `effect_at` next to `type_at` in `contextual`, and an eval whose checker handles effects.

## Highlighting the selection

`mark=` changes how the selection is shown in `program`:

| Variant | Program | Selection description |
| --- | --- | --- |
| `mark=guillemets`, the default when measured | `!int_add(«?», ?)` | kind, role and type |
| `mark=comments` | `!int_add(/* selection */ ? /* end */, ?)` | kind, role and type |
| `mark=unmarked` | `!int_add(?, ?)` | code, kind, role and type |
| `mark=excerpt`, now the default | `!int_add(«?», ?)` | code, kind, role and type |

The first four columns are hole mode, the last four whole program mode.

| Eval | «» | comments | unmarked | excerpt | «» | comments | unmarked | excerpt |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| fibonacci-scaffold | 2/3, 32 | 3/3, 23 | 3/3, 21 | 3/3, 31 | 0/3 | 0/3 | 0/3 | 0/3 |
| list-functions-scaffold | 0/3 | 0/3 | 0/3 | 3/3, 37 | 2/3, 24 | 1/3, 46 | 2/3, 19 | 3/3, 19 |
| greeting-scaffold | 3/3, 3 | 3/3, 3 | 3/3, 3 | 3/3, 3 | 3/3, 4 | 3/3, 4 | 3/3, 4 | 3/3, 4 |
| user-record-scaffold | 3/3, 4 | 3/3, 4 | 3/3, 6 | 3/3, 4 | 3/3, 4 | 3/3, 4 | 3/3, 4 | 3/3, 4 |
| total-scaffold | 3/3, 8 | 0/3 | 0/3 | 2/3, 8 | 0/3 | 0/3 | 0/3 | 0/3 |
| describe-scaffold | 3/3, 3 | 3/3, 3 | 3/3, 3 | 3/3, 3 | 3/3, 3 | 3/3, 3 | 3/3, 3 | 3/3, 3 |
| solved | 14 of 18 | 12 | 12 | 17 | 11 | 10 | 11 | 12 |
| input tokens | 2,126,000 | 2,562,000 | 2,490,000 | 1,506,000 | 2,842,000 | 3,304,000 | 2,760,000 | 2,470,000 |

Repeating the selected code in the description, `excerpt`, was the best variant of the sweep:
17 of 18 solved in hole mode for 1.5 million tokens, 29% fewer than the marks alone, and the only hole mode variant to solve `list-functions-scaffold`.
In hole mode the selection is usually a hole, the code is repeated when it is not, as after `variable list` when `.fold` must be selected from it.
Comments instead of «» cost more and lost `total-scaffold`, as did leaving the program unmarked.
Jev reads the marks, with only the description to say where the selection is it did no better.

A second sweep of hole mode with and without the excerpt (`sweep -- highlight repeat=3`)
solved 17 of 18 against 16 of 18, the one failure a request that timed out, with 34% fewer tokens,
and `list-functions-scaffold` 3 of 3 against 1 of 3. The excerpt is now the default, `mark=guillemets` gives the marks alone.

## Findings

- Resolving the types in scope mattered more than any way of showing them,
  it was part of the difference between `fibonacci-scaffold` never and usually solved.
- Keep the selection marked «» in the program and repeat the selected code in its description.
- A list of every hole's type adds nothing in hole mode and helps a little when the whole program is edited.
- Effects were not measured, the design above is ready for an eval that performs them.
