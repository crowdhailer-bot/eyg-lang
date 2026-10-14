//// Node filesystem: https://nodejs.org/api/fs.html#fsmkdtempsyncprefix-options

@external(javascript, "./fs_ffi.mjs", "temporaryDirectory")
pub fn temporary_directory(prefix: String) -> Result(String, String)
