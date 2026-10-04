//// The HTML queueMicrotask global function, also implemented by Bun and Node.

pub type QueueMicrotask

@external(javascript, "../../microtask.ffi.mjs", "get")
pub fn get() -> Result(QueueMicrotask, Nil)

@external(javascript, "../../microtask.ffi.mjs", "call")
pub fn call(queue: QueueMicrotask, callback: fn() -> Nil) -> Result(Nil, String)
