# eyg_compiler

[EYG](https://eyg.run) compiler that targets JavaScript.

```gleam
import eyg/compiler
import eyg/compiler/evidence
import gleam/dict

pub fn main() {
  let source = ir.let_("x", ir.integer(5), ir.variable("x"))
  // generalized evidence passing with every optimisation
  compiler.evidence(source, dict.new(), evidence.default())
  // effectful functions as JavaScript generators
  compiler.generator(source, dict.new())
}
```

The output is a function of a runtime that returns the program, run it with
the runtime created from the same options.

```js
import * as runtime from "eyg_compiler/eyg/compiler/runtime/evidence.mjs";
import * as browser from "eyg_compiler/eyg/compiler/platform/browser_runtime.mjs";

const rt = runtime.create();
const main = new Function("return " + code)()(rt);
await rt.run(main, browser.effects());
```

## Pipeline

1. `compiler.analyse` infers a type for every node.
2. `anf` names every call that can yield. A call can yield if the function
   called has an effect row that is not empty, so pure code is left alone.
3. `evidence` or `generator` renders JavaScript.
4. `runtime/*.mjs` implement handlers, the builtins are shared.
5. `platform/*` define and implement effects for a host.

## Evidence passing

The backend follows [Generalized Evidence Passing for Effect Handlers](https://www.microsoft.com/en-us/research/uploads/prod/2021/08/genev-icfp21.pdf).
`evidence.Options` turns each technique off so it can be measured.

- Evidence: `Map` constant time lookup, `Linked` insertion ordered, `Bubble` none.
- `tail` evaluates tail resumptive clauses in place.
- `inline` inlines binds with join points lifted to the top of the program.
- The runtime option `shortcut` keeps resumptions as an array of frames.
- `compiler.unchecked` compiles without types, every call is checked.

## Platforms

- `platform/browser` every effect of the touch grass browser harness, and
  `Sleep`, `Hash`, `CreateKey`, `Sign`, local storage and `Location`.
- `platform/dom`, `platform/signals`, `platform/webrtc` experimental designs
  for browser APIs, examples of each are in `examples/browser`.

## Development

```sh
gleam test
```

Tests run the spec suites, compare against the interpreter on programs from
the `soundness` generator, and type check the browser examples, for every
backend and option.

Benchmarks run each case in a fresh process.

```sh
gleam run -m eyg/compiler/bench -- compile
gleam run -m eyg/compiler/bench -- run counter10 full 2000
gleam run -m eyg/compiler/bench -- examples
bun install
bun run bin/bench_browser
bun run bin/bench_browser_apis
```

Results are in `bench/results`, the report is in `report`.
