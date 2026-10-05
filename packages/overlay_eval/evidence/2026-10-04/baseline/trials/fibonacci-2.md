# fibonacci, trial 2

Sum the first 20 Fibonacci numbers, starting with 1, 1.

Passed, score 100%.

## Checks

- **pass** computes 17710: run 1 computed the value

## Turn 1

User: Calculate the sum of the first 20 Fibonacci numbers, starting with 1, 1. Use an EYG program to calculate the sum and return it as an integer.

Agent: (thinking) We need to write EYG program that calculates sum of first 20 Fibonacci numbers starting with 1,1. Need to output integer. How to output? Use Print? But we need to return it as integer. In EYG, the program's result is the value of the last expression? Probably we need to use Print to output, but the instruction: "return it as an integer". In this system, the effect results we can capture. Possibly we can simply evaluate expression that yields sum, then the run tool will return that result. Use EYG code that calculates sum and then final expression is sum. Let's read guide for EYG.

Agent: (thinking) We need to compute sum of first 20 Fibonacci numbers starting with 1,1. So sequence: F1=1, F2=1, then F3=2, F4=3, F5=5, F6=8, F7=13, F8=21, F9=34, F10=55, F11=89, F12=144, F13=233, F14=377, F15=610, F16=987, F17=1597, F18=2584, F19=4181, F20=6765. Sum? Let's compute quickly with Python mental or quick compute: we can also know formula sum_{i=1}^{n} F_i = F_{n+2} - 1. For Fibonacci starting 1,1, that holds. So sum first 20 = F22 -1. F21? Let's compute: we have F20=6765, F21=10946 (6765+4181), F22=17711 (10946+6765). So sum = 17711 -1 = 17710. So answer integer 17710.

We need to produce EYG program that calculates and returns it as integer, not just printing. The program should output the integer as final expression. Use recursion maybe via !fix or use loop with list. Simpler: we can generate list of first 20 using iteration via a helper that builds list by folding. But we can directly compute using known formula using recursion to compute Fibonacci. Let's write a function fib(n) returns nth Fibonacci (1-indexed). Then sum via fold over range list 1..20. There is no built-in range list but we could generate list recursion.

Simpler: compute directly using iteration with let binding and loop emulated via recursion. Use !fix to define a loop that accumulates sum and previous two numbers. Something like:

let sum_fib = !fix((self, i, a, b, acc) -> {
  match !int_compare(i, 0) {
    Eq(_) -> { acc }
    | (_) -> {
      let new_acc = !int_add(acc, a)
      let next_a = b
      let next_b = !int_add(a, b)
      self(!int_subtract(i, 1), next_a, next_b, new_acc)
    }
  }
})
sum_fib(20, 1, 1, 0)

But we need to ensure pattern matching tags: !int_compare returns Lt({})|Eq({})|Gt({}). So match accordingly. Use Eq. For >0 we use Gt or maybe not required. Simpler: compare i with 0; if Eq => acc else continue.

So EYG script final expression is sum_fib(20,1,1,0). Need to use let to bind sum_fib then expression.

Let's write program:

let sum_fib = !fix((self, i, a, b, acc) -> {… (cut)

Agent: Ran:
```eyg
let sum_fib = !fix((self, i, a, b, acc) -> {
  match !int_compare(i, 0) {
    Eq(_) -> { acc }
    | (_) -> {
      let new_acc = !int_add(acc, a)
      let next_a = b
      let next_b = !int_add(a, b)
      self(!int_subtract(i, 1), next_a, next_b, new_acc)
    }
  }
})
sum_fib(20, 1, 1, 0)
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
