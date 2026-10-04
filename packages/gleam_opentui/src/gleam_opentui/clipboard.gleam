//// OpenTUI's native host clipboard service. Statuses and representations are
//// returned unchanged; fallback and clipboard policy belong to the caller.

import gleam/javascript/promise.{type Promise}

pub type HostClipboard

pub type ReadResult

pub type WriteResult

pub type Representation

@external(javascript, "../clipboard.ffi.mjs", "create")
pub fn create(options_json: String) -> Result(HostClipboard, String)

@external(javascript, "../clipboard.ffi.mjs", "read")
pub fn read(
  service: HostClipboard,
  options_json: String,
) -> Promise(Result(ReadResult, String))

@external(javascript, "../clipboard.ffi.mjs", "writeText")
pub fn write_text(
  service: HostClipboard,
  text: String,
) -> Promise(Result(WriteResult, String))

@external(javascript, "../clipboard.ffi.mjs", "dispose")
pub fn dispose(service: HostClipboard) -> Promise(Result(Nil, String))

@external(javascript, "../clipboard.ffi.mjs", "status")
pub fn read_status(result: ReadResult) -> String

@external(javascript, "../clipboard.ffi.mjs", "status")
pub fn write_status(result: WriteResult) -> String

@external(javascript, "../clipboard.ffi.mjs", "representation")
pub fn representation(result: ReadResult) -> Result(Representation, Nil)

@external(javascript, "../clipboard.ffi.mjs", "mimeType")
pub fn mime_type(representation: Representation) -> String

@external(javascript, "../clipboard.ffi.mjs", "bytes")
pub fn bytes(representation: Representation) -> BitArray
