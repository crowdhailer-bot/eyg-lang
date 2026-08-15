//// The application, driven the way it is driven in a browser: through the
//// shell, and through a model's tool calls.
////
//// The model is a fake here — the completions are written out rather than
//// asked for — but everything downstream of them is the real thing. The
//// programs are parsed, type checked and run, the effects are carried out
//// against the real board, and the board is the original project's.

import eyg/ir/tree as ir
import eyg/parser
import gleam/dict
import gleam/javascript/promise
import gleam/list
import gleam/option.{None}
import gleam/set
import gleam/string
import hashi/game
import hashi/harness
import hashi/shell
import hashi/source
import hashi/state.{type State, State}
import oas/generator/utils
import ogre/origin
import overlay/llm/chat
import overlay/llm/tool
import overlay/web/provider_setup
import overlay/web/state as agent
import overlay/web/tools
import shared/hashi

/// A square of four islands, each wanting two bridge ends. Four bridges round
/// the outside solves it.
///
/// ```txt
/// 2.2
/// ...
/// 2.2
/// ```
fn square() {
  hashi.from_islands_and_connections(
    width: 3,
    height: 3,
    islands: set.from_list([#(0, 0), #(2, 0), #(0, 2), #(2, 2)]),
    connections: [
      #(#(0, 0), #(2, 0), hashi.Single),
      #(#(0, 0), #(0, 2), hashi.Single),
      #(#(2, 0), #(2, 2), hashi.Single),
      #(#(0, 2), #(2, 2), hashi.Single),
    ],
  )
}

fn started() {
  let config =
    state.Config(
      origin: origin.https("hashi.test"),
      context: source.read("eyg/context.eyg"),
      puzzle: square(),
    )
  let #(state, _) = state.init(config)
  // The model will not be asked for anything until a provider is chosen.
  let #(state, _) =
    state.update(
      state,
      state.AgentMessage(
        agent.ProviderSetupMessage(provider_setup.SessionSettingsLoaded(
          "ollama",
          "qwen3.5:397b",
          "test-key",
        )),
      ),
    )
  state
}

// THE SHELL -------------------------------------------------------------------

/// Put a program in the shell and press run.
fn shell_runs(state: State, code: String) -> State {
  let assert Ok(tree) = parser.all_from_string(code)
  let shell =
    shell.edit(state.shell, ir.map_annotation(tree, fn(_) { [] }), state.infer)
  let state = State(..state, shell:)
  let #(state, _) =
    state.update(state, state.ShellMessage(shell.UserClickedRun))
  state
}

fn last_outcome(state: State) {
  let assert [shell.Entry(outcome:, ..), ..] = state.shell.history
  outcome
}

pub fn the_shell_opens_on_an_empty_program_test() {
  let state = started()
  assert state.Shell == state.panel
  assert [] == state.shell.history
  assert [] == game.bridges(state.board(state))
  assert None == state.failure
}

pub fn the_shell_can_look_at_the_board_test() {
  let state = shell_runs(started(), "picture({})")
  assert shell.Returned("2.2\n...\n2.2\n") == last_outcome(state)
}

pub fn a_program_from_the_shell_builds_a_bridge_test() {
  let state = shell_runs(started(), "connect({x: 0, y: 0}, {x: 2, y: 0})")
  assert shell.Returned("Ok({})") == last_outcome(state)
  assert [harness.Bridge(start: #(0, 0), end: #(2, 0), count: 1)]
    == game.bridges(state.board(state))
}

pub fn a_refused_bridge_leaves_the_board_alone_test() {
  let state = shell_runs(started(), "connect({x: 1, y: 1}, {x: 2, y: 0})")
  assert shell.Returned("Error(BadStart({}))") == last_outcome(state)
  assert [] == game.bridges(state.board(state))
}

pub fn a_program_that_will_not_run_says_why_test() {
  let state = shell_runs(started(), "nowhere({})")
  let assert shell.Failed(reason) = last_outcome(state)
  assert string.contains(reason, "nowhere")
  assert [] == game.bridges(state.board(state))
}

pub fn nothing_outside_the_game_is_reachable_from_the_shell_test() {
  let state = shell_runs(started(), "perform Fetch({})")
  let assert shell.Failed(reason) = last_outcome(state)
  assert string.contains(reason, "Fetch")
}

pub fn the_shell_keeps_what_it_has_run_test() {
  let state = shell_runs(started(), "connect({x: 0, y: 0}, {x: 2, y: 0})")
  let state = shell_runs(state, "count(bridges({}))")
  assert shell.Returned("1") == last_outcome(state)
  assert 2 == list.length(state.shell.history)
}

// THE AGENT -------------------------------------------------------------------

/// Everything the model says in one turn: some words, and the programs it
/// wants run.
fn model_says(state: State, text: String, programs: List(#(String, String))) {
  let tool_calls =
    list.map(programs, fn(program) {
      let #(id, code) = program
      tool.Call(
        id:,
        function: tool.FunctionCall(
          name: "run",
          arguments: dict.from_list([#("code", utils.String(code))]),
        ),
      )
    })
  let completion = chat.Completion(thinking: "", content: text, tool_calls:)
  let agent =
    agent.State(
      ..state.agent,
      status: agent.Streaming(
        reader: silent_reader(),
        completion:,
        remaining: <<>>,
      ),
    )
  let #(state, _) =
    state.update(
      State(..state, agent:),
      state.AgentMessage(agent.LlmStreamFinished(Ok(Nil))),
    )
  state
}

fn silent_reader() {
  fn() { promise.resolve(Ok(None)) }
}

/// What was sent back to the model for each program it asked to run.
fn tool_results(state: State) {
  let assert agent.Asking(messages:) = state.agent.status
  list.filter_map(messages, fn(message) {
    case message {
      chat.ToolResultMessage(text:, ..) -> Ok(text)
      _ -> Error(Nil)
    }
  })
}

pub fn the_agent_can_look_at_the_board_test() {
  let state = model_says(started(), "Let me look.", [#("a", "picture({})")])
  assert ["\"2.2\\n...\\n2.2\\n\""] == tool_results(state)
}

pub fn the_agent_builds_a_bridge_test() {
  let state =
    model_says(started(), "Joining those two.", [
      #("a", "connect({x: 0, y: 0}, {x: 2, y: 0})"),
    ])
  assert ["Ok({})"] == tool_results(state)
  assert [harness.Bridge(start: #(0, 0), end: #(2, 0), count: 1)]
    == game.bridges(state.board(state))
}

pub fn the_agent_is_told_why_a_bridge_was_refused_test() {
  let state =
    model_says(started(), "Trying this.", [
      #("a", "connect({x: 0, y: 0}, {x: 2, y: 2})"),
    ])
  assert ["Error(BadEnd({}))"] == tool_results(state)
}

pub fn the_agent_cannot_reach_outside_the_game_test() {
  let state = model_says(started(), "Fetching.", [#("a", "perform Fetch({})")])
  let assert [reason] = tool_results(state)
  assert string.contains(reason, "Fetch")
}

/// The whole point of one workspace: whatever built a bridge, there is only
/// one board and both sides see it.
pub fn the_shell_sees_what_the_agent_did_test() {
  let state =
    model_says(started(), "Joining those two.", [
      #("a", "connect({x: 0, y: 0}, {x: 2, y: 0})"),
    ])
  let state = shell_runs(state, "picture({})")
  assert shell.Returned("2-2\n...\n2.2\n") == last_outcome(state)
}

pub fn the_agent_sees_what_the_shell_did_test() {
  let state = shell_runs(started(), "connect({x: 0, y: 0}, {x: 0, y: 2})")
  let state = model_says(state, "What is there?", [#("a", "picture({})")])
  assert ["\"2.2\\n|..\\n2.2\\n\""] == tool_results(state)
}

// A WHOLE GAME ----------------------------------------------------------------

/// The model solves the board over four turns, the way it would: look, work
/// out a move, build it, check what is left.
pub fn the_agent_solves_a_whole_board_test() {
  let state = started()
  assert !state.is_complete(state)

  let state =
    model_says(state, "Let me see the board.", [#("1", "picture({})")])
  assert ["\"2.2\\n...\\n2.2\\n\""] == tool_results(state)

  // Every island wants two, and every island has exactly two neighbours, so
  // every pair in line has to be joined.
  let state =
    model_says(state, "Every island wants two and has two neighbours.", [
      #("2", "count(twos({}))"),
      #("3", "count(around({x: 0, y: 0}))"),
    ])
  assert ["4", "2"] == tool_results(state)

  let state =
    model_says(state, "Building the top and the left.", [
      #("4", "connect({x: 0, y: 0}, {x: 2, y: 0})"),
      #("5", "connect({x: 0, y: 0}, {x: 0, y: 2})"),
    ])
  assert ["Ok({})", "Ok({})"] == tool_results(state)
  assert !state.is_complete(state)

  let state =
    model_says(state, "And the right and the bottom.", [
      #("6", "connect({x: 2, y: 0}, {x: 2, y: 2})"),
      #("7", "connect({x: 0, y: 2}, {x: 2, y: 2})"),
      #("8", "is_empty(unfinished({}))"),
    ])
  assert ["Ok({})", "Ok({})", "True({})"] == tool_results(state)

  assert state.is_complete(state)
  let state = shell_runs(state, "picture({})")
  assert shell.Returned("2-2\n|.|\n2-2\n") == last_outcome(state)
}

/// A move taken back is taken back on the one board, whoever asks.
pub fn undo_reaches_across_both_sides_test() {
  let state = shell_runs(started(), "connect({x: 0, y: 0}, {x: 2, y: 0})")
  assert [harness.Bridge(start: #(0, 0), end: #(2, 0), count: 1)]
    == game.bridges(state.board(state))

  let state = model_says(state, "Taking that back.", [#("a", "undo({})")])
  assert ["True({})"] == tool_results(state)
  assert [] == game.bridges(state.board(state))

  let state = shell_runs(state, "redo({})")
  assert shell.Returned("True({})") == last_outcome(state)
  assert [harness.Bridge(start: #(0, 0), end: #(2, 0), count: 1)]
    == game.bridges(state.board(state))
}

// SHARING ---------------------------------------------------------------------

/// Sharing is the one effect that leaves the page, and it leaves it as work
/// for the platform rather than as anything the program chose.
pub fn sharing_hands_work_to_the_platform_test() {
  let state = shell_runs(started(), "share(\"solved it\")")
  assert shell.Working == last_outcome(state)
  let assert [#("shell", tools.Handling(..))] = state.running
}

pub fn a_value_is_written_out_for_reading_test() {
  let state = shell_runs(started(), "islands({})")
  let assert shell.Returned(text) = last_outcome(state)
  assert string.contains(text, "position")
  assert string.contains(text, "target")
}
