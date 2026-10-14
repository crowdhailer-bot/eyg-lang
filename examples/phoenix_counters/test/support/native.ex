defmodule PhoenixCounters.TestNative do
  @moduledoc false
  def fixture(fetch) do
    Application.put_env(:phoenix_counters, :hub, "https://hub.test")
    Application.put_env(:phoenix_counters, :package_fetch, fetch)
    nil
  end

  def clear_fixture do
    Application.delete_env(:phoenix_counters, :hub)
    Application.delete_env(:phoenix_counters, :package_fetch)
    nil
  end

  def scripts, do: PhoenixCounters.Scripts.start_link([])
  def stop(pid), do: GenServer.stop(pid)

  def timer(name) do
    [{pid, _}] = Registry.lookup(PhoenixCounters.Counters.Registry, name)
    {:ok, {pid, :sys.get_state(pid).timer}}
  end
end
