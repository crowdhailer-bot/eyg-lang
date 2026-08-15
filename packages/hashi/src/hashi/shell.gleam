//// A structural shell over the game.
////
//// There is no text here. A program is a tree, and every key builds a piece of
//// tree: `s` makes a string, `v` a variable, `p` a `perform`, `m` a match.
//// Because the shell is always holding a tree rather than a line of characters
//// it can type check what has been written as it is written, against the six
//// effects of the harness and the workspace the context module brings.
////
//// `morph` owns the editing: `buffer` has one function per transformation and
//// answers whether it applies to whatever is in focus. What belongs to an
//// application, and so is here, is which key does what, what to do while a
//// name is being typed or chosen, and what to keep of a program once it has
//// run.

import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/binding/debug as t_debug
import eyg/analysis/type_/isomorphic as t
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import morph/buffer
import morph/picker

pub type Shell {
  Shell(
    /// The program being written.
    buffer: buffer.Buffer,
    mode: Mode,
    /// Programs already run, newest first.
    history: List(Entry),
    help: Bool,
  )
}

type Naming =
  fn(String, infer.Context) -> buffer.Buffer

type Counting =
  fn(Int, infer.Context) -> buffer.Buffer

/// What the next keystroke means.
pub type Mode {
  /// Keys are commands.
  Command
  /// A name is being typed.
  Writing(value: String, rebuild: Naming)
  /// A number is being typed. It is kept as text so a half typed number, or
  /// nothing at all, is something the shell can hold.
  Numbering(value: String, rebuild: Counting)
  /// One of a list of names is being chosen.
  Choosing(picker: picker.Picker, rebuild: Naming)
}

/// A program that has been run and what came of it.
pub type Entry {
  Entry(buffer: buffer.Buffer, outcome: Outcome)
}

pub type Outcome {
  /// Still waiting on something the platform is doing.
  Working
  /// The program's value, already written out for reading.
  Returned(String)
  Failed(String)
}

pub fn new(context: infer.Context) -> Shell {
  Shell(buffer: buffer.empty(context), mode: Command, history: [], help: False)
}

pub type Message {
  UserPressedKey(String)
  UserClickedCode(List(Int))
  UserWroteInput(String)
  /// The picker keeps its own filtering and scrolling; it hands back what it
  /// became rather than a string to rebuild it from.
  UserMovedPicker(picker.Picker)
  UserSubmittedInput
  UserDismissedInput
  UserChoseSuggestion(String)
  UserClickedRun
  UserClickedPrevious(Int)
  UserToggledHelp
}

/// What the shell wants doing after a message. Running a program is not
/// something the shell can do; that belongs to whatever owns the game.
pub type Action {
  Nothing
  /// Run the program in the buffer.
  Run
}

pub fn update(
  shell: Shell,
  message: Message,
  context: infer.Context,
) -> #(Shell, Action) {
  case message, shell.mode {
    UserToggledHelp, _ -> #(Shell(..shell, help: !shell.help), Nothing)

    UserClickedCode(path), _ ->
      case buffer.focus_at(shell.buffer, path) {
        Ok(buffer) -> #(Shell(..shell, buffer:, mode: Command), Nothing)
        Error(Nil) -> #(Shell(..shell, mode: Command), Nothing)
      }

    UserClickedPrevious(index), _ -> #(recall(shell, index, context), Nothing)

    UserClickedRun, _ -> #(shell, Run)

    UserWroteInput(value), Writing(rebuild:, ..) -> #(
      Shell(..shell, mode: Writing(value:, rebuild:)),
      Nothing,
    )
    UserWroteInput(value), Numbering(rebuild:, ..) -> #(
      Shell(..shell, mode: Numbering(value:, rebuild:)),
      Nothing,
    )
    UserWroteInput(_), Choosing(..) -> #(shell, Nothing)
    UserWroteInput(_), Command -> #(shell, Nothing)

    UserMovedPicker(picker), Choosing(rebuild:, ..) -> #(
      Shell(..shell, mode: Choosing(picker:, rebuild:)),
      Nothing,
    )
    UserMovedPicker(_), _ -> #(shell, Nothing)

    UserChoseSuggestion(choice), Choosing(rebuild:, ..) -> #(
      named(shell, rebuild, choice, context),
      Nothing,
    )
    UserChoseSuggestion(_), _ -> #(shell, Nothing)

    UserSubmittedInput, Writing(value:, rebuild:) -> #(
      named(shell, rebuild, value, context),
      Nothing,
    )
    UserSubmittedInput, Choosing(picker:, rebuild:) -> #(
      named(shell, rebuild, picker.current(picker), context),
      Nothing,
    )
    UserSubmittedInput, Numbering(value:, rebuild:) ->
      case int.parse(value) {
        Ok(number) -> #(
          Shell(..shell, buffer: rebuild(number, context), mode: Command),
          Nothing,
        )
        // Nothing typed yet, or not a number. Leave it be rather than guess.
        Error(Nil) -> #(shell, Nothing)
      }
    UserSubmittedInput, Command -> #(shell, Run)

    UserDismissedInput, _ -> #(Shell(..shell, mode: Command), Nothing)

    UserPressedKey(key), Command -> command(shell, key, context)
    UserPressedKey("Escape"), _ -> #(Shell(..shell, mode: Command), Nothing)
    UserPressedKey(_), _ -> #(shell, Nothing)
  }
}

