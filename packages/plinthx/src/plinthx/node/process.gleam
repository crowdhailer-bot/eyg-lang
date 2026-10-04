//// Node process: https://nodejs.org/api/process.html

import gleam/dynamic.{type Dynamic}
import gleam/javascript/array.{type Array}
import plinthx/node/stream.{type Stream}

@external(javascript, "../../process.ffi.mjs", "stdin")
pub fn stdin(process: Process) -> Stream

@external(javascript, "../../process.ffi.mjs", "stdout")
pub fn stdout(process: Process) -> Stream

pub type Process

@external(javascript, "../../process.ffi.mjs", "get")
pub fn get() -> Result(Process, Nil)

@external(javascript, "../../process.ffi.mjs", "argv")
pub fn argv(process: Process) -> Array(String)

@external(javascript, "../../process.ffi.mjs", "execPath")
pub fn exec_path(process: Process) -> String

@external(javascript, "../../process.ffi.mjs", "cwd")
pub fn cwd(process: Process) -> Result(String, String)

@external(javascript, "../../process.ffi.mjs", "env")
pub fn env(process: Process) -> List(#(String, String))

@external(javascript, "../../process.ffi.mjs", "send")
pub fn send(process: Process, message: Dynamic) -> Result(Nil, String)

@external(javascript, "../../process.ffi.mjs", "onMessage")
pub fn on_message(
  process: Process,
  callback: fn(Dynamic) -> Nil,
) -> Result(Process, String)

@external(javascript, "../../process.ffi.mjs", "onDisconnect")
pub fn on_disconnect(
  process: Process,
  callback: fn() -> Nil,
) -> Result(Process, String)

@external(javascript, "../../process.ffi.mjs", "onceExit")
pub fn once_exit(
  process: Process,
  callback: fn(Int) -> Nil,
) -> Result(Process, String)

@external(javascript, "../../process.ffi.mjs", "removeExitListener")
pub fn remove_exit_listener(
  process: Process,
  callback: fn(Int) -> Nil,
) -> Result(Process, String)

@external(javascript, "../../process.ffi.mjs", "exit")
pub fn exit(process: Process, code: Int) -> Nil
