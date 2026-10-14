defmodule PhoenixCounters.Counters.Bridge do
  @moduledoc false
  alias PhoenixCounters.Counters
  def start(name), do: unit(Counters.start_counter(name))
  def rate(name, seconds), do: unit(Counters.set_tick_rate(name, seconds))
  def value(name), do: Counters.get_value(name)
  def shutdown(name), do: unit(Counters.shutdown(name))
  defp unit(:ok), do: {:ok, nil}
  defp unit(error), do: error
end
