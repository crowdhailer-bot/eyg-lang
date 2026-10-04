//// Bun subprocess APIs: https://bun.sh/docs/api/spawn

import gleam/dynamic.{type Dynamic}
import gleam/javascript/promise.{type Promise}
import plinth/browser/readable_stream.{type ReadableStream}
import plinthx/bun.{type Bun}

pub type Subprocess

/// Native spawn options. Stream values are "ignore", "pipe", or "inherit".
pub type Options {
  Options(
    cwd: String,
    env: List(#(String, String)),
    stdin: String,
    stdout: String,
    stderr: String,
    serialization: String,
    ipc: fn(Dynamic, Subprocess) -> Nil,
  )
}

@external(javascript, "../../subprocess.ffi.mjs", "spawn")
pub fn spawn(
  bun: Bun,
  command: List(String),
  options: Options,
) -> Result(Subprocess, String)

@external(javascript, "../../subprocess.ffi.mjs", "send")
pub fn send(process: Subprocess, message: Dynamic) -> Result(Nil, String)

@external(javascript, "../../subprocess.ffi.mjs", "kill")
pub fn kill(process: Subprocess, signal: String) -> Result(Nil, String)

@external(javascript, "../../subprocess.ffi.mjs", "exited")
pub fn exited(process: Subprocess) -> Promise(Result(Int, String))

@external(javascript, "../../subprocess.ffi.mjs", "stderr")
pub fn stderr(process: Subprocess) -> Result(ReadableStream, Nil)

@external(javascript, "../../subprocess.ffi.mjs", "readableStreamToText")
pub fn readable_stream_to_text(
  bun: Bun,
  stream: ReadableStream,
) -> Promise(Result(String, String))
