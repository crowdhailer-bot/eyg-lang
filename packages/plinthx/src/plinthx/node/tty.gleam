//// https://nodejs.org/api/tty.html

import plinthx/node/stream.{type Stream}

/// Streams without terminal support have no isTTY property.
@external(javascript, "./process_ffi.mjs", "isTTY")
pub fn is_tty(stream: Stream) -> Result(Bool, Nil)

/// Read a terminal's input a key at a time, without echo or line editing.
@external(javascript, "./process_ffi.mjs", "setRawMode")
pub fn set_raw_mode(stream: Stream, mode: Bool) -> Result(Nil, String)
