import eyg/interpreter/value
import gleam/string
import overlay/eval/pure
import overlay/llm/chat

pub fn computes_fibonacci_test() {
  let code =
    "let sum = !fix((self, n, a, b, total) -> {
    match !int_compare(n, 0) {
      Eq(_) -> { total }
      | (_) -> { self(!int_subtract(n, 1), b, !int_add(a, b), !int_add(total, a)) }
    }
  })
  sum(20, 1, 1, 0)"
  assert Ok(Nil) == pure.check(code, value.Integer(17_710))
}

pub fn rejects_wrong_value_test() {
  let assert Error(_) = pure.check("10945", value.Integer(17_710))
  let assert Error(_) = pure.check("\"17710\"", value.Integer(17_710))
}

pub fn rejects_effect_before_execution_test() {
  let assert Error(reason) =
    pure.evaluate("let _ = perform Print(\"hello\") 17710")
  assert string.contains(reason, "Print")
  let assert Error(_) = pure.evaluate("perform MadeUp({})")
}

pub fn rejects_invalid_programs_test() {
  let assert Error(_) = pure.evaluate("let =")
  let assert Error(_) = pure.evaluate("!int_add(1, \"two\")")
  let assert Error(_) = pure.evaluate("@standard")
}

pub fn context_is_in_scope_test() {
  assert Ok(value.unit()) == pure.evaluate("context")
}

pub fn a_prose_answer_does_not_pass_test() {
  let assert Error(_) = pure.program(chat.Completion("", "17710", []))
}
