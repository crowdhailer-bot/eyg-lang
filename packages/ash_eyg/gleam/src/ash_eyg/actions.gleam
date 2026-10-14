import ash_eyg/type_ as t
import eyg/analysis/type_/binding
import eyg/analysis/type_/isomorphic as iso
import eyg/interpreter/value as v
import gleam/dict
import gleam/list
import gleam/result

pub type Resource

pub type Action

pub type Options

pub type Kind {
  Read
  Create
  Update
  Destroy
  Generic
}

pub type Field {
  Field(name: String, key: t.Key, shape: Result(t.Shape, Nil), required: Bool)
}

pub type Descriptor {
  Descriptor(
    label: String,
    resource: Resource,
    action: Action,
    kind: Kind,
    eligible: Bool,
    inputs: List(Field),
    attributes: List(Field),
    returns: Result(t.Shape, Nil),
    nullable_return: Bool,
    unit_return: Bool,
  )
}

pub type Effect(m, context) {
  Effect(
    label: String,
    lift: binding.Mono,
    lower: binding.Mono,
    handle: fn(v.Value(m, context), Options) -> v.Value(m, context),
  )
}

pub fn build(descriptor: Descriptor) -> Result(Effect(m, context), Nil) {
  use _ <- result.try(case descriptor.eligible {
    True -> Ok(Nil)
    False -> Error(Nil)
  })
  use inputs <- result.try(representable(descriptor.inputs))
  let attributes =
    list.filter(descriptor.attributes, fn(field) { result.is_ok(field.shape) })
  let record = record_type(attributes)
  use #(reply, encode) <- result.try(
    case descriptor.kind, descriptor.unit_return {
      Read, _ ->
        Ok(
          #(iso.List(record), fn(value) {
            v.LinkedList(
              list.map(host_list(value), encode_record(attributes, _)),
            )
          }),
        )
      Create, _ | Update, _ -> Ok(#(record, encode_record(attributes, _)))
      Destroy, _ | Generic, True ->
        Ok(#(t.unit(), fn(_) { v.Record(dict.new()) }))
      Generic, False -> {
        use shape <- result.try(descriptor.returns)
        Ok(
          #(t.type_(shape, descriptor.nullable_return), t.encode(
            shape,
            descriptor.nullable_return,
            _,
          )),
        )
      }
    },
  )
  Ok(
    Effect(
      label: descriptor.label,
      lift: record_type(inputs),
      lower: iso.result(reply, iso.String),
      handle: fn(lift, opts) {
        let assert v.Record(fields) = lift
        let params =
          list.filter_map(inputs, fn(field) {
            let assert Ok(value) = dict.get(fields, field.name)
            case !field.required && t.absent(value) {
              True -> Error(Nil)
              False -> {
                let assert Ok(shape) = field.shape
                Ok(#(field.key, t.decode(shape, !field.required, value)))
              }
            }
          })
        case call(descriptor, params, opts) {
          Ok(value) -> v.Tagged("Ok", encode(value))
          Error(message) -> v.Tagged("Error", v.String(message))
        }
      },
    ),
  )
}

fn representable(fields: List(Field)) -> Result(List(Field), Nil) {
  list.try_fold(fields, [], fn(found, field) {
    case field.shape, field.required {
      Ok(_), _ -> Ok([field, ..found])
      Error(_), False -> Ok(found)
      Error(_), True -> Error(Nil)
    }
  })
  |> result.map(list.reverse)
}

fn record_type(fields: List(Field)) {
  iso.record(
    list.map(fields, fn(field) {
      let assert Ok(shape) = field.shape
      #(field.name, t.type_(shape, !field.required))
    }),
  )
}

fn encode_record(fields: List(Field), value: t.HostValue) {
  v.Record(
    dict.from_list(
      list.map(fields, fn(field) {
        let assert Ok(shape) = field.shape
        #(
          field.name,
          t.encode(shape, !field.required, host_field(value, field.key)),
        )
      }),
    ),
  )
}

@external(erlang, "Elixir.AshEyg.Native", "call")
fn call(
  descriptor: Descriptor,
  params: List(#(t.Key, t.HostValue)),
  opts: Options,
) -> Result(t.HostValue, String)

@external(erlang, "Elixir.AshEyg.Native", "values")
fn host_list(value: t.HostValue) -> List(t.HostValue)

@external(erlang, "Elixir.AshEyg.Native", "field")
fn host_field(value: t.HostValue, key: t.Key) -> t.HostValue
