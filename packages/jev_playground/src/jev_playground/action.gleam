//// Every structural edit Jev can choose, as data so that sequences of actions
//// can be recorded, replayed and searched for common patterns.
//// Each action wraps a `morph/buffer` transformation or navigation.

import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/binding/error
import eyg/analysis/type_/isomorphic as t
import eyg/ir/tree as ir
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import jev_playground/environment.{type Environment}
import morph/buffer.{type Buffer}
import morph/editable as e
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
  Destructure(fields: List(#(String, String)))
  // Checking the program
  RunTests
  Finish
  /// A named sequence of actions applied as one choice.
  Compound(name: String, steps: List(Action))
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
    Variable(name) -> "variable " <> name
    String(value) -> "string " <> quote(value)
    Integer(value) -> "integer " <> int.to_string(value)
    Builtin(name) -> "builtin !" <> name
    Tag(label) -> "tag " <> label
    Reference(reference) -> "library " <> reference_name(reference)
    OpenLibrary(package) -> "open library @" <> package
    EmptyList -> "empty list []"
    List -> "wrap in list [..]"
    EmptyRecord -> "empty record {}"
    Record(labels) -> "record {" <> string.join(labels, ", ") <> "}"
    Function(param) -> "function (" <> param <> ") ->"
    Call -> "call selection(..)"
    CallWith -> "pass selection to ?(..)"
    Assign(name) -> "let " <> name <> " ="
    AssignBefore(name) -> "let " <> name <> " = above"
    Select(label) -> "select ." <> label
    Overwrite(label) -> "overwrite {" <> label <> ": .., ..}"
    Match(labels) -> "match " <> string.join(labels, " | ")
    Perform(label) -> "perform " <> label
    Handle(label) -> "handle " <> label
    InsertBefore(None) -> "insert before"
    InsertBefore(Some(label)) -> "insert " <> label <> " before"
    InsertAfter(None) -> "insert after"
    InsertAfter(Some(label)) -> "insert " <> label <> " after"
    Spread -> "spread .."
    Delete -> "delete selection"
    Undo -> "undo"
    Rename(text) -> "rename to " <> text
    Destructure(fields) -> "destructure " <> fields_to_string(fields)
    RunTests -> "run tests"
    Finish -> "finish"
    Compound(name:, ..) -> name
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
    Call -> {
      let arity = buffer.target_arity(buffer) |> result.unwrap(1)
      with(buffer.call_many(buffer), int.max(arity, 1))
    }
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
    Compound(steps:, ..) ->
      list.try_fold(steps, buffer, fn(buffer, step) {
        apply(step, buffer, environment)
      })
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
      let filled = case buffer.projection {
        #(p.Exp(e.Vacant), _) -> advance && completes(action, after)
        _ -> False
      }
      case filled {
        True -> buffer.next_vacant(after) |> result.unwrap(after)
        False -> after
      }
    }
  }
}

fn completes(action, after: Buffer) {
  case action {
    String(_) | Integer(_) | EmptyList | EmptyRecord -> True
    Variable(_) | Builtin(_) | Tag(_) | Reference(_) ->
      case buffer.target_type(after) {
        Ok(t.Fun(..)) | Ok(t.Record(_)) -> False
        _ -> True
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
    Next | Previous | Up | Down | Parent | NextVacant | JumpToError(_) -> True
    _ -> False
  }
}
