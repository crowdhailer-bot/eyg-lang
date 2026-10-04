//// This module is the effectful implementation of the tool calls available to overlay.
//// The state passed to each tool call is a cache of state that is reusable between tool calls.
//// Currently this state is only used for keeping access tokens for authenticated calls to API's
//// The state is currently a bun specific implementation however as it is scoped to tool calls it could be moved to overlay
//// Moving the full application state to overlay core is a bad idea, because we want to track different state when streaming
//// vs using The Elm Architecture in a Lustre web app.
//// 
//// The code execution tool is defined sans io using an effect type defined in this project.
//// The other tools could use the same effect logic, this is probably a good idea once we start applying policies for which files can be read.

import eyg/cli/internal/config
import eyg/hub/cache
import eyg/interpreter/block
import eyg/interpreter/break
import eyg/interpreter/cast
import eyg/interpreter/expression
import eyg/interpreter/simple_debug
import eyg/interpreter/state
import eyg/interpreter/value
import eyg/ir/tree as ir
import gleam/dict
import gleam/http/response
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import loam/execute
import loam/platform/computer
import loam/source
import loam/system
import midas/continuation.{type Continuation as K}
import ogre/origin
import overlay/agent
import overlay/config as overlay_config
import overlay/llm/provider
import overlay/policy
import overlay/tools/run

// I don't need to implement streaming but if so that goes at the loam level
// the tools module in overlay web should be reusable
// policy is read as part of config, which can read files and effects. policy is pure

// Env should be readable on startup
pub fn execute(input, config: config.Config) {
  use cwd <- system.then(system.cwd())
  use cwd <- system.try(cwd)
  use input <- system.try(source.normalize_input(cwd, input))
  use code <- system.then(source.read_input(input))
  use code <- system.try(code)
  use source <- system.try(source.parse_input(code, input))

  let state = execute.State(config.client.origin, cache.empty())
  use #(result, _state) <- system.then(execute.block(source, [], state))
  case result {
    Ok(#(Some(user_config), _)) ->
      case overlay_config.decode(user_config, labels()) {
        Ok(user_config) -> {
          // A context without a string readme is still usable by the agent.
          let readme =
            cast.field("readme", cast.as_string, user_config.context)
            |> result.unwrap("The context has no readme.")
          use Nil <- system.then(
            outer_loop(
              user_config.llm,
              provider_context(config.client.origin, readme),
              cwd,
              state,
              user_config.policy,
              user_config.context,
              [],
            ),
          )
          Ok(0) |> system.Done
        }
        Error(reason) ->
          Error("error: invalid overlay config: " <> reason) |> system.Done
      }
    Ok(#(None, _)) ->
      Error(execute.render_error(break.Vacant, source.1, state.Empty, cwd))
      |> system.Done
    Error(#(reason, location, _, k)) ->
      Error(execute.render_error(reason, location, k, cwd)) |> system.Done
  }
}

// I call this chat because we're in a chat agent
import overlay/llm/chat

fn outer_loop(
  llm,
  provider_context,
  cwd,
  eyg_state,
  policy,
  user_context,
  history,
) {
  use read <- system.then(input(">>>", "send a message"))
  case read {
    Ok("") -> system.Done(Nil)
    Ok(text) -> {
      use result <- system.then(
        inner_loop(llm, provider_context, cwd, eyg_state, policy, user_context, [
          chat.UserMessage(text, []),
          ..history
        ]),
      )
      // A failed completion is reported and the session continues from the
      // history before the failed message, so the user can try again.
      use history <- system.then(case result {
        Ok(history) -> system.Done(history)
        Error(reason) -> {
          use Nil <- system.then(system.stdout(ansi.red(reason) <> "\n"))
          system.Done(history)
        }
      })
      outer_loop(
        llm,
        provider_context,
        cwd,
        eyg_state,
        policy,
        user_context,
        history,
      )
    }
    Error(Nil) -> system.Done(Nil)
  }
}

import gleam/io
import gleam/string
import gleam_community/ansi

pub fn input(
  prompt: String,
  placeholder: String,
) -> system.Effect(Result(String, Nil)) {
  let prompt = ansi.bold(ansi.yellow(prompt))
  io.print(prompt)
  io.print(" ")
  io.print(ansi.dim(placeholder))
  io.print("\r")
  io.print(prompt)
  io.print(" ")
  use return <- system.map(system.prompt(""))
  case return {
    Ok(line) -> Ok(string.trim_end(line))
    Error(reason) -> Error(reason)
  }
}

fn provider_context(origin: origin.Origin, readme: String) -> provider.Context {
  provider.Context(
    system_prompt: agent.system_prompt(origin, computer.effects(), readme),
    tools: [
      run.spec(),
    ],
  )
}

pub fn inner_loop(
  llm,
  provider_context,
  cwd,
  eyg_state,
  policy,
  context,
  history,
) {
  use completion <- system.then(provider.completion(
    llm,
    provider_context,
    list.reverse(history),
    fetch,
  )(system.Done))
  case completion {
    Ok(completion) -> {
      io.println(completion.content)
      let history = [chat.from_completion(completion), ..history]
      case completion.tool_calls {
        [] -> system.Done(Ok(history))
        calls -> {
          use #(history, eyg_state) <- system.then(
            system.fold(calls, #(history, eyg_state), fn(acc, call) {
              let #(history, eyg_state) = acc
              let tool.Call(id:, function:) = call
              use #(result, _) <- system.then(execute_call(
                function,
                cwd,
                eyg_state,
                policy,
                context,
              ))
              // let result = result.map(result, pair.first)
              let result = result_to_message(id, result)
              let history = [result, ..history]
              system.Done(#(history, eyg_state))
            }),
          )
          inner_loop(
            llm,
            provider_context,
            cwd,
            eyg_state,
            policy,
            context,
            history,
          )
        }
      }
    }
    Error(reason) -> system.Done(Error(reason))
  }
}

