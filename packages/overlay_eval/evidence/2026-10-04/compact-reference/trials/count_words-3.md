# count_words, trial 3

Compute a value with builtins, a regression check of writing EYG.

Failed, score 50%.

## Checks

- **fail** computes 4: no program computed 4, no program computed a value
- **pass** says "4": said "4" in turn 1

## Turn 1

User: Run a program that counts the words in "the quick brown fox".

Agent: (thinking) We need to write EYG program to count words in a string "the quick brown fox". Use split likely with !string_split; but that returns head and tail list? Actually !string_split returns {head, tail}; all parts are [head, ..tail]. So we can split on space. Then we get list of words. Use !list_fold? Or just get length of list. There is no built-in length, but we can fold counting. Use let words = !string_split("the quick brown fox", " "); then let count = !list_fold(words, 0, (item, acc) -> { !int_add(acc, 1) }); Return count.

Check !list_fold signature: items, initial, (item, acc) -> { next_acc }. Yes.

So code: let words = !string_split("the quick brown fox", " "); let count = !list_fold(words, 0, (w, a) -> { !int_add(a, 1) }); count.

We need to return final expression count.

Let's run.

Agent: Error: Internal Server Error (ref: 23a3b5b6-ba3d-4a37-b6cd-fa2e0817ce6f)

## Effects

- GET https://eyg.run/packages/pull? 200 (loading modules)
- GET https://eyg.run/packages/pull?since=14 200 (loading modules)

The agent finished.
