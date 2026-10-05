//// Node process: https://nodejs.org/api/process.html

import plinthx/node/stream.{type Stream}

pub type Process

@external(javascript, "./process_ffi.mjs", "get")
pub fn get() -> Result(Process, Nil)

@external(javascript, "./process_ffi.mjs", "stdout")
pub fn stdout(process: Process) -> Stream

@external(javascript, "./process_ffi.mjs", "env")
pub fn env(process: Process) -> List(#(String, String))

@external(javascript, "./process_ffi.mjs", "stdin")
pub fn stdin(process: Process) -> Stream

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
