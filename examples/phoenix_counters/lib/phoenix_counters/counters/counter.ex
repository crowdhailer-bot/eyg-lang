defmodule PhoenixCounters.Counters.Counter do
  use GenServer, restart: :transient

  @default_seconds 10

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts[:name], name: opts[:via])
  end

  @impl true
  def init(name) do
    {:ok, schedule(%{name: name, value: 0, seconds: @default_seconds, timer: nil})}
  end

  @impl true
  def handle_call(:get_value, _from, state), do: {:reply, {:ok, state.value}, state}
  def handle_call(:state, _from, state), do: {:reply, Map.delete(state, :timer), state}

  def handle_call({:set_tick_rate, seconds}, _from, state) do
    Process.cancel_timer(state.timer)
    {:reply, :ok, schedule(%{state | seconds: seconds})}
  end

  @impl true
  def handle_info(:tick, state), do: {:noreply, schedule(%{state | value: state.value + 1})}

  defp schedule(state) do
    %{state | timer: Process.send_after(self(), :tick, state.seconds * 1000)}
  end
end