fn named(shell: Shell, rebuild: Naming, value: String, context) {
  Shell(..shell, buffer: rebuild(value, context), mode: Command)
}

// KEYS ------------------------------------------------------------------------

/// One key, one piece of tree.
///
/// The letters are `morph`'s, so someone who knows the editor on eyg.run
/// already knows this one. A key that does not apply where the cursor is
/// leaves the program alone rather than complaining.
fn command(shell: Shell, key: String, context: infer.Context) {
  let Shell(buffer: b, ..) = shell
  case key {
    "?" -> #(Shell(..shell, help: !shell.help), Nothing)
    "Enter" -> #(shell, Run)

    // moving about
    "ArrowRight" -> moved(shell, buffer.next(b))
    "ArrowLeft" -> moved(shell, buffer.previous(b))
    "ArrowUp" -> moved(shell, buffer.up(b))
    "ArrowDown" -> moved(shell, buffer.down(b))
    " " -> moved(shell, buffer.next_vacant(b))
    "a" -> moved(shell, buffer.increase(b))
    "k" -> moved(shell, buffer.toggle_open(b))

    // undo and redo of the writing, not of the game
    "z" -> applied(shell, buffer.undo(b), context)
    "Z" -> applied(shell, buffer.redo(b), context)

    // writing a value
    "s" -> writing(shell, buffer.insert_string(b))
    "i" -> writing(shell, buffer.insert(b))
    "n" -> numbering(shell, buffer.insert_integer(b))
    "b" -> applied(shell, buffer.insert_binary(b), context)

    // naming something
    "e" -> naming(shell, buffer.assign(b), [])
    "E" -> naming(shell, buffer.assign_before(b), [])
    "v" -> naming(shell, buffer.insert_variable(b), variables(b))
    "f" -> naming(shell, buffer.insert_function(b), [])
    "g" -> naming(shell, buffer.select_field(b), fields(b))
    "o" -> naming(shell, buffer.overwrite(b), fields(b))
    "t" -> naming(shell, buffer.tag(b), varients(b))
    "p" -> naming(shell, buffer.perform(b), effects(context))
    "h" -> naming(shell, buffer.insert_handle(b), effects(context))
    "j" -> naming(shell, buffer.insert_builtin(b), builtins())

    // several names at once, typed with commas between them
    "r" -> listing(shell, buffer.create_record(b))
    "m" -> listing(shell, buffer.match(b))

    // shapes that need no name
    "c" -> applied(shell, buffer.call_once(b), context)
    "w" -> applied(shell, buffer.call_with(b), context)
    "R" -> applied(shell, buffer.create_empty_record(b), context)
    "l" -> applied(shell, buffer.create_list(b), context)
    "L" -> applied(shell, buffer.create_empty_list(b), context)
    "d" -> applied(shell, buffer.delete(b), context)
    "." -> applied(shell, buffer.spread(b), context)
    "," -> extended(shell, buffer.insert_after(b), context)
    _ -> #(shell, Nothing)
  }
}

fn moved(shell: Shell, result) {
  case result {
    Ok(buffer) -> #(Shell(..shell, buffer:), Nothing)
    Error(Nil) -> #(shell, Nothing)
  }
}

fn applied(shell: Shell, result, context) {
  case result {
    Ok(rebuild) -> #(Shell(..shell, buffer: rebuild(context)), Nothing)
    Error(Nil) -> #(shell, Nothing)
  }
}

fn writing(shell: Shell, result) {
  case result {
    Ok(#(value, rebuild)) -> #(
      Shell(..shell, mode: Writing(value:, rebuild:)),
      Nothing,
    )
    Error(Nil) -> #(shell, Nothing)
  }
}

