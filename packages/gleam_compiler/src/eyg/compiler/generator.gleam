//// JavaScript generation using generator functions.
////
//// The runtime is `runtime/generator.mjs`.
////
//// A lambda with an effect row that is not empty becomes a generator
//// function, a perform is a `yield` and an effectful call is a `yield*`.
//// Generators keep their own locals when suspended so no join points or
//// continuation frames are generated. A generator can not be copied, so a
//// resumption used twice replays the handled computation.

import eyg/compiler/anf.{type Block, type Expr}
import eyg/compiler/evidence
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string

type Terminal {
  FnReturn
  Assign(name: String)
}

pub fn render(program: Block) -> String {
  let #(body, _) = block(program, FnReturn, 0)
  string.concat([
    "(function ($rt) {\n",
    "\"use strict\";\n",
    "const {isGen: $isGen, pure: $pure, handle: $handle, list_fold: $list_fold, list_fold_pure: $list_fold_pure, binary_fold: $binary_fold, binary_fold_pure: $binary_fold_pure, fix: $fix, fix_pure: $fix_pure} = $rt;\n",
    evidence.builtins_prelude(),
    "return function* () {\n",
    body,
    "};\n",
    "})",
  ])
}

fn block(b: Block, term, i) -> #(String, Int) {
  case b {
    anf.Let(name, value, False, then) -> {
      let #(rest, i) = block(then, term, i)
      #("const " <> name <> " = " <> expr(value) <> ";\n" <> rest, i)
    }
    anf.Let(name, value, True, then) -> {
      let #(rest, i) = block(then, term, i)
      #(effectful(name, value) <> rest, i)
    }
    anf.Return(value, False) ->
      case term {
        FnReturn -> #("return " <> expr(value) <> ";\n", i)
        Assign(name) -> #(name <> " = " <> expr(value) <> ";\n", i)
      }
    anf.Return(value, True) -> {
      let temp = "g$" <> int.to_string(i)
      let code = effectful(temp, value)
      case term {
        FnReturn -> #(code <> "return " <> temp <> ";\n", i + 1)
        Assign(name) -> #(code <> name <> " = " <> temp <> ";\n", i + 1)
      }
    }
    anf.Match(name, subject, branches, otherwise, then) -> {
      let s = expr(subject)
      let #(bind, s) = case subject {
        anf.Var(_) -> #("", s)
        _ -> #("const " <> name <> "$s = " <> s <> ";\n", name <> "$s")
      }
      case then == anf.Return(anf.Var(name), False) {
        True -> {
          let #(c, i) = chain(s, branches, otherwise, term, i)
          #(bind <> c, i)
        }
        False -> {
          let #(c, i) = chain(s, branches, otherwise, Assign(name), i)
          let #(rest, i) = block(then, term, i)
          #(bind <> "let " <> name <> ";\n" <> c <> rest, i)
        }
      }
    }
  }
}

/// Bind the result of an effectful expression, delegating to any generator.
fn effectful(name, value) {
  case value {
    anf.Perform(label, lift) ->
      "const "
      <> name
      <> " = yield {l: "
      <> evidence.js_string(label)
      <> ", v: "
      <> expr(lift)
      <> "};\n"
    anf.Handle(label, handler, exec) ->
      "const "
      <> name
      <> " = yield* $handle("
      <> evidence.js_string(label)
      <> ", "
      <> expr(handler)
      <> ", "
      <> expr(exec)
      <> ");\n"
    anf.Builtin("list_fold" as builtin, args)
    | anf.Builtin("binary_fold" as builtin, args)
    | anf.Builtin("fix" as builtin, args) ->
      "const "
      <> name
      <> " = yield* $"
      <> builtin
      <> "("
      <> string.join(list.map(args, expr), ", ")
      <> ");\n"
    anf.Call(f, a) ->
      "let "
      <> name
      <> " = "
      <> expr(f)
      <> "("
      <> expr(a)
      <> ");\nif ($isGen("
      <> name
      <> ")) "
      <> name
      <> " = yield* "
      <> name
      <> ";\n"
    _ -> "const " <> name <> " = " <> expr(value) <> ";\n"
  }
}

fn chain(subject, branches, otherwise, term, i) {
  let #(parts, i) =
    list.fold(branches, #([], i), fn(acc, branch: anf.Branch) {
      let #(parts, i) = acc
      let #(body, i) = block(branch.body, term, i)
      let part =
        string.concat([
          "if (",
          subject,
          ".$T === ",
          evidence.js_string(branch.tag),
          ") {\n",
          "const ",
          branch.param,
          " = ",
          subject,
          ".$V;\n",
          body,
          "}",
        ])
      #([part, ..parts], i)
    })
  let #(last, i) = case otherwise {
    Some(#(param, body)) -> {
      let #(body, i) = block(body, term, i)
      #("{\nconst " <> param <> " = " <> subject <> ";\n" <> body <> "}\n", i)
    }
    None -> #("{\n$crash(\"no match\");\n}\n", i)
  }
  let code = case parts {
    [] -> last
    _ -> string.join(list.reverse(parts), " else ") <> " else " <> last
  }
  #(code, i)
}

fn expr(e: Expr) -> String {
  case e {
    anf.Var(name) -> name
    anf.Integer(n) ->
      case n < 0 {
        True -> "(" <> int.to_string(n) <> ")"
        False -> int.to_string(n)
      }
    anf.String(value) -> evidence.js_string(value)
    anf.Binary(value) -> evidence.binary(value)
    anf.Lambda(param, body, effectful) -> {
      let #(b, _) = block(body, FnReturn, 0)
      case effectful {
        True -> "(function* (" <> param <> ") {\n" <> b <> "})"
        False -> "((" <> param <> ") => {\n" <> b <> "})"
      }
    }
    anf.Call(f, a) -> "$pure(" <> expr(f) <> "(" <> expr(a) <> "))"
    anf.Builtin("list_fold", args) ->
      "$list_fold_pure(" <> string.join(list.map(args, expr), ", ") <> ")"
    anf.Builtin("binary_fold", args) ->
      "$binary_fold_pure(" <> string.join(list.map(args, expr), ", ") <> ")"
    anf.Builtin("fix", args) ->
      "$pure($fix(" <> string.join(list.map(args, expr), ", ") <> "))"
    anf.Builtin(name, args) ->
      "$" <> name <> "(" <> string.join(list.map(args, expr), ", ") <> ")"
    anf.Record([], None) -> "$unit"
    anf.Record(fields, base) -> {
      let fields =
        list.map(fields, fn(field) {
          evidence.key(field.0) <> ": " <> expr(field.1)
        })
      case base {
        None -> "({" <> string.join(fields, ", ") <> "})"
        Some(base) ->
          "({..." <> string.join([expr(base), ..fields], ", ") <> "})"
      }
    }
    anf.Select(from, label) -> expr(from) <> evidence.property(label)
    anf.Tag(label, value) ->
      "({$T: " <> evidence.js_string(label) <> ", $V: " <> expr(value) <> "})"
    anf.Cons(head, tail) -> "[" <> expr(head) <> ", " <> expr(tail) <> "]"
    anf.Tail -> "$nil"
    anf.Perform(label, _) ->
      "$crash(" <> evidence.js_string("pure perform " <> label) <> ")"
    anf.Handle(label, handler, exec) ->
      "$pure($handle("
      <> evidence.js_string(label)
      <> ", "
      <> expr(handler)
      <> ", "
      <> expr(exec)
      <> "))"
    anf.Crash(reason) -> "$crash(" <> evidence.js_string(reason) <> ")"
  }
}
