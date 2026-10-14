import ash_eyg/actions
import eyg/embedding/runtime
import gleam/list
import gleam/result

pub type NativeEffect

pub type Options

pub fn check(source, cache, loader, opts) {
  let effects = list.map(native_effects(opts), native_effect)
  runtime.check(source, cache, loader, signatures(effects))
}

pub fn run(source, cache, loader, opts) {
  let effects = list.map(native_effects(opts), native_effect)
  let host_opts = host_options(opts)
  runtime.run(source, cache, loader, signatures(effects), fn(label, lift) {
    list.find(effects, fn(effect) { effect.label == label })
    |> result.map(fn(effect) { effect.handle(lift, host_opts) })
    |> result.map_error(fn(_) { "Effect was not granted: " <> label })
  })
}

pub fn signatures(effects: List(actions.Effect(m, context))) {
  list.map(effects, fn(effect) { #(effect.label, #(effect.lift, effect.lower)) })
}

@external(erlang, "Elixir.AshEyg.Native", "effects")
fn native_effects(opts: Options) -> List(NativeEffect)

@external(erlang, "Elixir.AshEyg.Native", "effect")
fn native_effect(effect: NativeEffect) -> actions.Effect(m, context)

@external(erlang, "Elixir.AshEyg.Native", "options")
fn host_options(opts: Options) -> actions.Options
