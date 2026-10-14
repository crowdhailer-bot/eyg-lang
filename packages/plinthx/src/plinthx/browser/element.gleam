//// HTMLElement and Element methods absent from published Plinth.

import plinth/browser/element.{type Element}

@external(javascript, "./element_ffi.mjs", "click")
pub fn click(element: Element) -> Nil

@external(javascript, "./element_ffi.mjs", "scrollNearest")
pub fn scroll_nearest(element: Element) -> Nil
