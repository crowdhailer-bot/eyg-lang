//// Programs built from the type rules, see the soundness package, must
//// evaluate to the same value when compiled as when interpreted.

import eyg/compiler/support
import gleam/int
import gleam/list
import gleam/string
import soundness/generate_typed
import soundness/print
import soundness/property
import soundness/random

const fuel = 4000

pub fn typed_programs_agree_with_interpreter_test() {
  let config = generate_typed.everything()
  let failures =
    list.flat_map([10, 20, 35], fn(size) {
      list.flat_map(seeds(1, 400), fn(seed) {
        let #(source, _type, _) =
          generate_typed.program(random.seed(seed), config, size)
        case property.evaluate(source, fuel) {
          Ok(value) -> {
            let expected = support.canonical(value)
            list.filter_map(support.configs(), fn(c) {
              case support.run(source, c, []) {
                Ok(got) if got == expected -> Error(Nil)
                result ->
                  Ok(
                    string.concat([
                      c.name,
                      " seed ",
                      int.to_string(seed),
                      " size ",
                      int.to_string(size),
                      " expected ",
                      expected,
                      " got ",
                      string.inspect(result),
                      "\n  ",
                      print.source(source),
                    ]),
                  )
              }
            })
          }
          Error(_) -> []
        }
      })
    })
  assert [] == failures as string.join(list.take(failures, 10), "\n")
}

fn seeds(from, count) {
  list.repeat(Nil, count) |> list.index_map(fn(_, i) { from + i })
}
