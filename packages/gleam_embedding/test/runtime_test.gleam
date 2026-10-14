import embedding_fixture as f
import eyg/analysis/type_/isomorphic as t
import eyg/embedding/packages
import eyg/embedding/runtime as r
import eyg/hub/cache
import eyg/interpreter/value as v
import eyg/ir/tree as ir
import gleam/dict
import gleam/erlang/process
import gleam/list
import gleam/string
import gleeunit/should
import multiformats/cid/v1

fn check(source, cache, loader) {
  let done = process.new_subject()
  r.check(source, cache, loader, [])(fn(value) { process.send(done, value) })
  process.receive(done, 3000) |> should.be_ok
}

fn run(source, cache, loader) {
  run_with(source, cache, loader, [], fn(_, _) { Error("no effects") })
}

fn run_with(source, cache, loader, effects, handle) {
  let done = process.new_subject()
  r.run(source, cache, loader, effects, handle)(fn(value) {
    process.send(done, value)
  })
  process.receive(done, 3000) |> should.be_ok
}

pub fn local_and_unparsed_programs_need_no_hub_test() {
  let #(loader, requests) = f.standard(f.tree("42"), [], f.NetworkFailure)
  let loader = packages.Loader(..loader, hub: "invalid origin")
  check("1", cache.empty(), loader)
  |> should.equal(#(Ok("Integer"), cache.empty()))
  run("1", cache.empty(), loader)
  |> should.equal(#(Ok(v.Integer(1)), cache.empty()))
  let #(failed, returned) = run("{broken:", cache.empty(), loader)
  should.be_error(failed)
  returned |> should.equal(cache.empty())
  f.requests(requests) |> should.equal([])
}

pub fn check_loads_and_runs_reuse_the_callers_cache_test() {
  let #(loader, requests) = f.standard(f.tree("42"), [], f.Normal)
  let #(checked, loaded) = check("@standard", cache.empty(), loader)
  checked |> should.equal(Ok("Integer"))
  f.requests(requests) |> list.length |> should.equal(4)
  run("@standard", loaded, loader) |> should.equal(#(Ok(v.Integer(42)), loaded))
  check("@standard", loaded, loader) |> should.equal(#(checked, loaded))
  f.requests(requests) |> should.equal([])
}

pub fn all_reference_forms_fetch_their_immutable_dependencies_test() {
  let child = f.tree("42")
  let root = f.tree(f.content(child))
  let #(loader, _) = f.standard(root, [child, f.tree("0")], f.Normal)
  let pin = "@standard:2:" <> v1.to_string(f.cid(root))
  list.each(["@standard", "@standard:2", pin, f.content(root)], fn(source) {
    let #(value, loaded) = run(source, cache.empty(), loader)
    value |> should.equal(Ok(v.Integer(42)))
    cache.get_reference(loaded, ir.Content(f.cid(root))) |> should.be_ok
  })
  let #(failed, unchanged) =
    run("@standard:2:" <> v1.to_string(f.cid(child)), cache.empty(), loader)
  should.be_error(failed)
  unchanged |> should.equal(cache.empty())
}

pub fn arbitrary_packages_only_fetch_referenced_modules_test() {
  let child = f.tree("11")
  let prices = f.tree(f.content(child))
  let taxes = f.tree("7")
  let unused = f.tree("99")
  let #(loader, requests) =
    f.fixture(
      [
        f.entry("prices", 1, 1, prices),
        f.entry("taxes", 1, 2, taxes),
        f.entry("unused", 1, 3, unused),
      ],
      [prices, child, taxes, unused],
      f.Normal,
    )
  let #(value, loaded) = run("!int_add(@prices, @taxes)", cache.empty(), loader)
  value |> should.equal(Ok(v.Integer(18)))
  let paths = f.requests(requests)
  paths
  |> list.contains("/modules/" <> v1.to_string(f.cid(unused)))
  |> should.be_false
  run("@prices", loaded, loader) |> should.equal(#(Ok(v.Integer(11)), loaded))
  f.requests(requests) |> should.equal([])
}

pub fn failed_batches_retain_the_cache_and_do_not_perform_effects_test() {
  list.each(
    [f.NetworkFailure, f.Corrupt, f.MissingModule, f.MissingPackage],
    fn(mode) {
      let #(loader, _) = f.standard(f.tree("42"), [], mode)
      let calls = process.new_subject()
      let effect = [#("Touch", #(t.Integer, t.Integer))]
      let #(result, returned) =
        run_with(
          "let _ = perform Touch(1) @standard",
          cache.empty(),
          loader,
          effect,
          fn(_, value) {
            process.send(calls, value)
            Ok(value)
          },
        )
      should.be_error(result)
      returned |> should.equal(cache.empty())
      process.receive(calls, 0) |> should.be_error
    },
  )
}

pub fn invalid_closures_and_impure_modules_are_rejected_test() {
  list.each(["(x) -> { !int_add(\"bad\", x) }", "perform Touch(1)"], fn(code) {
    let #(loader, _) = f.standard(f.tree(code), [], f.Normal)
    let #(result, returned) = check("@standard", cache.empty(), loader)
    should.be_error(result)
    returned |> should.equal(cache.empty())
  })
}

pub fn an_invalid_script_keeps_valid_downloads_but_has_no_effects_test() {
  let #(loader, requests) = f.standard(f.tree("42"), [], f.Normal)
  let calls = process.new_subject()
  let #(failed, loaded) =
    run_with(
      "let _ = perform Touch(1) !int_add(@standard, \"bad\")",
      cache.empty(),
      loader,
      [#("Touch", #(t.Integer, t.Integer))],
      fn(_, value) {
        process.send(calls, value)
        Ok(value)
      },
    )
  should.be_error(failed)
  process.receive(calls, 0) |> should.be_error
  f.requests(requests) |> list.length |> should.equal(4)
  run("@standard", loaded, loader) |> should.equal(#(Ok(v.Integer(42)), loaded))
  f.requests(requests) |> should.equal([])
}

pub fn runtime_errors_return_the_same_cache_and_source_diagnostic_test() {
  let #(loader, _) = f.standard(f.tree("42"), [], f.Normal)
  let #(_, loaded) = check("@standard", cache.empty(), loader)
  let inconsistent =
    cache.Cache(
      ..loaded,
      modules: dict.map_values(loaded.modules, fn(_, module) {
        cache.Module(v.String("host supplied the wrong value"), module.type_)
      }),
    )
  let code = "!int_add(@standard, 1)"
  let #(failed, returned) = run(code, inconsistent, loader)
  should.be_error(failed) |> string.contains(code) |> should.be_true
  returned |> should.equal(inconsistent)
  run("1", returned, loader) |> should.equal(#(Ok(v.Integer(1)), returned))
}

pub fn separate_callers_own_separate_caches_test() {
  let #(loader, requests) = f.standard(f.tree("42"), [], f.Normal)
  let #(_, first) = check("@standard", cache.empty(), loader)
  let #(_, second) = run("@standard", cache.empty(), loader)
  first |> should.equal(second)
  f.requests(requests) |> list.length |> should.equal(8)
}

pub fn a_failed_later_batch_preserves_the_valid_existing_cache_test() {
  let #(loader, _) = f.standard(f.tree("42"), [], f.Normal)
  let #(_, loaded) = check("@standard", cache.empty(), loader)
  let #(failed, returned) = run("@missing", loaded, loader)
  should.be_error(failed)
  returned |> should.equal(loaded)
  run("@standard", returned, loader)
  |> should.equal(#(Ok(v.Integer(42)), loaded))
}

pub fn effects_resume_with_typed_replies_and_host_errors_test() {
  let #(loader, _) = f.standard(f.tree("42"), [], f.Normal)
  let source = "!int_add(perform Touch(20), 2)"
  let signatures = [#("Touch", #(t.Integer, t.Integer))]
  let #(value, _) =
    run_with(source, cache.empty(), loader, signatures, fn(label, lift) {
      label |> should.equal("Touch")
      Ok(lift)
    })
  value |> should.equal(Ok(v.Integer(22)))
  let #(failed, returned) =
    run_with(source, cache.empty(), loader, signatures, fn(_, _) {
      Error("host rejected the operation")
    })
  failed |> should.equal(Error("host rejected the operation"))
  returned |> should.equal(cache.empty())
}
