# fibonacci, trial 3

Sum the first 20 Fibonacci numbers, starting with 1, 1.

Failed, score 0%.

## Checks

- **fail** computes 17710: no program computed 17710, no program computed a value

## Turn 1

User: Calculate the sum of the first 20 Fibonacci numbers, starting with 1, 1. Use an EYG program to calculate the sum and return it as an integer.

Agent: (thinking) We need to compute sum of first 20 Fibonacci numbers starting with 1,1 (so sequence: 1,1,2,3,5,8,...). Need to write EYG program to compute sum and return integer. Use recursion or fold. We can generate list of first 20 fib numbers then sum.

We don't have built-in list generation; can use recursion with fix to build list maybe.

Simpler: compute sum while generating fibs using recursion: define fib_sum = fix (self, n, a, b, acc) -> if n == 0 then acc else recur with n-1, b, a+b, acc+a. Starting with n=20, a=1, b=1, acc=0. At each step add a.

We need int comparisons & add etc.

Pseudo:

let fib_sum = !fix((self, n, a, b, acc) -> {
  match !int_compare(n, 0) {
    Lt(_) -> { acc } // shouldn't happen
    Eq(_) -> { acc }
    Gt(_) -> {
      let next_n = !int_subtract(n, 1);
      let next_a = b;
      let next_b = !int_add(a, b);
      let next_acc = !int_add(acc, a);
      !self(next_n, next_a, next_b, next_acc)
    }
  }
});

fib_sum(20, 1, 1, 0)

Return final integer.

Need to use match syntax: match result { Ok(x) -> { x } Error(_) -> { fallback } }. For int_compare result tags: Lt({}), Eq({}), Gt({}). So match !int_compare(n, 0) { Lt(_) -> { acc } Eq(_) -> { acc } Gt(_) -> { ... } }.

Implement.

Let's write code as string for run.

Agent: Error: Internal Server Error (ref: 6281db58-fcb2-4daf-a855-d344ede5ee41)

## Effects

- GET https://eyg.run/packages/pull? 200 (loading modules)
- GET https://eyg.run/packages/pull?since=14 200 (loading modules)

The agent finished.
