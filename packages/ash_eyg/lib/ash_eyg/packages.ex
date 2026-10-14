defmodule AshEyg.Packages do
  @moduledoc "HTTP/configuration bridge for the shared Gleam package loader."
  def loader do
    hub = Application.get_env(:ash_eyg, :hub, "https://eyg.run")
    {:loader, ^hub, fetch, hash} = :eyg@embedding@beam.loader(hub)
    {:loader, hub, Application.get_env(:ash_eyg, :package_fetch, fetch), hash}
  end

  def prepare(tree, cache),
    do: :eyg@embedding@packages.prepare(tree, cache, loader()).(&Function.identity/1)
end
