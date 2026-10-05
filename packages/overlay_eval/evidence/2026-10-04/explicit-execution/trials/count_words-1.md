# count_words, trial 1

Compute a value with builtins, a regression check of writing EYG.

Passed, score 100%.

## Checks

- **pass** computes 4: run 2 computed the value
- **pass** says "4": said "4" in turn 1

## Turn 1

User: Run a program that counts the words in "the quick brown fox".

Agent: (thinking) We need to write an EYG program that counts words in a string "the quick brown fox". Probably there is a builtin function for splitting? Not sure. Need to read guide for builtins.

Agent: (thinking) We need to run program that counts words in "the quick brown fox". Use EYG language. We need to produce final expression as count integer. Let's write script: split by space, then count items. Using !string_split with separator " ". That returns record with head and tail list. Combine into list then length using !list_fold to count or we can use !list_fold to count items. There is no builtin for length of list directly, but we can fold. Use let {head, tail} = !string_split(...). let words = [head, ..tail]. Then perform count via !list_fold(words, 0, (item, acc) -> !int_add(acc, 1)). Return that integer. Need final expression as result. Use return last expression. Write code and run.

Agent: Ran:
```eyg
let {head, tail} = !string_split("the quick brown fox", " ")
let words = [head, ..tail]
!list_fold(words, 0, (item, acc) -> !int_add(acc, 1))
```
Result: invalid code
```
error: expected `->` followed by `{` in function definition at position 124
hint: functions are written as `(arg) -> { body }`

 3 | !list_fold(words, 0, (item, acc) -> !int_add(acc, 1))
                                         ^
```

Agent: (thinking) We need correct syntax: lambda is `(item, acc) -> { !int_add(acc, 1) }`. Also final expression should be the result of list_fold, giving count. Let's adjust.

Agent: Ran:
```eyg
let {head, tail} = !string_split("the quick brown fox", " ")
let words = [head, ..tail]
!list_fold(words, 0, (item, acc) -> { !int_add(acc, 1) })
```
Result: computed
```
4
```

Agent: (thinking) We need to output the word count. The program returns final expression result of list_fold which will be integer count. The result printed is 4. Need to respond in djot indicating the result.

Agent: The word count is **4**.

## Effects

- GET https://eyg.run/packages/pull? 200 (loading modules)
- GET https://eyg.run/packages/pull?since=14 200 (loading modules)
- GET https://eyg.run/guides/builtins-reference.md 200

The agent finished.
