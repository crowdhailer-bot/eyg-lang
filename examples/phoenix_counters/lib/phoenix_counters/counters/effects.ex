defmodule PhoenixCounters.Counters.Effects do
  @moduledoc """
  EYG effects for the counters API.
  Each effect has the type of the value lifted from a program and the type
  of the reply, then a clause in `handle/2` that implements it.
  """

  alias PhoenixCounters.Counters

  @type_ :eyg@analysis@type_@isomorphic
  @unit {:record, :empty}

  def types do
    reply = @type_.result(@unit, :string)

    [
      {"StartCounter", {:string, reply}},
      {"SetTickRate", {@type_.record([{"name", :string}, {"seconds", :integer}]), reply}},
      {"GetValue", {:string, @type_.result(:integer, :string)}},
      {"Shutdown", {:string, reply}}
    ]
  end

  def handle("StartCounter", {:string, name}), do: reply(name, Counters.start_counter(name))

  def handle(
        "SetTickRate",
        {:record, %{"name" => {:string, name}, "seconds" => {:integer, seconds}}}
      ),
      do: reply(name, Counters.set_tick_rate(name, seconds))

  def handle("GetValue", {:string, name}), do: reply(name, Counters.get_value(name))
  def handle("Shutdown", {:string, name}), do: reply(name, Counters.shutdown(name))

  defp reply(_name, :ok), do: {:tagged, "Ok", {:record, %{}}}
  defp reply(_name, {:ok, value}), do: {:tagged, "Ok", {:integer, value}}
  defp reply(name, {:error, reason}), do: {:tagged, "Error", {:string, message(name, reason)}}

  defp message(name, :already_started), do: "counter #{name} is already started"
  defp message(name, :not_found), do: "no counter named #{name}"
  defp message(_name, :invalid_rate), do: "seconds must be a positive integer"
end
