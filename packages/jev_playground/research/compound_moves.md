# Compound moves

Can Jev reach a program in fewer choices if some choices make several edits at once?

## Method

`gleam run -m jev_playground/mine --runtime bun` splits every `.eyg` file in `eyg_packages` into its top level definitions
and finds, by synthesis, the actions that build each one from `?`.
Each definition is typed in the scope of its file, so a call knows how many arguments the function takes.
Names and literals are removed from the actions so that `variable user, select .name` and `variable http, select .operation` count as the same move.
The most frequent adjacent pair is merged into one symbol and counted again, ten times, as byte pair encoding builds its vocabulary.

## Results

434 of 436 definitions were built, 12,042 choices in all, 13.2% of them navigation.
The two failures overwrote several record fields, which synthesis now supports.

| Compound | Uses | Definitions | Choices saved |
| --- | --- | --- | --- |
| `variable, select` | 773 | 148 | 773 |
| `call, variable` | 601 | 192 | 601 |
| `variable, select, call` | 509 | 93 | 1,018 |
| `variable, move to next ?` | 386 | 120 | 386 |
| `insert before, insert before` | 204 | 52 | 204 |
| `variable, select, call, insert before` | 257 | 76 | 771 |
| `variable, call` | 231 | 107 | 231 |
| `tag, call` | 214 | 80 | 214 |
| `builtin, call, variable` | 201 | 96 | 402 |
| `variable, call, variable` | 193 | 66 | 386 |

Together they would save 4,986 choices, 41.4%, if every instance were offered.

The compounds are about calling and selecting from values: EYG code is mostly `module.function(argument)`.
`variable, move to next ?` exists because a variable of unknown type stays selected in case it is called or selected from,
and `insert before` follows a call when the type of the function does not give its arity.

The first run built each definition out of the scope of its file.
Free variables then had unknown types, so the most common compound was `variable, move previous`: moving back to select from a variable the editor had moved on from.
Typing the scope removed 897 choices and that artifact, and the editor now only moves on from a value whose type is known and complete.

## Offering compounds to Jev

`compound.mined()` holds the ten compounds, `options.Config(compounds:)` offers them.
The slots of a compound are filled from context:
the six most recent variables in scope, the fields of the chosen variable's type,
builtins the task or program mentions and tags from the task, at most five instances of each compound.
An instance is offered when its first step is, the rest are checked when applied and a failure is shown to Jev as a failed edit.

The HTTP library demo takes 654 choices with single edits and 549 with compounds, 104 of them compound, 16% fewer.
The saving is well below the 41% possible because only the offered instances can be chosen:
a compound for the variable defined seven definitions ago, or the ninth field of a record, is not offered.
Offering more instances saves more choices but makes every choice larger, the trade off measured with the real API in [evals](./evals.md).

## Recordings

`/demo/http` and `/demo/http-compound` replay the two scripts with mocked answers,
`gleam run -m jev_playground/record -- video "/demo/http-compound?speed=3" recordings/http-library-compound.mp4` records them.
