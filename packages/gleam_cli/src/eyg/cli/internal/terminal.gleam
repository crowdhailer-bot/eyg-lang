//// Styling for terminal output, plain text when output is not a terminal or NO_COLOR is set.

@external(javascript, "./terminal_ffi.mjs", "isTty")
pub fn is_tty() -> Bool

/// Apply an ansi style function only when writing to a terminal.
pub fn style(apply: fn(String) -> String, text: String) -> String {
  case is_tty() {
    True -> apply(text)
    False -> text
  }
}

/// Catch Ctrl-C until `end_turn`, check it with `interrupted`.
@external(javascript, "./terminal_ffi.mjs", "startTurn")
pub fn start_turn() -> Nil

@external(javascript, "./terminal_ffi.mjs", "endTurn")
pub fn end_turn() -> Nil

/// Has the user pressed Ctrl-C since the turn started.
@external(javascript, "./terminal_ffi.mjs", "isInterrupted")
pub fn interrupted() -> Bool
