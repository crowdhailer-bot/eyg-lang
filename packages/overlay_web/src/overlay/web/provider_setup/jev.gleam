//// Jev, TypeSafe's decision model, builds a program one structural edit at a
//// time rather than generating text. Its requests go through the page's origin,
//// which forwards `/v1` to TypeSafe, as TypeSafe does not accept browser requests.

pub const id = "jev"

pub const label = "Jev"

pub const token_url = "https://typesafe.ai"

pub fn default_model() {
  "jev-latest"
}

pub fn models() {
  [#("jev-latest", "Jev latest"), #("jev-preview", "Jev preview")]
}
