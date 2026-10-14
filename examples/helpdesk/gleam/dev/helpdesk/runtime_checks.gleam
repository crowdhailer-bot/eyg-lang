import embedding_fixture as f
import eyg/embedding/runtime
import gleam/list
import gleam/string
import gleeunit/should
import helpdesk/native_test as n
import simplifile

pub fn triage_scope() {
  let assert Ok(source) = simplifile.read("scripts/open.eyg")
  n.triage_check(source)
  |> should.be_error
  |> string.contains("missing row 'SupportTicketOpen'")
  |> should.be_true
}

pub fn triage_assigns() {
  let #(ticket, representative) = n.seed()
  let assert Ok(source) = simplifile.read("scripts/triage.eyg")
  n.triage_run(source)
  |> should.be_ok
  |> runtime.inspect
  |> string.contains("Printer on fire")
  |> should.be_true
  n.assigned(ticket) |> should.equal(representative)
}

pub fn generic_packages() {
  let #(loader, requests) = f.standard(f.tree("42"), [], f.Normal)
  n.fixture(loader.fetch)
  n.script("@standard") |> should.equal(Ok("42"))
  f.requests(requests) |> list.length |> should.equal(4)
  n.script("@standard") |> should.equal(Ok("42"))
  f.requests(requests) |> should.equal([])
  // Reusing the cache does not broaden the effects available to triage.
  n.triage_check(
    "let _ = @standard perform SupportTicketOpen({subject: \"never\"})",
  )
  |> should.be_error
  |> string.contains("missing row 'SupportTicketOpen'")
  |> should.be_true
  f.requests(requests) |> should.equal([])
  n.clear_fixture()
}

pub fn generic_validation() {
  let error =
    n.script("perform SupportTicketClose({subject: \"x\"})")
    |> should.be_error
    |> n.invalid_argument
  error.0 |> should.equal("source")
  error.1 |> string.contains("missing row") |> should.be_true
}
