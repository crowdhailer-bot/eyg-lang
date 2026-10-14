import eyg/embedding/packages
import eyg/hub/cache
import eyg/interpreter/state
import gleam/erlang/process
import gleam/erlang/reference
import midas/effect
import phoenix_counter/domain

@external(erlang, "Elixir.PhoenixCounters.TestNative", "fixture")
pub fn fixture(fetch: effect.Fetch(t)) -> Nil

@external(erlang, "Elixir.PhoenixCounters.TestNative", "clear_fixture")
pub fn clear_fixture() -> Nil

@external(erlang, "Elixir.PhoenixCounters.Counters.Packages", "loader")
pub fn loader() -> packages.Loader(t)

@external(erlang, "Elixir.PhoenixCounters.Counters.Eyg", "check")
pub fn check(
  source: String,
  cache: cache.Cache(#(Int, Int)),
) -> #(Result(String, String), cache.Cache(#(Int, Int)))

@external(erlang, "Elixir.PhoenixCounters.Counters.Eyg", "run")
pub fn run(
  source: String,
  cache: cache.Cache(#(Int, Int)),
) -> #(Result(state.Value(#(Int, Int)), String), cache.Cache(#(Int, Int)))

@external(erlang, "Elixir.PhoenixCounters.TestNative", "scripts")
pub fn scripts() -> Result(process.Pid, Nil)

@external(erlang, "Elixir.PhoenixCounters.Scripts", "check")
pub fn check_session(pid: process.Pid, source: String) -> Result(String, String)

@external(erlang, "Elixir.PhoenixCounters.Scripts", "run")
pub fn run_session(
  pid: process.Pid,
  source: String,
) -> Result(state.Value(#(Int, Int)), String)

@external(erlang, "Elixir.PhoenixCounters.TestNative", "stop")
pub fn stop(pid: process.Pid) -> Nil

@external(erlang, "Elixir.PhoenixCounters.TestNative", "timer")
pub fn timer(
  name: String,
) -> Result(#(process.Pid, reference.Reference), domain.Failure)

pub type Tick {
  Tick
}

pub type TimerMessage {
  Timeout(reference.Reference, Tick)
}

@external(erlang, "erlang", "send")
pub fn send_timer(pid: process.Pid, message: TimerMessage) -> TimerMessage
