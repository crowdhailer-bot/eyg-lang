//// This module is the effectful implementation of the tool calls available to overlay.
//// The state passed to each tool call is a cache of state that is reusable between tool calls.
//// Currently this state is only used for keeping access tokens for authenticated calls to API's
//// The state is currently a bun specific implementation however as it is scoped to tool calls it could be moved to overlay
//// Moving the full application state to overlay core is a bad idea, because we want to track different state when streaming
//// vs using The Elm Architecture in a Lustre web app.
//// 
//// The code execution tool is defined sans io using an effect type defined in this project.
//// The other tools could use the same effect logic, this is probably a good idea once we start applying policies for which files can be read.

import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/binding
import eyg/cli/check
import eyg/cli/internal/config
import eyg/cli/internal/terminal
import eyg/hub/cache
import eyg/interpreter/block
import eyg/interpreter/break
import eyg/interpreter/builtin
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
import gleam/json
import gleam/list
import gleam/option.{None, Some}
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
import overlay/export
import overlay/llm/chat
import overlay/llm/provider
import overlay/llm/tool
import overlay/policy
import overlay/tools/run
import touch_grass/harness/computer as harness_computer
import touch_grass/interface

// I don't need to implement streaming but if so that goes at the loam level
// the tools module in overlay web should be reusable
// policy is read as part of config, which can read files and effects. policy is pure

