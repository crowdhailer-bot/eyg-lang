import eyg/interpreter/value as v
import gleam/dict
import overlay/policy

pub fn field_name_test() {
  assert policy.field_name("ReadFile") == "read_file"
  assert policy.field_name("CWD") == "cwd"
  assert policy.field_name("DecodeJSON") == "decode_json"
  assert policy.field_name("EYGParse") == "eyg_parse"
  assert policy.field_name("StandardOut") == "standard_out"
  assert policy.field_name("Now") == "now"
}

const labels = ["ReadFile", "WriteFile", "Hash"]

fn record(fields) -> v.Value(Nil, Nil) {
  v.Record(dict.from_list(fields))
}

pub fn decode_known_fields_test() {
  let assert Ok(p) =
    policy.decode(record([#("read_file", v.Integer(1))]), labels)
  assert policy.rule(p, "ReadFile") == policy.Apply(v.Integer(1))
  assert policy.rule(p, "WriteFile") == policy.Refused
  assert policy.rule(p, "Hash") == policy.Unrestricted
}

pub fn decode_unknown_field_test() {
  assert policy.decode(record([#("read_files", v.unit())]), labels)
    == Error(
      "unknown policy field `read_files`, expected one of: read_file, write_file, hash",
    )
}

pub fn decode_not_record_test() {
  let assert Error(_) = policy.decode(v.Integer(1), labels)
}

pub fn decision_test() {
  let value: v.Value(Nil, Nil) = v.Tagged("Pass", v.Integer(1))
  assert policy.decision(value) == Ok(policy.Pass(v.Integer(1)))
  let value: v.Value(Nil, Nil) = v.Tagged("Mock", v.Integer(2))
  assert policy.decision(value) == Ok(policy.Mock(v.Integer(2)))
  let value: v.Value(Nil, Nil) = v.Tagged("Allow", v.unit())
  let assert Error(_) = policy.decision(value)
}
