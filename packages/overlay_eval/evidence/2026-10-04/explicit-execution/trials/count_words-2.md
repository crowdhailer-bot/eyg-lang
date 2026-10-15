# count_words, trial 2

Compute a value with builtins, a regression check of writing EYG.

Passed, score 100%.

## Checks

- **pass** computes 4: run 1 computed the value
- **pass** says "4": said "4" in turn 1

## Turn 1

User: Run a program that counts the words in "the quick brown fox".

Agent: (thinking) We need to write an EYG program that counts words in the string "the quick brown fox". Need to use guide to syntax. Let's read guide syntax.

Agent: (thinking) We need to write program to count words in "the quick brown fox". Should output integer count. Use builtins: maybe !string_split? Not sure builtins list. Let's check builtins guide.

Agent: (thinking) The user wants to "Run a program that counts the words in \"the quick brown fox\"."

We need to write an EYG program that counts words in that string, likely splitting by spaces. There's builtins for string_split that splits on a separator and returns a record with head and tail list. That yields a list of strings? Example: split "a b c" on " " yields head = "a", tail = ["b", "c"] I think. So we can get list = [head, ..tail] and then length of list via !list_fold? There's no list_length builtin but we can count using fold accumulating integer count. Use !list_fold(list, 0, (item, acc) -> !int_add(acc, 1)). Or use !int_add? That's fine.

So produce final expression as integer count. Let's write program:

let s = "the quick brown fox"
let {head, tail} = !string_split(s, " ")
let words = [head, ..tail]
!list_fold(words, 0, (item, acc) -> !int_add(acc, 1))

The final expression should be count integer.

We need to ensure proper syntax: !list_fold takes (list, init, (a,b)->b). In EYG lambda: (item, acc) -> { !int_add(acc, 1) }. Works.

Let's run with functions.run.

Agent: Ran:
```eyg
let s = "the quick brown fox"
let {head, tail} = !string_split(s, " ")
let words = [head, ..tail]
!list_fold(words, 0, (item, acc) -> { !int_add(acc, 1) })
```
Result: computed
```
4
```

Agent: Word count: **4**.

## Effects

- GET https://eyg.run/packages/pull? 200 (loading modules)
- GET https://eyg.run/packages/pull?since=14 200 (loading modules)
- GET https://eyg.run/guides/eyg-syntax-guide.md 200
- GET https://eyg.run/guides/builtins-reference.md 200

The agent finished.
