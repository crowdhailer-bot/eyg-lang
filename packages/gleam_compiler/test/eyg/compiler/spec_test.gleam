import dag_json
import eyg/compiler/support
import eyg/interpreter/value as v
import eyg/ir/dag_json as codec
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/string
import simplifile

pub fn evaluation_suite_test() {
  let fixtures =
    ["core_suite.json", "builtins_suite.json", "effects_suite.json"]
    |> list.flat_map(fn(file) {
      let assert Ok(bits) =
        simplifile.read_bits("../../spec/evaluation/" <> file)
      let assert Ok(fixtures) = json.parse_bits(bits, suite_decoder())
      fixtures
    })

  let failures =
    list.flat_map(support.configs(), fn(config) {
      list.filter_map(fixtures, fn(fixture) {
        let #(name, source, effects, expected) = fixture
        case support.run(source, config, effects), expected {
          Ok(got), Ok(value) ->
            case got == support.canonical(value) {
              True -> Error(Nil)
              False -> Ok(config.name <> " " <> name <> " returned " <> got)
            }
          Error(_), Error(Nil) -> Error(Nil)
          Error(reason), Ok(_) ->
            Ok(config.name <> " " <> name <> " failed " <> reason)
          Ok(got), Error(Nil) ->
            Ok(config.name <> " " <> name <> " should break, returned " <> got)
        }
      })
    })
  assert [] == failures as string.join(failures, "\n")
}

fn value_decoder() {
  use <- decode.recursive
  decode.one_of(
    {
      use bytes <- decode.field("binary", dag_json.decode_bytes())
      decode.success(v.Binary(bytes))
    },
    [
      {
        use integer <- decode.field("integer", decode.int)
        decode.success(v.Integer(integer))
      },
      {
        use string <- decode.field("string", decode.string)
        decode.success(v.String(string))
      },
      {
        use items <- decode.field("list", decode.list(value_decoder()))
        decode.success(v.LinkedList(items))
      },
      {
        use items <- decode.field(
          "record",
          decode.dict(decode.string, value_decoder()),
        )
        decode.success(v.Record(items))
      },
      {
        use label <- decode.subfield(["tagged", "label"], decode.string)
        use value <- decode.subfield(
          ["tagged", "value"],
          tagged_value_decoder(),
        )
        decode.success(v.Tagged(label, value))
      },
    ],
  )
}

// A recursive call to value_decoder overflows the stack, as noted in the
// interpreter tests, so tagged values are decoded one level deep.
fn tagged_value_decoder() {
  decode.one_of(
    {
      use integer <- decode.field("integer", decode.int)
      decode.success(v.Integer(integer))
    },
    [
      {
        use items <- decode.field(
          "record",
          decode.dict(decode.string, value_decoder()),
        )
        decode.success(v.Record(items))
      },
      {
        use string <- decode.field("string", decode.string)
        decode.success(v.String(string))
      },
      {
        use items <- decode.field("list", decode.list(value_decoder()))
        decode.success(v.LinkedList(items))
      },
    ],
  )
}

fn effect_decoder() {
  use label <- decode.field("label", decode.string)
  use lift <- decode.field("lift", value_decoder())
  use reply <- decode.field("reply", value_decoder())
  decode.success(#(label, lift, reply))
}

fn suite_decoder() {
  decode.list({
    use name <- decode.field("name", decode.string)
    use source <- decode.field("source", codec.decoder(Nil))
    use effects <- decode.optional_field(
      "effects",
      [],
      decode.list(effect_decoder()),
    )
    use expected <- decode.then(
      decode.one_of(decode.at(["value"], value_decoder()) |> decode.map(Ok), [
        decode.at(["break"], decode.dynamic) |> decode.map(fn(_) { Error(Nil) }),
      ]),
    )
    decode.success(#(name, source, effects, expected))
  })
}
