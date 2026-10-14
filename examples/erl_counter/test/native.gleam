import counters_domain
import eyg/interpreter/state
import eyg/ir/tree as ir
import gleam/erlang/process
import gleam/erlang/reference
import midas/effect

@external(erlang, "counters_test_bridge", "start_app")
pub fn start_app() -> Nil

@external(erlang, "counters_test_bridge", "set_fixture")
pub fn fixture(fetch: effect.Fetch(t)) -> Nil

@external(erlang, "counters_test_bridge", "clear_fixture")
pub fn clear_fixture() -> Nil

@external(erlang, "counters_session", "start_link")
pub fn session() -> Result(process.Pid, Nil)

@external(erlang, "counters_session", "check")
pub fn check(session: process.Pid, source: String) -> Result(String, String)

@external(erlang, "counters_session", "run")
pub fn run(
  session: process.Pid,
  source: String,
) -> Result(state.Value(#(Int, Int)), String)

@external(erlang, "counters_session", "cached")
pub fn cached(session: process.Pid, reference: ir.Reference) -> Bool

@external(erlang, "counters_test_bridge", "stop_session")
pub fn stop(session: process.Pid) -> Nil

@external(erlang, "counters_test_bridge", "timer")
pub fn timer(
  name: String,
) -> Result(#(process.Pid, reference.Reference), counters_domain.Failure)

pub type Tick {
  Tick
}

pub type TimerMessage {
  Timeout(reference.Reference, Tick)
}

@external(erlang, "erlang", "send")
pub fn send_timer(pid: process.Pid, message: TimerMessage) -> TimerMessage
