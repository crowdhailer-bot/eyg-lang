defmodule Mix.Tasks.AshEyg.Effects do
  @shortdoc "List this application's EYG effects and their types"
  use Mix.Task
  @impl true
  def run(_args) do
    AshEyg.Mix.start()
    Mix.shell().info(:ash_eyg@tools.effects())
  end
end
