//// Record the playground in a browser.
//// `gleam run -m jev_playground/record -- screenshot <path> <file.png>`
//// `gleam run -m jev_playground/record -- video <path> <file.mp4>`
//// The dev server must be running, playwright needs Node rather than Bun.

import argv
import gleam/int
import gleam/io
import gleam/javascript/promise.{type Promise}

const origin = "http://localhost:8095"

pub fn main() {
  case argv.load().arguments {
    ["screenshot", path, file] -> {
      use text <- promise.map(screenshot(origin <> path, file, 30_000))
      io.println(text)
    }
    ["video", path, file] -> {
      use status <- promise.map(record(origin <> path, file, 30 * 60 * 1000))
      io.println(file <> " " <> status)
    }
    ["video", path, file, minutes] -> {
      let assert Ok(minutes) = int.parse(minutes)
      use status <- promise.map(record(
        origin <> path,
        file,
        minutes * 60 * 1000,
      ))
      io.println(file <> " " <> status)
    }
    ["inspect", path, expression] -> {
      use result <- promise.map(inspect(
        origin <> path,
        expression,
        10 * 60 * 1000,
      ))
      io.println(result)
    }
    _ -> {
      io.println(
        "usage: screenshot <path> <file> | video <path> <file> [minutes]",
      )
      promise.resolve(Nil)
    }
  }
}

@external(javascript, "./record_ffi.mjs", "screenshot")
fn screenshot(url: String, path: String, wait: Int) -> Promise(String)

@external(javascript, "./record_ffi.mjs", "record")
fn record(url: String, output: String, timeout: Int) -> Promise(String)

@external(javascript, "./record_ffi.mjs", "inspect")
fn inspect(url: String, expression: String, timeout: Int) -> Promise(String)
