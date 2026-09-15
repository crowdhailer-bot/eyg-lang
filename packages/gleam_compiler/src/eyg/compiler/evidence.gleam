//// JavaScript generation using generalized evidence passing.
////
//// The runtime is `runtime/evidence.mjs`, it must be created with options
//// that match the options used to compile.
////
//// A checked call is compiled with bind inlining and join point sharing,
//// section 2.10 of the paper. The fast path continues inline, the slow path
//// pushes a frame that calls a join point, a function lifted to the top of
//// the program that takes every free variable as an argument. A join point
//// continues with the next join point rather than inlining, so code size is
//// linear in the number of checked calls.

import eyg/compiler/anf.{type Block, type Expr}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/set.{type Set}
import gleam/string

pub type Evidence {
  /// Evidence vector as an object keyed by label, constant time lookup.
  Map
  /// Insertion ordered linked list of evidence, linear lookup.
  Linked
  /// No evidence, every perform yields up to the handler.
  Bubble
}

pub type Options {
  Options(evidence: Evidence, tail: Bool, inline: Bool)
}

pub fn default() {
  Options(evidence: Map, tail: True, inline: True)
}

type Env {
  Env(options: Options, prefix: String)
}

type Out {
  Out(joins: List(String), done: Set(String))
}

/// What to do with the value of a block.
type Terminal {
  /// Return from the current function.
  FnReturn
  /// Assign to the variable of a match and continue after the match.
  Assign(name: String, join: Option(#(String, List(String))))
  /// Call a join point with the value.
  Jump(join: String, args: List(String))
}

/// Inside a join point checked calls do not inline their continuation.
type Mode {
  Fast
  Joined
}

pub fn render(program: Block, options: Options) -> String {
  let env = Env(options, "")
  let #(body, out) = block(program, FnReturn, Fast, env, Out([], set.new()))
  string.concat([
    "(function ($rt) {\n",
    "\"use strict\";\n",
    "const $s = $rt.s;\n",
    "const {perform: $perform, performWith: $performWith, handle: $handle, extend: $extend, bind: $bind, tailResumptive: $tr, list_fold: $list_fold, binary_fold: $binary_fold, fix: $fix, fix_pure: $fix_pure} = $rt;\n",
    builtins_prelude(),
    string.concat(list.reverse(out.joins)),
    "return function () {\n",
    body,
    "};\n",
    "})",
  ])
}

pub fn builtins_prelude() {
  let names = [
    "unit", "nil", "crash", "equal", "never", "int_compare", "int_add",
    "int_subtract", "int_multiply", "int_divide", "int_absolute", "int_parse",
    "int_to_string", "string_append", "string_split", "string_split_once",
    "string_replace", "string_uppercase", "string_lowercase",
    "string_starts_with", "string_ends_with", "string_length",
    "string_to_binary", "string_from_binary", "list_pop", "binary_from_integers",
    "binary_size", "binary_concat", "binary_compare",
  ]
  "const {"
  <> string.join(list.map(names, fn(n) { n <> ": $" <> n }), ", ")
  <> "} = $rt.builtins;\n"
}

fn block(b: Block, term, mode, env: Env, out) -> #(String, Out) {
  case b {
    anf.Let(name, value, False, then) -> {
      let #(v, out) = expr(value, env, out)
      let #(rest, out) = block(then, term, mode, env, out)
      #("const " <> name <> " = " <> v <> ";\n" <> rest, out)
    }
    anf.Let(name, value, True, then) ->
      case env.options.inline {
        True -> checked(name, value, then, term, mode, env, out)
        False -> {
          let #(v, out) = expr(value, env, out)
          let #(rest, out) = block(then, term, Fast, env, out)
          let code =
            "return $bind("
            <> v
            <> ", ("
            <> name
            <> ") => {\n"
            <> rest
            <> "});\n"
          #(code, out)
        }
      }
    anf.Return(value, effectful) ->
      return(value, effectful, term, mode, env, out)
    anf.Match(name, subject, branches, otherwise, then) ->
      match(name, subject, branches, otherwise, then, term, mode, env, out)
  }
}

fn checked(name, value, then, term, mode, env: Env, out) {
  let #(v, out) = expr(value, env, out)
  let join = env.prefix <> "$j_" <> name
  let args = join_args(then, term, name)
  let params = list.append(args, [name])
  let out = ensure_join(join, params, then, term, env, out)
  let call = join <> "(" <> string.join(params, ", ") <> ")"
  let head =
    string.concat([
      "const ", name, " = ", v, ";\n", "if ($s.y !== null) { $extend((", name,
      ") => ", call, "); return; }\n",
    ])
  case mode {
    Fast -> {
      let #(rest, out) = block(then, term, Fast, env, out)
      #(head <> rest, out)
    }
    Joined -> #(head <> "return " <> call <> ";\n", out)
  }
}

fn join_args(then, term, bound) {
  let free = set.delete(anf.free_block(then), bound)
  let free = case term {
    FnReturn -> free
    Assign(_, None) -> free
    Assign(_, Some(#(_, args))) | Jump(_, args) ->
      set.union(free, set.from_list(args))
  }
  set.to_list(free) |> list.sort(string.compare)
}

fn ensure_join(join, params, then, term, env: Env, out: Out) {
  case set.contains(out.done, join) {
    True -> out
    False -> {
      let out = Out(..out, done: set.insert(out.done, join))
      let #(body, out) = block(then, joined(term), Joined, env, out)
      let code =
        "function "
        <> join
        <> "("
        <> string.join(params, ", ")
        <> ") {\n"
        <> body
        <> "}\n"
      Out(..out, joins: [code, ..out.joins])
    }
  }
}

fn joined(term) {
  case term {
    FnReturn -> FnReturn
    Jump(..) -> term
    Assign(_, Some(#(join, args))) -> Jump(join, args)
    Assign(_, None) -> panic as "assignment without join point can not yield"
  }
}

fn return(value, effectful, term, mode, env: Env, out) {
  case term, effectful {
    FnReturn, _ -> {
      let #(v, out) = expr(value, env, out)
      #("return " <> v <> ";\n", out)
    }
    Assign(name, _), False -> {
      let #(v, out) = expr(value, env, out)
      #(name <> " = " <> v <> ";\n", out)
    }
    Jump(join, args), False -> {
      let #(v, out) = expr(value, env, out)
      let args = string.join(list.append(args, [v]), ", ")
      #("return " <> join <> "(" <> args <> ");\n", out)
    }
    // The value must be checked before it is passed on.
    Assign(name, _), True -> {
      let temp = name <> "$v"
      let then = anf.Return(anf.Var(temp), False)
      block(anf.Let(temp, value, True, then), term, mode, env, out)
    }
    Jump(join, _), True -> {
      let temp = string.replace(join, "$", "_") <> "$v"
      let then = anf.Return(anf.Var(temp), False)
      block(anf.Let(temp, value, True, then), term, mode, env, out)
    }
  }
}

fn match(name, subject, branches, otherwise, then, term, mode, env: Env, out) {
  let #(s, bind_subject, out) = case subject {
    anf.Var(x) -> #(x, "", out)
    _ -> {
      let #(v, out) = expr(subject, env, out)
      let x = name <> "$s"
      #(x, "const " <> x <> " = " <> v <> ";\n", out)
    }
  }
  case then == anf.Return(anf.Var(name), False) {
    True -> {
      let #(c, out) = chain(s, branches, otherwise, term, mode, env, out)
      #(bind_subject <> c, out)
    }
    False -> {
      let yields =
        list.any(branches, fn(b: anf.Branch) { anf.yields(b.body) })
        || case otherwise {
          Some(#(_, body)) -> anf.yields(body)
          None -> False
        }
      case yields, env.options.inline {
        False, _ -> {
          let #(c, out) =
            chain(s, branches, otherwise, Assign(name, None), Fast, env, out)
          let #(rest, out) = block(then, term, mode, env, out)
          #(bind_subject <> "let " <> name <> ";\n" <> c <> rest, out)
        }
        True, True -> {
          let join = env.prefix <> "$m_" <> name
          let args = join_args(then, term, name)
          let params = list.append(args, [name])
          let out = ensure_join(join, params, then, term, env, out)
          let branch_term = Assign(name, Some(#(join, args)))
          let #(c, out) =
            chain(s, branches, otherwise, branch_term, mode, env, out)
          let #(rest, out) = case mode {
            Fast -> block(then, term, Fast, env, out)
            Joined -> #(
              "return " <> join <> "(" <> string.join(params, ", ") <> ");\n",
              out,
            )
          }
          #(bind_subject <> "let " <> name <> ";\n" <> c <> rest, out)
        }
        True, False -> {
          let join = env.prefix <> "$m_" <> name
          let args = join_args(then, term, name)
          let params = list.append(args, [name])
          let out = ensure_join(join, params, then, term, env, out)
          let #(c, out) =
            chain(s, branches, otherwise, Jump(join, args), Fast, env, out)
          #(bind_subject <> c, out)
        }
      }
    }
  }
}

fn chain(subject, branches, otherwise, term, mode, env, out) {
  let #(parts, out) =
    list.fold(branches, #([], out), fn(acc, branch: anf.Branch) {
      let #(parts, out) = acc
      let #(body, out) = block(branch.body, term, mode, env, out)
      let part =
        string.concat([
          "if (",
          subject,
          ".$T === ",
          js_string(branch.tag),
          ") {\n",
          "const ",
          branch.param,
          " = ",
          subject,
          ".$V;\n",
          body,
          "}",
        ])
      #([part, ..parts], out)
    })
  let #(last, out) = case otherwise {
    Some(#(param, body)) -> {
      let #(body, out) = block(body, term, mode, env, out)
      #("{\nconst " <> param <> " = " <> subject <> ";\n" <> body <> "}\n", out)
    }
    None -> #("{\n$crash(\"no match\");\n}\n", out)
  }
  let code = case parts {
    [] -> last
    _ -> string.join(list.reverse(parts), " else ") <> " else " <> last
  }
  #(code, out)
}

fn expr(e: Expr, env: Env, out) -> #(String, Out) {
  case e {
    anf.Var(name) -> #(name, out)
    anf.Integer(n) ->
      case n < 0 {
        True -> #("(" <> int.to_string(n) <> ")", out)
        False -> #(int.to_string(n), out)
      }
    anf.String(value) -> #(js_string(value), out)
    anf.Binary(value) -> #("new Uint8Array([" <> bytes(value, []) <> "])", out)
    anf.Lambda(param, body, _) -> lambda(param, body, env, out)
    anf.Call(f, a) -> {
      let #(f, out) = expr(f, env, out)
      let #(a, out) = expr(a, env, out)
      #(f <> "(" <> a <> ")", out)
    }
    anf.Builtin(name, args) -> {
      let #(args, out) = exprs(args, env, out)
      #("$" <> name <> "(" <> string.join(args, ", ") <> ")", out)
    }
    anf.Record([], None) -> #("$unit", out)
    anf.Record(fields, base) -> {
      let #(fields, out) =
        list.fold(fields, #([], out), fn(acc, field) {
          let #(parts, out) = acc
          let #(label, value) = field
          let #(v, out) = expr(value, env, out)
          #([key(label) <> ": " <> v, ..parts], out)
        })
      let fields = list.reverse(fields)
      case base {
        None -> #("({" <> string.join(fields, ", ") <> "})", out)
        Some(base) -> {
          let #(b, out) = expr(base, env, out)
          #("({..." <> string.join([b, ..fields], ", ") <> "})", out)
        }
      }
    }
    anf.Select(from, label) -> {
      let #(f, out) = expr(from, env, out)
      #(f <> property(label), out)
    }
    anf.Tag(label, value) -> {
      let #(v, out) = expr(value, env, out)
      #("({$T: " <> js_string(label) <> ", $V: " <> v <> "})", out)
    }
    anf.Cons(head, tail) -> {
      let #(h, out) = expr(head, env, out)
      let #(t, out) = expr(tail, env, out)
      #("[" <> h <> ", " <> t <> "]", out)
    }
    anf.Tail -> #("$nil", out)
    anf.Perform(label, value) -> {
      let #(v, out) = expr(value, env, out)
      case env.options.evidence {
        Map -> #(
          "$performWith($s.w" <> property(label) <> ", " <> v <> ")",
          out,
        )
        Linked | Bubble -> #(
          "$perform(" <> js_string(label) <> ", " <> v <> ")",
          out,
        )
      }
    }
    anf.Handle(label, handler, exec) -> {
      let #(h, out) = expr(handler, env, out)
      let #(x, out) = expr(exec, env, out)
      #("$handle(" <> js_string(label) <> ", " <> h <> ", " <> x <> ")", out)
    }
    anf.Crash(reason) -> #("$crash(" <> js_string(reason) <> ")", out)
  }
}

