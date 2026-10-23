import morph/frame.{Div, Span}

pub fn focus() {
  [frame.Focus]
}

pub fn error() {
  [frame.Problem]
}

pub fn frame(frame, attributes) {
  case frame {
    frame.Inline(text) -> frame.Inline([spans(text, attributes)])
    frame.Multiline(pre, inner, post) -> {
      frame.Multiline([spans(pre, attributes)], [Div(attributes, inner)], [
        spans(post, attributes),
      ])
    }
    frame.Statements(inner) -> frame.Statements([Div(attributes, inner)])
  }
}

pub fn spans(spans, attributes) {
  Span(attributes, spans)
}
