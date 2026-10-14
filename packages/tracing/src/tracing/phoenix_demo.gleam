//// Check the live Phoenix editor, effects, package reuse and Gleam hook behavior.

import gleam/dynamic/decode
import gleam/http/request
import gleam/io
import gleam/javascript/promise
import gleam/json
import gleam/list
import gleam/string
import gleam_playwright as browser
import loam/system
import plinthx/node/timers
import tracing/record_browser

const origin = "http://127.0.0.1:7815"

// Full pin printed by package_fixture for the checked repository standard IR.
const standard =
  "@standard:1:baguqeerahlbgfg7wjjdjguypivmsdcvh3e2vs4lhiafdbbtl3duxfuzv2eja"

pub fn main() {
  use _ <- promise.map(record_browser.run("phoenix-counters", walkthrough))
  io.println(
    "PASS Phoenix LiveView, highlighting, keys, counter effects and package cache reuse",
  )
}

fn walkthrough(page) {
  browser.on_error(page, io.print_error)
  browser.on_console(page, io.println)
  use opened <- promise.await(browser.goto(page, origin))
  let assert Ok(_) = opened
  let input = browser.locator(page, "#script-box textarea")
  let unicode = "let leaf = \"🌱緑\""
  use done <- promise.await(browser.fill(input, unicode))
  let assert Ok(_) = done
  use done <- promise.await(browser.contains(
    browser.locator(page, "#script-box pre"),
    unicode,
  ))
  let assert Ok(_) = done
  let long = list.repeat("let x = 1", 20) |> string.join("\n")
  use done <- promise.await(browser.fill(input, long))
  let assert Ok(_) = done
  use done <- promise.await(browser.press(input, "Control+End"))
  let assert Ok(_) = done
  use _ <- promise.await(timers.sleep(350))
  use scroll <- promise.await(browser.numeric_property(input, "scrollTop"))
  let assert Ok(scroll) = scroll
  use copy_scroll <- promise.await(browser.numeric_property(
    browser.locator(page, "#script-box pre"),
    "scrollTop",
  ))
  let assert Ok(copy_scroll) = copy_scroll
  assert scroll >. 0.0
  assert scroll == copy_scroll
  use done <- promise.await(browser.fill(input, "perform StartCounter("))
  let assert Ok(_) = done
  use _ <- promise.await(timers.sleep(350))
  use done <- promise.await(browser.count(browser.locator(page, "#errors"), 0))
  let assert Ok(_) = done
  use done <- promise.await(browser.fill(input, "perform StartCounter(1)"))
  let assert Ok(_) = done
  use done <- promise.await(browser.contains(
    browser.locator(page, "#errors"),
    "type mismatch given: Integer expected: String",
  ))
  let assert Ok(_) = done
  use done <- promise.await(browser.fill(
    input,
    "let _ = perform StartCounter(\"apples\") perform GetValue(\"apples\")",
  ))
  let assert Ok(_) = done
  use done <- promise.await(browser.contains(
    browser.locator(page, "#type"),
    "[Ok: Integer | Error: String]",
  ))
  let assert Ok(_) = done
  use done <- promise.await(browser.contains(
    browser.locator(page, "#script-box pre"),
    "apples",
  ))
  let assert Ok(_) = done
  use done <- promise.await(browser.press(input, "Shift+Enter"))
  let assert Ok(_) = done
  use draft <- promise.await(browser.input_value(input))
  let assert Ok(draft) = draft
  assert string.contains(draft, "\n")
  use done <- promise.await(browser.count(
    browser.locator(page, "#runs .run"),
    0,
  ))
  let assert Ok(_) = done
  use done <- promise.await(browser.press(input, "Enter"))
  let assert Ok(_) = done
  use done <- promise.await(browser.contains(
    browser.locator(page, "#runs"),
    "Ok(0)",
  ))
  let assert Ok(_) = done
  use _ <- promise.await(timers.sleep(350))
  use cleared <- promise.await(browser.input_value(input))
  let assert Ok(cleared) = cleared
  assert cleared == ""
  use done <- promise.await(browser.contains(
    browser.locator(page, "#counters"),
    "apples",
  ))
  let assert Ok(_) = done
  use done <- promise.await(browser.fill(
    input,
    "perform SetTickRate({name: \"apples\", seconds: 1})",
  ))
  let assert Ok(_) = done
  use done <- promise.await(browser.press(input, "Enter"))
  let assert Ok(_) = done
  use done <- promise.await(browser.contains(
    browser.locator(page, "#counters"),
    "1s",
  ))
  let assert Ok(_) = done
  use _ <- promise.await(timers.sleep(1200))
  use done <- promise.await(browser.fill(
    input,
    standard
      <> ".list.map([\"pears\", \"plums\"], (name) -> { perform StartCounter(name) })",
  ))
  let assert Ok(_) = done
  use done <- promise.await(browser.contains(
    browser.locator(page, "#type"),
    "List",
  ))
  let assert Ok(_) = done
  use before <- promise.await(request_count())
  use done <- promise.await(browser.press(input, "Enter"))
  let assert Ok(_) = done
  use done <- promise.await(browser.contains(
    browser.locator(page, "#runs"),
    "[Ok({}), Ok({})]",
  ))
  let assert Ok(_) = done
  use done <- promise.await(browser.contains(
    browser.locator(page, "#counters"),
    "plums",
  ))
  let assert Ok(_) = done
  use after <- promise.await(request_count())
  assert before == after
  assert before == 3
  use done <- promise.await(browser.fill(
    input,
    "let _ = perform StartCounter(\"never\") perform GetValue(1)",
  ))
  let assert Ok(_) = done
  use done <- promise.await(browser.press(input, "Enter"))
  let assert Ok(_) = done
  use done <- promise.await(browser.contains(
    browser.locator(page, "#errors"),
    "type mismatch",
  ))
  let assert Ok(_) = done
  use done <- promise.await(browser.count(
    browser.locator(page, "#counters td:text-is('never')"),
    0,
  ))
  let assert Ok(_) = done
  use done <- promise.await(
    browser.click(browser.locator(page, "[data-phx-theme='dark']")),
  )
  let assert Ok(_) = done
  use done <- promise.await(browser.has_attribute(
    browser.locator(page, "html"),
    "data-theme",
    "dark",
  ))
  let assert Ok(_) = done
  use done <- promise.await(
    browser.click(browser.locator(page, "[data-phx-theme='light']")),
  )
  let assert Ok(_) = done
  use done <- promise.await(browser.has_attribute(
    browser.locator(page, "html"),
    "data-theme",
    "light",
  ))
  let assert Ok(_) = done
  use _ <- promise.map(timers.sleep(900))
  Nil
}

fn request_count() {
  let assert Ok(request) = request.to("http://127.0.0.1:7207/stats")
  let request = request.set_body(request, <<>>)
  use response <- promise.map(system.run(system.fetch(request)))
  let assert Ok(response) = response
  let assert Ok(count) =
    json.parse_bits(
      response.body,
      decode.field("requests", decode.int, decode.success),
    )
  count
}
