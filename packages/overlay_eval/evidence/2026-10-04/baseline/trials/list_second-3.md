# list_second, trial 3

Extract a list item without assuming pattern matching on lists.

Failed, score 0%.

## Checks

- **fail** computes "b": no program computed "b", the last value computed was {}

## Turn 1

User: Use builtins to return the second item of ["a", "b", "c"]. Run the program.

Agent: (thinking) We need to write an EYG program that returns second item of list ["a","b","c"]. Need to use builtins. We should first read guide on builtins.

Agent: (thinking) We need to write an EYG program that uses builtins to return the second item of ["a","b","c"]. Likely need to access list by index. No builtin for index, but we can use list_pop repeatedly or fold. Simpler: pop first then pop next.

We have list_pop that returns Ok({head, tail}) or Error. So we can do:

let lst = ["a","b","c"]
let ok1 = !list_pop(lst)
let {head: _, tail: rest1} = match ok1 with Ok(v) -> v | Error(_) -> !abort...
Then pop again: let ok2 = !list_pop(rest1)
let {head: second, tail: _} = match ok2 ...

Return second. Need to output via Print? The user wants "Use builtins to return the second item". In EYG, the program's value is the final expression? Probably need to Print it? The spec not fully clear, but likely we can just perform Print.

Let's write script.

Check syntax: EYG uses let and pattern matching? Not sure. Use let and pattern matching via case? No info. Simpler: we can use builtins and let to get value, then perform Print.

Maybe we can just use !list_pop twice and get second.

We'll produce code:

let lst = ["a","b","c"]
let res1 = !list_pop(lst)
let {head: _, tail: rest1} = match res1 {
  Ok(v) -> v
  Error(_) -> !abort("empty")
}
let res2 = !list_pop(rest1)
let {head: second, tail: _} = match res2 {
  Ok(v) -> v
  Error(_) -> !abort("empty")
}
perform Print(second)

But need Abort builtin? Use Abort effect. Use perform Abort.

In EYG, pattern matching syntax unknown. Possibly use builtins to extract? Maybe easier: use !list_fold to get element at index 1.

list_fold(lst, {index:0, result:""}, (item, acc) -> {
   let index = acc.index
   if !equal(index, 1) then acc else {index: !int_add(index,1), result:item}
})

But lacking condition builtin. Not sure.

Probably pattern matching works.

Let's assume pattern matching using case syntax.

We'll just attempt.

Agent: Ran:
```eyg

let lst = ["a", "b", "c"]
let res1 = !list_pop(lst)
let {head: _, tail: rest1} = match res1 {
  Ok(v) -> v
  Error(_) -> !never(perform Abort("empty list"))
}
let res2 = !list_pop(rest1)
let {head: second, tail: _} = match res2 {
  Ok(v) -> v
  Error(_) -> !never(perform Abort("empty list"))
}
perform Print(second)

```
Result: invalid code
```
error: expected `->` followed by `{` in function definition at position 106
hint: functions are written as `(arg) -> { body }`

 5 |   Ok(v) -> v
                ^
```

Agent: (thinking) The EYG syntax expects pattern matching with maybe syntax. Need to recall EYG syntax. We need to write correct code.

We need to return the second item using builtins. Simpler: use !list_pop twice.

EYG code structure: let <pattern> = expression; or let v = expr; pattern matching perhaps with match expression: match expr { Ok(v) -> ...; Error(_) -> ... }

But we need correct syntax. The error says "expected -> followed by {" meaning bodies must be block { ... }. So pattern branches need block bodies. Like:

match res1 {
  Ok(v) -> {
    v
  }
  Error(_) -> {
    !never(perform Abort("empty list"))
  }
}

Thus need to wrap bodies in {}.

Let's write program:

let lst = ["a", "b", "c"]
let res1 = !list_pop(lst)
let {head: _, tail: rest1} = match res1 {
  Ok(v) -> { v }
  Error(_) -> { !never(perform Abort("empty list")) }
}
let res2 = !list_pop(rest1)
let {head: second, tail: _} = match res2 {
  Ok(v) -> { v }
  Error(_) -> { !never(perform Abort("empty list")) }
}
perform Print(second)

Check syntax for let pattern: let {head: _, tail: rest1} = ... maybe okay.

Let's run.

Agent: Ran:
```eyg
let lst = ["a", "b", "c"]
let res1 = !list_pop(lst)
let {head: _, tail: rest1} = match res1 {
  Ok(v) -> { v }
  Error(_) -> { !never(perform Abort("empty list")) }
}
let res2 = !list_pop(rest1)
let {head: second, tail: _} = match res2 {
  Ok(v) -> { v }
  Error(_) -> { !never(perform Abort("empty list")) }
}
perform Print(second)

```
Result: computed
```
{}
```
Printed:
```
b
```

Agent: The second item of the list `["a", "b", "c"]` is **b**.

## Effects

- GET https://eyg.run/packages/pull? 200 (loading modules)
- GET https://eyg.run/packages/pull?since=14 200 (loading modules)
- GET https://eyg.run/guides/builtins-reference.md 200

The agent finished.
