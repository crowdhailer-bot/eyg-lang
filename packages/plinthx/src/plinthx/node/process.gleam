//// Node process: https://nodejs.org/api/process.html

import gleam/dynamic.{type Dynamic}
import gleam/javascript/array.{type Array}
import plinthx/node/stream.{type Stream}

@external(javascript, "./process_ffi.mjs", "stdin")
pub fn stdin(process: Process) -> Stream

@external(javascript, "./process_ffi.mjs", "stdout")
pub fn stdout(process: Process) -> Stream

pub type Process

@external(javascript, "./process_ffi.mjs", "get")
pub fn get() -> Result(Process, Nil)

@external(javascript, "./process_ffi.mjs", "argv")
pub fn argv(process: Process) -> Array(String)

@external(javascript, "./process_ffi.mjs", "execPath")
pub fn exec_path(process: Process) -> String

@external(javascript, "./process_ffi.mjs", "cwd")
pub fn cwd(process: Process) -> Result(String, String)

@external(javascript, "./process_ffi.mjs", "env")
pub fn env(process: Process) -> List(#(String, String))

@external(javascript, "./process_ffi.mjs", "send")
pub fn send(process: Process, message: Dynamic) -> Result(Nil, String)

@external(javascript, "./process_ffi.mjs", "onMessage")
pub fn on_message(
  process: Process,
  callback: fn(Dynamic) -> Nil,
) -> Result(Process, String)

@external(javascript, "./process_ffi.mjs", "onDisconnect")
pub fn on_disconnect(
  process: Process,
  callback: fn() -> Nil,
) -> Result(Process, String)

@external(javascript, "./process_ffi.mjs", "onceExit")
pub fn once_exit(
  process: Process,
  callback: fn(Int) -> Nil,
) -> Result(Process, String)

@external(javascript, "./process_ffi.mjs", "removeExitListener")
pub fn remove_exit_listener(
  process: Process,
  callback: fn(Int) -> Nil,
) -> Result(Process, String)

@external(javascript, "./process_ffi.mjs", "exit")
pub fn exit(process: Process, code: Int) -> Nil

/// Listen for a signal such as `SIGINT`, the process is no longer stopped by it.
@external(javascript, "./process_ffi.mjs", "onSignal")
pub fn on_signal(
  process: Process,
  signal: String,
  callback: fn() -> Nil,
) -> Result(Process, String)

@external(javascript, "./process_ffi.mjs", "removeSignalListener")
pub fn remove_signal_listener(
  process: Process,
  signal: String,
  callback: fn() -> Nil,
) -> Result(Process, String)

/// The code the process exits with once it has nothing left to do.
@external(javascript, "./process_ffi.mjs", "setExitCode")
pub fn set_exit_code(process: Process, code: Int) -> Nil
