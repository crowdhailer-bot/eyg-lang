//// Node timers: https://nodejs.org/api/timers.html#timerspromisessettimeoutdelay-value-options

import gleam/javascript/promise.{type Promise}

@external(javascript, "./timers_ffi.mjs", "sleep")
pub fn sleep(milliseconds: Int) -> Promise(Nil)
