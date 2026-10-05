//// Node filesystem APIs: https://nodejs.org/api/fs.html

/// Read up to `length` bytes from a file descriptor, an empty result is the end of the file.
/// The error is the error's code, such as `EAGAIN`.
@external(javascript, "./fs_ffi.mjs", "readSync")
pub fn read_sync(fd: Int, length: Int) -> Result(BitArray, String)
