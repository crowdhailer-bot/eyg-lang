import eyg/hub/cache
import eyg/interpreter/break
import eyg/interpreter/expression
import eyg/interpreter/simple_debug
import eyg/interpreter/state
import eyg/ir/tree as ir
import eyg/parser
import eyg/parser/debug
import eyg/parser/parser.{type Reason} as _
import gleam/dynamic/decode
import gleam/list
import gleam/string
import oas/generator/utils
import overlay/llm/chat
import overlay/llm/tool
import overlay/web/environment.{type Environment, Environment}
import pal/system

pub type Context(host) {
  Context(
    environment: Environment(host),
    cache: cache.Cache(Meta),
    counter: Int,
    effects: List(system.Effect(#(Int, state.Value(Meta)))),
  )
}

pub type Meta =
  environment.Meta

pub type Call {
  UnknownTool(name: String)
  BadArguments(List(decode.DecodeError))
  InvalidCode(Reason)
  Successful(state.Value(Meta))
  Exception(state.Reason(Meta))
  Aborted(String)
  Handling(task_id: Int, env: state.Env(Meta), k: state.Stack(Meta))
  Pending(dep: cache.Dependency, env: state.Env(Meta), k: state.Stack(Meta))
}

pub type Calls =
  List(#(String, Call))

pub fn execute_all(
  context: Context(host),
  tool_calls: List(tool.Call),
) -> #(Context(host), Calls) {
  list.map_fold(tool_calls, context, execute_single)
}

fn execute_single(
  ctx: Context(host),
  call: tool.Call,
) -> #(Context(host), #(String, Call)) {
  let tool.Call(id:, function:) = call
  let tool.FunctionCall(name:, arguments:) = function
  case name {
    "run" ->
      case cast_run(arguments) {
        Ok(code) ->
          case parser.all_from_string(code) {
            Ok(source) -> {
              let #(ctx, call) =
                run(ctx, ir.map_annotation(source, fn(_) { [] }))
              #(ctx, #(id, call))
            }
            Error(reason) -> #(ctx, #(id, InvalidCode(reason)))
          }
        Error(reason) -> #(ctx, #(id, BadArguments(reason)))
      }
    _ -> #(ctx, #(id, UnknownTool(name)))
  }
}

/// Run a program in this environment, starting with its scope in hand.
///
/// This is what a tool call does once its code has been read. It is public
/// because a model is not the only thing that runs programs: a shell over the
/// same environment runs the tree a person has built, and wants the same
/// answer back.
pub fn run(
  ctx: Context(host),
  source: ir.Node(Meta),
) -> #(Context(host), Call) {
  let Environment(scope:, ..) = ctx.environment
  expression.execute(source, scope)
  |> loop(ctx)
}

fn cast_run(arguments) {
  let arguments = utils.fields_to_dynamic(arguments)
  let decoder = decode.field("code", decode.string, decode.success)
  decode.run(arguments, decoder)
}

// context can include tasks
// If we don't keep track of errors we'll keep calculating
fn loop(
  return: Result(state.Value(Meta), state.Debug(Meta)),
  ctx: Context(host),
) -> #(Context(host), Call) {
  case return {
    Error(#(break.UndefinedReference(ref) as break, _m, env, k)) -> {
      // TODO use the direct fetch status
      case cache.fetch_module(ctx.cache, ref) {
        cache.Ready(cache.Module(value:, type_: _)) ->
          loop(expression.resume(value, env, k), ctx)
        cache.Working(cache) -> {
          let ctx = Context(..ctx, cache:)
          #(ctx, Pending(cache.Content(ref), env, k))
        }
        cache.NotFound(at: _) -> #(ctx, Exception(break))
        cache.Unsound(reason:) -> #(ctx, Exception(reason))
      }
    }
    Error(#(break.UnhandledEffect(label, lift), _, env, k)) -> {
      let Environment(host:, handler:, ..) = ctx.environment
      let #(host, handling) = handler(host, label, lift)
      let environment = environment.set_host(ctx.environment, host)
      let ctx = Context(..ctx, environment:)
      case handling {
        environment.Stopped(reason) -> #(ctx, Aborted(reason))
        environment.Unknown(reason) -> #(ctx, Exception(reason))
        // Work that is already finished resumes the program in place, there is
        // nothing to wait for. Returning `Ok(value)` here would make the value
        // the answer of the whole program and throw the rest of it away.
        environment.Working(system.Done(value)) ->
          loop(expression.resume(value, env, k), ctx)
        environment.Working(effect) -> {
          let id = ctx.counter

          let effect = system.map(effect, fn(v) { #(id, v) })
          let effects = [effect, ..ctx.effects]
          let ctx = Context(..ctx, counter: id + 1, effects:)
          #(ctx, Handling(id, env, k))
        }
      }
    }
    Error(#(reason, _, _, _)) -> #(ctx, Exception(reason))
    Ok(value) -> #(ctx, Successful(value))
  }
}

fn is_running(call: Call) {
  case call {
    UnknownTool(..)
    | BadArguments(..)
    | InvalidCode(..)
    | Successful(..)
    | Exception(..)
    | Aborted(..) -> False
    Handling(..) | Pending(..) -> True
  }
}

pub fn any_running(tool_calls) {
  list.any(tool_calls, fn(tool_call) {
    let #(_, call) = tool_call
    is_running(call)
  })
}

pub fn all_returns(calls) {
  do_all_returns(calls, [])
}

fn do_all_returns(calls: Calls, acc) {
  case calls {
    [] -> Ok(list.reverse(acc))
    [#(id, call), ..calls] -> {
      let message = case call {
        UnknownTool(name:) -> Ok("unknown tool: " <> name)
        BadArguments(reasons) -> Ok(string.inspect(reasons))
        InvalidCode(reason) -> Ok(debug.describe(reason))
        Successful(value) -> Ok(simple_debug.inspect(value))
        Exception(reason) -> Ok(simple_debug.describe(reason))
        Aborted(reason) -> Ok(reason)
        Handling(..) -> Error(Nil)
        Pending(..) -> Error(Nil)
      }
      case message {
        Ok(text) -> {
          let message =
            chat.ToolResultMessage(tool_call_id: id, text:, images: [])
          let acc = [message, ..acc]
          do_all_returns(calls, acc)
        }
        Error(Nil) -> Error(Nil)
      }
    }
  }
}

pub fn restart(
  ctx: Context(host),
  call: #(String, Call),
) -> #(Context(host), #(String, Call)) {
  let #(call_id, call) = call
  case call {
    Pending(dep:, env:, k:) -> {
      let reason = cache.dep_to_reason(dep)
      let return = Error(#(reason, [], env, k))
      let #(ctx, call) = loop(return, ctx)
      #(ctx, #(call_id, call))
    }
    _ -> #(ctx, #(call_id, call))
  }
}

pub fn effect_handled(
  ctx: Context(host),
  calls: List(#(String, Call)),
  id: Int,
  value: state.Value(Meta),
) -> #(Context(host), List(#(String, Call))) {
  list.map_fold(calls, ctx, fn(ctx, call) { apply_effect(ctx, call, id, value) })
}

fn apply_effect(
  ctx: Context(host),
  call: #(String, Call),
  finished_id: Int,
  value: state.Value(Meta),
) {
  let #(call_id, call) = call
  case call {
    Handling(task_id:, env:, k:) if task_id == finished_id -> {
      let #(ctx, call) = loop(expression.resume(value, env, k), ctx)
      #(ctx, #(call_id, call))
    }
    _ -> #(ctx, #(call_id, call))
  }
}
