//// Bun's namespace object has no public constructor; get checks its native APIs.

pub type Bun

@external(javascript, "../bun.ffi.mjs", "get")
pub fn get() -> Result(Bun, Nil)

@external(javascript, "../bun.ffi.mjs", "stringWidth")
pub fn string_width(bun: Bun, text: String) -> Int
