# fibonacci, trial 2

Sum the first 20 Fibonacci numbers, starting with 1, 1.

Passed, score 100%.

## Checks

- **pass** computes 17710: run 4 computed the value

## Turn 1

User: Calculate the sum of the first 20 Fibonacci numbers, starting with 1, 1. Use an EYG program to calculate the sum and return it as an integer.

Agent: (thinking) We need to write EYG code to compute sum of first 20 Fibonacci numbers starting with 1,1. Fibonacci sequence: F1=1, F2=1, F3=2,... We need sum of first 20 terms. Compute using recursion or loop via !list_fold? Could generate list of 20 fib numbers then sum.

We can generate list using recursion building list. Simpler: iterate using fix to produce list.

Let's try to generate list of 20 fib numbers: let fibs = !fix((self, n, a, b) -> {
   // n remaining count, a is current fib, b next
   // if n == 0, return []
   match (!int_compare(n, 0)) {
       Eq({}) -> { [] }
       Gt({}) -> {
          let rest = self(!int_subtract(n,1), b, !int_add(a,b))
          [a, ..rest]
       }
   }
}) (20, 1, 1)

But need to call fix with function expecting self and args. Use !fix((self, n, a, b) -> { ... }). Then apply to arguments.

Then sum list via !list_fold(fibs, 0, (item, acc) -> { !int_add(item, acc) }).

Return that sum.

Let's code in EYG.

Need to be careful with syntax matching: match result { Ok(x) -> {...} } but int_compare returns a tag Lt, Eq, Gt. So we can match on that.

match (!int_compare(n, 0)) {
   Eq({}) -> { [] }
   Gt({}) -> {
      let rest = self(!int_subtract(n, 1), b, !int_add(a, b))
      [a, ..rest]
   }
   Lt({}) -> { [] } // shouldn't happen
}

Now final expression is sum.

Let's write full program:

let fibs =
   (!fix((self, n, a, b) -> {
      match (!int_compare(n, 0)) {
         Eq({}) -> { [] }
         Gt({}) -> {
            let rest = self(!int_subtract(n, 1), b, !int_add(a, b))
            [a, ..rest]
         }
         Lt({}) -> { [] }
      }
   }))(20, 1, 1)

in
!list_fold(fibs, 0, (item, acc) -> { !int_add(item, acc) })

We need to ensure parentheses for fix call: (!fix(...))(20,1,1). That returns a function applied.

Now run.

Agent: Ran:
```eyg
let fibs = (!fix((self, n, a, b) -> { match (!int_compare(n, 0)) { Eq({}) -> { [] } Gt({}) -> { let rest = self(!int_subtract(n, 1), b, !int_add(a, b)) [a, ..rest] } Lt({}) -> { [] } } }))(20, 1, 1) in !list_fold(fibs, 0, (item, acc) -> { !int_add(item, acc) })
```
Result: invalid code
```
error: unexpected `!` at position 12
hint: view the syntax guide

 1 | let fibs = (!fix((self, n, a, b) -> { match (!int_compare(n, 0)) { Eq({}) -> { [] } Gt({}) -> { let rest = self(!int_subtract(n, 1), b, !int_add(a, b)) [a, ..rest] } Lt({}) -> { [] } } }))(20, 1, 1) in !list_fold(fibs, 0, (item, acc) -> { !int_add(item, acc) })
                 ^
```

Agent: (thinking) We need to correct syntax. In EYG, special operators start with !. However, the example shows !fix((self, n) -> {...}) etc. The error says unexpected `!` at position 12, maybe top-level cannot start with `!`. The syntax may require `let` then expression without leading '!'. Actually builtins are called with leading '!'. That's fine. Maybe the issue is extra parentheses after !fix. The syntax for fix probably is !fix((self, n, a, b) -> { ... }). Maybe need no parentheses around parameters? Let's check guide. Use guide.

Agent: (thinking) The user wants sum of first 20 Fibonacci numbers starting with 1,1. Need to compute and return integer.

We need to write EYG program that returns integer.

We can write a recursive function generating list of first n fib numbers, then sum via list_fold.

Simplify: we can compute sum directly using recursion without list.

Define fib_sum = !fix((self, n, a, b, acc) -> { if n == 0 then acc else self(n-1, b, a+b, acc+a) }) Starting with n=20, a=1,b=1, acc=0. After loop, return acc.

We need int_compare to check n.

Implementation:

let fib_sum = !fix((self, n, a, b, acc) -> {
  match !int_compare(n, 0) {
    Eq({}) -> { acc }
    Gt({}) -> { self(!int_subtract(n, 1), b, !int_add(a, b), !int_add(acc, a)) }
    Lt({}) -> { acc } // shouldn't happen
  }
})
fib_sum(20, 1, 1, 0)

We must ensure function curried? In syntax, (self, n, a, b, acc) -> { ... } is curried? Actually multiple parameters are curried, but we can treat it as taking first arg self then returning function for n etc. In fix we need a function that expects self then args; but we call the result with all args after fix returns a function expecting n etc? Actually !fix returns a function where the self bound; we can then call it with remaining arguments. Usually pattern: let factorial = !fix((self, n) -> { ... }); factorial(5). So fix takes a function of (self, ...args). So our use: let fib_sum = !fix((self, n, a, b, acc) -> { ... }); fib_sum(20, 1, 1, 0).

That should work.

Now write program as single expression: let fib_sum = ... in fib_sum(20,1,1,0)

Return final integer.

Let's test.

