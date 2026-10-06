//// Styling for terminal output, plain text when output is not a terminal or NO_COLOR is set.

import gleam/javascript/array.{type Array}
import gleam/list
import plinthx/javascript/array as mutable
import plinthx/node/process
import plinthx/node/tty

/// According to specification NO_COLOR only disables colors however it's often useful to remove all ansi codes in that case.
pub fn noninteractive() -> Bool {
  case process.get() {
    Ok(process) ->
      tty.is_tty(process.stdout(process)) == Ok(True) && !no_color(process)
    Error(Nil) -> False
  }
}

fn no_color(process) {
  case list.key_find(process.env(process), "NO_COLOR") {
    Ok("") | Error(Nil) -> False
    Ok(_) -> True
  }
}

/// Apply an ansi style function only when writing to a terminal.
pub fn style(apply: fn(String) -> String, text: String) -> String {
  case noninteractive() {
    True -> apply(text)
    False -> text
  }
}

/// Records Ctrl-C while a turn runs, so it stops the turn rather than the process.
pub opaque type Interrupt {
  Interrupt(pressed: Array(Bool), listener: fn() -> Nil)
}

pub fn interrupt() -> Interrupt {
  let pressed = array.from_list([False])
  let listener = fn() {
    let _ = mutable.set(pressed, 0, True)
    Nil
  }
  Interrupt(pressed:, listener:)
}

/// Catch Ctrl-C until `end_turn`, check it with `interrupted`.
pub fn start_turn(interrupt: Interrupt) -> Nil {
  let _ = mutable.set(interrupt.pressed, 0, False)
  let _ = case process.get() {
    Ok(process) -> process.on_signal(process, "SIGINT", interrupt.listener)
    Error(Nil) -> Error("no process")
  }
  Nil
}

pub fn end_turn(interrupt: Interrupt) -> Nil {
  let _ = case process.get() {
    Ok(process) ->
      process.remove_signal_listener(process, "SIGINT", interrupt.listener)
    Error(Nil) -> Error("no process")
  }
  Nil
}

/// Has the user pressed Ctrl-C since the turn started.
pub fn interrupted(interrupt: Interrupt) -> Bool {
  array.get(interrupt.pressed, 0) == Ok(True)
}
