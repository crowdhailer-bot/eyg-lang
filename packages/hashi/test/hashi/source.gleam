//// Reading a file from disk, for tests only.
////
//// The page gets `eyg/context.eyg` from vite as a raw import; there is no file
//// system in a browser. Tests run under bun and read it straight.

@external(javascript, "./source_ffi.mjs", "read")
pub fn read(path: String) -> String
