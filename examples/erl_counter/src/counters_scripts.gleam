import counters_effects
import eyg/embedding/packages
import eyg/embedding/runtime

@external(erlang, "counters_environment", "loader")
fn loader() -> packages.Loader(t)

pub fn check(source, cache) {
  runtime.check(source, cache, loader(), counters_effects.types())(fn(value) {
    value
  })
}

pub fn run(source, cache) {
  runtime.run(
    source,
    cache,
    loader(),
    counters_effects.types(),
    counters_effects.handle,
  )(fn(value) { value })
}
