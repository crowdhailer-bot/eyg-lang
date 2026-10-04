defmodule AshEyg.Session do
  @moduledoc """
  A process that owns a package cache for an application's scripts.

  Every check and run goes through the session and it keeps the cache that comes back,
  so a package is fetched once. Only results leave the process.

  Add it to your application's supervision tree.

      children = [{AshEyg.Session, name: Helpdesk.Scripts}]

      AshEyg.Session.run(Helpdesk.Scripts, source, effects: effects, actor: actor)
  """
  use GenServer

  def start_link(opts), do: GenServer.start_link(__MODULE__, :ok, opts)

  @doc "As `AshEyg.check/3`, with the session's cache."
  def check(session, source, opts), do: GenServer.call(session, {:check, source, opts}, :infinity)

  @doc "As `AshEyg.run/3`, with the session's cache. Effects run in the session process."
  def run(session, source, opts), do: GenServer.call(session, {:run, source, opts}, :infinity)

  @impl true
  def init(:ok), do: {:ok, AshEyg.empty_cache()}

  @impl true
  def handle_call({:check, source, opts}, _from, cache) do
    {result, cache} = AshEyg.check(source, cache, opts)
    {:reply, result, cache}
  end

  def handle_call({:run, source, opts}, _from, cache) do
    {result, cache} = AshEyg.run(source, cache, opts)
    {:reply, result, cache}
  end
end
