pub type Failure {
  AlreadyStarted
  NotFound
  InvalidRate
}

@external(erlang, "counters_bridge", "start_counter")
pub fn start(name: String) -> Result(Nil, Failure)

@external(erlang, "counters_bridge", "set_tick_rate")
pub fn rate(name: String, seconds: Int) -> Result(Nil, Failure)

@external(erlang, "counters_bridge", "get_value")
pub fn value(name: String) -> Result(Int, Failure)

@external(erlang, "counters_bridge", "shutdown")
pub fn shutdown(name: String) -> Result(Nil, Failure)

pub fn message(reason) {
  case reason {
    AlreadyStarted -> "counter already started"
    NotFound -> "counter not found"
    InvalidRate -> "seconds must be a positive integer"
  }
}
