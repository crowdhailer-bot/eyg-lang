# list_second, trial 1

Extract a list item without assuming pattern matching on lists.

Failed, score 0%.

## Checks

- **fail** computes "b": no program computed "b", no program computed a value

## Turn 1

User: Use builtins to return the second item of ["a", "b", "c"]. Run the program.

Agent: (thinking) We need to write EYG program to get second item of list ["a","b","c"] using builtins. Likely use list indexing? There is no direct indexing; we can pattern match? We can use list_pop to get head and tail, then pop again. Or use list_fold? Simpler: let list = ["a","b","c"]; then let {head, tail} = !list_pop(list) -> gives head "a", tail ["b","c"]; then let {head2, tail2} = !list_pop(tail) -> head2 "b". Return head2. Need to handle Ok/ Error: list_pop returns Ok({head, tail}) or Error({}). So need match. Use match !list_pop(list) { Ok(pair) -> { let {head, tail} = pair; match !list_pop(tail) { Ok(pair2) -> { let {head: second, tail: _} = pair2; second } Error(_) -> { "" } } } Error(_) -> { "" }.

We can write final expression as that. Use perform? No, just program returns string.

Let's construct program.

Agent: Error: Internal Server Error (ref: b4bf542a-e251-41c3-9bc8-b5e95343ea45)

## Effects

- GET https://eyg.run/packages/pull? 200 (loading modules)
- GET https://eyg.run/packages/pull?since=14 200 (loading modules)

The agent finished.
