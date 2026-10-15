# list_second, trial 2

Extract a list item without assuming pattern matching on lists.

Passed, score 100%.

## Checks

- **pass** computes "b": run 2 computed the value

## Turn 1

User: Use builtins to return the second item of ["a", "b", "c"]. Run the program.

Agent: (thinking) We need to write EYG code that uses builtins to return second item of list ["a","b","c"], i.e., "b". Need to read builtins guide. Use tool functions.guide name "builtins".

Agent: (thinking) We need to return the second item of ["a","b","c"] using builtins. We should write EYG code that returns "b". Use list builtin? There's !list_pop but that's for head. Could use !list_fold? Simpler: we can index? Not sure about indexing builtin; maybe we can use pattern matching? List literals are supported. Could extract second by pattern: let [_, second, .._] = list? EYG language likely supports list deconstruction using pattern? Not sure. Safer to use !list_fold to iterate and pick the second element.

We can fold with accumulator being a pair (count, maybe result). But easier: use !list_pop repeatedly: pop first to get tail then pop head of tail.

We can do let {head: _, tail: tail1} = !list_pop(["a","b","c"]). Then let {head: second, tail: _} = !list_pop(tail1). Return second.

Let's write code.

Need to ensure syntax correct. Use let binding.

final expression should be second.

Write:

let {head: _, tail: tail1} = !list_pop(["a","b","c"])
let {head: second, tail: _} = !list_pop(tail1)
second

Return that.

Let's run.

Agent: Ran:
```eyg
let {head: _, tail: tail1} = !list_pop(["a","b","c"]);
let {head: second, tail: _} = !list_pop(tail1);
second
```
Result: invalid code
```
error: invalid character ';' at position 53
hint: remove or replace this character — EYG does not use it

 1 | let {head: _, tail: tail1} = !list_pop(["a","b","c"]);
                                                          ^
```

Agent: (thinking) We need to read syntax guide.

Agent: (thinking) We need to return the second item of ["a","b","c"] using builtins. Use list_pop to get head and tail. List_pop returns Ok({head, tail}) or Error. So we need to handle Ok. Use match.

Program: let {head:_, tail:rest} = match !list_pop(["a","b","c"]) { Ok(v) -> { v } Error(_) -> { [] } }? Actually need to get tail. Simpler: let {head:_, tail:rest} = match !list_pop(["a","b","c"]) { Ok(r) -> { r } Error(_) -> { {head: "", tail: []} } } then second = match !list_pop(rest) { Ok(r2) -> { r2.head } Error(_) -> { "" } } second.

Return expression second.

Let's write.

Agent: Ran:
```eyg
let result1 = match !list_pop(["a","b","c"]) {
  Ok(v) -> { v }
  Error(_) -> { {head: "", tail: []} }
}
let {head: _, tail: rest} = result1
let result2 = match !list_pop(rest) {
  Ok(v) -> { v }
  Error(_) -> { {head: "", tail: []} }
}
let {head: second, tail: _} = result2
second
```
Result: computed
```
"b"
```

Agent: The second item of `["a", "b", "c"]` is **"b"**.

## Effects

- GET https://eyg.run/packages/pull? 200 (loading modules)
- GET https://eyg.run/packages/pull?since=14 200 (loading modules)
- GET https://eyg.run/guides/builtins-reference.md 200
- GET https://eyg.run/guides/eyg-syntax-guide.md 200

The agent finished.
