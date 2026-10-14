import ash_eyg/actions
import ash_eyg/native_test as n
import ash_eyg/tools
import ash_eyg/type_ as t
import embedding_fixture as f
import eyg/analysis/type_/isomorphic as iso
import eyg/embedding/runtime
import eyg/hub/cache
import eyg/interpreter/value as v
import gleam/dict
import gleam/erlang/process
import gleam/list
import gleam/string
import gleeunit/should

fn check(source, effects) {
  n.check(source, cache.empty(), effects).0
}

fn run(source, effects, actor) {
  n.run(source, cache.empty(), effects, actor).0
}

fn rendered(source, effects) {
  run(source, effects, n.admin()) |> should.be_ok |> runtime.inspect
}

pub fn discovery_and_types() {
  n.effects()
  |> list.map(n.label)
  |> list.sort(string.compare)
  |> should.equal(list.sort(
    [
      "SupportTicketRead",
      "SupportTicketDestroy",
      "SupportTicketOpen",
      "SupportTicketClose",
      "SupportTicketByStatus",
      "SupportTicketCount",
      "SupportTicketScope",
    ],
    string.compare,
  ))
  n.named() |> list.map(n.label) |> should.equal(["DeskItemRead"])
  let type_ =
    check(
      "perform SupportTicketOpen({subject: \"Hi\", priority: Some(1)})",
      n.effects(),
    )
    |> should.be_ok
  type_
  |> string.contains("priority: [Some: Integer | None: {}]")
  |> should.be_true
  type_ |> string.contains("status: [Open: {} | Closed: {}]") |> should.be_true
  check(
    "perform SupportTicketOpen({subject: 1, priority: None({})})",
    n.effects(),
  )
  |> should.be_error
  |> string.contains("type mismatch given: Integer expected: String")
  |> should.be_true
  check(
    "match perform SupportTicketRead({}) { Ok(tickets) -> { !list_fold(tickets, \"\", (ticket, _) -> { ticket.secret }) } Error(reason) -> { reason } }",
    n.effects(),
  )
  |> should.be_error
  |> string.contains("missing row 'secret'")
  |> should.be_true
}

pub fn crud_and_generic() {
  let value =
    run(
      "perform SupportTicketOpen({subject: \"Printer on fire\", priority: None({})})",
      n.effects(),
      n.admin(),
    )
    |> should.be_ok
  let assert v.Tagged("Ok", v.Record(fields)) = value
  let assert Ok(v.String(id)) = dict.get(fields, "id")
  rendered("perform SupportTicketCount({})", n.effects())
  |> should.equal("Ok(1)")
  rendered("perform SupportTicketClose({id: \"" <> id <> "\"})", n.effects())
  |> string.contains("status: Closed({})")
  |> should.be_true
  rendered("perform SupportTicketByStatus({status: Open({})})", n.effects())
  |> should.equal("Ok([])")
  rendered("perform SupportTicketDestroy({id: \"" <> id <> "\"})", n.effects())
  |> should.equal("Ok({})")
  rendered("perform SupportTicketRead({})", n.effects())
  |> should.equal("Ok([])")
}

pub fn host_scope() {
  rendered("perform SupportTicketScope({})", n.effects())
  |> should.equal("Ok(\"admin:tenant-a:context-a\")")
  run("perform SupportTicketRead({})", n.effects(), n.no_actor())
  |> should.be_ok
  |> runtime.inspect
  |> should.equal("Error(\"forbidden\")")
  n.generic("perform SupportTicketScope({})", n.admin())
  |> should.be_ok
  |> should.equal("Ok(\"admin:tenant-a:context-a\")")
  n.generic("perform SupportTicketRead({})", n.no_actor())
  |> should.be_ok
  |> should.equal("Error(\"forbidden\")")
}

pub fn restricted_effects() {
  let read_only =
    n.effects() |> list.filter(fn(effect) { n.action(effect) == "read" })
  check(
    "perform SupportTicketOpen({subject: \"Hi\", priority: None({})})",
    read_only,
  )
  |> should.be_error
  |> string.contains("missing row 'SupportTicketOpen'")
  |> should.be_true
  run(
    "let _ = perform SupportTicketOpen({subject: \"never\", priority: None({})}) perform SupportTicketClose({id: 1})",
    n.effects(),
    n.admin(),
  )
  |> should.be_error
  rendered("perform SupportTicketRead({})", n.effects())
  |> should.equal("Ok([])")
}