// Env should be readable on startup
/// Everything about a session that is fixed when it starts.
pub type Session {
  Session(
    llm: provider.Llm,
    provider_context: provider.Context,
    cwd: String,
    policy: policy.Policy(harness_computer.Effect, source.Location),
    context: execute.Value,
    /// The type of the context, the agent's code is checked against it.
    context_type: binding.Poly,
    /// Ctrl-C stops a turn rather than the session.
    interrupt: terminal.Interrupt,
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
  let rules = policy_rules()
  let context =
    infer.pure()
    |> infer.with_effects(interface.types(computer.effects()))
  let #(expected, bindings) =
    overlay_config.type_(rules, context.level, context.bindings)
  let context =
    infer.Context(..context, bindings:)
    |> infer.with_expected_type(expected)
  use #(type_, _, errors) <- system.then(check.check_from(
    source,
    cwd,
    context,
    state,
  ))
  use Nil <- system.try(case errors {
    [] -> Ok(Nil)
    _ -> Error(list.map(errors, check.render_error) |> string.join("\n"))
  })
  let context_type = overlay_check.context(type_)

  use #(result, state) <- system.then(execute.block(source, [], state))
  case result {
    Ok(#(Some(user_config), _)) ->
      case overlay_config.cast(user_config, rules) {
        Ok(user_config) -> {
          let session =
            Session(
              llm: user_config.llm,
              provider_context: provider.Context(
                system_prompt: agent.system_prompt(
                  config.client.origin,
                  policy.harness(user_config.policy),
                  user_config.readme,
                  True,
                ),
                tools: agent.tools(),
              ),
              cwd:,
              policy: user_config.policy,
              context: user_config.context,
              context_type:,
              interrupt: terminal.interrupt(),
            )
          use Nil <- system.then(outer_loop(session, state, []))
          Ok(0) |> system.Done
        }
        Error(reason) ->
          Error(execute.render_error(reason, source.1, state.Empty, cwd))
          |> system.Done
      }
    Ok(#(None, _)) ->
      Error(execute.render_error(break.Vacant, source.1, state.Empty, cwd))
      |> system.Done
    Error(#(reason, location, _, k)) ->
      Error(execute.render_error(reason, location, k, cwd)) |> system.Done
  }
}

fn outer_loop(
  session: Session,
  eyg_state: execute.State,
  history: List(chat.Message(tool.Call)),
) -> system.Effect(Nil) {
  use read <- system.then(input(">>>", "send a message"))
  case read {
    Ok("") -> system.Done(Nil)
    Ok("/export" <> path) -> {
      use Nil <- system.then(export(session, history, string.trim(path)))
      outer_loop(session, eyg_state, history)
    }
    Ok(text) -> {
      terminal.start_turn(session.interrupt)
      use #(result, eyg_state) <- system.then(
        inner_loop(session, eyg_state, [chat.UserMessage(text, []), ..history]),
      )
      terminal.end_turn(session.interrupt)
      // A failed completion is reported and the session continues from the
      // history before the failed message, so the user can try again.
      use history <- system.then(case result {
        Ok(history) -> system.Done(history)
        Error(reason) -> {
          // This output should be error and potentially show to the agent.
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
  let prompt = case terminal.noninteractive() {
    // The placeholder is overwritten as the user types.
    True -> {
      let prompt = ansi.bold(ansi.yellow(prompt))
      prompt <> " " <> ansi.dim(placeholder) <> "\r" <> prompt <> " "
    }
    False -> prompt <> " "
  }
  use return <- system.map(system.prompt(prompt))
  case return {
    Ok(line) -> Ok(string.trim_end(line))
    Error(reason) -> Error(reason)
  }
}

/// Complete and run tool calls until the agent replies without calling a tool.
pub fn inner_loop(
  session: Session,
  eyg_state: execute.State,
  history: List(chat.Message(tool.Call)),
) -> system.Effect(
  #(Result(List(chat.Message(tool.Call)), String), execute.State),
) {
  use <- stopped(session.interrupt, eyg_state)
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
      chat.ToolResultMessage(
        tool_call_id: call_id,
        text: agent.tool_result_text(text),
        images:,
      )
    }
    Error(reason) ->
      chat.ToolResultMessage(
        tool_call_id: call_id,
        text: agent.tool_result_text(reason),
        images: [],
      )
  }
}

pub fn execute_call(
  session: Session,
  call: tool.FunctionCall,
  eyg_state: execute.State,
) -> system.Effect(#(Result(tool.Return, String), execute.State)) {
  let tool.FunctionCall(name, arguments) = call
  case agent.cast_tool_call(name, arguments) {
    Ok(call) -> {
      use Nil <- system.then(system.stdout(log_line(call)))
      case call {
        agent.Run(code) -> {
          use #(result, eyg_state, output) <- system.then(run_do(
            session,
            code,
            eyg_state,
          ))
          let result = case result {
            // current state is not used by the CLI implementation, this will need to change.
            Ok(#(Some(value), _)) -> {
              Ok(
                tool.Return(run.report(output, agent.inspect_result(value)), []),
              )
            }
            Ok(#(None, _)) -> Ok(tool.Return(run.report(output, ""), []))
            Error(reason) -> Error(run.report(output, reason))
          }
          use Nil <- system.then(system.stdout(log_result(result)))
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
    agent.Run(code) ->
      terminal.style(ansi.bg_bright_green, "Executing EYG code.")
      <> "\n"
      <> terminal.style(ansi.dim, code)
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
  let input = source.Stdin

  case source.parse_input(code, input) {
    Ok(source) -> {
      let inference =
        overlay_check.agent(
          policy.harness(session.policy),
          session.context_type,
        )
      use #(_, _, errors) <- system.then(check.check_gated(
        source,
        session.cwd,
        inference,
        eyg_state,
        import_gate(session.policy, source.1),
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
              Error(list.map(errors, check.render_error) |> string.join("\n")),
              eyg_state,
              [],
            ),
          )
      }
    }
    Error(reason) -> system.Done(#(Error(reason), eyg_state, []))
  }
}

// This is a replacement for execute.loop because of the police
pub fn loop(
  return: Result(_, execute.Debug),
  state: execute.State,
  policy: policy.Policy(_, _),
  output: List(String),
) -> system.Effect(#(Result(_, execute.Debug), execute.State, List(String))) {
  case return {
    Ok(return) -> system.Done(#(Ok(return), state, output))
    Error(#(reason, meta, env, k)) ->
      case reason {
        break.UnhandledEffect(label, lift) -> {
          use #(decided, state) <- system.then(decide(
            policy,
            label,
            lift,
            meta,
            state,
          ))
          case decided {
            Perform(interface, modified) ->
              case interface.decode(modified) {
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
            Resume(returned) ->
              loop(block.resume(returned, env, k), state, policy, output)
            Failed(debug) -> system.Done(#(Error(debug), state, output))
            Unavailable ->
              system.Done(#(Error(#(reason, meta, env, k)), state, output))
          }
        }
        break.UndefinedReference(reference) -> {
          use #(result, state) <- system.then(lookup_reference(
            reference,
            meta,
            state,
            policy,
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

/// What to do with an effect, decided by its gate.
type Decided {
  /// Perform the effect with this, possibly modified, input.
  Perform(
    interface: interface.Interface(harness_computer.Effect, source.Location),
    input: execute.Value,
  )
  /// Resume the program with this value, the effect is not performed.
  Resume(execute.Value)
  /// The gate failed or returned an invalid decision.
  Failed(execute.Debug)
  /// The host has no rule for the effect.
  Unavailable
}

/// Call the gate for an effect, unchecked effects are always performed.
fn decide(
  policy: policy.Policy(harness_computer.Effect, source.Location),
  label: String,
  lift: execute.Value,
  meta: source.Location,
  state: execute.State,
) -> system.Effect(#(Decided, execute.State)) {
  case dict.get(policy, label) {
    Ok(policy.Interface(interface, policy.Gated(gate))) -> {
      let return = expression.call(gate, [#(lift, meta)])
      use #(result, state) <- system.map(execute.pure_loop(return, state))
      let decided = case result {
        Ok(value) ->
          case policy.decision_from_value(value) {
            Ok(policy.Pass(modified)) -> Perform(interface, modified)
            Ok(policy.Mock(returned)) -> Resume(returned)
            Error(Nil) ->
              Failed(#(
                break.IncorrectTerm(expected: "Pass/Mock", got: value),
                meta,
                builtin.default([]),
                state.Empty,
              ))
          }
        Error(debug) -> Failed(debug)
      }
      #(decided, state)
    }
    Ok(policy.Interface(interface, policy.Unrestricted)) ->
      system.Done(#(Perform(interface, lift), state))
    Error(Nil) -> system.Done(#(Unavailable, state))
  }
}

/// The ReadFile request a relative import of `path` is decided by.
fn import_request(path) {
  value.Record(
    dict.from_list([
      #("path", value.String(path)),
      #("offset", value.Integer(0)),
      #("limit", value.Integer(100_000_000)),
    ]),
  )
}

/// Decide the agent's relative imports when type checking, as they are decided when it runs.
/// Policies are pure so asking the ReadFile gate performs no effects.
fn import_gate(
  policy: policy.Policy(harness_computer.Effect, source.Location),
  meta: source.Location,
) -> check.Gate {
  fn(path, state) {
    use #(decided, state) <- system.map(decide(
      policy,
      "ReadFile",
      import_request(path),
      meta,
      state,
    ))
    let path = case decided {
      Perform(_, modified) ->
        cast.field("path", cast.as_string, modified)
        |> result.replace_error(Nil)
      Resume(_) | Failed(_) | Unavailable -> Error(Nil)
    }
    #(path, state)
  }
}

// Relative imports read files, so ask the ReadFile gate before resolving them.
fn lookup_reference(reference, meta, state, policy) {
  case reference {
    ir.Relative(path) -> {
      let request = import_request(path)
      use #(decided, state) <- system.then(decide(
        policy,
        "ReadFile",
        request,
        meta,
        state,
      ))
      case decided {
        Perform(_, modified) ->
          case cast.field("path", cast.as_string, modified) {
            Ok(path) -> execute.lookup(ir.Relative(path), meta.origin, state)
            Error(reason) -> system.Done(#(Error(reason), state))
          }
        Resume(value.Tagged("Error", reason)) ->
          system.Done(#(
            Error(break.UnhandledEffect(
              "Abort",
              value.String(
                "import of "
                <> path
                <> " denied by policy: "
                <> simple_debug.inspect(reason),
              ),
            )),
            state,
          ))
        Resume(returned) ->
          system.Done(#(
            Error(break.IncorrectTerm(
              "Pass(request) or Mock(Error(reason)) for an import",
              returned,
            )),
            state,
          ))
        Failed(#(reason, _, _, _)) -> system.Done(#(Error(reason), state))
        Unavailable ->
          system.Done(#(
            Error(break.UnhandledEffect("ReadFile", request)),
            state,
          ))
      }
    }
    _ -> execute.lookup(reference, meta.origin, state)
  }
}

pub fn policy_rules() {
  policy.match_rules(computer.effects(), [
    #("AppendFile", policy.PolicyField("append_file")),
    #("CreateKey", policy.PolicyField("create_key")),
    #("CWD", policy.PolicyField("cwd")),
    #("DecodeJSON", policy.Unchecked),
    #("DeleteFile", policy.PolicyField("delete_file")),
    #("Env", policy.PolicyField("env")),
    #("Exit", policy.Unchecked),
    #("EYGParse", policy.Unchecked),
    #("Fetch", policy.PolicyField("fetch")),
    #("Flip", policy.Unchecked),
    #("Hash", policy.Unchecked),
    #("MakeDirectory", policy.PolicyField("make_directory")),
    #("Now", policy.PolicyField("now")),
    #("Random", policy.Unchecked),
    #("ReadDirectory", policy.PolicyField("read_directory")),
    #("ReadFile", policy.PolicyField("read_file")),
    #("Sign", policy.PolicyField("sign")),
    #("Sleep", policy.PolicyField("sleep")),
    #("StandardError", policy.PolicyField("standard_error")),
    #("StandardIn", policy.PolicyField("standard_in")),
    #("StandardOut", policy.PolicyField("standard_out")),
    #("WriteFile", policy.PolicyField("write_file")),
  ])
}

/// Request a completion and print its content as it arrives.
fn stream_completion(
  session: Session,
  history: List(chat.Message(tool.Call)),
) -> system.Effect(Result(chat.Completion(tool.Call), String)) {
  let request =
    provider.stream_completion_request(
      session.llm,
      session.provider_context,
      history,
    )
  use response <- system.then(system.fetch_stream(request))
  case response {
    Ok(response.Response(status: 200, body: reader, ..)) ->
      read_stream(
        session.llm.provider,
        session.interrupt,
        reader,
        <<>>,
        chat.fresh(),
      )
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

fn read_stream(llm_provider, interrupt, reader, remaining, completion) {
  use chunk <- system.then(system.read_chunk(reader))
  case chunk, terminal.interrupted(interrupt) {
    _, True -> {
      use Nil <- system.then(system.stdout(""))
      system.Done(Error(stopped_message))
    }
    Ok(#(Some(bits), reader)), False -> {
      let #(completions, remaining) =
        provider.completion_chunk_parse(llm_provider, remaining, bits)
      let text =
        list.map(completions, fn(delta: chat.Completion(tool.Call)) {
          delta.content
        })
        |> string.concat
      use Nil <- system.then(system.write_stdout(text))
      let completion = chat.append_chunks(completion, completions)
      read_stream(llm_provider, interrupt, reader, remaining, completion)
    }
    Ok(#(None, _)), False -> {
      use Nil <- system.then(system.stdout(""))
      system.Done(Ok(completion))
    }
    Error(reason), False ->
      system.Done(Error(effect.describe_fetch_error(reason)))
  }
}

const stopped_message = "Stopped, send a message to continue."

/// Stop the turn if the user pressed Ctrl-C.
fn stopped(interrupt, runtime, then) {
  case terminal.interrupted(interrupt) {
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

/// Write the chat in the opencode session export format.
fn export(
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
  use resolved <- system.then(source.resolve_filepath(source.Pipe, path))
  let path = result.unwrap(resolved, path)
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
