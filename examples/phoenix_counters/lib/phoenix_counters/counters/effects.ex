defmodule PhoenixCounters.Counters.Effects do
  @moduledoc "Compatibility entry points; effect types and replies are Gleam."
  def types, do: :phoenix_counter@effects.types()

  def handle(label, value) do
    {:ok, reply} = :phoenix_counter@effects.handle(label, value)
    reply
  end
end
