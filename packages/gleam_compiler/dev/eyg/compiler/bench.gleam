//// Benchmarks for the compiled backends and the interpreter.
////
//// Every case runs in a fresh process, so the state of the JIT is not shared
//// between backends. From the package directory:
////
//// ```sh
//// gleam run -m eyg/compiler/bench -- compile
//// gleam run -m eyg/compiler/bench -- run fib full 30
//// ```
////
//// `compile` writes every compiled program to `bench/out` and the size and
//// time taken to `bench/results/compile.json`. `run` appends one line of JSON
//// to `bench/results/bun.jsonl`.

import eyg/compiler
import eyg/compiler/evidence
import eyg/interpreter/break
import eyg/interpreter/expression as r
import eyg/interpreter/value as v
import eyg/parser
import gleam/dict
import gleam/float
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/string
import simplifile

pub type Backend {
  Evidence(options: evidence.Options, shortcut: Bool, selective: Bool)
  Generator(tail: Bool)
}

/// Compiled backends, named as they are passed on the command line.
pub fn backends() {
  let full = evidence.default()
  [
    #("full", Evidence(full, True, True)),
    #(
      "linked",
      Evidence(evidence.Options(..full, evidence: evidence.Linked), True, True),
    ),
    #(
      "bubble",
      Evidence(evidence.Options(..full, evidence: evidence.Bubble), True, True),
    ),
    #("no_tail", Evidence(evidence.Options(..full, tail: False), True, True)),
    #(
      "no_inline",
      Evidence(evidence.Options(..full, inline: False), True, True),
    ),
    #("no_shortcut", Evidence(full, False, True)),
    #("not_selective", Evidence(full, True, False)),
    #("generator", Generator(True)),
    #("generator_no_tail", Generator(False)),
  ]
}

pub fn benchmarks() {
  [
    "fib",
    "counter",
    "counter1",
    "counter10",
    "host",
    "polymorphic",
    "mstate",
    "nqueens",
  ]
}

pub fn main() {
  case args() {
    ["compile"] -> compile_all()
    ["examples"] -> compile_examples()
    ["run", name, label, size] ->
      case int.parse(size) {
        Ok(size) -> run(name, label, size)
        Error(Nil) -> usage()
      }
    _ -> usage()
  }
}

fn usage() {
  io.println("usage: compile | examples | run <bench> <backend> <size>")
}

