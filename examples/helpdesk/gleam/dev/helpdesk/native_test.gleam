import eyg/interpreter/state
import midas/effect

pub type AshError

@external(erlang, "Elixir.Helpdesk.TestNative", "triage_check")
pub fn triage_check(source: String) -> Result(String, String)

@external(erlang, "Elixir.Helpdesk.TestNative", "triage_run")
pub fn triage_run(source: String) -> Result(state.Value(#(Int, Int)), String)

@external(erlang, "Elixir.Helpdesk.TestNative", "seed")
pub fn seed() -> #(String, String)

@external(erlang, "Elixir.Helpdesk.TestNative", "assigned")
pub fn assigned(id: String) -> String

@external(erlang, "Elixir.Helpdesk.TestNative", "script")
pub fn script(source: String) -> Result(String, AshError)

@external(erlang, "Elixir.Helpdesk.TestNative", "invalid_argument")
pub fn invalid_argument(error: AshError) -> #(String, String)

@external(erlang, "Elixir.Helpdesk.TestNative", "fixture")
pub fn fixture(fetch: effect.Fetch(t)) -> Nil

@external(erlang, "Elixir.Helpdesk.TestNative", "clear_fixture")
pub fn clear_fixture() -> Nil
