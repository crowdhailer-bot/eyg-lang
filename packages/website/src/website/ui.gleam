import gleam/dynamic/decode
import lustre/element
import morph/lustre/projection as projection_ui
import morph/projection as p

pub const code_area_styles = projection_ui.code_area_styles

pub const embed_area_styles = [
  #("box-shadow", "6px 6px black"),
  #("border-style", "solid"),
  #(
    "font-family",
    "ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, \"Liberation Mono\", \"Courier New\", monospace",
  ),
  #("background-color", "rgb(255, 255, 255)"),
  #("border-color", "rgb(0, 0, 0)"),
  #("border-width", "1px"),
  #("flex-direction", "column"),
  #("display", "flex"),
  #("margin-bottom", "1.5rem"),
  #("margin-top", ".5rem"),
]

/// render a code projection with errors and focus
pub fn code(projection, analysis, user_clicked_code) {
  projection_ui.code(projection, analysis, user_clicked_code)
}

pub fn render_projection(
  proj: #(p.Focus, List(p.Break)),
  errors: List(#(List(Int), a)),
) -> element.Element(b) {
  projection_ui.render_projection(proj, errors)
}

pub fn code_path_click_decoder(
  user_clicked_code: fn(List(Int)) -> a,
) -> decode.Decoder(a) {
  projection_ui.click_decoder(user_clicked_code)
}
