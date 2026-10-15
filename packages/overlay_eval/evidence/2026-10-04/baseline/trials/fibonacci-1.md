# fibonacci, trial 1

Sum the first 20 Fibonacci numbers, starting with 1, 1.

Passed, score 100%.

## Checks

- **pass** computes 17710: run 1 computed the value

## Turn 1

User: Calculate the sum of the first 20 Fibonacci numbers, starting with 1, 1. Use an EYG program to calculate the sum and return it as an integer.

Agent: (thinking) We need write EYG script to compute sum of first 20 Fibonacci numbers starting with 1,1. We need to use run tool. Need to know EYG language basics - we don't have guide yet. Use guide tool to read "syntax".

Agent: (thinking) We need to calculate sum of first 20 Fibonacci numbers, starting with 1,1 (so F1=1, F2=1). Compute sum. Could compute via script.

EYG has builtins like !int_add, !int_multiply, !int_subtract, maybe !list_range, !list_fold etc. Not sure builtins list. We might need to generate list of first 20 fibs recursively using fix. Simpler: compute iteratively with loop via recursion/fold.

Implement a function that produces sum using recursion: let fib_sum = !fix((self, n, a, b, acc) -> { match n { Eq(_) -> { acc } | _ -> { self(!int_subtract(n,1), b, !int_add(a,b), !int_add(acc,b)) } } }). But need compare n to 0.

We need builtins for compare: !int_compare returns Lt, Eq, Gt tags. Use match.

Let's write EYG:

```
let fib_sum = !fix((self, n, a, b, acc) -> {
  match !int_compare(n, 0) {
    Eq(_) -> { acc }
    | (_) -> {
        let next = !int_add(a, b)
        self(!int_subtract(n, 1), b, next, !int_add(acc, b))
      }
  }
})
fib_sum(20, 1, 1, 0)
```

Wait: Starting with a=1, b=1. For summation, we need to add current term? Define that we have already first two? Approach: Use n count of terms left. At each step, add a (the current term) to acc, then update (a,b) = (b, a+b). Initially a=1, b=1.

So code:

```
let fib_sum = !fix((self, n, a, b, acc) -> {
  match !int_compare(n, 0) {
    Eq(_) -> { acc }
    | (_) -> {
        let new_acc = !int_add(acc, a)
        self(!int_subtract(n,1), b, !int_add(a,b), new_acc)
      }
  }
})
fib_sum(20, 1, 1, 0)
```

Should return integer sum.

Now we need to run this program using run tool. Provide code string.

We must ensure function syntax correct. No semicolons.

Also need to include any needed imports? Builtins available.

Let's produce program.

Agent: Ran:
```eyg
let fib_sum = !fix((self, n, a, b, acc) -> {
  match !int_compare(n, 0) {
    Eq(_) -> { acc }
    | (_) -> {
        let new_acc = !int_add(acc, a)
        self(!int_subtract(n,1), b, !int_add(a,b), new_acc)
      }
  }
})

fib_sum(20, 1, 1, 0)

```
Result: computed
```
17710
```

Agent: The sum of the first 20 Fibonacci numbers (starting with 1, 1) is **17710**.

## Effects

- GET https://eyg.run/packages/pull? 200 (loading modules)
- GET https://eyg.run/packages/pull?since=14 200 (loading modules)
- GET https://eyg.run/guides/eyg-syntax-guide.md 200

The agent finished.
