//// Bun subprocesses: https://bun.sh/docs/api/spawn

import gleam/dynamic.{type Dynamic}
import gleam/javascript/promise.{type Promise}
import plinthx/browser/readable_stream.{type ReadableStream}
import plinthx/bun/runtime.{type Bun}

pub type Subprocess

pub type Options {
  Options(
    cmd: List(String),
    cwd: String,
    env: List(#(String, String)),
    stdin: String,
    stdout: String,
    stderr: String,
  )
}

@external(javascript, "./subprocess_ffi.mjs", "spawn")
pub fn spawn(bun: Bun, options: Options) -> Result(Subprocess, String)

@external(javascript, "./subprocess_ffi.mjs", "exited")
pub fn exited(process: Subprocess) -> Promise(Result(Int, String))

@external(javascript, "./subprocess_ffi.mjs", "stdout")
pub fn stdout(process: Subprocess) -> Result(ReadableStream, Nil)

@external(javascript, "./subprocess_ffi.mjs", "stderr")
pub fn stderr(process: Subprocess) -> Result(ReadableStream, Nil)

pub type IpcOptions {
  IpcOptions(
    cwd: String,
    env: List(#(String, String)),
    stdin: String,
    stdout: String,
    stderr: String,
    serialization: String,
    ipc: fn(Dynamic, Subprocess) -> Nil,
  )
}

@external(javascript, "./subprocess_ffi.mjs", "spawnIpc")
pub fn spawn_ipc(
  bun: Bun,
  command: List(String),
  options: IpcOptions,
) -> Result(Subprocess, String)

@external(javascript, "./subprocess_ffi.mjs", "send")
pub fn send(process: Subprocess, message: Dynamic) -> Result(Nil, String)

@external(javascript, "./subprocess_ffi.mjs", "kill")
pub fn kill(process: Subprocess, signal: String) -> Result(Nil, String)

@external(javascript, "./subprocess_ffi.mjs", "readableStreamToText")
pub fn readable_stream_to_text(
  bun: Bun,
  stream: ReadableStream,
) -> Promise(Result(String, String))
