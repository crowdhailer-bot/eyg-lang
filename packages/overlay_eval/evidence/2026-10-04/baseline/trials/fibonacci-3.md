# fibonacci, trial 3

Sum the first 20 Fibonacci numbers, starting with 1, 1.

Passed, score 100%.

## Checks

- **pass** computes 17710: run 3 computed the value

## Turn 1

User: Calculate the sum of the first 20 Fibonacci numbers, starting with 1, 1. Use an EYG program to calculate the sum and return it as an integer.

Agent: (thinking) We need to write an EYG program that calculates sum of first 20 Fibonacci numbers starting with 1,1. Need to use run effect. We need to output the integer result. The run tool executes EYG code, which can have top-level effects like Print? We need to return integer. Possibly we can output via Print but we need to return as response to user. According to guidelines, we should run a program that returns the integer. The effect system includes maybe returning value from run? The run tool returns whatever the program yields? Likely the program can use Print to display, but we need to capture. The instruction: "Use an EYG program to calculate the sum and return it as an integer." So we need the run result to contain integer. Perhaps EYG code can end with the integer value as result. We need to see guide. Let's fetch guide on "syntax".

Agent: (thinking) We need to calculate sum of first 20 Fibonacci numbers starting with 1,1. So sequence: F1=1,F2=1, then F3=2,... up to F20. We need compute sum via EYG program and return integer. We need to run a program that outputs the integer using Print? The instruction: "return it as an integer". In EYG, the program's final expression result is returned to us? The run tool returns whatever script produces? Likely the final expression's value will be returned. So we can have the script evaluate sum and output as integer (maybe just the integer expression). So we need to write an EYG program that calculates. Use recursion or fix and list generation. Could generate list of first 20 fib numbers. Use !fix to define fib function that returns nth fib. Then fold sum over range 1..20. Need list of ints 1..20: maybe use builtins for range? Not sure builtins list functions: check builtins_reference? Not loaded. Could generate list recursively using fix.

Simpler: compute sum via recurrence: sum_n = sum_{i=1..n} F_i. Could compute both fib and sum together via recursion: define function that returns pair (fib_n, sum_n). Using fix: (self, n) -> if n==1 => (1,1) ; if n==2 => (1,2) ; else compute (prev_fib, prev_sum) = self(n-1); fib_n = prev_fib + (prev_fib_of_prev?) Hmm we need previous fib as well. Better compute using two previous fibs: iterative fold.

We can generate list of fib via simple loop using list_fold: start with record {a:1,b:1, sum:2? Actually first two numbers sum=2 after two terms}. For i from 3 to 20: next = a+b; sum += next; update a=b, b=next. At end, sum is total.

Implement using !list_fold on list of indices from 3..20. Need list: maybe we can generate list of length 18 with dummy values using recursion: define make_range(start, end) returns list of ints from start to end inclusive. Use fix to build.

Pseudo:

let range = !fix((self, start, end) -> {
  match !int_compare(start, end) {
    Gt(_) -> { [] }
    | (_) -> { [start, ..self(!int_add(start,1), end)] }
  }
})
… (cut)

Agent: Ran:
```eyg
// Calculate sum of first 20 Fibonacci numbers starting with 1,1
let range = !fix((self, start, end) -> {
  match !int_compare(start, end) {
    Gt(_) -> { [] }
    | (_) -> { [start, ..self(!int_add(start, 1), end)] }
  }
})
let indices = range(3, 20)
let step = (state, _idx) -> {
  let next = !int_add(state.prev, state.curr)
  {
    prev: state.curr,
    curr: next,
    sum: !int_add(state.sum, next)
  }
}
let init = {prev: 1, curr: 1, sum: 2}
let result = !list_fold(step, init, indices)
result.sum
```
Result: type errors
```
type mismatch given: List(154) expected: ({prev: Integer, curr: Integer, sum: Integer, ..159} <..161>, 160 <..162>) -> {
  prev: Integer,
  curr: Integer,
  sum: Integer,
}
```

