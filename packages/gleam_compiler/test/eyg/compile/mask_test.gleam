import eyg/analysis/inference/levels_j/contextual as infer
import eyg/compiler
import eyg/parser
import gleam/dict
import gleam/dynamic
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/string
import gleeunit/should
import plinth/browser/window
import simplifile

pub fn unchecked_masking_and_purity_test() {
  let fixtures =
    simplifile.read("../../spec/masking.json")
    |> should.be_ok
    |> json.parse(
      decode.list({
        use name <- decode.field("name", decode.string)
        use source <- decode.field("source", decode.string)
        use expected <- decode.field("value", decode.int)
        decode.success(#(name, source, expected))
      }),
    )
    |> should.be_ok
  list.each(fixtures, fn(fixture) {
    let #(name, source, expected) = fixture
    let tree = parser.all_from_string(source) |> should.be_ok
    let result =
      compiler.to_js(
        tree,
        dict.new(),
        "() => { throw Error('host effect escaped'); }",
      )
      |> window.eval
    #(name, result) |> should.equal(#(name, Ok(dynamic.int(expected))))
  })
}

pub fn unchecked_masking_and_purity_errors_test() {
  let fixtures =
    simplifile.read("../../spec/masking_errors.json")
    |> should.be_ok
    |> json.parse(
      decode.list({
        use name <- decode.field("name", decode.string)
        use source <- decode.field("source", decode.string)
        use expected <- decode.field("error", decode.string)
        decode.success(#(name, source, expected))
      }),
    )
    |> should.be_ok
  list.each(fixtures, fn(fixture) {
    let #(name, source, expected) = fixture
    let tree = parser.all_from_string(source) |> should.be_ok
    let js =
      compiler.to_js(
        tree,
        dict.new(),
        "() => { throw Error('host effect escaped'); }",
      )
    let wrapped =
      "(() => { try { "
      <> js
      <> "; return 'no error'; } catch (e) { return Object.keys(e.eygBreak || {})[0] || 'host effect escaped'; } })()"
    #(name, window.eval(wrapped))
    |> should.equal(#(name, Ok(dynamic.string(expected))))
  })
}

pub fn masked_testing_api_preserves_native_replies_and_callback_scope_test() {
  let first =
    simplifile.read("../../eyg_packages/aok/first.eyg") |> should.be_ok
  let api =
    simplifile.read("../../eyg_packages/aok/expect.eyg")
    |> should.be_ok
    |> string.replace(
      "import \"./first.eyg\"",
      "(_) -> { " <> first <> " }({})",
    )
  let source = "let expect = (_) -> { " <> api <> " }({})
    let equal = (a, b) -> {
      match !equal(a, b) { True(_) -> { {} } False(_) -> { !never(perform Abort(\"wrong value\")) } }
    }
    handle Abort((_, _) -> { -1 }, (_) -> {
      handle ReadFile((request, resume) -> {
        let _ = equal(request.path, \"callback\")
        resume(Ok(!string_to_binary(\"outside\")))
      }, (_) -> {
        let reply = expect.run((_) -> {
          let _ = perform StandardOut(\"before\")
          let reply = perform ReadFile({path: \"subject\", offset: 0, limit: 100})
          let _ = perform StandardOut(\"after\")
          reply
        }, [
          expect.stdout((text) -> { equal(text, \"before\") }),
          expect.read_file((request) -> {
            let _ = equal(request.path, \"subject\")
            Ok(!string_to_binary(\"hi\"))
          }),
          expect.stdout((text) -> {
            let _ = equal(text, \"after\")
            equal(perform ReadFile({path: \"callback\", offset: 0, limit: 100}), Ok(!string_to_binary(\"outside\")))
          })
        ])
        let _ = equal(reply, Ok(!string_to_binary(\"hi\")))
        42
      })
    })"
  let tree = parser.all_from_string(source) |> should.be_ok
  let assert infer.Done(analysis) = infer.check(infer.pure(), tree)
  infer.all_errors(analysis) |> should.equal([])
  compiler.to_js(
    tree,
    dict.new(),
    "() => { throw Error('unexpected host effect'); }",
  )
  |> window.eval
  |> should.equal(Ok(dynamic.int(42)))
}
