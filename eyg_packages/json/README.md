# json

Reading and writing JSON.

The module has two fields, so one line brings in everything:

```eyg
let {encode, decode} = @json
```

Reading is `decode`, writing is `encode`. Nothing else is exported.

## Decoding

```eyg
let {decode} = @json

match decode.parse("{\"name\":\"Ada\"}", decode.object(
  decode.field("name", decode.string)
)) {
  Ok(name) -> { name }
  Error(reason) -> { reason }
}
```

| Decoder                       | Decodes to                                    |
|-------------------------------|-----------------------------------------------|
| `decode.boolean`              | `True({}) \| False({})`                       |
| `decode.integer`              | `Int`                                         |
| `decode.string`               | `String`                                      |
| `decode.list(item_decoder)`   | `List(a)`                                     |
| `decode.field(label, dec)`    | the field's decoded value (aborts if missing) |
| `decode.object(decoder_fn)`   | wraps a fields-record builder                 |

| Runner                          | Does                                      |
|---------------------------------|-------------------------------------------|
| `decode.parse(json, decoder)`   | `Ok(value) \| Error(reason)` from a String |
| `decode.parse_bytes(bin, dec)`  | the same for `Binary` input                |
| `decode.expect(result, message)`| the value, or aborts with `message`        |

Decoding performs the `DecodeJSON` effect, which every EYG runtime provides.

## Encoding

```eyg
let {encode} = @json

encode.object([
  encode.field("name", encode.string("Ada")),
  encode.field("age", encode.integer(36)),
])
// -> "{\"name\":\"Ada\",\"age\":36}"
```

| Encoder                 | Produces                            |
|-------------------------|-------------------------------------|
| `encode.string(s)`      | `"\"<escaped>\""`                   |
| `encode.integer(n)`     | `"<n>"`                             |
| `encode.boolean(b)`     | `"true"` / `"false"`                |
| `encode.null(_)`        | `"null"`                            |
| `encode.array(items)`   | `"[a,b,...]"` over encoded strings  |
| `encode.object(fields)` | `"{\"k\":v,...}"`                   |
| `encode.field(k, v)`    | `{key, value}` helper for `object`  |

Every encoder returns a `String` of valid JSON and performs no effects, so the
result can be built anywhere, including in a test.

## Tests

`test.eyg` covers each decoder, each encoder, the escaping rules, and that what
`encode` writes `decode` reads back. Run them with the rest of the repository:

```sh
eyg script entry.eyg
```
