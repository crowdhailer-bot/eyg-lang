import gleam/float
import tracing/eval_slides as deck

pub fn illustrative_reliability_is_independent_attempts_not_a_sample_estimate_test() {
  let #(one, any, all) = deck.probabilities(80, 5)
  assert one == 0.8
  assert float.absolute_value(any -. 0.99968) <. 0.000001
  assert float.absolute_value(all -. 0.32768) <. 0.000001
  assert deck.probabilities(0, 5) == #(0.0, 0.0, 0.0)
  assert deck.probabilities(100, 5) == #(1.0, 1.0, 1.0)
}
