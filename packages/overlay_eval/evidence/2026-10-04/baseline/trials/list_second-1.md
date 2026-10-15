# list_second, trial 1

Extract a list item without assuming pattern matching on lists.

Passed, score 100%.

## Checks

- **pass** computes "b": run 1 computed the value

## Turn 1

User: Use builtins to return the second item of ["a", "b", "c"]. Run the program.

Agent: (thinking) We need to write an EYG script that uses builtins to return the second item of the list ["a","b","c"]. Need to read guide on builtins. Use guide tool.

Agent: (thinking) We need to write a program that returns the second item of ["a","b","c"] using builtins. Likely we can use list_pop repeatedly. Starting list ["a","b","c"]; pop gives head "a" tail ["b","c"]; then pop tail to get "b". Return "b". The program should output? How to return? In EYG, top-level expression result is returned? Probably just evaluate to something. Use let and then maybe Print? But user wants to "Use builtins to return the second item... Run the program." So we should write a script that computes that and maybe print it via Print effect. But the instruction says "use builtins to return". Probably just evaluate to the value, not print. In earlier tasks they used Print. But let's just compute and perform Print. Let's create script:

let {head: first, tail: rest} = !list_pop(["a","b","c"])
let {head: second, tail: _} = !list_pop(rest)
perform Print(second)

Wrap in appropriate syntax. Need to read syntax guide. Let's open guide for syntax.

Agent: (thinking) Goal: Use builtins to return second item of ["a","b","c"]. Need a program that evaluates to "b". Use list indexing? There's no builtin for index directly. Could use !list_pop and fold? Could get tail then head. Approach: Use !list_pop to get head and tail, then pop again on tail.

Pseudo:

let xs = ["a","b","c"]
let {head: _, tail: rest1} = !list_pop(xs) // remove first
let {head: second, tail: _} = !list_pop(rest1)
second

Need to handle Ok/Error. !list_pop returns Ok({head,tail}) | Error. Use match.

let xs = ["a","b","c"]
match !list_pop(xs) {
  Ok({head: _, tail: rest1}) -> {
    match !list_pop(rest1) {
      Ok({head: second, tail: _}) -> { second }
      Error(_) -> { "" } // fallback
    }
  }
  Error(_) -> { "" }
}

Will return second item.

Now need to run program with run effect. Use perform? Actually just need to run program; output is the program's final expression result (should be string). Use run tool with code.

Let's construct EYG code.

Agent: Ran:
```eyg
let xs = ["a", "b", "c"]
match !list_pop(xs) {
  Ok({head: _, tail: rest1}) -> {
    match !list_pop(rest1) {
      Ok({head: second, tail: _}) -> { second }
      Error(_) -> { "" }
    }
  }
  Error(_) -> { "" }
}

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
