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
import gleam/bit_array
import gleam/dict
import gleam/http/request
import gleam/http/response
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleam/uri
import gleam_community/ansi
import loam/execute
import loam/platform/computer
import loam/source
import loam/system
import midas/effect
import overlay/agent
import overlay/check as overlay_check
import overlay/config as overlay_config
import overlay/context
import overlay/export
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
    audit: Option(execute.Value),
    context_policy: Option(policy.Policy(execute.Value)),
  )
}

pub fn execute(input, config: config.Config) {
  use initial <- system.then(initialize(input, config))
  use #(session, runtime) <- system.try(initial)
  use Nil <- system.then(outer_loop(session, runtime, []))
  system.Done(Ok(0))
}

/// Load and validate a session without owning its terminal or conversation loop.
pub fn initialize(input, config: config.Config) {
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
      system.Done(prepare(user_config, context_type, cwd, state))
    Ok(#(None, _)) ->
      Error(execute.render_error(break.Vacant, source.1, state.Empty, cwd))
      |> system.Done
    Error(#(reason, location, _, k)) ->
      Error(execute.render_error(reason, location, k, cwd)) |> system.Done
  }
}

/// Run a session from an evaluated config until the user ends it.
pub fn start(
  user_config: execute.Value,
  context_type: binding.Poly,
  cwd: String,
  state: execute.State,
) -> system.Effect(Result(Nil, String)) {
  use #(session, runtime) <- system.try(prepare(
    user_config,
    context_type,
    cwd,
    state,
  ))
  use Nil <- system.map(outer_loop(session, runtime, []))
  Ok(Nil)
}

