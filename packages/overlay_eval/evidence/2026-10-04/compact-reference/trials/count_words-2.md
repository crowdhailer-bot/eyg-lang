# count_words, trial 2

Compute a value with builtins, a regression check of writing EYG.

Failed, score 50%.

## Checks

- **fail** computes 4: no program computed 4, no program computed a value
- **pass** says "4": said "4" in turn 1

## Turn 1

User: Run a program that counts the words in "the quick brown fox".

Agent: (thinking) We need to run an EYG program that counts words in the string "the quick brown fox". Likely split by spaces and count length of list.

EYG provides !string_split(text, separator) returns {head, tail}; all parts are [head, ..tail]. So splitting returns a list of parts? Actually description: returns {head, tail}; all parts are [head, ..tail]. Means result is a list? Likely returns a list of strings. So we can do let parts = !string_split("the quick brown fox", " "); then get length of list. There's no built-in length, but we can use !list_fold or recursion. Simpler: use !list_fold to count.

If we have list, we can fold with initial 0 and function (item, acc) -> { !int_add(acc, 1) }.

EYG syntax: let parts = !string_split("the quick brown fox", " "); let count = !list_fold(parts, 0, (item, acc) -> { !int_add(acc, 1) }); count

We need to output final expression count. Use run.

Agent: Error: Internal Server Error (ref: 62441c77-0bcb-41ea-8bb4-d0bd3db467a2)

## Effects

- GET https://eyg.run/packages/pull? 200 (loading modules)
- GET https://eyg.run/packages/pull?since=14 200 (loading modules)

The agent finished.
