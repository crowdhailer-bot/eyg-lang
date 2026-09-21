//// Every structural edit Jev can choose, as data so that sequences of actions
//// can be recorded, replayed and searched for common patterns.
//// Each action wraps a `morph/buffer` transformation or navigation.

import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/binding/error
import eyg/analysis/type_/isomorphic as t
import eyg/ir/tree as ir
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import jev_playground/environment.{type Environment}
import morph/buffer.{type Buffer}
import morph/editable as e
import morph/navigation
import morph/projection as p
import multiformats/cid/v1

pub type Action {
  // Navigation
  Next
  Previous
  Up
  Down
  Parent
  NextVacant
  JumpToError(index: Int)
  /// Select a hole by its number in reading order, starting from 1.
  JumpToHole(number: Int)
  // Values
  Variable(name: String)
  String(value: String)
  Integer(value: Int)
  Builtin(name: String)
  Tag(label: String)
  Reference(reference: ir.Reference)
  OpenLibrary(package: String)
  EmptyList
  List
  EmptyRecord
  Record(labels: List(String))
  // Structure
  Function(param: String)
  Call
  /// Call with a number of arguments known before, as the type of the selection
  /// can be lost while a program is part way through a compound move.
  CallTaking(arity: Int)
  CallWith
  Assign(name: String)
  AssignBefore(name: String)
  Select(label: String)
  Overwrite(label: String)
  Match(labels: List(String))
  Perform(label: String)
  Handle(label: String)
  InsertBefore(label: Option(String))
  InsertAfter(label: Option(String))
  Spread
  Delete
  Undo
  Rename(text: String)
  /// A string literal chosen by a separate question.
  ChooseString
  /// An integer literal chosen by a separate question.
  ChooseInteger
  Destructure(fields: List(#(String, String)))
  // Checking the program
  RunTests
  Finish
  /// A named sequence of actions applied as one choice.
  Compound(name: String, steps: List(Action))
  /// Fill the hole at the path, numbered as it was shown, leaving the selection where it was.
  AtHole(path: List(Int), number: Int, action: Action)
}

/// The option name shown to Jev, unique for each action.
pub fn key(action: Action) -> String {
  case action {
    Next -> "move next"
    Previous -> "move previous"
    Up -> "move up"
    Down -> "move down"
    Parent -> "select parent"
    NextVacant -> "move to next ?"
    JumpToError(index) -> "jump to type error " <> int.to_string(index + 1)
    JumpToHole(number) -> "move to hole " <> int.to_string(number)
    Variable(name) -> "variable " <> slot(name)
    String(value) -> "string " <> quote(value)
    Integer(value) -> "integer " <> int.to_string(value)
    Builtin(name) -> "builtin !" <> slot(name)
    Tag(label) -> "tag " <> slot(label)
    Reference(reference) -> "library " <> reference_name(reference)
    OpenLibrary(package) -> "open library @" <> package
    EmptyList -> "empty list []"
    List -> "wrap in list [..]"
    EmptyRecord -> "empty record {}"
    Record(labels) ->
      "record {" <> string.join(list.map(labels, slot), ", ") <> "}"
    Function(param) -> "function (" <> slot(param) <> ") ->"
    Call -> "call selection(..)"
    CallTaking(arity) ->
      "call selection(" <> string.join(list.repeat("?", arity), ", ") <> ")"
    CallWith -> "pass selection to ?(..)"
    Assign(name) -> "let " <> slot(name) <> " ="
    AssignBefore(name) -> "let " <> slot(name) <> " = above"
    Select(label) -> "select ." <> slot(label)
    Overwrite(label) -> "overwrite {" <> slot(label) <> ": .., ..}"
    Match(labels) -> "match " <> string.join(labels, " | ")
    Perform(label) -> "perform " <> label
    Handle(label) -> "handle " <> label
    InsertBefore(None) -> "insert before"
    InsertBefore(Some(label)) -> "insert " <> slot(label) <> " before"
    InsertAfter(None) -> "insert after"
    InsertAfter(Some(label)) -> "insert " <> slot(label) <> " after"
    Spread -> "spread .."
    Delete -> "delete selection"
    Undo -> "undo"
    Rename(text) -> "rename to " <> slot(text)
    ChooseString -> "string ?"
    ChooseInteger -> "integer ?"
    Destructure(fields) -> "destructure " <> fields_to_string(fields)
    RunTests -> "run tests"
    Finish -> "finish"
    Compound(name:, ..) -> name
    AtHole(number:, action:, ..) ->
      "at hole " <> int.to_string(number) <> ": " <> key(action)
  }
}

/// A short name for a reference, as written in code.
pub fn reference_name(reference) {
  case reference {
    ir.Pinned(release) -> "@" <> release.package
    ir.Package(package) -> "@" <> package
    ir.Version(package, version) ->
      "@" <> package <> ":" <> int.to_string(version)
    ir.Content(cid) -> "#" <> string.slice(v1.to_string(cid), 0, 16)
    ir.Relative(path) -> "import " <> quote(path)
  }
}

// Names left empty are slots filled later, shown as `?`.
fn slot(name) {
  case name {
    "" -> "?"
    _ -> name
  }
}

fn fields_to_string(fields) {
  let fields =
    list.map(fields, fn(field) {
      case field {
        #(label, var) if label == var -> label
        #(label, var) -> label <> ": " <> var
      }
    })
  "{" <> string.join(fields, ", ") <> "}"
}

fn quote(value) {
  "\"" <> string.replace(value, "\"", "\\\"") <> "\""
}

/// Apply an action to the buffer, failing if it is not possible at the current focus.
/// `RunTests`, `Finish` and `OpenLibrary` leave the buffer unchanged, the caller acts on them.
pub fn apply(
  action: Action,
  buffer: Buffer,
  environment: Environment,
) -> Result(Buffer, Nil) {
  let context = environment.context(environment)
  let refs = environment.references(environment)
  let done = fn(result: Result(fn(_, _) -> Buffer, Nil)) {
    result.map(result, fn(k) { k(context, refs) })
  }
  let with = fn(result: Result(fn(a, _, _) -> Buffer, Nil), value) {
    result.map(result, fn(k) { k(value, context, refs) })
  }
  case action {
    Next -> moved(buffer, buffer.next(buffer))
    Previous -> moved(buffer, buffer.previous(buffer))
    Up -> moved(buffer, buffer.up(buffer))
    Down -> moved(buffer, buffer.down(buffer))
    Parent -> moved(buffer, buffer.increase(buffer))
    NextVacant -> moved(buffer, buffer.next_vacant(buffer))
    JumpToError(index) -> {
      use #(rev, _reason) <- result.try(error_at(buffer, index))
      moved(buffer, buffer.focus_at_reversed(buffer, rev))
    }
    JumpToHole(number) -> {
      use hole <- result.try(list.drop(holes(buffer), number - 1) |> list.first)
      moved(buffer, Ok(buffer.update_position(buffer, hole)))
    }
    Variable(name) -> with(buffer.insert_variable(buffer), name)
    String(value) -> {
      use #(_, rebuild) <- result.map(buffer.insert_string(buffer))
      rebuild(value, context, refs)
    }
    Integer(value) -> {
      use #(_, rebuild) <- result.map(buffer.insert_integer(buffer))
      rebuild(value, context, refs)
    }
    Builtin(name) -> with(buffer.insert_builtin(buffer), name)
    Tag(label) -> with(buffer.tag(buffer), label)
    Reference(reference) ->
      with(buffer.set_expression(buffer), e.Reference(reference))
    EmptyList -> done(buffer.create_empty_list(buffer))
    List -> done(buffer.create_list(buffer))
    EmptyRecord -> done(buffer.create_empty_record(buffer))
    Record(labels) -> with(buffer.create_record(buffer), labels)
    Function(param) -> with(buffer.insert_function(buffer), param)
    Call -> with(buffer.call_many(buffer), call_arity(buffer))
    CallTaking(arity) -> with(buffer.call_many(buffer), arity)
    CallWith -> done(buffer.call_with(buffer))
    Assign(name) -> with(buffer.assign(buffer), name)
    AssignBefore(name) -> with(buffer.assign_before(buffer), name)
    Select(label) -> with(buffer.select_field(buffer), label)
    Overwrite(label) -> with(buffer.overwrite(buffer), label)
    Match(labels) -> with(buffer.match(buffer), labels)
    Perform(label) -> with(buffer.perform(buffer), label)
    Handle(label) -> with(buffer.insert_handle(buffer), label)
    InsertBefore(label) ->
      insert(buffer.insert_before(buffer), label, context, refs)
    InsertAfter(label) ->
      insert(buffer.insert_after(buffer), label, context, refs)
    Spread -> done(buffer.spread(buffer))
    Delete -> done(buffer.delete(buffer))
    Undo -> done(buffer.undo(buffer))
    Rename(text) -> {
      use #(_, rebuild) <- result.map(buffer.insert(buffer))
      rebuild(text, context, refs)
    }
    Destructure(fields) -> {
      let pattern = p.AssignPattern(e.Destructure(fields))
      use projection <- result.map(case buffer.projection {
        #(p.Assign(p.AssignPattern(_), value, pre, post, then), zoom)
        | #(p.Assign(p.AssignStatement(_), value, pre, post, then), zoom) ->
          Ok(#(p.Assign(pattern, value, pre, post, then), zoom))
        #(p.FnParam(p.AssignPattern(_), pre, post, body), zoom) ->
          Ok(#(p.FnParam(pattern, pre, post, body), zoom))
        _ -> Error(Nil)
      })
      buffer.update_code(buffer, projection, context, refs)
    }
    RunTests | Finish | OpenLibrary(_) -> Ok(buffer)
    // A literal must be chosen before it can be applied.
    ChooseString | ChooseInteger -> Error(Nil)
    Compound(steps:, ..) ->
      list.try_fold(steps, buffer, fn(buffer, step) {
        apply(step, buffer, environment)
      })
    AtHole(path:, action:, ..) -> {
      let here = p.path(buffer.projection)
      use at <- result.try(buffer.focus_at(buffer, path))
      use Nil <- result.try(case at.projection {
        #(p.Exp(e.Vacant), _) -> Ok(Nil)
        _ -> Error(Nil)
      })
      use filled <- result.try(apply(action, at, environment))
      case here == path {
        True -> Ok(buffer.next_vacant(filled) |> result.unwrap(filled))
        False -> buffer.focus_at(filled, here)
      }
    }
  }
}

/// Calls take no more arguments than this, a function whose type is only known
/// from how it is used can seem to take any number.
pub const max_arity = 8

/// The number of arguments a call of the selection takes.
pub fn call_arity(buffer: Buffer) -> Int {
  buffer.target_arity(buffer)
  |> result.unwrap(1)
  |> int.clamp(1, max_arity)
}

/// Every hole in the program, in the order they are written.
pub fn holes(buffer: Buffer) -> List(p.Projection) {
  let top = p.all(p.rebuild(buffer.projection))
  case top {
    #(p.Exp(e.Vacant), _) -> [top]
    _ -> do_holes(top, [])
  }
}

fn do_holes(projection, found) {
  case navigation.next_vacant(projection) {
    Ok(hole) ->
      case list.any(found, fn(h) { p.path(h) == p.path(hole) }) {
        True -> list.reverse(found)
        False -> do_holes(hole, [hole, ..found])
      }
    Error(Nil) -> list.reverse(found)
  }
}

/// Apply the action, with `advance` filling a `?` with a complete value moves
/// the selection to the next `?`, as a person typing would.
/// Functions and records stay selected because they are normally called or selected from next.
pub fn perform(
  action: Action,
  buffer: Buffer,
  environment: Environment,
  advance: Bool,
) -> Result(Buffer, Nil) {
  case action {
    Compound(steps:, ..) ->
      list.try_fold(steps, buffer, fn(buffer, step) {
        perform(step, buffer, environment, advance)
      })
    _ -> {
      use after <- result.map(apply(action, buffer, environment))
      let filled = case buffer.projection, action {
        #(p.Exp(e.Vacant), _), _ ->
          advance && completes(action, buffer.target_type(buffer), after)
        // Choosing the selected variable again keeps it and moves on.
        #(p.Exp(e.Variable(selected)), _), Variable(name) if selected == name ->
          advance
        _, _ -> False
      }
      case filled {
        True -> buffer.next_vacant(after) |> result.unwrap(after)
        False -> after
      }
    }
  }
}

// `expected` is the type the hole had before it was filled.
fn completes(action, expected, after: Buffer) {
  case action {
    String(_) | Integer(_) | EmptyList | EmptyRecord -> True
    Variable(_) | Builtin(_) | Tag(_) | Reference(_) ->
      case expected, buffer.target_type(after) {
        // A function where a function is expected is not about to be called,
        // and a record where a record is expected is not about to be selected from.
        Ok(t.Fun(..)), Ok(t.Fun(..)) | Ok(t.Record(_)), Ok(t.Record(_)) -> True
        // A value of unknown type might be a function or record, keep it selected.
        _, Ok(t.Fun(..))
        | _, Ok(t.Record(_))
        | _, Ok(t.Var(_))
        | _, Error(Nil)
        -> False
        _, _ -> True
      }
    _ -> False
  }
}

// A navigation that does not move is not a useful choice.
fn moved(before: Buffer, after: Result(Buffer, Nil)) {
  case after {
    Ok(after) if after.projection != before.projection -> Ok(after)
    _ -> Error(Nil)
  }
}

fn insert(continue, label, context, refs) {
  case continue, label {
    Ok(buffer.Done(k)), None -> Ok(k(context, refs))
    Ok(buffer.WithString(k)), Some(label) -> Ok(k(label, context, refs))
    _, _ -> Error(Nil)
  }
}

/// Type errors in the order they are numbered for Jev, with reversed paths.
/// Vacant nodes are reported by inference as `Todo` and are not included.
pub fn type_errors(buffer: Buffer) {
  infer.all_errors(buffer.analysis)
  |> list.filter(fn(error) { error.1 != error.Todo })
}

fn error_at(buffer, index) {
  type_errors(buffer)
  |> list.drop(index)
  |> list.first
}

/// Actions that only move the focus, which need no reanalysis.
pub fn is_navigation(action) {
  case action {
    Next
    | Previous
    | Up
    | Down
    | Parent
    | NextVacant
    | JumpToError(_)
    | JumpToHole(_) -> True
    _ -> False
  }
}

pub fn to_json(action: Action) -> json.Json {
  let with = fn(kind, fields) {
    json.object([#("kind", json.string(kind)), ..fields])
  }
  let text = fn(kind, value) { with(kind, [#("text", json.string(value))]) }
  let texts = fn(kind, values) {
    with(kind, [#("texts", json.array(values, json.string))])
  }
  case action {
    Next -> with("next", [])
    Previous -> with("previous", [])
    Up -> with("up", [])
    Down -> with("down", [])
    Parent -> with("parent", [])
    NextVacant -> with("next_vacant", [])
    JumpToError(index) -> with("jump_to_error", [#("index", json.int(index))])
    JumpToHole(number) -> with("jump_to_hole", [#("number", json.int(number))])
    Variable(name) -> text("variable", name)
    String(value) -> text("string", value)
    Integer(value) -> with("integer", [#("value", json.int(value))])
    Builtin(name) -> text("builtin", name)
    Tag(label) -> text("tag", label)
    Reference(reference) ->
      with("reference", [#("reference", reference_to_json(reference))])
    OpenLibrary(package) -> text("open_library", package)
    EmptyList -> with("empty_list", [])
    List -> with("list", [])
    EmptyRecord -> with("empty_record", [])
    Record(labels) -> texts("record", labels)
    Function(param) -> text("function", param)
    Call -> with("call", [])
    CallTaking(arity) -> with("call_taking", [#("arity", json.int(arity))])
    CallWith -> with("call_with", [])
    Assign(name) -> text("assign", name)
    AssignBefore(name) -> text("assign_before", name)
    Select(label) -> text("select", label)
    Overwrite(label) -> text("overwrite", label)
    Match(labels) -> texts("match", labels)
    Perform(label) -> text("perform", label)
    Handle(label) -> text("handle", label)
    InsertBefore(label) ->
      with("insert_before", [#("text", json.nullable(label, json.string))])
    InsertAfter(label) ->
      with("insert_after", [#("text", json.nullable(label, json.string))])
    Spread -> with("spread", [])
    Delete -> with("delete", [])
    Undo -> with("undo", [])
    Rename(value) -> text("rename", value)
    ChooseString -> with("choose_string", [])
    ChooseInteger -> with("choose_integer", [])
    Destructure(fields) ->
      with("destructure", [
        #(
          "fields",
          json.array(fields, fn(field) {
            json.preprocessed_array([json.string(field.0), json.string(field.1)])
          }),
        ),
      ])
    RunTests -> with("run_tests", [])
    Finish -> with("finish", [])
    Compound(name:, steps:) ->
      with("compound", [
        #("name", json.string(name)),
        #("steps", json.array(steps, to_json)),
      ])
    AtHole(path:, number:, action:) ->
      with("at_hole", [
        #("path", json.array(path, json.int)),
        #("number", json.int(number)),
        #("action", to_json(action)),
      ])
  }
}

fn reference_to_json(reference) {
  // Only references to released and content addressed modules are needed by scripts.
  case reference {
    ir.Pinned(ir.Release(package, version, module)) ->
      json.object([
        #("package", json.string(package)),
        #("version", json.int(version)),
        #("module", json.string(v1.to_string(module))),
      ])
    ir.Content(module) ->
      json.object([#("module", json.string(v1.to_string(module)))])
    ir.Package(package) -> json.object([#("package", json.string(package))])
    ir.Version(package, version) ->
      json.object([
        #("package", json.string(package)),
        #("version", json.int(version)),
      ])
    ir.Relative(path) -> json.object([#("path", json.string(path))])
  }
}

pub fn decoder() -> decode.Decoder(Action) {
  use kind <- decode.field("kind", decode.string)
  let text = decode.field("text", decode.string, decode.success)
  let texts = decode.field("texts", decode.list(decode.string), decode.success)
  case kind {
    "next" -> decode.success(Next)
    "previous" -> decode.success(Previous)
    "up" -> decode.success(Up)
    "down" -> decode.success(Down)
    "parent" -> decode.success(Parent)
    "next_vacant" -> decode.success(NextVacant)
    "jump_to_error" ->
      decode.field("index", decode.int, fn(i) { decode.success(JumpToError(i)) })
    "jump_to_hole" ->
      decode.field("number", decode.int, fn(i) { decode.success(JumpToHole(i)) })
    "variable" -> decode.map(text, Variable)
    "string" -> decode.map(text, String)
    "integer" ->
      decode.field("value", decode.int, fn(i) { decode.success(Integer(i)) })
    "builtin" -> decode.map(text, Builtin)
    "tag" -> decode.map(text, Tag)
    "reference" ->
      decode.field("reference", reference_decoder(), fn(r) {
        decode.success(Reference(r))
      })
    "open_library" -> decode.map(text, OpenLibrary)
    "empty_list" -> decode.success(EmptyList)
    "list" -> decode.success(List)
    "empty_record" -> decode.success(EmptyRecord)
    "record" -> decode.map(texts, Record)
    "function" -> decode.map(text, Function)
    "call" -> decode.success(Call)
    "call_taking" -> {
      use arity <- decode.field("arity", decode.int)
      decode.success(CallTaking(arity))
    }
    "call_with" -> decode.success(CallWith)
    "assign" -> decode.map(text, Assign)
    "assign_before" -> decode.map(text, AssignBefore)
    "select" -> decode.map(text, Select)
    "overwrite" -> decode.map(text, Overwrite)
    "match" -> decode.map(texts, Match)
    "perform" -> decode.map(text, Perform)
    "handle" -> decode.map(text, Handle)
    "insert_before" ->
      decode.field("text", decode.optional(decode.string), fn(label) {
        decode.success(InsertBefore(label))
      })
    "insert_after" ->
      decode.field("text", decode.optional(decode.string), fn(label) {
        decode.success(InsertAfter(label))
      })
    "spread" -> decode.success(Spread)
    "delete" -> decode.success(Delete)
    "undo" -> decode.success(Undo)
    "rename" -> decode.map(text, Rename)
    "choose_string" -> decode.success(ChooseString)
    "choose_integer" -> decode.success(ChooseInteger)
    "destructure" ->
      decode.field(
        "fields",
        decode.list({
          use label <- decode.field(0, decode.string)
          use var <- decode.field(1, decode.string)
          decode.success(#(label, var))
        }),
        fn(fields) { decode.success(Destructure(fields)) },
      )
    "run_tests" -> decode.success(RunTests)
    "finish" -> decode.success(Finish)
    "compound" -> {
      use name <- decode.field("name", decode.string)
      use steps <- decode.field("steps", decode.list(decoder()))
      decode.success(Compound(name, steps))
    }
    "at_hole" -> {
      use path <- decode.field("path", decode.list(decode.int))
      use number <- decode.field("number", decode.int)
      use action <- decode.field("action", decoder())
      decode.success(AtHole(path:, number:, action:))
    }
    _ -> decode.failure(Finish, "Action")
  }
}

fn reference_decoder() {
  let cid = {
    use text <- decode.then(decode.string)
    case v1.from_string(text) {
      Ok(#(module, _)) -> decode.success(module)
      Error(_) -> decode.failure(placeholder_cid(), "cid")
    }
  }
  decode.one_of(
    {
      use package <- decode.field("package", decode.string)
      use version <- decode.field("version", decode.int)
      use module <- decode.field("module", cid)
      decode.success(ir.Pinned(ir.Release(package, version, module)))
    },
    [
      decode.field("module", cid, fn(module) {
        decode.success(ir.Content(module))
      }),
      {
        use package <- decode.field("package", decode.string)
        use version <- decode.field("version", decode.int)
        decode.success(ir.Version(package, version))
      },
      decode.field("package", decode.string, fn(package) {
        decode.success(ir.Package(package))
      }),
      decode.field("path", decode.string, fn(path) {
        decode.success(ir.Relative(path))
      }),
    ],
  )
}

fn placeholder_cid() {
  let assert Ok(#(module, _)) =
    v1.from_string(
      "baguqeerahlbgfg7wjjdjguypivmsdcvh3e2vs4lhiafdbbtl3duxfuzv2eja",
    )
  module
}
