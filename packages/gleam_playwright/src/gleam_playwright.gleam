//// Playwright library bindings. Test, fixture and recording logic belongs in Gleam.

import gleam/javascript/promise.{type Promise}

pub type Browser

pub type Context

pub type Page

pub type Locator

pub type Download

pub type Video

@external(javascript, "./playwright_ffi.mjs", "launch")
pub fn launch(
  executable: String,
  slow_motion: Int,
) -> Promise(Result(Browser, String))

@external(javascript, "./playwright_ffi.mjs", "context")
pub fn context(
  browser: Browser,
  video_directory: String,
  width: Int,
  height: Int,
) -> Promise(Result(Context, String))

@external(javascript, "./playwright_ffi.mjs", "page")
pub fn page(context: Context) -> Promise(Result(Page, String))

@external(javascript, "./playwright_ffi.mjs", "goto")
pub fn goto(page: Page, url: String) -> Promise(Result(Nil, String))

@external(javascript, "./playwright_ffi.mjs", "locator")
pub fn locator(page: Page, selector: String) -> Locator

@external(javascript, "./playwright_ffi.mjs", "fill")
pub fn fill(locator: Locator, value: String) -> Promise(Result(Nil, String))

@external(javascript, "./playwright_ffi.mjs", "selectOption")
pub fn select_option(locator: Locator, value: String) -> Promise(Result(Nil, String))

@external(javascript, "./playwright_ffi.mjs", "onError")
pub fn on_error(page: Page, handler: fn(String) -> Nil) -> Nil

@external(javascript, "./playwright_ffi.mjs", "content")
pub fn content(page: Page) -> Promise(String)

@external(javascript, "./playwright_ffi.mjs", "onConsole")
pub fn on_console(page: Page, handler: fn(String) -> Nil) -> Nil

@external(javascript, "./playwright_ffi.mjs", "press")
pub fn press(locator: Locator, key: String) -> Promise(Result(Nil, String))

@external(javascript, "./playwright_ffi.mjs", "click")
pub fn click(locator: Locator) -> Promise(Result(Nil, String))

@external(javascript, "./playwright_ffi.mjs", "contains")
pub fn contains(locator: Locator, text: String) -> Promise(Result(Nil, String))

@external(javascript, "./playwright_ffi.mjs", "download")
pub fn download(page: Page) -> Promise(Result(Download, String))

@external(javascript, "./playwright_ffi.mjs", "saveDownload")
pub fn save_download(
  download: Download,
  path: String,
) -> Promise(Result(Nil, String))

@external(javascript, "./playwright_ffi.mjs", "setInputFiles")
pub fn set_input_files(
  locator: Locator,
  path: String,
) -> Promise(Result(Nil, String))

@external(javascript, "./playwright_ffi.mjs", "video")
pub fn video(page: Page) -> Video

@external(javascript, "./playwright_ffi.mjs", "saveVideo")
pub fn save_video(video: Video, path: String) -> Promise(Result(Nil, String))

@external(javascript, "./playwright_ffi.mjs", "screenshot")
pub fn screenshot(page: Page, path: String) -> Promise(Result(Nil, String))

@external(javascript, "./playwright_ffi.mjs", "closeContext")
pub fn close_context(context: Context) -> Promise(Result(Nil, String))

@external(javascript, "./playwright_ffi.mjs", "closeBrowser")
pub fn close_browser(browser: Browser) -> Promise(Result(Nil, String))
