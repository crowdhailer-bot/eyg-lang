# fibonacci, trial 3

Sum the first 20 Fibonacci numbers, starting with 1, 1.

Passed, score 100%.

## Checks

- **pass** computes 17710: run 1 computed the value

## Turn 1

User: Calculate the sum of the first 20 Fibonacci numbers, starting with 1, 1. Use an EYG program to calculate the sum and return it as an integer.

Agent: (thinking) We need to run an EYG program to compute the sum of first 20 Fibonacci numbers (starting with 1,1). Need to read syntax guide. Let's read guide for syntax.

Agent: (thinking) We need to calculate sum of first 20 Fibonacci numbers starting with 1,1. So sequence: F1=1, F2=1, then F3=2, F4=3, F5=5, F6=8, F7=13, F8=21, F9=34, F10=55, F11=89, F12=144, F13=233, F14=377, F15=610, F16=987, F17=1597, F18=2584, F19=4181, F20=6765. Sum =? Known formula: sum_{i=1..n} F_i = F_{n+2} - 1. For n=20, sum = F22 -1. F21 = 10946, F22 = 17711. So sum = 17711 -1 = 17710. Let's verify: compute quickly: sum up: let's add: 1+1=2, +2=4, +3=7, +5=12, +8=20, +13=33, +21=54, +34=88, +55=143, +89=232, +144=376, +233=609, +377=986, +610=1596, +987=2583, +1597=4180, +2584=6764, +4181=10945, +6765=17710. Yes.

We need to write an EYG program to compute sum, using recursion/fix and list fold maybe. Simpler: generate list of first 20 fib numbers via recursion, then fold sum.

We need to know builtins: there's !list_range? Not sure. Use !list_fold, !int_add etc. Also could compute directly using formula using !int_add, !int_multiply, but need fibonacci numbers.

Simplify: Use !fix to generate fib recursively: a function that given n returns pair (F_n, sum_n). Or compute sum directly via formula using int_fib? Not known.

Better: write a recursive function fib_sum(n) that returns sum of first n fib numbers. Using recursion formula: sum_n = F_{n+2} -1. Could compute F_{n+2} using fast recursion.

We can implement fib function using !fix: fib(self, k) returns F_k. base: if k==1 or 2 return 1 else return self(k-1)+self(k-2). Use !int_compare, !int_subtract, !int_add, etc.

Then compute sum = fib(n+2) -1.

Let's write program.

Need to remember builtins for compare: !int_compare returns tag Lt, Eq, Gt? According to docs, probably returns tags. Use match.

We'll write:

let fib = !fix((self, k) -> {
  match !int_compare(k, 1) {
    Eq(_) -> { 1 }
    | (_) -> {
      match !int_compare(k, 2) {
        Eq(_) -> { 1 }
        | (_) -> {
          let a = self(!int_subtract(k, 1))
          let b = self(!int_subtract(k, 2))
          !int_add(a, b)
        }
      }
    }
  }
})

l… (cut)

Agent: Ran:
```eyg
let fib = !fix((self, k) -> {
  match !int_compare(k, 1) {
    Eq(_) -> { 1 }
    | (_) -> {
      match !int_compare(k, 2) {
        Eq(_) -> { 1 }
        | (_) -> {
          let a = self(!int_subtract(k, 1))
          let b = self(!int_subtract(k, 2))
          !int_add(a, b)
        }
      }
    }
  }
})
let n = 20
!int_subtract(fib(!int_add(n, 2)), 1)
```
Result: computed
```
17710
```

Agent: The sum of the first 20 Fibonacci numbers (starting 1, 1) is **17710**.

## Effects

- GET https://eyg.run/packages/pull? 200 (loading modules)
- GET https://eyg.run/packages/pull?since=14 200 (loading modules)
- GET https://eyg.run/guides/eyg-syntax-guide.md 200

The agent finished.
