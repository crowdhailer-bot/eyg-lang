//// Native mutable array operations, supplementing gleam/javascript/array.

import gleam/javascript/array.{type Array}

/// Assign an array element. Frozen arrays and invalid indices may reject writes.
@external(javascript, "./array_ffi.mjs", "set")
pub fn set(array: Array(a), index: Int, value: a) -> Result(Nil, String)
