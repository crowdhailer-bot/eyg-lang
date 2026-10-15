//// Check and record the compiled Gleam viewer entirely offline.

import gleam/io
import gleam/javascript/promise
import gleam/list
import gleam_playwright as browser
import javascript/mutable_reference as reference
import plinthx/node/timers
import simplifile
import tracing/model
import tracing/record_browser
import tracing/storage

fn checked(work, next) {
  use reply <- promise.await(work)
  let assert Ok(value) = reply
  next(value)
}

pub fn main() {
  let assert Ok(cwd) = simplifile.current_directory()
  let assert Ok(profiles) =
    storage.read("presentation/profiles.json", "profiles")
  let assert [profile, ..] = profiles
  let wall = model.layout(profile, False, False)
  let active = model.layout(profile, True, False)
  let intrinsics = model.layout(profile, True, True)
  record_browser.run("trace-performance", fn(page) {
    let errors = reference.new([])
    let requests = reference.new([])
    browser.on_error(page, fn(error) {
      let _ = reference.set(errors, [error, ..reference.get(errors)])
      Nil
    })
    browser.on_request(page, fn(url) {
      let _ = reference.set(requests, [url, ..reference.get(requests)])
      Nil
    })
    use _ <- checked(browser.goto(
      page,
      "file://" <> cwd <> "/presentation/profile.html",
    ))
    use _ <- checked(browser.count(
      browser.locator(page, "#chart .frame"),
      list.length(wall.frames),
    ))
    use _ <- checked(browser.contains(
      browser.locator(page, "#stats"),
      "Elapsed:",
    ))
    use _ <- checked(browser.select_option(
      browser.locator(page, "#clock"),
      "active",
    ))
    use _ <- checked(browser.count(
      browser.locator(page, "#chart .frame"),
      list.length(active.frames),
    ))
    use _ <- checked(browser.contains(
      browser.locator(page, "#chart"),
      "outside host effects",
    ))
    use _ <- checked(browser.click(browser.locator(page, "#intrinsics")))
    use _ <- checked(browser.count(
      browser.locator(page, "#chart .frame"),
      list.length(intrinsics.frames),
    ))
    use _ <- checked(
      browser.click(browser.locator(page, "#chart .frame:nth-of-type(3)")),
    )
    use _ <- checked(browser.contains(
      browser.locator(page, "#detail"),
      "Span ID",
    ))
    let assert Ok(frame) =
      list.find(intrinsics.frames, fn(f) { f.span.name == "prepare" })
    let focused =
      model.layout(profile, True, True).frames
      |> list.filter(fn(f) { f.start >= frame.start && f.end <= frame.end })
    use _ <- checked(
      browser.double_click(browser.locator(
        page,
        "#chart [data-frame='" <> frame.span.span_id <> "']",
      )),
    )
    use _ <- checked(browser.count(
      browser.locator(page, "#chart .frame"),
      list.length(focused),
    ))
    use _ <- checked(browser.click(browser.locator(page, "#reset")))
    use _ <- checked(browser.count(
      browser.locator(page, "#chart .frame"),
      list.length(intrinsics.frames),
    ))
    use _ <- checked(browser.press(browser.locator(page, "#zoom"), "ArrowRight"))
    use _ <- checked(browser.has_attribute(
      browser.locator(page, "#chart svg"),
      "width",
      "2800",
    ))
    use _ <- checked(browser.click(browser.locator(page, "[data-sort='name']")))
    use _ <- checked(browser.contains(
      browser.locator(page, "#rows tbody tr:first-child td:first-child"),
      "!binary_size",
    ))
    use _ <- checked(browser.select_option(
      browser.locator(page, "#recording"),
      "1",
    ))
    use _ <- checked(browser.contains(
      browser.locator(page, "#chart"),
      "120 ms Sleep",
    ))
    use _ <- checked(browser.select_option(
      browser.locator(page, "#clock"),
      "wall",
    ))
    use _ <- checked(browser.press(
      browser.locator(page, "body"),
      "Control+Home",
    ))
    use _ <- promise.map(timers.sleep(1400))
    assert reference.get(errors) == []
    assert list.all(reference.get(requests), fn(url) {
      url == "file://" <> cwd <> "/presentation/profile.html"
    })
    io.println(
      "PASS offline performance viewer: clocks, intrinsics, frames, focus, reset, zoom, sorting and recordings",
    )
  })
}
