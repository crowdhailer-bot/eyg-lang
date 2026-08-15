//// The whole application.
////
//// One puzzle, and two ways to write programs against it. The shell is a
//// structural editor; the agent is a model writing the same programs from
//// English. They are not two runtimes: there is one environment, one board,
//// one cache and one run of task numbers, and both of them take it, run in it,
//// and put back what it became. A bridge built by the agent is there when the
//// shell next looks, because there is only ever one board.

import eyg/analysis/inference/levels_j/contextual as infer
import eyg/interpreter/simple_debug
import eyg/interpreter/state as istate
import eyg/interpreter/value as v
import eyg/parser/debug as parser_debug
import gleam/dict
import gleam/list
import gleam/option.{type Option, None, Some}
import hashi/context
import hashi/game
import hashi/harness
import hashi/platform
import hashi/shell
import morph/buffer
import ogre/origin
import overlay/web/environment
import overlay/web/state as agent
import overlay/web/tools
import pal/system
import shared/hashi

pub type Config {
  Config(
    origin: origin.Origin,
    /// The source of `eyg/context.eyg`, handed in by the page.
    context: String,
    /// The board to play. Which board that is belongs to whoever starts the
    /// application, not to the application.
    puzzle: hashi.Puzzle,
  )
}

/// One puzzle a day, the same one for everybody, which is what the original
/// project plays. Nine islands on an eight by eight board is the size it uses
/// for a comfortable game.
pub fn daily(day: Int) -> hashi.Puzzle {
  hashi.new(width: 8, height: 8, islands: 9)
  |> hashi.with_seed(day)
  |> hashi.generate
}

/// Which side of the panel is showing.
pub type Panel {
  Shell
  Agent
}

pub type State {
  State(
    panel: Panel,
    /// Owns the environment, and with it the board.
    agent: agent.State(platform.Host),
    shell: shell.Shell,
    /// Shell programs waiting on the platform, by the id the shell knows them
    /// by. The agent's own waiting programs are the agent's business.
    running: List(#(String, tools.Call)),
    /// What the shell type checks a program against.
    infer: infer.Context,
    /// Something wrong with the page itself rather than with a program.
    failure: Option(String),
  )
}

pub fn init(config: Config) -> #(State, List(system.Effect(Message))) {
  let Config(origin:, context: source, puzzle:) = config

  let #(readme, scope, types, failure) = case context.load(source) {
    Ok(context.Context(readme:, scope:, types:)) -> #(
      readme,
      scope,
      types,
      None,
    )
    Error(reason) -> #("", [], [], Some("the workspace is broken: " <> reason))
  }

  let host = platform.Host(game: game.new(puzzle), origin:)
  let environment = platform.environment(host, readme, scope)
  let #(agent, actions) = agent.init(agent.Config(origin:, environment:))

  let infer = infer.Context(..harness.infer_context(dict.new()), env: types)

  let state =
    State(
      panel: Shell,
      agent:,
      shell: shell.new(infer),
      running: [],
      infer:,
      failure:,
    )
  #(state, list.map(actions, system.map(_, AgentMessage)))
}

pub type Message {
  UserSelectedPanel(Panel)
  ShellMessage(shell.Message)
  AgentMessage(agent.Message)
  /// A program the shell ran was waiting on the platform, and the platform is
  /// done.
  ShellEffectHandled(task_id: Int, value: istate.Value(tools.Meta))
  /// A key pressed anywhere on the page.
  ///
  /// The shell is driven by keys and has no text box to type them into, so
  /// there is nothing to keep focused; a name typed into a prompt would
  /// otherwise leave the keys stranded once the prompt closed.
  UserPressedKey(String)
  /// The board is drawn but not played with. Every pointer event it produces
  /// arrives here and is dropped.
  Ignore
}

pub fn update(
  state: State,
  message: Message,
) -> #(State, List(system.Effect(Message))) {
  case message {
    UserSelectedPanel(panel) -> #(State(..state, panel:), [])

    ShellMessage(message) -> {
      let #(shell, action) = shell.update(state.shell, message, state.infer)
      let state = State(..state, shell:)
      case action {
        shell.Nothing -> #(state, [])
        shell.Run -> run(state)
      }
    }

    AgentMessage(message) -> {
      let #(agent, actions) = agent.update(state.agent, message)
      #(State(..state, agent:), list.map(actions, system.map(_, AgentMessage)))
    }

    ShellEffectHandled(task_id:, value:) -> {
      let ctx = agent.workspace(state.agent)
      let #(ctx, running) =
        tools.effect_handled(ctx, state.running, task_id, value)
      settle(state, ctx, running)
    }

    // Only the shell is written with keys. While the agent is showing they
    // belong to whatever the person is typing to it.
    UserPressedKey(key) ->
      case state.panel {
        Shell -> update(state, ShellMessage(shell.UserPressedKey(key)))
        Agent -> #(state, [])
      }

    Ignore -> #(state, [])
  }
}

/// Run whatever is in the shell's buffer.
fn run(state: State) -> #(State, List(system.Effect(Message))) {
  let source = buffer.source(state.shell.buffer)
  let ctx = agent.workspace(state.agent)
  let #(ctx, call) = tools.run(ctx, source)

  // The shell only ever has one program in flight, so one name is enough.
  let running = [#(shell_task, call)]
  let state =
    State(..state, shell: shell.ran(state.shell, shell.Working, state.infer))
  settle(state, ctx, running)
}

const shell_task = "shell"

/// Take what a run left behind: put the workspace back, tell the shell how its
/// program ended, and hand on any work the platform has to do.
fn settle(
  state: State,
  ctx: tools.Context(platform.Host),
  running: List(#(String, tools.Call)),
) -> #(State, List(system.Effect(Message))) {
  let agent = agent.restore(state.agent, ctx)
  let actions =
    list.map(ctx.effects, fn(effect) {
      system.map(effect, fn(returned) {
        let #(task_id, value) = returned
        ShellEffectHandled(task_id:, value:)
      })
    })

  let #(shell, running) = case running {
    [#(_, call)] ->
      case outcome(call) {
        Some(outcome) -> #(shell.settled(state.shell, outcome), [])
        None -> #(state.shell, running)
      }
    _ -> #(state.shell, running)
  }

  #(State(..state, agent:, shell:, running:), actions)
}

/// How a program ended, or nothing if it has not ended.
fn outcome(call: tools.Call) -> Option(shell.Outcome) {
  case call {
    // A string is shown as it reads. `picture({})` draws the board, and a
    // board written out with the newlines escaped is no use to anybody.
    tools.Successful(v.String(text)) -> Some(shell.Returned(text))
    tools.Successful(value) -> Some(shell.Returned(simple_debug.inspect(value)))
    tools.Exception(reason) -> Some(shell.Failed(simple_debug.describe(reason)))
    tools.Aborted(reason) -> Some(shell.Failed(reason))
    tools.InvalidCode(reason) ->
      Some(shell.Failed(parser_debug.describe(reason)))
    tools.UnknownTool(name) -> Some(shell.Failed("unknown tool: " <> name))
    tools.BadArguments(_) -> Some(shell.Failed("the tool call made no sense"))
    tools.Handling(..) | tools.Pending(..) -> None
  }
}

// READING THE STATE -----------------------------------------------------------

/// The board, which lives in the environment because that is what the effects
/// act on.
pub fn board(state: State) -> game.Game {
  let environment.Environment(host:, ..) = state.agent.environment
  host.game
}

pub fn is_complete(state: State) -> Bool {
  game.is_complete(board(state))
}