/// Compile the browser examples for `bin/bench_browser_apis`.
fn compile_examples() {
  let assert Ok(Nil) = simplifile.create_directory_all("examples/out")
  let assert Ok(files) = simplifile.read_directory("examples/browser")
  list.each(files, fn(file) {
    case string.ends_with(file, ".eyg") {
      False -> Nil
      True -> {
        let name = string.drop_end(file, 4)
        let assert Ok(text) = simplifile.read("examples/browser/" <> file)
        let assert Ok(#(source, _)) = parser.from_string(text)
        let full = compiler.evidence(source, dict.new(), evidence.default())
        let generator = compiler.generator(source, dict.new())
        let assert Ok(Nil) =
          simplifile.write("examples/out/" <> name <> ".full.js", full)
        let assert Ok(Nil) =
          simplifile.write(
            "examples/out/" <> name <> ".generator.js",
            generator,
          )
        Nil
      }
    }
  })
}

fn source(name) {
  let assert Ok(text) = simplifile.read("bench/" <> name <> ".eyg")
  let assert Ok(#(source, _)) = parser.from_string(text)
  source
}

fn path(name, label) {
  "bench/out/" <> name <> "." <> label <> ".js"
}

fn compile_all() {
  let assert Ok(Nil) = simplifile.create_directory_all("bench/out")
  let assert Ok(Nil) = simplifile.create_directory_all("bench/results")
  let entries =
    list.flat_map(benchmarks(), fn(name) {
      let source = source(name)
      list.map(backends(), fn(backend) {
        let #(label, backend) = backend
        let start = now()
        let code = case backend {
          Evidence(options:, selective: True, ..) ->
            compiler.evidence(source, dict.new(), options)
          Evidence(options:, selective: False, ..) ->
            compiler.unchecked(source, options)
          Generator(..) -> compiler.generator(source, dict.new())
        }
        let elapsed = now() -. start
        let assert Ok(Nil) = simplifile.write(path(name, label), code)
        json.object([
          #("bench", json.string(name)),
          #("backend", json.string(label)),
          #("compile", json.float(elapsed)),
          #("bytes", json.int(string.byte_size(code))),
        ])
      })
    })
  let assert Ok(Nil) =
    simplifile.write(
      "bench/results/compile.json",
      json.to_string(json.preprocessed_array(entries)),
    )
  Nil
}

fn run(name, label, size) {
  let result = case label {
    "interpreter" -> interpreter(name, size)
    _ ->
      case
        list.key_find(backends(), label),
        simplifile.read(path(name, label))
      {
        Ok(Evidence(options:, shortcut:, ..)), Ok(code) -> {
          let evidence = case options.evidence {
            evidence.Map -> "map"
            evidence.Linked -> "linked"
            evidence.Bubble -> "none"
          }
          time(code, "evidence", evidence, options.tail, shortcut, size, 10)
          |> warm(3)
        }
        Ok(Generator(tail:)), Ok(code) ->
          time(code, "generator", "", tail, False, size, 10) |> warm(3)
        _, _ -> Error("unknown backend or not compiled " <> label)
      }
  }
  let fields = [
    #("bench", json.string(name)),
    #("backend", json.string(label)),
    #("size", json.int(size)),
  ]
  let #(entry, line) = case result {
    Ok(#(value, times)) -> #(
      json.object(
        list.append(fields, [
          #("value", json.string(value)),
          #("times", json.array(times, json.float)),
          #("median", json.float(median(times))),
        ]),
      ),
      string.pad_start(
        float.to_string(float.to_precision(median(times), 2)),
        12,
        " ",
      )
        <> " ms  "
        <> string.slice(value, 0, 30),
    )
    Error(reason) -> #(
      json.object(list.append(fields, [#("error", json.string(reason))])),
      "error " <> reason,
    )
  }
  io.println(
    string.pad_end(name, 12, " ")
    <> string.pad_end(label, 18, " ")
    <> string.pad_start(int.to_string(size), 8, " ")
    <> line,
  )
  let assert Ok(Nil) =
    simplifile.append("bench/results/bun.jsonl", json.to_string(entry) <> "\n")
  Nil
}

fn warm(result, n) {
  case result {
    Ok(#(value, times)) -> Ok(#(value, list.drop(times, n)))
    Error(reason) -> Error(reason)
  }
}

/// The interpreter is slow, it is run three times and the first dropped.
fn interpreter(name, size) {
  let assert Ok(f) = r.execute(source(name), [])
  let runs =
    list.map([1, 2, 3], fn(_) {
      let start = now()
      let result = interpret(r.call(f, [#(v.Integer(size), #(0, 0))]))
      #(result, now() -. start)
    })
  case runs {
    [_, #(Ok(value), a), #(_, b)] -> Ok(#(canonical(value), [a, b]))
    [#(Error(reason), _), ..] -> Error(reason)
    _ -> Error("interpreter failed")
  }
}

fn interpret(return) {
  case return {
    Ok(value) -> Ok(value)
    Error(#(break.UnhandledEffect("Random", v.Integer(max)), _, env, k)) ->
      interpret(r.resume(v.Integer(max - 1), env, k))
    Error(#(reason, _, _, _)) -> Error(string.inspect(reason))
  }
}

pub fn median(times) {
  let sorted = list.sort(times, float.compare)
  case list.drop(sorted, list.length(sorted) / 2) {
    [m, ..] -> m
    [] -> 0.0
  }
}

/// The same format as `runtime/inspect.mjs`.
fn canonical(value) {
  case value {
    v.Integer(i) -> "I" <> int.to_string(i)
    v.String(s) -> "S" <> json.to_string(json.string(s))
    v.Binary(_) -> "B"
    v.LinkedList(items) ->
      "L[" <> string.join(list.map(items, canonical), ",") <> "]"
    v.Record(fields) ->
      "R{"
      <> dict.to_list(fields)
      |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
      |> list.map(fn(field) {
        json.to_string(json.string(field.0)) <> ":" <> canonical(field.1)
      })
      |> string.join(",")
      <> "}"
    v.Tagged(label, inner) -> "T" <> label <> "(" <> canonical(inner) <> ")"
    v.Closure(..) | v.Partial(..) -> "F"
  }
}

@external(javascript, "./bench_ffi.mjs", "args")
fn args() -> List(String)

@external(javascript, "./bench_ffi.mjs", "now")
fn now() -> Float

@external(javascript, "./bench_ffi.mjs", "time")
fn time(
  code: String,
  kind: String,
  evidence: String,
  tail: Bool,
  shortcut: Bool,
  size: Int,
  iterations: Int,
) -> Result(#(String, List(Float)), String)
