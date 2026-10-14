//// Convenience facade over the existing native Fetch Request bindings.

import plinthx/browser/fetch

pub type Request =
  fetch.Request

pub fn text(request: Request) {
  fetch.request_text(request)
}
