import eyg/compiler/support
import gleam/list
import gleam/string
import touch_grass/decode_json

pub fn decode_json_matches_touch_grass_test() {
  let cases = [
    <<"{\"a\": [1, 2.5e-3, true, null, \"x\\u00e9\\ud83d\\ude00\"]}">>,
    <<"[]">>,
    <<"-0">>,
    <<"0.5">>,
    <<"-12E+3">>,
    <<"  42  trailing">>,
    <<"[1,]">>,
    <<"{\"a\" 1}">>,
    <<"\"bad \\x\"">>,
    <<"">>,
    <<"[1, 2">>,
    <<"\"\\ud800\"">>,
    <<34, 255, 34>>,
    <<"{\"nested\": {\"deep\": [[], {}]}}">>,
  ]
  let failures =
    list.filter_map(cases, fn(raw) {
      let expected = support.canonical(decode_json.sync(raw))
      let got = decode(raw)
      case got == expected {
        True -> Error(Nil)
        False ->
          Ok(string.inspect(raw) <> " expected " <> expected <> " got " <> got)
      }
    })
  assert [] == failures as string.join(failures, "\n")
}

@external(javascript, "./browser_ffi.mjs", "decode_json")
fn decode(raw: BitArray) -> String
