//// The page: the board on the right, and on the left the two ways of writing
//// programs against it.
////
//// The board is drawn by the original hashi project and every pointer event it
//// produces is thrown away, so there is nothing to click on it. That is the
//// whole point of the demonstration: the only way to move is to run a program,
//// whether a person writes it in the shell or a model writes it from English.

import gleam/dynamic/decode
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import hashi/game
import hashi/shell
import hashi/state.{type State, State}
import lustre/attribute as a
import lustre/element
import lustre/element/html as h
import lustre/element/svg
import lustre/event
import morph/lustre/projection as projection_ui
import morph/picker
import overlay/web/components/chat
import overlay/web/components/input
import overlay/web/components/provider_setup as provider_view
import overlay/web/state as agent
import overlay/web/view as agent_view

pub fn render(model: State) -> element.Element(state.Message) {
  h.div([a.class("layout")], [
    h.aside([a.class("panel")], [
      rail(model.panel),
      case model.panel {
        state.Shell -> shell_panel(model)
        state.Agent -> agent_panel(model)
      },
    ]),
    board(model),
  ])
}

// THE RAIL --------------------------------------------------------------------

fn rail(panel: state.Panel) {
  h.nav([a.class("rail")], [
    rail_button(panel == state.Shell, state.Shell, "Shell", terminal_icon()),
    rail_button(panel == state.Agent, state.Agent, "Agent", sparkle_icon()),
  ])
}

