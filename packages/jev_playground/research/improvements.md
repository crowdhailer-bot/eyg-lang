# Improvements

What helps Jev reach a correct program in fewer choices, tested against the real API where possible.
The variants are listed at `eval.variant` and compared with `sweep`, see [evals](./evals.md) for the method.
This is the index of every technique in the harness: each row is a thing that can be turned off, with what
turning it off cost. Rows that say "not swept" were never measured on their own, which is the honest state
of them, and the first candidates for a sweep.

The scaffold numbers are 18 runs, six evals three times each. The DNSimple numbers are 60 runs, twenty
questions three times each, from an empty program.

## Tested

| Change | Evidence |
| --- | --- |
| Hole mode, `holes`: code moves the selection to the next hole and Jev only chooses what fills it | 14 and 16 of 18 scaffold runs solved in two sweeps, 11 of 18 editing the whole program, and only hole mode solves `fibonacci-scaffold` and `total-scaffold`. |
| Scaffolds: the structure is given with `todo` holes | Every scaffold eval is solved by some variant, no eval is solved from an empty program. |
| Names, labels and literals asked for in their own questions | Needed for a long task, which offered more than the 255 options a choice accepts. Turned off, 13 of 18 solved against 15, with 93% more tokens, see [ablations](#ablations). |
| Type filter: only values whose type fits the hole | Turned off, 14 of 18 solved against 15, with 55% more tokens. |
| Stop repeats: a state seen before, one kind of edit five times in a row, moving back to repeat an edit | Turned off, 13 of 18 solved against 15, one of the failures a network timeout, with 53% more tokens. |
| Choosing the selected variable again keeps it and moves on | `describe-scaffold` 4 steps to 3, `user-record-scaffold` 5 to 4. Without the option Jev overwrote the variable, as it had used choosing it again to mean keep it. |
| Records offered with the labels of `{a: x, b: y}` in the task | `user-record-scaffold` went from failing to 4 steps. |
| A hole in a match branch described by its tag | With the next two, `fibonacci-scaffold` went from never solved to solved in 21 steps. |
| The types in scope resolved with what inference learnt later | Every parameter had been type `a`. Fixed in `eyg_analysis.scope_at`. |
| A call keeps the arity its type had when offered | `call go(?, ?, ?, ?)` had become `go(?)` because the intermediate program was ill typed. |
| Calls take at most eight arguments | A jump and call loop doubled the arguments each time until a request passed 32,800 tokens. |
| Evaluation stops after a million steps | A program that never finished grew until the kernel killed the eval, which `gleam run` reported as success. |
| Compounds, `compounds` | Solved `list-functions-scaffold` before the excerpt highlight, which solves it without them, and broke `fibonacci-scaffold` and `total-scaffold`, see [compounds](./evals.md#compounds). |
| Compound instances applied before they are offered, `checked` | Fewer tokens and steps, the same evals solved, twice the wall time, see [checked compounds](./evals.md#checked-compounds). |
| The selected code repeated in the selection's description, `mark=excerpt` | The best variant: 17 of 18 scaffold runs solved in hole mode for 29% fewer tokens, against 14 of 18, and 17 against 16 when repeated. Now the default, see [type information](./type_information.md). |
| The type of every hole listed, `types` | No change in hole mode, one more of 18 solved editing the whole program. |
| No jumps to type errors, `nojumps` | No change, see [cursors and jumps](./cursors_and_jumps.md). |
| Several holes per request, `cursors=2` or `3` | Worse: 10 of 18 against 16 of 18, with 74 to 100% more tokens, see [cursors and jumps](./cursors_and_jumps.md). |
| Moving to any hole by its number, `holejumps` | Worse: 12 of 18 against 16 of 18, the moves were seldom chosen and their options shifted other choices. |
| A context in scope with its functions offered as calls, `ctx=calls` and above | From an empty program, 16 of 60 DNSimple questions solved without context compounds, 59 with calls, 60 with the readme examples as well, see [contexts](./contexts.md#compounds-from-the-context). |
| The readme of the context in the state | 60 of 60 against 55, with a third fewer tokens, before the readme examples were offered as compounds. |
| Effects shown only on the context calls that perform them, `effects=callsonly` | As many questions solved as any other way of showing effects, for 40% fewer tokens than listing signatures. |
| Selecting an argument of a complete program, and moving on from a wrap or a function argument | Four questions went from 0 of 15 blind runs each to 15 of 15, see [contexts](./contexts.md#what-blind-runs-found). |
| Stop a run after three choices in a row below 0.2 confidence | Over 544 runs 1 of 357 solved runs and 65 of 187 unsolved runs did this, stopping there would have saved 18% of all input tokens. |
| Compound moves built from the readme's examples, `ctx=examples` | The default: 60 of 60 DNSimple questions for $0.062, against 59 for $0.066 with calls alone. `total-records` went from nine edits to two, and from never solved to solved, when an example showed the shape. |
| The functions of an open library offered as calls, wraps and values | Not swept. `a-records` went from out of steps to solved in 18 edits in the run that added it, because `wrap in @standard.list.map(.., f)` was offered at all. |
| A library the program references counted as open | Not swept. Without it the examples brought `@standard` into the program but its functions were never offered, which is the same failure as above. |
| Releases written `@standard` rather than `@standard:1:baguq…` where they are read | Not swept. The program Jev read was mostly content id before it, 60 characters at every use. |
| Asking whether the finished program answers the task, `answered` | Measured and rejected: it finished at the whole account record for "what email address" and at every record for "which mail servers", and solved no more, 13 of 20 either way. Off by default. |
| Selecting only the literal arguments of a complete program | Not swept on its own. Offering every argument sent runs into a loop selecting a lambda and undoing, which is what narrowed it to strings and integers. |
| Blind runs, `blind`: Jev is shown what a program returned, never whether it is right | Not a comparison, it is the protocol the overlay uses. It is what the DNSimple numbers are measured under, and it is why a wrong answer is final. |
| Offering to open a library, `search_libraries` | Not swept. Needed for a task whose library is not open at the start, and on by default only where a context is in scope. |
| Moving to the next `?` after a hole is filled, `advance` | Not swept. Added because Jev kept replacing the hole it had just filled. |

## Ablations

The improvements made before the real API was used were each turned off in hole mode,
three runs of each of the six scaffolds (`sweep -- ablations repeat=3`):

| Eval | holes | names in the edit question, `flat` | no type filter, `untyped` | no repeat filters, `repeats` |
| --- | --- | --- | --- | --- |
| fibonacci-scaffold | 3/3, 21 | 2/3, 38 | 2/3, 32 | 3/3, 32 |
| list-functions-scaffold | 0/3 | 1/3, 27 | 0/3 | 0/3 |
| greeting-scaffold | 3/3, 3 | 3/3, 3 | 3/3, 3 | 3/3, 3 |
| user-record-scaffold | 3/3, 4 | 3/3, 4 | 3/3, 4 | 3/3, 4 |
| total-scaffold | 3/3, 8 | 1/3, 9 | 3/3, 33 | 2/3, 8 |
| describe-scaffold | 3/3, 3 | 3/3, 3 | 3/3, 3 | 2/3, 3 |
| solved | 15 of 18 | 13 of 18 | 14 of 18 | 13 of 18 |
| input tokens | 1,469,000 | 2,841,000 | 2,273,000 | 2,249,000 |
| seconds | 103 | 172 | 159 | 450 |

Plain hole mode solved 14, 16 and 15 of 18 in three sweeps, so one run either way is noise.
Each improvement is worth a run or two of 18 and a lot of cost:
names in the edit question nearly double the tokens, without the type filter `total-scaffold` took 33 steps rather than 8,
and without the repeat filters one run of `total-scaffold` ran out of steps. The failed `describe-scaffold` run was a request that timed out, not Jev.

## Suggested

- **Plan outside Jev.** The largest effect measured is the scaffold. A planner, a person or a language model,
  writes the structure with `todo` holes and Jev fills them. Worth an eval where a model writes the scaffold from the task.
- **Ask for a label after the edit.** The label question is answered alongside the edit, without knowing which fields are used,
  and chose `quantity` for both sides of `total-scaffold`'s multiplication.
  Offering only the fields not yet used in the enclosing expression, or asking in a second request, would avoid it.
- **Compounds per task.** Instantiate compounds from the API of the libraries the task opens, `list.fold(?, ?, ?)` for each function of `list`,
  rather than one mined list for every task.
- **Incremental checking.** Checking compound instances doubled the wall time as each is analysed from scratch.
- **Hand back when unsure.** Evals now stop after three choices in a row below 0.2 confidence.
  The playground should do the same and ask the person, or a planner, for more structure.
