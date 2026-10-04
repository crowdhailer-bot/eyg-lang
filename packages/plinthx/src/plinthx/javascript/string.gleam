import gleam/dynamic.{type Dynamic}

/// ECMAScript String(value). Objects may throw from their conversion hooks.
@external(javascript, "./string_ffi.mjs", "convert")
pub fn convert(value: Dynamic) -> Result(String, String)