pub fn result_to_message(
  call_id: String,
  result: Result(tool.Return, String),
) -> chat.Message(a) {
  case result {
    Ok(tool.Return(text, images)) -> {
      chat.ToolResultMessage(tool_call_id: call_id, text:, images:)
    }
    Error(reason) ->
      chat.ToolResultMessage(tool_call_id: call_id, text: reason, images: [])
  }
}

fn fetch(
  request,
) -> K(system.Effect(_), Result(response.Response(BitArray), _)) {
  system.Fetch(request, _)
}

// ---------------------------- toools

import overlay/llm/tool

pub fn execute_call(
  call: tool.FunctionCall,
  cwd: String,
  eyg_state: execute.State,
  policy: policy.Policy(execute.Value),
  context: execute.Value,
) -> system.Effect(#(Result(tool.Return, String), execute.State)) {
  let tool.FunctionCall(name, arguments) = call
  case agent.cast_tool_call(name, arguments) {
    Ok(call) -> {
      io.println(ansi.bg_bright_green(log_line(call)))
      case call {
        agent.Run(code) -> {
          use #(result, eyg_state, output) <- system.then(run_do(
            code,
            cwd,
            eyg_state,
            policy,
            context,
          ))
          let result = case result {
            // current state is not used by the CLI implementation, this will need to change.
            Ok(#(Some(value), _)) -> {
              Ok(tool.Return(report(output, simple_debug.inspect(value)), []))
            }
            Ok(#(None, _)) -> Ok(tool.Return(report(output, ""), []))
            Error(reason) -> {
              Error(report(output, reason))
            }
          }
          system.Done(#(result, eyg_state))
        }
      }
    }
    Error(reason) ->
      system.Done(#(
        Error(agent.describe_failure(reason, name, arguments)),
        eyg_state,
      ))
  }
}

pub fn log_line(call) {
  case call {
    agent.Run(_code) -> "Executing EYG code."
  }
}

/// Output is collected newest-first, scoped to a single tool call.
fn report(output: List(String), result: String) -> String {
  case list.reverse(output) {
    [] -> result
    printed -> "Output:\n" <> string.concat(printed) <> "\nResult:\n" <> result
  }
}

// There's a problem that the final execute is tied to runtime
// ---------------------- run

