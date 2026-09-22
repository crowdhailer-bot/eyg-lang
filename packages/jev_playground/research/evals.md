# Evals

How quickly and cheaply does Jev reach a correct program through the real API, and which ways of offering choices help?

## Method

An eval, in `eval.gleam`, is a task, a starting program and a checker that calls the program with inputs and compares what it returns.
The starting program is empty or a scaffold whose holes are written `todo`.
Jev is asked for one edit at a time until the checker accepts the program or the step budget runs out.
The checker runs when Jev runs the tests, says it has finished or the program is complete, and its verdict is shown to Jev as test results.

```sh
TYPESAFE_API_KEY=... gleam run -m jev_playground/evaluate --runtime bun -- fibonacci-scaffold holes
TYPESAFE_API_KEY=... gleam run -m jev_playground/sweep --runtime bun -- compounds [eval ...]
```

A variant is a set of flags, listed at `eval.variant`, that changes how choices are offered.
`sweep` runs each eval with each variant of a set and writes a table to `recordings/evals`.
Every step of every run is saved there too, `/eval/<file>` replays one at the speed Jev answered and `record` turns the replay into a video.
Cost is $0.042 per million input tokens, output is free.

Jev mostly answers the same request the same way: two runs of `list-functions-scaffold` made the same 11 choices, with confidences a hundredth apart.
Close calls do flip. The fibonacci scaffold took 21 steps in one run and 32 in another with the same code.
The compound sweeps below ran each eval and variant once, the later sweeps three times with `repeat=3`.
Differences of a few steps are noise, solved or not is the result that matters.
Since the later sweeps a run stops after three choices in a row below 0.2 confidence, which 1 of 357 solved runs made.

## Evals

| Eval | Start | Needs |
| --- | --- | --- |
| `fibonacci` | empty | a recursive function with `!fix`, a match and four argument calls, 40 or so edits |
| `list-functions` | a library with `length` | two definitions added above the export and the export extended |
| `greeting` | empty | destructure `{string}`, a function and a call with a string literal |
| `fibonacci-scaffold` | the structure of `fibonacci` | three holes: the recursive call, `acc` and the first call |
| `list-functions-scaffold` | `sum` and `last` defined as holes | `list.fold(items, 0, !int_add)` and `list.head(list.reverse(items))` |
| `greeting-scaffold` | `greet = (name) -> { todo }` | one call with a string literal |
| `user-record-scaffold` | `user = (name, age) -> { todo }` | a record of two fields |
| `total-scaffold` | a fold with the reducer's body missing | nested builtin calls selecting two fields |
| `describe-scaffold` | a match with both branch bodies missing | a variable and a string |
| `dnsimple-*` | empty, with the DNSimple context in scope | one to nine edits, twenty questions about an account |

Tasks name everything the program needs in backticks, as Jev can only choose from what is offered.

## From nothing

