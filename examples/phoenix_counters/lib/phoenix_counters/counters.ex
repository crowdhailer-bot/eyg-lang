defmodule PhoenixCounters.Counters do
  @moduledoc """
  Named counters that add one to their value on every tick.
  Every counter is a child of a dynamic supervisor.
  """

  alias PhoenixCounters.Counters.Counter

  @supervisor PhoenixCounters.Counters.Supervisor
  @registry PhoenixCounters.Counters.Registry

  def child_specs do
    [
      {Registry, keys: :unique, name: @registry},
      {DynamicSupervisor, name: @supervisor}
    ]
  end

  def start_counter(name) do
    case DynamicSupervisor.start_child(@supervisor, {Counter, name: name, via: via(name)}) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> {:error, :already_started}
    end
  end

  @doc "Tick every `seconds` seconds."
  def set_tick_rate(_name, seconds) when not is_integer(seconds) or seconds < 1,
    do: {:error, :invalid_rate}

  def set_tick_rate(name, seconds),
    do: with_counter(name, &GenServer.call(&1, {:set_tick_rate, seconds}))

  def get_value(name), do: with_counter(name, &GenServer.call(&1, :get_value))

  def shutdown(name),
    do: with_counter(name, &DynamicSupervisor.terminate_child(@supervisor, &1))

  @doc "Every counter with its current state, ordered by name."
  def list do
    Registry.select(@registry, [{{:"$1", :"$2", :_}, [], [{{:"$1", :"$2"}}]}])
    |> Enum.flat_map(fn {_name, pid} ->
      try do
        [GenServer.call(pid, :state)]
      catch
        :exit, _ -> []
      end
    end)
    |> Enum.sort_by(& &1.name)
  end

  defp via(name), do: {:via, Registry, {@registry, name}}

  defp with_counter(name, fun) do
    case Registry.lookup(@registry, name) do
      [{pid, _}] -> fun.(pid)
      [] -> {:error, :not_found}
    end
  end
end
