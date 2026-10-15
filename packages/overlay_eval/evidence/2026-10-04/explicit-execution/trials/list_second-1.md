# list_second, trial 1

Extract a list item without assuming pattern matching on lists.

Passed, score 100%.

## Checks

- **pass** computes "b": run 10 computed the value

## Turn 1

User: Use builtins to return the second item of ["a", "b", "c"]. Run the program.

Agent: (thinking) The user wants to use builtins to return the second item of ["a","b","c"].

We need to read builtins guide. Let's fetch guide.

Agent: (thinking) The user: "Use builtins to return the second item of ["a", "b", "c"]. Run the program."

We need to write an EYG program using builtins to return the second element of list ["a","b","c"]. Need to run via run tool. Return final expression as the result. Use builtins: maybe list_pop? To get second item we could pop first then pop next. Or use list_fold? Simpler: Use list indexing? Not provided. Use list_pop to get head and tail; then pop again.

Program:

let {head: first, tail: rest1} = !list_pop(["a","b","c"])
let {head: second, tail: _} = !list_pop(rest1)
second

But need to handle Ok/Error: list_pop returns Ok({head, tail}) | Error({}). In this case list is non-empty, so we can assume Ok. In EYG we can pattern match? Maybe using let-binding with pattern? Not sure of syntax. The language likely has pattern matching via let with record destructuring? Not described. Simpler: Use !list_fold to get element at index? Might be complicated.

Maybe EYG lets you just call !list_pop and then get .head property? Possibly returns a record.

Assume we can write:

let result1 = !list_pop(["a","b","c"])
let {head: _, tail: rest1} = result1 // destructuring? not sure.

Better: Use !list_pop and then access fields: result1.head? but record fields accessed via .? Possibly syntax like result1.head. Not provided.

Simplify: Use builtins list_pop twice by using pattern matching with let with record shape:

let {head: _, tail: rest1} = !list_pop(["a","b","c"])
let {head: second, tail: _} = !list_pop(rest1)
second

Assume works.

We'll run program.

Agent: Ran:
```eyg
let {head: _, tail: rest1} = !list_pop(["a", "b", "c"]);
let {head: second, tail: _} = !list_pop(rest1);
second
```
Result: invalid code
```
error: invalid character ';' at position 55
hint: remove or replace this character — EYG does not use it

 1 | let {head: _, tail: rest1} = !list_pop(["a", "b", "c"]);
                                                            ^
```

Agent: (thinking) We need to read syntax guide.

Agent: (thinking) We need to return the second item of ["a","b","c"] using builtins. Probably should use !list_pop twice. Syntax: let {head: _, tail: rest1} = !list_pop(["a","b","c"]). No semicolons, newlines separate lets. Then let {head: second, tail: _} = !list_pop(rest1). Then second as final expression.

Make sure patterns correct: destructuring record: {head: _, tail: rest1}. Tail variable name.

Let's write program:

let {head: _, tail: rest1} = !list_pop(["a","b","c"])
let {head: second, tail: _} = !list_pop(rest1)
second

Let's run.

Agent: Ran:
```eyg
let {head: _, tail: rest1} = !list_pop(["a", "b", "c"])
let {head: second, tail: _} = !list_pop(rest1)
second
```
Result: type errors
```
type mismatch given: {head: 26, ..27} expected: [Ok: {head: String, tail: List(String)} | Error: {}]
type mismatch given: {tail: 31, ..32} expected: [Ok: {head: String, tail: List(String)} | Error: {}]
type mismatch given: {head: 41, ..42} expected: [Ok: {head: 44, tail: List(44)} | Error: {}]
type mismatch given: {tail: 47, ..48} expected: [Ok: {head: 50, tail: List(50)} | Error: {}]
```

Agent: (thinking) The error indicates that !list_pop returns a tagged value Ok({head, tail}) or Error. We need to match on that. Use match expression.

Goal: return second item of ["a","b","c"] = "b". Use builtins.

We can do:

match !list_pop(["a","b","c"]) {
 Ok({head: _, tail}) -> {
   match !list_pop(tail) {
     Ok({head: second, tail: _}) -> second
     Error(_) -> Abort("unexpected")
   }
 }
 Error(_) -> Abort("empty")
}

But need syntax per guide. The match syntax: match <expr> { Ok({head, tail}) -> { ... } | Error(_) -> { ... } }

So:

