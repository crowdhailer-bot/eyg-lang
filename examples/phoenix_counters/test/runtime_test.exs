defmodule PhoenixCounters.RuntimeTest do
  use ExUnit.Case
  @checks :phoenix_counter@runtime_checks
  test "Gleam loading and reuse", do: @checks.loading_and_reuse()
  test "Gleam checks before effects", do: @checks.no_fetch_and_no_early_effects()
  test "Gleam failed batch rollback", do: @checks.failed_batch_preserves_cache()
  test "Gleam session cache ownership", do: @checks.scripts_process_owns_cache()
  test "Gleam stale timers and domain errors", do: @checks.cancelled_ticks_and_domain_errors()
end
