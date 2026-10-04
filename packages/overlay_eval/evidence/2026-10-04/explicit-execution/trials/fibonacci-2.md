# fibonacci, trial 2

Sum the first 20 Fibonacci numbers, starting with 1, 1.

Passed, score 100%.

## Checks

- **pass** computes 17710: run 2 computed the value

## Turn 1

User: Calculate the sum of the first 20 Fibonacci numbers, starting with 1, 1. Use an EYG program to calculate the sum and return it as an integer.

Agent: (thinking) We need to write EYG program to compute sum of first 20 Fibonacci numbers starting with 1,1. Need to read syntax guide. Let's fetch guide.

Agent: (thinking) We need to compute sum of first 20 Fibonacci numbers starting with 1,1. Use EYG program to calculate sum and return integer. Use recursion or fix. We'll use list generation? Simpler: compute iteratively using fix or fold.

We can write a function that generates fib sequence via recursion with accumulator. Use fix to produce nth fib.

Define fib = !fix ((self, n) -> { match !int_compare(n, 2) { Lt(_) -> {1} | Eq(_) -> {1} | Gt(_) -> { let a = self(!int_subtract(n, 1)); let b = self(!int_subtract(n, 2)); !int_add(a, b) } } }) but that will be exponential. 20 is fine.

Then compute sum using list fold over range? There is no built-in range list, but we can generate list via recursion as well.

Simpler: compute sum directly by iterating n from 1 to 20, accumulating fib values.

We can define accumulator function using fix that takes (i, acc, a, b) where a=F_i, b=F_{i+1}. Starting i=1, a=1, b=1, acc=0. While i <=20, add a to acc, then next a=b, b=a+b (old a+b). Return acc when i>20.

Implement using fix:

let sum_fib = !fix ((self, i, acc, a, b) -> {
  match !int_compare(i, 21) {
    Gt(_) -> { acc }
    | (_) -> {
        let new_acc = !int_add(acc, a);
        let next_a = b;
        let next_b = !int_add(a, b);
        self(!int_add(i, 1), new_acc, next_a, next_b)
      }
  }
})

Then call sum_fib(1, 0, 1, 1). Return that.

Need to use int_compare etc. Let's confirm builtins: !int_compare returns tag Lt, Eq, Gt? Probably. Use pattern matching.

Write:

let sum_fib = !fix((self, i, acc, a, b) -> {
  match !int_compare(i, 21) {
    Gt(_) -> { acc }
    | (_) -> {
        let new_acc = !int_add(acc, a);
        let next_a = b;
        let next_b = !int_add(a, b);
        self(!int_add(i, 1), new_acc, next_a, next_b)
      }
  }
})

But match must cover all tags. Provide Gt, Eq, Lt? Simpler: compare i with 21, we want when i >20 stop. We can do compare i, 20 and stop when i >20. Use compare(i, 20). If Gt -> return acc else continue.

match !int_compare(i, 20) {
  Gt(_) ->… (cut)

Agent: Ran:
```eyg
let sum_fib = !fix((self, i, acc, a, b) -> {
  match !int_compare(i, 20) {
    Gt(_) -> { acc }
    | (_) -> {
        let new_acc = !int_add(acc, a);
        let next_a = b;
        let next_b = !int_add(a, b);
        self(!int_add(i, 1), new_acc, next_a, next_b)
      }
  }
})
sum_fib(1, 0, 1, 1)
```
Result: invalid code
```
error: invalid character ';' at position 149
hint: remove or replace this character — EYG does not use it

 5 |         let new_acc = !int_add(acc, a);
                                           ^
```

Agent: (thinking) We need to write correct EYG syntax. No semicolons. Use let binding as `let new_acc = expr` then next line is expression, not need semicolon.

Also need to pass correct arguments: we want a recursive function that iterates i from 1 to 20 inclusive? Starting with first Fibonacci numbers 1,1. Sum of first 20 numbers.

Define fix function self, i, acc, a, b where a and b are current fib numbers? At start i=1, a=1, b=1, acc=0. For each step, add a to acc, then advance a=b, b=a+b (old). Increment i. When i>20 stop and return acc.

But need int_compare returning Lt, Eq, Gt tags. To check >20 use Gt. Use pattern match. Syntax: match !int_compare(i, 20) { Gt(_) -> { acc } | (_) -> { ... } }

But need to import tags? Probably Gt, Eq, Lt are tags. Use Gt(_). That's fine.

Also need int_add.

Let's construct:

let sum_fib = !fix((self, i, acc, a, b) -> {
  match !int_compare(i, 20) {
    Gt(_) -> { acc }
    | (_) -> {
        let new_acc = !int_add(acc, a)
        let next_a = b
        let next_b = !int_add(a, b)
        self(!int_add(i, 1), new_acc, next_a, next_b)
      }
  }
})
sum_fib(1, 0, 1, 1)

Make sure parentheses right. Use arrow -> after parameters. All let statements inside block.

Let's run.

Agent: Ran:
```eyg
let sum_fib = !fix((self, i, acc, a, b) -> {
  match !int_compare(i, 20) {
    Gt(_) -> { acc }
    | (_) -> {
        let new_acc = !int_add(acc, a)
        let next_a = b
        let next_b = !int_add(a, b)
        self(!int_add(i, 1), new_acc, next_a, next_b)
      }
  }
})
sum_fib(1, 0, 1, 1)
```
Result: computed
```
17710
```

Agent: (thinking) We need to output sum as integer. The result 17710 is the final expression. Need respond in djot without code blocks.

Agent: The sum of the first 20 Fibonacci numbers (starting 1, 1) is **17710**.

## Effects

- GET https://eyg.run/packages/pull? 200 (loading modules)
- GET https://eyg.run/packages/pull?since=14 200 (loading modules)
- GET https://eyg.run/guides/eyg-syntax-guide.md 200

The agent finished.
