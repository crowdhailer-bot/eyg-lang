# Eat Your Greens (EYG)

EYG is a scripting language with structural typing, managed effects and immutable dependencies.

Install the CLI with:

```sh
curl -fsSL https://eyg.run/install | bash
```

A hello world example script.

```eyg
#!/usr/bin/env eyg
{
  script: (_) -> {
    let _ = perform StandardOut("Hello, World!\n")
    0
  }
}
```

Update permissions `chmod +x entry.eyg`.
Then run the script directly `./entry.eyg`.

## Scripts and modules

Any file containing valid source code is a module.
The file containing just `5` is a module.

An EYG script is a function from the list of script arguments to a returned exit code.
The type of a script function is `(List(String)) -> Integer`

A valid script module has a script function as a field of a record.
The type of a script file/module is `{script: (List(String)) -> Int, ..}`.

Run a script using `eyg script path/to/script`.

### Entryfiles

An entryfile is the first module run.
It can be a valid script file and, because records are extensible, have other fields.
For example a module with a "shell" field is a valid shell config.

Top-level modules may be executable and have a shebang (`#!/usr/bin/env eyg`).


The example below works as a script and shell config.

```eyg
// entry.eyg
let tests = import "./path/to/tests.eyg"
{
  script: (arguments) -> {
    let counts = test({})
    match !equal(counts.failed, 0) {
      True({}) -> { 0 }
      False({}) -> { 1 }
    }
  },
  shell: (_) -> {
    perform Break({})
  }
}
```

Start the shell with `eyg shell entry.eyg`
Run all the tests with `eyg script entry.eyg`

EYG is a strongly typed replacement for `bash`, `make` and shell tools in general.
Type check your whole project, application and scripts with `eyg check entry.eyg`

### Pure evaluation

Use `eyg eval` for evaluating pure values, no side effects, and printing the result.

## Resources

- For the full CLI reference see [`packages/gleam_cli/README.md`](./packages/gleam_cli/README.md).
- To create, protect, and use publishing identities see [`guides/managing_signatories.md`](./guides/managing_signatories.md).
- The language syntax is described in [`guides/syntax.md`](./guides/syntax.md).
- Every `!builtin` is catalogued in [`guides/builtins_reference.md`](./guides/builtins_reference.md).
- Full effect reference is in [`./guides/cli_effects_reference.md`](./guides/cli_effects_reference.md).
- File and import path resolution is explained in [`guides/file_resolution.md`](./guides/file_resolution.md).
- To install from source see [`./guides/install_from_source.md`](./guides/install_from_source.md).

## Packages

The intermediate representation (IR) of EYG is a minimal tree and is the stable interface for writing EYG programs. 
Type checking, syntax, evaluation or compilation are optional components built on this foundation.

This repository contains the language definition, implementation, website and package hub.

EYG makes it easy to swap out components of the toolchain.
A sensible reason could be to create a runtime with a unique set of effects, i.e. embed EYG in a game or website.
Another reason could be to imagine your own syntax, or even visual editor, and reuse the EYG interpreter and packages.

- [spec](./spec) A JSON spec of all evaluation rules. Compiler and interpreter implementations should use this as their test suite.
- [gleam_analysis](./packages/gleam_analysis/) Type inference for expressions, effects and scope variables in EYG programs.
- [gleam_cli](./packages/gleam_cli/) The CLI for running EYG programs and interacting with the EYG hub.
- [gleam_hub](./packages/gleam_hub/) Schemas, encoders and decoders for the EYG Hub API. (Unpublished)
- [gleam_ir](./packages/gleam_ir/) Data structures for the EYG IR. This is the original implementation of EYG.
- [gleam_interpreter](./packages/gleam_interpreter/) A Gleam interpreter for EYG targeting JavaScript. Runs in the browser and on the server.
- [gleam_embed](./packages/gleam_embed/) Run programs, keep a typed shell, exchange JSON values, and add an agent to a JavaScript host written in Gleam.
- [embed_js](./packages/embed_js/) Build one ES module with TypeScript declarations for JavaScript hosts.
- [ash_eyg](./packages/ash_eyg/) Expose Ash resource actions as typed effects, with Mix tasks and application-owned package caches.
- [gleam_parser](./packages/gleam_parser/) Parser for a curly braces syntax for EYG IR.
- [hub](./packages/hub/) Backend application for [eyg.run](https://eyg.run). Stores modules, packages and signatories.
- [morph](./packages/morph/) Higher level AST and transformation functions for structural edits. (Unpublished)
- [touch_grass](./packages/touch_grass/) Common effect definitions (types, decoders and encoders) for your Eat Your Greens (EYG) runtime.
- [untethered](./packages/untethered/) Location independent datastructures to immutably record decisions. Foundation of EYG hub package signing. (Unpublished)
- [vscode-eyg](./packages/vscode-eyg/) VS Code extension and canonical TextMate grammar, also used by the web guides.
- [website](./packages/website/) Website for documentation, guides and introduction on [eyg.run](https://eyg.run).

## Embedding EYG

A host supplies the effects a script may perform. EYG checks the complete script
against those effects before running it. The interpreter, type checker, parser,
and hub cache can also be used separately; hosts choose the pieces they need.

Start with the browser examples, which use the shared shell and agent libraries.
The server examples add runtime-specific setup:

| Host | Example | Setup and walkthrough |
| --- | --- | --- |
| Gleam / Lustre | [TodoMVC](./examples/todomvc_lustre/) | [Typed effects, shell, and agent](./guides/embedding_todomvc.md) |
| JavaScript / TypeScript | [TodoMVC](./examples/todomvc_typescript/) | [One bundled ES module](./guides/embedding_typescript.md) |
| Existing Gleam browser app | [Hashi](./examples/hashi/) | [Script an unchanged game](./guides/embedding_hashi.md); requires Gleam 1.18.1+ |
| nginx / njs | [Request handler](./examples/njs/) | [Compile EYG to a module](./guides/embedding_njs.md); requires Docker |
| Erlang / OTP | [Counters](./examples/erl_counter/) | [Effects, supervision, and cached packages](./posts/embedding-eyg-in-erlang/index.md) |
| Elixir / Phoenix | [LiveView counters](./examples/phoenix_counters/) | [A script editor in an application](./posts/embedding-eyg-in-elixir/index.md) |
| Elixir / Ash | [Helpdesk](./examples/helpdesk/) | [Derive and restrict effects from resources](./posts/using-eyg-in-ash/index.md) |

The examples include tests and recorded demonstrations. The BEAM hosts currently
build the EYG libraries from this checkout with Gleam; their READMEs describe the
setup. [CONTRIBUTING.md](./CONTRIBUTING.md) lists validation commands.

## EYG packages
[eyg_packages](./eyg_packages/)

The source for packages maintained as a standard library i.e. `standard` and `json`.
Other packages in this collection are for demo purposes i.e. `catfact`
The [`overlay`](./eyg_packages/overlay/) package contains access policy helpers for CLI effects.

## Philosophy

**Building better languages and tools; for some measure of better.**

"Eat Your Greens" is a reference to the idea that eating vegetables is good for you, however the benefit is only realised at some later time.

Projects in this repo introduce extra contraints, over regular programming languages and tools. By doing so more guarantees about the system built on them can be given.

### Previous experiments

Over the last few years the Eat Greens Principle to build actor systems, datalog engines.
A record of these experiments is at https://petersaxton.uk/log/.
The code for these experiments is no longer available if you want to ask more about them reach out to me directly
