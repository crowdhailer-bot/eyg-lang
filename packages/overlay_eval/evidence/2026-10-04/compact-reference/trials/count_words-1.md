# count_words, trial 1

Compute a value with builtins, a regression check of writing EYG.

Passed, score 100%.

## Checks

- **pass** computes 4: run 2 computed the value
- **pass** says "4": said "4" in turn 1

## Turn 1

User: Run a program that counts the words in "the quick brown fox".

Agent: (thinking) We need to write an EYG program that counts words in a given string "the quick brown fox". We can split string on spaces and count elements.

We have !string_split but returns a record {head, tail}. Actually returns {head, tail} where tail is a list of remaining splits? The guide likely says something else: maybe it's like splitting once. But we can use !string_split repeatedly? Better: maybe we can use !list_fold or recursion to count.

Simplify: we can count words by splitting on space and then using list length. Do we have list length? Not listed. Could use fold to increment count.

We need to get list of words. There's no direct split all, but maybe !string_split returns a list? However doc: returns {head, tail}; all parts are [head, ..tail]. Means tail is a list of remaining parts? So we can treat result as list: the result itself is a list where the first element is head, and tail is the rest list. So the result is a list of strings.

Thus we can do let parts = !string_split("the quick brown fox", " "); then parts is a list. To count, we can use !list_fold(parts, 0, (item, acc) -> { !int_add(acc, 1) }). That returns final accumulator.

We need final expression to be that count.

Let's write program:

let parts = !string_split("the quick brown fox", " ");
!list_fold(parts, 0, (item, acc) -> { !int_add(acc, 1) })

Test via run.

Agent: Ran:
```eyg
let parts = !string_split("the quick brown fox", " ");
!list_fold(parts, 0, (item, acc) -> { !int_add(acc, 1) })
```
Result: invalid code
```
error: invalid character ';' at position 53
hint: remove or replace this character — EYG does not use it

 1 | let parts = !string_split("the quick brown fox", " ");
                                                          ^
```

Agent: (thinking) We need EYG syntax, which apparently doesn't have semicolons. Use line breaks maybe just separate expressions with whitespace. Use let binding and final expression.

We need to split string by space; !string_split returns {head, tail} where tail is list of rest. So direct fold not works; we can convert to list of parts? Probably there is a function to split returns list? But per quick reference, !string_split returns {head, tail} and all parts are [head, ..tail] (a list). So maybe we can do let {head, tail} = !string_split(...). Then let parts = [head, ..tail]. Then fold.

Let's code:

let {head, tail} = !string_split("the quick brown fox", " ")
let parts = [head, ..tail]
!list_fold(parts, 0, (item, acc) -> { !int_add(acc, 1) })

That returns count. Let's run.

Agent: Ran:
```eyg
let {head, tail} = !string_split("the quick brown fox", " ")
let parts = [head, ..tail]
!list_fold(parts, 0, (item, acc) -> { !int_add(acc, 1) })
```
Result: computed
```
4
```

Agent: The word count is **4**.

## Effects

- GET https://eyg.run/packages/pull? 200 (loading modules)
- GET https://eyg.run/packages/pull?since=14 200 (loading modules)

The agent finished.
