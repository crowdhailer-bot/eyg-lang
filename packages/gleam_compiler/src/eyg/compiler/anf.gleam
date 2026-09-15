//// A-normal form of an EYG program, the input to every code generator.
////
//// Every variable is given a unique name, applications of primitives and
//// builtins are recognised and unapplied primitives are eta expanded, so the
//// generators never see a curried primitive.
////
//// A call is effectful if the function called has an effect row that is not
//// empty. A call to a function with an empty row can never yield so the
//// generators do not need to check it. Effectful calls are bound to a name
//// unless they are in tail position.

import eyg/analysis/type_/isomorphic as t
import eyg/ir/tree as ir
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/set.{type Set}
import gleam/string

pub type Expr {
  Var(name: String)
  Integer(value: Int)
  String(value: String)
  Binary(value: BitArray)
  Lambda(param: String, body: Block, effectful: Bool)
  Call(func: Expr, arg: Expr)
  Builtin(name: String, args: List(Expr))
  Record(fields: List(#(String, Expr)), base: Option(Expr))
  Select(from: Expr, label: String)
  Tag(label: String, value: Expr)
  Cons(head: Expr, tail: Expr)
  Tail
  Perform(label: String, value: Expr)
  Handle(label: String, handler: Expr, exec: Expr)
  Crash(reason: String)
}

pub type Block {
  Let(name: String, value: Expr, effectful: Bool, then: Block)
  Match(
    name: String,
    subject: Expr,
    branches: List(Branch),
    otherwise: Option(#(String, Block)),
    then: Block,
  )
  Return(value: Expr, effectful: Bool)
}

pub type Branch {
  Branch(tag: String, param: String, body: Block)
}

/// The type of a node and whether evaluating it, not calling it, is pure.
pub type Info {
  Info(type_: t.Type(Int), pure: Bool)
}

type Config {
  Config(selective: Bool)
}

type Env =
  List(#(String, String))

/// Convert a program annotated with resolved types.
///
/// When `selective` is false every call is treated as effectful,
/// this is the behaviour when the program did not type check.
pub fn program(source: ir.Node(t.Type(Int)), selective: Bool) -> Block {
  let config = Config(selective)
  let source = annotate(source, config)
  let #(block, _) = tail(source, [], config, 0)
  block
}

// --- purity

fn annotate(node: ir.Node(t.Type(Int)), config: Config) -> ir.Node(Info) {
  let #(exp, type_) = node
  case exp {
    ir.Lambda(x, body) -> #(
      ir.Lambda(x, annotate(body, config)),
      Info(type_, True),
    )
    ir.Let(x, value, then) -> {
      let value = annotate(value, config)
      let then = annotate(then, config)
      let pure = { value.1 }.pure && { then.1 }.pure
      #(ir.Let(x, value, then), Info(type_, pure))
    }
    ir.Apply(f, a) -> {
      let f = annotate(f, config)
      let a = annotate(a, config)
      let pure =
        { f.1 }.pure && { a.1 }.pure && !call_effectful({ f.1 }.type_, config)
      #(ir.Apply(f, a), Info(type_, pure))
    }
    ir.Variable(x) -> #(ir.Variable(x), Info(type_, True))
    ir.Binary(x) -> #(ir.Binary(x), Info(type_, True))
    ir.Integer(x) -> #(ir.Integer(x), Info(type_, True))
    ir.String(x) -> #(ir.String(x), Info(type_, True))
    ir.Tail -> #(ir.Tail, Info(type_, True))
    ir.Cons -> #(ir.Cons, Info(type_, True))
    ir.Vacant -> #(ir.Vacant, Info(type_, True))
    ir.Empty -> #(ir.Empty, Info(type_, True))
    ir.Extend(l) -> #(ir.Extend(l), Info(type_, True))
    ir.Select(l) -> #(ir.Select(l), Info(type_, True))
    ir.Overwrite(l) -> #(ir.Overwrite(l), Info(type_, True))
    ir.Tag(l) -> #(ir.Tag(l), Info(type_, True))
    ir.Case(l) -> #(ir.Case(l), Info(type_, True))
    ir.NoCases -> #(ir.NoCases, Info(type_, True))
    ir.Perform(l) -> #(ir.Perform(l), Info(type_, True))
    ir.Handle(l) -> #(ir.Handle(l), Info(type_, True))
    ir.Builtin(l) -> #(ir.Builtin(l), Info(type_, True))
    ir.Reference(r) -> #(ir.Reference(r), Info(type_, True))
  }
}

/// Is a call to a function of this type effectful.
fn call_effectful(type_, config: Config) {
  !config.selective || !function_pure(type_)
}

/// A function with an empty effect row can not yield.
pub fn function_pure(type_) {
  case type_ {
    t.Fun(_, t.Empty, _) -> True
    _ -> False
  }
}

fn return_type(type_) {
  case type_ {
    t.Fun(_, _, return) -> return
    _ -> t.Var(-1)
  }
}

fn argument_type(type_) {
  case type_ {
    t.Fun(argument, _, _) -> argument
    _ -> t.Var(-1)
  }
}

// --- naming

fn fresh(label, i) {
  #(mangle(label) <> "$" <> int.to_string(i), i + 1)
}

fn temp(i) {
  #("t$" <> int.to_string(i), i + 1)
}

fn mangle(label) {
  let clean =
    string.to_graphemes(label)
    |> list.map(fn(g) {
      case is_identifier_char(g) {
        True -> g
        False -> "_"
      }
    })
    |> string.concat
  case clean {
    "" -> "v"
    _ -> clean
  }
}

fn is_identifier_char(g) {
  case g {
    "_" -> True
    _ ->
      case string.to_utf_codepoints(g) {
        [cp] -> {
          let c = string.utf_codepoint_to_int(cp)
          { c >= 48 && c <= 57 }
          || { c >= 65 && c <= 90 }
          || { c >= 97 && c <= 122 }
        }
        _ -> False
      }
  }
}

// --- normalisation

type Node =
  ir.Node(Info)

type K =
  fn(Expr, Bool, Int) -> #(Block, Int)

fn tail(node: Node, env: Env, config, i) -> #(Block, Int) {
  compute(node, env, config, i, fn(expr, effectful, i) {
    #(Return(expr, effectful), i)
  })
}

fn compute(node: Node, env: Env, config, i, k: K) -> #(Block, Int) {
  let #(exp, _) = node
  case exp {
    ir.Variable(x) ->
      case list.key_find(env, x) {
        Ok(name) -> k(Var(name), False, i)
        Error(Nil) -> k(Crash("undefined variable " <> x), False, i)
      }
    ir.Integer(n) -> k(Integer(n), False, i)
    ir.String(s) -> k(String(s), False, i)
    ir.Binary(b) -> k(Binary(b), False, i)
    ir.Tail -> k(Tail, False, i)
    ir.Empty -> k(Record([], None), False, i)
    ir.Vacant -> k(Crash("vacant"), False, i)
    ir.Reference(_) -> k(Crash("unresolved reference"), False, i)
    ir.Lambda(x, body) -> {
      let #(name, i) = fresh(x, i)
      let #(body, i) = tail(body, [#(x, name), ..env], config, i)
      // A closed row on a lambda annotation does not imply calls in its body
      // are annotated pure, so whether the body yields is taken from the body.
      k(Lambda(name, body, yields(body)), False, i)
    }
    ir.Let(x, value, then) -> {
      use expr, effectful, i <- compute(value, env, config, i)
      let #(name, i) = fresh(x, i)
      let #(then, i) = compute(then, [#(x, name), ..env], config, i, k)
      #(Let(name, expr, effectful, then), i)
    }
    ir.Apply(_, _) -> {
      let #(head, args) = spine(node, [])
      apply(head, args, env, config, i, k)
    }
    _ -> apply(node, [], env, config, i, k)
  }
}

/// Unwind nested applications, each argument is paired with the node that
/// applies it, the type of the previous node is the type of the function called.
fn spine(node: Node, acc) {
  case node {
    #(ir.Apply(f, a), _) -> spine(f, [#(a, node), ..acc])
    _ -> #(node, acc)
  }
}

fn apply(head: Node, args: List(#(Node, Node)), env, config, i, k: K) {
  let #(exp, info) = head
  let arg_nodes = list.map(args, fn(pair) { pair.0 })
  case exp {
    ir.Builtin(name) ->
      case arity(name) {
        Ok(n) -> primitive(head, args, n, env, config, i, k, builtin(name, _))
        Error(Nil) -> k(Crash("undefined builtin " <> name), False, i)
      }
    ir.Cons ->
      primitive(head, args, 2, env, config, i, k, fn(xs) {
        let assert [h, t] = xs
        Cons(h, t)
      })
    ir.Extend(label) ->
      primitive(head, args, 2, env, config, i, k, fn(xs) {
        let assert [value, base] = xs
        extend(label, value, base)
      })
    ir.Overwrite(label) ->
      primitive(head, args, 2, env, config, i, k, fn(xs) {
        let assert [value, base] = xs
        overwrite(label, value, base)
      })
    ir.Select(label) ->
      primitive(head, args, 1, env, config, i, k, fn(xs) {
        let assert [from] = xs
        Select(from, label)
      })
    ir.Tag(label) ->
      primitive(head, args, 1, env, config, i, k, fn(xs) {
        let assert [value] = xs
        Tag(label, value)
      })
    ir.Perform(label) ->
      primitive(head, args, 1, env, config, i, k, fn(xs) {
        let assert [value] = xs
        Perform(label, value)
      })
    ir.Handle(label) ->
      primitive(head, args, 2, env, config, i, k, fn(xs) {
        let assert [handler, exec] = xs
        Handle(label, handler, exec)
      })
    ir.NoCases ->
      primitive(head, args, 1, env, config, i, k, fn(_) { Crash("no match") })
    ir.Case(_) ->
      case args {
        [_, _, _, ..] -> match(head, args, env, config, i, k)
        _ -> eta(head, args, 3, env, config, i, k)
      }
    _ -> {
      use f, i <- operands([head], arg_nodes, env, config, i)
      let assert [f] = f
      calls(f, info.type_, args, env, config, i, k)
    }
  }
  |> fn(result) { result }
}

/// Apply a primitive with a known arity.
///
/// With too few arguments the primitive is eta expanded,
/// with too many the result is called with the rest.
fn primitive(head: Node, args, n, env, config, i, k: K, build) {
  case list.length(args) >= n {
    False -> eta(head, args, n, env, config, i, k)
    True -> {
      let #(now, later) = list.split(args, n)
      let now_nodes = list.map(now, fn(pair) { pair.0 })
      let later_nodes = list.map(later, fn(pair) { pair.0 })
      let effectful = spine_effectful(head, now, config)
      use values, i <- operands(now_nodes, later_nodes, env, config, i)
      let expr = build(values)
      let expr = case expr {
        Builtin("fix", [builder]) ->
          case builder_pure(now) {
            True -> Builtin("fix_pure", [builder])
            False -> expr
          }
        _ -> expr
      }
      case later {
        [] -> k(expr, effectful, i)
        _ -> {
          let assert Ok(#(_, last)) = list.last(now)
          use f, i <- bind(expr, effectful, later_nodes, i)
          calls(f, { last.1 }.type_, later, env, config, i, k)
        }
      }
    }
  }
}

fn builder_pure(now: List(#(Node, Node))) {
  case now {
    [#(#(_, info), _)] -> function_pure(info.type_)
    _ -> False
  }
}

/// Whether any of the applications in a saturated primitive are effectful.
fn spine_effectful(head: Node, args: List(#(Node, Node)), config) {
  let #(_, effectful) =
    list.fold(args, #({ head.1 }.type_, False), fn(acc, pair) {
      let #(callee, effectful) = acc
      let #(_, applied) = pair
      #({ applied.1 }.type_, effectful || call_effectful(callee, config))
    })
  effectful
}

fn builtin(name, args) {
  Builtin(name, args)
}

fn extend(label, value, base) {
  case base {
    Record(fields, b) ->
      case list.key_find(fields, label) {
        Error(Nil) -> Record([#(label, value), ..fields], b)
        Ok(_) -> Record([#(label, value)], Some(base))
      }
    _ -> Record([#(label, value)], Some(base))
  }
}

fn overwrite(label, value, base) {
  case base {
    Record(fields, b) ->
      case list.key_find(fields, label) {
        Ok(_) -> Record(list.key_set(fields, label, value), b)
        Error(Nil) -> Record([#(label, value)], Some(base))
      }
    _ -> Record([#(label, value)], Some(base))
  }
}

/// Call a function value with each argument in turn.
fn calls(f, callee_type, args: List(#(Node, Node)), env, config, i, k: K) {
  case args {
    [] -> k(f, False, i)
    [#(arg, applied), ..rest] -> {
      let rest_nodes = list.map(rest, fn(pair) { pair.0 })
      use values, i <- operands([arg], rest_nodes, env, config, i)
      let assert [a] = values
      let effectful = call_effectful(callee_type, config)
      case rest {
        [] -> k(Call(f, a), effectful, i)
        _ -> {
          use f, i <- bind(Call(f, a), effectful, rest_nodes, i)
          calls(f, { applied.1 }.type_, rest, env, config, i, k)
        }
      }
    }
  }
}

/// Bind an expression to a name if it is effectful, or if later evaluation
/// could yield and the expression is not trivial.
fn bind(expr, effectful, later: List(Node), i, k) {
  case effectful || { !trivial(expr) && !all_pure(later) } {
    True -> {
      let #(name, i) = temp(i)
      let #(then, i) = k(Var(name), i)
      #(Let(name, expr, effectful, then), i)
    }
    False -> k(expr, i)
  }
}

fn all_pure(nodes: List(Node)) {
  list.all(nodes, fn(node) { { node.1 }.pure })
}

fn trivial(expr) {
  case expr {
    Var(_) | Integer(_) | String(_) | Binary(_) | Tail | Lambda(..) -> True
    Record([], None) -> True
    _ -> False
  }
}

/// Normalise nodes left to right, keeping evaluation order.
fn operands(nodes: List(Node), later: List(Node), env, config, i, k) {
  do_operands(nodes, later, env, config, i, [], k)
}

fn do_operands(nodes: List(Node), later, env, config, i, acc, k) {
  case nodes {
    [] -> k(list.reverse(acc), i)
    [node, ..rest] -> {
      use expr, effectful, i <- compute(node, env, config, i)
      use expr, i <- bind(expr, effectful, list.append(rest, later), i)
      do_operands(rest, later, env, config, i, [expr, ..acc], k)
    }
  }
}

/// Eta expand a partially applied primitive, `head(args...)` becomes
/// `(x) -> { head(args..., x) }` for each missing argument.
fn eta(head: Node, args: List(#(Node, Node)), n, env, config, i, k: K) {
  let arg_nodes = list.map(args, fn(pair) { pair.0 })
  use values, i <- operands(arg_nodes, [], env, config, i)
  // bind supplied arguments so they are evaluated once
  let callee = case list.last(args) {
    Ok(#(_, applied)) -> { applied.1 }.type_
    Error(Nil) -> { head.1 }.type_
  }
  let missing = n - list.length(args)
  let #(params, i) =
    list.fold(list.repeat(Nil, missing), #([], i), fn(acc, _) {
      let #(params, i) = acc
      let #(name, i) = temp(i)
      #([name, ..params], i)
    })
  let params = list.reverse(params)
  // Build a synthetic body from variables bound to the parameters.
  let values = list.append(values, list.map(params, Var))
  let #(body, i) = saturated(head, values, callee, missing, env, config, i)
  k(lambdas(params, body, callee), False, i)
}

fn lambdas(params, body, type_) {
  case params {
    [] -> panic as "eta expansion needs parameters"
    [param] -> Lambda(param, body, yields(body))
    [param, ..rest] ->
      Lambda(
        param,
        Return(lambdas(rest, body, return_type(type_)), False),
        False,
      )
  }
}

/// The body of an eta expanded primitive with every argument available.
fn saturated(head: Node, values, callee, missing, _env, config, i) {
  let #(exp, _) = head
  let final = nth_return(callee, missing - 1)
  let effectful = call_effectful(final, config)
  case exp, values {
    ir.Builtin(name), _ -> #(Return(Builtin(name, values), effectful), i)
    ir.Cons, [h, t] -> #(Return(Cons(h, t), False), i)
    ir.Extend(label), [value, base] -> #(
      Return(extend(label, value, base), False),
      i,
    )
    ir.Overwrite(label), [value, base] -> #(
      Return(overwrite(label, value, base), False),
      i,
    )
    ir.Select(label), [from] -> #(Return(Select(from, label), False), i)
    ir.Tag(label), [value] -> #(Return(Tag(label, value), False), i)
    ir.Perform(label), [value] -> #(Return(Perform(label, value), True), i)
    ir.Handle(label), [h, e] -> #(Return(Handle(label, h, e), True), i)
    ir.NoCases, _ -> #(Return(Crash("no match"), False), i)
    ir.Case(label), [branch, otherwise, subject] -> {
      let #(x, i) = temp(i)
      let #(y, i) = temp(i)
      let branch_type = argument_type({ head.1 }.type_)
      let otherwise_type = argument_type(return_type({ head.1 }.type_))
      let #(result, i) = temp(i)
      let block =
        Match(
          result,
          subject,
          [
            Branch(
              label,
              x,
              Return(Call(branch, Var(x)), call_effectful(branch_type, config)),
            ),
          ],
          Some(#(
            y,
            Return(
              Call(otherwise, Var(y)),
              call_effectful(otherwise_type, config),
            ),
          )),
          Return(Var(result), False),
        )
      #(block, i)
    }
    _, _ -> #(Return(Crash("invalid primitive"), False), i)
  }
}

fn nth_return(type_, n) {
  case n <= 0 {
    True -> type_
    False -> nth_return(return_type(type_), n - 1)
  }
}

/// `match value { A(x) -> {..} B(y) -> {..} | (other) -> {..} }`
///
/// Branches that are lambdas are inlined, the chain of `Case` nodes in the
/// otherwise position is flattened into a single match.
fn match(head: Node, args: List(#(Node, Node)), env, config, i, k: K) {
  let assert [#(branch, _), #(otherwise, _), #(subject, applied), ..rest] = args
  let assert #(ir.Case(label), _) = head
  let chain = [#(label, branch), ..cases(otherwise)]
  let #(chain, last) = case list.last(chain) {
    _ -> split_last(chain, otherwise)
  }
  // Non lambda branches and the subject are evaluated in order.
  let branch_nodes =
    list.filter_map(chain, fn(c) {
      case c.1 {
        #(ir.Lambda(..), _) -> Error(Nil)
        node -> Ok(node)
      }
    })
  let last_nodes = case last {
    Some(#(ir.Lambda(..), _)) | None -> []
    Some(node) -> [node]
  }
  let rest_nodes = list.map(rest, fn(pair) { pair.0 })
  let evaluated = list.flatten([branch_nodes, last_nodes, [subject]])
  use values, i <- operands(evaluated, rest_nodes, env, config, i)
  let #(branch_values, values) = list.split(values, list.length(branch_nodes))
  let #(last_values, values) = list.split(values, list.length(last_nodes))
  let assert [subject_value] = values
  let #(branches, i, _) =
    list.fold(chain, #([], i, branch_values), fn(acc, c) {
      let #(branches, i, remaining) = acc
      let #(tag, node) = c
      let #(param, body, i, remaining) =
        branch_body(node, remaining, env, config, i)
      #([Branch(tag, param, body), ..branches], i, remaining)
    })
  let branches = list.reverse(branches)
  let #(otherwise, i) = case last {
    None -> #(None, i)
    Some(node) -> {
      let #(param, body, i, _) = branch_body(node, last_values, env, config, i)
      #(Some(#(param, body)), i)
    }
  }
  let #(result, i) = temp(i)
  case rest {
    [] -> {
      let #(then, i) = k(Var(result), False, i)
      #(Match(result, subject_value, branches, otherwise, then), i)
    }
    _ -> {
      let #(then, i) =
        calls(Var(result), { applied.1 }.type_, rest, env, config, i, k)
      #(Match(result, subject_value, branches, otherwise, then), i)
    }
  }
}

/// The partially applied cases in an otherwise position.
fn cases(node: Node) {
  case node {
    #(ir.Apply(#(ir.Apply(#(ir.Case(label), _), branch), _), otherwise), _) -> [
      #(label, branch),
      ..cases(otherwise)
    ]
    _ -> []
  }
}

/// Separate the final otherwise, `NoCases` means there is none.
fn split_last(chain, otherwise: Node) {
  let last = final_otherwise(otherwise)
  #(chain, last)
}

fn final_otherwise(node: Node) {
  case node {
    #(ir.Apply(#(ir.Apply(#(ir.Case(_), _), _), _), otherwise), _) ->
      final_otherwise(otherwise)
    #(ir.NoCases, _) -> None
    other -> Some(other)
  }
}

fn branch_body(node: Node, values, env, config, i) {
  case node {
    #(ir.Lambda(x, body), _) -> {
      let #(param, i) = fresh(x, i)
      let #(body, i) = tail(body, [#(x, param), ..env], config, i)
      #(param, body, i, values)
    }
    #(_, info) -> {
      let assert [f, ..remaining] = values
      let #(param, i) = temp(i)
      let effectful = call_effectful(info.type_, config)
      #(param, Return(Call(f, Var(param)), effectful), i, remaining)
    }
  }
}

// --- analysis of normal form

pub fn free_block(block) -> Set(String) {
  case block {
    Let(name, value, _, then) ->
      set.union(free_expr(value), set.delete(free_block(then), name))
    Match(name, subject, branches, otherwise, then) -> {
      let acc =
        set.union(free_expr(subject), set.delete(free_block(then), name))
      let acc =
        list.fold(branches, acc, fn(acc, branch) {
          set.union(acc, set.delete(free_block(branch.body), branch.param))
        })
      case otherwise {
        Some(#(param, body)) ->
          set.union(acc, set.delete(free_block(body), param))
        None -> acc
      }
    }
    Return(value, _) -> free_expr(value)
  }
}

pub fn free_expr(expr) -> Set(String) {
  case expr {
    Var(name) -> set.from_list([name])
    Integer(_) | String(_) | Binary(_) | Tail | Crash(_) -> set.new()
    Lambda(param, body, _) -> set.delete(free_block(body), param)
    Call(f, a) -> set.union(free_expr(f), free_expr(a))
    Builtin(_, args) -> free_list(args)
    Record(fields, base) -> {
      let acc = free_list(list.map(fields, fn(f) { f.1 }))
      case base {
        Some(base) -> set.union(acc, free_expr(base))
        None -> acc
      }
    }
    Select(from, _) -> free_expr(from)
    Tag(_, value) -> free_expr(value)
    Cons(h, t) -> set.union(free_expr(h), free_expr(t))
    Perform(_, value) -> free_expr(value)
    Handle(_, h, e) -> set.union(free_expr(h), free_expr(e))
  }
}

fn free_list(exprs) {
  list.fold(exprs, set.new(), fn(acc, e) { set.union(acc, free_expr(e)) })
}

/// Does the block contain a checked call outside of any lambda.
/// An effectful return is checked when its value is not returned directly.
pub fn yields(block) {
  case block {
    Let(_, _, True, _) -> True
    Let(_, _, False, then) -> yields(then)
    Match(_, _, branches, otherwise, then) ->
      list.any(branches, fn(b) { yields(b.body) })
      || case otherwise {
        Some(#(_, body)) -> yields(body)
        None -> False
      }
      || yields(then)
    Return(_, effectful) -> effectful
  }
}

/// The arity of every builtin the interpreter implements.
pub fn arity(name) {
  case name {
    "fix" | "never" | "int_absolute" | "int_parse" | "int_to_string" -> Ok(1)
    "string_uppercase"
    | "string_lowercase"
    | "string_length"
    | "string_to_binary"
    | "string_from_binary"
    | "list_pop"
    | "binary_from_integers"
    | "binary_size" -> Ok(1)
    "equal"
    | "int_compare"
    | "int_add"
    | "int_subtract"
    | "int_multiply"
    | "int_divide"
    | "string_append"
    | "string_split"
    | "string_split_once"
    | "string_starts_with"
    | "string_ends_with"
    | "binary_concat"
    | "binary_compare" -> Ok(2)
    "string_replace" | "list_fold" | "binary_fold" -> Ok(3)
    _ -> Error(Nil)
  }
}
