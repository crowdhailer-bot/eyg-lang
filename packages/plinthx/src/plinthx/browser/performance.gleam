//// High Resolution Time: https://www.w3.org/TR/hr-time-3/

pub type Performance

@external(javascript, "./performance_ffi.mjs", "get")
pub fn get() -> Result(Performance, Nil)

@external(javascript, "./performance_ffi.mjs", "now")
pub fn now(performance: Performance) -> Float