fn prepare(user_config, context_type, cwd, state) {
  case overlay_config.decode(user_config, labels()) {
    Ok(user_config) -> {
      let readme = context.readme(user_config.context, Some(context_type))
      let session =
        Session(
          llm: user_config.llm,
          provider_context: agent.provider_context(
            computer.effects(),
            readme,
            True,
          ),
          cwd:,
          policy: user_config.policy,
          context: user_config.context,
          context_type:,
          audit: user_config.audit,
          context_policy: user_config.context_policy,
        )
      let runtime = Runtime(state:, policy_state: user_config.state)
      Ok(#(session, runtime))
    }
    Error(reason) -> Error("error: invalid overlay config: " <> reason)
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
    Ok("/export" <> path) -> {
      use Nil <- system.then(export(session, history, string.trim(path)))
      outer_loop(session, eyg_state, history)
    }
    Ok(text) -> {
      let message = chat.UserMessage(text, [])
      terminal.start_turn()
      use #(result, eyg_state) <- system.then(
        inner_loop(session, eyg_state, [message, ..history]),
      )
      terminal.end_turn()
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
  let text = case terminal.is_tty() {
    // The placeholder is overwritten as the user types.
    True -> {
      let prompt = ansi.bold(ansi.yellow(prompt))
      prompt <> " " <> ansi.dim(placeholder) <> "\r" <> prompt <> " "
    }
    False -> prompt <> " "
  }
  use return <- system.map(system.prompt(text))
  case return {
    Ok(line) -> Ok(string.trim_end(line))
    Error(reason) -> Error(reason)
  }
}

pub fn inner_loop(
  session: Session,
  eyg_state: Runtime,
  history: List(chat.Message(tool.Call)),
) -> system.Effect(#(Result(List(chat.Message(tool.Call)), String), Runtime)) {
  use <- stopped(eyg_state)
  use completion <- system.then(stream_completion(
    session,
    list.reverse(history),
  ))
  case completion {
    Ok(completion) -> {
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

pub fn execute_call(
  session: Session,
  call: tool.FunctionCall,
  eyg_state: Runtime,
) -> system.Effect(#(Result(tool.Return, String), Runtime)) {
  case agent.cast_tool_call(call.name, call.arguments) {
    Ok(decoded) -> io.println(log_line(decoded))
    Error(_) -> Nil
  }
  use #(result, runtime) <- system.map(
    call_observed(session, call, eyg_state, fn(_, _, _, _) { Nil }),
  )
  io.println(log_result(result))
  #(result, runtime)
}

/// Execute a tool using the same policy and type checks as the line CLI.
/// An observation records the label, input, policy outcome and returned value.
pub fn call_observed(session, call, eyg_state, observe) {
  let tool.FunctionCall(name, arguments) = call
  case agent.cast_tool_call(name, arguments) {
    Ok(call) -> {
      case call {
        agent.Run(code) -> {
          use #(result, eyg_state, output) <- system.then(run_do_observed(
            session,
            code,
            eyg_state,
            observe,
          ))
          let result = case result {
            Ok(#(Some(value), _)) ->
              Ok(
                tool.Return(run.report(output, simple_debug.inspect(value)), []),
              )
            Ok(#(None, _)) -> Ok(tool.Return(run.report(output, ""), []))
            Error(reason) -> Error(run.report(output, reason))
          }
          system.Done(#(result, eyg_state))
        }
        agent.Guide(name) -> {
          use result <- system.map(read_guide(eyg_state.state.origin, name))
          let result = result.map(result, tool.Return(_, []))
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
  eyg_state: Runtime,
) -> system.Effect(#(Result(_, String), Runtime, List(String))) {
  run_do_observed(session, code, eyg_state, fn(_, _, _, _) { Nil })
}

pub fn run_do_observed(session, code, eyg_state, observe) {
  case source.parse_input(code, source.Stdin) {
    Ok(source) -> {
      use #(trusted, eyg_state) <- system.then(check_references(
        session,
        source,
        eyg_state,
      ))
      use <- untrusted(trusted, eyg_state)
      let inference =
        overlay_check.agent(computer.effects(), session.context_type)
      use #(_type, errors, state) <- system.then(check.check_from(
        source,
        session.cwd,
        inference,
        eyg_state.state,
        check.AnyType,
      ))
      let eyg_state = Runtime(..eyg_state, state:)
      case errors {
        [] -> {
          let scope = [#("context", session.context)]
          use #(result, state, output) <- system.map(loop_observed(
            block.execute(source, scope),
            eyg_state,
            session,
            [],
            observe,
          ))
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
  runtime: Runtime,
) -> system.Effect(
  #(Result(policy.Decision(execute.Value), execute.Reason), Runtime),
) {
  case policy.rule(policy, label) {
    policy.Apply(function) -> {
      // A policy with state is also given the state and returns the next state.
      let arguments = case runtime.policy_state {
        Some(policy_state) -> [#(lift, meta), #(policy_state, meta)]
        None -> [#(lift, meta)]
      }
      use #(result, state) <- system.map(execute.pure_loop(
        expression.call(function, arguments),
        runtime.state,
      ))
      let runtime = Runtime(..runtime, state:)
      let failed = fn(reason) {
        abort("policy for " <> label <> " failed: " <> reason)
      }
      case result, runtime.policy_state {
        Ok(returned), None -> #(
          policy.decision(returned) |> result.map_error(failed),
          runtime,
        )
        Ok(returned), Some(_) ->
          case policy.stateful_decision(returned) {
            Ok(#(decision, policy_state)) -> #(
              Ok(decision),
              Runtime(..runtime, policy_state: Some(policy_state)),
            )
            Error(reason) -> #(Error(failed(reason)), runtime)
          }
        Error(#(reason, _, _, _)), _ -> #(
          Error(failed(simple_debug.describe(reason))),
          runtime,
        )
      }
    }
    policy.Unrestricted -> system.Done(#(Ok(policy.Pass(lift)), runtime))
    policy.Refused ->
      system.Done(#(Error(abort(policy.refused(label))), runtime))
  }
}

/// State that changes as the session runs.
/// The policy state is only used when the config has a `state` field.
pub type Runtime {
  Runtime(state: execute.State, policy_state: Option(execute.Value))
}

fn abort(reason: String) -> execute.Reason {
  break.UnhandledEffect("Abort", value.String(reason))
}

// This is a replacement for execute.loop because of the policy
pub fn loop(
  return: Result(_, execute.Debug),
  state: Runtime,
  session: Session,
  output: List(String),
) -> system.Effect(#(Result(_, execute.Debug), Runtime, List(String))) {
  loop_observed(return, state, session, output, fn(_, _, _, _) { Nil })
}

fn loop_observed(
  return: Result(#(Option(execute.Value), execute.Scope), execute.Debug),
  state: Runtime,
  session: Session,
  output: List(String),
  observe: fn(String, String, String, String) -> Nil,
) -> system.Effect(#(Result(_, execute.Debug), Runtime, List(String))) {
  case return {
    Ok(return) -> system.Done(#(Ok(return), state, output))
    Error(#(reason, meta, env, k)) ->
      case reason {
        // Aborting ends the program, it does no IO so needs no policy.
        break.UnhandledEffect("Abort", lift) -> {
          observe("Abort", simple_debug.inspect(lift), "abort", "")
          system.Done(#(Error(#(reason, meta, env, k)), state, output))
        }
        break.UnhandledEffect(label, lift) -> {
          use lift <- system.then(resolve_paths(label, lift, meta.origin))
          use #(result, state) <- system.then(decide(
            session,
            label,
            lift,
            meta,
            state,
          ))
          case result {
            Ok(Perform(modified)) ->
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
                  observe(
                    label,
                    simple_debug.inspect(modified),
                    "pass",
                    simple_debug.inspect(value),
                  )
                  loop_observed(
                    block.resume(value, env, k),
                    state,
                    session,
                    output,
                    observe,
                  )
                }

                Error(reason) -> {
                  observe(
                    label,
                    simple_debug.inspect(lift),
                    "error",
                    simple_debug.describe(reason),
                  )
                  system.Done(#(Error(#(reason, meta, env, k)), state, output))
                }
              }
            Ok(Resume(returned)) -> {
              observe(
                label,
                simple_debug.inspect(lift),
                "mock",
                simple_debug.inspect(returned),
              )
              loop_observed(
                block.resume(returned, env, k),
                state,
                session,
                output,
                observe,
              )
            }
            Error(reason) -> {
              observe(
                label,
                simple_debug.inspect(lift),
                "refused",
                simple_debug.describe(reason),
              )
              system.Done(#(Error(#(reason, meta, env, k)), state, output))
            }
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
          use #(decision, state) <- system.then(decide(
            session,
            "ReadFile",
            request,
            meta,
            state,
          ))
          let path = case decision {
            Ok(Perform(modified)) ->
              cast.field("path", cast.as_string, modified)
            Ok(Resume(value.Tagged("Error", reason))) ->
              Error(import_denied(location, simple_debug.inspect(reason)))
            Ok(Resume(_)) ->
              Error(import_denied(
                location,
                "imports can only be passed or mocked with an error",
              ))
            Error(reason) -> Error(reason)
          }
          case path {
            Ok(path) -> {
              use #(result, looked_up) <- system.then(execute.lookup(
                ir.Relative(path),
                meta.origin,
                state.state,
              ))
              let state = Runtime(..state, state: looked_up)
              case result {
                Ok(value) -> {
                  observe(
                    "ReadFile",
                    simple_debug.inspect(request),
                    "import",
                    path,
                  )
                  loop_observed(
                    block.resume(value, env, k),
                    state,
                    session,
                    output,
                    observe,
                  )
                }
                Error(reason) ->
                  system.Done(#(Error(#(reason, meta, env, k)), state, output))
              }
            }
            Error(reason) -> {
              observe(
                "ReadFile",
                simple_debug.inspect(request),
                "refused",
                simple_debug.describe(reason),
              )
              system.Done(#(Error(#(reason, meta, env, k)), state, output))
            }
          }
        }
        break.UndefinedReference(reference) -> {
          use #(result, looked_up) <- system.then(execute.lookup(
            reference,
            meta.origin,
            state.state,
          ))
          let state = Runtime(..state, state: looked_up)
          case result {
            Ok(value) ->
              loop_observed(
                block.resume(value, env, k),
                state,
                session,
                output,
                observe,
              )
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

/// What to do with an effect once the policy and user have decided.
type Outcome {
  Perform(execute.Value)
  Resume(execute.Value)
}

/// Apply the policy, ask the user if the policy asks, then audit the decision.
fn decide(
  session: Session,
  label: String,
  lift: execute.Value,
  meta: source.Location,
  state: Runtime,
) -> system.Effect(#(Result(Outcome, execute.Reason), Runtime)) {
  use #(decision, state) <- system.then(apply_policy(
    label,
    lift,
    meta,
    policy_for(session, meta.origin),
    state,
  ))
  use outcome <- system.then(case decision {
    Ok(policy.Pass(value)) -> system.Done(Ok(Perform(value)))
    Ok(policy.Mock(value)) -> system.Done(Ok(Resume(value)))
    Ok(policy.Ask(question:, denied:)) -> {
      use answer <- system.map(input(
        terminal.style(ansi.yellow, question) <> " allow?",
        "y/N",
      ))
      case answer {
        Ok("y") | Ok("Y") | Ok("yes") -> Ok(Perform(lift))
        _ -> Ok(Resume(denied))
      }
    }
    Error(reason) -> system.Done(Error(reason))
  })
  use audited <- system.map(audit(session, label, lift, outcome, state.state))
  #(outcome, Runtime(..state, state: audited))
}

/// Call the config's audit function, which may perform effects, with the effect and outcome.
/// A failing audit is reported to the user but does not stop the agent.
fn audit(session: Session, label, lift, outcome, state) {
  case session.audit {
    None -> system.Done(state)
    Some(function) -> {
      let decision = case outcome {
        Ok(Perform(_)) -> "pass"
        Ok(Resume(_)) -> "mock"
        Error(_) -> "refused"
      }
      let entry =
        value.Record(
          dict.from_list([
            #("effect", value.String(label)),
            #("input", value.String(simple_debug.inspect(lift))),
            #("decision", value.String(decision)),
          ]),
        )
      let meta = source.Location(source.Inline, source.Json)
      use #(result, state) <- system.then(execute.expression_loop(
        expression.call(function, [#(entry, meta)]),
        state,
      ))
      case result {
        Ok(_) -> system.Done(state)
        Error(#(reason, _, _, _)) -> {
          use Nil <- system.then(
            system.stdout(terminal.style(
              ansi.red,
              "audit failed: " <> simple_debug.describe(reason),
            )),
          )
          system.Done(state)
        }
      }
    }
  }
}

/// Write the chat in the opencode session export format.
pub fn export(
  session: Session,
  history: List(chat.Message(tool.Call)),
  path: String,
) -> system.Effect(Nil) {
  use time <- system.then(system.now())
  let path = case path {
    "" -> "overlay-session-" <> int.to_string(time) <> ".json"
    path -> path
  }
  let exported =
    export.encode(
      export.Session(
        id: "ses_" <> int.to_string(time),
        directory: session.cwd,
        provider_id: provider.id(session.llm.provider),
        model_id: session.llm.model,
        time:,
      ),
      list.reverse(history),
    )
    |> json.to_string
  use path <- system.then(resolve_path(path, source.Pipe))
  use result <- system.then(system.write_file(path, exported))
  system.stdout(case result {
    Ok(Nil) -> "exported session to " <> path
    Error(reason) ->
      terminal.style(
        ansi.red,
        "failed to export session: " <> string.inspect(reason),
      )
  })
}

/// Effects performed by code from the config's files, such as context functions,
/// use the context policy when there is one.
/// The agent's code, and modules from the hub, use the policy.
fn policy_for(session: Session, origin: source.Origin) {
  case origin, session.context_policy {
    source.Disk(..), Some(context_policy) -> context_policy
    _, _ -> session.policy
  }
}

/// Published references are loaded unless the policy has a `reference` rule that denies them.
fn check_reference(session: Session, reference, meta: source.Location, state) {
  case policy.rule(policy_for(session, meta.origin), policy.reference) {
    policy.Apply(_) -> {
      let text = ir.reference_to_string(reference)
      use #(outcome, state) <- system.map(decide(
        session,
        policy.reference,
        value.String(text),
        meta,
        state,
      ))
      let result = case outcome {
        Ok(Perform(_)) -> Ok(Nil)
        Ok(Resume(value.String(reason))) ->
          Error(abort("reference " <> text <> " denied by policy: " <> reason))
        Ok(Resume(_)) ->
          Error(abort("reference " <> text <> " denied by policy"))
        Error(reason) -> Error(reason)
      }
      #(result, state)
    }
    policy.Unrestricted | policy.Refused -> system.Done(#(Ok(Nil), state))
  }
}

/// Check every published reference in the agent's code before it is fetched.
fn check_references(session, source: ir.Node(source.Location), state) {
  let references =
    ir.list_references(source)
    |> list.filter(fn(reference) {
      case reference {
        ir.Relative(..) -> False
        _ -> True
      }
    })
  system.fold(references, #(Ok(Nil), state), fn(acc, reference) {
    case acc {
      #(Error(_), _) -> system.Done(acc)
      #(Ok(Nil), state) -> check_reference(session, reference, source.1, state)
    }
  })
}

fn untrusted(trusted, eyg_state, then) {
  case trusted {
    Ok(Nil) -> then()
    Error(reason) ->
      system.Done(
        #(Error("error: " <> simple_debug.describe(reason)), eyg_state, []),
      )
  }
}

/// Request a completion and print its content as it arrives.
fn stream_completion(
  session: Session,
  history: List(chat.Message(tool.Call)),
) -> system.Effect(Result(chat.Completion(tool.Call), String)) {
  use result <- system.map(completion(session, history, io.print))
  io.println("")
  result
}

/// Stream a completion into a frontend callback while retaining provider parsing.
pub fn completion(session: Session, history, on_delta) {
  let request =
    provider.stream_completion_request(
      session.llm,
      session.provider_context,
      history,
    )
  use response <- system.then(system.fetch_stream(request))
  case response {
    Ok(response.Response(status: 200, body: reader, ..)) ->
      read_stream(session.llm.provider, reader, <<>>, chat.fresh(), on_delta)
    Ok(response.Response(status:, body: reader, ..)) -> {
      use body <- system.map(read_all(reader, <<>>))
      Error(
        "unexpected status: "
        <> int.to_string(status)
        <> case bit_array.to_string(body) {
          Ok("") | Error(Nil) -> ""
          Ok(body) -> " " <> body
        },
      )
    }
    Error(reason) ->
      system.Done(Error(
        "request to "
        <> uri.to_string(request.to_uri(request))
        <> " failed: "
        <> effect.describe_fetch_error(reason),
      ))
  }
}

fn read_stream(llm_provider, reader, remaining, completion, on_delta) {
  use chunk <- system.then(system.read_chunk(reader))
  case chunk, terminal.interrupted() {
    _, True -> system.Done(Error(stopped_message))
    Ok(#(Some(bits), reader)), False -> {
      let #(completions, remaining) =
        provider.completion_chunk_parse(llm_provider, remaining, bits)
      list.each(completions, fn(delta: chat.Completion(tool.Call)) {
        on_delta(delta.content)
      })
      let completion = chat.append_chunks(completion, completions)
      read_stream(llm_provider, reader, remaining, completion, on_delta)
    }
    Ok(#(None, _)), False -> {
      system.Done(Ok(completion))
    }
    Error(reason), False ->
      system.Done(Error(effect.describe_fetch_error(reason)))
  }
}

const stopped_message = "Stopped, send a message to continue."

/// Stop the turn if the user pressed Ctrl-C.
fn stopped(runtime, then) {
  case terminal.interrupted() {
    True -> system.Done(#(Error(stopped_message), runtime))
    False -> then()
  }
}

fn read_all(reader, acc) {
  use chunk <- system.then(system.read_chunk(reader))
  case chunk {
    Ok(#(Some(bits), reader)) -> read_all(reader, <<acc:bits, bits:bits>>)
    _ -> system.Done(acc)
  }
}
