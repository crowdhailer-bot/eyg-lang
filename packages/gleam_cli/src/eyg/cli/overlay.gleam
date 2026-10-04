//// Run an overlay agent in the terminal.
////
//// The config is type checked and evaluated once, then the session reads prompts a line at a time.
//// Every effect performed by the agent's code is checked by the policy from the config.

import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/binding
import eyg/cli/check
import eyg/cli/internal/config
import eyg/cli/internal/terminal
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
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import gleam_community/ansi
import loam/execute
import loam/platform/computer
import loam/source
import loam/system
import midas/continuation.{type Continuation as K}
import midas/effect
import overlay/agent
import overlay/check as overlay_check
import overlay/config as overlay_config
import overlay/context
import overlay/llm/chat
import overlay/llm/provider
import overlay/llm/tool
import overlay/policy
import overlay/tools/guide
import overlay/tools/run

/// Everything about a session that is fixed when it starts.
pub type Session {
  Session(
    llm: provider.Llm,
    provider_context: provider.Context,
    cwd: String,
    policy: policy.Policy(execute.Value),
    context: execute.Value,
    context_type: binding.Poly,
  )
}

pub fn execute(input, config: config.Config) {
  use cwd <- system.then(system.cwd())
  use cwd <- system.try(cwd)
  use input <- system.try(source.normalize_input(cwd, input))
  use code <- system.then(source.read_input(input))
  use code <- system.try(code)
  use source <- system.try(source.parse_input(code, input))

  let state = execute.State(config.client.origin, cache.empty())
  use #(type_, errors, state) <- system.then(check.check_from(
    source,
    cwd,
    infer.unpure(),
    state,
    check.Follow,
  ))
  use Nil <- system.then(
    system.each(list.map(check.render_errors(errors), system.stdout)),
  )
  use <- bool_guard(errors != [], "error: the overlay config has type errors")
  use context_type <- system.try(
    overlay_check.config(type_, computer.effects())
    |> result.map_error(fn(reasons) {
      "error: invalid overlay config: " <> string.join(reasons, "\n")
    }),
  )

  use #(result, state) <- system.then(execute.block(source, [], state))
  case result {
    Ok(#(Some(user_config), _)) ->
      case overlay_config.decode(user_config, labels()) {
        Ok(user_config) -> {
          let readme = context.readme(user_config.context, Some(context_type))
          let session =
            Session(
              llm: user_config.llm,
              provider_context: agent.provider_context(
                computer.effects(),
                readme,
              ),
              cwd:,
              policy: user_config.policy,
              context: user_config.context,
              context_type:,
            )
          use Nil <- system.then(outer_loop(session, state, []))
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

fn bool_guard(
  condition: Bool,
  reason: String,
  then: fn() -> system.Effect(Result(a, String)),
) -> system.Effect(Result(a, String)) {
  case condition {
    True -> system.Done(Error(reason))
    False -> then()
  }
}

fn outer_loop(session: Session, eyg_state, history) {
  use read <- system.then(input(">>>", "send a message"))
  case read {
    Ok("") -> system.Done(Nil)
    Ok(text) -> {
      let message = chat.UserMessage(text, [])
      use #(result, eyg_state) <- system.then(
        inner_loop(session, eyg_state, [message, ..history]),
      )
      // A failed completion is reported and the session continues from the
      // history before the failed message, so the user can try again.
      use history <- system.then(case result {
        Ok(history) -> system.Done(history)
        Error(reason) -> {
          use Nil <- system.then(system.stdout(
            terminal.style(ansi.red, reason) <> "\n",
          ))
          system.Done(history)
        }
      })
      outer_loop(session, eyg_state, history)
    }
    Error(Nil) -> system.Done(Nil)
  }
}

pub fn input(
  prompt: String,
  placeholder: String,
) -> system.Effect(Result(String, Nil)) {
  case terminal.is_tty() {
    // The placeholder is overwritten as the user types.
    True -> {
      let prompt = ansi.bold(ansi.yellow(prompt))
      io.print(prompt <> " " <> ansi.dim(placeholder) <> "\r" <> prompt <> " ")
    }
    False -> io.print(prompt <> " ")
  }
  use return <- system.map(system.prompt(""))
  case return {
    Ok(line) -> Ok(string.trim_end(line))
    Error(reason) -> Error(reason)
  }
}

pub fn inner_loop(
  session: Session,
  eyg_state: execute.State,
  history: List(chat.Message(tool.Call)),
) -> system.Effect(
  #(Result(List(chat.Message(tool.Call)), String), execute.State),
) {
  use completion <- system.then(provider.completion(
    session.llm,
    session.provider_context,
    list.reverse(history),
    fetch,
  )(system.Done))
  case completion {
    Ok(completion) -> {
      io.println(completion.content)
      let history = [chat.from_completion(completion), ..history]
      case completion.tool_calls {
        [] -> system.Done(#(Ok(history), eyg_state))
        calls -> {
          use #(history, eyg_state) <- system.then(
            system.fold(calls, #(history, eyg_state), fn(acc, call) {
              let #(history, eyg_state) = acc
              let tool.Call(id:, function:) = call
              io.print(terminal.style(
                ansi.dim,
                "[step " <> int.to_string(step(history)) <> "] ",
              ))
              use #(result, eyg_state) <- system.then(execute_call(
                session,
                function,
                eyg_state,
              ))
              let history = [result_to_message(id, result), ..history]
              system.Done(#(history, eyg_state))
            }),
          )
          inner_loop(session, eyg_state, history)
        }
      }
    }
    Error(reason) -> system.Done(#(Error(reason), eyg_state))
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

pub fn execute_call(
  session: Session,
  call: tool.FunctionCall,
  eyg_state: execute.State,
) -> system.Effect(#(Result(tool.Return, String), execute.State)) {
  let tool.FunctionCall(name, arguments) = call
  case agent.cast_tool_call(name, arguments) {
    Ok(call) -> {
      io.println(log_line(call))
      case call {
        agent.Run(code) -> {
          use #(result, eyg_state, output) <- system.then(run_do(
            session,
            code,
            eyg_state,
          ))
          let result = case result {
            Ok(#(Some(value), _)) ->
              Ok(
                tool.Return(run.report(output, simple_debug.inspect(value)), []),
              )
            Ok(#(None, _)) -> Ok(tool.Return(run.report(output, ""), []))
            Error(reason) -> Error(run.report(output, reason))
          }
          io.println(log_result(result))
          system.Done(#(result, eyg_state))
        }
        agent.Guide(name) -> {
          use result <- system.map(read_guide(eyg_state.origin, name))
          let result = result.map(result, tool.Return(_, []))
          io.println(log_result(result))
          #(result, eyg_state)
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
    agent.Run(code) ->
      terminal.style(ansi.bg_bright_green, "Executing EYG code.")
      <> "\n"
      <> terminal.style(ansi.dim, code)
    agent.Guide(name) ->
      terminal.style(ansi.bg_bright_green, "Reading guide " <> name <> ".")
  }
}

/// Summarise a tool call result so the user can see what the agent saw.
fn log_result(result: Result(tool.Return, String)) -> String {
  case result {
    Ok(tool.Return(text:, ..)) ->
      terminal.style(ansi.green, "ok ")
      <> terminal.style(ansi.dim, truncate(text))
    Error(reason) ->
      terminal.style(ansi.red, "error ")
      <> terminal.style(ansi.dim, truncate(reason))
  }
}

fn truncate(text) {
  case string.length(text) > 500 {
    True -> string.slice(text, 0, 500) <> "..."
    False -> text
  }
}

/// Type check then run the agent's code.
/// Type errors are returned to the agent without running anything.
pub fn run_do(
  session: Session,
  code: String,
  eyg_state: execute.State,
) -> system.Effect(#(Result(_, String), execute.State, List(String))) {
  case source.parse_input(code, source.Stdin) {
    Ok(source) -> {
      let inference =
        overlay_check.agent(computer.effects(), session.context_type)
      use #(_type, errors, eyg_state) <- system.then(check.check_from(
        source,
        session.cwd,
        inference,
        eyg_state,
        check.AnyType,
      ))
      case errors {
        [] -> {
          let scope = [#("context", session.context)]
          use #(result, state, output) <- system.map(
            loop(block.execute(source, scope), eyg_state, session.policy, []),
          )
          let result = case result {
            Ok(value) -> Ok(value)
            Error(#(reason, location, _env, k)) ->
              Error(execute.render_error(reason, location, k, session.cwd))
          }
          #(result, state, output)
        }
        _ ->
          system.Done(
            #(
              Error(string.join(check.render_errors(errors), "\n")),
              eyg_state,
              [],
            ),
          )
      }
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
        // Aborting ends the program, it does no IO so needs no policy.
        break.UnhandledEffect("Abort", _) ->
          system.Done(#(Error(#(reason, meta, env, k)), state, output))
        break.UnhandledEffect(label, lift) -> {
          use lift <- system.then(resolve_paths(label, lift, meta.origin))
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
          use location <- system.then(resolve_path(location, meta.origin))
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

/// Guides are fetched by the harness so are not subject to the policy.
fn read_guide(origin, name) -> system.Effect(Result(String, String)) {
  case guide.request(origin, name) {
    Ok(request) -> {
      use response <- system.map(system.fetch(request))
      case response {
        Ok(response) -> guide.response(response)
        Error(reason) -> Error(effect.describe_fetch_error(reason))
      }
    }
    Error(reason) -> system.Done(Error(reason))
  }
}

/// Policies see file paths resolved to absolute paths, as the effect will use them.
fn resolve_paths(
  label: String,
  lift: execute.Value,
  origin: source.Origin,
) -> system.Effect(execute.Value) {
  case label, lift {
    "ReadFile", value.Record(fields)
    | "WriteFile", value.Record(fields)
    | "AppendFile", value.Record(fields)
    ->
      case dict.get(fields, "path") {
        Ok(value.String(path)) -> {
          use path <- system.map(resolve_path(path, origin))
          value.Record(dict.insert(fields, "path", value.String(path)))
        }
        _ -> system.Done(lift)
      }
    "DeleteFile", value.String(path)
    | "MakeDirectory", value.String(path)
    | "ReadDirectory", value.String(path)
    -> system.map(resolve_path(path, origin), value.String)
    _, _ -> system.Done(lift)
  }
}

/// A path that can't be resolved is left for the effect to report.
fn resolve_path(path, origin) {
  use resolved <- system.map(source.resolve_filepath(origin, path))
  result.unwrap(resolved, path)
}

/// The number of the next tool call since the user's last message.
fn step(history: List(chat.Message(_))) -> Int {
  list.take_while(history, fn(message) {
    case message {
      chat.UserMessage(..) -> False
      _ -> True
    }
  })
  |> list.count(fn(message) {
    case message {
      chat.ToolResultMessage(..) -> True
      _ -> False
    }
  })
  |> int.add(1)
}
