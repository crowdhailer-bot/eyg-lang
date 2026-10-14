import eyg/embedding/runtime
import phoenix_counter/effects

pub fn check(source, cache, loader) {
  runtime.check(source, cache, loader, effects.types())(fn(value) { value })
}

pub fn run(source, cache, loader) {
  runtime.run(source, cache, loader, effects.types(), effects.handle)(fn(value) {
    value
  })
}
