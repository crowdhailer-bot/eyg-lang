# Live pure Fibonacci eval

Run on 2026-09-26 against Ollama Cloud, model `gpt-oss:120b`.
Both requests used the unmodified `overlay/eval/pure` prompt, Overlay's shared
instructions and run tool, and the repository's syntax and builtins guides.
Each attempt is a fresh single request, with no correction or expected answer
sent to the model. Credentials are supplied only through `OLLAMA_API_KEY`.

```sh
gleam run -m overlay/eval/pure -- ollama:gpt-oss:120b
```

Two calls were made. This demonstrates a successful live run, not a reliability
estimate. The first response returned `28655` and failed; the second returned
`17710` and passed. In both cases the source parsed and type-checked as pure EYG.

## Attempt 1: fail

```eyg
let rec_sum = !fix((self, n, sum, a, b) -> {
  match !int_compare(n, 0) {
    Eq(_) -> { sum }
    | (_) -> {
        let next = !int_add(a, b)
        self(!int_subtract(n, 1), !int_add(sum, next), b, next)
      }
  }
})
rec_sum(20, 0, 0, 1)
```

`FAIL: expected 17710, got 28655` (exit 1).

## Attempt 2: pass

```eyg
let sum_fib = !fix((self, count, a, b) -> {
  match !int_compare(count, 0) {
    Eq(_) -> { 0 }
    | (_) -> {
      match !int_compare(count, 1) {
        Eq(_) -> { a }
        | (_) -> {
          let next = !int_add(a, b)
          let rest = self(!int_subtract(count, 1), b, next)
          !int_add(a, rest)
        }
      }
    }
  }
})
sum_fib(20, 1, 1)
```

`PASS: Fibonacci sum = 17710` (exit 0).

## Full session

The same model also passed `suites/fibonacci.eyg` through the full Overlay
session on 2026-09-26. It made six model calls, fetched the local syntax guide,
received program errors through tool feedback, and computed `17710` in run 5.
The trial had only the `Computes(17710)` check and used no model judge.

```sh
gleam run -m overlay/eval -- run suites/fibonacci.eyg \
  --model ollama:gpt-oss:120b --record evals/fibonacci-cassettes
```

Output:

```text
Running fibonacci with context none
pass fibonacci #1 (6 model calls)
Pass rate 100% over 1 tasks
```
