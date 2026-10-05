//// Native Node readable and writable streams.

pub type Stream

/// Write a chunk to a writable stream, false when the stream's buffer is full.
@external(javascript, "./stream_ffi.mjs", "write")
pub fn write(stream: Stream, chunk: String) -> Bool
