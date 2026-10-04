//// Node filesystem APIs: https://nodejs.org/api/fs.html

import gleam/javascript/promise.{type Promise}

pub type Dirent

@external(javascript, "../../fs.ffi.mjs", "readdir")
pub fn readdir_with_file_types(
  path: String,
) -> Promise(Result(List(Dirent), String))

@external(javascript, "../../fs.ffi.mjs", "name")
pub fn name(entry: Dirent) -> String

@external(javascript, "../../fs.ffi.mjs", "isDirectory")
pub fn is_directory(entry: Dirent) -> Bool
