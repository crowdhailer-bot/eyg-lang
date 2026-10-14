import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/value as v
import gleam/dict
import phoenix_counter/domain

pub fn types() {
  let reply = t.result(t.unit, t.String)
  [
    #("StartCounter", #(t.String, reply)),
    #(
      "SetTickRate",
      #(t.record([#("name", t.String), #("seconds", t.Integer)]), reply),
    ),
    #("GetValue", #(t.String, t.result(t.Integer, t.String))),
    #("Shutdown", #(t.String, reply)),
  ]
}

pub fn handle(label, lift) {
  case label, lift {
    "StartCounter", v.String(name) -> Ok(unit_reply(name, domain.start(name)))
    "SetTickRate", v.Record(fields) -> {
      case dict.get(fields, "name"), dict.get(fields, "seconds") {
        Ok(v.String(name)), Ok(v.Integer(seconds)) ->
          Ok(unit_reply(name, domain.rate(name, seconds)))
        _, _ -> Error("invalid SetTickRate input")
      }
    }
    "GetValue", v.String(name) ->
      Ok(case domain.value(name) {
        Ok(value) -> v.Tagged("Ok", v.Integer(value))
        Error(reason) -> failure(name, reason)
      })
    "Shutdown", v.String(name) -> Ok(unit_reply(name, domain.shutdown(name)))
    _, _ -> Error("unsupported counter effect or invalid input")
  }
}

fn unit_reply(name, result) {
  case result {
    Ok(_) -> v.Tagged("Ok", v.Record(dict.new()))
    Error(reason) -> failure(name, reason)
  }
}

fn failure(name, reason) {
  v.Tagged("Error", v.String(domain.message(name, reason)))
}
