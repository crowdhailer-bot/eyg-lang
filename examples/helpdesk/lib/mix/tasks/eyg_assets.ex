defmodule Mix.Tasks.Eyg.Assets do
  use Mix.Task
  @shortdoc "Bundle the Gleam AshAdmin editor"
  @impl true
  def run(_args) do
    case System.cmd("gleam", ["run", "-m", "bundle"], cd: "browser", stderr_to_stdout: true) do
      {output, 0} -> Mix.shell().info(output)
      {output, _} -> Mix.raise(output)
    end
  end
end
