//// Read prompts from stdin a byte at a time,
//// so input after the end of the line is left for the next read.

import gleam/bit_array
import gleam/result
import gleam/string
import plinthx/node/fs
import plinthx/node/process
import plinthx/node/stream

/// Write the prompt then read a single line from stdin, without the line ending.
/// Several lines piped at once are returned one per call.
/// Returns an error at the end of input.
pub fn read_line(prompt: String) -> Result(String, Nil) {
  use process <- result.try(process.get())
  stream.write(process.stdout(process), prompt)
  read_until_newline(<<>>)
}

fn read_until_newline(line: BitArray) -> Result(String, Nil) {
  case fs.read_sync(0, 1) {
    Ok(<<"\n">>) -> Ok(decode(line))
    Ok(<<>>) | Error("EOF") ->
      case line {
        <<>> -> Error(Nil)
        _ -> Ok(decode(line))
      }
    Ok(byte) -> read_until_newline(<<line:bits, byte:bits>>)
    // Non blocking stdin has no input yet.
    Error("EAGAIN") -> read_until_newline(line)
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
