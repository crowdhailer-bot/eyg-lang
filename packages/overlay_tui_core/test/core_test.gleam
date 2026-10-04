import core/controller
import gleam/javascript/promise
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleam_opentui as o
import gleam_opentui/testing as t
import gleeunit/should
import terminal/app as a
import terminal/driver
import terminal/protocol as p
import test_frontend as native_view

fn setup() {
  use setup <- promise.map(t.create("{\"width\":100,\"height\":32}"))
  let setup = setup |> should.be_ok
  let handle =
    controller.start(
      t.renderer(setup),
      [],
      False,
      ".",
      [#("EYG_ORIGIN", "http://127.0.0.1:1")],
      native_view.mount,
    )
  #(setup, handle)
}

fn replay(overlay) {
  fn(emit) {
    controller.Port(
      fn(request) {
        case request {
          p.Initialize(_) ->
            emit(case overlay {
              True -> p.OverlayReady("fixture")
              False -> p.Ready(["standard"])
            })
          _ -> Nil
        }
        Ok(Nil)
      },
      fn() { promise.resolve(Nil) },
    )
  }
}

fn wait_for(handle: controller.Handle, predicate, remaining) {
  case predicate(handle.model()), remaining {
    True, _ -> promise.resolve(Nil)
    False, 0 -> {
      let status = "Timed out: " <> handle.model().status
      use Nil <- promise.map(handle.stop())
      panic as status
    }
    False, _ -> {
      use Nil <- promise.await(promise.wait(5))
      wait_for(handle, predicate, remaining - 1)
    }
  }
}

fn render(setup) {
  use rendered <- promise.await(t.render_once(setup))
  should.be_ok(rendered)
  // Reveal callbacks run after layout, requiring one more render for capture.
  use rendered <- promise.map(t.render_once(setup))
  should.be_ok(rendered)
  t.capture(setup)
}

fn key(setup, key) {
  t.press_key(t.input(setup), key, False, False, False) |> should.be_ok
}

pub fn real_input_evaluation_effects_resize_and_shutdown_test() {
  use #(setup, handle) <- promise.await(setup())
  use Nil <- promise.await(wait_for(handle, fn(model) { model.ready }, 1000))
  use _ <- promise.await(render(setup))
  use typed <- promise.await(t.type_text(
    t.input(setup),
    "perform StandardOut(\"hello\")",
  ))
  should.be_ok(typed)
  key(setup, "RETURN")
  use Nil <- promise.await(wait_for(
    handle,
    fn(model) { model.sequence == 1 && !model.busy },
    1000,
  ))
  t.press_key(t.input(setup), "e", True, False, False) |> should.be_ok
  use frame <- promise.await(render(setup))
  let entry = a.find_entry(handle.model(), 1) |> should.be_ok
  t.resize(setup, 60, 20) |> should.be_ok
  use small <- promise.await(render(setup))
  use Nil <- promise.map(handle.stop())
  entry.source |> should.equal("perform StandardOut(\"hello\")")
  entry.output |> should.equal("hello")
  entry.results |> should.equal([Ok("{}")])
  frame |> string.contains("↳ {}") |> should.be_true
  small |> string.contains("Ready") |> should.be_true
}

pub fn unicode_completion_and_prompt_draft_restore_test() {
  use setup <- promise.await(t.create("{\"width\":100,\"height\":32}"))
  let setup = setup |> should.be_ok
  let handle =
    controller.attach(
      t.renderer(setup),
      [],
      False,
      ".",
      replay(False),
      native_view.mount,
    )
  let prefix = "let banner = \"🌱緑é\" "
  use pasted <- promise.await(t.paste(t.input(setup), prefix <> "@sta"))
  should.be_ok(pasted)
  use Nil <- promise.await(wait_for(
    handle,
    fn(model) { model.choices != [] },
    1000,
  ))
  key(setup, "TAB")
  use Nil <- promise.await(promise.wait(1))
  let completed = o.plain_text(handle.mounted.screen.editor)
  handle.dispatch(a.Received(p.Prompt(1, "Name?")))
  use typed <- promise.await(t.type_text(t.input(setup), "Corin"))
  should.be_ok(typed)
  key(setup, "RETURN")
  use Nil <- promise.await(promise.wait(1))
  let restored = o.plain_text(handle.mounted.screen.editor)
  use Nil <- promise.map(handle.stop())
  completed |> should.equal(prefix <> "@standard")
  restored |> should.equal(completed)
}

fn structural(handle: controller.Handle, predicate) {
  wait_for(
    handle,
    fn(model) {
      case model.structure {
        Some(view) -> predicate(view)
        None -> False
      }
    },
    1000,
  )
}

pub fn structural_edit_undo_redo_and_drafts_use_real_worker_test() {
  use #(setup, handle) <- promise.await(setup())
  use Nil <- promise.await(wait_for(handle, fn(model) { model.ready }, 1000))
  use _ <- promise.await(t.type_text(t.input(setup), "!int_add(20, 22)"))
  key(setup, "F2")
  use Nil <- promise.await(
    structural(handle, fn(view) { view.source == "!int_add(20, 22)" }),
  )
  key(setup, "ARROW_RIGHT")
  use Nil <- promise.await(promise.wait(20))
  key(setup, "ARROW_RIGHT")
  use Nil <- promise.await(promise.wait(20))
  key(setup, "n")
  use Nil <- promise.await(structural(handle, fn(view) { view.input != None }))
  use _ <- promise.await(t.type_text(t.input(setup), "40"))
  key(setup, "RETURN")
  use Nil <- promise.await(
    structural(handle, fn(view) { view.source == "!int_add(40, 22)" }),
  )
  key(setup, "z")
  use Nil <- promise.await(
    structural(handle, fn(view) { view.source == "!int_add(20, 22)" }),
  )
  key(setup, "Z")
  use Nil <- promise.await(
    structural(handle, fn(view) { view.source == "!int_add(40, 22)" }),
  )
  key(setup, "F2")
  let draft = o.plain_text(handle.mounted.screen.editor)
  key(setup, "F2")
  use Nil <- promise.await(promise.wait(20))
  key(setup, "RETURN")
  use Nil <- promise.await(wait_for(
    handle,
    fn(model) { model.sequence == 1 && !model.busy },
    1000,
  ))
  let entry = a.find_entry(handle.model(), 1) |> should.be_ok
  use frame <- promise.await(render(setup))
  use Nil <- promise.map(handle.stop())
  draft |> should.equal("!int_add(20, 22)")
  entry.results |> should.equal([Ok("62")])
  frame |> string.contains("62") |> should.be_true
}

pub fn overlay_tool_code_effects_and_streaming_markdown_test() {
  use setup <- promise.await(t.create("{\"width\":100,\"height\":32}"))
  let setup = setup |> should.be_ok
  let handle =
    controller.attach(
      t.renderer(setup),
      [],
      True,
      ".",
      replay(True),
      native_view.mount,
    )
  handle.dispatch(a.Received(p.OverlayReady("fixture")))
  handle.dispatch(
    a.Received(p.Tool(-1, "run", "perform StandardOut(\"inspect me\")")),
  )
  handle.dispatch(
    a.Received(p.Effect(
      -1,
      p.EffectRecord("StandardOut", "\"inspect me\"", "{}", Some("pass")),
    )),
  )
  handle.dispatch(a.Received(p.ToolResult(-1, "Done", False, 12.0)))
  handle.dispatch(a.Received(p.Assistant(-2, "**Result**\n\n")))
  handle.dispatch(a.Received(p.Assistant(-2, "The tool succeeded.")))
  use before <- promise.await(frame_containing(
    setup,
    "The tool succeeded.",
    200,
  ))
  t.press_key(t.input(setup), "o", True, False, False) |> should.be_ok
  use code <- promise.await(render(setup))
  t.press_key(t.input(setup), "e", True, False, False) |> should.be_ok
  use effects <- promise.await(render(setup))
  use Nil <- promise.map(handle.stop())
  contains(before, "The tool succeeded.")
  before |> string.contains("inspect me") |> should.be_false
  contains(code, "perform StandardOut")
  code |> string.contains("↳ pass") |> should.be_false
  contains(effects, "↳ pass · {}")
}

fn frame_containing(setup, text, remaining) {
  use frame <- promise.await(render(setup))
  case string.contains(frame, text), remaining {
    True, _ | _, 0 -> promise.resolve(frame)
    False, _ -> {
      use Nil <- promise.await(promise.wait(10))
      frame_containing(setup, text, remaining - 1)
    }
  }
}

fn contains(frame, text) {
  case string.contains(frame, text) {
    True -> Nil
    False -> {
      let message = "Missing " <> text <> " in:\n" <> frame
      panic as message
    }
  }
}

pub fn native_mouse_expands_tool_code_test() {
  use setup <- promise.await(t.create(
    "{\"width\":100,\"height\":32,\"useMouse\":true}",
  ))
  let setup = setup |> should.be_ok
  let handle =
    controller.attach(
      t.renderer(setup),
      [],
      True,
      ".",
      replay(True),
      native_view.mount,
    )
  handle.dispatch(
    a.Received(p.Tool(-1, "run", "perform StandardOut(\"clicked\")")),
  )
  handle.dispatch(a.Received(p.ToolResult(-1, "done", False, 1.0)))
  use before <- promise.await(render(setup))
  let row =
    string.split(before, "\n")
    |> list.index_fold(-1, fn(found, line, index) {
      case string.contains(line, "▸ run") {
        True -> index
        False -> found
      }
    })
  use clicked <- promise.await(t.click(t.mouse(setup), 6, row))
  should.be_ok(clicked)
  use after <- promise.await(render(setup))
  let expanded = a.find_entry(handle.model(), -1) |> should.be_ok
  use Nil <- promise.map(handle.stop())
  expanded.code_expanded |> should.be_true
  contains(after, "perform StandardOut")
}

pub fn native_typing_and_shutdown_remain_responsive_during_infinite_evaluation_test() {
  use #(setup, handle) <- promise.await(setup())
  use Nil <- promise.await(wait_for(handle, fn(model) { model.ready }, 1000))
  use _ <- promise.await(t.type_text(
    t.input(setup),
    "let forever = (f) -> { f(f) } forever(forever)",
  ))
  key(setup, "RETURN")
  use Nil <- promise.await(promise.wait(100))
  let started = driver.now()
  use _ <- promise.await(t.type_text(t.input(setup), "next expression"))
  use frame <- promise.await(render(setup))
  let typing = driver.now() -. started
  use Nil <- promise.map(handle.stop())
  contains(frame, "next expression")
  contains(frame, "Running…")
  { typing <. 250.0 } |> should.be_true
  { driver.now() -. started <. 1000.0 } |> should.be_true
}

pub fn native_stdin_prompt_resumes_the_worker_test() {
  use #(setup, handle) <- promise.await(setup())
  use Nil <- promise.await(wait_for(handle, fn(model) { model.ready }, 1000))
  use _ <- promise.await(t.type_text(
    t.input(setup),
    "match perform StandardIn({}) { Ok(bytes) -> { !string_from_binary(bytes) } Error(e) -> { Error(e) } }",
  ))
  key(setup, "RETURN")
  use Nil <- promise.await(wait_for(
    handle,
    fn(model) { model.prompt != None },
    1000,
  ))
  use _ <- promise.await(t.type_text(t.input(setup), "hello from terminal"))
  key(setup, "RETURN")
  use Nil <- promise.await(wait_for(
    handle,
    fn(model) { model.sequence == 1 && !model.busy },
    1000,
  ))
  let entry = a.find_entry(handle.model(), 1) |> should.be_ok
  use Nil <- promise.map(handle.stop())
  entry.results |> should.equal([Ok("Ok(\"hello from terminal\")")])
}
