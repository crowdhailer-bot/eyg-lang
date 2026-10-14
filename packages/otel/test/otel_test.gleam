import gleam/option.{None, Some}
import gleeunit
import otel
import otel/clock

pub fn main() {
  gleeunit.main()
}

pub fn epoch_nanoseconds_remain_exact_test() {
  let assert Ok(time) = clock.decode("1791912345123456789")
  assert time == clock.Time(1_791_912_345, 123_456_789)
  assert clock.encode(time) == "1791912345123456789"
  assert clock.difference(clock.Time(1_791_912_346, 5), time) == 876_543_216
}

pub fn exporter_configuration_is_pure_test() {
  let exporter =
    otel.configure(
      [
        #("OTEL_EXPORTER_OTLP_ENDPOINT", "http://localhost:4318///"),
        #("OTEL_SERVICE_NAME", "demo"),
      ],
      "default",
      "scope",
      [],
    )
  assert exporter.endpoint == Some("http://localhost:4318/v1/traces")
  assert exporter.service == "demo"
  let disabled =
    otel.configure(
      [
        #("OTEL_EXPORTER_OTLP_TRACES_ENDPOINT", "http://localhost/custom"),
        #("OTEL_SDK_DISABLED", "TRUE"),
      ],
      "default",
      "scope",
      [],
    )
  assert disabled.endpoint == None
  assert disabled.disabled
}

pub fn partial_acceptance_and_invalid_responses_test() {
  assert otel.acceptance("") == Ok(Nil)
  assert otel.acceptance("{}") == Ok(Nil)
  assert otel.acceptance("{\"partialSuccess\":{\"rejectedSpans\":\"1\"}}")
    == Error("collector partially accepted traces: 1")
  let assert Error(_) = otel.acceptance("invalid")
}
