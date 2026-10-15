# list_second, trial 2

Extract a list item without assuming pattern matching on lists.

Failed, score 0%.

## Checks

- **fail** computes "b": no program computed "b", no program computed a value

## Turn 1

User: Use builtins to return the second item of ["a", "b", "c"]. Run the program.

Agent: (thinking) We need to write EYG code that returns second item of list ["a","b","c"]. Builtins: list indexing? Not given. Could use list_pop etc. But we can pattern match: list has head and tail. To get second element, we can pop first then pop to get head. Steps:

let xs = ["a","b","c"]
let first_pop = !list_pop(xs) -> yields Ok({head, tail}) or Error. Then get tail, then pop again.

So EYG:

let xs = ["a","b","c"]
let first = match !list_pop(xs) { Ok(pair) -> { pair } Error(_) -> { abort } } ???

But we can directly: let {head: _, tail} = match !list_pop(xs) { Ok({head, tail}) -> { {head, tail} } Error(_) -> { abort } }. Actually we need to extract tail.

Simplify: let res1 = !list_pop(xs)
match res1 { Ok({head, tail}) -> { let res2 = !list_pop(tail) match res2 { Ok({head, tail}) -> { head } Error(_) -> { perform Abort("error") } } } Error(_) -> { perform Abort("error") } }

We need to use perform Abort.

Let's write code.

Agent: Error: Internal Server Error (ref: cdaa16e0-99dc-49da-be69-9d46a13b596b)

## Effects

- GET https://eyg.run/packages/pull? 200 (loading modules)
- GET https://eyg.run/packages/pull?since=14 200 (loading modules)

The agent finished.