Agent: (thinking) The error: !list_fold expects function (accumulator, element) -> newAccumulator. We passed step defined as (state, _idx) -> {...}. That's okay. But we gave indices as List of integers from 3 to 20 inclusive? Actually we want 18 steps (since we already have first two terms). We need to generate range of count. The range we defined returns list [start, ..., end-1]? Wait: our range uses start to end exclusive? We used condition start >= end => [] else include start then recurse start+1, end. That yields list from start to end-1. For start=3, end=20, list includes numbers 3..19 (17 numbers). Actually we need 18 steps? Let's consider: first two terms sum=2 (1+1). We need to add next 18 terms to get first 20 total. Terms indices: 1:1,2:1,3:2,4:3,...20th term. So we need to loop 18 times (from term 3 to term 20 inclusive). So we need 18 iterations. Our indices list should length 18. If we generate range 3..21 (exclusive end 21) that'll give 3..20 inclusive length 18. So range(3,21). Let's adjust.

Also ensure !list_fold signature: maybe (!list_fold f init list) where f: (acc, elem) -> acc. Our step doesn't use elem, just ignore. That's fine.

Now need to run code again.

Agent: Ran:
```eyg
// Calculate sum of first 20 Fibonacci numbers starting with 1,1
let range = !fix((self, start, end) -> {
  match !int_compare(start, end) {
    Gt(_) -> { [] }
    | (_) -> { [start, ..self(!int_add(start, 1), end)] }
  }
})
let indices = range(3, 21) // will produce 3..20 inclusive (18 numbers)
let step = (state, _idx) -> {
  let next = !int_add(state.prev, state.curr)
  {prev: state.curr, curr: next, sum: !int_add(state.sum, next)}
}
let init = {prev: 1, curr: 1, sum: 2}
let result = !list_fold(step, init, indices)
result.sum
```
Result: type errors
```
type mismatch given: List(154) expected: ({prev: Integer, curr: Integer, sum: Integer, ..159} <..161>, 160 <..162>) -> {
  prev: Integer,
  curr: Integer,
  sum: Integer,
}
```

Agent: (thinking) We need to compute sum of first 20 Fibonacci numbers starting 1,1. That's sum of F1..F20. We can compute directly using math: sum_{i=1}^{n} F_i = F_{n+2} - 1. For n=20, sum = F22 -1. Fibonacci: let's compute quickly: F1=1,F2=1,F3=2,F4=3,F5=5,F6=8,F7=13,F8=21,F9=34,F10=55,F11=89,F12=144,F13=233,F14=377,F15=610,F16=987,F17=1597,F18=2584,F19=4181,F20=6765. Sum = let's add: could use formula: F22? Continue: F21 = 10946, F22 = 17711. So sum = 17711 -1 = 17710. So answer 17710. We need to compute via EYG program and return integer. Our previous attempt to generate range list seems troublesome. Could instead use recursion to generate list of Fibonacci numbers and sum. Could use !fix to generate Fibonacci list of length n, then fold sum.

Simplify: Use !fix to create a function that given (self, count, a, b, acc) returns sum. Use recursion: if count = 0 return acc, else next = a+b, recurse count-1 with b, next, acc+next (but need include starting numbers). Since we want first 20 numbers starting with 1,1 sum includes both first two. Could start with count=20, a=1,b=1, acc=0, then in each step add a to acc, then next step count-1, a=b, b=a+b. At end when count=0 return acc.

Implement: let fib_sum = !fix((self, n, a, b, acc) -> {\n match !int_compare(n, 0) {\n   Eq(_) -> { acc }\n   | (_) -> { let new_acc = !int_add(acc, a) let new_n = !int_subtract(n, 1) let new_a = b let new_b = !int_add(a, b) self(new_n, new_a, new_b, new_acc) }\n }\n})\nlet result = fib_sum(20, 1, 1, 0)\nresult

Need builtins: !int_compare returns Lt/Eq/Gt tags; we used Eq. Use match on tag. Use !int_subtract. Ensure correct.

Write EYG code.

Agent: Ran:
```eyg
let fib_sum = !fix((self, n, a, b, acc) -> {
  match !int_compare(n, 0) {
    Eq(_) -> { acc }
    | (_) -> {
        let new_acc = !int_add(acc, a)
        let new_n = !int_subtract(n, 1)
        let new_a = b
        let new_b = !int_add(a, b)
        self(new_n, new_a, new_b, new_acc)
    }
  }
})
let result = fib_sum(20, 1, 1, 0)
result
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
