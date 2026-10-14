import plinthx/bun/runtime

pub type Bun =
  runtime.Bun

pub fn get() {
  runtime.get()
}

@external(javascript, "./bun_ffi.mjs", "stringWidth")
pub fn string_width(bun: Bun, text: String) -> Int