Agent: Ran:
```eyg
let fib_sum = !fix((self, n, a, b, acc) -> {
  match !int_compare(n, 0) {
    Eq({}) -> { acc }
    Gt({}) -> { self(!int_subtract(n, 1), b, !int_add(a, b), !int_add(acc, a)) }
    Lt({}) -> { acc }
  }
}) in fib_sum(20, 1, 1, 0)
```
Result: invalid code
```
error: unexpected `fib_sum` at position 209 — the expression is complete but there are leftover tokens
hint: EYG uses function calls for operations (e.g. !int_add(a, b)), not infix operators

 7 | }) in fib_sum(20, 1, 1, 0)
           ^
```

Agent: (thinking) We need to compute sum of first 20 Fibonacci numbers starting with 1,1. So sequence: F1=1, F2=1, then 2,3,5,8,... up to F20. Need sum.

We can compute with recursion returning sum directly, not need fib list. Use !fix to define recursive function returning sum. Function parameters: n remaining count, a current fib, b next fib, acc sum so far. Base case n == 0 returns acc. Else call self(n-1, b, a+b, acc+a). Note need to use !int_add, !int_subtract, !int_compare.

We need final expression as integer sum. Ensure syntax correct: let fib_sum = !fix((self, n, a, b, acc) -> { ... }) in fib_sum(20, 1, 1, 0). The whole program is let... in ... That's okay.

But we need correct syntax for lambda: (self, n, a, b, acc) -> { ... } inside !fix. No stray tokens. Also need to use match !int_compare(n, 0) { Eq({}) -> { acc } Gt({}) -> { self(...)} ... }. The pattern syntax: In guide, match syntax is: match expr { Tag(var) -> { ... } | (_) -> { ... } }. For int_compare, result is Lt({}), Eq({}), Gt({}). So match !int_compare(n, 0) { Eq({}) -> { acc } Gt({}) -> { ... } Lt({}) -> { acc } }. Need spaces? Use newline.

Let's craft code:

let fib_sum = !fix((self, n, a, b, acc) -> {
  match !int_compare(n, 0) {
    Eq({}) -> { acc }
    Gt({}) -> { self(!int_subtract(n, 1), b, !int_add(a, b), !int_add(acc, a)) }
    Lt({}) -> { acc }
  }
}) in fib_sum(20, 1, 1, 0)

Check parentheses: fib_sum called with 4 args? It expects 5: n,a,b,acc. Actually we defined fib_sum as function with 5 parameters; but we pass 4, missing acc. Should pass initial acc 0. So fib_sum(20, 1, 1, 0). That's 4 args, we need 5: n, a, b, acc? Wait we have parameters (self, n, a, b, acc). So order: n, a, b, acc. That's 4 after self. So call fib_sum(20, 1, 1, 0). Yes that's correct.

Thus final expression returns sum.

Let's run.

Agent: Ran:
```eyg
let fib_sum = !fix((self, n, a, b, acc) -> {
  match !int_compare(n, 0) {
    Eq({}) -> { acc }
    Gt({}) -> { self(!int_subtract(n, 1), b, !int_add(a, b), !int_add(acc, a)) }
    Lt({}) -> { acc }
  }
}) in fib_sum(20, 1, 1, 0)
```
Result: invalid code
```
error: unexpected `fib_sum` at position 209 — the expression is complete but there are leftover tokens
hint: EYG uses function calls for operations (e.g. !int_add(a, b)), not infix operators

 7 | }) in fib_sum(20, 1, 1, 0)
           ^
```

Agent: (thinking) We need to compute sum of first 20 Fibonacci numbers starting with 1,1 (so sequence: 1,1,2,3,5,8,13,21,34,55,89,144,233,377,610,987,1597,2584,4181,6765). Sum should be? Let's calculate quickly: known sum of first n fib numbers = F_{n+2} -1. With starting F1=1, F2=1. So sum of first 20 = F22 -1. F22? Let's compute: F1=1,2=1,3=2,4=3,5=5,6=8,7=13,8=21,9=34,10=55,11=89,12=144,13=233,14=377,15=610,16=987,17=1597,18=2584,19=4181,20=6765,21=10946,22=17711. So sum = 17711 -1 = 17710.

We need to produce EYG program that returns integer 17710. Could compute directly using formula with recursion but we can just compute using recursion generate fib numbers and sum.

We had trouble with calling fib_sum; need correct syntax: after let binding, the final expression must be reference. In EYG, let binding returns the value of the final expression, not naming. To use fib_sum variable, must refer to it after let ends: The syntax: let fib_sum = !(fix(...)) in fib_sum(20,1,1,0). In earlier attempts we used that but error about leftover tokens suggests maybe missing parentheses around fib_sum call? Actually error says unexpected `fib_sum` after expression is complete. Means the parser expects end after let expression: `let name = value` is a statement but not a let expression? Wait syntax: `let name = value` at top-level is a binding, then you need a final expression. The syntax is `let name = value` (no 'in'), then subsequent lines. For block: `let x = 5 let y = 6 x`. So we shouldn't use `in`. So we can do:

let fib_sum = !fix((self, n, a, b, acc) -> {
  match !int_compare(n, 0) {
    Eq({}) -> { acc }
    Gt({}) -> { self(!int_subtract(n, 1), b, !int_add(a, b), !int_add(acc, a)) }
    Lt({}) -> { acc }
  }
})
fib_sum(20, 1, 1, 0)

Let's try.

Agent: Ran:
```eyg
let fib_sum = !fix((self, n, a, b, acc) -> {
  match !int_compare(n, 0) {
    Eq({}) -> { acc }
    Gt({}) -> { self(!int_subtract(n, 1), b, !int_add(a, b), !int_add(acc, a)) }
    Lt({}) -> { acc }
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
