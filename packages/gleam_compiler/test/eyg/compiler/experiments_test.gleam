import eyg/analysis/inference/levels_j/contextual as j
import eyg/compiler/platform/browser
import eyg/compiler/platform/dom
import eyg/compiler/platform/signals
import eyg/compiler/platform/webrtc
import eyg/ir/tree as ir
import eyg/parser
import gleam/dict
import gleam/list
import gleam/string
import simplifile

fn examples() {
  let size =
    ir.apply(
      ir.apply(ir.extend("rows"), ir.integer(2)),
      ir.apply(ir.apply(ir.extend("columns"), ir.integer(2)), ir.empty()),
    )
  [
    #("read_handles", dom.handles(), ir.empty()),
    #("read_selectors", dom.selectors(), ir.empty()),
    #("read_selectors_each", dom.selectors(), size),
    #("read_snapshot", dom.snapshot(), ir.empty()),
    #("rows_imperative", dom.imperative(), ir.integer(10)),
    #("rows_patch", dom.patch(), ir.integer(10)),
    #("rows_render", dom.render(), ir.integer(10)),
    #("counters_host", signals.host(), ir.integer(10)),
    #("counters_handlers", dom.selectors(), ir.integer(10)),
    #("counters_render", dom.render(), ir.integer(10)),
    #("counters_render_batched", dom.render(), ir.integer(10)),
    #("webrtc_mirror", webrtc.mirror(), ir.integer(10)),
    #("webrtc_batch", webrtc.batch(), ir.integer(10)),
    #("webrtc_session", webrtc.session(), ir.integer(10)),
  ]
}

pub fn browser_examples_use_only_the_effects_of_their_design_test() {
  let failures =
    list.filter_map(examples(), fn(example) {
      let #(name, effects, argument) = example
      let assert Ok(text) =
        simplifile.read("examples/browser/" <> name <> ".eyg")
      case parser.from_string(text) {
        Error(reason) ->
          Ok(name <> " does not parse " <> string.inspect(reason))
        Ok(#(source, _)) -> {
          let program = ir.apply(ir.clear_annotation(source), argument)
          let context =
            j.with_effects(
              j.pure(),
              list.append(browser.touch_grass(), effects),
            )
          let analysis = j.check_with_references(context, dict.new(), program)
          case j.all_errors(analysis) {
            [] -> Error(Nil)
            errors ->
              Ok(name <> " " <> string.inspect(list.map(errors, fn(e) { e.1 })))
          }
        }
      }
    })
  assert [] == failures as string.join(failures, "\n")
}
