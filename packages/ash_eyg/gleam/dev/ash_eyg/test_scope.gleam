import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/result

pub fn describe(actor: Dynamic, tenant: Dynamic, context: Dynamic) {
  let actor =
    decode.run(field(actor, "id"), decode.string) |> result.unwrap("anonymous")
  let tenant = decode.run(tenant, decode.string) |> result.unwrap("no-tenant")
  let context =
    decode.run(field(context, "marker"), decode.string)
    |> result.unwrap("no-context")
  actor <> ":" <> tenant <> ":" <> context
}

@external(erlang, "Elixir.AshEyg.Test.Native", "context_field")
fn field(value: Dynamic, key: String) -> Dynamic
