# fibonacci, trial 1

Sum the first 20 Fibonacci numbers, starting with 1, 1.

Passed, score 100%.

## Checks

- **pass** computes 17710: run 1 computed the value

## Turn 1

User: Calculate the sum of the first 20 Fibonacci numbers, starting with 1, 1. Use an EYG program to calculate the sum and return it as an integer.

Agent: Ran:
```eyg
let sum = !fix((self, n, a, b, total) -> {
  match !int_compare(n, 0) {
    Eq(_) -> { total }
    | (_) -> { self(!int_subtract(n, 1), b, !int_add(a, b), !int_add(total, a)) }
  }
})
sum(20, 1, 1, 0)
```
Result: computed
```
17710
```

Agent: The sum is 17710.

## Effects

- GET https://eyg.run/packages/pull? 200 (loading modules)
- GET https://eyg.run/packages/pull?since=12 200 (loading modules)

The agent finished.
