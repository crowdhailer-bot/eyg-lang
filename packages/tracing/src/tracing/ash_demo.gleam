//// Check AshAdmin's real script action and Gleam highlighting against the guide.

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

const origin = "http://127.0.0.1:7816/admin"

const editor = "textarea[name$=\"[source]\"]"

const output = ".max-w-2xl.mx-auto.mt-6 > div"

const standard =
  "@standard:1:baguqeerahlbgfg7wjjdjguypivmsdcvh3e2vs4lhiafdbbtl3duxfuzv2eja"

pub fn main() {
  use _ <- promise.map(record_browser.run("ash-helpdesk", walkthrough))
  io.println(
    "PASS AshAdmin effects, package cache reuse, errors and Gleam highlighting",
  )
}

fn walkthrough(page) {
  browser.on_error(page, io.print_error)
  browser.on_console(page, io.println)
  use opened <- promise.await(browser.goto(
    page,
    origin <> "?domain=Scripting&resource=Script&action=run&action_type=action",
  ))
  let assert Ok(_) = opened
  let input = browser.locator(page, editor)
  let unicode = "let leaf = \"🌱緑\""
  use done <- promise.await(browser.fill(input, unicode))
  let assert Ok(_) = done
  use done <- promise.await(browser.contains(
    browser.locator(page, ".eyg-overlay"),
    unicode,
  ))
  let assert Ok(_) = done
  let long = list.repeat("let x = 1", 25) |> string.join("\n")
  use done <- promise.await(browser.fill(input, long))
  let assert Ok(_) = done
  use done <- promise.await(browser.press(input, "Control+End"))
  let assert Ok(_) = done
  use _ <- promise.await(timers.sleep(200))
  use scrolled <- promise.await(browser.numeric_property(input, "scrollTop"))
  let assert Ok(scrolled) = scrolled
  use mirrored <- promise.await(browser.numeric_property(
    browser.locator(page, ".eyg-overlay"),
    "scrollTop",
  ))
  let assert Ok(mirrored) = mirrored
  assert scrolled >. 0.0 && scrolled == mirrored
  let create =
    standard
    <> ".list.map([\"Printer on fire\", \"Mouse will not click\", \"Coffee machine is empty\"], (subject) -> { perform SupportTicketOpen({subject: subject}) })"
  use done <- promise.await(browser.fill(input, create))
  let assert Ok(_) = done
  use done <- promise.await(browser.contains(
    browser.locator(page, ".eyg-overlay"),
    "Coffee machine",
  ))
  let assert Ok(_) = done
  use before <- promise.await(request_count())
  assert before == 0
  use _ <- promise.await(timers.sleep(1500))
  use done <- promise.await(
    browser.click(browser.locator(page, "form button[type=submit]")),
  )
  let assert Ok(_) = done
  use done <- promise.await(browser.contains(
    browser.locator(page, output),
    "Printer on fire",
  ))
  let assert Ok(_) = done
  use done <- promise.await(browser.contains(
    browser.locator(page, output),
    "Coffee machine is empty",
  ))
  let assert Ok(_) = done
  use loaded <- promise.await(request_count())
  assert loaded == 3
  use done <- promise.await(browser.count(
    browser.locator(page, output <> " .eyg-token:has-text('Ok')"),
    3,
  ))
  let assert Ok(_) = done
  use _ <- promise.await(timers.sleep(2500))
  use done <- promise.await(browser.fill(
    input,
    standard <> ".list.map([1, 2], (x) -> { !int_add(x, 1) })",
  ))
  let assert Ok(_) = done
  use done <- promise.await(
    browser.click(browser.locator(page, "form button[type=submit]")),
  )
  let assert Ok(_) = done
  use done <- promise.await(browser.contains(
    browser.locator(page, output),
    "[2, 3]",
  ))
  let assert Ok(_) = done
  use repeated <- promise.await(request_count())
  assert repeated == loaded
  use _ <- promise.await(timers.sleep(1200))
  use done <- promise.await(browser.fill(
    input,
    "let _ = perform SupportTicketOpen({subject: \"never created\"}) perform SupportTicketClose({id: 1})",
  ))
  let assert Ok(_) = done
  use done <- promise.await(
    browser.click(browser.locator(page, "form button[type=submit]")),
  )
  let assert Ok(_) = done
  use done <- promise.await(browser.contains(
    browser.locator(page, editor <> " ~ p"),
    "type mismatch given: Integer expected: String",
  ))
  let assert Ok(_) = done
  use _ <- promise.await(timers.sleep(2500))
  use done <- promise.await(browser.goto(
    page,
    origin <> "?domain=Support&resource=Ticket&action=read&action_type=read",
  ))
  let assert Ok(_) = done
  use done <- promise.await(browser.contains(
    browser.locator(page, "table"),
    "Printer on fire",
  ))
  let assert Ok(_) = done
  use done <- promise.await(browser.contains(
    browser.locator(page, "table"),
    "Coffee machine is empty",
  ))
  let assert Ok(_) = done
  use done <- promise.await(browser.count(
    browser.locator(page, "table tbody tr"),
    3,
  ))
  let assert Ok(_) = done
  use done <- promise.await(browser.count(
    browser.locator(page, ".eyg-overlay"),
    0,
  ))
  let assert Ok(_) = done
  use _ <- promise.map(timers.sleep(2200))
  Nil
}

fn request_count() {
  let assert Ok(request) = request.to("http://127.0.0.1:7207/stats")
  use response <- promise.map(
    system.run(system.fetch(request.set_body(request, <<>>))),
  )
  let assert Ok(response) = response
  let assert Ok(count) =
    json.parse_bits(
      response.body,
      decode.field("requests", decode.int, decode.success),
    )
  count
}
