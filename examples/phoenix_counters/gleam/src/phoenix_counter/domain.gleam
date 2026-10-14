pub type Failure {
  AlreadyStarted
  NotFound
  InvalidRate
}

@external(erlang, "Elixir.PhoenixCounters.Counters.Bridge", "start")
pub fn start(name: String) -> Result(Nil, Failure)

@external(erlang, "Elixir.PhoenixCounters.Counters.Bridge", "rate")
pub fn rate(name: String, seconds: Int) -> Result(Nil, Failure)

@external(erlang, "Elixir.PhoenixCounters.Counters.Bridge", "value")
pub fn value(name: String) -> Result(Int, Failure)

@external(erlang, "Elixir.PhoenixCounters.Counters.Bridge", "shutdown")
pub fn shutdown(name: String) -> Result(Nil, Failure)

pub fn message(name, reason) {
  case reason {
    AlreadyStarted -> "counter " <> name <> " is already started"
    NotFound -> "no counter named " <> name
    InvalidRate -> "seconds must be a positive integer"
  }
}
