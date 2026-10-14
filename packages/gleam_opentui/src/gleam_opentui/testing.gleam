//// The native OpenTUI test renderer and mock terminal input.

import gleam/javascript/promise.{type Promise}
import gleam_opentui.{type Renderer}

pub type TestRendererSetup

pub type MockInput

pub type MockMouse

@external(javascript, "../opentui_testing.ffi.mjs", "mouse")
pub fn mouse(setup: TestRendererSetup) -> MockMouse

@external(javascript, "../opentui_testing.ffi.mjs", "click")
pub fn click(mouse: MockMouse, x: Int, y: Int) -> Promise(Result(Nil, String))

@external(javascript, "../opentui_testing.ffi.mjs", "create")
pub fn create(
  options_json: String,
) -> Promise(Result(TestRendererSetup, String))

@external(javascript, "../opentui_testing.ffi.mjs", "renderer")
pub fn renderer(setup: TestRendererSetup) -> Renderer

@external(javascript, "../opentui_testing.ffi.mjs", "input")
pub fn input(setup: TestRendererSetup) -> MockInput

@external(javascript, "../opentui_testing.ffi.mjs", "renderOnce")
pub fn render_once(setup: TestRendererSetup) -> Promise(Result(Nil, String))

@external(javascript, "../opentui_testing.ffi.mjs", "capture")
pub fn capture(setup: TestRendererSetup) -> String

@external(javascript, "../opentui_testing.ffi.mjs", "resize")
pub fn resize(
  setup: TestRendererSetup,
  width: Int,
  height: Int,
) -> Result(Nil, String)

@external(javascript, "../opentui_testing.ffi.mjs", "typeText")
pub fn type_text(input: MockInput, text: String) -> Promise(Result(Nil, String))

@external(javascript, "../opentui_testing.ffi.mjs", "pressKey")
pub fn press_key(
  input: MockInput,
  key: String,
  ctrl: Bool,
  shift: Bool,
  meta: Bool,
) -> Result(Nil, String)

@external(javascript, "../opentui_testing.ffi.mjs", "paste")
pub fn paste(input: MockInput, text: String) -> Promise(Result(Nil, String))
