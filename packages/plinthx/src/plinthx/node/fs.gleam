//// Node filesystem APIs: https://nodejs.org/api/fs.html

import gleam/javascript/promise.{type Promise}

pub type Dirent

@external(javascript, "./fs_ffi.mjs", "readdir")
pub fn readdir_with_file_types(
  path: String,
) -> Promise(Result(List(Dirent), String))

@external(javascript, "./fs_ffi.mjs", "name")
pub fn name(entry: Dirent) -> String

@external(javascript, "./fs_ffi.mjs", "isDirectory")
pub fn is_directory(entry: Dirent) -> Bool

/// Read up to `length` bytes from a file descriptor, an empty result is the end of the file.
/// The error is the error's code, such as `EAGAIN`.
@external(javascript, "./fs_ffi.mjs", "readSync")
pub fn read_sync(fd: Int, length: Int) -> Result(BitArray, String)
