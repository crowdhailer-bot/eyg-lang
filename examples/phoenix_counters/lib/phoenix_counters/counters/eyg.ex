defmodule PhoenixCounters.Counters.Eyg do
  @moduledoc "Native entry points to the shared Gleam EYG runtime."
  alias PhoenixCounters.Counters.Packages

  def parse(source) do
    case :eyg@embedding@runtime.parse(source) do
      {:ok, nil} -> :ok
      error -> error
    end
  end

  def check(source, cache), do: :phoenix_counter@scripts.check(source, cache, Packages.loader())
  def run(source, cache), do: :phoenix_counter@scripts.run(source, cache, Packages.loader())
  def inspect_value(value), do: :eyg@embedding@runtime.inspect(value)
end
