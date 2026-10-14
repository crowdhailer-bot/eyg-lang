//// Node filesystem: https://nodejs.org/api/fs.html#fsmkdtempsyncprefix-options

import gleam/javascript/promise.{type Promise}

pub type Dirent

@external(javascript, "./fs_ffi.mjs", "temporaryDirectory")
pub fn temporary_directory(prefix: String) -> Result(String, String)

@external(javascript, "./fs_ffi.mjs", "readdir")
pub fn readdir_with_file_types(
  path: String,
) -> Promise(Result(List(Dirent), String))

@external(javascript, "./fs_ffi.mjs", "name")
pub fn name(entry: Dirent) -> String

@external(javascript, "./fs_ffi.mjs", "isDirectory")
pub fn is_directory(entry: Dirent) -> Bool

@external(javascript, "./fs_ffi.mjs", "readSync")
pub fn read_sync(fd: Int, length: Int) -> Result(BitArray, String)