fn exprs(es, env, out) {
  let #(parts, out) =
    list.fold(es, #([], out), fn(acc, e) {
      let #(parts, out) = acc
      let #(part, out) = expr(e, env, out)
      #([part, ..parts], out)
    })
  #(list.reverse(parts), out)
}

fn lambda(param, body, env: Env, out) {
  let #(b, out) = block(body, FnReturn, Fast, env, out)
  let code = "((" <> param <> ") => {\n" <> b <> "})"
  let tail = case env.options.tail, env.options.evidence {
    True, Map | True, Linked -> tail_resumptive(body)
    _, _ -> Error(Nil)
  }
  case tail {
    Error(Nil) -> #(code, out)
    Ok(#(resume, inner)) -> {
      let env = Env(..env, prefix: env.prefix <> "$t_" <> resume)
      let #(t, out) = block(inner, FnReturn, Fast, env, out)
      let t = "((" <> param <> ") => {\n" <> t <> "})"
      #("$tr(" <> code <> ", " <> t <> ")", out)
    }
  }
}

/// A handler of the form `(lift) -> { (resume) -> { ...resume(e) } }` where
/// every tail position calls resume and resume is used nowhere else.
/// Returns the body with each `resume(e)` replaced by `e`.
pub fn tail_resumptive(body) {
  case body {
    anf.Return(anf.Lambda(resume, inner, _), False) ->
      case tail_version(inner, resume) {
        Ok(inner) -> Ok(#(resume, inner))
        Error(Nil) -> Error(Nil)
      }
    _ -> Error(Nil)
  }
}

fn tail_version(block, k) {
  case block {
    anf.Let(name, value, effectful, then) ->
      case set.contains(anf.free_expr(value), k) {
        True -> Error(Nil)
        False ->
          case tail_version(then, k) {
            Ok(then) -> Ok(anf.Let(name, value, effectful, then))
            Error(Nil) -> Error(Nil)
          }
      }
    anf.Match(name, subject, branches, otherwise, then) ->
      case set.contains(anf.free_expr(subject), k) {
        True -> Error(Nil)
        False ->
          case then == anf.Return(anf.Var(name), False) {
            True -> {
              let branches =
                list.try_map(branches, fn(b: anf.Branch) {
                  case tail_version(b.body, k) {
                    Ok(body) -> Ok(anf.Branch(..b, body: body))
                    Error(Nil) -> Error(Nil)
                  }
                })
              let otherwise = case otherwise {
                None -> Ok(None)
                Some(#(param, body)) ->
                  case tail_version(body, k) {
                    Ok(body) -> Ok(Some(#(param, body)))
                    Error(Nil) -> Error(Nil)
                  }
              }
              case branches, otherwise {
                Ok(branches), Ok(otherwise) ->
                  Ok(anf.Match(name, subject, branches, otherwise, then))
                _, _ -> Error(Nil)
              }
            }
            False -> {
              let used =
                list.any(branches, fn(b: anf.Branch) {
                  set.contains(anf.free_block(b.body), k)
                })
                || case otherwise {
                  Some(#(_, body)) -> set.contains(anf.free_block(body), k)
                  None -> False
                }
              case used, tail_version(then, k) {
                False, Ok(then) ->
                  Ok(anf.Match(name, subject, branches, otherwise, then))
                _, _ -> Error(Nil)
              }
            }
          }
      }
    anf.Return(anf.Call(anf.Var(f), arg), _) if f == k ->
      case set.contains(anf.free_expr(arg), k) {
        True -> Error(Nil)
        False -> Ok(anf.Return(arg, False))
      }
    anf.Return(_, _) -> Error(Nil)
  }
}

/// A record field key in an object literal.
pub fn key(label) {
  case is_identifier(label) && label != "__proto__" {
    True -> label
    False -> "[" <> js_string(label) <> "]"
  }
}

/// A record field access.
pub fn property(label) {
  case is_identifier(label) {
    True -> "." <> label
    False -> "[" <> js_string(label) <> "]"
  }
}

fn is_identifier(label) {
  case string.to_utf_codepoints(label) {
    [] -> False
    [first, ..rest] ->
      identifier_start(string.utf_codepoint_to_int(first))
      && list.all(rest, fn(c) {
        let c = string.utf_codepoint_to_int(c)
        identifier_start(c) || { c >= 48 && c <= 57 }
      })
  }
}

fn identifier_start(c) {
  { c >= 65 && c <= 90 } || { c >= 97 && c <= 122 } || c == 95 || c == 36
}

pub fn js_string(value) {
  let escaped =
    string.to_utf_codepoints(value)
    |> list.map(fn(cp) {
      case string.utf_codepoint_to_int(cp) {
        34 -> "\\\""
        92 -> "\\\\"
        10 -> "\\n"
        13 -> "\\r"
        9 -> "\\t"
        0x2028 -> "\\u2028"
        0x2029 -> "\\u2029"
        c if c < 32 -> "\\u{" <> int.to_base16(c) <> "}"
        _ -> string.from_utf_codepoints([cp])
      }
    })
  "\"" <> string.concat(escaped) <> "\""
}

/// A binary literal.
pub fn binary(value) {
  "new Uint8Array([" <> bytes(value, []) <> "])"
}

fn bytes(value, acc) {
  case value {
    <<b, rest:bytes>> -> bytes(rest, [int.to_string(b), ..acc])
    _ -> string.join(list.reverse(acc), ", ")
  }
}