pub fn host_effects() {
  let observed = process.new_subject()
  let log =
    actions.Effect("Log", iso.String, t.unit(), fn(lift, _) {
      process.send(observed, lift)
      v.Record(dict.new())
    })
    |> n.host_effect
  run("perform Log(\"hello\")", [log, ..n.effects()], n.admin()) |> should.be_ok
  process.receive(observed, 1000) |> should.equal(Ok(v.String("hello")))
}

pub fn packages_and_sessions() {
  let #(loader, requests) = f.standard(f.tree("42"), [], f.Normal)
  n.fixture(loader.fetch)
  let #(checked, loaded) = n.check("@standard", cache.empty(), n.effects())
  checked |> should.equal(Ok("Integer"))
  f.requests(requests) |> list.length |> should.equal(4)
  n.run("@standard", loaded, n.effects(), n.admin())
  |> should.equal(#(Ok(v.Integer(42)), loaded))
  f.requests(requests) |> should.equal([])
  let #(failed, returned) = n.check("@missing", loaded, n.effects())
  should.be_error(failed)
  returned |> should.equal(loaded)
  f.requests(requests) |> should.not_equal([])
  let owner = n.session() |> should.be_ok
  let independent = n.session() |> should.be_ok
  n.check_session(owner, "@standard", n.effects())
  |> should.equal(Ok("Integer"))
  f.requests(requests) |> list.length |> should.equal(4)
  n.run_session(owner, "@standard", n.effects())
  |> should.equal(Ok(v.Integer(42)))
  f.requests(requests) |> should.equal([])
  n.check_session(independent, "@standard", n.effects()) |> should.be_ok
  f.requests(requests) |> list.length |> should.equal(4)
  n.stop(owner)
  n.stop(independent)
  n.clear_fixture()
  let #(loader, requests) = f.standard(f.tree("42"), [], f.NetworkFailure)
  n.fixture(loader.fetch)
  n.check("!int_add(1, 2)", cache.empty(), n.effects())
  |> should.equal(#(Ok("Integer"), cache.empty()))
  f.requests(requests) |> should.equal([])
  n.clear_fixture()
}

pub fn generic_action_bridge() {
  let #(loader, requests) = f.standard(f.tree("42"), [], f.Normal)
  n.fixture(loader.fetch)
  n.generic("@standard", n.admin()) |> should.equal(Ok("42"))
  f.requests(requests) |> list.length |> should.equal(4)
  n.generic("@standard", n.admin()) |> should.equal(Ok("42"))
  f.requests(requests) |> should.equal([])
  n.clear_fixture()
  let error =
    n.generic("perform Missing({})", n.admin())
    |> should.be_error
    |> n.invalid_argument
  error.0 |> should.equal("source")
  error.1 |> string.contains("missing row 'Missing'") |> should.be_true
}

pub fn conversion_and_tools() {
  let values = [
    #(t.Integer, n.raw(42)),
    #(t.Boolean, n.raw(True)),
    #(t.Text, n.raw("🌱")),
    #(t.Array(t.Integer), n.raw([1, 2])),
  ]
  list.each(values, fn(item) {
    t.decode(item.0, False, t.encode(item.0, False, item.1))
    |> should.equal(item.1)
  })
  tools.source(["-e", "42"]) |> should.equal(Ok("42"))
  tools.source(["--eval", "42"]) |> should.equal(Ok("42"))
  tools.source(["-e"]) |> should.be_error
  tools.source(["nonexistent-script.eyg"]) |> should.be_error
  t.encode(t.Integer, True, n.raw(n.no_actor()))
  |> should.equal(v.Tagged("None", v.Record(dict.new())))
  t.encode(t.Integer, True, n.raw(42))
  |> should.equal(v.Tagged("Some", v.Integer(42)))
  let assert [effect] = n.named()
  tools.describe(n.effect(effect))
  |> string.contains("DeskItemRead\n  lift:  {}\n  reply: [Ok:")
  |> should.be_true
}
