# Overlay evals

Start with a real model returning one pure EYG program through Overlay's `run`
tool. The eval uses the shared Overlay instructions, with the syntax and builtin
guides inline because no effects or imports are available. Type errors stop
execution. The only grading check is equality with the expected EYG value.

```sh
cd packages/overlay_eval
OLLAMA_API_KEY=... gleam run -m overlay/eval/pure -- ollama:gpt-oss:120b
# Or a model served locally:
gleam run -m overlay/eval/pure -- ollama-local:qwen3.5:4b
```

The task asks for the sum of the first 20 Fibonacci numbers starting with `1, 1`.
The program must return the integer `17710`. Its source and pass/fail are printed;
a failure exits nonzero. The answer is never included in the model request.

`gleam test` checks the evaluator offline. These tests do not substitute for
running the command against a real provider.
