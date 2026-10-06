//// Read prompts from stdin a byte at a time,
//// so input after the end of the line is left for the next read.

import gleam/bit_array
import gleam/int
import gleam/list
import gleam/order
import gleam/result
import gleam/string
import plinthx/node/fs
import plinthx/node/process
import plinthx/node/stream.{type Stream}
import plinthx/node/tty

/// Write the prompt then read a single line from stdin, without the line ending.
/// Several lines piped at once are returned one per call.
/// Returns an error at the end of input.
///
/// At a terminal the line can be edited, with left and right, home and end,
/// backspace and delete, and earlier lines are recalled with up and down.
/// `history` is the lines entered so far, most recent first.
pub fn read_line(
  prompt: String,
  history: List(String),
) -> #(Result(String, Nil), List(String)) {
  case process.get() {
    Ok(process) -> {
      let stdout = process.stdout(process)
      stream.write(stdout, prompt)
      let stdin = process.stdin(process)
      case tty.is_tty(stdin) {
        Ok(True) -> edit_line(stdin, stdout, history)
        _ -> #(read_until_newline(<<>>), history)
      }
    }
    Error(Nil) -> #(Error(Nil), history)
  }
}

fn read_until_newline(line: BitArray) -> Result(String, Nil) {
  case read_byte() {
    Ok(<<"\n">>) -> Ok(decode(line))
    Ok(byte) -> read_until_newline(<<line:bits, byte:bits>>)
    Error(Nil) ->
      case line {
        <<>> -> Error(Nil)
        _ -> Ok(decode(line))
      }
  }
}

/// Read one byte from stdin, an error at the end of input.
fn read_byte() -> Result(BitArray, Nil) {
  case fs.read_sync(0, 1) {
    Ok(<<>>) | Error("EOF") -> Error(Nil)
    Ok(byte) -> Ok(byte)
    // Non blocking stdin has no input yet.
    Error("EAGAIN") -> read_byte()
    Error(_) -> Error(Nil)
  }
}

fn decode(line: BitArray) -> String {
  let text = bit_array.to_string(line) |> result.unwrap("")
  case string.ends_with(text, "\r") {
    True -> string.drop_end(text, 1)
    False -> text
  }
}

/// The characters before the cursor, nearest first, and after it.
type Line {
  Line(before: List(String), after: List(String))
}

/// Ctrl-C, or Ctrl-D on an empty line, ends input.
fn edit_line(stdin: Stream, stdout: Stream, history: List(String)) {
  // Save the cursor so the line can be redrawn after the prompt.
  stream.write(stdout, "\u{1b}7")
  let _ = tty.set_raw_mode(stdin, True)
  let result = edit(stdout, Line([], []), history, 0)
  let _ = tty.set_raw_mode(stdin, False)
  stream.write(stdout, "\n")
  result
}

/// `browsing` is how far back in the history the line is, 0 for a new line.
fn edit(stdout, line: Line, history: List(String), browsing: Int) {
  let continue = fn(line) {
    redraw(stdout, line)
    edit(stdout, line, history, browsing)
  }
  case read_key() {
    Error(Nil) -> #(Error(Nil), history)
    Ok("\r") | Ok("\n") -> {
      let text = to_string(line)
      redraw(stdout, Line(list.reverse(string.to_graphemes(text)), []))
      let history = case text {
        "" -> history
        _ -> [text, ..history]
      }
      #(Ok(text), history)
    }
    Ok("\u{03}") -> #(Error(Nil), history)
    Ok("\u{04}") if line.before == [] && line.after == [] -> #(
      Error(Nil),
      history,
    )
    // Backspace
    Ok("\u{7f}") | Ok("\u{08}") ->
      case line.before {
        [_, ..before] -> continue(Line(..line, before:))
        [] -> continue(line)
      }
    // Ctrl-A and Ctrl-E
    Ok("\u{01}") -> continue(home(line))
    Ok("\u{05}") -> continue(end(line))
    // Ctrl-U
    Ok("\u{15}") -> continue(Line([], []))
    Ok("\u{1b}" <> sequence) ->
      case sequence {
        "D" ->
          case line.before {
            [char, ..before] -> continue(Line(before, [char, ..line.after]))
            [] -> continue(line)
          }
        "C" ->
          case line.after {
            [char, ..after] -> continue(Line([char, ..line.before], after))
            [] -> continue(line)
          }
        "H" | "1~" -> continue(home(line))
        "F" | "4~" -> continue(end(line))
        "3~" ->
          case line.after {
            [_, ..after] -> continue(Line(..line, after:))
            [] -> continue(line)
          }
        "A" | "B" if history != [] -> {
          let browsing = case sequence {
            "A" -> int.min(list.length(history), browsing + 1)
            _ -> int.max(0, browsing - 1)
          }
          let text = case list.drop(history, browsing - 1), browsing {
            [text, ..], b if b > 0 -> text
            _, _ -> ""
          }
          let line = Line(list.reverse(string.to_graphemes(text)), [])
          redraw(stdout, line)
          edit(stdout, line, history, browsing)
        }
        _ -> continue(line)
      }
    Ok(char) ->
      case string.compare(char, " ") {
        order.Lt -> continue(line)
        _ -> continue(Line(..line, before: [char, ..line.before]))
      }
  }
}

fn home(line: Line) {
  Line([], list.append(list.reverse(line.before), line.after))
}

fn end(line: Line) {
  Line(list.append(list.reverse(line.after), line.before), [])
}

fn to_string(line: Line) {
  string.concat(list.append(list.reverse(line.before), line.after))
}

fn redraw(stdout: Stream, line: Line) {
  let back = case list.length(line.after) {
    0 -> ""
    n -> "\u{1b}[" <> int.to_string(n) <> "D"
  }
  stream.write(stdout, "\u{1b}8" <> to_string(line) <> "\u{1b}[0K" <> back)
  Nil
}

/// Read a key: a character, or an escape sequence as `ESC` followed by any
/// parameter digits and the final character, i.e. `ESC 3~` for delete.
fn read_key() -> Result(String, Nil) {
  use byte <- result.try(read_byte())
  case byte {
    <<0x1b>> ->
      case read_byte() {
        Ok(<<"[">>) -> result.map(read_sequence(""), string.append("\u{1b}", _))
        Ok(<<"O">>) -> result.map(read_sequence(""), string.append("\u{1b}", _))
        Ok(_) -> Ok("\u{1b}")
        Error(Nil) -> Error(Nil)
      }
    <<lead>> -> read_character(byte, continuation_bytes(lead))
    _ -> Error(Nil)
  }
}

fn read_sequence(parameters: String) -> Result(String, Nil) {
  use byte <- result.try(read_byte())
  case bit_array.to_string(byte) {
    Ok(digit) ->
      case int.parse(digit) {
        Ok(_) -> read_sequence(parameters <> digit)
        Error(Nil) -> Ok(parameters <> digit)
      }
    Error(Nil) -> Ok("")
  }
}

fn continuation_bytes(lead: Int) {
  case lead {
    _ if lead >= 0xf0 -> 3
    _ if lead >= 0xe0 -> 2
    _ if lead >= 0xc0 -> 1
    _ -> 0
  }
}

fn read_character(bytes: BitArray, remaining: Int) -> Result(String, Nil) {
  case remaining {
    0 -> Ok(bit_array.to_string(bytes) |> result.unwrap(""))
    _ -> {
      use byte <- result.try(read_byte())
      read_character(<<bytes:bits, byte:bits>>, remaining - 1)
    }
  }
}
