import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/binding/debug as analysis_debug
import eyg/analysis/type_/binding/error
import eyg/hub/cache
import eyg/interpreter/break
import eyg/interpreter/expression
import eyg/interpreter/simple_debug
import eyg/interpreter/state
import eyg/interpreter/value as v
import eyg/ir/tree as ir
import eyg/ir/utils.{push_new} as _
import eyg/parser
import eyg/parser/parser.{type Reason} as _
import gleam/bit_array
import gleam/dict
import gleam/dynamic/decode
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import multiformats/cid/v1
import ogre/origin
import overlay/agent
import overlay/check as overlay_check
import overlay/llm/chat
import overlay/llm/tool
import overlay/policy
import overlay/tools/guide
import overlay/tools/run
import overlay/web/artifact
import overlay/web/puppet
import pal/platform/browser
import pal/system
import touch_grass as tg
import touch_grass/harness/browser as harness
import touch_grass/interface
import touch_grass/prompt

pub type Context {
  Context(
    cache: cache.Cache(Meta),
    counter: Int,
    effects: List(system.Effect(#(Int, state.Value(Meta)))),
    context: cache.Module(Meta),
    artifacts: artifact.Store,
    origin: origin.Origin,
    /// Without a policy every effect is performed.
    policy: Option(policy.Policy(state.Value(Meta))),
  )
}

pub type Meta =
  List(Int)

/// The running state of a given tool call
pub type Call {
  UnknownTool(name: String)
  BadArguments(List(decode.DecodeError))
  InvalidCode(reason: Reason, code: String)
  Pulling(ir.Node(Meta))
  Fetching(cids: List(v1.Cid), source: ir.Node(Meta))
  Successful(state.Value(Meta))
  Errored(List(#(Meta, error.Reason)))
  Exception(state.Reason(Meta))
  Aborted(String)
  Handling(
    task_id: Int,
    env: state.Env(Meta),
    k: state.Stack(Meta),
    screenshot: Bool,
  )
  /// Waiting for a guide to be fetched by the harness.
  Reading(task_id: Int)
  Read(Result(String, String))
  /// Waiting for the user to answer a question asked by the policy.
  Approving(
    task_id: Int,
    label: String,
    lift: state.Value(Meta),
    denied: state.Value(Meta),
    env: state.Env(Meta),
    k: state.Stack(Meta),
  )
}

/// A tool call state and any output printed or screenshots taken.
/// Output and images are held most recent first.
pub type Progress {
  Progress(id: String, output: List(String), images: List(BitArray), call: Call)
}

pub type Calls =
  List(Progress)

pub fn execute_all(
  context: Context,
  tool_calls: List(tool.Call),
) -> #(Context, Calls) {
  list.map_fold(tool_calls, context, execute_single)
}

fn execute_single(ctx: Context, call: tool.Call) -> #(Context, Progress) {
  let tool.Call(id:, function:) = call
  let tool.FunctionCall(name:, arguments:) = function
  case agent.cast_tool_call(name, arguments) {
    Ok(agent.Run(code)) -> run_code(ctx, id, code)
    Ok(agent.Guide(name)) -> read_guide(ctx, id, name)
    Error(agent.DecodeError(reason)) -> #(ctx, failed(id, BadArguments(reason)))
    Error(agent.UnknownTool) -> #(ctx, failed(id, UnknownTool(name)))
  }
}

fn run_code(ctx: Context, id: String, code: String) -> #(Context, Progress) {
  case parser.all_from_string(code) {
    Ok(source) -> {
      let source = ir.map_annotation(source, fn(_) { [] })
      case check_single(source, ctx.cache, ctx.context) {
        [] -> {
          let #(ctx, output, call) =
            source
            |> execute(ctx.context)
            |> loop(ctx, [])
          #(ctx, Progress(id:, output:, images: [], call:))
        }
        errors -> {
          let references = missing_references(errors)
          case requires_pull(references, ctx.cache) {
            True -> {
              let cache = cache.pull(ctx.cache)
              let ctx = Context(..ctx, cache:)
              #(ctx, failed(id, Pulling(source)))
            }
            False -> {
              case to_fetch(references, ctx.cache, []) {
                [] -> #(ctx, failed(id, Errored(errors)))
                needed -> {
                  let cache = cache.fetch_all(ctx.cache, needed)
                  let ctx = Context(..ctx, cache:)
                  #(ctx, failed(id, Fetching(needed, source)))
                }
              }
            }
          }
        }
      }
    }
    Error(reason) -> #(ctx, failed(id, InvalidCode(reason, code)))
  }
}

fn check_single(
  source: #(ir.Expression(a), a),
  cache: cache.Cache(b),
  context: cache.Module(_),
) -> List(#(a, error.Reason)) {
  let analysis =
    overlay_check.agent(effects(), context.type_)
    |> infer.check(source)
    |> cache.infer_sync(cache)
  infer.all_errors(analysis)
}

pub fn missing_references(errors) {
  list.filter_map(errors, fn(error) {
    let #(_, error) = error
    case error {
      error.MissingReference(reference:) -> Ok(reference)
      _ -> Error(Nil)
    }
  })
}

fn requires_pull(refs, cache) {
  case refs {
    [] -> False
    [reference, ..rest] ->
      case reference {
        ir.Content(..) | ir.Relative(..) -> requires_pull(rest, cache)
        ir.Package(package:) ->
          case cache.package(cache, package) {
            Ok(_) -> requires_pull(rest, cache)
            Error(_) -> True
          }
        ir.Version(package:, version:) ->
          case cache.unbound_release(cache, package, version) {
            Ok(_) -> requires_pull(rest, cache)
            Error(_) -> True
          }
        ir.Pinned(release: ir.Release(package:, version:, module: _)) ->
          case cache.unbound_release(cache, package, version) {
            Ok(_) -> requires_pull(rest, cache)
            Error(_) -> True
          }
      }
  }
}

pub fn to_fetch(
  refs: List(ir.Reference),
  cache: cache.Cache(a),
  acc: List(v1.Cid),
) -> List(v1.Cid) {
  case refs {
    [] -> acc
    [reference, ..rest] -> {
      let acc = case reference {
        ir.Content(cid:) -> push_new(acc, cid)
        ir.Package(package:) ->
          case cache.package(cache, package) {
            Ok(cache.Entry(module:, ..)) -> push_new(acc, module)
            Error(_) -> acc
          }
        ir.Version(package:, version:) ->
          case cache.unbound_release(cache, package, version) {
            Ok(cid) -> push_new(acc, cid)
            Error(_) -> acc
          }
        // Only the release log can make a pin right, so there is nothing to
        // gain from fetching a module it does not name for that release.
        ir.Pinned(release: ir.Release(package:, version:, module:)) ->
          case cache.unbound_release(cache, package, version) {
            Ok(cid) if cid == module -> push_new(acc, module)
            _ -> acc
          }
        ir.Relative(..) -> acc
      }
      to_fetch(rest, cache, acc)
    }
  }
}

fn failed(id, call) {
  Progress(id:, output: [], images: [], call:)
}

// context can include tasks
// If we don't keep track of errors we'll keep calculating
// prepare and fetch all need to look at relative references
// Or we just type check and lookup
// There's multiple ways to do this, pick one.
// 1. reset failed
// 2. reset pulled
// document/state

fn loop(
  return: Result(state.Value(Meta), state.Debug(Meta)),
  ctx: Context,
  output: List(String),
) -> #(Context, List(String), Call) {
  case return {
    Error(#(break.UndefinedReference(reference) as break, _m, env, k)) -> {
      case reference {
        ir.Relative(location:) -> {
          let message = "unable to load source from location: " <> location
          #(ctx, output, Aborted(message))
        }
        _ ->
          case cache.get_reference(ctx.cache, reference) {
            Ok(cache.Module(value:, ..)) ->
              loop(expression.resume(value, env, k), ctx, output)
            Error(Nil) -> #(ctx, output, Exception(break))
          }
      }
    }
    Error(#(break.UnhandledEffect(label, lift), _, env, k)) ->
      case decide(ctx, label, lift) {
        Perform(lift) -> perform(label, lift, env, k, ctx, output)
        Resume(value) -> loop(expression.resume(value, env, k), ctx, output)
        Refuse(reason) -> #(ctx, output, Aborted(reason))
        Approve(question:, denied:) -> {
          let id = ctx.counter
          let effect =
            system.Prompt(question <> " allow? y/N", fn(answer) {
              system.Done(#(id, prompt.encode(answer)))
            })
          let effects = [effect, ..ctx.effects]
          let ctx = Context(..ctx, counter: id + 1, effects:)
          #(ctx, output, Approving(id, label, lift, denied, env, k))
        }
      }
    Error(#(reason, _, _, _)) -> #(ctx, output, Exception(reason))
    Ok(value) -> #(ctx, output, Successful(value))
  }
}

/// Effects for the artifact workspace, in addition to the browser harness.
type WorkspaceEffect {
  ArtifactEffect(artifact.Effect)
  PuppetEffect(puppet.Request)
}

fn workspace_effects() {
  [
    tg.map(puppet.effect(), PuppetEffect),
    ..list.map(artifact.effects(), tg.map(_, ArtifactEffect))
  ]
}

fn perform(label, lift, env, k, ctx: Context, output) {
  case interface.cast(workspace_effects(), label, lift) {
    Ok(ArtifactEffect(effect)) -> {
      let #(artifacts, value) = artifact.perform(ctx.artifacts, effect)
      let ctx = Context(..ctx, artifacts:)
      loop(expression.resume(value, env, k), ctx, output)
    }
    Ok(PuppetEffect(request)) ->
      case puppet.frame_selector(ctx.artifacts, request.page) {
        Ok(selector) -> {
          let id = ctx.counter
          let effect =
            system.RequestFrame(
              selector:,
              message: puppet.to_json(request),
              // Allow for loading the preview and rendering screenshots.
              timeout: request.timeout + 5000,
              resume: fn(reply) {
                let reply = result.try(reply, puppet.reply)
                system.Done(#(id, puppet.to_value(reply)))
              },
            )
          let effects = [effect, ..ctx.effects]
          let ctx = Context(..ctx, counter: id + 1, effects:)
          let screenshot = request.action == puppet.Screenshot
          #(ctx, output, Handling(id, env, k, screenshot))
        }
        Error(reason) -> {
          let value = puppet.to_value(Error(reason))
          loop(expression.resume(value, env, k), ctx, output)
        }
      }
    Error(break.UnhandledEffect(..)) ->
      browser_perform(label, lift, env, k, ctx, output)
    Error(reason) -> #(ctx, output, Exception(reason))
  }
}

fn browser_perform(label, lift, env, k, ctx: Context, output) {
  {
    case browser.cast(label, lift) {
      // Printing belongs to the result the agent reads, not only the browser
      // console. Keeping it here also preserves output across suspension.
      Ok(harness.Print(message)) ->
        loop(expression.resume(v.unit(), env, k), ctx, [message, ..output])
      Ok(effect) -> {
        case browser.extrinsic(effect) {
          browser.Abort(reason) -> #(ctx, output, Aborted(reason))
          browser.Work(system.Done(value)) ->
            loop(expression.resume(value, env, k), ctx, output)
          browser.Work(effect) -> {
            let id = ctx.counter

            let effect = system.map(effect, fn(v) { #(id, v) })
            let effects = [effect, ..ctx.effects]
            let ctx = Context(..ctx, counter: id + 1, effects:)
            #(ctx, output, Handling(id, env, k, False))
          }
          browser.Spotless(..) -> #(
            ctx,
            output,
            Aborted("Spotless integration not supported in harness"),
          )
        }
      }
      Error(reason) -> #(ctx, output, Exception(reason))
    }
  }
}

fn is_running(call: Call) {
  case call {
    UnknownTool(..)
    | BadArguments(..)
    | InvalidCode(..)
    | Successful(..)
    | Errored(..)
    | Exception(..)
    | Aborted(..)
    | Read(..) -> False
    Handling(..) | Pulling(..) | Fetching(..) | Reading(..) | Approving(..) ->
      True
  }
}

pub fn any_running(tool_calls: Calls) {
  list.any(tool_calls, fn(progress: Progress) { is_running(progress.call) })
}

pub fn all_returns(calls) {
  do_all_returns(calls, [])
}

fn do_all_returns(
  calls: Calls,
  acc: List(chat.Message(a)),
) -> Result(List(chat.Message(a)), Nil) {
  case calls {
    [] -> Ok(list.reverse(acc))
    [Progress(id:, output:, images:, call:), ..calls] -> {
      let message = case call {
        UnknownTool(name:) -> Ok("unknown tool: " <> name)
        BadArguments(reasons) -> Ok(string.inspect(reasons))
        InvalidCode(reason, code) -> Ok(parser.format_error(reason, code))
        Successful(value) -> Ok(inspect_result(value))
        Errored(errors) -> {
          list.map(errors, fn(error) { analysis_debug.reason(error.1) })
          |> string.join("\n")
          |> Ok()
        }
        Exception(reason) -> Ok(simple_debug.describe(reason))
        Aborted(reason) -> Ok(reason)
        Read(Ok(text)) -> Ok(text)
        Read(Error(reason)) -> Ok(reason)
        Handling(..)
        | Pulling(..)
        | Fetching(..)
        | Reading(..)
        | Approving(..) -> Error(Nil)
      }
      case message {
        Ok(text) -> {
          let message =
            chat.ToolResultMessage(
              tool_call_id: id,
              text: run.report(output, text),
              images: attached(images),
            )
          do_all_returns(calls, [message, ..acc])
        }
        Error(Nil) -> Error(Nil)
      }
    }
  }
}

fn attached(images) {
  list.take(images, 3)
  |> list.reverse
  |> list.map(bit_array.base64_encode(_, True))
}

/// Tool results are text for the model, not a binary transport.
/// Returning a large Fetch response, such as a video, must not encode every
/// byte into the next model request. Only this presentation is summarized,
/// the program works with the original value.
pub fn inspect_result(value) -> String {
  summarize_binaries(value) |> simple_debug.inspect
}

/// Binaries up to this size are shown in full.
const shown_bytes = 1024

fn summarize_binaries(value: v.Value(a, b)) -> v.Value(a, b) {
  case value {
    v.Binary(bytes) ->
      case bit_array.byte_size(bytes) {
        size if size > shown_bytes ->
          v.Tagged(
            "BinarySummary",
            v.Record(
              dict.from_list([
                #("bytes", v.Integer(size)),
                #(
                  "note",
                  v.String(
                    "Bytes omitted from tool output. Use the bytes in the program that produced them, this summary cannot reconstruct them.",
                  ),
                ),
              ]),
            ),
          )
        _ -> value
      }
    v.Record(fields) ->
      v.Record(
        dict.map_values(fields, fn(_, child) { summarize_binaries(child) }),
      )
    v.LinkedList(items) -> v.LinkedList(list.map(items, summarize_binaries))
    v.Tagged(label, inner) -> v.Tagged(label, summarize_binaries(inner))
    v.Partial(func, args) -> v.Partial(func, list.map(args, summarize_binaries))
    _ -> value
  }
}

pub fn pulled(ctx: Context, progress: Progress) -> #(Context, Progress) {
  let Progress(id:, output:, images:, call:) = progress

  case call {
    Pulling(source) -> {
      // TODO move to cache.infer_sync that will gather need to pull and to fetch references
      case check_single(source, ctx.cache, ctx.context) {
        [] -> {
          let #(ctx, output, call) =
            source
            |> execute(ctx.context)
            // output should always be empty going into this loop.
            // Maybe output should move into a running state of call
            |> loop(ctx, output)
          #(ctx, Progress(id:, output:, images:, call:))
        }
        errors -> {
          // Don't check for needs pull here as we've aready done that.
          let references = missing_references(errors)
          case to_fetch(references, ctx.cache, []) {
            [] -> #(ctx, failed(id, Errored(errors)))
            needed -> {
              let cache = cache.fetch_all(ctx.cache, needed)
              let ctx = Context(..ctx, cache:)
              #(ctx, failed(id, Fetching(needed, source)))
            }
          }
        }
      }
    }
    _ -> #(ctx, progress)
  }
}

fn execute(source: ir.Node(Meta), context: cache.Module(Meta)) {
  expression.execute(source, [#("context", context.value)])
}

pub fn check_fetching(
  ctx: Context,
  progress: Progress,
) -> #(Context, Progress) {
  let Progress(id:, output:, images:, call:) = progress
  case call {
    Fetching(cids:, source:) -> {
      let cids = list.filter(cids, still_fetching(_, ctx.cache))
      case cids {
        [] ->
          case check_single(source, ctx.cache, ctx.context) {
            [] -> {
              let #(ctx, output, call) =
                source
                |> execute(ctx.context)
                // output should always be empty going into this loop.
                // Maybe output should move into a running state of call
                |> loop(ctx, output)
              #(ctx, Progress(id:, output:, images:, call:))
            }
            errors -> #(ctx, failed(id, Errored(errors)))
          }
        _ -> #(ctx, failed(id, Fetching(cids, source)))
      }
    }
    _ -> #(ctx, progress)
  }
}

// TODO move this to cache
pub fn still_fetching(cid, cache) {
  case cache.get_module(cache, cid) {
    Ok(_) -> False
    // Not requested is the state given by fetch and before flush.
    // It means not requested from the network not never requested by the user.
    Error(cache.NotRequested)
    | Error(cache.Requested(..))
    | Error(cache.DependsOn(..)) -> True

    Error(cache.Failed(_)) | Error(cache.Invalid(_)) -> False
  }
}

pub fn effect_handled(
  ctx: Context,
  calls: Calls,
  id: Int,
  value: state.Value(Meta),
) -> #(Context, Calls) {
  list.map_fold(calls, ctx, fn(ctx, call) { apply_effect(ctx, call, id, value) })
}

fn apply_effect(
  ctx: Context,
  progress: Progress,
  finished_id: Int,
  value: state.Value(Meta),
) {
  let Progress(id:, output:, images:, call:) = progress
  case call {
    Handling(task_id:, env:, k:, screenshot:) if task_id == finished_id -> {
      let images = case screenshot, value {
        True, v.Tagged("Ok", v.Tagged("Image", v.Binary(image))) -> [
          image,
          ..images
        ]
        _, _ -> images
      }
      let #(ctx, output, call) =
        loop(expression.resume(value, env, k), ctx, output)
      #(ctx, Progress(id:, output:, images:, call:))
    }
    Approving(task_id:, label:, lift:, denied:, env:, k:)
      if task_id == finished_id
    -> {
      let #(ctx, output, call) = case value {
        v.Tagged("Ok", v.String(answer)) if answer == "y" || answer == "Y" ->
          perform(label, lift, env, k, ctx, output)
        _ -> loop(expression.resume(denied, env, k), ctx, output)
      }
      #(ctx, Progress(id:, output:, images:, call:))
    }
    Reading(task_id:) if task_id == finished_id -> {
      let result = case value {
        v.Tagged("Ok", v.String(text)) -> Ok(text)
        v.Tagged("Error", v.String(reason)) -> Error(reason)
        _ -> Error("unexpected guide result")
      }
      #(ctx, Progress(id:, output:, images:, call: Read(result)))
    }
    _ -> #(ctx, progress)
  }
}

/// Guides are fetched by the harness so are not subject to agent permissions.
fn read_guide(ctx: Context, id: String, name: String) -> #(Context, Progress) {
  case guide.request(ctx.origin, name) {
    Ok(request) -> {
      let task_id = ctx.counter
      let effect = {
        use response <- system.Fetch(request)
        let result = case response {
          Ok(response) -> guide.response(response)
          Error(reason) -> Error(string.inspect(reason))
        }
        let value = case result {
          Ok(text) -> v.ok(v.String(text))
          Error(reason) -> v.error(v.String(reason))
        }
        system.Done(#(task_id, value))
      }
      let ctx =
        Context(..ctx, counter: task_id + 1, effects: [effect, ..ctx.effects])
      #(ctx, failed(id, Reading(task_id)))
    }
    Error(reason) -> #(ctx, failed(id, Read(Error(reason))))
  }
}

/// The effects available to the agent.
/// Service effects need a Spotless integration which this harness does not have.
pub fn effects() {
  let services =
    list.map(
      [harness.DNSimple, harness.GitHub, harness.Vimeo],
      harness.effect_label,
    )
  let browser =
    harness.effects()
    |> list.filter(fn(effect) { !list.contains(services, effect.name) })
    |> list.map(tg.map(_, fn(_) { Nil }))
  list.append(browser, list.map(workspace_effects(), tg.map(_, fn(_) { Nil })))
}

type Outcome {
  Perform(state.Value(Meta))
  Resume(state.Value(Meta))
  Refuse(String)
  Approve(question: String, denied: state.Value(Meta))
}

/// Ask the policy, if there is one, what to do with an effect.
fn decide(ctx: Context, label, lift) -> Outcome {
  case ctx.policy, label {
    None, _ -> Perform(lift)
    // Aborting ends the program, it needs no permission.
    Some(_), "Abort" -> Perform(lift)
    Some(rules), _ ->
      case policy.rule(rules, label) {
        policy.Apply(function) -> {
          let return =
            expression.call(function, [#(lift, [])])
            |> cache.static_loop(ctx.cache, expression.resume)
          case return {
            Ok(returned) ->
              case policy.decision(returned) {
                Ok(policy.Pass(lift)) -> Perform(lift)
                Ok(policy.Mock(value)) -> Resume(value)
                Ok(policy.Ask(question:, denied:)) ->
                  Approve(question:, denied:)
                Error(reason) ->
                  Refuse("policy for " <> label <> " failed: " <> reason)
              }
            Error(#(reason, _, _, _)) ->
              Refuse(
                "policy for "
                <> label
                <> " failed: "
                <> simple_debug.describe(reason),
              )
          }
        }
        policy.Unrestricted -> Perform(lift)
        policy.Refused -> Refuse(policy.refused(label))
      }
  }
}
