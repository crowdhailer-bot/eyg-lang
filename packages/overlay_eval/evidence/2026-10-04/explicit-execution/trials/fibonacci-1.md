# fibonacci, trial 1

Sum the first 20 Fibonacci numbers, starting with 1, 1.

Passed, score 100%.

## Checks

- **pass** computes 17710: run 1 computed the value

## Turn 1

User: Calculate the sum of the first 20 Fibonacci numbers, starting with 1, 1. Use an EYG program to calculate the sum and return it as an integer.

Agent: (thinking) We need to write EYG program to calculate sum of first 20 Fibonacci numbers, starting with 1,1. So sequence: 1,1,2,3,5,8,13,21,34,55,89,144,233,377,610,987,1597,2584,4181,6765. Sum? Let's compute manually or via program. Better to write program to calculate sum.

We need to read syntax guide first. Use guide function.

Agent: (thinking) We need to calculate sum of first 20 Fibonacci numbers starting with 1,1. Use EYG program to calculate sum and return as integer. Need to write script using recursion/fold.

We can generate list of first 20 fib numbers. Use fix to generate list? Simpler: use list_fold to generate sum while generating sequence.

We could define a recursive function that builds list: fibs n a b where n count left. base case n=0 returns [] else cons a then rec with n-1 b a+b.

In EYG, to construct list we can use [head, ..tail] syntax. Use recursion with fix.

Pseudo:

let fib_list = !fix((self, n, a, b) -> {
  match !int_compare(n, 0) {
    Eq(_) -> { [] }
    | (_) -> {
      let tail = self(!int_subtract(n, 1), b, !int_add(a, b))
      [a, ..tail]
    }
  }
})

let first20 = fib_list(20, 1, 1)

Then sum using !list_fold: fold list with accumulator 0 and function (acc, x) -> !int_add(acc, x).

But list_fold builtin? Not described but likely exists. Use !list_fold(list, init, f). Need check builtins_reference but not loaded. However can use recursion to sum as well.

Simpler: directly compute sum using recursion of generating and adding.

Define sum_fibs = !fix((self, n, a, b) -> {
  match !int_compare(n, 0) {
    Eq(_) -> { 0 }
    | (_) -> {
        let next = self(!int_subtract(n, 1), b, !int_add(a, b))
        !int_add(a, next)
    }
  }
})

Then sum_fibs(20,1,1) returns sum.

We need to return as final expression.

Let's craft EYG code.

Will need !int_compare, !int_add, !int_subtract. Also need match syntax. Use pattern: match !int_compare(n,0) { Eq(_) -> { ... } | (_) -> { ... } }

Ok.

Now produce final expression.

We'll run with run tool.

Agent: Ran:
```eyg
let sum_fibs = !fix((self, n, a, b) -> {
  match !int_compare(n, 0) {
    Eq(_) -> { 0 }
    | (_) -> {
        let next = self(!int_subtract(n, 1), b, !int_add(a, b))
        !int_add(a, next)
    }
  }
})
sum_fibs(20, 1, 1)
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
