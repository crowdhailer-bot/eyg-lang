defmodule PhoenixCounters.Counters.Counter do
  use GenServer, restart: :transient

  @model :phoenix_counter@model

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts[:name], name: opts[:via])
  end

  @impl true
  def init(name) do
    {:ok, schedule(%{model: @model.new(name), timer: nil})}
  end

  @impl true
  def handle_call(:get_value, _from, state), do: {:reply, {:ok, @model.value(state.model)}, state}

  def handle_call(:state, _from, state) do
    reply = %{
      name: @model.name(state.model),
      value: @model.value(state.model),
      seconds: @model.seconds(state.model)
    }

    {:reply, reply, state}
  end

  def handle_call({:set_tick_rate, seconds}, _from, state) do
    Process.cancel_timer(state.timer)
    {:reply, :ok, schedule(%{state | model: @model.with_rate(state.model, seconds)})}
  end

  @impl true
  def handle_info({:timeout, timer, :tick}, %{timer: timer} = state),
    do: {:noreply, schedule(%{state | model: @model.tick(state.model)})}

  def handle_info(_message, state), do: {:noreply, state}

  defp schedule(state) do
    %{state | timer: :erlang.start_timer(@model.seconds(state.model) * 1000, self(), :tick)}
  end
end
