import eyg/analysis/type_/binding
import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/value as v
import gleam/dict
import gleam/option.{None, Some}
import overlay/context

fn record(fields) -> v.Value(Nil, Nil) {
  v.Record(dict.from_list(fields))
}

pub fn readme_test() {
  let value = record([#("readme", v.String("hello"))])
  assert context.provided_readme(value) == Some("hello")
  assert context.readme(value, None) == "hello"
}

pub fn no_readme_test() {
  let value = record([#("count", v.Integer(1))])
  assert context.provided_readme(value) == None
  assert context.readme(value, None) == "The context has no readme."
}

pub fn no_readme_with_type_test() {
  let value = record([#("count", v.Integer(1))])
  let type_ = binding.gen(t.record([#("count", t.Integer)]), 0, dict.new())
  assert context.readme(value, Some(type_))
    == "The context has no readme, it has type:\n{count: Integer}"
}
