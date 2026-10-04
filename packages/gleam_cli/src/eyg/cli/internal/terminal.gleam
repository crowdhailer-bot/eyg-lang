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
