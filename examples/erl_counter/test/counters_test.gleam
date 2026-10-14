import counters_domain as domain
import counters_scripts as scripts
import embedding_fixture as f
import eyg/embedding/runtime
import eyg/hub/cache
import eyg/interpreter/value as v
import eyg/ir/dag_json
import eyg/ir/tree as ir
import gleam/erlang/process
import gleam/json
import gleam/list
import gleam/string
import gleeunit/should
import native
import simplifile

pub fn checking_and_bad_scripts_never_start_a_counter_test() {
  let #(checked, returned) =
    scripts.check("perform StartCounter(\"checked\")", cache.empty())
  should.be_ok(checked)
  returned |> should.equal(cache.empty())
  domain.value("checked") |> should.equal(Error(domain.NotFound))
  let source = "let _ = perform StartCounter(\"bad\") perform GetValue(3)"
  let #(failed, returned) = scripts.run(source, cache.empty())
  let message = should.be_error(failed)
  message
  |> string.contains("type mismatch given: Integer expected: String")
  |> should.be_true
  message |> string.contains("perform GetValue(3)") |> should.be_true
  returned |> should.equal(cache.empty())
  domain.value("bad") |> should.equal(Error(domain.NotFound))
}

pub fn sequential_host_effects_return_values_test() {
  let source =
    "let _ = perform StartCounter(\"sequence\") let _ = perform SetTickRate({name: \"sequence\", seconds: 1}) perform GetValue(\"sequence\")"
  let #(value, _) = scripts.run(source, cache.empty())
  domain.shutdown("sequence") |> should.be_ok
  value |> should.equal(Ok(v.Tagged("Ok", v.Integer(0))))
}

pub fn domain_errors_remain_eyg_results_test() {
  domain.start("errors") |> should.be_ok
  let #(duplicate, _) =
    scripts.run("perform StartCounter(\"errors\")", cache.empty())
  let #(rate, _) =
    scripts.run(
      "perform SetTickRate({name: \"errors\", seconds: 0})",
      cache.empty(),
    )
  let #(stopped, _) = scripts.run("perform Shutdown(\"errors\")", cache.empty())
  let #(missing, _) = scripts.run("perform GetValue(\"errors\")", cache.empty())
  runtime.inspect(should.be_ok(duplicate))
  |> should.equal("Error(\"counter already started\")")
  runtime.inspect(should.be_ok(rate))
  |> should.equal("Error(\"seconds must be a positive integer\")")
  runtime.inspect(should.be_ok(stopped)) |> should.equal("Ok({})")
  runtime.inspect(should.be_ok(missing))
  |> should.equal("Error(\"counter not found\")")
}

pub fn cancelled_timers_cannot_increment_a_counter_test() {
  domain.start("timer") |> should.be_ok
  let #(pid, old_timer) = native.timer("timer") |> should.be_ok
  domain.rate("timer", 1) |> should.be_ok
  let _ = native.send_timer(pid, native.Timeout(old_timer, native.Tick))
  domain.value("timer") |> should.equal(Ok(0))
  await_tick(150)
  domain.shutdown("timer") |> should.be_ok
}

fn await_tick(attempts) {
  case domain.value("timer"), attempts {
    Ok(value), _ if value >= 1 -> Nil
    _, 0 -> panic as "counter did not tick"
    _, _ -> {
      process.sleep(20)
      await_tick(attempts - 1)
    }
  }
}

pub fn a_session_owns_validated_packages_for_multiple_callers_test() {
  let assert Ok(json) =
    simplifile.read("../../eyg_packages/standard/index.eyg.json")
  let root = json.parse(json, dag_json.decoder(Nil)) |> should.be_ok
  let #(loader, calls) = f.standard(root, [], f.Normal)
  native.fixture(loader.fetch)
  let session = native.session() |> should.be_ok
  let source =
    "@standard.list.map([\"session\"], (name) -> { perform StartCounter(name) })"
  native.cached(session, ir.Package("standard")) |> should.be_false
  let checked = native.check(session, source)
  let loaded = native.cached(session, ir.Package("standard"))
  let requests = f.requests(calls)
  let before = domain.value("session")
  let value = native.run(session, source)
  let reused = f.requests(calls)
  native.stop(session)
  native.clear_fixture()
  domain.shutdown("session") |> should.be_ok
  should.be_ok(checked)
  loaded |> should.be_true
  requests |> list.length |> should.equal(4)
  before |> should.equal(Error(domain.NotFound))
  should.be_ok(value)
  reused |> should.equal([])
}