No variant solved `fibonacci`, `list-functions` or `greeting` from an empty program.
Every one of 28 runs of the first two ran out of steps, whichever of the 14 variants in the [experiments](#other-variants) was used.
Jev is good at the next local edit and poor at holding a plan:
it builds the first definition, then wraps, deletes and undoes rather than moving on to the next part of the task.

With a context in scope, a module whose functions are shaped like the questions asked of it, an empty program is enough:
twenty questions about a DNSimple account are all answered from `?`, see [contexts](./contexts.md).

## From a scaffold

With the structure given, Jev fills holes well. In hole mode, where code moves the selection to the next hole and Jev only chooses what fills it:

| Eval | Steps | Cost | Seconds |
| --- | --- | --- | --- |
| `greeting-scaffold` | 3 | $0.0005 | 1.0 |
| `describe-scaffold` | 3 | $0.0003 | 0.9 |
| `user-record-scaffold` | 4 | $0.0003 | 1.2 |
| `total-scaffold` | 8 | $0.0016 | 2.7 |
| `fibonacci-scaffold` | 21 | $0.0043 | 8.1 |
| `list-functions-scaffold` | 11, with compounds | $0.0028 | 3.5 |

Structure should come from the person or a planner, and Jev should fill it.
`gleam run -m jev_playground/record -- video "/eval/<file>" recordings/eval-fibonacci-scaffold-solved.mp4` records a run being filled at the speed Jev answered.

## Compounds

The [compound moves](./compound_moves.md) were mined from `eyg_packages`, where the ten most common would save 41% of choices.
The `compounds` sweep offers none, the five most common or all ten, with 2, 5 or 10 instances of each:

| Eval | holes | 5 compounds | 10 | 10, 2 instances | 10, 10 instances | whole program | whole program, 10 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| fibonacci-scaffold | 32 | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| list-functions-scaffold | ✗ | 29 | 11 | ✗ | 40 | ✗ | 10 |
| greeting | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| greeting-scaffold | 3 | 3 | 4 | 3 | 3 | 4 | 4 |
| user-record-scaffold | 4 | 5 | 4 | 4 | 4 | 4 | 4 |
| total-scaffold | 8 | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| describe-scaffold | 3 | 4 | 4 | 2 | 4 | 3 | 4 |
| solved | 5 of 7 | 4 | 4 | 3 | 4 | 3 | 4 |
| input tokens per request | 4,900 | 5,000 | 5,600 | 5,400 | 6,300 | 4,800 | 5,700 |
| cost of the sweep | $0.039 | $0.050 | $0.052 | $0.066 | $0.067 | $0.059 | $0.053 |

Cells are the steps to a solution, ✗ ran out of steps.

- In this sweep compounds are what solve `list-functions-scaffold`, whose bodies are `module.function(argument)`, the shape the compounds were mined from.
  With all ten it takes 11 steps. The later sweeps solved it without compounds, when the selected code is repeated in the selection's description,
  so the compounds help Jev see that `list` is to be selected from, which that description also does.
- Compounds break `fibonacci-scaffold` and `total-scaffold`, which are solved without them.
  An instance is offered when its first step is, so `variable item, call selection(..)` is offered for a record,
  and Jev chooses it over and over. The `checked` variant removes such instances, both evals still fail, see [below](#checked-compounds).
- Each request grows by the compounds' options: 14% more input tokens with ten compounds of five instances, 29% with ten instances.
- Fewer instances is not cheaper: two instances of each missed the one Jev needed, and the run spent its budget.

Offering compounds is worth it when the task is made of the shapes they were mined from, and only if the instances offered are correct.
The next step is to choose compounds per task, from the library API the task opens, rather than one list for every task.

## Checked compounds

`checked` applies every compound instance before offering it and drops those that fail part way or add a type error.

| Eval | 10 compounds, holes | checked | whole program | checked |
| --- | --- | --- | --- | --- |
| fibonacci-scaffold | ✗ | ✗ | ✗ | ✗ |
| list-functions-scaffold | 11 | 7 | 10 | 9 |
| greeting | ✗ | ✗ | ✗ | ✗ |
| greeting-scaffold | 4 | 4 | 4 | 3 |
| user-record-scaffold | 4 | 4 | 4 | 4 |
| total-scaffold | ✗ | ✗ | ✗ | ✗ |
| describe-scaffold | 4 | 3 | 4 | 3 |
| input tokens | 1,251,000 | 1,101,000 | 1,218,000 | 1,142,000 |
| seconds | 79 | 161 | 77 | 190 |

Checking removes the instances that call a record, and every solved eval took as many or fewer steps, with 6 to 12% fewer tokens.
It did not rescue `fibonacci-scaffold` or `total-scaffold`.
In `total-scaffold` the problem was the label question rather than the compounds:
it chose `quantity` for both sides of the multiplication, as that question is asked alongside the edit and does not know which field is used.
Applying every instance doubled the wall time, analysis is the cost, so checking should be incremental or cached before it is on by default.

## Other variants

The `experiments` sweep ran the six scaffolds three times with 14 variants, 252 runs.
The best was hole mode with the selected code repeated in the selection's description, `holes mark=excerpt`:
17 of 18 runs solved for $0.063, against 14 of 18 for $0.089 in plain hole mode and at most 12 of 18 editing the whole program.
A second sweep of just those two confirmed it, 17 of 18, the one failure a request that timed out, against 16 of 18 with 34% fewer tokens.
It is now the default.
The details are in [type information](./type_information.md), [cursors and jumps](./cursors_and_jumps.md) and [improvements](./improvements.md).

## Found by running evals

Running against the real API found problems the mocked demos could not:

- The types of variables in scope were never resolved with what inference learnt after the scope was taken,
  so every parameter showed as type `a` and the type filter could not work. Fixed in `eyg_analysis`, see [improvements](./improvements.md).
- A hole in a match branch was described as "the body of the function taking (_)", now it says which tag it is returned for.
- `call go(?, ?, ?, ?)` inserted `go` first, which made the program ill typed, so the call that followed took one argument.
- Jumping to a type error and wrapping the code in a call, again and again, doubled the arguments each time until a request was refused
  for having more than 32,800 input tokens.
- A type error inside a desugared pattern has no node in the editor, focusing it crashed.
- A complete program whose recursion never ended grew until the kernel killed the eval, evaluation now stops after a million steps.

## Conclusions

- Jev fills holes well and does not plan. Give it a scaffold, from a person or a planner, and ask it only what fills each hole.
- The state matters more than the options: resolved types, a role for each hole and the selected code repeated
  took `fibonacci-scaffold` from never to usually solved and `list-functions-scaffold` from never to always.
- Every option costs tokens on every request. Compounds, several cursors and moves to any hole each added options,
  and each solved fewer evals, unless the options were exactly the shapes the task needed.
- A scaffold eval costs a tenth of a cent. Most of the cost is in failed runs, which three unsure choices in a row predict.
