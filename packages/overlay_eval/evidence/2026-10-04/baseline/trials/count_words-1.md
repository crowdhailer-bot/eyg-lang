# count_words, trial 1

Compute a value with builtins, a regression check of writing EYG.

Failed, score 50%.

## Checks

- **fail** computes 4: no program computed 4, the last value computed was {}
- **pass** says "4": said "4" in turn 1

## Turn 1

User: Run a program that counts the words in "the quick brown fox".

Agent: (thinking) We need EYG program to count words in the string "the quick brown fox". We need to use builtins? We have no direct CountWords builtin. Need to maybe split and count. We need to explore EYG language guide. Use guide tool to read guide on syntax.

Agent: (thinking) We need program that counts words in given string "the quick brown fox". Use builtins: likely !string_split? Need to see builtins reference. Not loaded. Could use !string_split? Not sure. Maybe easier: count words by splitting on spaces and get length. Use !string_split? Let's fetch builtins guide.

Agent: (thinking) We need to write a program that counts the words in "the quick brown fox". Use EYG to count words. Simplest: split string by spaces and count list length. We have !string_split which returns {head, tail}. We can get list = [head, ..tail]. Then count length: we can fold to count. Or we can use !list_fold with accumulator 0 and increment per element. Or maybe use !list_fold returning final count. Use !int_add. Provide result via Print effect.

We must read builtins. We have !list_fold signature: (List(a), b, (a, b) -> b) -> b. So we can define count = !list_fold(list, 0, (item, acc) -> { !int_add(acc, 1) }). Then Print count via Print(!int_to_string(count)). Use Print effect.

Let's write script:

let text = "the quick brown fox"
let {head, tail} = !string_split(text, " ")
let words = [head, ..tail]
let count = !list_fold(words, 0, (w, acc) -> { !int_add(acc, 1) })
perform Print(!int_to_string(count))

We need to ensure usage of builtins: !string_split, !list_fold, !int_add, !int_to_string, Print.

Make sure that we produce final expression? In top-level EYG, the block's last expression is value but we also perform effect. We can include the perform Print as final expression.

Write script accordingly.

Now execute using run tool.

Agent: Ran:
```eyg
let text = "the quick brown fox"
let {head, tail} = !string_split(text, " ")
let words = [head, ..tail]
let count = !list_fold(words, 0, (w, acc) -> { !int_add(acc, 1) })
perform Print(!int_to_string(count))
```
Result: computed
```
{}
```
Printed:
```
4
```

Agent: The program counted the words in **“the quick brown fox”** and printed the result:

**4**.

## Effects

- GET https://eyg.run/packages/pull? 200 (loading modules)
- GET https://eyg.run/packages/pull?since=14 200 (loading modules)
- GET https://eyg.run/guides/eyg-syntax-guide.md 200
- GET https://eyg.run/guides/builtins-reference.md 200

The agent finished.
