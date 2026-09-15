import eyg/compiler
import eyg/compiler/evidence
import eyg/interpreter/value as v
import gleam/dict
import gleam/int
import gleam/json
import gleam/list
import gleam/string

pub type Backend {
  Evidence(options: evidence.Options, shortcut: Bool, selective: Bool)
  Generator(tail: Bool)
}

pub type Config {
  Config(name: String, backend: Backend)
}

/// The generator backend and every evidence passing combination the paper
/// measures, each with one optimisation turned off.
pub fn configs() {
  let full = evidence.default()
  [
    Config("full", Evidence(full, True, True)),
    Config(
      "linked",
      Evidence(evidence.Options(..full, evidence: evidence.Linked), True, True),
    ),
    Config(
      "bubble",
      Evidence(evidence.Options(..full, evidence: evidence.Bubble), True, True),
    ),
    Config(
      "no tail",
      Evidence(evidence.Options(..full, tail: False), True, True),
    ),
    Config(
      "no inline",
      Evidence(evidence.Options(..full, inline: False), True, True),
    ),
    Config("no shortcut", Evidence(full, False, True)),
    Config("not selective", Evidence(full, True, False)),
    Config("generator", Generator(True)),
    Config("generator no tail", Generator(False)),
  ]
}

pub fn evidence_name(evidence) {
  case evidence {
    evidence.Map -> "map"
    evidence.Linked -> "linked"
    evidence.Bubble -> "none"
  }
}

pub fn compile(source, config: Config) {
  case config.backend {
    Evidence(options:, selective: True, ..) ->
      compiler.evidence(source, dict.new(), options)
    Evidence(options:, selective: False, ..) ->
      compiler.unchecked(source, options)
    Generator(..) -> compiler.generator(source, dict.new())
  }
}

/// Compile and run, effects are label, lift and reply that must happen in order.
pub fn run(source, config: Config, effects) {
  let code = compile(source, config)
  let effects =
    list.map(effects, fn(effect) {
      let #(label, lift, reply) = effect
      #(label, canonical(lift), js_literal(reply))
    })
  case config.backend {
    Evidence(options:, shortcut:, ..) ->
      do_run(
        code,
        evidence_name(options.evidence),
        options.tail,
        shortcut,
        effects,
      )
    Generator(tail:) -> do_run_generator(code, tail, effects)
  }
}

@external(javascript, "./run_ffi.mjs", "run")
fn do_run(
  code: String,
  evidence: String,
  tail: Bool,
  shortcut: Bool,
  effects: List(#(String, String, String)),
) -> Result(String, String)

@external(javascript, "./run_ffi.mjs", "run_generator")
fn do_run_generator(
  code: String,
  tail: Bool,
  effects: List(#(String, String, String)),
) -> Result(String, String)

/// Canonical string for an interpreter value.
pub fn canonical(value) {
  case value {
    v.Integer(i) -> "I" <> int.to_string(i)
    v.String(s) -> "S" <> json.to_string(json.string(s))
    v.Binary(b) -> "B" <> string.join(bytes(b, []), ",")
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

fn bytes(b, acc) {
  case b {
    <<x, rest:bytes>> -> bytes(rest, [int.to_string(x), ..acc])
    _ -> list.reverse(acc)
  }
}

pub fn js_literal(value) {
  case value {
    v.Integer(i) -> int.to_string(i)
    v.String(s) -> evidence.js_string(s)
    v.Binary(b) -> "new Uint8Array([" <> string.join(bytes(b, []), ", ") <> "])"
    v.LinkedList(items) ->
      list.fold_right(items, "[]", fn(acc, item) {
        "[" <> js_literal(item) <> ", " <> acc <> "]"
      })
    v.Record(fields) ->
      "({"
      <> dict.to_list(fields)
      |> list.map(fn(field) {
        evidence.js_string(field.0) <> ": " <> js_literal(field.1)
      })
      |> string.join(", ")
      <> "})"
    v.Tagged(label, inner) ->
      "({$T: "
      <> evidence.js_string(label)
      <> ", $V: "
      <> js_literal(inner)
      <> "})"
    v.Closure(..) | v.Partial(..) -> "undefined"
  }
}
