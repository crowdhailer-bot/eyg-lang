# count_words, trial 3

Compute a value with builtins, a regression check of writing EYG.

Passed, score 100%.

## Checks

- **pass** computes 4: run 1 computed the value
- **pass** says "4": said "4" in turn 1

## Turn 1

User: Run a program that counts the words in "the quick brown fox".

Agent: (thinking) We need to write an EYG program that counts words in the given string. Need to read syntax guide. Let's fetch guide "syntax".

Agent: (thinking) We need to run a program that counts the words in "the quick brown fox". Need to write EYG code to count words. Probably split string by spaces, then count list length. Need builtins: !string_split? Let's check builtins guide.

Agent: (thinking) User wants to "Run a program that counts the words in \"the quick brown fox\"."

We need to write EYG program that counts words. Likely split on spaces, then count list length. Use builtins: !string_split? That splits into head and tail list based on separator. For "the quick brown fox", splitting by space yields head "the", tail ["quick","brown","fox"]. Length = 1 + len(tail) = 4.

We can get head, tail via let {head, tail} = !string_split(text, " "). Then we need list length. There's no built-in for list length, but we can use !list_fold to count. Or we could convert to array? No list length builtin. Use !list_fold with accumulator 0 and function that adds 1.

Define count = let countList = (lst) -> { !list_fold(lst, 0, (item, acc) -> { !int_add(acc, 1) }) }. Then total = !int_add(1, countList(tail)) if list non-empty. Simpler: combine head+tail into full list: let words = [head, ..tail]; then count with fold.

Thus program:

let txt = "the quick brown fox"
let {head, tail} = !string_split(txt, " ")
let words = [head, ..tail]
!list_fold(words, 0, (item, acc) -> { !int_add(acc, 1) })

That final expression yields count (integer) 4.

We need to run using run tool. Ensure syntax correct. Use let syntax: let var = expr. For pattern destructuring, let {head, tail} = !string_split(...). This returns a record head and tail.

Write program exactly.

Let's run.

Agent: Ran:
```eyg
let txt = "the quick brown fox"
let {head, tail} = !string_split(txt, " ")
let words = [head, ..tail]
!list_fold(words, 0, (item, acc) -> { !int_add(acc, 1) })
```
Result: computed
```
4
```

Agent: The word count is **4**.

## Effects

- GET https://eyg.run/packages/pull? 200 (loading modules)
- GET https://eyg.run/packages/pull?since=14 200 (loading modules)
- GET https://eyg.run/guides/eyg-syntax-guide.md 200
- GET https://eyg.run/guides/builtins-reference.md 200

The agent finished.
