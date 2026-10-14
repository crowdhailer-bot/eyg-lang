pub opaque type State {
  State(name: String, value: Int, seconds: Int)
}

pub fn new(name) {
  State(name, 0, 10)
}

pub fn tick(state: State) {
  State(..state, value: state.value + 1)
}

pub fn with_rate(state: State, seconds) {
  State(..state, seconds:)
}

pub fn name(state: State) {
  state.name
}

pub fn value(state: State) {
  state.value
}

pub fn seconds(state: State) {
  state.seconds
}
