//// The HTML queueMicrotask global function, also implemented by Bun and Node.

pub type QueueMicrotask

@external(javascript, "./microtask_ffi.mjs", "get")
pub fn get() -> Result(QueueMicrotask, Nil)

@external(javascript, "./microtask_ffi.mjs", "call")
pub fn call(queue: QueueMicrotask, callback: fn() -> Nil) -> Result(Nil, String)
