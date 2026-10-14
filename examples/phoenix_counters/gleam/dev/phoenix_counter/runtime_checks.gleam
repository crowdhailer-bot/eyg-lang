import embedding_fixture as f
import eyg/hub/cache
import eyg/interpreter/value as v
import gleam/erlang/process
import gleam/list
import gleam/string
import gleeunit/should
import phoenix_counter/domain
import phoenix_counter/native as n

pub fn loading_and_reuse() {
  let #(loader, requests) = f.standard(f.tree("42"), [], f.Normal)
  n.fixture(loader.fetch)
  let #(checked, loaded) = n.check("@standard", cache.empty())
  let initial = f.requests(requests)
  let reused = n.run("@standard", loaded)
  let repeated = f.requests(requests)
  n.clear_fixture()
  checked |> should.equal(Ok("Integer"))
  initial |> list.length |> should.equal(4)
  reused |> should.equal(#(Ok(v.Integer(42)), loaded))
  repeated |> should.equal([])
}

pub fn no_fetch_and_no_early_effects() {
  let #(loader, requests) = f.standard(f.tree("42"), [], f.NetworkFailure)
  n.fixture(loader.fetch)
  let checked = n.check("!int_add(1, 2)", cache.empty())
  let #(failed, returned) =
    n.run(
      "let _ = perform StartCounter(\"never\") perform GetValue(3)",
      cache.empty(),
    )
  let parse_error = n.run("!int_add(1", cache.empty()).0
  let calls = f.requests(requests)
  n.clear_fixture()
  checked |> should.equal(#(Ok("Integer"), cache.empty()))
  should.be_error(failed)
  |> string.contains("type mismatch given: Integer expected: String")
  |> should.be_true
  should.be_error(parse_error)
  returned |> should.equal(cache.empty())
  domain.value("never") |> should.equal(Error(domain.NotFound))
  calls |> should.equal([])
}

pub fn failed_batch_preserves_cache() {
  let #(loader, _) = f.standard(f.tree("42"), [], f.Normal)
  n.fixture(loader.fetch)
  let #(_, loaded) = n.check("@standard", cache.empty())
  let #(failed, returned) = n.run("@missing", loaded)
  let reused = n.run("@standard", returned)
  n.clear_fixture()
  should.be_error(failed)
  returned |> should.equal(loaded)
  reused |> should.equal(#(Ok(v.Integer(42)), loaded))
}

pub fn scripts_process_owns_cache() {
  let #(loader, requests) = f.standard(f.tree("42"), [], f.Normal)
  n.fixture(loader.fetch)
  let pid = n.scripts() |> should.be_ok
  let checked = n.check_session(pid, "@standard")
  let initial = f.requests(requests)
  let value = n.run_session(pid, "@standard")
  let repeated = f.requests(requests)
  n.stop(pid)
  n.clear_fixture()
  checked |> should.equal(Ok("Integer"))
  initial |> list.length |> should.equal(4)
  value |> should.equal(Ok(v.Integer(42)))
  repeated |> should.equal([])
}

pub fn cancelled_ticks_and_domain_errors() {
  domain.start("ticker") |> should.be_ok
  domain.start("ticker") |> should.equal(Error(domain.AlreadyStarted))
  domain.rate("ticker", 0) |> should.equal(Error(domain.InvalidRate))
  let #(pid, timer) = n.timer("ticker") |> should.be_ok
  domain.rate("ticker", 1) |> should.be_ok
  let _ = n.send_timer(pid, n.Timeout(timer, n.Tick))
  domain.value("ticker") |> should.equal(Ok(0))
  await_tick(150)
  domain.shutdown("ticker") |> should.be_ok
  domain.value("ticker") |> should.equal(Error(domain.NotFound))
}

fn await_tick(attempts) {
  case domain.value("ticker"), attempts {
    Ok(value), _ if value >= 1 -> Nil
    _, 0 -> panic as "Counter did not tick"
    _, _ -> {
      process.sleep(20)
      await_tick(attempts - 1)
    }
  }
}