match !list_pop(["a","b","c"]) {
  Ok({head: _, tail}) -> {
    match !list_pop(tail) {
      Ok({head: second, tail: _}) -> second
      Error(_) -> !never(perform Abort(\"empty\" ))
    }
  }
  Error(_) -> !never(perform Abort(\"empty\" ))
}

Return second. Use !never for Abort.

Let's run.

Agent: Ran:
```eyg
match !list_pop(["a", "b", "c"]) {
  Ok({head: _, tail}) -> {
    match !list_pop(tail) {
      Ok({head: second, tail: _}) -> second
      Error(_) -> !never(perform Abort("unexpected"))
    }
  }
  Error(_) -> !never(perform Abort("unexpected"))
}
```
Result: invalid code
```
error: expected `->` followed by `{` in function definition at position 127
hint: functions are written as `(arg) -> { body }`

 4 |       Ok({head: second, tail: _}) -> second
                                          ^
```

Agent: (thinking) We need correct syntax for match arms: pattern -> { expression } . Not using braces directly after arrow? In syntax, after -> we need block { ... }. So need to wrap second in { second }.

Also `Ok({head: _, tail}) -> {` need block braces. Let's construct:

match !list_pop(["a","b","c"]) {
  Ok({head: _, tail}) -> {
    match !list_pop(tail) {
      Ok({head: second, tail: _}) -> { second }
      Error(_) -> !never(perform Abort(\"unexpected\"))
    }
  }
  Error(_) -> !never(perform Abort(\"unexpected\"))
}

But need to reference tail variable name, can't just use tail after pattern because pattern destructures: Ok({head: _, tail}) -> { let tailList = tail; ... } Actually tail is bound as variable. So fine.

Let's try.

Agent: Ran:
```eyg
match !list_pop(["a", "b", "c"]) {
  Ok({head: _, tail}) -> {
    match !list_pop(tail) {
      Ok({head: second, tail: _}) -> { second }
      Error(_) -> !never(perform Abort("unexpected"))
    }
  }
  Error(_) -> !never(perform Abort("unexpected"))
}
```
Result: invalid code
```
error: expected `->` followed by `{` in function definition at position 156
hint: functions are written as `(arg) -> { body }`

 5 |       Error(_) -> !never(perform Abort("unexpected"))
                       ^
```

Agent: (thinking) We need to return second item using builtins. Use !list_pop twice via match. Syntax: match !list_pop(list) { Ok({head, tail}) -> ... }. The arrow syntax is `->` with body in braces. Actually match syntax: match expr { Tag(pat) -> { expr } | ... }. In our earlier code we used `->` but need braces after arrow.

So:

match !list_pop(["a","b","c"]) {
  Ok({head: _, tail}) -> {
    match !list_pop(tail) {
      Ok({head: second, tail: _}) -> { second }
      Error(_) -> !never(perform Abort("unexpected"))
    }
  }
  Error(_) -> !never(perform Abort("unexpected"))
}

Make sure braces correct.

Let's run.

Agent: Ran:
```eyg
match !list_pop(["a", "b", "c"]) {
  Ok({head: _, tail}) -> {
    match !list_pop(tail) {
      Ok({head: second, tail: _}) -> { second }
      Error(_) -> !never(perform Abort("unexpected"))
    }
  }
  Error(_) -> !never(perform Abort("unexpected"))
}
```
Result: invalid code
```
error: expected `->` followed by `{` in function definition at position 156
hint: functions are written as `(arg) -> { body }`

 5 |       Error(_) -> !never(perform Abort("unexpected"))
                       ^
```

Agent: (thinking) We need correct syntax for match branches: pattern -> { expr } where body is a block. In my code, I used `Error(_) -\u003e !never(...)` missing braces. Must wrap in `{ ... }`. Also need to correctly destructure record inside Ok: pattern like `Ok({head: _, tail})`? The pattern syntax: `Ok({head, tail})`? According to spec, match on tag with payload, payload can be a record pattern. Example: `Ok(value) -> { value }`. For record, they used `{head, tail}`? Should be `Ok({head, tail}) -> { ... }`. Let's do that.

Also note that list_pop returns `Ok({head: a, tail: List(a)}) | Error({})`. So pattern: `Ok({head: _, tail})`. Need to use `Ok({head: _, tail})`. The `tail` variable will be list. Then second pop.

Write script:

```
match !list_pop(["a","b","c"]) {
  Ok({head: _, tail}) -> {
    match !list_pop(tail) {
      Ok({head: second, tail: _}) -> { second }
      Error(_) -> !never(perform Abort("unexpected"))
    }
  }
  Error(_) -> !never(perform Abort("unexpected"))
}
```

Make sure braces correct.

Let's run.

Agent: Ran:
```eyg
match !list_pop(["a","b","c"]) {
  Ok({head: _, tail}) -> {
    match !list_pop(tail) {
      Ok({head: second, tail: _}) -> { second }
      Error(_) -> !never(perform Abort("unexpected"))
    }
  }
  Error(_) -> !never(perform Abort("unexpected"))
}
```
Result: invalid code
```
error: expected `->` followed by `{` in function definition at position 154
hint: functions are written as `(arg) -> { body }`

 5 |       Error(_) -> !never(perform Abort("unexpected"))
                       ^
```

Agent: (thinking) We need to understand EYG syntax for match patterns. The syntax guide says match { ... } where each case looks like `Ok(value) -> { value }`. But in the earlier attempts they used `Ok({head: _, tail}) ->`. Wait pattern with record fields inside tag maybe without parentheses? Should be `Ok({head: _, tail}) -> { ... }`. Actually they used "Ok({head: _, tail}) -\u003e". The error expects `->` followed by `{` in function definition at position ... Wait the parser is interpreting something as function definition inside match? Maybe they need parentheses around pattern? Let's check examples: In guide: `match result { Ok(value) -> { value } Error(msg) -> { 0 } }`. So pattern is `Ok(value)` not `Ok({head: _, tail})`. That's acceptable: inside tag you can have a variable pattern, not a record. But they want to match on the record returned by builtin. The builtin returns a tagged value `Ok({head: ..., tail: ...})`. So in pattern we can write `Ok({head: _, tail})` maybe need no curly braces? But pattern record must be inside parentheses? Actually pattern grammar: tag pattern is `TagName variable` where variable is a single identifier. So only one variable allowed, not pattern matching inside. So cannot directly destructure inside tag. Must match Ok(record) then inside use let destructuring. So do:

match !list_pop([...]) {
  Ok(pair) -> {
    let {head: _, tail} = pair
    match !list_pop(tail) {
      Ok(pair2) -> {
        let {head: second, tail: _} = pair2
        second
      }
      Error(_) -> !never(perform Abort("unexpected"))
    }
  }
  Error(_) -> !never(perform Abort("unexpected"))
}

Need to ensure syntax correct: use `let {head: _, tail} = pair` etc. Also braces for bodies.

Let's craft code.

Agent: Ran:
```eyg
match !list_pop(["a","b","c"]) {
  Ok(pair) -> {
    let {head: _, tail} = pair
    match !list_pop(tail) {
      Ok(pair2) -> {
        let {head: second, tail: _} = pair2
        second
      }
      Error(_) -> !never(perform Abort("unexpected"))
    }
  }
  Error(_) -> !never(perform Abort("unexpected"))
}
```
Result: invalid code
```
error: expected `->` followed by `{` in function definition at position 214
hint: functions are written as `(arg) -> { body }`

 9 |       Error(_) -> !never(perform Abort("unexpected"))
                       ^
```

Agent: (thinking) We need to use correct syntax for match branches: pattern -> { expression } (without spaces? Actually syntax: `Ok({head: _, tail}) -> { second }`). The arrow is `->` directly followed by `{`. In earlier attempts they used `-&#x3e;` but that's escaped. Probably using `->` works. Let's write:

```
match !list_pop(["a","b","c"]) {
  Ok({head: _, tail}) -> {
    match !list_pop(tail) {
      Ok({head: second, tail: _}) -> { second }
      Error(_) -> !never(perform Abort("unexpected"))
    }
  }
  Error(_) -> !never(perform Abort("unexpected"))
}
```

Make sure curly braces. Also need final expression is second string. Let's run.

Agent: Ran:
```eyg
match !list_pop(["a","b","c"]) {
  Ok({head: _, tail}) -> {
    match !list_pop(tail) {
      Ok({head: second, tail: _}) -> { second }
      Error(_) -> !never(perform Abort("unexpected"))
    }
  }
  Error(_) -> !never(perform Abort("unexpected"))
}
```
Result: invalid code
```
error: expected `->` followed by `{` in function definition at position 154
hint: functions are written as `(arg) -> { body }`

 5 |       Error(_) -> !never(perform Abort("unexpected"))
                       ^
```

Agent: (thinking) Parsing errors: The syntax for match branches uses `Tag(pattern) -> { expression }`. The error about expecting `->` with `{` indicates that after `Error(_)` we wrote `->` but missing `{`. Actually we did have `{` but the parser expects the body directly after arrow, not preceded by `{`? Let's recall syntax: In match, pattern -> { expression } . So after `->` you need a block (which could be a single expression) but the block should be just the expression, not surrounded by braces? Wait earlier sections: `match Ok(5) { Ok(n) -> { n } Error(_) -> { 0 } }`. So they do use `{}` after arrow. The error indicates maybe we used `!never(perform Abort(...))` which is a function call? That is okay. The problem maybe the arrow token in our source appears as `-�` due to unicode escape? Because we wrote `-\u003e` which becomes `->` but maybe parsing sees? Should directly use `->`. Let's write simple code without unicode escape.

Goal: Return second element of list. Simpler: use !list_pop twice.

We can do:

```
let {head: _, tail} = match !list_pop(["a","b","c"]) {
  Ok(p) -> p
  Error(_) -> !never(perform Abort("empty"))
}
let {head: second, tail: _} = match !list_pop(tail) {
  Ok(p) -> p
  Error(_) -> !never(perform Abort("no second"))
}
second
```

But pattern matching on result: match expression returns either branch result. Need each branch to produce a record. We'll just use pattern matching to extract.

Let's code.

Agent: Ran:
```eyg
let pop1 = match !list_pop(["a","b","c"]) {
  Ok(p) -> { p }
  Error(_) -> !never(perform Abort("empty list"))
}
let {head: _, tail} = pop1
let pop2 = match !list_pop(tail) {
  Ok(p) -> { p }
  Error(_) -> !never(perform Abort("no second"))
}
let {head: second, tail: _} = pop2
second
```
Result: invalid code
```
error: expected `->` followed by `{` in function definition at position 75
hint: functions are written as `(arg) -> { body }`

 3 |   Error(_) -> !never(perform Abort("empty list"))
                   ^
```

Agent: (thinking) We need to understand syntax for match patterns: in the guide, match syntax is:

match expression {
  Ok(value) -> { value }
  Error(_) -> { 0 }
}

But the arrow syntax `->` must be followed by `{`. It seems we used `-> { p }` okay, but got error expecting `->` followed by `{`. The error points at the position after pattern? Actually code: `Ok(p) -\u003e { p }` should be okay. However I think the syntax for pattern uses parentheses after tag? In guide: `Ok(value) -> { value }`. That's what we wrote. Why error? Possibly because we used `match !list_pop([\"a\",\"b\",\"c\"]) {` but !list_pop returns a tagged union of Ok or Error. The pattern must be `Ok({head:..., tail:...})` as built-in returns variant Ok with record. So pattern `Ok(p)` where p is record. That's fine.

But error: "expected `->` followed by `{` in function definition". Might be that the parser interprets the match arms as function definitions because we used arrow without braces incorrectly? Wait we have `Ok(p) -\u003e { p }`. That's okay. However error shows position at `Error(_) -> !never(perform Abort(...))` where we used no braces around body. Indeed in that line we wrote `Error(_) -\u003e !never(perform Abort(\"empty list\"))` missing braces. The rule: after `->` must be `{`. So we need braces around body even if single expression.

Let's fix all arms: wrap bodies in `{ ... }`.

Also in pattern matching with `Ok(p) -> { p }` fine.

Now rewrite program correctly.

Agent: Ran:
```eyg
let pop1 = match !list_pop(["a","b","c"]) {
  Ok(p) -> { p }
  Error(_) -> { !never(perform Abort("empty list")) }
}
let {head: _, tail} = pop1
let pop2 = match !list_pop(tail) {
  Ok(p) -> { p }
  Error(_) -> { !never(perform Abort("no second")) }
}
let {head: second, tail: _} = pop2
second
```
Result: computed
```
"b"
```

Agent: The second element of the list `["a", "b", "c"]` is:

**"b"**

## Effects

- GET https://eyg.run/packages/pull? 200 (loading modules)
- GET https://eyg.run/packages/pull?since=14 200 (loading modules)
- GET https://eyg.run/guides/builtins-reference.md 200
- GET https://eyg.run/guides/eyg-syntax-guide.md 200

The agent finished.
