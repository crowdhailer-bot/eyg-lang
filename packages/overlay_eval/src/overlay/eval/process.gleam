import gleam/io

pub fn fail(message: String) -> Nil {
  io.println_error(message)
  exit_code(1)
}

@external(javascript, "./process_ffi.mjs", "exitCode")
pub fn exit_code(code: Int) -> Nil
