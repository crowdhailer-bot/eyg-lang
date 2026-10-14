import ash_eyg/runtime
import gleam/list

pub fn effects() {
  list.filter(all_effects(), fn(effect) {
    list.contains(["read", "assign"], action(effect))
  })
}

@external(erlang, "Elixir.Helpdesk.EygBridge", "effects")
fn all_effects() -> List(runtime.NativeEffect)

@external(erlang, "Elixir.Helpdesk.EygBridge", "action")
fn action(effect: runtime.NativeEffect) -> String