fn numbering(shell: Shell, result) {
  case result {
    Ok(#(value, rebuild)) -> #(
      Shell(..shell, mode: Numbering(value: int.to_string(value), rebuild:)),
      Nothing,
    )
    Error(Nil) -> #(shell, Nothing)
  }
}

/// A name is being asked for. When there is something sensible to suggest the
/// shell offers a list; otherwise the name is typed.
fn naming(shell: Shell, result, suggestions) {
  case result {
    Ok(rebuild) ->
      case suggestions {
        [] -> #(Shell(..shell, mode: Writing(value: "", rebuild:)), Nothing)
        _ -> #(
          Shell(..shell, mode: Choosing(picker.new("", suggestions), rebuild:)),
          Nothing,
        )
      }
    Error(Nil) -> #(shell, Nothing)
  }
}

/// A record's fields, or a match's branches: several names at once, typed with
/// commas between them.
fn listing(shell: Shell, result) {
  case result {
    Ok(rebuild) -> {
      let rebuild = fn(typed, context) { rebuild(names(typed), context) }
      #(Shell(..shell, mode: Writing(value: "", rebuild:)), Nothing)
    }
    Error(Nil) -> #(shell, Nothing)
  }
}

fn names(typed: String) -> List(String) {
  string.split(typed, ",")
  |> list.map(string.trim)
  |> list.filter(fn(name) { name != "" })
}

/// `insert_after` may or may not need a name, depending on what it is
/// extending.
fn extended(shell: Shell, result, context) {
  case result {
    Ok(buffer.Done(rebuild)) -> #(
      Shell(..shell, buffer: rebuild(context)),
      Nothing,
    )
    Ok(buffer.WithString(rebuild)) -> #(
      Shell(..shell, mode: Writing(value: "", rebuild:)),
      Nothing,
    )
    Error(Nil) -> #(shell, Nothing)
  }
}

// SUGGESTIONS -----------------------------------------------------------------

/// A picker wants a name and something to say about it. Where the something is
/// a type this is the whole point of having written the program as a tree.
fn variables(b) {
  case buffer.target_scope(b) {
    Ok(scope) -> list.map(scope, fn(entry) { #(entry.0, "") })
    Error(_) -> []
  }
}

fn fields(b) {
  typed(buffer.fields(b))
}

fn varients(b) {
  typed(buffer.varients(b))
}

fn typed(entries) {
  list.map(entries, fn(entry) {
    let #(name, type_) = entry
    #(name, t_debug.mono(type_))
  })
}

/// The effects of the environment the shell is over, read off the inference
/// context so the list is never out of step with what actually runs.
fn effects(context: infer.Context) {
  effect_labels(context.eff, [])
}

fn effect_labels(row, acc) {
  case row {
    t.EffectExtend(label, #(lift, lower), rest) ->
      effect_labels(rest, [
        #(label, t_debug.mono(lift) <> " -> " <> t_debug.mono(lower)),
        ..acc
      ])
    _ -> list.reverse(acc)
  }
}

fn builtins() {
  list.map(infer.builtins(), fn(entry) { #(entry.0, "") })
}

// RUNNING ----------------------------------------------------------------------

/// Keep the program that has just been run, and start a new empty one.
pub fn ran(shell: Shell, outcome: Outcome, context: infer.Context) -> Shell {
  let entry = Entry(buffer: shell.buffer, outcome:)
  Shell(..shell, buffer: buffer.empty(context), mode: Command, history: [
    entry,
    ..shell.history
  ])
}

/// Replace the outcome of the program that was still working.
pub fn settled(shell: Shell, outcome: Outcome) -> Shell {
  case shell.history {
    [Entry(buffer:, outcome: Working), ..rest] ->
      Shell(..shell, history: [Entry(buffer:, outcome:), ..rest])
    _ -> shell
  }
}

/// Put a program in the buffer, ready to change and run.
///
/// The shell is written with keys, but a program that came from somewhere else
/// — an example, a link, a test — comes in here.
pub fn edit(shell: Shell, source, context: infer.Context) -> Shell {
  Shell(..shell, buffer: buffer.from_source(source, context), mode: Command)
}

/// Put a program that has already run back in the buffer, to change and run
/// again.
pub fn recall(shell: Shell, index: Int, context: infer.Context) -> Shell {
  case at(shell.history, index) {
    Some(Entry(buffer: previous, ..)) ->
      Shell(..shell, buffer: buffer.reanalyse(previous, context), mode: Command)
    None -> shell
  }
}

fn at(items: List(a), index: Int) -> Option(a) {
  case items, index {
    [item, ..], 0 -> Some(item)
    [_, ..rest], _ if index > 0 -> at(rest, index - 1)
    _, _ -> None
  }
}
