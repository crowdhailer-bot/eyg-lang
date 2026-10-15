# count_words, trial 2

Compute a value with builtins, a regression check of writing EYG.

Failed, score 50%.

## Checks

- **fail** computes 4: no program computed 4, the last value computed was {}
- **pass** says "4": said "4" in turn 1

## Turn 1

User: Run a program that counts the words in "the quick brown fox".

Agent: (thinking) We need to write an EYG program that counts words in the given string. Need to know syntax of EYG. Use guide.

Agent: (thinking) We need to write a program that counts the words in "the quick brown fox". Use EYG script. We need to output the count. We can use builtins like !string_split? Not sure what builtins are available. We have list operations. We could maybe Count words by splitting on spaces. There may be !string_split built-in. Not sure. Let's check builtins guide.

Agent: (thinking) We need to write a program that counts the words in "the quick brown fox". We should produce output perhaps via Print effect. User says "Run a program that counts the words in "the quick brown fox"." So we need to write EYG script that takes that string, splits into words, counts them, and prints the count.

We need to read syntax guide before writing. Already did. We need to use builtins for string split, maybe count list length. However there is no builtin for list length; we have !list_fold but we can use fold to count. Could also split by spaces. Use !string_split with separator " " returns record {head, tail}. That gives head string and tail list of strings (rest). To get flat list of all words: [head, ..tail]. Then use !list_fold to count: start 0 and for each _, acc -> !int_add(acc, 1). Then Print result as string via !int_to_string.

Use Print effect. Use let bindings. Finally the script's final expression could be Print but we must still produce something? Actually performing Print is an effect, we need to call perform Print? The effect is Print(String). So! we use perform Print(string). The program should end after that maybe returns something else (maybe unit). We can just have perform Print(...). The script returns whatever last expression yields, which will be the unit {} maybe.

Let's craft program:

let text = "the quick brown fox"
let {head, tail} = !string_split(text, " ")
let words = [head, ..tail]
let count = !list_fold(words, 0, (word, acc) -> {
  !int_add(acc, 1)
})
perform Print(!int_to_string(count))

We need to ensure that the split works: string_split returns record {head: String, tail: List(String)}. This works.

Now we need to run via run tool.

Agent: Ran:
```eyg
let text = "the quick brown fox"
let {head, tail} = !string_split(text, " ")
let words = [head, ..tail]
let count = !list_fold(words, 0, (word, acc) -> { !int_add(acc, 1) })
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

Agent: The program counted the words and printed the result: **4**.

## Effects

- GET https://eyg.run/packages/pull? 200 (loading modules)
- GET https://eyg.run/packages/pull?since=14 200 (loading modules)
- GET https://eyg.run/guides/eyg-syntax-guide.md 200
- GET https://eyg.run/guides/builtins-reference.md 200

The agent finished.
