defmodule PhoenixCounters.Scripts do
  @moduledoc """
  Owns the package cache for scripts run by this application.

  Every check and run goes through this process and keeps the cache it returns,
  so a package is fetched once and only results reach the LiveView.
  """
  use GenServer

  alias PhoenixCounters.Counters.Eyg

  def start_link(opts), do: GenServer.start_link(__MODULE__, :ok, opts)

  def check(server \\ __MODULE__, source), do: GenServer.call(server, {:check, source}, :infinity)

  def run(server \\ __MODULE__, source), do: GenServer.call(server, {:run, source}, :infinity)

  @impl true
  def init(:ok), do: {:ok, :eyg@hub@cache.empty()}

  @impl true
  def handle_call({:check, source}, _from, cache) do
    {result, cache} = Eyg.check(source, cache)
    {:reply, result, cache}
  end

  def handle_call({:run, source}, _from, cache) do
    {result, cache} = Eyg.run(source, cache)
    {:reply, result, cache}
  end
end
