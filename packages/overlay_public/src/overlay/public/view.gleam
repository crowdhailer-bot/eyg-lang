import gleam/list
import gleam/option.{None, Some}
import lustre/attribute as a
import lustre/element
import lustre/element/html as h
import overlay/web/components/chat
import overlay/web/components/input
import overlay/web/components/provider_setup as provider_view
import overlay/web/state
import overlay/web/view

pub fn render(model: state.State(host)) {
  // let state = demo()
  let messages = view.messages(model)
  h.div([a.class("layout")], [
    h.div([a.class("chat")], [
      h.header(
        [
          a.class("heading"),
          a.classes([#("hero", list.is_empty(messages))]),
        ],
        [
          h.h1([a.class("impact-heading")], [h.text("Overlay")]),
          provider_view.render(model),
        ],
      ),
      case messages {
        [] -> element.none()
        _ -> h.div([a.class("messages")], chat.render(model))
      },
      case model.input_error {
        Some(error) -> h.div([a.class("failure-message")], [h.text(error)])
        None -> element.none()
      },
      input.render(
        model.input,
        "Ask anything...",
        state.UserUpdatedInput,
        state.UserSubmittedPrompt,
        state.Ignore,
      ),
    ]),
    // h.div([a.class("output")], [
  //   // h.div([], [h.span([], [h.text("cell1")])]),
  // // h.div([], [h.span([], [h.text("cell2")])]),
  // // h.div([], [h.span([], [h.text("cell3")])]),
  // // h.div([], [h.span([], [h.text("cell4")])]),
  // // h.div([], [h.span([], [h.text("cell5")])]),
  // ]),
  ])
}
