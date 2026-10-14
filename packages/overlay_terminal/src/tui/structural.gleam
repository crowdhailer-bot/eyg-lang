//// All terminal frontends use the same operations and projection as the website.
//// The terminal owns input and clipboard access; this module only transforms IR.

import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/binding/debug
import eyg/analysis/type_/isomorphic as t
import eyg/hub/cache
import eyg/ir/dag_json
import eyg/ir/tree as ir
import eyg/parser
import gleam/dict
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None}
import gleam/result
import gleam/string
import loam/execute
import loam/platform/computer
import loam/source
import loam/system
import morph/analysis
import morph/buffer
import morph/editable
import morph/lustre/frame
import morph/lustre/render
import morph/manipulation as m
import morph/picker
import morph/projection
import multiformats/cid/v1
import touch_grass/interface

pub fn context(scope: execute.Scope) {
  let #(bindings, env) =
    analysis.env_to_tenv(scope, source.Location(source.Repl, source.Json))
  infer.Context(env:, eff: t.Empty, level: 0, bindings:, expected_type: None)
  |> infer.with_effects(interface.types(computer.effects()))
}

pub fn parse(text, scope, state: execute.State) {
  let parsed = case string.trim(text) {
    "" -> Ok(#(ir.Vacant, []))
    _ -> {
      use code <- result.map(
        result.map_error(source.block_expression(text), parser.format_error(
          _,
          text,
        )),
      )
      ir.map_annotation(code, fn(_) { [] })
    }
  }
  use code <- result.map(parsed)
  buffer.from_source(code, context(scope), cache.types(state.cache))
}

pub fn view(buffer: buffer.Buffer) {
  let #(_, zoom) = buffer.projection
  let errors = infer.all_errors(buffer.analysis)
  render.projection_frame(buffer.projection, render.Statements, errors)
  |> render.push_render(zoom, render.Statements, errors)
  |> frame.to_fat_line
}

/// A readable history display, never used to execute the expression.
pub fn display(buffer: buffer.Buffer) {
  buffer.projection
  |> projection.rebuild
  |> editable.open_all
  |> render.top([])
}

pub fn type_info(buffer: buffer.Buffer) {
  case buffer.source(buffer) {
    #(ir.Vacant, _) -> #("", [])
    _ -> expression_type_info(buffer)
  }
}

fn expression_type_info(buffer: buffer.Buffer) {
  let type_ = case buffer.target_type(buffer) {
    Ok(type_) -> debug.mono(type_)
    Error(Nil) -> ""
  }
  let errors =
    list.map(infer.all_errors(buffer.analysis), fn(error) {
      debug.render_reason(error.1)
    })
  #(type_, errors)
}

pub fn navigate(buffer, key) {
  case key {
    "right" -> buffer.next(buffer)
    "left" -> buffer.previous(buffer)
    "up" -> buffer.up(buffer)
    "down" -> buffer.down(buffer)
    "a" -> buffer.increase(buffer)
    "k" -> buffer.toggle_open(buffer)
    " " -> buffer.next_vacant(buffer)
    _ -> Error(Nil)
  }
}

pub fn operation(buffer, key, state: execute.State) {
  let effects = interface.types(computer.effects())
  let packages =
    list.map(dict.to_list(state.cache.packages), fn(entry) {
      #(entry.0, entry.1.version)
    })
  let operation = case key {
    "w" -> Ok(m.call_with())
    "E" -> Ok(m.assign_before())
    "e" -> Ok(m.assign())
    "R" -> Ok(m.create_empty_record())
    "r" -> Ok(m.create_record())
    "t" -> Ok(m.insert_tag())
    "i" -> Ok(m.insert())
    "o" -> Ok(m.overwrite())
    "p" -> Ok(m.perform(effects))
    "s" -> Ok(m.insert_string())
    "d" -> Ok(m.delete())
    "f" -> Ok(m.insert_function())
    "g" -> Ok(m.select_field())
    "h" -> Ok(m.insert_handle(effects))
    "j" -> Ok(m.insert_builtin())
    "L" -> Ok(m.create_empty_list())
    "l" -> Ok(m.create_list())
    "@" -> Ok(m.choose_release(packages))
    "#" -> Ok(m.insert_reference())
    "Z" -> Ok(m.redo())
    "z" -> Ok(m.undo())
    "x" -> Ok(m.spread())
    "c" -> Ok(m.call_function())
    "C" -> Ok(m.call_once())
    "b" -> Ok(m.insert_binary())
    "n" -> Ok(m.insert_integer())
    "m" -> Ok(m.insert_case())
    "v" -> Ok(m.insert_variable())
    "<" -> Ok(m.insert_before())
    ">" -> Ok(m.insert_after())
    // Terminal modules are files in scope. Both web module and filesystem
    // shortcuts use the file picker, retaining the relative import in the IR.
    "q" | "Q" ->
      Ok(
        m.Operation("import file", fn(buffer) {
          use rebuild <- result.map(buffer.insert_explicit_reference(buffer))
          m.UserInput(
            m.PickSingle(picker.new("./", []), fn(path, context, refs) {
              rebuild(ir.Relative(path), context, refs)
            }),
          )
        }),
      )
    _ -> Error(Nil)
  }
  use m.Operation(name:, apply:) <- result.try(operation)
  use step <- result.map(apply(buffer))
  #(name, step)
}

pub fn resolve(rebuild, scope, state: execute.State) {
  rebuild(context(scope), cache.types(state.cache))
}

pub fn input_details(input) {
  case input {
    m.EnterText(value, _) -> #(value, [])
    m.EnterInteger(value, _) -> #(int.to_string(value), [])
    m.PickSingle(picker, _) | m.PickCid(picker, _) | m.PickRelease(picker, _) -> {
      case picker {
        picker.Typing(value, hints) -> #(value, hints)
        picker.Scrolling(_, hints) -> #("", hints)
      }
    }
  }
}

pub fn answer(input, text, scope, state: execute.State) {
  let context = context(scope)
  let refs = cache.types(state.cache)
  case input {
    m.EnterText(_, rebuild) | m.PickSingle(_, rebuild) ->
      Ok(rebuild(text, context, refs))
    m.EnterInteger(_, rebuild) -> {
      use number <- result.try(result.replace_error(
        int.parse(text),
        "Enter an integer",
      ))
      Ok(rebuild(number, context, refs))
    }
    m.PickCid(_, rebuild) -> {
      use #(cid, _) <- result.try(result.replace_error(
        v1.from_string(text),
        "Enter a content identifier",
      ))
      Ok(rebuild(cid, context, refs))
    }
    m.PickRelease(_, rebuild) -> {
      let text = case text {
        "@" <> rest -> rest
        _ -> text
      }
      case parser.all_from_string("@" <> text) {
        Ok(#(ir.Reference(ir.Pinned(release)), _)) ->
          Ok(rebuild(release, context, refs))
        Ok(#(ir.Reference(ir.Package(name)), _)) -> {
          use entry <- result.try(result.replace_error(
            dict.get(state.cache.packages, name),
            "Package not found in the hub index",
          ))
          Ok(rebuild(
            ir.Release(name, entry.version, entry.module),
            context,
            refs,
          ))
        }
        _ -> Error("Enter a package name or pinned package reference")
      }
    }
  }
}

