defmodule PhoenixCounters.CountersTest do
  use ExUnit.Case

  alias PhoenixCounters.Counters

  test "a counter ticks at its rate until it is shut down" do
    assert :ok = Counters.start_counter("ticker")
    assert {:error, :already_started} = Counters.start_counter("ticker")
    assert {:error, :invalid_rate} = Counters.set_tick_rate("ticker", 0)
    assert :ok = Counters.set_tick_rate("ticker", 1)
    Process.sleep(1100)
    assert {:ok, 1} = Counters.get_value("ticker")
    assert :ok = Counters.shutdown("ticker")
    assert {:error, :not_found} = Counters.get_value("ticker")
  end
end
