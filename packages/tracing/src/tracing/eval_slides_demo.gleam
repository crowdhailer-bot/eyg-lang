//// Check the offline talk controls and export its printable 38-slide copy.

import gleam/io
import gleam/javascript/promise
import gleam/string
import gleam_playwright as browser
import javascript/mutable_reference as reference
import plinthx/node/timers
import simplifile
import tracing/record_browser

fn checked(work, next) {
  use reply <- promise.await(work)
  let assert Ok(value) = reply
  next(value)
}

pub fn main() {
  let assert Ok(cwd) = simplifile.current_directory()
  let url = "file://" <> cwd <> "/../../blog/effect-evals/slides.html"
  record_browser.run("effect-evals", fn(page) {
    let errors = reference.new([])
    browser.on_error(page, fn(error) {
      let _ = reference.set(errors, [error, ..reference.get(errors)])
      io.print_error(error)
    })
    use _ <- checked(browser.goto(page, url))
    use _ <- checked(browser.count(browser.locator(page, ".slide"), 38))
    use _ <- checked(browser.contains(
      browser.locator(page, "#counter"),
      "1 / 38",
    ))
    use _ <- checked(browser.press(browser.locator(page, "body"), "ArrowRight"))
    use _ <- checked(browser.contains(
      browser.locator(page, "#counter"),
      "2 / 38",
    ))
    use _ <- checked(browser.press(browser.locator(page, "body"), "n"))
    use _ <- checked(browser.count(browser.locator(page, "body.show-notes"), 1))
    use _ <- checked(browser.contains(
      browser.locator(page, "#notes-panel h3"),
      "2.",
    ))
    use _ <- checked(browser.press(browser.locator(page, "body"), "n"))
    use _ <- checked(browser.press(browser.locator(page, "body"), "End"))
    use _ <- checked(browser.contains(
      browser.locator(page, "#counter"),
      "38 / 38",
    ))
    use _ <- checked(browser.press(browser.locator(page, "body"), "Home"))
    use _ <- checked(browser.contains(
      browser.locator(page, "#counter"),
      "1 / 38",
    ))
    use _ <- checked(browser.select_option(browser.locator(page, "#jump"), "23"))
    use _ <- checked(browser.count(
      browser.locator(page, "#reliability.active"),
      1,
    ))
    use _ <- checked(browser.press(
      browser.locator(page, "#attempts"),
      "ArrowRight",
    ))
    use _ <- checked(browser.has_attribute(
      browser.locator(page, "#reliability"),
      "aria-hidden",
      "false",
    ))
    use _ <- checked(browser.contains(
      browser.locator(page, "#all-result"),
      "41.0%",
    ))
    use _ <- checked(browser.press(browser.locator(page, "body"), "f"))
    use _ <- checked(browser.count(browser.locator(page, ":fullscreen"), 1))
    use _ <- checked(browser.press(browser.locator(page, "body"), "f"))
    use _ <- checked(browser.count(browser.locator(page, ":fullscreen"), 0))
    use _ <- checked(browser.viewport(page, 900, 600))
    use style <- promise.await(stage_scaled(page, "scale(0.684375)", 40))
    assert string.contains(style, "scale(0.684375)") as style
    use _ <- checked(browser.viewport(page, 1280, 800))
    use _ <- checked(browser.pdf(
      page,
      "../../blog/effect-evals/slides.pdf",
      "{\"printBackground\":true,\"preferCSSPageSize\":true}",
    ))
    use _ <- checked(browser.count(
      browser.locator(page, ".slide[aria-hidden='false']"),
      1,
    ))
    use _ <- promise.map(timers.sleep(1500))
    assert reference.get(errors) == []
    io.println(
      "PASS offline eval slides: navigation, notes, probability controls, fullscreen, resize and PDF",
    )
  })
}

/// The stage rescales on the resize event that follows a viewport change.
fn stage_scaled(page, scale, attempts) {
  use style <- checked(browser.attribute(
    browser.locator(page, "#stage"),
    "style",
  ))
  case string.contains(style, scale) || attempts == 0 {
    True -> promise.resolve(style)
    False -> {
      use _ <- promise.await(timers.sleep(50))
      stage_scaled(page, scale, attempts - 1)
    }
  }
}
