import plinth/browser/element.{type Element}
import plinth/browser/window_proxy.{type WindowProxy}

/// The window of an element's nested browsing context, such as an iframe's.
@external(javascript, "./element_ffi.mjs", "contentWindow")
pub fn content_window(element: Element) -> Result(WindowProxy, Nil)
