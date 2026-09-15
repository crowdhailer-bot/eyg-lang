import eyg/compiler/support
import eyg/parser
import gleam/list
import gleam/string
import soundness/property

fn agrees(source) {
  let assert Ok(#(source, _)) = parser.from_string(source)
  let assert Ok(value) = property.evaluate(source, 100_000)
  let expected = support.canonical(value)
  let failures =
    list.filter_map(support.configs(), fn(config) {
      case support.run(source, config, []) {
        Ok(got) if got == expected -> Error(Nil)
        result -> Ok(config.name <> " " <> string.inspect(result))
      }
    })
  assert [] == failures
    as { "expected " <> expected <> "\n" <> string.join(failures, "\n") }
}

pub fn nested_handlers_test() {
  agrees(
    "handle Ask((_, resume) -> { resume(1) }, (_) -> {
      handle Log((_, resume) -> { resume({}) }, (_) -> {
        let _ = perform Log(\"a\")
        !int_add(perform Ask({}), perform Ask({}))
      })
    })",
  )
}

pub fn handler_that_does_not_resume_test() {
  agrees(
    "handle Fail((reason, _) -> { Error(reason) }, (_) -> {
      let _ = perform Fail(\"no\")
      Ok(1)
    })",
  )
}

pub fn multiple_resumption_test() {
  agrees(
    "handle Flip((_, resume) -> { !list_fold(resume(True({})), resume(False({})), (x, acc) -> { [x, ..acc] }) }, (_) -> {
      let a = perform Flip({})
      let b = perform Flip({})
      [{a: a, b: b}]
    })",
  )
}

pub fn effectful_fold_test() {
  agrees(
    "handle Ask((x, resume) -> { resume(!int_multiply(x, 2)) }, (_) -> {
      !list_fold([1, 2, 3], 0, (item, acc) -> { !int_add(acc, perform Ask(item)) })
    })",
  )
}

pub fn clause_performs_outer_effect_test() {
  agrees(
    "handle Ask((_, resume) -> { resume(10) }, (_) -> {
      handle Ask((_, resume) -> { resume(!int_add(perform Ask({}), 1)) }, (_) -> {
        perform Ask({})
      })
    })",
  )
}

// Section 2.12.1, a resumption returned from its handler and resumed under a
// different reader handler must see the new handler.
pub fn non_scoped_resumption_test() {
  agrees(
    "let r = handle Ask((_, resume) -> { resume(1) }, (_) -> {
      handle Evil((_, resume) -> { Suspended(resume) }, (_) -> {
        let _ = perform Ask({})
        let _ = perform Evil({})
        Done(perform Ask({}))
      })
    })
    match r {
      Suspended(k) -> { handle Ask((_, resume) -> { resume(2) }, (_) -> { k({}) }) }
      Done(x) -> { Done(x) }
    }",
  )
}

// Section 2.12.2, as above but from inside a tail resumptive clause.
// Resuming must find the evidence for Tl again rather than reuse the old one.
pub fn non_scoped_resumption_in_tail_resumptive_clause_test() {
  agrees(
    "let r = handle Ask((_, resume) -> { resume(1) }, (_) -> {
      handle Evil((_, resume) -> { Suspended(resume) }, (_) -> {
        handle Tl((_, resume) -> {
          let _ = perform Ask({})
          let _ = perform Evil({})
          resume(perform Ask({}))
        }, (_) -> { Done(perform Tl({})) })
      })
    })
    match r {
      Suspended(k) -> { handle Ask((_, resume) -> { resume(2) }, (_) -> { k({}) }) }
      Done(x) -> { Done(x) }
    }",
  )
}

pub fn recursion_test() {
  agrees(
    "let count = !fix((count, n) -> {
      match !int_compare(n, 0) {
        Eq(_) -> { 0 }
        | (_) -> { !int_add(1, count(!int_subtract(n, 1))) }
      }
    })
    count(100)",
  )
}

pub fn integer_precision_test() {
  agrees("!int_add(9007199254740990, 1)")
  list.each(
    [
      "!int_add(9007199254740991, 1)",
      "!int_subtract(-9007199254740991, 1)",
      "!int_multiply(9007199254740991, 2)",
      "!int_parse(\"9007199254740992\")",
    ],
    fn(text) {
      let assert Ok(#(source, _)) = parser.from_string(text)
      let assert Error(_) = property.evaluate(source, 100_000)
      list.each(support.configs(), fn(config) {
        assert support.run(source, config, [])
          == Error("unrepresentable integer")
      })
    },
  )
}

pub fn effectful_recursion_test() {
  agrees(
    "handle Tick((_, resume) -> { resume({}) }, (_) -> {
      let loop = !fix((loop, n) -> {
        match !int_compare(n, 0) {
          Eq(_) -> { 0 }
          | (_) -> {
            let _ = perform Tick({})
            !int_add(1, loop(!int_subtract(n, 1)))
          }
        }
      })
      loop(100)
    })",
  )
}
