# list_second, trial 3

Extract a list item without assuming pattern matching on lists.

Passed, score 100%.

## Checks

- **pass** computes "b": run 1 computed the value

## Turn 1

User: Use builtins to return the second item of ["a", "b", "c"]. Run the program.

Agent: (thinking) The user asks: "Use builtins to return the second item of ["a", "b", "c"]. Run the program."

We need to write an EYG program that returns the second item. Need to read builtins guide. Let's fetch guide "builtins".

Agent: (thinking) We need to return the second item of ["a","b","c"] using builtins. Probably list indexing not provided; use list_pop? Could pop first then head is "a", tail is ["b","c"]; then pop again to get "b". Use let binding. Need to output final expression which is the string "b". Write program using builtins. Syntax? Need to read syntax guide.

Agent: (thinking) The user wants to "Use builtins to return the second item of ["a", "b", "c"]. Run the program."

We need to write an EYG program that uses builtins to get the second item. Likely use list indexing? There's no builtin for indexing directly. Could use !list_pop repeatedly? Or pattern matching? Could use !list_pop to get head and tail, then pop again.

Steps: let list = ["a","b","c"]; then let {head: first, tail: rest} = !list_pop(list) // returns Ok or Error? Actually !list_pop returns Ok({head, tail}) | Error({}). So need to match. Use match.

let pop1 = match !list_pop(list) { Ok(pair) -> { pair } Error(_) -> { abort... } } but we can directly destructure: let {head: _, tail} = match !list_pop(list) { Ok(v) -> { v } Error(_) -> { !never(perform Abort("empty")) } }.

Then pop second: let {head: second, tail: _} = match !list_pop(tail) { Ok(v) -> { v } Error(_) -> { ... } }.

Return second.

Implement using builtins and match.

We must run with run tool.

Write program:

let lst = ["a","b","c"]
let {head: _, tail} = match !list_pop(lst) {
  Ok(v) -> { v }
  Error(_) -> { !never(perform Abort("empty")) }
}
let {head: second, tail: _} = match !list_pop(tail) {
  Ok(v) -> { v }
  Error(_) -> { !never(perform Abort("empty")) }
}
second

We need to import Abort effect? Abort is built-in effect, can perform Abort. Use !never.

That should produce a string "b". Run.

Agent: Ran:
```eyg
let lst = ["a","b","c"]
let {head: _, tail} = match !list_pop(lst) {
  Ok(v) -> { v }
  Error(_) -> { !never(perform Abort("empty")) }
}
let {head: second, tail: _} = match !list_pop(tail) {
  Ok(v) -> { v }
  Error(_) -> { !never(perform Abort("empty")) }
}
second
```
Result: computed
```
"b"
```

Agent: The second item of the list `["a", "b", "c"]` is **"b"**.

## Effects

- GET https://eyg.run/packages/pull? 200 (loading modules)
- GET https://eyg.run/packages/pull?since=14 200 (loading modules)
- GET https://eyg.run/guides/builtins-reference.md 200
- GET https://eyg.run/guides/eyg-syntax-guide.md 200

The agent finished.
