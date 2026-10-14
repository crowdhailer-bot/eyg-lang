defmodule PhoenixCounters.Counters.Packages do
  @moduledoc "Application configuration and callbacks for the Gleam package loader."

  def loader do
    hub = Application.get_env(:phoenix_counters, :hub, "https://eyg.run")
    {:loader, ^hub, fetch, hash} = :eyg@embedding@beam.loader(hub)
    {:loader, hub, Application.get_env(:phoenix_counters, :package_fetch, fetch), hash}
  end

  def prepare(tree, cache),
    do: :eyg@embedding@packages.prepare(tree, cache, loader()).(&Function.identity/1)
end