pub fn paste(buffer, text, scope, state: execute.State) {
  use rebuild <- result.try(result.replace_error(
    buffer.set_expression(buffer),
    "Select an expression to paste",
  ))
  let code = case json.parse(text, dag_json.decoder([])) {
    Ok(code) -> Ok(code)
    Error(_) -> result.map(parse(text, scope, state), buffer.source)
  }
  use code <- result.map(code)
  rebuild(
    editable.from_annotated(code),
    context(scope),
    cache.types(state.cache),
  )
}

pub fn empty(scope, state: execute.State) {
  buffer.empty(context(scope), cache.types(state.cache))
}

pub fn json(buffer) {
  buffer.source(buffer) |> dag_json.to_string
}

pub fn executable(buffer) {
  buffer.source(buffer)
  |> ir.map_annotation(fn(_) { source.Location(source.Repl, source.Json) })
}

pub fn references(buffer) {
  ir.list_references(buffer.source(buffer))
}

/// Lookups use the normal pure module loader. They can fetch references and
/// read modules, but cannot run a module's unhandled program effects.
pub fn load_reference(reference, state) {
  use #(loaded, state) <- system.map(execute.lookup(
    reference,
    source.Repl,
    state,
  ))
  let type_ =
    result.map(loaded, fn(value) {
      analysis.value_to_type(
        value,
        dict.new(),
        source.Location(source.Repl, source.Json),
      ).0
    })
  #(result.replace_error(type_, Nil), state)
}

pub fn reanalyse(buffer: buffer.Buffer, scope, references) {
  let analysis = infer.check(context(scope), buffer.source(buffer))
  buffer.Buffer(..buffer, analysis: with_references(analysis, references))
}

fn with_references(step, references) {
  case step {
    infer.Done(analysis) -> analysis
    infer.Lookup(reference, resume) -> {
      let type_ = list.key_find(references, reference)
      with_references(resume(type_), references)
    }
  }
}