pub fn run_do(
  code,
  cwd,
  eyg_state,
  policy: policy.Policy(execute.Value),
  context: execute.Value,
) -> system.Effect(#(Result(_, String), execute.State, List(String))) {
  let input = source.Stdin

  case source.parse_input(code, input) {
    Ok(source) -> {
      let scope = [#("context", context)]
      use #(result, state, output) <- system.map(
        loop(block.execute(source, scope), eyg_state, policy, []),
      )
      let result = case result {
        Ok(value) -> Ok(value)
        Error(#(reason, location, _env, k)) ->
          Error(execute.render_error(reason, location, k, cwd))
      }
      #(result, state, output)
    }
    Error(reason) -> system.Done(#(Error(reason), eyg_state, []))
  }
}

/// Ask the policy what to do with an effect.
/// Policy functions are pure, a failure in the policy is reported as an abort.
fn apply_policy(
  label: String,
  lift: execute.Value,
  meta: source.Location,
  policy: policy.Policy(execute.Value),
  state: execute.State,
) -> system.Effect(
  #(Result(policy.Decision(execute.Value), execute.Reason), execute.State),
) {
  case policy.rule(policy, label) {
    policy.Apply(function) -> {
      use #(result, state) <- system.map(execute.pure_loop(
        expression.call(function, [#(lift, meta)]),
        state,
      ))
      let result = case result {
        Ok(returned) ->
          policy.decision(returned)
          |> result.map_error(fn(reason) {
            abort("policy for " <> label <> " failed: " <> reason)
          })
        Error(#(reason, _, _, _)) ->
          Error(abort(
            "policy for "
            <> label
            <> " failed: "
            <> simple_debug.describe(reason),
          ))
      }
      #(result, state)
    }
    policy.Unrestricted -> system.Done(#(Ok(policy.Pass(lift)), state))
    policy.Refused -> system.Done(#(Error(abort(policy.refused(label))), state))
  }
}

fn abort(reason: String) -> execute.Reason {
  break.UnhandledEffect("Abort", value.String(reason))
}

// This is a replacement for execute.loop because of the policy
pub fn loop(
  return: Result(_, execute.Debug),
  state: execute.State,
  policy: policy.Policy(execute.Value),
  output: List(String),
) -> system.Effect(#(Result(_, execute.Debug), execute.State, List(String))) {
  case return {
    Ok(return) -> system.Done(#(Ok(return), state, output))
    Error(#(reason, meta, env, k)) ->
      case reason {
        break.UnhandledEffect(label, lift) -> {
          use #(result, state) <- system.then(apply_policy(
            label,
            lift,
            meta,
            policy,
            state,
          ))
          case result {
            Ok(policy.Pass(modified)) ->
              case computer.cast(label, modified) {
                Ok(effect) -> {
                  let effect = computer.extrinsic(effect, meta.origin)
                  // Capture the actual write after policy transformation while
                  // still forwarding it to the terminal.
                  let output = case effect {
                    system.WriteStdout(text, _) -> [text, ..output]
                    system.WriteStderr(text, _) -> [text, ..output]
                    _ -> output
                  }
                  use value <- system.then(effect)
                  loop(block.resume(value, env, k), state, policy, output)
                }

                Error(reason) ->
                  system.Done(#(Error(#(reason, meta, env, k)), state, output))
              }
            Ok(policy.Mock(returned)) ->
              loop(block.resume(returned, env, k), state, policy, output)
            Error(reason) ->
              system.Done(#(Error(#(reason, meta, env, k)), state, output))
          }
        }
        // Relative imports read the file system so are checked by the read_file policy.
        break.UndefinedReference(ir.Relative(location:)) -> {
          let request =
            value.Record(
              dict.from_list([
                #("path", value.String(location)),
                #("offset", value.Integer(0)),
                #("limit", value.Integer(import_limit)),
              ]),
            )
          use #(decision, state) <- system.then(apply_policy(
            "ReadFile",
            request,
            meta,
            policy,
            state,
          ))
          let path = case decision {
            Ok(policy.Pass(modified)) ->
              cast.field("path", cast.as_string, modified)
            Ok(policy.Mock(value.Tagged("Error", reason))) ->
              Error(import_denied(location, simple_debug.inspect(reason)))
            Ok(policy.Mock(_)) ->
              Error(import_denied(
                location,
                "imports can only be passed or mocked with an error",
              ))
            Error(reason) -> Error(reason)
          }
          case path {
            Ok(path) -> {
              use #(result, state) <- system.then(execute.lookup(
                ir.Relative(path),
                meta.origin,
                state,
              ))
              case result {
                Ok(value) ->
                  loop(block.resume(value, env, k), state, policy, output)
                Error(reason) ->
                  system.Done(#(Error(#(reason, meta, env, k)), state, output))
              }
            }
            Error(reason) ->
              system.Done(#(Error(#(reason, meta, env, k)), state, output))
          }
        }
        break.UndefinedReference(reference) -> {
          use #(result, state) <- system.then(execute.lookup(
            reference,
            meta.origin,
            state,
          ))
          case result {
            Ok(value) ->
              loop(block.resume(value, env, k), state, policy, output)
            Error(reason) ->
              system.Done(#(Error(#(reason, meta, env, k)), state, output))
          }
        }

        _ -> system.Done(#(Error(#(reason, meta, env, k)), state, output))
      }
  }
}

const import_limit = 100_000_000

fn import_denied(location, reason) {
  abort("import of " <> location <> " denied by policy: " <> reason)
}

/// The effects available to agent code.
fn labels() {
  list.map(computer.effects(), fn(effect) { effect.name })
}