fn rail_button(selected, panel, label, icon) {
  h.button(
    [
      a.class("rail-button"),
      a.classes([#("selected", selected)]),
      a.type_("button"),
      a.title(label),
      a.attribute("aria-label", label),
      event.on_click(state.UserSelectedPanel(panel)),
    ],
    [icon],
  )
}

fn icon(children) {
  h.svg(
    [
      a.class("icon"),
      a.attribute("viewBox", "0 0 24 24"),
      a.attribute("fill", "none"),
      a.attribute("stroke", "currentColor"),
      a.attribute("stroke-width", "2"),
      a.attribute("stroke-linecap", "round"),
      a.attribute("stroke-linejoin", "round"),
    ],
    children,
  )
}

fn terminal_icon() {
  icon([
    svg.polyline([a.attribute("points", "5 8 9 12 5 16")]),
    svg.line([
      a.attribute("x1", "12"),
      a.attribute("y1", "17"),
      a.attribute("x2", "19"),
      a.attribute("y2", "17"),
    ]),
  ])
}

fn sparkle_icon() {
  icon([
    svg.path([
      a.attribute(
        "d",
        "M12 3 L13.8 9.2 L20 11 L13.8 12.8 L12 19 L10.2 12.8 L4 11 L10.2 9.2 Z",
      ),
    ]),
  ])
}

// THE BOARD -------------------------------------------------------------------

fn board(model: State) {
  let playing = state.board(model)
  h.main([a.class("board")], [
    h.h1([], [h.text("Hashi")]),
    h.div([a.class("board-frame")], [game.view(playing, state.Ignore)]),
    h.p(
      [
        a.class("board-status"),
        a.classes([#("solved", state.is_complete(model))]),
      ],
      [
        h.text(case state.is_complete(model) {
          True -> "Solved."
          False -> "Nothing on this board is clickable. Write a program."
        }),
      ],
    ),
  ])
}

// THE SHELL -------------------------------------------------------------------

fn shell_panel(model: State) {
  let shell.Shell(buffer:, mode:, history:, help:) = model.shell

  h.section([a.class("panel-body shell")], [
    case model.failure {
      Some(reason) -> h.p([a.class("failure")], [h.text(reason)])
      None -> element.none()
    },
    h.div(
      [a.class("shell-history")],
      list.reverse(list.index_map(history, previous)),
    ),
    // Keys are listened for on the page, not here: a prompt takes the focus
    // while a name is being typed and the shell has nothing to give it back to.
    h.div([a.class("shell-editor")], [
      projection_ui.code(buffer.projection, buffer.analysis, fn(path) {
        state.ShellMessage(shell.UserClickedCode(path))
      }),
    ]),
    prompt(mode),
    h.div([a.class("shell-actions")], [
      h.button(
        [
          a.class("button"),
          a.type_("button"),
          event.on_click(state.ShellMessage(shell.UserToggledHelp)),
        ],
        [h.text("keys")],
      ),
      h.button(
        [
          a.class("button run"),
          a.type_("button"),
          event.on_click(state.ShellMessage(shell.UserClickedRun)),
        ],
        [h.text("run")],
      ),
    ]),
    case help {
      True -> keys()
      False -> element.none()
    },
  ])
}

/// A program already run, with what came of it.
fn previous(entry: shell.Entry, index: Int) {
  let shell.Entry(buffer:, outcome:) = entry
  h.div([a.class("shell-entry")], [
    h.div(
      [
        a.class("shell-entry-code"),
        event.on_click(state.ShellMessage(shell.UserClickedPrevious(index))),
      ],
      [projection_ui.render_projection(buffer.projection, [])],
    ),
    case outcome {
      shell.Working -> h.div([a.class("shell-outcome working")], [h.text("…")])
      shell.Returned(value) ->
        h.div([a.class("shell-outcome")], [h.text(value)])
      shell.Failed(reason) ->
        h.div([a.class("shell-outcome failed")], [h.text(reason)])
    },
  ])
}

/// While a name or a number is being written, or one of a list chosen.
fn prompt(mode: shell.Mode) {
  case mode {
    shell.Command -> element.none()
    shell.Writing(value:, ..) -> writing_prompt("name", value)
    shell.Numbering(value:, ..) -> writing_prompt("number", value)
    shell.Choosing(picker: chosen, ..) ->
      h.div([a.class("shell-prompt")], [
        picker.render(chosen)
        |> element.map(fn(message) {
          state.ShellMessage(case message {
            picker.Updated(picker: moved) -> shell.UserMovedPicker(moved)
            picker.Decided(value:) -> shell.UserChoseSuggestion(value)
            picker.Dismissed -> shell.UserDismissedInput
          })
        }),
      ])
  }
}

fn writing_prompt(label: String, value: String) {
  h.div([a.class("shell-prompt")], [
    h.label([], [h.text(label)]),
    h.input([
      a.value(value),
      a.autofocus(True),
      event.on_input(fn(value) {
        state.ShellMessage(shell.UserWroteInput(value))
      }),
      event.on("keydown", prompt_key_decoder()),
    ]),
  ])
}

fn prompt_key_decoder() {
  use key <- decode.field("key", decode.string)
  decode.success(
    state.ShellMessage(case key {
      "Enter" -> shell.UserSubmittedInput
      "Escape" -> shell.UserDismissedInput
      _ -> shell.UserPressedKey(key)
    }),
  )
}

fn keys() {
  h.div(
    [a.class("shell-keys")],
    list.map(bindings(), fn(binding) {
      let #(key, action) = binding
      h.div([], [
        h.kbd([], [h.text(key)]),
        h.span([], [h.text(action)]),
      ])
    }),
  )
}

fn bindings() {
  [
    #("arrows", "move about the program"),
    #("space", "jump to the next hole"),
    #("a", "select more"),
    #("ctrl+enter", "run it"),
    #("s", "a string"),
    #("n", "a number"),
    #("v", "a variable"),
    #("e", "give this a name"),
    #("f", "wrap in a function"),
    #("c", "call it"),
    #("w", "call something with it"),
    #("r", "a record, fields separated by commas"),
    #("g", "select a field"),
    #("t", "a tag"),
    #("m", "match, branches separated by commas"),
    #("l", "a list"),
    #("p", "perform an effect"),
    #("j", "a builtin"),
    #("d", "delete"),
    #("z", "undo the writing"),
  ]
}

// THE AGENT -------------------------------------------------------------------

fn agent_panel(model: State) {
  let conversation = agent_view.messages(model.agent)
  h.section([a.class("panel-body agent")], [
    h.header([a.class("agent-header")], [
      provider_view.render(model.agent) |> element.map(state.AgentMessage),
    ]),
    case conversation {
      [] ->
        h.div([a.class("agent-empty")], [
          h.p([], [h.text("Ask for a move.")]),
          h.p([a.class("hint")], [
            h.text(
              "The model writes the same programs the shell does, against the "
              <> "same six effects. Every one is there to read before it runs.",
            ),
          ]),
        ])
      _ ->
        h.div([a.class("messages")], chat.render(model.agent))
        |> element.map(state.AgentMessage)
    },
    case model.agent.input_error {
      Some(error) -> h.div([a.class("failure")], [h.text(error)])
      None -> element.none()
    },
    input.render(
      model.agent.input,
      "Ask for a move...",
      agent.UserUpdatedInput,
      agent.UserSubmittedPrompt,
      agent.Ignore,
    )
      |> element.map(state.AgentMessage),
  ])
}

/// The board is one puzzle a day, which is what the original project plays.
/// Nothing here needs it, it is the page's own tidiness.
pub fn seed_label(seed: Int) -> String {
  "#" <> int.to_string(seed)
}
